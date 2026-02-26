import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/multiaddr.dart';
import 'package:dart_libp2p/core/network/stream.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/network/context.dart';
import 'package:dart_libp2p_pubsub/dart_libp2p_pubsub.dart';
import 'package:logging/logging.dart';
import '../core/sf_message.dart';
import '../core/message_types.dart';
import '../protocol/maa/access_handler.dart';
import '../protocol/sca/collection_handler.dart';
import '../protocol/sda/document_handler.dart';
import '../protocol/sfa/feed_handler.dart';
import '../protocol/mailbox_notify_protocol.dart';
import '../protocol/stream_utils.dart';
import '../registry/peer_preferences.dart';
import '../uri/ricochet_uri.dart';
import '../uri/ricochet_uri_resolver.dart';
import 'sf_client_config.dart';
import 'server_selector.dart';
import 'message_sender.dart';
import 'mailbox_manager.dart';
import 'presence_tracker.dart';
import '../presence/presence_cache.dart';
import '../presence/presence_event.dart';

export 'message_sender.dart' show SendResult;

/// High-level client for store-and-forward messaging
/// 
/// Provides easy-to-use API for sending messages with automatic routing via S&F servers
/// when recipients are offline, retrieving pending messages, and managing preferences.
class SFClient {
  static final Logger _logger = Logger('SFClient');
  
  final Host host;
  final SFClientConfig config;
  final PubSub? pubsub;
  
  late final ServerSelector _serverSelector;
  late final MessageSender _messageSender;
  late final MailboxManager _mailboxManager;
  PresenceTracker? _presenceTracker;
  
  final StreamController<SFMessage> _incomingMessagesController = 
      StreamController<SFMessage>.broadcast();
  
  final StreamController<MailboxNotification> _notificationController = 
      StreamController.broadcast();
  
  final Map<String, Subscription> _gossipSubSubscriptions = {};
  
  Timer? _autoRetrievalTimer;
  bool _isStarted = false;
  
  SFClient({
    required this.host,
    required this.config,
    this.pubsub,
  }) {
    if (!config.isValid()) {
      throw ArgumentError('Invalid client configuration');
    }
    
    _serverSelector = ServerSelector(host: host);
    _messageSender = MessageSender(
      host: host,
      config: config,
      serverSelector: _serverSelector,
    );
    _mailboxManager = MailboxManager(
      host: host,
      config: config,
    );
  }
  
  /// Access mailbox management operations
  MailboxManager get mailboxes => _mailboxManager;

  /// Register a known server address so the ServerSelector can refresh
  /// peerstore TTLs when reconnection is needed after address expiry.
  void registerServerAddress(PeerId serverId, MultiAddr addr) {
    _serverSelector.registerServerAddress(serverId, addr);
  }
  
  /// Start the client (enables auto-retrieval if configured)
  Future<void> start() async {
    if (_isStarted) {
      _logger.warning('Client already started');
      return;
    }
    
    _logger.info('Starting S&F client');
    _logger.info('Peer ID: ${host.id}');
    _logger.info('Preferred servers: ${config.preferredServers.length}');
    
    // Register private mailbox notification handler (direct P2P stream)
    registerPrivateNotificationHandler();

    // Initialize presence tracker if PubSub is available
    if (pubsub != null) {
      _presenceTracker = PresenceTracker(
        pubsub: pubsub!,
        localPeerId: host.id,
      );
      _logger.info('Presence tracker initialized');
    }

    if (config.enableAutoRetrieval) {
      startAutoRetrieval();
    }

    _isStarted = true;
  }
  
  /// Stop the client
  Future<void> stop() async {
    if (!_isStarted) return;
    
    _logger.info('Stopping S&F client');
    
    stopAutoRetrieval();
    await _presenceTracker?.dispose();
    await _incomingMessagesController.close();

    _isStarted = false;
  }
  
  /// Send a message (auto-routes via S&F if recipient offline)
  Future<SendResult> sendMessage({
    required PeerId recipient,
    required Uint8List payload,
    String? folderPath,  // Target folder (default: 'inbox')
    MessagePriority priority = MessagePriority.normal,
    Duration? expiry,
    bool persistent = false,  // Keep after reading
    bool tryDirectFirst = false, // Set to true to try direct delivery first
  }) async {
    _logger.fine('Sending message to ${recipient.toString().substring(0, 12)}... (folder: ${folderPath ?? 'inbox'})');
    
    final result = await _messageSender.sendMessage(
      recipient: recipient,
      payload: payload,
      folderPath: folderPath,
      priority: priority,
      expiry: expiry,
      persistent: persistent,
      tryDirectFirst: tryDirectFirst,
    );
    
    _logger.info('Send result: $result');
    return result;
  }
  
  /// Retrieve pending messages from S&F server
  /// 
  /// [targetPeerId] Optional: retrieve from another peer's public mailbox (default: own mailbox)
  /// [fromServer] Optional: specify which server to retrieve from
  /// [folderPath] Which folder to retrieve from (default: 'inbox')
  /// [fromSequence] Cursor position (for multi-reader mailboxes)
  /// [maxMessages] Maximum number of messages to retrieve
  /// [minPriority] Minimum priority level to retrieve
  Future<List<SFMessage>> retrieveMessages({
    PeerId? targetPeerId,  // NEW: retrieve from another peer's public mailbox
    PeerId? fromServer,
    String? folderPath,
    int? fromSequence,
    int? maxMessages,
    MessagePriority? minPriority,
  }) async {
    final effectivePeerId = targetPeerId ?? host.id;
    final isOwnMailbox = effectivePeerId == host.id;
    
    _logger.info('📥 [SFClient] retrieveMessages called');
    _logger.info('📥 [SFClient] Target peer: ${effectivePeerId.toBase58()}');
    _logger.info('📥 [SFClient] Folder: ${folderPath ?? 'inbox'}');
    _logger.info('📥 [SFClient] Own mailbox: $isOwnMailbox');
    _logger.info('📥 [SFClient] FromSeq: $fromSequence, MaxMsgs: $maxMessages');
    
    // Determine which server to query
    _logger.info('📥 [SFClient] Selecting server...');
    final serverId = fromServer ?? 
        await _serverSelector.selectServer(config.preferredServers);
    
    if (serverId == null) {
      _logger.warning('❌ [SFClient] No S&F server available for retrieval');
      return [];
    }
    
    _logger.info('✅ [SFClient] Server selected: ${serverId.toBase58()}');
    
    P2PStream? stream;  // Declare outside try
    try {
      // Open stream to server using MAA (Mail Access Agent) protocol
      _logger.info('🌐 [SFClient] Opening stream to server (MAA protocol)...');
      final context = Context();
      stream = await host.newStream(
        serverId,
        [AccessHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);
      
      _logger.info('✅ [SFClient] Stream opened successfully');
      _logger.info('📤 [SFClient] Sending retrieve request to server...');
      
      // Retrieve messages via MAA (pass targetPeerId to protocol handler)
      final response = await AccessHandler.retrieveMessages(
        stream,
        effectivePeerId,  // Request messages for this peer (could be us or another peer)
        folderPath: folderPath,
        fromSequence: fromSequence,
        maxMessages: maxMessages,
        minPriority: minPriority,
      ).timeout(config.messageTimeout);
      
      _logger.info('✅ [SFClient] Retrieved ${response.messages.length} messages from ${folderPath ?? 'inbox'}');
      
      // Protect the S&F server connection so it won't be closed by cleanup
      host.connManager.protect(serverId, 'ricochet-sf-server');
      _logger.fine('Protected connection to S&F server ${serverId.toBase58().substring(0, 12)}...');
      
      for (int i = 0; i < response.messages.length; i++) {
        final msg = response.messages[i];
        _logger.info('✅ [SFClient] Message $i: ID=${msg.messageId.substring(0, 8)}, Folder=${msg.folderPath ?? "null"}');
      }
      
      // Emit to incoming messages stream
      for (final message in response.messages) {
        _incomingMessagesController.add(message);
      }
      
      return response.messages;
      
    } on TimeoutException {
      _logger.warning('Retrieval timed out');
      return [];
    } catch (e) {
      _logger.warning('Failed to retrieve messages: $e');
      return [];
    } finally {
      // Always close the stream after use
      if (stream != null && !stream.isClosed) {
        try {
          await stream.close();
        } catch (e) {
          _logger.fine('Error closing stream: $e');
        }
      }
    }
  }
  
  /// Set preferred S&F servers (MX-like)
  Future<void> setPreferredServers(List<SFServerPreference> servers) async {
    _logger.info('Setting ${servers.length} preferred servers');
    
    // This would update the config, but since config is final, we'd need to
    // recreate the client or have a mutable preferences list
    // For now, log a warning
    _logger.warning('setPreferredServers: Consider recreating client with new config');
  }
  
  /// Query server capacity
  Future<ServerCapacity?> queryServerCapacity(PeerId serverId) async {
    _logger.fine('Querying capacity for ${serverId.toString().substring(0, 12)}...');
    
    return await _serverSelector.queryServerCapacity(serverId);
  }
  
  /// Start automatic message retrieval
  void startAutoRetrieval() {
    if (_autoRetrievalTimer != null) {
      _logger.warning('Auto-retrieval already started');
      return;
    }
    
    _logger.info('Starting auto-retrieval (interval: ${config.retrievalInterval.inSeconds}s)');
    
    _autoRetrievalTimer = Timer.periodic(config.retrievalInterval, (_) async {
      try {
        await retrieveMessages();
      } catch (e) {
        _logger.warning('Error during auto-retrieval: $e');
      }
    });
  }
  
  /// Stop automatic message retrieval
  void stopAutoRetrieval() {
    if (_autoRetrievalTimer == null) return;
    
    _logger.info('Stopping auto-retrieval');
    _autoRetrievalTimer?.cancel();
    _autoRetrievalTimer = null;
  }
  
  /// Stream of incoming messages
  Stream<SFMessage> get incomingMessages => _incomingMessagesController.stream;
  
  /// Get client statistics
  Map<String, dynamic> getStats() {
    return {
      'isStarted': _isStarted,
      'peerId': host.id.toString(),
      'preferredServers': config.preferredServers.length,
      'autoRetrievalEnabled': _autoRetrievalTimer != null,
      'messageSender': _messageSender.getStats(),
      'serverSelector': _serverSelector.getStats(),
    };
  }
  
  /// Get peer ID
  PeerId get peerId => host.id;
  
  /// Stream of mailbox notifications (both private and public/shared)
  Stream<MailboxNotification> get notifications => _notificationController.stream;
  
  /// Register handler for private mailbox direct streams
  void registerPrivateNotificationHandler() {
    host.setStreamHandler(mailboxNotifyProtocolId, (stream, remotePeer) async {
      try {
        final data = await StreamUtils.readLengthPrefixedFrame(stream);
        final json = jsonDecode(utf8.decode(data));
        final notification = MailboxNotification.fromJson(json);
        
        // CRITICAL: Include the server peer ID so retrieval uses the same server
        // that sent the notification (and has the message)
        final notificationWithServer = notification.withServerPeerId(remotePeer.toBase58());
        
        _logger.info('📬 Private notification from ${remotePeer.toBase58().substring(0, 12)}...: ${notification.mailboxPath}');
        _notificationController.add(notificationWithServer);
        
        await stream.close();
      } catch (e) {
        _logger.warning('Error handling private notification: $e');
      }
    });
    
    _logger.info('📡 Registered private notification handler');
  }
  
  /// Subscribe to GossipSub topic for public/shared mailbox
  Future<void> subscribeToMailbox(String ownerPeerId, String folderPath) async {
    if (pubsub == null) {
      _logger.warning('Cannot subscribe - PubSub not available');
      return;
    }
    
    final topic = getMailboxTopic(ownerPeerId, folderPath);
    
    if (_gossipSubSubscriptions.containsKey(topic)) {
      return; // Already subscribed
    }
    
    _logger.info('📡 Subscribing to public/shared mailbox: $topic');
    
    final subscription = pubsub!.subscribe(topic);
    _gossipSubSubscriptions[topic] = subscription;
    
    subscription.stream.listen((message) {
      try {
        final json = jsonDecode(utf8.decode(message.data));
        final notification = MailboxNotification.fromJson(json);
        
        _logger.info('📬 Public/Shared notification: ${notification.mailboxPath}');
        _notificationController.add(notification);
      } catch (e) {
        _logger.warning('Error parsing GossipSub notification: $e');
      }
    });
  }
  
  /// Unsubscribe from mailbox topic
  Future<void> unsubscribeFromMailbox(String ownerPeerId, String folderPath) async {
    final topic = getMailboxTopic(ownerPeerId, folderPath);
    final subscription = _gossipSubSubscriptions.remove(topic);
    
    if (subscription != null) {
      await subscription.cancel();
      _logger.info('📡 Unsubscribed from: $topic');
    }
  }
  
  // ============================================================================
  // IMAP-Style Message Flag Operations
  // ============================================================================
  
  /// Mark messages as delivered (sets \Seen flag)
  /// 
  /// This is the equivalent of IMAP STORE +FLAGS \Seen
  Future<MarkDeliveredAck?> markMessagesDelivered(
    List<String> messageIds, {
    PeerId? serverPeerId,
    String? folderPath,
  }) async {
    _logger.info('Marking ${messageIds.length} messages as delivered');
    
    // Select server
    final serverId = serverPeerId ?? 
        await _serverSelector.selectServer(config.preferredServers);
    
    if (serverId == null) {
      _logger.warning('No S&F server available');
      return null;
    }
    
    try {
      // Use MAA (Mail Access Agent) protocol for IMAP-style operations
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [AccessHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);
      
      final ack = await AccessHandler.markDelivered(
        stream,
        messageIds,
        folderPath: folderPath,
      ).timeout(config.messageTimeout);
      
      _logger.info('Marked ${ack.updatedCount} messages as delivered');
      return ack;
      
    } on TimeoutException {
      _logger.warning('Mark delivered timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to mark messages delivered: $e');
      return null;
    }
  }
  
  /// Update flags on a message (IMAP STORE)
  /// 
  /// [messageId] The message to update
  /// [addFlags] Flags to add (use MessageFlags constants)
  /// [removeFlags] Flags to remove
  Future<UpdateFlagsAck?> updateMessageFlags(
    String messageId, {
    PeerId? serverPeerId,
    int addFlags = 0,
    int removeFlags = 0,
  }) async {
    _logger.info('Updating flags for message $messageId: +$addFlags -$removeFlags');
    
    // Select server
    final serverId = serverPeerId ?? 
        await _serverSelector.selectServer(config.preferredServers);
    
    if (serverId == null) {
      _logger.warning('No S&F server available');
      return null;
    }
    
    try {
      // Use MAA (Mail Access Agent) protocol for IMAP-style operations
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [AccessHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);
      
      final ack = await AccessHandler.updateFlags(
        stream,
        messageId,
        addFlags: addFlags,
        removeFlags: removeFlags,
      ).timeout(config.messageTimeout);
      
      _logger.info('Updated flags: success=${ack.success}, newFlags=${ack.newFlags}');
      return ack;
      
    } on TimeoutException {
      _logger.warning('Update flags timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to update flags: $e');
      return null;
    }
  }
  
  /// Expunge messages marked with \Deleted flag (IMAP EXPUNGE)
  /// 
  /// [folderPath] Optional: expunge specific folder only (null = all folders)
  Future<ExpungeAck?> expungeMessages({
    PeerId? serverPeerId,
    String? folderPath,
  }) async {
    _logger.info('Expunging deleted messages from ${folderPath ?? 'all folders'}');
    
    // Select server
    final serverId = serverPeerId ?? 
        await _serverSelector.selectServer(config.preferredServers);
    
    if (serverId == null) {
      _logger.warning('No S&F server available');
      return null;
    }
    
    try {
      // Use MAA (Mail Access Agent) protocol for IMAP-style operations
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [AccessHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);
      
      final ack = await AccessHandler.expunge(
        stream,
        host.id,
        folderPath: folderPath,
      ).timeout(config.messageTimeout);
      
      _logger.info('Expunged ${ack.deletedCount} messages');
      return ack;
      
    } on TimeoutException {
      _logger.warning('Expunge timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to expunge: $e');
      return null;
    }
  }
  
  /// Delete messages immediately (bypasses \Deleted flag)
  /// 
  /// This is the equivalent of IMAP STORE +FLAGS \Deleted followed by EXPUNGE
  Future<DeleteMessagesAck?> deleteMessages(
    List<String> messageIds, {
    PeerId? serverPeerId,
  }) async {
    _logger.info('Deleting ${messageIds.length} messages immediately');
    
    // Select server
    final serverId = serverPeerId ?? 
        await _serverSelector.selectServer(config.preferredServers);
    
    if (serverId == null) {
      _logger.warning('No S&F server available');
      return null;
    }
    
    try {
      // Use MAA (Mail Access Agent) protocol for IMAP-style operations
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [AccessHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);
      
      final ack = await AccessHandler.deleteMessages(
        stream,
        messageIds,
      ).timeout(config.messageTimeout);
      
      _logger.info('Deleted ${ack.deletedCount} messages');
      return ack;
      
    } on TimeoutException {
      _logger.warning('Delete timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to delete messages: $e');
      return null;
    }
  }
  
  // ============================================================================
  // Document Store Operations
  // ============================================================================
  
  /// Get a document from a peer's store
  /// 
  /// [ownerPeerId] The peer who owns the document
  /// [path] Document path (e.g., "profile", "avatar")
  /// [ifNoneMatch] Optional ETag for conditional GET (returns null if unchanged)
  /// [fromServer] Optional: specify which server to retrieve from
  Future<DocumentResponse?> getDocument({
    required PeerId ownerPeerId,
    required String path,
    String? ifNoneMatch,
    PeerId? fromServer,
  }) async {
    final serverId = fromServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for document retrieval');
      return null;
    }

    dynamic stream;
    try {
      final context = Context();
      stream = await host.newStream(
        serverId,
        ['/ricochet/store/doc/1.0.0'],
        context,
      ).timeout(config.connectionTimeout);

      final response = await DocumentHandler.getDocument(
        stream,
        ownerPeerId: ownerPeerId,
        path: path,
        ifNoneMatch: ifNoneMatch,
      ).timeout(config.messageTimeout);

      await stream.close();

      _logger.info('GET document ${ownerPeerId.toBase58().substring(0, 12)}.../doc/$path: ${response.status}');
      return DocumentResponse(
        status: response.status,
        etag: response.etag,
        contentType: response.contentType,
        lastModified: response.lastModified,
        content: response.body,
      );
    } on TimeoutException {
      _logger.warning('GET document timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to GET document: $e');
      return null;
    } finally {
      if (stream != null && !stream.isClosed) {
        try {
          await stream.close();
        } catch (e) {
          _logger.fine('Error closing document stream: $e');
        }
      }
    }
  }
  
  /// Put a document to your own store
  /// 
  /// [path] Document path (e.g., "profile", "avatar")
  /// [content] Document content bytes
  /// [contentType] MIME content type
  /// [ifMatch] Optional ETag for optimistic locking
  /// [toServer] Optional: specify which server to store to
  Future<DocumentPutResponse?> putDocument({
    required String path,
    required Uint8List content,
    String contentType = 'application/json',
    String? ifMatch,
    PeerId? toServer,
  }) async {
    final serverId = toServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for document storage');
      return null;
    }
    
    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        ['/ricochet/store/doc/1.0.0'],
        context,
      ).timeout(config.connectionTimeout);
      
      final response = await DocumentHandler.putDocument(
        stream,
        ownerPeerId: host.id,  // Can only PUT to own documents
        path: path,
        content: content,
        contentType: contentType,
        ifMatch: ifMatch,
      ).timeout(config.messageTimeout);
      
      await stream.close();
      
      final created = response.status == 201;
      _logger.info('PUT document ${host.id.toBase58().substring(0, 12)}.../doc/$path: ${response.status} ${created ? "Created" : "Updated"}');
      
      return DocumentPutResponse(
        status: response.status,
        etag: response.etag,
        lastModified: response.lastModified,
        created: created,
      );
    } on TimeoutException {
      _logger.warning('PUT document timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to PUT document: $e');
      return null;
    }
  }

  /// Patch a document using JSON Merge Patch (RFC 7396)
  /// 
  /// Applies partial updates to an existing JSON document.
  /// 
  /// [path] Document path (e.g., "profile", "avatar")
  /// [patch] JSON Merge Patch object (keys with null values are removed, others are merged)
  /// [ifMatch] Optional: ETag for optimistic locking
  /// [toServer] Optional: specify which server to use
  Future<DocumentPutResponse?> patchDocument({
    required String path,
    required Map<String, dynamic> patch,
    String? ifMatch,
    PeerId? toServer,
  }) async {
    final serverId = toServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for document PATCH');
      return null;
    }
    
    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        ['/ricochet/store/doc/1.0.0'],
        context,
      ).timeout(config.connectionTimeout);
      
      final response = await DocumentHandler.patchDocument(
        stream,
        ownerPeerId: host.id,  // Can only PATCH own documents
        path: path,
        patch: patch,
        ifMatch: ifMatch,
      ).timeout(config.messageTimeout);
      
      await stream.close();
      
      if (!response.isSuccess) {
        _logger.warning('PATCH document failed with status ${response.status}: ${response.error}');
        return null;
      }
      
      _logger.info('Patched document: doc/$path');
      return DocumentPutResponse(
        status: response.status,
        etag: response.etag,
        lastModified: response.lastModified,
        created: false,  // PATCH never creates
      );
    } on TimeoutException {
      _logger.warning('PATCH document timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to PATCH document: $e');
      return null;
    }
  }
  
  /// Check if a document has changed (HEAD request)
  /// 
  /// [ownerPeerId] The peer who owns the document
  /// [path] Document path (e.g., "profile", "avatar")
  /// [fromServer] Optional: specify which server to query
  Future<DocumentMetadata?> headDocument({
    required PeerId ownerPeerId,
    required String path,
    PeerId? fromServer,
  }) async {
    final serverId = fromServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for document HEAD');
      return null;
    }
    
    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        ['/ricochet/store/doc/1.0.0'],
        context,
      ).timeout(config.connectionTimeout);
      
      final response = await DocumentHandler.headDocument(
        stream,
        ownerPeerId: ownerPeerId,
        path: path,
      ).timeout(config.messageTimeout);
      
      await stream.close();
      
      if (response.status != 200) {
        _logger.info('HEAD document ${ownerPeerId.toBase58().substring(0, 12)}.../doc/$path: ${response.status}');
        return null;
      }
      
      return DocumentMetadata(
        etag: response.etag!,
        contentType: response.contentType!,
        lastModified: response.lastModified!,
        contentLength: response.contentLength!,
      );
    } on TimeoutException {
      _logger.warning('HEAD document timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to HEAD document: $e');
      return null;
    }
  }

  /// Delete a document from your own store
  /// 
  /// [path] Document path (e.g., "profile", "avatar")
  /// [ifMatch] Optional: ETag for conditional delete (prevents accidental deletion of updated documents)
  /// [toServer] Optional: specify which server to use
  /// 
  /// Returns true if document was deleted, false if not found or error occurred
  Future<bool> deleteDocument({
    required String path,
    String? ifMatch,
    PeerId? toServer,
  }) async {
    final serverId = toServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for document DELETE');
      return false;
    }
    
    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        ['/ricochet/store/doc/1.0.0'],
        context,
      ).timeout(config.connectionTimeout);
      
      final response = await DocumentHandler.deleteDocument(
        stream,
        ownerPeerId: host.id,  // Can only DELETE own documents
        path: path,
        ifMatch: ifMatch,
      ).timeout(config.messageTimeout);
      
      await stream.close();
      
      if (response.status == 204) {
        _logger.info('Deleted document: doc/$path');
        return true;
      } else if (response.status == 404) {
        _logger.info('Document not found for deletion: doc/$path');
        return false;
      } else {
        _logger.warning('DELETE document failed with status ${response.status}: ${response.error}');
        return false;
      }
    } on TimeoutException {
      _logger.warning('DELETE document timed out');
      return false;
    } catch (e) {
      _logger.warning('Failed to DELETE document: $e');
      return false;
    }
  }

  /// List all documents for a peer
  /// 
  /// [ownerPeerId] The peer who owns the documents
  /// [pathPrefix] Optional: filter documents by path prefix (e.g., "settings/" for all settings docs)
  /// [fromServer] Optional: specify which server to query
  /// 
  /// Returns list of document metadata, or null if error occurred
  Future<List<DocumentInfo>?> listDocuments({
    required PeerId ownerPeerId,
    String pathPrefix = '',
    PeerId? fromServer,
  }) async {
    final serverId = fromServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for document LIST');
      return null;
    }
    
    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        ['/ricochet/store/doc/1.0.0'],
        context,
      ).timeout(config.connectionTimeout);
      
      final response = await DocumentHandler.listDocuments(
        stream,
        ownerPeerId: ownerPeerId,
        pathPrefix: pathPrefix,
      ).timeout(config.messageTimeout);
      
      await stream.close();
      
      if (response.status != 200) {
        _logger.warning('LIST documents failed with status ${response.status}: ${response.error}');
        return null;
      }
      
      // Parse the response body
      // Go server returns a bare JSON array, Dart server wraps in {"documents": [...]}
      final decoded = jsonDecode(utf8.decode(response.body!));
      final List<dynamic> docsList;
      if (decoded is List) {
        docsList = decoded;
      } else {
        docsList = (decoded as Map<String, dynamic>)['documents'] as List<dynamic>;
      }

      return docsList.map((doc) {
        final docMap = doc as Map<String, dynamic>;
        // Go server uses 'contentHash' and 'updatedAt' (RFC3339 string)
        // Dart server uses 'etag' and 'lastModified' (int timestamp)
        final etag = (docMap['etag'] ?? docMap['contentHash'] ?? '') as String;
        final lastModified = docMap['lastModified'] as int? ??
            (docMap['updatedAt'] != null
                ? DateTime.parse(docMap['updatedAt'] as String).millisecondsSinceEpoch
                : 0);
        return DocumentInfo(
          path: docMap['path'] as String,
          contentType: docMap['contentType'] as String,
          size: docMap['size'] as int,
          etag: etag,
          lastModified: lastModified,
        );
      }).toList();
    } on TimeoutException {
      _logger.warning('LIST documents timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to LIST documents: $e');
      return null;
    }
  }
  
  // ============================================================================
  // Directory Operations
  // ============================================================================

  /// Opt in to the server's user directory
  ///
  /// Sends a DIRECTORY/join request so the server registers this user
  /// in its browsable directory.
  Future<bool> joinDirectory({
    required String displayName,
    String? bio,
    Map<String, dynamic>? extras,
    PeerId? toServer,
  }) async {
    final serverId =
        toServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for directory join');
      return false;
    }

    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [DocumentHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);

      final response = await DocumentHandler.joinDirectory(
        stream,
        ownerPeerId: host.id,
        displayName: displayName,
        bio: bio,
        extras: extras,
      ).timeout(config.messageTimeout);

      await stream.close();

      if (response.status != 200) {
        _logger.warning('DIRECTORY join failed: ${response.status} ${response.error}');
        return false;
      }
      _logger.info('Successfully joined directory');
      return true;
    } on TimeoutException {
      _logger.warning('DIRECTORY join timed out');
      return false;
    } catch (e) {
      _logger.warning('Failed to join directory: $e');
      return false;
    }
  }

  /// Opt out of the server's user directory
  Future<bool> leaveDirectory({PeerId? toServer}) async {
    final serverId =
        toServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for directory leave');
      return false;
    }

    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [DocumentHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);

      final response = await DocumentHandler.leaveDirectory(
        stream,
        ownerPeerId: host.id,
      ).timeout(config.messageTimeout);

      await stream.close();

      // 204 No Content is the success response
      if (response.status != 204) {
        _logger.warning('DIRECTORY leave failed: ${response.status}');
        return false;
      }
      _logger.info('Successfully left directory');
      return true;
    } on TimeoutException {
      _logger.warning('DIRECTORY leave timed out');
      return false;
    } catch (e) {
      _logger.warning('Failed to leave directory: $e');
      return false;
    }
  }

  /// Browse the user directory on a server
  ///
  /// [cursor] Opaque cursor from a previous page (for pagination)
  /// [limit] Maximum entries per page (default 20, max 100)
  /// [search] Optional search string (matches display name, bio)
  /// [fromServer] Optional: specify which server to browse
  Future<DirectoryBrowseResult?> browseDirectory({
    String? cursor,
    int limit = 20,
    String? search,
    PeerId? fromServer,
  }) async {
    final serverId = fromServer ??
        await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for directory browse');
      return null;
    }

    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [DocumentHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);

      final response = await DocumentHandler.browseDirectory(
        stream,
        ownerPeerId: host.id,
        cursor: cursor,
        limit: limit,
        search: search,
      ).timeout(config.messageTimeout);

      await stream.close();

      if (response.status != 200) {
        _logger.warning('DIRECTORY browse failed: ${response.status}');
        return null;
      }

      final rawBody = utf8.decode(response.body!);
      _logger.info('DIRECTORY browse raw response: $rawBody');

      final body = jsonDecode(rawBody) as Map<String, dynamic>;
      final entries = ((body['entries'] as List?) ?? []).map((e) {
        final entry = e as Map<String, dynamic>;
        // Go server uses 'ownerPeerId', Dart server uses 'peerId'
        final peerId = (entry['peerId'] ?? entry['ownerPeerId'] ?? '') as String;
        // Go server sends timestamps as RFC3339 strings, Dart server as int ms
        final listedAt = entry['listedAt'] is int
            ? entry['listedAt'] as int
            : DateTime.parse(entry['listedAt'] as String).millisecondsSinceEpoch;
        final updatedAt = entry['updatedAt'] is int
            ? entry['updatedAt'] as int
            : DateTime.parse(entry['updatedAt'] as String).millisecondsSinceEpoch;
        return DirectoryEntryInfo(
          peerId: peerId,
          displayName: entry['displayName'] as String,
          bio: entry['bio'] as String?,
          avatarHash: entry['avatarHash'] as String?,
          listedAt: listedAt,
          updatedAt: updatedAt,
        );
      }).toList();

      // Go server has no 'totalCount' field, uses 'hasMore' instead
      final totalCount = body['totalCount'] as int? ?? entries.length;

      return DirectoryBrowseResult(
        entries: entries,
        nextCursor: body['nextCursor'] as String?,
        totalCount: totalCount,
      );
    } on TimeoutException {
      _logger.warning('DIRECTORY browse timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to browse directory: $e');
      return null;
    }
  }

  // ============================================================================
  // Feed Store Operations (SFA)
  // ============================================================================

  /// Create a new feed on your store
  Future<FeedInfo?> createFeed({
    required String path,
    required String title,
    String description = '',
    bool collaborative = false,
    PeerId? toServer,
  }) async {
    final serverId = toServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for feed creation');
      return null;
    }

    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [FeedHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);

      final response = await FeedHandler.createFeed(
        stream,
        ownerPeerId: host.id,
        path: path,
        title: title,
        description: description,
        collaborative: collaborative,
      ).timeout(config.messageTimeout);

      await stream.close();

      if (!response.isSuccess) {
        _logger.warning('CREATE feed $path: ${response.status} ${response.error}');
        return null;
      }

      final body = jsonDecode(utf8.decode(response.body!)) as Map<String, dynamic>;
      return FeedInfo(
        path: body['path'] as String,
        title: body['title'] as String,
        description: body['description'] as String? ?? '',
        currentSequence: body['currentSequence'] as int? ?? 0,
        createdAt: body['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      );
    } on TimeoutException {
      _logger.warning('CREATE feed timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to CREATE feed: $e');
      return null;
    }
  }

  /// Get feed metadata
  Future<FeedInfo?> getFeed({
    required PeerId ownerPeerId,
    required String path,
    PeerId? fromServer,
  }) async {
    final serverId = fromServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for feed retrieval');
      return null;
    }

    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [FeedHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);

      final response = await FeedHandler.getFeed(
        stream,
        ownerPeerId: ownerPeerId,
        path: path,
      ).timeout(config.messageTimeout);

      await stream.close();

      if (!response.isSuccess) {
        _logger.warning('GET feed $path: ${response.status} ${response.error}');
        return null;
      }

      final body = jsonDecode(utf8.decode(response.body!)) as Map<String, dynamic>;
      return FeedInfo(
        path: body['path'] as String? ?? path,
        title: body['title'] as String? ?? '',
        description: body['description'] as String? ?? '',
        currentSequence: body['currentSequence'] as int? ?? 0,
        lastEntryAt: body['lastEntryAt'] as int?,
        createdAt: body['createdAt'] as int? ?? 0,
      );
    } on TimeoutException {
      _logger.warning('GET feed timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to GET feed: $e');
      return null;
    }
  }

  /// Delete a feed from your store
  Future<bool> deleteFeed({
    required String path,
    PeerId? toServer,
  }) async {
    final serverId = toServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for feed deletion');
      return false;
    }

    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [FeedHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);

      final response = await FeedHandler.deleteFeed(
        stream,
        ownerPeerId: host.id,
        path: path,
      ).timeout(config.messageTimeout);

      await stream.close();
      return response.isSuccess;
    } on TimeoutException {
      _logger.warning('DELETE feed timed out');
      return false;
    } catch (e) {
      _logger.warning('Failed to DELETE feed: $e');
      return false;
    }
  }

  /// List all feeds for an owner
  Future<List<FeedInfo>?> listFeeds({
    required PeerId ownerPeerId,
    PeerId? fromServer,
  }) async {
    final serverId = fromServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for feed listing');
      return null;
    }

    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [FeedHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);

      final response = await FeedHandler.listFeeds(
        stream,
        ownerPeerId: ownerPeerId,
      ).timeout(config.messageTimeout);

      await stream.close();

      if (!response.isSuccess) {
        _logger.warning('LIST feeds: ${response.status} ${response.error}');
        return null;
      }

      final list = jsonDecode(utf8.decode(response.body!)) as List<dynamic>;
      return list.map((item) {
        final f = item as Map<String, dynamic>;
        return FeedInfo(
          path: f['path'] as String,
          title: f['title'] as String? ?? '',
          description: f['description'] as String? ?? '',
          currentSequence: f['currentSequence'] as int? ?? 0,
          lastEntryAt: f['lastEntryAt'] as int?,
          createdAt: f['createdAt'] as int? ?? 0,
        );
      }).toList();
    } on TimeoutException {
      _logger.warning('LIST feeds timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to LIST feeds: $e');
      return null;
    }
  }

  /// Append an entry to a feed
  /// [ownerPeerId] Optional: feed owner's peer ID (for collaborative feeds).
  /// If omitted, defaults to this client's own peer ID.
  Future<FeedAppendResult?> appendFeedEntry({
    required String path,
    required Uint8List content,
    String? entryType,
    PeerId? ownerPeerId,
    PeerId? toServer,
  }) async {
    final serverId = toServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for feed append');
      return null;
    }

    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [FeedHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);

      final effectiveOwner = ownerPeerId ?? host.id;
      final response = await FeedHandler.appendFeedEntry(
        stream,
        ownerPeerId: effectiveOwner,
        path: path,
        content: content,
        entryType: entryType,
      ).timeout(config.messageTimeout);

      await stream.close();

      if (!response.isSuccess) {
        _logger.warning('APPEND feed $path: ${response.status} ${response.error}');
        return null;
      }

      return FeedAppendResult(
        status: response.status,
        sequence: response.sequence ?? 0,
        etag: response.etag ?? '',
      );
    } on TimeoutException {
      _logger.warning('APPEND feed timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to APPEND feed: $e');
      return null;
    }
  }

  /// Get a single feed entry by sequence number
  Future<FeedEntry?> getFeedEntry({
    required PeerId ownerPeerId,
    required String path,
    required int sequenceNumber,
    PeerId? fromServer,
  }) async {
    final serverId = fromServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for feed entry retrieval');
      return null;
    }

    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [FeedHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);

      final response = await FeedHandler.getFeedEntry(
        stream,
        ownerPeerId: ownerPeerId,
        path: path,
        sequenceNumber: sequenceNumber,
      ).timeout(config.messageTimeout);

      await stream.close();

      if (!response.isSuccess) {
        _logger.warning('GET feed entry $path#$sequenceNumber: ${response.status}');
        return null;
      }

      return FeedEntry(
        sequence: response.sequence ?? sequenceNumber,
        entryType: response.entryType,
        content: response.body ?? Uint8List(0),
        contentHash: response.etag ?? '',
        createdAt: response.headers['Created-At'] as int? ?? 0,
      );
    } on TimeoutException {
      _logger.warning('GET feed entry timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to GET feed entry: $e');
      return null;
    }
  }

  /// Get feed entries (range query)
  Future<FeedEntriesResult?> getFeedEntries({
    required PeerId ownerPeerId,
    required String path,
    int? fromSequence,
    int? toSequence,
    int? limit,
    String? entryType,
    PeerId? fromServer,
  }) async {
    final serverId = fromServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for feed entries retrieval');
      return null;
    }

    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [FeedHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);

      final response = await FeedHandler.getFeedEntries(
        stream,
        ownerPeerId: ownerPeerId,
        path: path,
        fromSequence: fromSequence,
        toSequence: toSequence,
        limit: limit,
        entryType: entryType,
      ).timeout(config.messageTimeout);

      await stream.close();

      if (!response.isSuccess) {
        _logger.warning('GET feed entries $path: ${response.status}');
        return null;
      }

      final body = jsonDecode(utf8.decode(response.body!)) as Map<String, dynamic>;
      final entriesList = body['entries'] as List<dynamic>? ?? [];
      final entries = entriesList.map((e) {
        final entry = e as Map<String, dynamic>;
        return FeedEntry(
          sequence: entry['seq'] as int,
          entryType: entry['type'] as String?,
          content: Uint8List.fromList(
            base64Decode(entry['content'] as String? ?? ''),
          ),
          contentHash: entry['hash'] as String? ?? '',
          createdAt: entry['createdAt'] as int? ?? 0,
          createdBy: entry['createdBy'] as String?,
        );
      }).toList();

      return FeedEntriesResult(
        entries: entries,
        hasMore: response.hasMore ?? false,
        nextSequence: response.nextSequence,
      );
    } on TimeoutException {
      _logger.warning('GET feed entries timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to GET feed entries: $e');
      return null;
    }
  }

  // ============================================================================
  // Collection Store Operations (SCA)
  // ============================================================================

  /// Create a new collection on your store
  Future<CollectionInfo?> createCollection({
    required String path,
    required String name,
    PeerId? toServer,
  }) async {
    final serverId = toServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for collection creation');
      return null;
    }

    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [CollectionHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);

      final response = await CollectionHandler.createCollection(
        stream,
        ownerPeerId: host.id,
        path: path,
        name: name,
      ).timeout(config.messageTimeout);

      await stream.close();

      if (!response.isSuccess) {
        _logger.warning('CREATE collection $path: ${response.status} ${response.error}');
        return null;
      }

      final body = jsonDecode(utf8.decode(response.body!)) as Map<String, dynamic>;
      return CollectionInfo(
        path: body['path'] as String,
        name: body['name'] as String,
        recordCount: body['recordCount'] as int? ?? 0,
        createdAt: body['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      );
    } on TimeoutException {
      _logger.warning('CREATE collection timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to CREATE collection: $e');
      return null;
    }
  }

  /// Get collection metadata
  Future<CollectionInfo?> getCollection({
    required PeerId ownerPeerId,
    required String path,
    PeerId? fromServer,
  }) async {
    final serverId = fromServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for collection retrieval');
      return null;
    }

    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [CollectionHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);

      final response = await CollectionHandler.getCollection(
        stream,
        ownerPeerId: ownerPeerId,
        path: path,
      ).timeout(config.messageTimeout);

      await stream.close();

      if (!response.isSuccess) {
        _logger.warning('GET collection $path: ${response.status} ${response.error}');
        return null;
      }

      final body = jsonDecode(utf8.decode(response.body!)) as Map<String, dynamic>;
      return CollectionInfo(
        path: body['path'] as String? ?? path,
        name: body['name'] as String? ?? '',
        recordCount: body['recordCount'] as int? ?? 0,
        lastModifiedAt: body['lastModifiedAt'] as int?,
        createdAt: body['createdAt'] as int? ?? 0,
      );
    } on TimeoutException {
      _logger.warning('GET collection timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to GET collection: $e');
      return null;
    }
  }

  /// Delete a collection from your store
  Future<bool> deleteCollection({
    required String path,
    PeerId? toServer,
  }) async {
    final serverId = toServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for collection deletion');
      return false;
    }

    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [CollectionHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);

      final response = await CollectionHandler.deleteCollection(
        stream,
        ownerPeerId: host.id,
        path: path,
      ).timeout(config.messageTimeout);

      await stream.close();
      return response.isSuccess;
    } on TimeoutException {
      _logger.warning('DELETE collection timed out');
      return false;
    } catch (e) {
      _logger.warning('Failed to DELETE collection: $e');
      return false;
    }
  }

  /// List all collections for an owner
  Future<List<CollectionInfo>?> listCollections({
    required PeerId ownerPeerId,
    PeerId? fromServer,
  }) async {
    final serverId = fromServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for collection listing');
      return null;
    }

    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [CollectionHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);

      final response = await CollectionHandler.listCollections(
        stream,
        ownerPeerId: ownerPeerId,
      ).timeout(config.messageTimeout);

      await stream.close();

      if (!response.isSuccess) {
        _logger.warning('LIST collections: ${response.status} ${response.error}');
        return null;
      }

      final list = jsonDecode(utf8.decode(response.body!)) as List<dynamic>;
      return list.map((item) {
        final c = item as Map<String, dynamic>;
        return CollectionInfo(
          path: c['path'] as String,
          name: c['name'] as String? ?? '',
          recordCount: c['recordCount'] as int? ?? 0,
          lastModifiedAt: c['lastModifiedAt'] as int?,
          createdAt: c['createdAt'] as int? ?? 0,
        );
      }).toList();
    } on TimeoutException {
      _logger.warning('LIST collections timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to LIST collections: $e');
      return null;
    }
  }

  /// Put (create or update) a collection item
  Future<CollectionItemResult?> putCollectionItem({
    required String path,
    required String key,
    required Uint8List content,
    String? ifMatch,
    PeerId? toServer,
  }) async {
    final serverId = toServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for collection item put');
      return null;
    }

    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [CollectionHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);

      final response = await CollectionHandler.putCollectionItem(
        stream,
        ownerPeerId: host.id,
        path: path,
        key: key,
        content: content,
        ifMatch: ifMatch,
      ).timeout(config.messageTimeout);

      await stream.close();

      return CollectionItemResult(
        status: response.status,
        etag: response.etag,
        version: response.version,
        created: response.status == 201,
      );
    } on TimeoutException {
      _logger.warning('PUT collection item timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to PUT collection item: $e');
      return null;
    }
  }

  /// Get a single collection item by key
  Future<CollectionItem?> getCollectionItem({
    required PeerId ownerPeerId,
    required String path,
    required String key,
    PeerId? fromServer,
  }) async {
    final serverId = fromServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for collection item retrieval');
      return null;
    }

    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [CollectionHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);

      final response = await CollectionHandler.getCollectionItem(
        stream,
        ownerPeerId: ownerPeerId,
        path: path,
        key: key,
      ).timeout(config.messageTimeout);

      await stream.close();

      if (!response.isSuccess) {
        _logger.warning('GET collection item $path/$key: ${response.status}');
        return null;
      }

      final content = response.body != null
          ? jsonDecode(utf8.decode(response.body!)) as Map<String, dynamic>
          : <String, dynamic>{};

      return CollectionItem(
        key: key,
        content: content,
        contentHash: response.etag ?? '',
        version: response.version ?? 1,
        createdAt: response.headers['Created-At'] as int? ?? 0,
        updatedAt: response.headers['Updated-At'] as int? ?? 0,
      );
    } on TimeoutException {
      _logger.warning('GET collection item timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to GET collection item: $e');
      return null;
    }
  }

  /// Delete a collection item
  Future<bool> deleteCollectionItem({
    required String path,
    required String key,
    PeerId? toServer,
  }) async {
    final serverId = toServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for collection item deletion');
      return false;
    }

    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [CollectionHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);

      final response = await CollectionHandler.deleteCollectionItem(
        stream,
        ownerPeerId: host.id,
        path: path,
        key: key,
      ).timeout(config.messageTimeout);

      await stream.close();
      return response.isSuccess;
    } on TimeoutException {
      _logger.warning('DELETE collection item timed out');
      return false;
    } catch (e) {
      _logger.warning('Failed to DELETE collection item: $e');
      return false;
    }
  }

  /// List keys in a collection
  Future<CollectionKeysResult?> listCollectionKeys({
    required PeerId ownerPeerId,
    required String path,
    int? limit,
    int? offset,
    PeerId? fromServer,
  }) async {
    final serverId = fromServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for collection keys listing');
      return null;
    }

    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [CollectionHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);

      final response = await CollectionHandler.listCollectionKeys(
        stream,
        ownerPeerId: ownerPeerId,
        path: path,
        limit: limit,
        offset: offset,
      ).timeout(config.messageTimeout);

      await stream.close();

      if (!response.isSuccess) {
        _logger.warning('LIST collection keys $path: ${response.status}');
        return null;
      }

      final body = jsonDecode(utf8.decode(response.body!)) as Map<String, dynamic>;
      final keys = (body['keys'] as List<dynamic>).cast<String>();

      return CollectionKeysResult(
        keys: keys,
        totalCount: response.totalCount ?? keys.length,
        hasMore: response.hasMore ?? false,
      );
    } on TimeoutException {
      _logger.warning('LIST collection keys timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to LIST collection keys: $e');
      return null;
    }
  }

  /// Query a collection with JSONB filtering
  Future<CollectionQueryResult?> queryCollection({
    required PeerId ownerPeerId,
    required String path,
    Map<String, dynamic>? filter,
    String? sortField,
    bool? sortAsc,
    int? limit,
    int? offset,
    PeerId? fromServer,
  }) async {
    final serverId = fromServer ?? await _serverSelector.selectServer(config.preferredServers);
    if (serverId == null) {
      _logger.warning('No S&F server available for collection query');
      return null;
    }

    try {
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [CollectionHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);

      final response = await CollectionHandler.queryCollection(
        stream,
        ownerPeerId: ownerPeerId,
        path: path,
        filter: filter,
        sortField: sortField,
        sortAsc: sortAsc,
        limit: limit,
        offset: offset,
      ).timeout(config.messageTimeout);

      await stream.close();

      if (!response.isSuccess) {
        _logger.warning('QUERY collection $path: ${response.status}');
        return null;
      }

      final body = jsonDecode(utf8.decode(response.body!)) as Map<String, dynamic>;
      final itemsList = body['items'] as List<dynamic>? ?? [];
      final items = itemsList.map((item) {
        final i = item as Map<String, dynamic>;
        return CollectionItem(
          key: i['key'] as String,
          content: i['content'] as Map<String, dynamic>? ?? {},
          contentHash: i['hash'] as String? ?? '',
          version: i['version'] as int? ?? 1,
          createdAt: i['createdAt'] as int? ?? 0,
          updatedAt: i['updatedAt'] as int? ?? 0,
        );
      }).toList();

      return CollectionQueryResult(
        items: items,
        totalCount: response.totalCount ?? items.length,
        hasMore: response.hasMore ?? false,
      );
    } on TimeoutException {
      _logger.warning('QUERY collection timed out');
      return null;
    } catch (e) {
      _logger.warning('Failed to QUERY collection: $e');
      return null;
    }
  }

  // ============================================================================
  // Presence Tracking Operations
  // ============================================================================

  /// Track a contact's online/offline presence
  ///
  /// Subscribes to the presence topic of the server hosting this contact.
  /// Use [contactPresenceChanges] to receive state change events.
  void trackContactPresence(PeerId contact, PeerId serverPeerId) {
    if (_presenceTracker == null) {
      _logger.warning('Presence tracking unavailable - PubSub not initialized');
      return;
    }
    _presenceTracker!.trackContact(contact, serverPeerId);
  }

  /// Stop tracking a contact's presence
  void untrackContactPresence(PeerId contact) {
    _presenceTracker?.untrackContact(contact);
  }

  /// Get a contact's current presence state (from local cache)
  PresenceStatus? getContactPresence(PeerId contact) {
    return _presenceTracker?.getPresence(contact);
  }

  /// Check if a contact is online
  bool isContactOnline(PeerId contact) {
    return _presenceTracker?.isOnline(contact) ?? false;
  }

  /// Stream of presence changes for tracked contacts
  Stream<PresenceChange>? get contactPresenceChanges =>
      _presenceTracker?.contactPresenceChanges;

  // ============================================================================
  // URI Operations
  // ============================================================================

  /// Build a document URI for a resource owned by the current user
  /// 
  /// Creates a stable Ricochet URI with the current user as owner and
  /// the configured preferred servers as resolution hints.
  /// 
  /// Example:
  /// ```dart
  /// final uri = client.buildDocumentUri('profile');
  /// // ricochet://12D3KooW.../doc/profile?servers=12D3KooWServer...
  /// ```
  RicochetUri buildDocumentUri(String path) {
    return RicochetUri.document(
      owner: host.id,
      path: path,
      servers: config.preferredServers.map((s) => s.serverId).toList(),
    );
  }
  
  /// Build a mailbox URI for a resource owned by the current user
  RicochetUri buildMailboxUri(String path) {
    return RicochetUri.mailbox(
      owner: host.id,
      path: path,
      servers: config.preferredServers.map((s) => s.serverId).toList(),
    );
  }
  
  /// Resolve a Ricochet URI to its content
  /// 
  /// Tries each server in the URI's server list until one succeeds,
  /// providing automatic failover and resilience.
  /// 
  /// Returns null if the resource doesn't exist or all servers fail.
  /// 
  /// Example:
  /// ```dart
  /// final uri = RicochetUri.parse('ricochet://12D3KooWBob.../doc/avatar?servers=...');
  /// final resolved = await client.resolveUri(uri);
  /// if (resolved != null) {
  ///   final imageData = resolved.content;
  ///   final optimizedUri = resolved.optimizedUri; // Server order updated
  /// }
  /// ```
  Future<ResolvedDocument?> resolveUri(
    RicochetUri uri, {
    Duration? perServerTimeout,
  }) async {
    final resolver = RicochetUriResolver(this, defaultPerServerTimeout: perServerTimeout ?? config.messageTimeout);
    return resolver.resolveDocument(uri, perServerTimeout: perServerTimeout);
  }
  
  @override
  String toString() {
    return 'SFClient(peer: ${host.id.toString().substring(0, 12)}..., '
           'servers: ${config.preferredServers.length}, '
           'autoRetrieval: ${_autoRetrievalTimer != null})';
  }
}


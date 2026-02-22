/// Client API for remote mailbox management
///
/// Provides high-level methods for creating mailboxes, managing ACLs,
/// updating configuration, and performing other mailbox operations.
library;

import 'dart:async';
import 'dart:typed_data';
import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/network/context.dart';
import 'package:logging/logging.dart';

import '../core/mailbox_address.dart';
import '../core/mailbox_types.dart';
import '../protocol/mma/admin_protocol.dart';
import '../protocol/mma/admin_frame.dart';
import 'sf_client_config.dart';
import 'server_selector.dart';

/// Mailbox Manager - Client API for remote mailbox management
class MailboxManager {
  static final Logger _logger = Logger('MailboxManager');
  
  final Host host;
  final SFClientConfig config;
  late final ServerSelector _serverSelector;
  
  MailboxManager({
    required this.host,
    required this.config,
  }) {
    _serverSelector = ServerSelector(host: host);
  }
  
  /// Create a new mailbox
  Future<void> createMailbox({
    required String folderPath,
    required MailboxType type,
    int? maxMessages,
    int? retentionDays,
    int? retentionCount,
  }) async {
    _logger.fine('Creating mailbox: $folderPath (type: ${type.name})');
    
    final address = MailboxAddress(
      ownerId: host.id,
      folderPath: folderPath,
      type: type,
    );
    
    final request = CreateMailboxRequest(
      address: address,
      maxMessages: maxMessages,
      retentionDays: retentionDays,
      retentionCount: retentionCount,
    );
    
    final response = await _sendRequest(request);
    if (!response.success) {
      throw MailboxManagementError(
        response.errorMessage ?? 'Failed to create mailbox',
      );
    }
    
    _logger.info('Created mailbox: ${address.fullPath}');
  }
  
  /// Grant access to another peer
  Future<void> grantAccess({
    required String folderPath,
    required MailboxType type,
    required PeerId targetPeerId,
    required AccessMode accessMode,
  }) async {
    _logger.fine('Granting $accessMode access to ${targetPeerId.toBase58()} for $folderPath');
    
    final address = MailboxAddress(
      ownerId: host.id,
      folderPath: folderPath,
      type: type,
    );
    
    final request = GrantAccessRequest(
      address: address,
      targetPeerId: targetPeerId,
      accessMode: accessMode,
    );
    
    final response = await _sendRequest(request);
    if (!response.success) {
      throw MailboxManagementError(
        response.errorMessage ?? 'Failed to grant access',
      );
    }
    
    _logger.info('Granted $accessMode access to ${targetPeerId.toBase58()} for ${address.fullPath}');
  }
  
  /// Revoke access from a peer
  Future<void> revokeAccess({
    required String folderPath,
    required MailboxType type,
    required PeerId targetPeerId,
  }) async {
    _logger.fine('Revoking access from ${targetPeerId.toBase58()} for $folderPath');
    
    final address = MailboxAddress(
      ownerId: host.id,
      folderPath: folderPath,
      type: type,
    );
    
    final request = RevokeAccessRequest(
      address: address,
      targetPeerId: targetPeerId,
    );
    
    final response = await _sendRequest(request);
    if (!response.success) {
      throw MailboxManagementError(
        response.errorMessage ?? 'Failed to revoke access',
      );
    }
    
    _logger.info('Revoked access from ${targetPeerId.toBase58()} for ${address.fullPath}');
  }
  
  /// List all ACL entries for a mailbox
  Future<List<ACLEntry>> listACL({
    required String folderPath,
    required MailboxType type,
  }) async {
    _logger.fine('Listing ACL for $folderPath');
    
    final address = MailboxAddress(
      ownerId: host.id,
      folderPath: folderPath,
      type: type,
    );
    
    final request = ListACLRequest(address: address);
    
    final response = await _sendRequest(request);
    if (!response.success) {
      throw MailboxManagementError(
        response.errorMessage ?? 'Failed to list ACL',
      );
    }
    
    if (response.data == null) {
      return [];
    }
    
    return AdminFrame.decodeACLList(response.data as List<dynamic>);
  }
  
  /// Update mailbox configuration
  Future<void> updateConfig({
    required String folderPath,
    required MailboxType type,
    int? maxMessages,
    int? retentionDays,
    int? retentionCount,
  }) async {
    _logger.fine('Updating config for $folderPath');
    
    final address = MailboxAddress(
      ownerId: host.id,
      folderPath: folderPath,
      type: type,
    );
    
    final request = UpdateMailboxConfigRequest(
      address: address,
      maxMessages: maxMessages,
      retentionDays: retentionDays,
      retentionCount: retentionCount,
    );
    
    final response = await _sendRequest(request);
    if (!response.success) {
      throw MailboxManagementError(
        response.errorMessage ?? 'Failed to update config',
      );
    }
    
    _logger.info('Updated config for ${address.fullPath}');
  }
  
  /// Delete a mailbox
  Future<void> deleteMailbox({
    required String folderPath,
    required MailboxType type,
  }) async {
    _logger.fine('Deleting mailbox: $folderPath');
    
    final address = MailboxAddress(
      ownerId: host.id,
      folderPath: folderPath,
      type: type,
    );
    
    final request = DeleteMailboxRequest(address: address);
    
    final response = await _sendRequest(request);
    if (!response.success) {
      throw MailboxManagementError(
        response.errorMessage ?? 'Failed to delete mailbox',
      );
    }
    
    _logger.info('Deleted mailbox: ${address.fullPath}');
  }
  
  /// List all mailboxes owned by this client
  Future<List<MailboxInfo>> listMailboxes() async {
    _logger.fine('Listing mailboxes for ${host.id.toBase58()}');
    
    final request = ListMailboxesRequest(ownerId: host.id);
    
    final response = await _sendRequest(request);
    if (!response.success) {
      throw MailboxManagementError(
        response.errorMessage ?? 'Failed to list mailboxes',
      );
    }
    
    if (response.data == null) {
      return [];
    }
    
    return AdminFrame.decodeMailboxInfoList(response.data as List<dynamic>);
  }
  
  /// Get detailed info about a specific mailbox
  Future<MailboxInfo> getMailboxInfo({
    required String folderPath,
    required MailboxType type,
  }) async {
    _logger.fine('Getting info for mailbox: $folderPath');
    
    final address = MailboxAddress(
      ownerId: host.id,
      folderPath: folderPath,
      type: type,
    );
    
    final request = GetMailboxInfoRequest(address: address);
    
    final response = await _sendRequest(request);
    if (!response.success) {
      if (response.errorMessage?.contains('not found') ?? false) {
        throw MailboxNotFound(address.fullPath);
      }
      throw MailboxManagementError(
        response.errorMessage ?? 'Failed to get mailbox info',
      );
    }
    
    if (response.data == null) {
      throw MailboxManagementError('No data returned for mailbox info');
    }
    
    return MailboxInfo.fromJson(response.data as Map<String, dynamic>);
  }
  
  /// Send a request to the mailbox management server using MMA (Admin) protocol
  Future<MailboxOperationResponse> _sendRequest(MailboxMgmtRequest request) async {
    try {
      // Select server
      final server = await _selectServer();
      
      // Open stream using MMA (Mailbox Management Agent) protocol
      final context = Context();
      final stream = await host.newStream(
        server,
        [adminProtocolId],
        context,
      );
      
      // Encode and send request with length prefix
      final requestBytes = AdminFrame.encodeRequest(request);
      final lengthBytes = ByteData(4)..setUint32(0, requestBytes.length);
      final combined = Uint8List(4 + requestBytes.length);
      combined.setRange(0, 4, lengthBytes.buffer.asUint8List());
      combined.setRange(4, 4 + requestBytes.length, requestBytes);
      
      await stream.write(combined);
      
      // Read response length
      final responseLengthBytes = await stream.read(4);
      if (responseLengthBytes.length < 4) {
        throw MailboxManagementError('Failed to read response length');
      }
      
      final responseLength = responseLengthBytes.buffer.asByteData().getUint32(0);
      
      // Read response data
      final responseBytes = await stream.read(responseLength);
      if (responseBytes.length < responseLength) {
        throw MailboxManagementError('Failed to read complete response');
      }
      
      // Decode response
      final response = AdminFrame.decodeResponse(responseBytes);
      
      await stream.close();
      
      return response;
      
    } catch (e, stackTrace) {
      _logger.severe('Error sending mailbox management request: $e', e, stackTrace);
      rethrow;
    }
  }
  
  /// Select a server for mailbox management operations
  Future<PeerId> _selectServer() async {
    try {
      // Try preferred servers first
      if (config.preferredServers.isNotEmpty) {
        for (final pref in config.preferredServers) {
          try {
            // Check if we have an existing connection
            final conns = host.network.conns;
            if (conns.any((c) => c.remotePeer == pref.serverId)) {
              return pref.serverId;
            }
            
            // Server is reachable, will be dialed when opening stream
            return pref.serverId;
          } catch (e) {
            _logger.fine('Could not select preferred server ${pref.serverId.toBase58()}: $e');
            continue;
          }
        }
      }
      
      // Fallback to server selector
      final selected = await _serverSelector.selectServer(
        config.preferredServers,
      );
      
      if (selected == null) {
        throw MailboxManagementError('No available servers found');
      }
      
      return selected;
      
    } catch (e) {
      throw MailboxManagementError('Failed to select server: $e');
    }
  }
}


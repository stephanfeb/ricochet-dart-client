import 'dart:convert';
import 'dart:typed_data';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'message_types.dart';
import 'message_flags.dart';

/// Core Store-and-Forward message
/// 
/// Represents a message to be stored and forwarded to a recipient peer.
/// Messages have priority, expiration, and can be encrypted/signed.
/// Supports folder-based addressing and IMAP-style flags.
class SFMessage {
  /// Unique message identifier (UUID)
  final String messageId;
  
  /// Recipient peer ID
  final PeerId recipientPeerId;
  
  /// Sender peer ID
  final PeerId senderPeerId;
  
  /// Message payload (possibly encrypted)
  final Uint8List payload;
  
  /// Message priority
  final MessagePriority priority;
  
  /// Expiration timestamp (milliseconds since epoch)
  final int expiryTimestamp;
  
  /// Number of hops this message has taken
  final int hopCount;
  
  /// Message flags (for protocol-level flags like encrypted, signed, etc.)
  final SFMessageFlags flags;
  
  /// Creation timestamp (milliseconds since epoch)
  final int createdTimestamp;
  
  /// Target folder path (null = default inbox)
  final String? folderPath;
  
  /// Sequence number (set by MDA on storage, null for unsaved messages)
  final int? sequenceNumber;
  
  /// IMAP-style message flags (seen, flagged, deleted, draft)
  final MessageFlags? messageFlags;
  
  /// Whether to keep message after reading (default: false for private mailboxes)
  final bool persistent;
  
  /// Maximum hop count before message is dropped
  static const int maxHopCount = 10;
  
  SFMessage({
    required this.messageId,
    required this.recipientPeerId,
    required this.senderPeerId,
    required this.payload,
    this.priority = MessagePriority.normal,
    required this.expiryTimestamp,
    this.hopCount = 0,
    this.flags = SFMessageFlags.none,
    int? createdTimestamp,
    this.folderPath,
    this.sequenceNumber,
    this.messageFlags,
    this.persistent = false,
  }) : createdTimestamp = createdTimestamp ?? DateTime.now().millisecondsSinceEpoch {
    if (hopCount > maxHopCount) {
      throw ArgumentError('Hop count ($hopCount) exceeds maximum ($maxHopCount)');
    }
  }
  
  /// Create message with default 7-day expiry
  factory SFMessage.withDefaultExpiry({
    required String messageId,
    required PeerId recipientPeerId,
    required PeerId senderPeerId,
    required Uint8List payload,
    MessagePriority priority = MessagePriority.normal,
    int hopCount = 0,
    SFMessageFlags flags = SFMessageFlags.none,
    String? folderPath,
    bool persistent = false,
  }) {
    final now = DateTime.now();
    final expiry = now.add(const Duration(days: 7));
    
    return SFMessage(
      messageId: messageId,
      recipientPeerId: recipientPeerId,
      senderPeerId: senderPeerId,
      payload: payload,
      priority: priority,
      expiryTimestamp: expiry.millisecondsSinceEpoch,
      hopCount: hopCount,
      flags: flags,
      createdTimestamp: now.millisecondsSinceEpoch,
      folderPath: folderPath,
      persistent: persistent,
    );
  }
  
  /// Check if message has expired
  bool get isExpired {
    return DateTime.now().millisecondsSinceEpoch > expiryTimestamp;
  }
  
  /// Get time remaining until expiry
  Duration get timeUntilExpiry {
    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = expiryTimestamp - now;
    return Duration(milliseconds: remaining.clamp(0, double.infinity).toInt());
  }
  
  /// Get message age
  Duration get age {
    final now = DateTime.now().millisecondsSinceEpoch;
    return Duration(milliseconds: now - createdTimestamp);
  }
  
  /// Create a copy with incremented hop count (for forwarding)
  SFMessage withIncrementedHopCount() {
    if (hopCount >= maxHopCount) {
      throw StateError('Cannot forward message: hop count limit reached');
    }
    
    return SFMessage(
      messageId: messageId,
      recipientPeerId: recipientPeerId,
      senderPeerId: senderPeerId,
      payload: payload,
      priority: priority,
      expiryTimestamp: expiryTimestamp,
      hopCount: hopCount + 1,
      flags: flags.withFlag(SFMessageFlags.forwarded),
      createdTimestamp: createdTimestamp,
      folderPath: folderPath,
      sequenceNumber: sequenceNumber,
      messageFlags: messageFlags,
      persistent: persistent,
    );
  }
  
  /// Create a copy with a different payload (and, optionally, flags): the
  /// sealed or opened form of the same message.
  SFMessage withPayload(Uint8List newPayload, {SFMessageFlags? flags}) {
    return SFMessage(
      messageId: messageId,
      recipientPeerId: recipientPeerId,
      senderPeerId: senderPeerId,
      payload: newPayload,
      priority: priority,
      expiryTimestamp: expiryTimestamp,
      hopCount: hopCount,
      flags: flags ?? this.flags,
      createdTimestamp: createdTimestamp,
      folderPath: folderPath,
      sequenceNumber: sequenceNumber,
      messageFlags: messageFlags,
      persistent: persistent,
    );
  }

  /// Create a copy with updated flags
  SFMessage withFlags(SFMessageFlags newFlags) {
    return SFMessage(
      messageId: messageId,
      recipientPeerId: recipientPeerId,
      senderPeerId: senderPeerId,
      payload: payload,
      priority: priority,
      expiryTimestamp: expiryTimestamp,
      hopCount: hopCount,
      flags: newFlags,
      createdTimestamp: createdTimestamp,
      folderPath: folderPath,
      sequenceNumber: sequenceNumber,
      messageFlags: messageFlags,
      persistent: persistent,
    );
  }
  
  /// Create a copy with updated priority
  SFMessage withPriority(MessagePriority newPriority) {
    return SFMessage(
      messageId: messageId,
      recipientPeerId: recipientPeerId,
      senderPeerId: senderPeerId,
      payload: payload,
      priority: newPriority,
      expiryTimestamp: expiryTimestamp,
      hopCount: hopCount,
      flags: flags,
      createdTimestamp: createdTimestamp,
      folderPath: folderPath,
      sequenceNumber: sequenceNumber,
      messageFlags: messageFlags,
      persistent: persistent,
    );
  }
  
  /// Create a copy with updated sequence number (set by MDA on storage)
  SFMessage withSequence(int sequence) {
    return SFMessage(
      messageId: messageId,
      recipientPeerId: recipientPeerId,
      senderPeerId: senderPeerId,
      payload: payload,
      priority: priority,
      expiryTimestamp: expiryTimestamp,
      hopCount: hopCount,
      flags: flags,
      createdTimestamp: createdTimestamp,
      folderPath: folderPath,
      sequenceNumber: sequence,
      messageFlags: messageFlags,
      persistent: persistent,
    );
  }
  
  /// Create a copy with updated message flags
  SFMessage withMessageFlags(MessageFlags newMessageFlags) {
    return SFMessage(
      messageId: messageId,
      recipientPeerId: recipientPeerId,
      senderPeerId: senderPeerId,
      payload: payload,
      priority: priority,
      expiryTimestamp: expiryTimestamp,
      hopCount: hopCount,
      flags: flags,
      createdTimestamp: createdTimestamp,
      folderPath: folderPath,
      sequenceNumber: sequenceNumber,
      messageFlags: newMessageFlags,
      persistent: persistent,
    );
  }
  
  /// Convert to map for serialization (without payload data)
  Map<String, dynamic> toMap() {
    return {
      'messageId': messageId,
      'recipientPeerId': recipientPeerId.toString(),
      'senderPeerId': senderPeerId.toString(),
      'payloadSize': payload.length,
      'priority': priority.value,
      'expiryTimestamp': expiryTimestamp,
      'hopCount': hopCount,
      'flags': flags.value,
      'createdTimestamp': createdTimestamp,
    };
  }
  
  /// Convert to JSON for wire/storage (includes payload as base64)
  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'recipientPeerId': recipientPeerId.toString(),
      'senderPeerId': senderPeerId.toString(),
      'payload': base64Encode(payload),
      'priority': priority.value,
      'expiryTimestamp': expiryTimestamp,
      'hopCount': hopCount,
      'flags': flags.value,
      'createdTimestamp': createdTimestamp,
      'folderPath': folderPath,
      'sequenceNumber': sequenceNumber,
      'messageFlags': messageFlags?.bitmap,
      'persistent': persistent,
    };
  }
  
  /// Create from JSON (handles both string and byte-array peer ID formats)
  factory SFMessage.fromJson(Map<String, dynamic> json) {
    try {
      final recipientRaw = json['recipientPeerId'];
      final senderRaw = json['senderPeerId'];

      if (recipientRaw == null) {
        throw FormatException('Missing recipientPeerId in JSON');
      }
      if (senderRaw == null) {
        throw FormatException('Missing senderPeerId in JSON');
      }

      // Parse peer ID from string or byte array (backward compat)
      PeerId parsePeerId(dynamic raw) {
        if (raw is String) {
          return PeerId.fromString(raw);
        } else if (raw is List) {
          return PeerId.fromBytes(Uint8List.fromList(raw.cast<int>()));
        } else {
          throw FormatException('Invalid peerId format: ${raw.runtimeType}');
        }
      }

      return SFMessage(
        messageId: json['messageId'] as String,
        recipientPeerId: parsePeerId(recipientRaw),
        senderPeerId: parsePeerId(senderRaw),
        payload: base64Decode(json['payload'] as String),
        priority: MessagePriority.fromValue(json['priority'] as int),
        expiryTimestamp: json['expiryTimestamp'] as int,
        hopCount: json['hopCount'] as int,
        flags: SFMessageFlags(json['flags'] as int),
        createdTimestamp: json['createdTimestamp'] as int,
        folderPath: json['folderPath'] as String?,
        sequenceNumber: json['sequenceNumber'] as int?,
        messageFlags: json['messageFlags'] != null
            ? MessageFlags(json['messageFlags'] as int)
            : null,
        persistent: json['persistent'] as bool? ?? false,
      );
    } catch (e, stackTrace) {
      throw FormatException('Failed to parse SFMessage from JSON: $e\nJSON: $json\nStack: $stackTrace');
    }
  }
  
  @override
  String toString() {
    return 'SFMessage(id: $messageId, from: ${senderPeerId.toString().substring(0, 12)}..., '
           'to: ${recipientPeerId.toString().substring(0, 12)}..., '
           'priority: $priority, hops: $hopCount, size: ${payload.length} bytes)';
  }
  
  @override
  bool operator ==(Object other) =>
      other is SFMessage && other.messageId == messageId;
  
  @override
  int get hashCode => messageId.hashCode;
}

/// Store message acknowledgment
class StoreAck {
  final String messageId;
  final bool success;
  final String? errorMessage;
  final int? estimatedDeliveryTime; // milliseconds until expected delivery
  
  const StoreAck({
    required this.messageId,
    required this.success,
    this.errorMessage,
    this.estimatedDeliveryTime,
  });
  
  @override
  String toString() {
    if (success) {
      return 'StoreAck(messageId: $messageId, success: true, eta: ${estimatedDeliveryTime}ms)';
    } else {
      return 'StoreAck(messageId: $messageId, success: false, error: $errorMessage)';
    }
  }
}

/// Retrieve messages request
class RetrieveMessagesRequest {
  final PeerId peerId;
  final String? folderPath;
  final int? fromSequence;
  final int? maxMessages;
  final MessagePriority? minPriority;
  
  const RetrieveMessagesRequest({
    required this.peerId,
    this.folderPath,
    this.fromSequence,
    this.maxMessages,
    this.minPriority,
  });
}

/// Retrieve messages response
class RetrieveMessagesResponse {
  final List<SFMessage> messages;
  final bool hasMore;
  
  const RetrieveMessagesResponse({
    required this.messages,
    this.hasMore = false,
  });
  
  @override
  String toString() {
    return 'RetrieveMessagesResponse(count: ${messages.length}, hasMore: $hasMore)';
  }
}

/// Server capacity information
class ServerCapacity {
  final int totalStorageBytes;
  final int usedStorageBytes;
  final int availableStorageBytes;
  final int messageCount;
  final int activeMailboxes;
  final double healthScore;
  
  const ServerCapacity({
    required this.totalStorageBytes,
    required this.usedStorageBytes,
    required this.availableStorageBytes,
    required this.messageCount,
    required this.activeMailboxes,
    required this.healthScore,
  });
  
  double get usagePercent => 
      totalStorageBytes > 0 ? (usedStorageBytes / totalStorageBytes) * 100 : 0;
  
  bool get isNearCapacity => usagePercent > 90;
  
  Map<String, dynamic> toMap() {
    return {
      'totalStorageBytes': totalStorageBytes,
      'usedStorageBytes': usedStorageBytes,
      'availableStorageBytes': availableStorageBytes,
      'usagePercent': usagePercent.toStringAsFixed(2),
      'messageCount': messageCount,
      'activeMailboxes': activeMailboxes,
      'healthScore': healthScore,
    };
  }
  
  Map<String, dynamic> toJson() => toMap();
  
  factory ServerCapacity.fromJson(Map<String, dynamic> json) {
    return ServerCapacity(
      totalStorageBytes: json['totalStorageBytes'] as int,
      usedStorageBytes: json['usedStorageBytes'] as int,
      availableStorageBytes: json['availableStorageBytes'] as int,
      messageCount: json['messageCount'] as int,
      activeMailboxes: json['activeMailboxes'] as int,
      healthScore: (json['healthScore'] as num).toDouble(),
    );
  }
  
  @override
  String toString() {
    return 'ServerCapacity(usage: ${usagePercent.toStringAsFixed(1)}%, '
           'messages: $messageCount, mailboxes: $activeMailboxes, health: $healthScore)';
  }
}

// ============================================================================
// IMAP-Style Message Flag Operations
// ============================================================================

/// Request to mark messages as delivered (sets \Seen flag)
class MarkDeliveredRequest {
  /// List of message IDs to mark as delivered
  final List<String> messageIds;
  
  /// Optional folder path filter (null = all folders)
  final String? folderPath;
  
  const MarkDeliveredRequest({
    required this.messageIds,
    this.folderPath,
  });
  
  Map<String, dynamic> toJson() => {
    'operationType': 'markDelivered',
    'messageIds': messageIds,
    if (folderPath != null) 'folderPath': folderPath,
  };
  
  factory MarkDeliveredRequest.fromJson(Map<String, dynamic> json) {
    return MarkDeliveredRequest(
      messageIds: (json['messageIds'] as List).cast<String>(),
      folderPath: json['folderPath'] as String?,
    );
  }
}

/// Acknowledgment for mark delivered request
class MarkDeliveredAck {
  final bool success;
  final int updatedCount;
  final String? errorMessage;
  
  const MarkDeliveredAck({
    required this.success,
    this.updatedCount = 0,
    this.errorMessage,
  });
  
  Map<String, dynamic> toJson() => {
    'success': success,
    'updatedCount': updatedCount,
    if (errorMessage != null) 'errorMessage': errorMessage,
  };
  
  factory MarkDeliveredAck.fromJson(Map<String, dynamic> json) {
    return MarkDeliveredAck(
      success: json['success'] as bool? ?? false, // Default to false if missing/null
      updatedCount: json['updatedCount'] as int? ?? 0,
      errorMessage: json['errorMessage'] as String?,
    );
  }
}

/// Request to update message flags (IMAP STORE)
class UpdateFlagsRequest {
  /// Message ID to update
  final String messageId;
  
  /// Flags to add (bitwise OR)
  final int addFlags;
  
  /// Flags to remove (bitwise AND NOT)
  final int removeFlags;
  
  const UpdateFlagsRequest({
    required this.messageId,
    this.addFlags = 0,
    this.removeFlags = 0,
  });
  
  Map<String, dynamic> toJson() => {
    'operationType': 'updateFlags',
    'messageId': messageId,
    'addFlags': addFlags,
    'removeFlags': removeFlags,
  };
  
  factory UpdateFlagsRequest.fromJson(Map<String, dynamic> json) {
    return UpdateFlagsRequest(
      messageId: json['messageId'] as String,
      addFlags: json['addFlags'] as int? ?? 0,
      removeFlags: json['removeFlags'] as int? ?? 0,
    );
  }
}

/// Acknowledgment for update flags request
class UpdateFlagsAck {
  final bool success;
  final int? newFlags;
  final String? errorMessage;
  
  const UpdateFlagsAck({
    required this.success,
    this.newFlags,
    this.errorMessage,
  });
  
  Map<String, dynamic> toJson() => {
    'success': success,
    if (newFlags != null) 'newFlags': newFlags,
    if (errorMessage != null) 'errorMessage': errorMessage,
  };
  
  factory UpdateFlagsAck.fromJson(Map<String, dynamic> json) {
    return UpdateFlagsAck(
      success: json['success'] as bool,
      newFlags: json['newFlags'] as int?,
      errorMessage: json['errorMessage'] as String?,
    );
  }
}

/// Request to expunge messages marked with \Deleted flag (IMAP EXPUNGE)
class ExpungeRequest {
  /// Peer ID owning the mailboxes to expunge
  final PeerId peerId;
  
  /// Optional folder path filter (null = all folders)
  final String? folderPath;
  
  const ExpungeRequest({
    required this.peerId,
    this.folderPath,
  });
  
  Map<String, dynamic> toJson() => {
    'operationType': 'expunge',
    'peerId': peerId.toString(),
    if (folderPath != null) 'folderPath': folderPath,
  };

  factory ExpungeRequest.fromJson(Map<String, dynamic> json) {
    final peerIdRaw = json['peerId'];
    PeerId peerId;
    if (peerIdRaw is String) {
      peerId = PeerId.fromString(peerIdRaw);
    } else if (peerIdRaw is List) {
      peerId = PeerId.fromBytes(Uint8List.fromList(peerIdRaw.cast<int>()));
    } else {
      throw FormatException('Invalid peerId format: ${peerIdRaw.runtimeType}');
    }
    return ExpungeRequest(
      peerId: peerId,
      folderPath: json['folderPath'] as String?,
    );
  }
}

/// Acknowledgment for expunge request
class ExpungeAck {
  final bool success;
  final int deletedCount;
  final String? errorMessage;
  
  const ExpungeAck({
    required this.success,
    this.deletedCount = 0,
    this.errorMessage,
  });
  
  Map<String, dynamic> toJson() => {
    'success': success,
    'deletedCount': deletedCount,
    if (errorMessage != null) 'errorMessage': errorMessage,
  };
  
  factory ExpungeAck.fromJson(Map<String, dynamic> json) {
    return ExpungeAck(
      success: json['success'] as bool,
      deletedCount: json['deletedCount'] as int? ?? 0,
      errorMessage: json['errorMessage'] as String?,
    );
  }
}

/// Request to delete messages immediately (bypasses \Deleted flag)
class DeleteMessagesRequest {
  /// List of message IDs to delete
  final List<String> messageIds;
  
  const DeleteMessagesRequest({
    required this.messageIds,
  });
  
  Map<String, dynamic> toJson() => {
    'operationType': 'deleteMessages',
    'messageIds': messageIds,
  };
  
  factory DeleteMessagesRequest.fromJson(Map<String, dynamic> json) {
    return DeleteMessagesRequest(
      messageIds: (json['messageIds'] as List).cast<String>(),
    );
  }
}

/// Acknowledgment for delete messages request
class DeleteMessagesAck {
  final bool success;
  final int deletedCount;
  final String? errorMessage;
  
  const DeleteMessagesAck({
    required this.success,
    this.deletedCount = 0,
    this.errorMessage,
  });
  
  Map<String, dynamic> toJson() => {
    'success': success,
    'deletedCount': deletedCount,
    if (errorMessage != null) 'errorMessage': errorMessage,
  };
  
  factory DeleteMessagesAck.fromJson(Map<String, dynamic> json) {
    return DeleteMessagesAck(
      success: json['success'] as bool,
      deletedCount: json['deletedCount'] as int? ?? 0,
      errorMessage: json['errorMessage'] as String?,
    );
  }
}

// ============================================================================
// Document Store Types
// ============================================================================

/// Response from GET document operation
class DocumentResponse {
  final int status;
  final String? etag;
  final String? contentType;
  final int? lastModified;
  final Uint8List? content;
  
  const DocumentResponse({
    required this.status,
    this.etag,
    this.contentType,
    this.lastModified,
    this.content,
  });
  
  bool get isNotModified => status == 304;
  bool get isNotFound => status == 404;
  bool get isSuccess => status == 200;
  bool get isForbidden => status == 403;
}

/// Response from PUT document operation
class DocumentPutResponse {
  final int status;
  final String? etag;
  final int? lastModified;
  final bool created;
  
  const DocumentPutResponse({
    required this.status,
    this.etag,
    this.lastModified,
    required this.created,
  });
  
  bool get isSuccess => status == 200 || status == 201 || status == 204;
  bool get isConflict => status == 409;
  bool get isForbidden => status == 403;
}

/// Metadata from HEAD document operation
class DocumentMetadata {
  final String etag;
  final String contentType;
  final int lastModified;
  final int contentLength;
  
  const DocumentMetadata({
    required this.etag,
    required this.contentType,
    required this.lastModified,
    required this.contentLength,
  });
}

/// Document information from LIST operation
class DocumentInfo {
  final String path;
  final String contentType;
  final int size;
  final String etag;
  final int lastModified;

  const DocumentInfo({
    required this.path,
    required this.contentType,
    required this.size,
    required this.etag,
    required this.lastModified,
  });
}

/// A user's directory listing entry (client-facing)
class DirectoryEntryInfo {
  final String peerId;
  final String displayName;
  final String? bio;
  final String? avatarHash;
  final int listedAt;
  final int updatedAt;

  const DirectoryEntryInfo({
    required this.peerId,
    required this.displayName,
    this.bio,
    this.avatarHash,
    required this.listedAt,
    required this.updatedAt,
  });
}

/// Paginated directory browse result
class DirectoryBrowseResult {
  final List<DirectoryEntryInfo> entries;
  final String? nextCursor;
  final int totalCount;

  const DirectoryBrowseResult({
    required this.entries,
    this.nextCursor,
    required this.totalCount,
  });
}

// ============================================================================
// Feed Store Types
// ============================================================================

/// Feed metadata from GET/CREATE/LIST operations
class FeedInfo {
  final String path;
  final String title;
  final String description;
  final int currentSequence;
  final int? lastEntryAt;
  final int createdAt;

  const FeedInfo({
    required this.path,
    required this.title,
    required this.description,
    required this.currentSequence,
    this.lastEntryAt,
    required this.createdAt,
  });
}

/// A single feed entry
class FeedEntry {
  final int sequence;
  final String? entryType;
  final Uint8List content;
  final String contentHash;
  final int createdAt;
  final String? createdBy;

  const FeedEntry({
    required this.sequence,
    this.entryType,
    required this.content,
    required this.contentHash,
    required this.createdAt,
    this.createdBy,
  });
}

/// Result from appending a feed entry
class FeedAppendResult {
  final int status;
  final int sequence;
  final String etag;

  const FeedAppendResult({
    required this.status,
    required this.sequence,
    required this.etag,
  });

  bool get isSuccess => status == 201;
}

/// Result from getting feed entries (range query)
class FeedEntriesResult {
  final List<FeedEntry> entries;
  final bool hasMore;
  final int? nextSequence;

  const FeedEntriesResult({
    required this.entries,
    required this.hasMore,
    this.nextSequence,
  });
}

/// Result for a single feed within a batch feed retrieval
class BatchFeedResult {
  final List<FeedEntry> entries;
  final bool hasMore;
  final String? error;

  const BatchFeedResult({
    required this.entries,
    required this.hasMore,
    this.error,
  });
}

/// Result from batch getting entries across multiple feeds
class BatchFeedEntriesResult {
  /// Results keyed by "ownerPeerId/path"
  final Map<String, BatchFeedResult> feeds;

  const BatchFeedEntriesResult({required this.feeds});
}

// ============================================================================
// Collection Store Types
// ============================================================================

/// Collection metadata from GET/CREATE/LIST operations
class CollectionInfo {
  final String path;
  final String name;
  final int recordCount;
  final int? lastModifiedAt;
  final int createdAt;

  const CollectionInfo({
    required this.path,
    required this.name,
    required this.recordCount,
    this.lastModifiedAt,
    required this.createdAt,
  });
}

/// A single collection item
class CollectionItem {
  final String key;
  final Map<String, dynamic> content;
  final String contentHash;
  final int version;
  final int createdAt;
  final int updatedAt;

  const CollectionItem({
    required this.key,
    required this.content,
    required this.contentHash,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });
}

/// Result from putting a collection item
class CollectionItemResult {
  final int status;
  final String? etag;
  final int? version;
  final bool created;

  const CollectionItemResult({
    required this.status,
    this.etag,
    this.version,
    required this.created,
  });

  bool get isSuccess => status == 200 || status == 201;
  bool get isConflict => status == 409;
  bool get isForbidden => status == 403;
}

/// Result from querying a collection
class CollectionQueryResult {
  final List<CollectionItem> items;
  final int totalCount;
  final bool hasMore;

  const CollectionQueryResult({
    required this.items,
    required this.totalCount,
    required this.hasMore,
  });
}

/// Result from listing collection keys
class CollectionKeysResult {
  final List<String> keys;
  final int totalCount;
  final bool hasMore;

  const CollectionKeysResult({
    required this.keys,
    required this.totalCount,
    required this.hasMore,
  });
}


/// Mailbox Management Agent (MMA) Protocol definitions
///
/// Provides remote mailbox management capabilities including creation,
/// ACL management, configuration updates, and deletion.
///
/// Renamed from mailbox_mgmt_protocol.dart for architectural consistency.
library;

import 'package:dart_libp2p/core/peer/peer_id.dart';
import '../../core/mailbox_address.dart';
import '../../core/mailbox_types.dart';

/// Protocol ID for mailbox management operations (MMA)
const String adminProtocolId = '/sf-network/admin/1.0.0';

// ============================================================================
// Helper Functions
// ============================================================================

/// Parse mailbox address from string format
MailboxAddress parseAddress(String addressStr, {MailboxType? type}) {
  // If type is provided explicitly, use it; otherwise try to parse from address string
  if (type != null) {
    return MailboxAddress.parse(addressStr, type: type);
  }

  // Address format: peerId/type/folder
  final parts = addressStr.split('/');
  if (parts.length < 2) {
    throw FormatException('Invalid mailbox address format: $addressStr');
  }

  final parsedType = MailboxType.values.firstWhere(
    (e) => e.name == parts[1],
    orElse: () => MailboxType.private,
  );

  return MailboxAddress.parse(addressStr, type: parsedType);
}

// ============================================================================
// Request Types
// ============================================================================

/// Base class for all mailbox management requests
abstract class MailboxMgmtRequest {
  String get operationType;
  Map<String, dynamic> toJson();
}

/// Request to create a new mailbox
class CreateMailboxRequest implements MailboxMgmtRequest {
  final MailboxAddress address;
  final int? maxMessages;
  final int? retentionDays;
  final int? retentionCount; // For public mailboxes

  const CreateMailboxRequest({
    required this.address,
    this.maxMessages,
    this.retentionDays,
    this.retentionCount,
  });

  @override
  String get operationType => 'createMailbox';

  @override
  Map<String, dynamic> toJson() => {
        'operationType': operationType,
        'address': address.toString(),
        'type': address.type.name,
        'maxMessages': maxMessages,
        'retentionDays': retentionDays,
        'retentionCount': retentionCount,
      };

  factory CreateMailboxRequest.fromJson(Map<String, dynamic> json) {
    // Use explicit type field from JSON instead of parsing from address string
    final typeStr = json['type'] as String;
    final type = MailboxType.values.firstWhere((e) => e.name == typeStr);

    return CreateMailboxRequest(
      address: parseAddress(json['address'] as String, type: type),
      maxMessages: json['maxMessages'] as int?,
      retentionDays: json['retentionDays'] as int?,
      retentionCount: json['retentionCount'] as int?,
    );
  }
}

/// Request to grant access to a peer
class GrantAccessRequest implements MailboxMgmtRequest {
  final MailboxAddress address;
  final PeerId targetPeerId;
  final AccessMode accessMode;

  const GrantAccessRequest({
    required this.address,
    required this.targetPeerId,
    required this.accessMode,
  });

  @override
  String get operationType => 'grantAccess';

  @override
  Map<String, dynamic> toJson() => {
        'operationType': operationType,
        'address': address.toString(),
        'type': address.type.name,
        'targetPeerId': targetPeerId.toString(),
        'accessMode': accessMode.name,
      };

  factory GrantAccessRequest.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = MailboxType.values.firstWhere((e) => e.name == typeStr);

    return GrantAccessRequest(
      address: parseAddress(json['address'] as String, type: type),
      targetPeerId: PeerId.fromString(json['targetPeerId'] as String),
      accessMode: AccessMode.values.firstWhere((e) => e.name == json['accessMode']),
    );
  }
}

/// Request to revoke access from a peer
class RevokeAccessRequest implements MailboxMgmtRequest {
  final MailboxAddress address;
  final PeerId targetPeerId;

  const RevokeAccessRequest({
    required this.address,
    required this.targetPeerId,
  });

  @override
  String get operationType => 'revokeAccess';

  @override
  Map<String, dynamic> toJson() => {
        'operationType': operationType,
        'address': address.toString(),
        'type': address.type.name,
        'targetPeerId': targetPeerId.toString(),
      };

  factory RevokeAccessRequest.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = MailboxType.values.firstWhere((e) => e.name == typeStr);

    return RevokeAccessRequest(
      address: parseAddress(json['address'] as String, type: type),
      targetPeerId: PeerId.fromString(json['targetPeerId'] as String),
    );
  }
}

/// Request to list ACL entries for a mailbox
class ListACLRequest implements MailboxMgmtRequest {
  final MailboxAddress address;

  const ListACLRequest({required this.address});

  @override
  String get operationType => 'listACL';

  @override
  Map<String, dynamic> toJson() => {
        'operationType': operationType,
        'address': address.toString(),
        'type': address.type.name,
      };

  factory ListACLRequest.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = MailboxType.values.firstWhere((e) => e.name == typeStr);

    return ListACLRequest(
      address: parseAddress(json['address'] as String, type: type),
    );
  }
}

/// Request to update mailbox configuration
class UpdateMailboxConfigRequest implements MailboxMgmtRequest {
  final MailboxAddress address;
  final int? maxMessages;
  final int? retentionDays;
  final int? retentionCount;

  const UpdateMailboxConfigRequest({
    required this.address,
    this.maxMessages,
    this.retentionDays,
    this.retentionCount,
  });

  @override
  String get operationType => 'updateConfig';

  @override
  Map<String, dynamic> toJson() => {
        'operationType': operationType,
        'address': address.toString(),
        'type': address.type.name,
        'maxMessages': maxMessages,
        'retentionDays': retentionDays,
        'retentionCount': retentionCount,
      };

  factory UpdateMailboxConfigRequest.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = MailboxType.values.firstWhere((e) => e.name == typeStr);

    return UpdateMailboxConfigRequest(
      address: parseAddress(json['address'] as String, type: type),
      maxMessages: json['maxMessages'] as int?,
      retentionDays: json['retentionDays'] as int?,
      retentionCount: json['retentionCount'] as int?,
    );
  }
}

/// Request to delete a mailbox
class DeleteMailboxRequest implements MailboxMgmtRequest {
  final MailboxAddress address;

  const DeleteMailboxRequest({required this.address});

  @override
  String get operationType => 'deleteMailbox';

  @override
  Map<String, dynamic> toJson() => {
        'operationType': operationType,
        'address': address.toString(),
        'type': address.type.name,
      };

  factory DeleteMailboxRequest.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = MailboxType.values.firstWhere((e) => e.name == typeStr);

    return DeleteMailboxRequest(
      address: parseAddress(json['address'] as String, type: type),
    );
  }
}

/// Request to list mailboxes
class ListMailboxesRequest implements MailboxMgmtRequest {
  final PeerId? ownerId; // Optional, defaults to caller

  const ListMailboxesRequest({this.ownerId});

  @override
  String get operationType => 'listMailboxes';

  @override
  Map<String, dynamic> toJson() => {
        'operationType': operationType,
        'ownerId': ownerId?.toString(),
      };

  factory ListMailboxesRequest.fromJson(Map<String, dynamic> json) {
    return ListMailboxesRequest(
      ownerId: json['ownerId'] != null ? PeerId.fromString(json['ownerId'] as String) : null,
    );
  }
}

/// Request to get mailbox info
class GetMailboxInfoRequest implements MailboxMgmtRequest {
  final MailboxAddress address;

  const GetMailboxInfoRequest({required this.address});

  @override
  String get operationType => 'getMailboxInfo';

  @override
  Map<String, dynamic> toJson() => {
        'operationType': operationType,
        'address': address.toString(),
        'type': address.type.name,
      };

  factory GetMailboxInfoRequest.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = MailboxType.values.firstWhere((e) => e.name == typeStr);

    return GetMailboxInfoRequest(
      address: parseAddress(json['address'] as String, type: type),
    );
  }
}

/// Request to query server capacity
class QueryCapacityRequest implements MailboxMgmtRequest {
  const QueryCapacityRequest();

  @override
  String get operationType => 'queryCapacity';

  @override
  Map<String, dynamic> toJson() => {
        'operationType': operationType,
      };

  factory QueryCapacityRequest.fromJson(Map<String, dynamic> json) {
    return const QueryCapacityRequest();
  }
}

// ============================================================================
// Response Types
// ============================================================================

/// Generic response for mailbox operations
class MailboxOperationResponse {
  final bool success;
  final String? errorMessage;
  final dynamic data; // Operation-specific data

  const MailboxOperationResponse({
    required this.success,
    this.errorMessage,
    this.data,
  });

  Map<String, dynamic> toJson() => {
        'success': success,
        'errorMessage': errorMessage,
        'data': data,
      };

  factory MailboxOperationResponse.fromJson(Map<String, dynamic> json) {
    return MailboxOperationResponse(
      success: json['success'] as bool,
      errorMessage: json['errorMessage'] as String?,
      data: json['data'],
    );
  }
}

/// ACL entry information
class ACLEntry {
  final PeerId peerId;
  final AccessMode accessMode;
  final DateTime grantedAt;

  const ACLEntry({
    required this.peerId,
    required this.accessMode,
    required this.grantedAt,
  });

  Map<String, dynamic> toJson() => {
        'peerId': peerId.toString(),
        'accessMode': accessMode.name,
        'grantedAt': grantedAt.millisecondsSinceEpoch,
      };

  factory ACLEntry.fromJson(Map<String, dynamic> json) {
    return ACLEntry(
      peerId: PeerId.fromString(json['peerId'] as String),
      accessMode: AccessMode.values.firstWhere((e) => e.name == json['accessMode']),
      grantedAt: DateTime.fromMillisecondsSinceEpoch(json['grantedAt'] as int),
    );
  }
}

/// Mailbox information
class MailboxInfo {
  final MailboxAddress address;
  final int messageCount;
  final DateTime createdAt;
  final DateTime lastAccessedAt;
  final int maxMessages;
  final int retentionDays;
  final int? retentionCount;

  const MailboxInfo({
    required this.address,
    required this.messageCount,
    required this.createdAt,
    required this.lastAccessedAt,
    required this.maxMessages,
    required this.retentionDays,
    this.retentionCount,
  });

  Map<String, dynamic> toJson() => {
        'address': address.toString(),
        'type': address.type.name,
        'messageCount': messageCount,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'lastAccessedAt': lastAccessedAt.millisecondsSinceEpoch,
        'maxMessages': maxMessages,
        'retentionDays': retentionDays,
        'retentionCount': retentionCount,
      };

  factory MailboxInfo.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = MailboxType.values.firstWhere((e) => e.name == typeStr);

    return MailboxInfo(
      address: parseAddress(json['address'] as String, type: type),
      messageCount: (json['messageCount'] as int?) ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch((json['createdAt'] as int?) ?? 0),
      lastAccessedAt: DateTime.fromMillisecondsSinceEpoch((json['lastAccessedAt'] as int?) ?? 0),
      maxMessages: (json['maxMessages'] as int?) ?? 0,
      retentionDays: (json['retentionDays'] as int?) ?? 0,
      retentionCount: json['retentionCount'] as int?,
    );
  }
}

// ============================================================================
// Error Types
// ============================================================================

/// Base exception for mailbox management errors
class MailboxManagementError implements Exception {
  final String message;
  final String? details;

  MailboxManagementError(this.message, {this.details});

  @override
  String toString() => 'MailboxManagementError: $message${details != null ? ' ($details)' : ''}';
}

/// Exception for unauthorized mailbox operations
class UnauthorizedMailboxOperation extends MailboxManagementError {
  UnauthorizedMailboxOperation(super.message, {super.details});

  @override
  String toString() => 'UnauthorizedMailboxOperation: $message${details != null ? ' ($details)' : ''}';
}

/// Exception for mailbox not found
class MailboxNotFound extends MailboxManagementError {
  MailboxNotFound(String mailboxPath, {String? details}) : super('Mailbox not found: $mailboxPath', details: details);
}

/// Exception for mailbox already exists
class MailboxAlreadyExists extends MailboxManagementError {
  MailboxAlreadyExists(String mailboxPath, {String? details})
      : super('Mailbox already exists: $mailboxPath', details: details);
}

/// Exception for invalid mailbox configuration
class InvalidMailboxConfig extends MailboxManagementError {
  InvalidMailboxConfig(super.message, {super.details});
}

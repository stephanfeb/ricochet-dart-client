/// Frame encoding/decoding for mailbox management protocol (MMA)
///
/// Handles JSON-based encoding of requests and responses with length prefixing.
/// Renamed from mailbox_mgmt_frame.dart for architectural consistency.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'admin_protocol.dart';

/// Frame encoder/decoder for mailbox management operations
class AdminFrame {
  /// Encode request to JSON bytes with length prefix
  static Uint8List encodeRequest(MailboxMgmtRequest request) {
    final json = jsonEncode(request.toJson());
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Decode request from JSON bytes
  static MailboxMgmtRequest decodeRequest(Uint8List bytes) {
    try {
      final json = utf8.decode(bytes);
      final data = jsonDecode(json) as Map<String, dynamic>;

      final operation = data['operationType'] as String;

      switch (operation) {
        case 'createMailbox':
          return CreateMailboxRequest.fromJson(data);
        case 'grantAccess':
          return GrantAccessRequest.fromJson(data);
        case 'revokeAccess':
          return RevokeAccessRequest.fromJson(data);
        case 'listACL':
          return ListACLRequest.fromJson(data);
        case 'updateConfig':
          return UpdateMailboxConfigRequest.fromJson(data);
        case 'deleteMailbox':
          return DeleteMailboxRequest.fromJson(data);
        case 'listMailboxes':
          return ListMailboxesRequest.fromJson(data);
        case 'getMailboxInfo':
          return GetMailboxInfoRequest.fromJson(data);
        case 'queryCapacity':
          return QueryCapacityRequest.fromJson(data);
        default:
          throw FormatException('Unknown operation type: $operation');
      }
    } catch (e) {
      throw FormatException('Failed to decode mailbox management request: $e');
    }
  }

  /// Encode response to JSON bytes
  static Uint8List encodeResponse(MailboxOperationResponse response) {
    final json = jsonEncode(response.toJson());
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Decode response from JSON bytes
  static MailboxOperationResponse decodeResponse(Uint8List bytes) {
    try {
      final json = utf8.decode(bytes);
      final data = jsonDecode(json) as Map<String, dynamic>;
      return MailboxOperationResponse.fromJson(data);
    } catch (e) {
      throw FormatException('Failed to decode mailbox management response: $e');
    }
  }

  /// Encode ACL entry list to JSON
  static List<Map<String, dynamic>> encodeACLList(List<ACLEntry> entries) {
    return entries.map((e) => e.toJson()).toList();
  }

  /// Decode ACL entry list from JSON
  static List<ACLEntry> decodeACLList(List<dynamic> data) {
    return data.cast<Map<String, dynamic>>().map((e) => ACLEntry.fromJson(e)).toList();
  }

  /// Encode mailbox info list to JSON
  static List<Map<String, dynamic>> encodeMailboxInfoList(List<MailboxInfo> mailboxes) {
    return mailboxes.map((m) => m.toJson()).toList();
  }

  /// Decode mailbox info list from JSON
  static List<MailboxInfo> decodeMailboxInfoList(List<dynamic> data) {
    return data.cast<Map<String, dynamic>>().map((m) => MailboxInfo.fromJson(m)).toList();
  }
}

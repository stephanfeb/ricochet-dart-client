/// SFA Frame Encoding/Decoding
///
/// Handles serialization of Store Feed Access protocol messages
/// including CREATE, GET, APPEND, DELETE, and LIST operations.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:dart_libp2p/core/peer/peer_id.dart';

/// Feed frame encoding/decoding for SFA protocol
class FeedFrame {
  /// Get operation type from request bytes
  static String getOperation(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return data['operation'] as String? ?? 'unknown';
  }

  // ============================================================================
  // Request Encoding/Decoding
  // ============================================================================

  /// Encode feed request
  static Uint8List encodeRequest({
    required String operation,
    required PeerId ownerPeerId,
    String? path,
    Map<String, String>? headers,
    Uint8List? body,
    String? title,
    String? description,
    String? entryType,
    int? sequenceNumber,
    int? fromSequence,
    int? toSequence,
    int? limit,
    bool collaborative = false,
  }) {
    final data = <String, dynamic>{
      'operation': operation,
      'ownerPeerId': ownerPeerId.toString(),
    };

    if (path != null) data['path'] = path;
    if (headers != null && headers.isNotEmpty) data['headers'] = headers;
    if (body != null) data['body'] = base64Encode(body);
    if (title != null) data['title'] = title;
    if (description != null) data['description'] = description;
    if (entryType != null) data['entryType'] = entryType;
    if (sequenceNumber != null) data['sequenceNumber'] = sequenceNumber;
    if (fromSequence != null) data['fromSequence'] = fromSequence;
    if (toSequence != null) data['toSequence'] = toSequence;
    if (limit != null) data['limit'] = limit;
    if (collaborative) data['collaborative'] = true;

    final json = jsonEncode(data);
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Decode feed request
  static FeedRequest decodeRequest(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;

    final headers = data['headers'] != null
        ? Map<String, String>.from(data['headers'] as Map)
        : <String, String>{};

    final body = data['body'] != null
        ? base64Decode(data['body'] as String)
        : null;

    return FeedRequest(
      operation: data['operation'] as String,
      ownerPeerId: PeerId.fromString(data['ownerPeerId'] as String),
      path: data['path'] as String?,
      headers: headers,
      body: body,
      title: data['title'] as String?,
      description: data['description'] as String?,
      entryType: data['entryType'] as String?,
      sequenceNumber: data['sequenceNumber'] as int?,
      fromSequence: data['fromSequence'] as int?,
      toSequence: data['toSequence'] as int?,
      limit: data['limit'] as int?,
      collaborative: data['collaborative'] as bool? ?? false,
    );
  }

  // ============================================================================
  // Response Encoding/Decoding
  // ============================================================================

  /// Encode feed response
  static Uint8List encodeResponse({
    required int status,
    Map<String, dynamic>? headers,
    Uint8List? body,
  }) {
    final data = <String, dynamic>{
      'status': status,
    };

    if (headers != null && headers.isNotEmpty) data['headers'] = headers;
    if (body != null) data['body'] = base64Encode(body);

    final json = jsonEncode(data);
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Decode feed response
  static FeedFrameResponse decodeResponse(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;

    final headers = data['headers'] != null
        ? Map<String, dynamic>.from(data['headers'] as Map)
        : <String, dynamic>{};

    final body = data['body'] != null
        ? base64Decode(data['body'] as String)
        : null;

    return FeedFrameResponse(
      status: data['status'] as int,
      headers: headers,
      body: body,
    );
  }

  // ============================================================================
  // Error Response
  // ============================================================================

  /// Encode error response
  static Uint8List encodeError(int status, String errorMessage) {
    final data = <String, dynamic>{
      'status': status,
      'headers': {
        'Error': errorMessage,
      },
    };

    final json = jsonEncode(data);
    return Uint8List.fromList(utf8.encode(json));
  }
}

/// Feed request wrapper
class FeedRequest {
  final String operation;
  final PeerId ownerPeerId;
  final String? path;
  final Map<String, String> headers;
  final Uint8List? body;
  final String? title;
  final String? description;
  final String? entryType;
  final int? sequenceNumber;
  final int? fromSequence;
  final int? toSequence;
  final int? limit;
  final bool collaborative;

  FeedRequest({
    required this.operation,
    required this.ownerPeerId,
    this.path,
    required this.headers,
    this.body,
    this.title,
    this.description,
    this.entryType,
    this.sequenceNumber,
    this.fromSequence,
    this.toSequence,
    this.limit,
    this.collaborative = false,
  });
}

/// Feed response wrapper
class FeedFrameResponse {
  final int status;
  final Map<String, dynamic> headers;
  final Uint8List? body;

  FeedFrameResponse({
    required this.status,
    required this.headers,
    this.body,
  });

  String? get etag => headers['ETag'] as String?;
  int? get sequence => headers['X-Sequence'] as int?;
  String? get entryType => headers['X-Entry-Type'] as String?;
  bool? get hasMore => headers['X-Has-More'] as bool?;
  int? get nextSequence => headers['X-Next-Sequence'] as int?;
  String? get error => headers['Error'] as String?;

  bool get isSuccess => status >= 200 && status < 300;
  bool get isNotFound => status == 404;
  bool get isForbidden => status == 403;
  bool get isTooManyRequests => status == 429;
}

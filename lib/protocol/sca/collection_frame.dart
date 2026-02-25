/// SCA Frame Encoding/Decoding
///
/// Handles serialization of Store Collection Access protocol messages
/// including CREATE, GET, PUT, DELETE, LIST, and QUERY operations.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:dart_libp2p/core/peer/peer_id.dart';

/// Collection frame encoding/decoding for SCA protocol
class CollectionFrame {
  /// Get operation type from request bytes
  static String getOperation(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return data['operation'] as String? ?? 'unknown';
  }

  // ============================================================================
  // Request Encoding/Decoding
  // ============================================================================

  /// Encode collection request
  static Uint8List encodeRequest({
    required String operation,
    required PeerId ownerPeerId,
    String? path,
    String? key,
    Map<String, String>? headers,
    Uint8List? body,
    String? name,
    Map<String, dynamic>? filter,
    String? sortField,
    bool? sortAsc,
    int? limit,
    int? offset,
  }) {
    final data = <String, dynamic>{
      'operation': operation,
      'ownerPeerId': ownerPeerId.toString(),
    };

    if (path != null) data['path'] = path;
    if (key != null) data['key'] = key;
    if (headers != null && headers.isNotEmpty) data['headers'] = headers;
    if (body != null) data['body'] = base64Encode(body);
    if (name != null) data['name'] = name;
    if (filter != null) data['filter'] = filter;
    if (sortField != null) data['sortField'] = sortField;
    if (sortAsc != null) data['sortAsc'] = sortAsc;
    if (limit != null) data['limit'] = limit;
    if (offset != null) data['offset'] = offset;

    final json = jsonEncode(data);
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Decode collection request
  static CollectionRequest decodeRequest(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;

    final headers = data['headers'] != null
        ? Map<String, String>.from(data['headers'] as Map)
        : <String, String>{};

    final body = data['body'] != null
        ? base64Decode(data['body'] as String)
        : null;

    return CollectionRequest(
      operation: data['operation'] as String,
      ownerPeerId: PeerId.fromString(data['ownerPeerId'] as String),
      path: data['path'] as String?,
      key: data['key'] as String?,
      headers: headers,
      body: body,
      name: data['name'] as String?,
      filter: data['filter'] as Map<String, dynamic>?,
      sortField: data['sortField'] as String?,
      sortAsc: data['sortAsc'] as bool?,
      limit: data['limit'] as int?,
      offset: data['offset'] as int?,
    );
  }

  // ============================================================================
  // Response Encoding/Decoding
  // ============================================================================

  /// Encode collection response
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

  /// Decode collection response
  static CollectionFrameResponse decodeResponse(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;

    final headers = data['headers'] != null
        ? Map<String, dynamic>.from(data['headers'] as Map)
        : <String, dynamic>{};

    final body = data['body'] != null
        ? base64Decode(data['body'] as String)
        : null;

    return CollectionFrameResponse(
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

/// Collection request wrapper
class CollectionRequest {
  final String operation;
  final PeerId ownerPeerId;
  final String? path;
  final String? key;
  final Map<String, String> headers;
  final Uint8List? body;
  final String? name;
  final Map<String, dynamic>? filter;
  final String? sortField;
  final bool? sortAsc;
  final int? limit;
  final int? offset;

  CollectionRequest({
    required this.operation,
    required this.ownerPeerId,
    this.path,
    this.key,
    required this.headers,
    this.body,
    this.name,
    this.filter,
    this.sortField,
    this.sortAsc,
    this.limit,
    this.offset,
  });

  String? get ifMatch => headers['If-Match'];
}

/// Collection response wrapper
class CollectionFrameResponse {
  final int status;
  final Map<String, dynamic> headers;
  final Uint8List? body;

  CollectionFrameResponse({
    required this.status,
    required this.headers,
    this.body,
  });

  String? get etag => headers['ETag'] as String?;
  int? get version => headers['X-Version'] as int?;
  int? get totalCount => headers['X-Total-Count'] as int?;
  bool? get hasMore => headers['X-Has-More'] as bool?;
  int? get recordCount => headers['X-Record-Count'] as int?;
  String? get error => headers['Error'] as String?;

  bool get isSuccess => status >= 200 && status < 300;
  bool get isNotFound => status == 404;
  bool get isForbidden => status == 403;
  bool get isConflict => status == 409;
  bool get isTooManyRequests => status == 429;
}

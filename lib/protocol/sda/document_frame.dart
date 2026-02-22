/// SDA Frame Encoding/Decoding
///
/// Handles serialization of Store Document Access protocol messages
/// including GET, PUT, and HEAD operations.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:logging/logging.dart';

/// Document frame encoding/decoding for SDA protocol
class DocumentFrame {
  /// Get operation type from request bytes
  static String getOperation(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return data['operation'] as String? ?? 'unknown';
  }

  // ============================================================================
  // Request Encoding/Decoding
  // ============================================================================

  /// Encode document request (GET, PUT, HEAD)
  static Uint8List encodeRequest({
    required String operation,
    required PeerId ownerPeerId,
    required String path,
    Map<String, String>? headers,
    Uint8List? body,
  }) {
    final data = <String, dynamic>{
      'operation': operation,
      'ownerPeerId': ownerPeerId.toString(),
      'path': path,
    };

    if (headers != null && headers.isNotEmpty) {
      data['headers'] = headers;
    }

    if (body != null) {
      data['body'] = base64Encode(body);
    }

    final json = jsonEncode(data);
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Decode document request
  static DocumentRequest decodeRequest(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;

    final headers = data['headers'] != null
        ? Map<String, String>.from(data['headers'] as Map)
        : <String, String>{};

    final body = data['body'] != null
        ? base64Decode(data['body'] as String)
        : null;

    return DocumentRequest(
      operation: data['operation'] as String,
      ownerPeerId: PeerId.fromString(data['ownerPeerId'] as String),
      path: data['path'] as String,
      headers: headers,
      body: body,
    );
  }

  // ============================================================================
  // Response Encoding/Decoding
  // ============================================================================

  /// Encode document response
  static Uint8List encodeResponse({
    required int status,
    Map<String, dynamic>? headers,
    Uint8List? body,
  }) {
    final data = <String, dynamic>{
      'status': status,
    };

    if (headers != null && headers.isNotEmpty) {
      data['headers'] = headers;
    }

    if (body != null) {
      final base64Body = base64Encode(body);
      data['body'] = base64Body;
    }

    final json = jsonEncode(data);
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Decode document response
  static DocumentResponse decodeResponse(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;

    final headers = data['headers'] != null
        ? Map<String, dynamic>.from(data['headers'] as Map)
        : <String, dynamic>{};

    final body = data['body'] != null
        ? base64Decode(data['body'] as String)
        : null;

    return DocumentResponse(
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
        'error': errorMessage,
      },
    };

    final json = jsonEncode(data);
    return Uint8List.fromList(utf8.encode(json));
  }
}

/// Document request wrapper
class DocumentRequest {
  final String operation;
  final PeerId ownerPeerId;
  final String path;
  final Map<String, String> headers;
  final Uint8List? body;

  DocumentRequest({
    required this.operation,
    required this.ownerPeerId,
    required this.path,
    required this.headers,
    this.body,
  });

  String? get ifNoneMatch => headers['If-None-Match'];
  String? get ifMatch => headers['If-Match'];
  String? get contentType => headers['Content-Type'];
}

/// Document response wrapper
class DocumentResponse {
  final int status;
  final Map<String, dynamic> headers;
  final Uint8List? body;

  DocumentResponse({
    required this.status,
    required this.headers,
    this.body,
  });

  String? get etag => headers['ETag'] as String?;
  String? get contentType => headers['Content-Type'] as String?;
  int? get lastModified => headers['Last-Modified'] as int?;
  int? get contentLength => headers['Content-Length'] as int?;
  String? get error => headers['error'] as String?;

  bool get isSuccess => status >= 200 && status < 300;
  bool get isNotModified => status == 304;
  bool get isNotFound => status == 404;
  bool get isConflict => status == 409;
  bool get isForbidden => status == 403;
}


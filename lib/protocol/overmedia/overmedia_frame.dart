/// OverMedia Frame Encoding/Decoding
///
/// Shared frame utilities for all OverMedia protocol handlers.
/// Encodes requests as JSON and decodes JSON responses.
library;

import 'dart:convert';
import 'dart:typed_data';

/// OverMedia frame encoding/decoding
class OverMediaFrame {
  /// Encode a request map to bytes
  static Uint8List encodeRequest(Map<String, dynamic> request) {
    final json = jsonEncode(request);
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Decode response bytes to an [OverMediaResponse]
  static OverMediaResponse decodeResponse(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return OverMediaResponse(data);
  }
}

/// OverMedia response wrapper
class OverMediaResponse {
  final Map<String, dynamic> data;

  OverMediaResponse(this.data);

  bool get success => data['success'] as bool? ?? false;
  String? get error => data['error'] as String?;

  /// Access arbitrary response fields
  dynamic operator [](String key) => data[key];
}

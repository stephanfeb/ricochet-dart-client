/// MSA Frame Encoding/Decoding
///
/// Handles serialization of submission protocol messages.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../core/sf_message.dart';

/// Submission frame encoding/decoding for MSA protocol
class SubmissionFrame {
  /// Encode an SFMessage for submission
  static Uint8List encodeMessage(SFMessage message) {
    final json = jsonEncode(message.toJson());
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Decode an SFMessage from submission frame
  static SFMessage decodeMessage(Uint8List frameBytes) {
    try {
      final json = utf8.decode(frameBytes);
      final data = jsonDecode(json) as Map<String, dynamic>;
      return SFMessage.fromJson(data);
    } catch (e) {
      throw FormatException('Failed to decode submission frame: $e');
    }
  }

  /// Encode store acknowledgment
  static Uint8List encodeAck(StoreAck ack) {
    final data = <String, dynamic>{
      'messageId': ack.messageId,
      'success': ack.success,
      'errorMessage': ack.errorMessage,
      'estimatedDeliveryTime': ack.estimatedDeliveryTime,
    };

    final json = jsonEncode(data);
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Decode store acknowledgment
  static StoreAck decodeAck(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;

    return StoreAck(
      messageId: data['messageId'] as String,
      success: data['success'] as bool,
      errorMessage: data['errorMessage'] as String?,
      estimatedDeliveryTime: data['estimatedDeliveryTime'] as int?,
    );
  }
}


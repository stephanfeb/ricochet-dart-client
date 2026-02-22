/// MAA Frame Encoding/Decoding
///
/// Handles serialization of access protocol messages including
/// retrieve, mark delivered, update flags, expunge, and delete.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:dart_libp2p/core/peer/peer_id.dart';

import '../../core/sf_message.dart';
import '../../core/message_types.dart';

/// Access frame encoding/decoding for MAA protocol
class AccessFrame {
  /// Get operation type from request bytes
  static String getOperationType(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return data['operationType'] as String? ?? 'unknown';
  }

  // ============================================================================
  // Retrieve Messages
  // ============================================================================

  /// Encode retrieve messages request
  static Uint8List encodeRetrieveRequest(RetrieveMessagesRequest request) {
    final data = <String, dynamic>{
      'operationType': 'retrieve',
      'peerId': request.peerId.toString(),
      'folderPath': request.folderPath,
      'fromSequence': request.fromSequence,
      'maxMessages': request.maxMessages,
      'minPriority': request.minPriority?.value,
    };

    final json = jsonEncode(data);
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Decode retrieve messages request
  static RetrieveMessagesRequest decodeRetrieveRequest(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;

    return RetrieveMessagesRequest(
      peerId: PeerId.fromString(data['peerId'] as String),
      folderPath: data['folderPath'] as String?,
      fromSequence: data['fromSequence'] as int?,
      maxMessages: data['maxMessages'] as int?,
      minPriority: data['minPriority'] != null
          ? MessagePriority.fromValue(data['minPriority'] as int)
          : null,
    );
  }

  /// Encode retrieve messages response
  static Uint8List encodeRetrieveResponse(RetrieveMessagesResponse response) {
    // Encode each message
    final encodedMessages = response.messages.map((m) => _encodeMessage(m)).toList();

    final metadata = <String, dynamic>{
      'hasMore': response.hasMore,
      'messageCount': response.messages.length,
    };

    final metadataBytes = utf8.encode(jsonEncode(metadata));
    final metadataLength = metadataBytes.length;

    // Calculate total size
    int totalSize = 4; // metadata length (4 bytes)
    totalSize += metadataLength;
    for (final msgBytes in encodedMessages) {
      totalSize += 4; // message length (4 bytes)
      totalSize += msgBytes.length;
    }

    final result = ByteData(totalSize);
    int offset = 0;

    // Write metadata length and data
    result.setUint32(offset, metadataLength);
    offset += 4;
    result.buffer.asUint8List().setRange(offset, offset + metadataLength, metadataBytes);
    offset += metadataLength;

    // Write each message frame
    for (final msgBytes in encodedMessages) {
      result.setUint32(offset, msgBytes.length);
      offset += 4;
      result.buffer.asUint8List().setRange(offset, offset + msgBytes.length, msgBytes);
      offset += msgBytes.length;
    }

    return result.buffer.asUint8List();
  }

  /// Decode retrieve messages response
  static RetrieveMessagesResponse decodeRetrieveResponse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    int offset = 0;

    // Read metadata
    final metadataLength = data.getUint32(offset);
    offset += 4;

    final metadataBytes = bytes.sublist(offset, offset + metadataLength);
    final json = utf8.decode(metadataBytes);
    final metadata = jsonDecode(json) as Map<String, dynamic>;
    offset += metadataLength;

    final hasMore = metadata['hasMore'] as bool;
    final messageCount = metadata['messageCount'] as int;

    // Read message frames
    final messages = <SFMessage>[];
    for (int i = 0; i < messageCount; i++) {
      final msgLength = data.getUint32(offset);
      offset += 4;

      final msgBytes = bytes.sublist(offset, offset + msgLength);
      messages.add(_decodeMessage(msgBytes));
      offset += msgLength;
    }

    return RetrieveMessagesResponse(
      messages: messages,
      hasMore: hasMore,
    );
  }

  // ============================================================================
  // Mark Delivered
  // ============================================================================

  /// Encode mark delivered request
  static Uint8List encodeMarkDelivered(MarkDeliveredRequest request) {
    final json = jsonEncode(request.toJson());
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Decode mark delivered request
  static MarkDeliveredRequest decodeMarkDelivered(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return MarkDeliveredRequest.fromJson(data);
  }

  /// Encode mark delivered acknowledgment
  static Uint8List encodeMarkDeliveredAck(MarkDeliveredAck ack) {
    final json = jsonEncode(ack.toJson());
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Decode mark delivered acknowledgment
  static MarkDeliveredAck decodeMarkDeliveredAck(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return MarkDeliveredAck.fromJson(data);
  }

  // ============================================================================
  // Update Flags
  // ============================================================================

  /// Encode update flags request
  static Uint8List encodeUpdateFlags(UpdateFlagsRequest request) {
    final json = jsonEncode(request.toJson());
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Decode update flags request
  static UpdateFlagsRequest decodeUpdateFlags(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return UpdateFlagsRequest.fromJson(data);
  }

  /// Encode update flags acknowledgment
  static Uint8List encodeUpdateFlagsAck(UpdateFlagsAck ack) {
    final json = jsonEncode(ack.toJson());
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Decode update flags acknowledgment
  static UpdateFlagsAck decodeUpdateFlagsAck(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return UpdateFlagsAck.fromJson(data);
  }

  // ============================================================================
  // Expunge
  // ============================================================================

  /// Encode expunge request
  static Uint8List encodeExpunge(ExpungeRequest request) {
    final json = jsonEncode(request.toJson());
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Decode expunge request
  static ExpungeRequest decodeExpunge(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return ExpungeRequest.fromJson(data);
  }

  /// Encode expunge acknowledgment
  static Uint8List encodeExpungeAck(ExpungeAck ack) {
    final json = jsonEncode(ack.toJson());
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Decode expunge acknowledgment
  static ExpungeAck decodeExpungeAck(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return ExpungeAck.fromJson(data);
  }

  // ============================================================================
  // Delete Messages
  // ============================================================================

  /// Encode delete messages request
  static Uint8List encodeDeleteMessages(DeleteMessagesRequest request) {
    final json = jsonEncode(request.toJson());
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Decode delete messages request
  static DeleteMessagesRequest decodeDeleteMessages(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return DeleteMessagesRequest.fromJson(data);
  }

  /// Encode delete messages acknowledgment
  static Uint8List encodeDeleteMessagesAck(DeleteMessagesAck ack) {
    final json = jsonEncode(ack.toJson());
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Decode delete messages acknowledgment
  static DeleteMessagesAck decodeDeleteMessagesAck(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return DeleteMessagesAck.fromJson(data);
  }

  // ============================================================================
  // Error
  // ============================================================================

  /// Encode error message
  static Uint8List encodeError(String errorMessage) {
    final data = <String, dynamic>{
      'error': errorMessage,
    };

    final json = jsonEncode(data);
    return Uint8List.fromList(utf8.encode(json));
  }

  // ============================================================================
  // Private helpers
  // ============================================================================

  static Uint8List _encodeMessage(SFMessage message) {
    final json = jsonEncode(message.toJson());
    return Uint8List.fromList(utf8.encode(json));
  }

  static SFMessage _decodeMessage(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;
    return SFMessage.fromJson(data);
  }
}


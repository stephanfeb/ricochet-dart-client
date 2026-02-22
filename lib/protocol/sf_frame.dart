import 'dart:typed_data';
import 'dart:convert';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import '../core/message_types.dart';
import '../core/sf_message.dart';

/// Store-and-Forward frame encoding/decoding
/// 
/// S&F frames now use JSON encoding for simplicity and forward compatibility.
/// This supports all message fields including new ones (folderPath, sequenceNumber, etc.)
/// 
/// Frame format:
/// 1. JSON-encoded message (all fields)
/// 
/// Benefits:
/// - Supports variable-length fields (folderPath)
/// - Forward/backward compatible
/// - Easy to extend
/// - Leverages existing SFMessage.toJson()/fromJson()
class SFFrame {
  // Legacy constants kept for reference but not used
  @deprecated
  static const int headerSize = 109;
  @deprecated
  static const int peerIdFieldSize = 40;
  @deprecated
  static const int messageIdSize = 16;
  
  /// Encode S&F message into frame bytes using JSON
  static Uint8List encode(SFMessage message) {
    final json = jsonEncode(message.toJson());
    return Uint8List.fromList(utf8.encode(json));
  }
  
  /// Decode S&F frame bytes into message using JSON
  static SFMessage decode(Uint8List frameBytes) {
    try {
      final json = utf8.decode(frameBytes);
      final data = jsonDecode(json) as Map<String, dynamic>;
      return SFMessage.fromJson(data);
    } catch (e) {
      throw FormatException('Failed to decode SFFrame: $e');
    }
  }
  
  /// Encode store acknowledgment
  static Uint8List encodeStoreAck(StoreAck ack) {
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
  static StoreAck decodeStoreAck(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;
    
    return StoreAck(
      messageId: data['messageId'] as String,
      success: data['success'] as bool,
      errorMessage: data['errorMessage'] as String?,
      estimatedDeliveryTime: data['estimatedDeliveryTime'] as int?,
    );
  }
  
  /// Encode retrieve messages request
  static Uint8List encodeRetrieveRequest(RetrieveMessagesRequest request) {
    final data = <String, dynamic>{
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
    final data = <String, dynamic>{
      'hasMore': response.hasMore,
      'messageCount': response.messages.length,
      'messages': response.messages.map((m) => encode(m)).toList(),
    };
    
    final json = jsonEncode({
      'hasMore': data['hasMore'],
      'messageCount': data['messageCount'],
    });
    
    // Pack: JSON metadata + message frames
    final metadataBytes = utf8.encode(json);
    final metadataLength = metadataBytes.length;
    
    // Calculate total size
    int totalSize = 4; // metadata length (4 bytes)
    totalSize += metadataLength;
    for (final msgBytes in data['messages'] as List) {
      totalSize += 4; // message length (4 bytes)
      totalSize += (msgBytes as Uint8List).length;
    }
    
    final result = ByteData(totalSize);
    int offset = 0;
    
    // Write metadata length and data
    result.setUint32(offset, metadataLength);
    offset += 4;
    result.buffer.asUint8List().setRange(offset, offset + metadataLength, metadataBytes);
    offset += metadataLength;
    
    // Write each message frame
    for (final msgBytes in data['messages'] as List) {
      final bytes = msgBytes as Uint8List;
      result.setUint32(offset, bytes.length);
      offset += 4;
      result.buffer.asUint8List().setRange(offset, offset + bytes.length, bytes);
      offset += bytes.length;
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
      messages.add(decode(msgBytes));
      offset += msgLength;
    }
    
    return RetrieveMessagesResponse(
      messages: messages,
      hasMore: hasMore,
    );
  }
  
  /// Encode server capacity
  static Uint8List encodeCapacity(ServerCapacity capacity) {
    final json = jsonEncode(capacity.toMap());
    return Uint8List.fromList(utf8.encode(json));
  }
  
  /// Decode server capacity
  static ServerCapacity decodeCapacity(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;
    
    return ServerCapacity(
      totalStorageBytes: data['totalStorageBytes'] as int,
      usedStorageBytes: data['usedStorageBytes'] as int,
      availableStorageBytes: data['availableStorageBytes'] as int,
      messageCount: data['messageCount'] as int,
      activeMailboxes: data['activeMailboxes'] as int,
      healthScore: (data['healthScore'] as num).toDouble(),
    );
  }
  
  /// Encode error message
  static Uint8List encodeError(String errorMessage) {
    final data = <String, dynamic>{
      'error': errorMessage,
    };
    
    final json = jsonEncode(data);
    return Uint8List.fromList(utf8.encode(json));
  }
  
  // ============================================================================
  // IMAP-Style Flag Operations Encoding/Decoding
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
  
  /// Decode message flags request to determine operation type
  /// 
  /// Returns a Map containing the operation type and raw data.
  /// Used by MessageFlagsHandler to route requests.
  static Map<String, dynamic> decodeMessageFlagsRequest(Uint8List bytes) {
    final json = utf8.decode(bytes);
    final data = jsonDecode(json) as Map<String, dynamic>;
    
    // Use explicit operationType field (added to all request toJson methods)
    final operationType = data['operationType'] as String? ?? 'unknown';
    
    return {
      'operationType': operationType,
      ...data,
    };
  }
}


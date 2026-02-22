/// Mail Access Agent (MAA) Protocol Handler - Client Side
///
/// Provides client-side static methods for message retrieval and
/// IMAP-style flag operations (read path).
///
/// Protocol ID: /sf-network/access/1.0.0
library;

import 'dart:async';
import 'dart:typed_data';
import 'package:dart_libp2p/core/network/stream.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:logging/logging.dart';

import '../../core/sf_message.dart';
import '../../core/message_types.dart';
import 'access_frame.dart';

/// Mail Access Agent (MAA) - Client-side protocol methods
///
/// Provides static methods for clients to interact with MAA servers
/// for message retrieval and IMAP-style flag operations.
class AccessHandler {
  static const String protocolId = '/sf-network/access/1.0.0';
  static final Logger _logger = Logger('MAA.AccessHandler');

  // ============================================================================
  // Client-side static methods
  // ============================================================================

  /// Retrieve messages (client-side)
  static Future<RetrieveMessagesResponse> retrieveMessages(
    P2PStream stream,
    PeerId peerId, {
    String? folderPath,
    int? fromSequence,
    int? maxMessages,
    MessagePriority? minPriority,
  }) async {
    try {
      final request = RetrieveMessagesRequest(
        peerId: peerId,
        folderPath: folderPath,
        fromSequence: fromSequence,
        maxMessages: maxMessages,
        minPriority: minPriority,
      );

      // Encode and send request with length prefix
      final requestBytes = AccessFrame.encodeRetrieveRequest(request);
      await _writeFrameStatic(stream, requestBytes);

      // Read response
      final responseBytes = await _readFrameStatic(stream);
      return AccessFrame.decodeRetrieveResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error retrieving messages: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Mark messages as delivered (client-side) - sets \Seen flag
  static Future<MarkDeliveredAck> markDelivered(
    P2PStream stream,
    List<String> messageIds, {
    String? folderPath,
  }) async {
    try {
      final request = MarkDeliveredRequest(
        messageIds: messageIds,
        folderPath: folderPath,
      );

      // Encode and send request with length prefix
      final requestBytes = AccessFrame.encodeMarkDelivered(request);
      await _writeFrameStatic(stream, requestBytes);

      // Read acknowledgment
      final ackBytes = await _readFrameStatic(stream);
      return AccessFrame.decodeMarkDeliveredAck(ackBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error marking messages delivered: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Update message flags (client-side) - IMAP STORE
  static Future<UpdateFlagsAck> updateFlags(
    P2PStream stream,
    String messageId, {
    int addFlags = 0,
    int removeFlags = 0,
  }) async {
    try {
      final request = UpdateFlagsRequest(
        messageId: messageId,
        addFlags: addFlags,
        removeFlags: removeFlags,
      );

      // Encode and send request with length prefix
      final requestBytes = AccessFrame.encodeUpdateFlags(request);
      await _writeFrameStatic(stream, requestBytes);

      // Read acknowledgment
      final ackBytes = await _readFrameStatic(stream);
      return AccessFrame.decodeUpdateFlagsAck(ackBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error updating message flags: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Expunge messages (client-side) - IMAP EXPUNGE
  static Future<ExpungeAck> expunge(
    P2PStream stream,
    PeerId peerId, {
    String? folderPath,
  }) async {
    try {
      final request = ExpungeRequest(
        peerId: peerId,
        folderPath: folderPath,
      );

      // Encode and send request with length prefix
      final requestBytes = AccessFrame.encodeExpunge(request);
      await _writeFrameStatic(stream, requestBytes);

      // Read acknowledgment
      final ackBytes = await _readFrameStatic(stream);
      return AccessFrame.decodeExpungeAck(ackBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error expunging messages: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Delete messages immediately (client-side)
  static Future<DeleteMessagesAck> deleteMessages(
    P2PStream stream,
    List<String> messageIds,
  ) async {
    try {
      final request = DeleteMessagesRequest(messageIds: messageIds);

      // Encode and send request with length prefix
      final requestBytes = AccessFrame.encodeDeleteMessages(request);
      await _writeFrameStatic(stream, requestBytes);

      // Read acknowledgment
      final ackBytes = await _readFrameStatic(stream);
      return AccessFrame.decodeDeleteMessagesAck(ackBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error deleting messages: $e', e, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Helper methods
  // ============================================================================

  static Future<void> _writeFrameStatic(P2PStream stream, Uint8List data) async {
    // Combine length prefix and data into single write
    final lengthBytes = ByteData(4)..setUint32(0, data.length);
    final combined = Uint8List(4 + data.length);
    combined.setRange(0, 4, lengthBytes.buffer.asUint8List());
    combined.setRange(4, 4 + data.length, data);

    await stream.write(combined);
  }

  static Future<Uint8List> _readFrameStatic(P2PStream stream) async {
    // Read length prefix (4 bytes) - handle partial reads
    final lengthBytes = await _readExact(stream, 4);
    final length = ByteData.sublistView(lengthBytes).getUint32(0);

    // Read frame data - handle partial reads
    final frameBytes = await _readExact(stream, length);
    return frameBytes;
  }

  /// Helper to read exactly N bytes from a stream, handling partial reads.
  ///
  /// P2PStream.read() may return less data than requested if the stream
  /// buffer doesn't have enough data available yet. This helper loops
  /// until exactly the requested number of bytes are read, or the stream
  /// closes (returns empty Uint8List).
  static Future<Uint8List> _readExact(P2PStream stream, int length) async {
    final buffer = <int>[];

    while (buffer.length < length) {
      final remaining = length - buffer.length;
      final chunk = await stream.read(remaining);

      // Empty read indicates stream closure (EOF or FIN)
      if (chunk.isEmpty) {
        throw StateError(
          'Stream closed after reading ${buffer.length} of $length bytes'
        );
      }

      buffer.addAll(chunk);
    }

    return Uint8List.fromList(buffer);
  }
}

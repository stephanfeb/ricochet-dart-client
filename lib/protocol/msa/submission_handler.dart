/// Mail Submission Agent (MSA) Protocol Handler - Client Side
///
/// Provides client-side static methods for message submission (write path).
///
/// Protocol ID: /sf-network/submit/1.0.0
library;

import 'dart:async';
import 'dart:typed_data';
import 'package:dart_libp2p/core/network/stream.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../../core/sf_message.dart';
import '../../core/message_types.dart';
import '../stream_utils.dart';
import 'submission_frame.dart';

/// Mail Submission Agent (MSA) - Client-side protocol methods
///
/// Provides static methods for clients to submit messages to MSA servers.
class SubmissionHandler {
  static const String protocolId = '/sf-network/submit/1.0.0';
  static final Logger _logger = Logger('MSA.SubmissionHandler');
  static final _uuid = Uuid();

  // ============================================================================
  // Client-side static methods
  // ============================================================================

  /// Submit a message to the server (client-side)
  static Future<StoreAck> submitMessage(
    P2PStream stream,
    PeerId recipientPeerId,
    Uint8List payload, {
    MessagePriority priority = MessagePriority.normal,
    Duration? expiry,
    String? folderPath,
    bool persistent = false,
  }) async {
    try {
      final message = SFMessage.withDefaultExpiry(
        messageId: _uuid.v4(),
        recipientPeerId: recipientPeerId,
        senderPeerId: stream.conn.localPeer,
        payload: payload,
        priority: priority,
        persistent: persistent,
      );

      // Create final message with all parameters
      final finalMessage = SFMessage(
        messageId: message.messageId,
        recipientPeerId: recipientPeerId,
        senderPeerId: stream.conn.localPeer,
        payload: payload,
        priority: priority,
        expiryTimestamp: expiry != null
            ? DateTime.now().add(expiry).millisecondsSinceEpoch
            : message.expiryTimestamp,
        hopCount: message.hopCount,
        flags: message.flags,
        createdTimestamp: message.createdTimestamp,
        folderPath: folderPath,
        persistent: persistent,
      );

      // Encode and send with length prefix
      final frameBytes = SubmissionFrame.encodeMessage(finalMessage);
      await _writeFrameStatic(stream, frameBytes);

      // Read acknowledgment
      final ackBytes = await _readFrameStatic(stream);
      return SubmissionFrame.decodeAck(ackBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error submitting message: $e', e, stackTrace);
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
    // Read length-prefixed frame (accumulates until complete)
    return await StreamUtils.readLengthPrefixedFrame(stream);
  }
}

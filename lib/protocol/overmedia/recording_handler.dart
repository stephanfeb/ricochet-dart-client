/// OverMedia Recording Protocol Handler - Client Side
///
/// Provides client-side static methods for OverMedia recording operations
/// (create, get, track play, delete) over libp2p streams.
///
/// Protocol ID: /overmedia/recordings/1.0.0
library;

import 'dart:typed_data';
import 'package:dart_libp2p/core/network/stream.dart';
import 'package:logging/logging.dart';

import '../stream_utils.dart';
import 'overmedia_frame.dart';

/// OverMedia Recording Handler - Client-side protocol methods
class RecordingHandler {
  static const String protocolId = '/overmedia/recordings/1.0.0';
  static final Logger _logger = Logger('OverMedia.RecordingHandler');

  /// Create a recording entry
  static Future<OverMediaResponse> createRecording(
    P2PStream stream, {
    required String meetingId,
    required String recordingUrl,
    required int durationSeconds,
    required String hostPeerId,
  }) async {
    return _send(stream, {
      'action': 'create',
      'meetingId': meetingId,
      'recordingUrl': recordingUrl,
      'durationSeconds': durationSeconds,
      'hostPeerId': hostPeerId,
    });
  }

  /// Get a recording by ID
  static Future<OverMediaResponse> getRecording(
    P2PStream stream, {
    required String recordingId,
  }) async {
    return _send(stream, {
      'action': 'get',
      'recordingId': recordingId,
    });
  }

  /// Track a recording play
  static Future<OverMediaResponse> trackPlay(
    P2PStream stream, {
    required String recordingId,
    required String listenerPeerId,
  }) async {
    return _send(stream, {
      'action': 'track_play',
      'recordingId': recordingId,
      'listenerPeerId': listenerPeerId,
    });
  }

  /// Delete a recording (host-only)
  static Future<OverMediaResponse> deleteRecording(
    P2PStream stream, {
    required String recordingId,
    required String hostPeerId,
  }) async {
    return _send(stream, {
      'action': 'delete',
      'recordingId': recordingId,
      'hostPeerId': hostPeerId,
    });
  }

  /// Send a raw request map (for forward compatibility)
  static Future<OverMediaResponse> sendRequest(
    P2PStream stream,
    Map<String, dynamic> request,
  ) async {
    return _send(stream, request);
  }

  // ============================================================================
  // Helper methods
  // ============================================================================

  static Future<OverMediaResponse> _send(
    P2PStream stream,
    Map<String, dynamic> request,
  ) async {
    try {
      final requestBytes = OverMediaFrame.encodeRequest(request);
      await _writeFrameStatic(stream, requestBytes);
      final responseBytes = await _readFrameStatic(stream);
      return OverMediaFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error in recording request: $e', e, stackTrace);
      rethrow;
    }
  }

  static Future<void> _writeFrameStatic(
      P2PStream stream, Uint8List data) async {
    final lengthBytes = ByteData(4)..setUint32(0, data.length);
    final combined = Uint8List(4 + data.length);
    combined.setRange(0, 4, lengthBytes.buffer.asUint8List());
    combined.setRange(4, 4 + data.length, data);
    await stream.write(combined);
  }

  static Future<Uint8List> _readFrameStatic(P2PStream stream) async {
    return StreamUtils.readLengthPrefixedFrame(stream);
  }
}

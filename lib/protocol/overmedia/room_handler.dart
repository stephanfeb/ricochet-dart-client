/// OverMedia Room Protocol Handler - Client Side
///
/// Provides client-side static methods for OverMedia room management operations
/// (space metadata, recording control, heartbeat, end room) over libp2p streams.
///
/// Protocol ID: /overmedia/rooms/1.0.0
library;

import 'dart:typed_data';
import 'package:dart_libp2p/core/network/stream.dart';
import 'package:logging/logging.dart';

import '../stream_utils.dart';
import 'overmedia_frame.dart';

/// OverMedia Room Handler - Client-side protocol methods
class RoomHandler {
  static const String protocolId = '/overmedia/rooms/1.0.0';
  static final Logger _logger = Logger('OverMedia.RoomHandler');

  /// Get space metadata
  static Future<OverMediaResponse> getSpaceMetadata(
    P2PStream stream, {
    required String meetingId,
  }) async {
    return _send(stream, {
      'action': 'get_space_metadata',
      'meetingId': meetingId,
    });
  }

  /// Get recording status
  static Future<OverMediaResponse> getRecordingStatus(
    P2PStream stream, {
    required String meetingId,
  }) async {
    return _send(stream, {
      'action': 'get_recording_status',
      'meetingId': meetingId,
    });
  }

  /// Start recording
  static Future<OverMediaResponse> startRecording(
    P2PStream stream, {
    required String meetingId,
    required String hostPeerId,
  }) async {
    return _send(stream, {
      'action': 'start_recording',
      'meetingId': meetingId,
      'hostPeerId': hostPeerId,
    });
  }

  /// Stop recording
  static Future<OverMediaResponse> stopRecording(
    P2PStream stream, {
    required String meetingId,
    required String egressId,
    required String hostPeerId,
  }) async {
    return _send(stream, {
      'action': 'stop_recording',
      'meetingId': meetingId,
      'egressId': egressId,
      'hostPeerId': hostPeerId,
    });
  }

  /// Send heartbeat
  static Future<OverMediaResponse> heartbeat(
    P2PStream stream, {
    required String meetingId,
    required String hostPeerId,
    int? listenerCount,
    int? speakerCount,
    List<Map<String, dynamic>>? activeSpeakers,
  }) async {
    return _send(stream, {
      'action': 'heartbeat',
      'meetingId': meetingId,
      'hostPeerId': hostPeerId,
      if (listenerCount != null) 'listenerCount': listenerCount,
      if (speakerCount != null) 'speakerCount': speakerCount,
      if (activeSpeakers != null) 'activeSpeakers': activeSpeakers,
    });
  }

  /// End a room
  static Future<OverMediaResponse> endRoom(
    P2PStream stream, {
    required String meetingId,
    required String hostPeerId,
  }) async {
    return _send(stream, {
      'action': 'end_room',
      'meetingId': meetingId,
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
      _logger.severe('Error in room request: $e', e, stackTrace);
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

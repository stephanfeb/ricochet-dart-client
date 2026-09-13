/// OverMedia Token Protocol Handler - Client Side
///
/// Provides client-side static methods for OverMedia token operations
/// (create meeting, add/edit participant, get/end meeting) over libp2p streams.
///
/// Protocol ID: /overmedia/tokens/1.0.0
library;

import 'dart:typed_data';
import 'package:dart_libp2p/core/network/stream.dart';
import 'package:logging/logging.dart';

import '../stream_utils.dart';
import 'overmedia_frame.dart';

/// OverMedia Token Handler - Client-side protocol methods
class TokenHandler {
  static const String protocolId = '/overmedia/tokens/1.0.0';
  static final Logger _logger = Logger('OverMedia.TokenHandler');

  /// Create a new meeting
  static Future<OverMediaResponse> createMeeting(
    P2PStream stream, {
    required String title,
    String? description,
    List<String>? tags,
    String? hostName,
    int? expectedSpeakers,
    bool? isPublic,
    bool? recordOnStart,
    bool? liveStreamOnStart,
    bool? allowRequests,
    bool? spotlightEnabled,
    int? spotlightFeeSats,
    int? spotlightDurationSecs,
  }) async {
    return _send(stream, {
      'type': 'create_meeting',
      'title': title,
      if (description != null) 'description': description,
      if (tags != null) 'tags': tags,
      if (hostName != null) 'hostName': hostName,
      if (expectedSpeakers != null) 'expectedSpeakers': expectedSpeakers,
      if (isPublic != null) 'isPublic': isPublic,
      if (recordOnStart != null) 'recordOnStart': recordOnStart,
      if (liveStreamOnStart != null) 'liveStreamOnStart': liveStreamOnStart,
      if (allowRequests != null) 'allowRequests': allowRequests,
      if (spotlightEnabled != null) 'spotlightEnabled': spotlightEnabled,
      if (spotlightFeeSats != null) 'spotlightFeeSats': spotlightFeeSats,
      if (spotlightDurationSecs != null)
        'spotlightDurationSecs': spotlightDurationSecs,
    });
  }

  /// Add a participant to a meeting
  static Future<OverMediaResponse> addParticipant(
    P2PStream stream, {
    required String meetingId,
    required String presetName,
    required String participantName,
    required String targetPeerId,
  }) async {
    return _send(stream, {
      'type': 'add_participant',
      'meetingId': meetingId,
      'presetName': presetName,
      'participantName': participantName,
      'targetPeerId': targetPeerId,
    });
  }

  /// Edit a participant in a meeting
  static Future<OverMediaResponse> editParticipant(
    P2PStream stream, {
    required String meetingId,
    required String presetName,
    required String participantName,
    String? picture,
    required String targetPeerId,
  }) async {
    return _send(stream, {
      'type': 'edit_participant',
      'meetingId': meetingId,
      'presetName': presetName,
      'participantName': participantName,
      if (picture != null) 'picture': picture,
      'targetPeerId': targetPeerId,
    });
  }

  /// Get meeting details
  static Future<OverMediaResponse> getMeeting(
    P2PStream stream, {
    required String meetingId,
  }) async {
    return _send(stream, {
      'type': 'get_meeting',
      'meetingId': meetingId,
    });
  }

  /// End a meeting
  static Future<OverMediaResponse> endMeeting(
    P2PStream stream, {
    required String meetingId,
  }) async {
    return _send(stream, {
      'type': 'end_meeting',
      'meetingId': meetingId,
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
      _logger.severe('Error in token request: $e', e, stackTrace);
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

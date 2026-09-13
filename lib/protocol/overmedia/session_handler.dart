/// OverMedia Session Protocol Handler - Client Side
///
/// Provides client-side static methods for OverMedia session queries
/// (get sessions, active session, participants) over libp2p streams.
///
/// Protocol ID: /overmedia/sessions/1.0.0
library;

import 'dart:typed_data';
import 'package:dart_libp2p/core/network/stream.dart';
import 'package:logging/logging.dart';

import '../stream_utils.dart';
import 'overmedia_frame.dart';

/// OverMedia Session Handler - Client-side protocol methods
class SessionHandler {
  static const String protocolId = '/overmedia/sessions/1.0.0';
  static final Logger _logger = Logger('OverMedia.SessionHandler');

  /// Get all active sessions
  static Future<OverMediaResponse> getSessions(P2PStream stream) async {
    return _send(stream, {
      'action': 'get_sessions',
    });
  }

  /// Get a specific active session
  static Future<OverMediaResponse> getActiveSession(
    P2PStream stream, {
    required String meetingId,
  }) async {
    return _send(stream, {
      'action': 'get_active_session',
      'meetingId': meetingId,
    });
  }

  /// Get participants for a session
  static Future<OverMediaResponse> getSessionParticipants(
    P2PStream stream, {
    required String meetingId,
  }) async {
    return _send(stream, {
      'action': 'get_session_participants',
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
      _logger.severe('Error in session request: $e', e, stackTrace);
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

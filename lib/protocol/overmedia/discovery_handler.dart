/// OverMedia Discovery Protocol Handler - Client Side
///
/// Provides client-side static methods for OverMedia discovery operations
/// (query live, trending tags, popular hosts, recordings, playback, payments)
/// over libp2p streams.
///
/// Protocol ID: /overmedia/discovery/1.0.0
library;

import 'dart:typed_data';
import 'package:dart_libp2p/core/network/stream.dart';
import 'package:logging/logging.dart';

import '../stream_utils.dart';
import 'overmedia_frame.dart';

/// OverMedia Discovery Handler - Client-side protocol methods
class DiscoveryHandler {
  static const String protocolId = '/overmedia/discovery/1.0.0';
  static final Logger _logger = Logger('OverMedia.DiscoveryHandler');

  /// Query live rooms
  static Future<OverMediaResponse> queryLive(
    P2PStream stream, {
    int? limit,
    int? offset,
    List<String>? tags,
  }) async {
    return _send(stream, {
      'action': 'query_live',
      'params': {
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
        if (tags != null && tags.isNotEmpty) 'tags': tags,
      },
    });
  }

  /// Get trending tags
  static Future<OverMediaResponse> trendingTags(
    P2PStream stream, {
    int? limit,
  }) async {
    return _send(stream, {
      'action': 'trending_tags',
      'params': {
        if (limit != null) 'limit': limit,
      },
    });
  }

  /// Get popular hosts
  static Future<OverMediaResponse> popularHosts(
    P2PStream stream, {
    int? limit,
  }) async {
    return _send(stream, {
      'action': 'popular_hosts',
      'params': {
        if (limit != null) 'limit': limit,
      },
    });
  }

  /// Query recordings
  static Future<OverMediaResponse> queryRecordings(
    P2PStream stream, {
    int? limit,
    int? offset,
    bool? premium,
    String? hostPeerId,
    String? sortBy,
  }) async {
    return _send(stream, {
      'action': 'recordings',
      'params': {
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
        if (premium != null) 'premium': premium,
        if (hostPeerId != null) 'hostPeerId': hostPeerId,
        if (sortBy != null) 'sortBy': sortBy,
      },
    });
  }

  /// Get playback URL for a recording
  static Future<OverMediaResponse> getPlaybackUrl(
    P2PStream stream, {
    required String recordingId,
    required String peerId,
    int? expiryHours,
  }) async {
    return _send(stream, {
      'action': 'get_playback_url',
      'params': {
        'recordingId': recordingId,
        'peerId': peerId,
        if (expiryHours != null) 'expiryHours': expiryHours,
      },
    });
  }

  /// Track a recording play
  static Future<OverMediaResponse> trackPlay(
    P2PStream stream, {
    required String recordingId,
    required String peerId,
  }) async {
    return _send(stream, {
      'action': 'track_play',
      'params': {
        'recordingId': recordingId,
        'peerId': peerId,
      },
    });
  }

  /// Register a payment xpub
  static Future<OverMediaResponse> registerPaymentXpub(
    P2PStream stream, {
    required String xpub,
    required String signature,
    required String hostPeerId,
  }) async {
    return _send(stream, {
      'action': 'register_payment_xpub',
      'params': {
        'xpub': xpub,
        'signature': signature,
        'hostPeerId': hostPeerId,
      },
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
      _logger.severe('Error in discovery request: $e', e, stackTrace);
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

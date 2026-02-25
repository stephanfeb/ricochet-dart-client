/// Store Feed Access (SFA) Protocol Handler - Client Side
///
/// Provides client-side static methods for feed storage operations
/// (CREATE, GET, APPEND, DELETE, LIST) over libp2p streams.
///
/// Protocol ID: /ricochet/store/feed/1.0.0
library;

import 'dart:typed_data';
import 'package:dart_libp2p/core/network/stream.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:logging/logging.dart';

import 'feed_frame.dart';

/// Store Feed Access (SFA) - Client-side protocol methods
class FeedHandler {
  static const String protocolId = '/ricochet/store/feed/1.0.0';
  static final Logger _logger = Logger('SFA.FeedHandler');

  // ============================================================================
  // Client-side static methods
  // ============================================================================

  /// Create a new feed
  static Future<FeedFrameResponse> createFeed(
    P2PStream stream, {
    required PeerId ownerPeerId,
    required String path,
    required String title,
    String description = '',
  }) async {
    try {
      final requestBytes = FeedFrame.encodeRequest(
        operation: 'CREATE',
        ownerPeerId: ownerPeerId,
        path: path,
        title: title,
        description: description,
      );

      await _writeFrameStatic(stream, requestBytes);
      final responseBytes = await _readFrameStatic(stream);
      return FeedFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error creating feed: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Get feed metadata
  static Future<FeedFrameResponse> getFeed(
    P2PStream stream, {
    required PeerId ownerPeerId,
    required String path,
  }) async {
    try {
      final requestBytes = FeedFrame.encodeRequest(
        operation: 'GET',
        ownerPeerId: ownerPeerId,
        path: path,
      );

      await _writeFrameStatic(stream, requestBytes);
      final responseBytes = await _readFrameStatic(stream);
      return FeedFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error getting feed: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Get a single feed entry by sequence number
  static Future<FeedFrameResponse> getFeedEntry(
    P2PStream stream, {
    required PeerId ownerPeerId,
    required String path,
    required int sequenceNumber,
  }) async {
    try {
      final requestBytes = FeedFrame.encodeRequest(
        operation: 'GET',
        ownerPeerId: ownerPeerId,
        path: path,
        sequenceNumber: sequenceNumber,
      );

      await _writeFrameStatic(stream, requestBytes);
      final responseBytes = await _readFrameStatic(stream);
      return FeedFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error getting feed entry: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Get feed entries (range query)
  static Future<FeedFrameResponse> getFeedEntries(
    P2PStream stream, {
    required PeerId ownerPeerId,
    required String path,
    int? fromSequence,
    int? toSequence,
    int? limit,
    String? entryType,
  }) async {
    try {
      final requestBytes = FeedFrame.encodeRequest(
        operation: 'GET',
        ownerPeerId: ownerPeerId,
        path: path,
        fromSequence: fromSequence,
        toSequence: toSequence,
        limit: limit,
        entryType: entryType,
      );

      await _writeFrameStatic(stream, requestBytes);
      final responseBytes = await _readFrameStatic(stream);
      return FeedFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error getting feed entries: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Append an entry to a feed
  static Future<FeedFrameResponse> appendFeedEntry(
    P2PStream stream, {
    required PeerId ownerPeerId,
    required String path,
    required Uint8List content,
    String? entryType,
  }) async {
    try {
      final requestBytes = FeedFrame.encodeRequest(
        operation: 'APPEND',
        ownerPeerId: ownerPeerId,
        path: path,
        body: content,
        entryType: entryType,
      );

      await _writeFrameStatic(stream, requestBytes);
      final responseBytes = await _readFrameStatic(stream);
      return FeedFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error appending feed entry: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Delete a feed
  static Future<FeedFrameResponse> deleteFeed(
    P2PStream stream, {
    required PeerId ownerPeerId,
    required String path,
  }) async {
    try {
      final requestBytes = FeedFrame.encodeRequest(
        operation: 'DELETE',
        ownerPeerId: ownerPeerId,
        path: path,
      );

      await _writeFrameStatic(stream, requestBytes);
      final responseBytes = await _readFrameStatic(stream);
      return FeedFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error deleting feed: $e', e, stackTrace);
      rethrow;
    }
  }

  /// List all feeds for an owner
  static Future<FeedFrameResponse> listFeeds(
    P2PStream stream, {
    required PeerId ownerPeerId,
  }) async {
    try {
      final requestBytes = FeedFrame.encodeRequest(
        operation: 'LIST',
        ownerPeerId: ownerPeerId,
      );

      await _writeFrameStatic(stream, requestBytes);
      final responseBytes = await _readFrameStatic(stream);
      return FeedFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error listing feeds: $e', e, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Helper methods
  // ============================================================================

  static Future<void> _writeFrameStatic(P2PStream stream, Uint8List data) async {
    final lengthBytes = ByteData(4)..setUint32(0, data.length);
    final combined = Uint8List(4 + data.length);
    combined.setRange(0, 4, lengthBytes.buffer.asUint8List());
    combined.setRange(4, 4 + data.length, data);

    await stream.write(combined);
  }

  static Future<Uint8List> _readFrameStatic(P2PStream stream) async {
    final lengthBytes = await _readExact(stream, 4);
    final length = ByteData.sublistView(lengthBytes).getUint32(0);

    final frameBytes = await _readExact(stream, length);
    return frameBytes;
  }

  static Future<Uint8List> _readExact(P2PStream stream, int length) async {
    final buffer = <int>[];

    while (buffer.length < length) {
      final remaining = length - buffer.length;
      final chunk = await stream.read(remaining);

      if (chunk.isEmpty) {
        throw StateError(
            'Stream closed after reading ${buffer.length} of $length bytes');
      }

      buffer.addAll(chunk);
    }

    return Uint8List.fromList(buffer);
  }
}

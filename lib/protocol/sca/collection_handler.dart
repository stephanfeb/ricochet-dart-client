/// Store Collection Access (SCA) Protocol Handler - Client Side
///
/// Provides client-side static methods for collection storage operations
/// (CREATE, GET, PUT, DELETE, LIST, QUERY) over libp2p streams.
///
/// Protocol ID: /ricochet/store/collection/1.0.0
library;

import 'dart:typed_data';
import 'package:dart_libp2p/core/network/stream.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:logging/logging.dart';

import 'collection_frame.dart';

/// Store Collection Access (SCA) - Client-side protocol methods
class CollectionHandler {
  static const String protocolId = '/ricochet/store/collection/1.0.0';
  static final Logger _logger = Logger('SCA.CollectionHandler');

  // ============================================================================
  // Client-side static methods
  // ============================================================================

  /// Create a new collection
  static Future<CollectionFrameResponse> createCollection(
    P2PStream stream, {
    required PeerId ownerPeerId,
    required String path,
    required String name,
  }) async {
    try {
      final requestBytes = CollectionFrame.encodeRequest(
        operation: 'CREATE',
        ownerPeerId: ownerPeerId,
        path: path,
        name: name,
      );

      await _writeFrameStatic(stream, requestBytes);
      final responseBytes = await _readFrameStatic(stream);
      return CollectionFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error creating collection: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Get collection metadata
  static Future<CollectionFrameResponse> getCollection(
    P2PStream stream, {
    required PeerId ownerPeerId,
    required String path,
  }) async {
    try {
      final requestBytes = CollectionFrame.encodeRequest(
        operation: 'GET',
        ownerPeerId: ownerPeerId,
        path: path,
      );

      await _writeFrameStatic(stream, requestBytes);
      final responseBytes = await _readFrameStatic(stream);
      return CollectionFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error getting collection: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Get a single collection item by key
  static Future<CollectionFrameResponse> getCollectionItem(
    P2PStream stream, {
    required PeerId ownerPeerId,
    required String path,
    required String key,
  }) async {
    try {
      final requestBytes = CollectionFrame.encodeRequest(
        operation: 'GET',
        ownerPeerId: ownerPeerId,
        path: path,
        key: key,
      );

      await _writeFrameStatic(stream, requestBytes);
      final responseBytes = await _readFrameStatic(stream);
      return CollectionFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error getting collection item: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Put (create or update) a collection item
  static Future<CollectionFrameResponse> putCollectionItem(
    P2PStream stream, {
    required PeerId ownerPeerId,
    required String path,
    required String key,
    required Uint8List content,
    String? ifMatch,
  }) async {
    try {
      final headers = <String, String>{};
      if (ifMatch != null) {
        headers['If-Match'] = ifMatch;
      }

      final requestBytes = CollectionFrame.encodeRequest(
        operation: 'PUT',
        ownerPeerId: ownerPeerId,
        path: path,
        key: key,
        headers: headers.isNotEmpty ? headers : null,
        body: content,
      );

      await _writeFrameStatic(stream, requestBytes);
      final responseBytes = await _readFrameStatic(stream);
      return CollectionFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error putting collection item: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Delete a collection
  static Future<CollectionFrameResponse> deleteCollection(
    P2PStream stream, {
    required PeerId ownerPeerId,
    required String path,
  }) async {
    try {
      final requestBytes = CollectionFrame.encodeRequest(
        operation: 'DELETE',
        ownerPeerId: ownerPeerId,
        path: path,
      );

      await _writeFrameStatic(stream, requestBytes);
      final responseBytes = await _readFrameStatic(stream);
      return CollectionFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error deleting collection: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Delete a collection item
  static Future<CollectionFrameResponse> deleteCollectionItem(
    P2PStream stream, {
    required PeerId ownerPeerId,
    required String path,
    required String key,
  }) async {
    try {
      final requestBytes = CollectionFrame.encodeRequest(
        operation: 'DELETE',
        ownerPeerId: ownerPeerId,
        path: path,
        key: key,
      );

      await _writeFrameStatic(stream, requestBytes);
      final responseBytes = await _readFrameStatic(stream);
      return CollectionFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error deleting collection item: $e', e, stackTrace);
      rethrow;
    }
  }

  /// List all collections for an owner
  static Future<CollectionFrameResponse> listCollections(
    P2PStream stream, {
    required PeerId ownerPeerId,
  }) async {
    try {
      final requestBytes = CollectionFrame.encodeRequest(
        operation: 'LIST',
        ownerPeerId: ownerPeerId,
      );

      await _writeFrameStatic(stream, requestBytes);
      final responseBytes = await _readFrameStatic(stream);
      return CollectionFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error listing collections: $e', e, stackTrace);
      rethrow;
    }
  }

  /// List keys in a collection
  static Future<CollectionFrameResponse> listCollectionKeys(
    P2PStream stream, {
    required PeerId ownerPeerId,
    required String path,
    int? limit,
    int? offset,
  }) async {
    try {
      final requestBytes = CollectionFrame.encodeRequest(
        operation: 'LIST',
        ownerPeerId: ownerPeerId,
        path: path,
        limit: limit,
        offset: offset,
      );

      await _writeFrameStatic(stream, requestBytes);
      final responseBytes = await _readFrameStatic(stream);
      return CollectionFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error listing collection keys: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Query a collection with JSONB filter
  static Future<CollectionFrameResponse> queryCollection(
    P2PStream stream, {
    required PeerId ownerPeerId,
    required String path,
    Map<String, dynamic>? filter,
    String? sortField,
    bool? sortAsc,
    int? limit,
    int? offset,
  }) async {
    try {
      final requestBytes = CollectionFrame.encodeRequest(
        operation: 'QUERY',
        ownerPeerId: ownerPeerId,
        path: path,
        filter: filter,
        sortField: sortField,
        sortAsc: sortAsc,
        limit: limit,
        offset: offset,
      );

      await _writeFrameStatic(stream, requestBytes);
      final responseBytes = await _readFrameStatic(stream);
      return CollectionFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error querying collection: $e', e, stackTrace);
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

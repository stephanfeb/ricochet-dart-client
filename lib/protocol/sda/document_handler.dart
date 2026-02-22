/// Store Document Access (SDA) Protocol Handler - Client Side
///
/// Provides client-side static methods for document storage operations
/// (GET, PUT, PATCH, HEAD, DELETE, LIST, DIRECTORY) over libp2p streams.
///
/// Protocol ID: /ricochet/store/doc/1.0.0
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dart_libp2p/core/network/stream.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:logging/logging.dart';

import 'document_frame.dart';

/// Store Document Access (SDA) - Client-side protocol methods
///
/// Provides static methods for clients to interact with SDA servers
/// for document GET, PUT, PATCH, HEAD, DELETE, LIST, and DIRECTORY operations.
class DocumentHandler {
  static const String protocolId = '/ricochet/store/doc/1.0.0';
  static final Logger _logger = Logger('SDA.DocumentHandler');

  // ============================================================================
  // Client-side static methods
  // ============================================================================

  /// Get a document (client-side)
  static Future<DocumentResponse> getDocument(
    P2PStream stream, {
    required PeerId ownerPeerId,
    required String path,
    String? ifNoneMatch,
  }) async {
    try {
      final headers = <String, String>{};
      if (ifNoneMatch != null) {
        headers['If-None-Match'] = ifNoneMatch;
      }

      final requestBytes = DocumentFrame.encodeRequest(
        operation: 'GET',
        ownerPeerId: ownerPeerId,
        path: path,
        headers: headers,
      );

      await _writeFrameStatic(stream, requestBytes);

      // Read response
      final responseBytes = await _readFrameStatic(stream);
      return DocumentFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error getting document: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Put a document (client-side)
  static Future<DocumentResponse> putDocument(
    P2PStream stream, {
    required PeerId ownerPeerId,
    required String path,
    required Uint8List content,
    String contentType = 'application/json',
    String? ifMatch,
  }) async {
    try {
      final headers = <String, String>{
        'Content-Type': contentType,
      };
      if (ifMatch != null) {
        headers['If-Match'] = ifMatch;
      }

      final requestBytes = DocumentFrame.encodeRequest(
        operation: 'PUT',
        ownerPeerId: ownerPeerId,
        path: path,
        headers: headers,
        body: content,
      );

      await _writeFrameStatic(stream, requestBytes);

      // Read response
      final responseBytes = await _readFrameStatic(stream);
      return DocumentFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error putting document: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Patch a document (client-side) using JSON Merge Patch
  static Future<DocumentResponse> patchDocument(
    P2PStream stream, {
    required PeerId ownerPeerId,
    required String path,
    required Map<String, dynamic> patch,
    String? ifMatch,
  }) async {
    try {
      final headers = <String, String>{
        'Content-Type': 'application/merge-patch+json',
      };
      if (ifMatch != null) {
        headers['If-Match'] = ifMatch;
      }

      final patchBytes = Uint8List.fromList(utf8.encode(jsonEncode(patch)));

      final requestBytes = DocumentFrame.encodeRequest(
        operation: 'PATCH',
        ownerPeerId: ownerPeerId,
        path: path,
        headers: headers,
        body: patchBytes,
      );

      await _writeFrameStatic(stream, requestBytes);

      // Read response
      final responseBytes = await _readFrameStatic(stream);
      return DocumentFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error patching document: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Head a document (client-side)
  static Future<DocumentResponse> headDocument(
    P2PStream stream, {
    required PeerId ownerPeerId,
    required String path,
  }) async {
    try {
      final requestBytes = DocumentFrame.encodeRequest(
        operation: 'HEAD',
        ownerPeerId: ownerPeerId,
        path: path,
      );

      await _writeFrameStatic(stream, requestBytes);

      // Read response
      final responseBytes = await _readFrameStatic(stream);
      return DocumentFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error heading document: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Delete a document (client-side)
  static Future<DocumentResponse> deleteDocument(
    P2PStream stream, {
    required PeerId ownerPeerId,
    required String path,
    String? ifMatch,
  }) async {
    try {
      final headers = <String, String>{};
      if (ifMatch != null) {
        headers['If-Match'] = ifMatch;
      }

      final requestBytes = DocumentFrame.encodeRequest(
        operation: 'DELETE',
        ownerPeerId: ownerPeerId,
        path: path,
        headers: headers,
      );

      await _writeFrameStatic(stream, requestBytes);

      // Read response
      final responseBytes = await _readFrameStatic(stream);
      return DocumentFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error deleting document: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Join server directory (client-side)
  static Future<DocumentResponse> joinDirectory(
    P2PStream stream, {
    required PeerId ownerPeerId,
    required String displayName,
    String? bio,
    String? avatarHash,
    Map<String, dynamic>? extras,
  }) async {
    try {
      final listing = <String, dynamic>{
        'displayName': displayName,
        if (bio != null) 'bio': bio,
        if (avatarHash != null) 'avatarHash': avatarHash,
        if (extras != null) 'extras': extras,
      };

      final requestData = <String, dynamic>{
        'operation': 'DIRECTORY',
        'ownerPeerId': ownerPeerId.toBase58(),
        'directoryAction': 'join',
        'body': base64Encode(utf8.encode(jsonEncode(listing))),
      };

      final requestBytes =
          Uint8List.fromList(utf8.encode(jsonEncode(requestData)));

      await _writeFrameStatic(stream, requestBytes);

      final responseBytes = await _readFrameStatic(stream);
      return DocumentFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error joining directory: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Leave server directory (client-side)
  static Future<DocumentResponse> leaveDirectory(
    P2PStream stream, {
    required PeerId ownerPeerId,
  }) async {
    try {
      final requestData = <String, dynamic>{
        'operation': 'DIRECTORY',
        'ownerPeerId': ownerPeerId.toBase58(),
        'directoryAction': 'leave',
      };

      final requestBytes =
          Uint8List.fromList(utf8.encode(jsonEncode(requestData)));

      await _writeFrameStatic(stream, requestBytes);

      final responseBytes = await _readFrameStatic(stream);
      return DocumentFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error leaving directory: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Browse server directory (client-side)
  static Future<DocumentResponse> browseDirectory(
    P2PStream stream, {
    required PeerId ownerPeerId,
    String? cursor,
    int limit = 20,
    String? search,
  }) async {
    try {
      final requestData = <String, dynamic>{
        'operation': 'DIRECTORY',
        'ownerPeerId': ownerPeerId.toBase58(),
        'directoryAction': 'browse',
        'directoryLimit': limit,
      };
      if (cursor != null) requestData['directoryCursor'] = cursor;
      if (search != null) requestData['directoryQuery'] = search;

      final requestBytes =
          Uint8List.fromList(utf8.encode(jsonEncode(requestData)));

      await _writeFrameStatic(stream, requestBytes);

      final responseBytes = await _readFrameStatic(stream);
      return DocumentFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error browsing directory: $e', e, stackTrace);
      rethrow;
    }
  }

  /// List documents (client-side)
  static Future<DocumentResponse> listDocuments(
    P2PStream stream, {
    required PeerId ownerPeerId,
    String pathPrefix = '',
  }) async {
    try {
      final requestBytes = DocumentFrame.encodeRequest(
        operation: 'LIST',
        ownerPeerId: ownerPeerId,
        path: pathPrefix,
      );

      await _writeFrameStatic(stream, requestBytes);

      // Read response
      final responseBytes = await _readFrameStatic(stream);
      return DocumentFrame.decodeResponse(responseBytes);
    } catch (e, stackTrace) {
      _logger.severe('Error listing documents: $e', e, stackTrace);
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
  static Future<Uint8List> _readExact(P2PStream stream, int length) async {
    final buffer = <int>[];

    while (buffer.length < length) {
      final remaining = length - buffer.length;
      final chunk = await stream.read(remaining);

      // Empty read indicates stream closure (EOF or FIN)
      if (chunk.isEmpty) {
        throw StateError(
            'Stream closed after reading ${buffer.length} of $length bytes');
      }

      buffer.addAll(chunk);
    }

    return Uint8List.fromList(buffer);
  }
}

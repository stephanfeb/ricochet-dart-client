import 'dart:typed_data';
import 'package:dart_libp2p/dart_libp2p.dart';

/// Utilities for reading from P2P streams with proper handling of partial reads.
class StreamUtils {
  /// Reads exactly [length] bytes from the stream.
  /// 
  /// Unlike [P2PStream.read], which may return fewer bytes than requested,
  /// this method accumulates data until exactly [length] bytes are read.
  /// 
  /// Throws [StateError] if the stream closes before [length] bytes are read.
  static Future<Uint8List> readExactly(P2PStream stream, int length) async {
    if (length == 0) {
      return Uint8List(0);
    }

    final buffer = BytesBuilder(copy: false);
    
    while (buffer.length < length) {
      final remaining = length - buffer.length;
      final chunk = await stream.read(remaining);
      
      if (chunk.isEmpty) {
        throw StateError(
          'Stream closed after reading ${buffer.length} bytes, '
          'expected $length bytes'
        );
      }
      
      buffer.add(chunk);
    }
    
    return buffer.toBytes();
  }

  /// Reads a 4-byte big-endian length prefix from the stream.
  static Future<int> readLengthPrefix(P2PStream stream) async {
    final lengthBytes = await readExactly(stream, 4);
    return ByteData.sublistView(lengthBytes).getUint32(0);
  }

  /// Reads a length-prefixed frame from the stream.
  /// 
  /// First reads a 4-byte big-endian length, then reads exactly that many bytes.
  static Future<Uint8List> readLengthPrefixedFrame(P2PStream stream) async {
    final length = await readLengthPrefix(stream);
    return await readExactly(stream, length);
  }
}


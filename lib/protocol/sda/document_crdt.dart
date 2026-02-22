/// Document CRDT (Conflict-free Replicated Data Type)
///
/// Implements Last-Writer-Wins (LWW) CRDT with version vectors for
/// multi-server document replication.
library;

import 'dart:typed_data';

/// Dominance relationship between version vectors
enum Dominance {
  thisWins,   // This version is strictly newer
  otherWins,  // Other version is strictly newer
  concurrent, // Versions are concurrent (conflict)
}

/// Document CRDT state
class DocumentCRDT {
  /// Version vector: serverId -> logical clock
  final Map<String, int> versionVector;
  
  /// Document content
  final Uint8List content;
  
  /// Content hash (for verification)
  final String contentHash;
  
  /// Wall clock timestamp (for LWW tiebreaking)
  final int timestamp;
  
  /// Content type
  final String contentType;

  DocumentCRDT({
    required this.versionVector,
    required this.content,
    required this.contentHash,
    required this.timestamp,
    required this.contentType,
  });

  /// Create initial CRDT for a new document
  factory DocumentCRDT.initial({
    required String serverId,
    required Uint8List content,
    required String contentHash,
    required String contentType,
  }) {
    return DocumentCRDT(
      versionVector: {serverId: 1},
      content: content,
      contentHash: contentHash,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      contentType: contentType,
    );
  }

  /// Create CRDT from existing document state
  factory DocumentCRDT.fromDocument({
    required Map<String, int> versionVector,
    required Uint8List content,
    required String contentHash,
    required int timestamp,
    required String contentType,
  }) {
    return DocumentCRDT(
      versionVector: versionVector,
      content: content,
      contentHash: contentHash,
      timestamp: timestamp,
      contentType: contentType,
    );
  }

  /// Merge with another CRDT state
  /// 
  /// Returns the merged CRDT, which is either this, other, or the
  /// LWW winner if the versions are concurrent.
  DocumentCRDT merge(DocumentCRDT other) {
    // Compare version vectors
    final dominance = _compareVersionVectors(versionVector, other.versionVector);
    
    switch (dominance) {
      case Dominance.thisWins:
        // This version is strictly newer
        return this;
      
      case Dominance.otherWins:
        // Other version is strictly newer
        return other;
      
      case Dominance.concurrent:
        // Concurrent updates: merge version vectors (pointwise max)
        // and use LWW to pick the winning content
        final mergedVector = <String, int>{};
        final allServers = {...versionVector.keys, ...other.versionVector.keys};
        for (final serverId in allServers) {
          final v1 = versionVector[serverId] ?? 0;
          final v2 = other.versionVector[serverId] ?? 0;
          mergedVector[serverId] = v1 > v2 ? v1 : v2;
        }

        DocumentCRDT winner;
        if (timestamp > other.timestamp) {
          winner = this;
        } else if (timestamp < other.timestamp) {
          winner = other;
        } else {
          // Exact same timestamp: use content hash as tiebreaker (deterministic)
          winner = contentHash.compareTo(other.contentHash) > 0 ? this : other;
        }

        return DocumentCRDT(
          versionVector: mergedVector,
          content: winner.content,
          contentHash: winner.contentHash,
          timestamp: winner.timestamp,
          contentType: winner.contentType,
        );
    }
  }

  /// Increment version for a local update
  /// 
  /// Returns new CRDT with incremented version vector for this server.
  DocumentCRDT localUpdate({
    required String serverId,
    required Uint8List newContent,
    required String newContentHash,
    required String newContentType,
  }) {
    final newVector = Map<String, int>.from(versionVector);
    newVector[serverId] = (newVector[serverId] ?? 0) + 1;
    
    return DocumentCRDT(
      versionVector: newVector,
      content: newContent,
      contentHash: newContentHash,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      contentType: newContentType,
    );
  }

  /// Compare two version vectors to determine dominance
  static Dominance _compareVersionVectors(
    Map<String, int> v1,
    Map<String, int> v2,
  ) {
    bool v1Dominates = false;
    bool v2Dominates = false;

    // Get all server IDs from both vectors
    final allServers = {...v1.keys, ...v2.keys};

    for (final serverId in allServers) {
      final clock1 = v1[serverId] ?? 0;
      final clock2 = v2[serverId] ?? 0;

      if (clock1 > clock2) {
        v1Dominates = true;
      } else if (clock2 > clock1) {
        v2Dominates = true;
      }
    }

    if (v1Dominates && !v2Dominates) {
      return Dominance.thisWins;
    } else if (v2Dominates && !v1Dominates) {
      return Dominance.otherWins;
    } else {
      return Dominance.concurrent;
    }
  }

  /// Check if this version causally depends on (or is equal to) another
  bool happenedAfter(DocumentCRDT other) {
    for (final entry in other.versionVector.entries) {
      final ourClock = versionVector[entry.key] ?? 0;
      if (ourClock < entry.value) {
        return false; // We're missing an update from this server
      }
    }
    return true;
  }

  /// Encode version vector to JSON string for storage
  String encodeVersionVector() {
    return versionVector.entries
        .map((e) => '${e.key}:${e.value}')
        .join(',');
  }

  /// Decode version vector from JSON string
  static Map<String, int> decodeVersionVector(String encoded) {
    if (encoded.isEmpty) return {};
    
    final result = <String, int>{};
    for (final pair in encoded.split(',')) {
      final parts = pair.split(':');
      if (parts.length == 2) {
        result[parts[0]] = int.parse(parts[1]);
      }
    }
    return result;
  }

  /// Create a copy with updated fields
  DocumentCRDT copyWith({
    Map<String, int>? versionVector,
    Uint8List? content,
    String? contentHash,
    int? timestamp,
    String? contentType,
  }) {
    return DocumentCRDT(
      versionVector: versionVector ?? this.versionVector,
      content: content ?? this.content,
      contentHash: contentHash ?? this.contentHash,
      timestamp: timestamp ?? this.timestamp,
      contentType: contentType ?? this.contentType,
    );
  }

  @override
  String toString() {
    return 'DocumentCRDT(version=$versionVector, hash=${contentHash.substring(0, 16)}..., ts=$timestamp)';
  }
}

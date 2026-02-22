import 'package:dart_libp2p/core/peer/peer_id.dart';

/// Presence status for a peer
enum PresenceState {
  online,          // Active reservation < 5 min old
  probablyOnline,  // Reservation 5-30 min old
  offline,         // Expired or no reservation
  unknown,         // Query failed or pending
}

/// Presence status information for a peer
class PresenceStatus {
  final PeerId peerId;
  final PresenceState state;
  final DateTime? lastSeen;
  final Duration? ttlRemaining;
  final String? relayId;
  final DateTime checkedAt;
  
  PresenceStatus({
    required this.peerId,
    required this.state,
    this.lastSeen,
    this.ttlRemaining,
    this.relayId,
    DateTime? checkedAt,
  }) : checkedAt = checkedAt ?? DateTime.now();
  
  factory PresenceStatus.online({
    required PeerId peerId,
    required Duration ttlRemaining,
    String? relayId,
  }) {
    return PresenceStatus(
      peerId: peerId,
      state: PresenceState.online,
      lastSeen: DateTime.now(),
      ttlRemaining: ttlRemaining,
      relayId: relayId,
      checkedAt: DateTime.now(),
    );
  }
  
  factory PresenceStatus.offline({
    required PeerId peerId,
  }) {
    return PresenceStatus(
      peerId: peerId,
      state: PresenceState.offline,
      checkedAt: DateTime.now(),
    );
  }
  
  factory PresenceStatus.unknown({
    required PeerId peerId,
  }) {
    return PresenceStatus(
      peerId: peerId,
      state: PresenceState.unknown,
      checkedAt: DateTime.now(),
    );
  }
  
  bool get isOnline => state == PresenceState.online || state == PresenceState.probablyOnline;
  bool get isOffline => state == PresenceState.offline;
  bool get isUnknown => state == PresenceState.unknown;
  
  @override
  String toString() {
    return 'PresenceStatus(peer: ${peerId.toString().substring(0, 12)}..., '
           'state: $state, ttl: $ttlRemaining, relay: $relayId)';
  }
}

/// Cache for peer presence information with TTL
class PresenceCache {
  final Map<String, PresenceStatus> _cache = {};
  final Duration _cacheTtl;
  
  PresenceCache({Duration? cacheTtl})
      : _cacheTtl = cacheTtl ?? const Duration(seconds: 30);
  
  /// Get cached presence status for a peer
  PresenceStatus? get(PeerId peerId) {
    final peerIdStr = peerId.toString();
    final cached = _cache[peerIdStr];
    
    if (cached == null) return null;
    
    // Check if cache entry is still valid
    final age = DateTime.now().difference(cached.checkedAt);
    if (age > _cacheTtl) {
      _cache.remove(peerIdStr);
      return null;
    }
    
    return cached;
  }
  
  /// Update cache with new presence status
  void update(PresenceStatus status) {
    _cache[status.peerId.toString()] = status;
  }
  
  /// Check if peer has cached presence
  bool has(PeerId peerId) {
    return get(peerId) != null;
  }
  
  /// Remove peer from cache
  void remove(PeerId peerId) {
    _cache.remove(peerId.toString());
  }
  
  /// Clear all cached entries
  void clear() {
    _cache.clear();
  }
  
  /// Get all cached peers
  List<PeerId> getCachedPeers() {
    return _cache.keys
        .map((peerIdStr) => PeerId.fromString(peerIdStr))
        .toList();
  }
  
  /// Cleanup expired cache entries
  int cleanupExpired() {
    final now = DateTime.now();
    int removed = 0;
    
    final toRemove = <String>[];
    for (final entry in _cache.entries) {
      final age = now.difference(entry.value.checkedAt);
      if (age > _cacheTtl) {
        toRemove.add(entry.key);
      }
    }
    
    for (final peerIdStr in toRemove) {
      _cache.remove(peerIdStr);
      removed++;
    }
    
    return removed;
  }
  
  /// Get cache statistics
  Map<String, dynamic> getStats() {
    final now = DateTime.now();
    
    int onlineCount = 0;
    int offlineCount = 0;
    int unknownCount = 0;
    
    for (final status in _cache.values) {
      final age = now.difference(status.checkedAt);
      if (age <= _cacheTtl) {
        switch (status.state) {
          case PresenceState.online:
          case PresenceState.probablyOnline:
            onlineCount++;
            break;
          case PresenceState.offline:
            offlineCount++;
            break;
          case PresenceState.unknown:
            unknownCount++;
            break;
        }
      }
    }
    
    return {
      'totalCached': _cache.length,
      'onlineCount': onlineCount,
      'offlineCount': offlineCount,
      'unknownCount': unknownCount,
      'cacheTtlSeconds': _cacheTtl.inSeconds,
    };
  }
  
  @override
  String toString() {
    return 'PresenceCache(cached: ${_cache.length}, ttl: ${_cacheTtl.inSeconds}s)';
  }
}


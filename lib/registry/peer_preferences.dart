import 'package:dart_libp2p/core/peer/peer_id.dart';

/// Peer S&F server preference (MX-like record)
class SFServerPreference {
  final PeerId serverId;
  final int priority; // Lower value = higher priority (like MX records)
  final int weight;   // For load balancing among same priority
  
  const SFServerPreference({
    required this.serverId,
    required this.priority,
    this.weight = 50,
  });
  
  factory SFServerPreference.fromJson(Map<String, dynamic> json) {
    return SFServerPreference(
      serverId: PeerId.fromString(json['server_id'] as String),
      priority: json['priority'] as int,
      weight: json['weight'] as int? ?? 50,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'server_id': serverId.toString(),
      'priority': priority,
      'weight': weight,
    };
  }
  
  @override
  String toString() {
    return 'SFServerPreference(server: ${serverId.toString().substring(0, 12)}..., '
           'priority: $priority, weight: $weight)';
  }
}

/// Peer preferences for S&F servers (MX-like)
/// 
/// Defines which S&F servers a peer prefers to use for message storage,
/// with priority ordering for failover, similar to email MX records.
class PeerPreferences {
  final PeerId peerId;
  final List<SFServerPreference> servers;
  final int version;
  final int ttl; // seconds
  final DateTime timestamp;
  
  const PeerPreferences({
    required this.peerId,
    required this.servers,
    required this.version,
    required this.ttl,
    required this.timestamp,
  });
  
  factory PeerPreferences.fromJson(Map<String, dynamic> json) {
    return PeerPreferences(
      peerId: PeerId.fromString(json['peer_id'] as String),
      servers: (json['sf_servers'] as List)
          .map((s) => SFServerPreference.fromJson(s as Map<String, dynamic>))
          .toList(),
      version: json['version'] as int,
      ttl: json['ttl'] as int,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'peer_id': peerId.toString(),
      'sf_servers': servers.map((s) => s.toJson()).toList(),
      'version': version,
      'ttl': ttl,
      'timestamp': timestamp.toIso8601String(),
    };
  }
  
  /// Get servers sorted by priority (lower = higher priority)
  List<SFServerPreference> get serversByPriority {
    final sorted = List<SFServerPreference>.from(servers);
    sorted.sort((a, b) {
      final priorityCompare = a.priority.compareTo(b.priority);
      if (priorityCompare != 0) return priorityCompare;
      // Same priority: sort by weight (higher first for load balancing)
      return b.weight.compareTo(a.weight);
    });
    return sorted;
  }
  
  /// Get primary (highest priority) server
  SFServerPreference? get primaryServer {
    if (servers.isEmpty) return null;
    return serversByPriority.first;
  }
  
  /// Check if preferences have expired
  bool get isExpired {
    final age = DateTime.now().difference(timestamp);
    return age.inSeconds > ttl;
  }
  
  @override
  String toString() {
    return 'PeerPreferences(peer: ${peerId.toString().substring(0, 12)}..., '
           'servers: ${servers.length}, primary: ${primaryServer?.serverId.toString().substring(0, 12)}...)';
  }
}

/// Preferences manager
/// 
/// Future enhancement: Store/retrieve peer preferences using DHT or GossipSub.
/// For now, provides data structures and local management.
class PreferencesManager {
  final Map<String, PeerPreferences> _preferences = {};
  
  /// Store peer preferences
  void storePreferences(PeerPreferences preferences) {
    _preferences[preferences.peerId.toString()] = preferences;
  }
  
  /// Get peer preferences
  PeerPreferences? getPreferences(PeerId peerId) {
    final prefs = _preferences[peerId.toString()];
    
    // Check expiration
    if (prefs != null && prefs.isExpired) {
      _preferences.remove(peerId.toString());
      return null;
    }
    
    return prefs;
  }
  
  /// Remove peer preferences
  void removePreferences(PeerId peerId) {
    _preferences.remove(peerId.toString());
  }
  
  /// Cleanup expired preferences
  int cleanupExpired() {
    int removed = 0;
    final toRemove = <String>[];
    
    for (final entry in _preferences.entries) {
      if (entry.value.isExpired) {
        toRemove.add(entry.key);
      }
    }
    
    for (final peerIdStr in toRemove) {
      _preferences.remove(peerIdStr);
      removed++;
    }
    
    return removed;
  }
  
  /// Get statistics
  Map<String, dynamic> getStats() {
    return {
      'totalPreferences': _preferences.length,
    };
  }
}


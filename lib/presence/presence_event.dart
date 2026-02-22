/// Presence event models for GossipSub-based presence signaling
library;

import 'dart:convert';
import 'dart:typed_data';

import 'presence_cache.dart';

/// A batch of presence state changes published via GossipSub
class PresenceEvent {
  final String serverId;
  final int timestamp;
  final List<PresenceChange> changes;

  PresenceEvent({
    required this.serverId,
    required this.timestamp,
    required this.changes,
  });

  Map<String, dynamic> toJson() => {
        'type': 'presence_event',
        'serverId': serverId,
        'timestamp': timestamp,
        'changes': changes.map((c) => c.toJson()).toList(),
      };

  factory PresenceEvent.fromJson(Map<String, dynamic> json) {
    return PresenceEvent(
      serverId: json['serverId'] as String,
      timestamp: json['timestamp'] as int,
      changes: (json['changes'] as List)
          .map((c) => PresenceChange.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }

  Uint8List encode() =>
      Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  static PresenceEvent decode(Uint8List data) =>
      PresenceEvent.fromJson(
          jsonDecode(utf8.decode(data)) as Map<String, dynamic>);
}

/// A single peer's presence state change
class PresenceChange {
  final String peerId;
  final PresenceState state;
  final int? ttlSeconds;

  PresenceChange({
    required this.peerId,
    required this.state,
    this.ttlSeconds,
  });

  Map<String, dynamic> toJson() => {
        'peerId': peerId,
        'state': state.name,
        if (ttlSeconds != null) 'ttlSeconds': ttlSeconds,
      };

  factory PresenceChange.fromJson(Map<String, dynamic> json) {
    return PresenceChange(
      peerId: json['peerId'] as String,
      state: PresenceState.values.byName(json['state'] as String),
      ttlSeconds: json['ttlSeconds'] as int?,
    );
  }
}

/// Periodic heartbeat with compact summary of all online users
class PresenceHeartbeat {
  final String serverId;
  final int timestamp;
  final int onlineCount;
  final List<String> onlinePeerIds;
  final int heartbeatSequence;

  PresenceHeartbeat({
    required this.serverId,
    required this.timestamp,
    required this.onlineCount,
    required this.onlinePeerIds,
    required this.heartbeatSequence,
  });

  Map<String, dynamic> toJson() => {
        'type': 'presence_heartbeat',
        'serverId': serverId,
        'timestamp': timestamp,
        'onlineCount': onlineCount,
        'onlinePeerIds': onlinePeerIds,
        'heartbeatSequence': heartbeatSequence,
      };

  factory PresenceHeartbeat.fromJson(Map<String, dynamic> json) {
    return PresenceHeartbeat(
      serverId: json['serverId'] as String,
      timestamp: json['timestamp'] as int,
      onlineCount: json['onlineCount'] as int,
      onlinePeerIds:
          (json['onlinePeerIds'] as List).cast<String>(),
      heartbeatSequence: json['heartbeatSequence'] as int,
    );
  }

  Uint8List encode() =>
      Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  static PresenceHeartbeat decode(Uint8List data) =>
      PresenceHeartbeat.fromJson(
          jsonDecode(utf8.decode(data)) as Map<String, dynamic>);
}

/// Presence visibility preference
enum PresenceVisibility {
  everyone,
  nobody,
}

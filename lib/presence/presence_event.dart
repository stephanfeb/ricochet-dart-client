/// Presence event models for GossipSub-based presence signaling
///
/// Wire format matches the Go server (go-ricochet/internal/presence/events.go):
///   - type: "heartbeat" or "event" (short form, not "presence_heartbeat")
///   - timestamp: RFC3339Nano string (Go time.Time JSON encoding)
///   - state in PresenceChange: int (0=Online, 1=ProbablyOnline, 2=Offline, 3=Unknown)
library;

import 'dart:convert';
import 'dart:typed_data';

import 'presence_cache.dart';

/// Parse a timestamp that may be an ISO8601/RFC3339 string or a Unix epoch int.
/// Returns Unix epoch seconds.
int _parseTimestamp(dynamic value) {
  if (value is int) return value;
  if (value is String) {
    final dt = DateTime.parse(value);
    return dt.millisecondsSinceEpoch ~/ 1000;
  }
  return 0;
}

/// Parse a JSON value that may be int or String to int.
int _parseIntField(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.parse(value);
  return 0;
}

/// Map from Go's integer PresenceState to Dart enum.
/// Go: 0=Online, 1=ProbablyOnline, 2=Offline, 3=Unknown
PresenceState _presenceStateFromGo(dynamic value) {
  if (value is String) {
    // Also accept string names for flexibility
    return PresenceState.values.byName(value);
  }
  final intVal = (value is int) ? value : 0;
  switch (intVal) {
    case 0: return PresenceState.online;
    case 1: return PresenceState.probablyOnline;
    case 2: return PresenceState.offline;
    case 3: return PresenceState.unknown;
    default: return PresenceState.unknown;
  }
}

/// Integer value for Go wire format.
int _presenceStateToGo(PresenceState state) {
  switch (state) {
    case PresenceState.online: return 0;
    case PresenceState.probablyOnline: return 1;
    case PresenceState.offline: return 2;
    case PresenceState.unknown: return 3;
  }
}

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
        'type': 'event',
        'serverId': serverId,
        'timestamp': timestamp,
        'changes': changes.map((c) => c.toJson()).toList(),
      };

  factory PresenceEvent.fromJson(Map<String, dynamic> json) {
    return PresenceEvent(
      serverId: (json['serverId'] ?? '') as String,
      timestamp: _parseTimestamp(json['timestamp'] ?? 0),
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
        'state': _presenceStateToGo(state),
        if (ttlSeconds != null) 'ttlSeconds': ttlSeconds,
      };

  factory PresenceChange.fromJson(Map<String, dynamic> json) {
    return PresenceChange(
      peerId: (json['peerId'] ?? '') as String,
      state: _presenceStateFromGo(json['state']),
      ttlSeconds: json['ttlSeconds'] != null
          ? _parseIntField(json['ttlSeconds'])
          : null,
    );
  }
}

/// Periodic heartbeat carrying a server's online set.
///
/// A large online set arrives in pages: every page of one heartbeat shares
/// [heartbeatSequence], [timestamp] and [onlineCount], and carries its own
/// slice of [onlinePeerIds]. The set is complete once all [pageCount] pages
/// of a sequence are held; see [HeartbeatAssembler]. A heartbeat without a
/// page count (a server from before paging) is complete on its own.
class PresenceHeartbeat {
  final String serverId;
  final int timestamp;
  final int onlineCount;
  final List<String> onlinePeerIds;
  final int heartbeatSequence;

  /// Zero-based index of this page within the sequence.
  final int page;

  /// Number of pages in the sequence; 1 when the heartbeat is unpaged.
  final int pageCount;

  PresenceHeartbeat({
    required this.serverId,
    required this.timestamp,
    required this.onlineCount,
    required this.onlinePeerIds,
    required this.heartbeatSequence,
    this.page = 0,
    this.pageCount = 1,
  });

  /// Whether this heartbeat is the whole online set by itself.
  bool get isComplete => pageCount <= 1;

  Map<String, dynamic> toJson() => {
        'type': 'heartbeat',
        'serverId': serverId,
        'timestamp': timestamp,
        'onlineCount': onlineCount,
        'onlinePeerIds': onlinePeerIds,
        'heartbeatSequence': heartbeatSequence,
        if (pageCount > 1) 'page': page,
        if (pageCount > 1) 'pageCount': pageCount,
      };

  factory PresenceHeartbeat.fromJson(Map<String, dynamic> json) {
    final pageCount = _parseIntField(json['pageCount'] ?? 1);
    return PresenceHeartbeat(
      serverId: (json['serverId'] ?? '') as String,
      timestamp: _parseTimestamp(json['timestamp'] ?? 0),
      onlineCount: _parseIntField(json['onlineCount'] ?? 0),
      onlinePeerIds:
          ((json['onlinePeerIds'] ?? []) as List).cast<String>(),
      heartbeatSequence: _parseIntField(json['heartbeatSequence'] ?? 0),
      page: _parseIntField(json['page'] ?? 0),
      pageCount: pageCount < 1 ? 1 : pageCount,
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
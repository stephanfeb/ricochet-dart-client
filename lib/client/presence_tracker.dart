/// Client-side presence tracking via GossipSub subscription
///
/// Subscribes to server-scoped presence topics and filters events
/// for contacts the client cares about.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p_pubsub/dart_libp2p_pubsub.dart';
import 'package:logging/logging.dart';

import '../presence/presence_cache.dart';
import '../presence/presence_event.dart';

/// Client-side presence tracker
///
/// Tracks the online/offline status of contacts by subscribing to
/// server-scoped GossipSub presence topics.
class PresenceTracker {
  static final Logger _logger = Logger('PresenceTracker');

  final PubSub pubsub;
  final PeerId localPeerId;
  final PresenceCache cache;

  // Subscriptions to server presence topics
  final Map<String, Subscription> _serverSubscriptions = {};
  final Map<String, StreamSubscription> _streamSubscriptions = {};

  // Contact -> server mapping
  final Map<String, String> _contactServerMap = {}; // peerId -> serverId

  // Event stream for application layer
  final StreamController<PresenceChange> _contactPresenceChanges =
      StreamController.broadcast();

  /// Stream of presence changes for tracked contacts
  Stream<PresenceChange> get contactPresenceChanges =>
      _contactPresenceChanges.stream;

  PresenceTracker({
    required this.pubsub,
    required this.localPeerId,
    PresenceCache? cache,
  }) : cache = cache ?? PresenceCache(cacheTtl: const Duration(seconds: 90));

  /// Start tracking a contact's presence
  ///
  /// [contact] The peer to track
  /// [serverPeerId] The server that hosts this contact
  void trackContact(PeerId contact, PeerId serverPeerId) {
    final contactStr = contact.toBase58();
    final serverStr = serverPeerId.toBase58();

    _contactServerMap[contactStr] = serverStr;

    // Subscribe to this server's presence topic if not already
    final topic = '/sf-network/presence/${serverPeerId.toBase58()}';
    if (!_serverSubscriptions.containsKey(topic)) {
      _subscribeToServer(topic, serverStr);
    }

    _logger.fine('Tracking contact ${contactStr.substring(0, 12)}... '
        'on server ${serverStr.substring(0, 12)}...');
  }

  /// Stop tracking a contact's presence
  void untrackContact(PeerId contact) {
    final contactStr = contact.toBase58();
    final serverStr = _contactServerMap.remove(contactStr);

    if (serverStr != null) {
      // Check if any other contacts use this server
      final serverStillNeeded =
          _contactServerMap.values.any((s) => s == serverStr);
      if (!serverStillNeeded) {
        final topic = '/sf-network/presence/$serverStr';
        _unsubscribeFromServer(topic);
      }
    }

    cache.remove(contact);
    _logger.fine('Untracked contact ${contactStr.substring(0, 12)}...');
  }

  /// Get the current presence state of a contact (from cache)
  PresenceStatus? getPresence(PeerId contact) {
    return cache.get(contact);
  }

  /// Check if a contact is online
  bool isOnline(PeerId contact) {
    final status = cache.get(contact);
    return status?.isOnline ?? false;
  }

  /// Get all tracked contacts
  Set<String> get trackedContacts => Set.unmodifiable(_contactServerMap.keys);

  /// Stop all tracking and clean up
  Future<void> dispose() async {
    for (final sub in _streamSubscriptions.values) {
      await sub.cancel();
    }
    _streamSubscriptions.clear();

    for (final sub in _serverSubscriptions.values) {
      await sub.cancel();
    }
    _serverSubscriptions.clear();

    _contactServerMap.clear();
    cache.clear();

    await _contactPresenceChanges.close();
    _logger.info('PresenceTracker disposed');
  }

  // ===========================================================================
  // Internal
  // ===========================================================================

  void _subscribeToServer(String topic, String serverStr) {
    _logger.info('Subscribing to presence topic: $topic');

    final subscription = pubsub.subscribe(topic);
    _serverSubscriptions[topic] = subscription;

    final streamSub = subscription.stream.listen(
      (message) {
        _logger.info('Received presence message on topic: $topic (${message.data.length} bytes)');
        _handlePresenceMessage(message.data, serverStr);
      },
      onError: (e) => _logger.warning('Presence subscription error for $topic: $e'),
      onDone: () => _logger.warning('Presence subscription closed for $topic'),
    );
    _streamSubscriptions[topic] = streamSub;
  }

  Future<void> _unsubscribeFromServer(String topic) async {
    await _streamSubscriptions.remove(topic)?.cancel();
    await _serverSubscriptions.remove(topic)?.cancel();
    _logger.info('Unsubscribed from presence topic: $topic');
  }

  void _handlePresenceMessage(List<int> data, String serverStr) {
    try {
      final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      final type = json['type'] as String?;

      if (type == 'presence_event') {
        _handlePresenceEvent(PresenceEvent.fromJson(json));
      } else if (type == 'presence_heartbeat') {
        _handleHeartbeat(PresenceHeartbeat.fromJson(json));
      }
    } catch (e) {
      _logger.warning('Failed to parse presence message: $e');
    }
  }

  void _handlePresenceEvent(PresenceEvent event) {
    for (final change in event.changes) {
      // Only process changes for tracked contacts
      if (!_contactServerMap.containsKey(change.peerId)) continue;

      final peerId = PeerId.fromString(change.peerId);

      // Update cache
      if (change.state == PresenceState.online) {
        cache.update(PresenceStatus.online(
          peerId: peerId,
          ttlRemaining: Duration(seconds: change.ttlSeconds ?? 300),
        ));
      } else {
        cache.update(PresenceStatus.offline(peerId: peerId));
      }

      // Emit to application
      _contactPresenceChanges.add(change);

      _logger.fine('Contact ${change.peerId.substring(0, 12)}... '
          'is now ${change.state.name}');
    }
  }

  void _handleHeartbeat(PresenceHeartbeat heartbeat) {
    final onlineSet = heartbeat.onlinePeerIds.toSet();

    // Reconcile tracked contacts against heartbeat
    for (final entry in _contactServerMap.entries) {
      final contactStr = entry.key;
      final serverStr = entry.value;

      // Only reconcile contacts on this server
      if (serverStr != heartbeat.serverId) continue;

      final peerId = PeerId.fromString(contactStr);
      final isOnlineInHeartbeat = onlineSet.contains(contactStr);
      final cached = cache.get(peerId);

      if (isOnlineInHeartbeat && (cached == null || cached.isOffline)) {
        // Missed an online event
        cache.update(PresenceStatus.online(
          peerId: peerId,
          ttlRemaining: const Duration(minutes: 5),
        ));
        _contactPresenceChanges.add(PresenceChange(
          peerId: contactStr,
          state: PresenceState.online,
          ttlSeconds: 300,
        ));
        _logger.fine('Reconciled: ${contactStr.substring(0, 12)}... is online');
      } else if (!isOnlineInHeartbeat && cached != null && cached.isOnline) {
        // Missed an offline event
        cache.update(PresenceStatus.offline(peerId: peerId));
        _contactPresenceChanges.add(PresenceChange(
          peerId: contactStr,
          state: PresenceState.offline,
        ));
        _logger.fine(
            'Reconciled: ${contactStr.substring(0, 12)}... is offline');
      }
    }
  }

  /// Get tracker statistics
  Map<String, dynamic> getStats() {
    return {
      'trackedContacts': _contactServerMap.length,
      'serverSubscriptions': _serverSubscriptions.length,
      'cache': cache.getStats(),
    };
  }
}

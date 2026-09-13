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

import '../presence/heartbeat_assembler.dart';
import '../presence/presence_cache.dart';
import '../presence/presence_event.dart';

/// Client-side presence tracker
///
/// Tracks the online/offline status of contacts by subscribing to
/// server-scoped GossipSub presence topics.
class PresenceTracker {
  static final Logger _logger = Logger('PresenceTracker');

  final PubSub? pubsub;
  final PeerId localPeerId;
  final PresenceCache cache;

  // How server topics are subscribed to: the pubsub's subscribe, or a
  // stand-in under test.
  final Subscription Function(String topic) _subscribe;

  // Messages refused because the signer was not the server whose topic they
  // arrived on, or the payload named a different server.
  int _rejected = 0;

  /// Messages refused for not being the server's own.
  int get rejectedMessages => _rejected;

  // Subscriptions to server presence topics
  final Map<String, Subscription> _serverSubscriptions = {};
  final Map<String, StreamSubscription> _streamSubscriptions = {};

  // Contact -> server mapping
  final Map<String, String> _contactServerMap = {}; // peerId -> serverId

  // Pages of a multi-page heartbeat received so far, per server
  final HeartbeatAssembler _heartbeats = HeartbeatAssembler();

  // Event stream for application layer
  final StreamController<PresenceChange> _contactPresenceChanges =
      StreamController.broadcast();

  /// Stream of presence changes for tracked contacts
  Stream<PresenceChange> get contactPresenceChanges =>
      _contactPresenceChanges.stream;

  PresenceTracker({
    required PubSub this.pubsub,
    required this.localPeerId,
    PresenceCache? cache,
  })  : _subscribe = pubsub.subscribe,
        cache = cache ?? PresenceCache(cacheTtl: const Duration(seconds: 90));

  /// A tracker fed by [subscribe] instead of a live pubsub, for tests.
  PresenceTracker.withSubscriber(
    Subscription Function(String topic) subscribe, {
    required this.localPeerId,
    PresenceCache? cache,
  })  : pubsub = null,
        _subscribe = subscribe,
        cache = cache ?? PresenceCache(cacheTtl: const Duration(seconds: 90));

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
    print('[PresenceTracker] 📌 DIAG: trackContact contact=${contactStr.substring(0, 16)}... server=${serverStr.substring(0, 12)}... topic=$topic alreadySubscribed=${_serverSubscriptions.containsKey(topic)}');
    if (!_serverSubscriptions.containsKey(topic)) {
      _subscribeToServer(topic, serverStr);
    }

    print('[PresenceTracker] 📌 DIAG: Now tracking ${_contactServerMap.length} contacts, ${_serverSubscriptions.length} server subscriptions');
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

    final subscription = _subscribe(topic);
    _serverSubscriptions[topic] = subscription;

    final streamSub = subscription.stream.listen(
      (message) {
        print('[PresenceTracker] 📥 DIAG: Received GossipSub message on topic: $topic (${message.data.length} bytes)');
        // `from` is the publisher whose signature pubsub verified before
        // delivering; `receivedFrom` is only the neighbour that relayed it.
        handleMessage(message.from as PeerId, serverStr, message.data as List<int>);
      },
      onError: (e) => print('[PresenceTracker] ❌ DIAG: Subscription error for $topic: $e'),
      onDone: () => print('[PresenceTracker] ⚠️ DIAG: Subscription closed for $topic'),
    );
    _streamSubscriptions[topic] = streamSub;
  }

  Future<void> _unsubscribeFromServer(String topic) async {
    await _streamSubscriptions.remove(topic)?.cancel();
    await _serverSubscriptions.remove(topic)?.cancel();
    _heartbeats.forget(topic.substring(topic.lastIndexOf('/') + 1));
    _logger.info('Unsubscribed from presence topic: $topic');
  }

  /// Applies a presence message signed by [from] that arrived on the topic
  /// of the server [serverStr].
  ///
  /// The topic is open to any publisher, so only the server the topic
  /// belongs to may speak on it, and the payload must name that same
  /// server. Without both checks any peer on the topic could mark a
  /// contact online or offline, or feed a heartbeat that reconciles every
  /// tracked contact on that server the wrong way. Same rule as the Go
  /// server's presence tracker.
  void handleMessage(PeerId from, String serverStr, List<int> data) {
    final signer = from.toBase58();
    if (signer != serverStr) {
      _rejected++;
      _logger.warning(
          'Rejected presence message on ${serverStr.substring(0, 12)}...\'s topic signed by ${signer.substring(0, 12)}...');
      return;
    }
    try {
      final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      final type = json['type'] as String?;
      print('[PresenceTracker] 📋 DIAG: Message type=$type, server=$serverStr, raw keys=${json.keys.toList()}');

      if (type == 'presence_event' || type == 'event') {
        final event = PresenceEvent.fromJson(json);
        if (event.serverId != serverStr) {
          _rejected++;
          _logger.warning(
              'Rejected presence event naming server ${event.serverId} signed by ${serverStr.substring(0, 12)}...');
          return;
        }
        _handlePresenceEvent(event);
      } else if (type == 'presence_heartbeat' || type == 'heartbeat') {
        final heartbeat = PresenceHeartbeat.fromJson(json);
        if (heartbeat.serverId != serverStr) {
          _rejected++;
          _logger.warning(
              'Rejected presence heartbeat naming server ${heartbeat.serverId} signed by ${serverStr.substring(0, 12)}...');
          return;
        }
        _handleHeartbeat(heartbeat);
      } else {
        print('[PresenceTracker] ⚠️ DIAG: Unknown message type: $type, raw=$json');
      }
    } catch (e, st) {
      print('[PresenceTracker] ❌ DIAG: Failed to parse presence message: $e');
      print('[PresenceTracker] ❌ DIAG: Raw JSON was: ${utf8.decode(data)}');
      print('[PresenceTracker] ❌ DIAG: Stack: $st');
    }
  }

  void _handlePresenceEvent(PresenceEvent event) {
    print('[PresenceTracker] 🔍 DIAG: presence_event with ${event.changes.length} changes. Tracked contacts: ${_contactServerMap.keys.map((k) => k.substring(0, 12)).toList()}');
    for (final change in event.changes) {
      print('[PresenceTracker] 🔍 DIAG: Change peerId=${change.peerId.substring(0, 16)}... state=${change.state.name} — tracked=${_contactServerMap.containsKey(change.peerId)}');
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
      print('[PresenceTracker] ✅ DIAG: Emitting presence change for ${change.peerId.substring(0, 12)}... → ${change.state.name}');
      _contactPresenceChanges.add(change);
    }
  }

  void _handleHeartbeat(PresenceHeartbeat heartbeat) {
    print('[PresenceTracker] 💓 DIAG: Heartbeat from server=${heartbeat.serverId.substring(0, 12)}... onlineCount=${heartbeat.onlineCount} onlinePeers=${heartbeat.onlinePeerIds.map((p) => p.substring(0, 12)).toList()} seq=${heartbeat.heartbeatSequence} page=${heartbeat.page + 1}/${heartbeat.pageCount}');

    // A paged heartbeat is applied only once every page of its sequence
    // has arrived; a single page is not the whole online set.
    final onlineSet = _heartbeats.add(heartbeat);
    if (onlineSet == null) {
      return;
    }
    print('[PresenceTracker] 💓 DIAG: Tracked contacts: ${_contactServerMap.entries.map((e) => "${e.key.substring(0, 12)}→${e.value.substring(0, 12)}").toList()}');

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

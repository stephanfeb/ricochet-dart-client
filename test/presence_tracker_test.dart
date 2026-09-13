import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_libp2p/core/crypto/ed25519.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p_pubsub/dart_libp2p_pubsub.dart';
import 'package:dart_libp2p_pubsub/src/pb/rpc.pb.dart' as pb;
import 'package:ricochet/client/presence_tracker.dart';
import 'package:ricochet/presence/presence_cache.dart';
import 'package:ricochet/presence/presence_event.dart';
import 'package:test/test.dart';

Future<PeerId> randomPeer() async {
  final key = await generateEd25519KeyPair();
  return PeerId.fromPublicKey(key.publicKey);
}

/// A message as pubsub would deliver it after verifying the signature of
/// [from]: the tracker sees only the verified publisher and the payload.
PubSubMessage signedBy(PeerId from, String topic, Map<String, dynamic> payload) =>
    PubSubMessage(
      rpcMessage: pb.Message()
        ..from = from.toBytes()
        ..topic = topic
        ..data = utf8.encode(jsonEncode(payload)),
      receivedFrom: from,
    );

Map<String, dynamic> onlineEvent(String server, String peer) => {
      'type': 'event',
      'serverId': server,
      'timestamp': 0,
      'changes': [
        {'peerId': peer, 'state': 0, 'ttlSeconds': 300},
      ],
    };

Map<String, dynamic> heartbeat(String server, List<String> online) => {
      'type': 'heartbeat',
      'serverId': server,
      'timestamp': 0,
      'onlineCount': online.length,
      'onlinePeerIds': online,
      'heartbeatSequence': 1,
      'page': 0,
      'pageCount': 1,
    };

void main() {
  late PeerId server;
  late PeerId forger;
  late PeerId contact;
  late PeerId me;
  late String topic;
  late Subscription subscription;
  late PresenceTracker tracker;

  setUp(() async {
    server = await randomPeer();
    forger = await randomPeer();
    contact = await randomPeer();
    me = await randomPeer();
    topic = '/sf-network/presence/${server.toBase58()}';
    subscription = Subscription(topic, () async {});
    tracker = PresenceTracker.withSubscriber(
      (t) {
        expect(t, topic);
        return subscription;
      },
      localPeerId: me,
      cache: PresenceCache(cacheTtl: const Duration(minutes: 5)),
    );
    tracker.trackContact(contact, server);
  });

  tearDown(() => tracker.dispose());

  Future<void> deliver(PubSubMessage m) async {
    subscription.deliver(m);
    await Future<void>.delayed(Duration.zero);
  }

  test('a presence event signed by the server is applied', () async {
    await deliver(signedBy(server, topic, onlineEvent(server.toBase58(), contact.toBase58())));
    expect(tracker.isOnline(contact), isTrue);
    expect(tracker.rejectedMessages, 0);
  });

  test('an event on the server\'s topic signed by anyone else is refused', () async {
    final changes = <PresenceChange>[];
    tracker.contactPresenceChanges.listen(changes.add);

    await deliver(signedBy(forger, topic, onlineEvent(server.toBase58(), contact.toBase58())));
    expect(tracker.isOnline(contact), isFalse);
    expect(tracker.rejectedMessages, 1);

    // Nor can the forger knock a contact offline once it is online.
    await deliver(signedBy(server, topic, onlineEvent(server.toBase58(), contact.toBase58())));
    expect(tracker.isOnline(contact), isTrue);
    await deliver(signedBy(forger, topic, heartbeat(server.toBase58(), [])));
    expect(tracker.isOnline(contact), isTrue);
    expect(tracker.rejectedMessages, 2);
    await Future<void>.delayed(Duration.zero);
    expect(changes.length, 1);
  });

  test('a payload naming a different server than its signer is refused', () async {
    final other = (await randomPeer()).toBase58();
    await deliver(signedBy(server, topic, onlineEvent(other, contact.toBase58())));
    expect(tracker.isOnline(contact), isFalse);
    await deliver(signedBy(server, topic, heartbeat(other, [contact.toBase58()])));
    expect(tracker.isOnline(contact), isFalse);
    expect(tracker.rejectedMessages, 2);
  });

  test('a heartbeat signed by the server reconciles', () async {
    await deliver(signedBy(server, topic, heartbeat(server.toBase58(), [contact.toBase58()])));
    expect(tracker.isOnline(contact), isTrue);
    await deliver(signedBy(server, topic, heartbeat(server.toBase58(), [])));
    expect(tracker.isOnline(contact), isFalse);
    expect(tracker.rejectedMessages, 0);
  });

  test('the wire shape the Go server emits is the one accepted', () {
    // Keep the fixture honest: it must round-trip through the real decoders.
    final ev = PresenceEvent.fromJson(onlineEvent('s', 'p'));
    expect(ev.serverId, 's');
    expect(ev.changes.single.peerId, 'p');
    final hb = PresenceHeartbeat.fromJson(heartbeat('s', ['p']));
    expect(hb.serverId, 's');
    expect(hb.onlinePeerIds, ['p']);
    expect(Uint8List.fromList(utf8.encode('{}')), isNotEmpty);
  });
}

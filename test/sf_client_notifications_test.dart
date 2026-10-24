import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_libp2p/core/crypto/ed25519.dart' as crypto_ed25519;
import 'package:dart_libp2p/core/multiaddr.dart';
import 'package:dart_libp2p/core/network/context.dart' as core_context;
import 'package:dart_libp2p/core/peer/addr_info.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/p2p/host/basic/basic_host.dart';
import 'package:ricochet/client/sf_client.dart';
import 'package:ricochet/client/sf_client_config.dart';
import 'package:ricochet/protocol/mailbox_notify_protocol.dart';
import 'package:ricochet/registry/peer_preferences.dart';
import 'package:test/test.dart';

import 'support/ricochet_server.dart';
import 'support/test_host.dart';

/// A mailbox notification names the mailbox's owner (go-ricochet
/// ricochet-31s, N23), so a client following several owners' mailboxes can
/// tell two folders of the same name apart.
void main() async {
  final skip = await RicochetTestServer.available();

  group('SFClient notifications', () {
    late RicochetTestServer server;
    final hosts = <BasicHost>[];
    final clients = <SFClient>[];
    late SFClient owner;
    late SFClient reader;
    Uint8List text(String s) => Uint8List.fromList(utf8.encode(s));

    Future<SFClient> connect(PeerId serverId, MultiAddr addr) async {
      final host = await testHost(await crypto_ed25519.generateEd25519KeyPair());
      hosts.add(host);
      await host.start();
      await host.peerStore.addrBook.addAddr(serverId, addr, const Duration(hours: 24));
      await host.connect(AddrInfo(serverId, [addr]), context: core_context.Context())
          .timeout(const Duration(seconds: 20));
      final client = SFClient(
        host: host,
        config: SFClientConfig(
          preferredServers: [SFServerPreference(serverId: serverId, priority: 10)],
          connectionTimeout: const Duration(seconds: 20),
          messageTimeout: const Duration(seconds: 20),
        ),
      );
      client.registerServerAddress(serverId, addr);
      await client.start();
      clients.add(client);
      return client;
    }

    setUpAll(() async {
      server = (await RicochetTestServer.start())!;
      final serverId = PeerId.fromString(server.peerId!);
      final addr = MultiAddr(server.address.split('/p2p/').first);
      owner = await connect(serverId, addr);
      reader = await connect(serverId, addr);
    });

    tearDownAll(() async {
      for (final c in clients) {
        try {
          await c.stop();
        } catch (_) {}
      }
      for (final h in hosts) {
        try {
          await h.close();
        } catch (_) {}
      }
      await server.dispose();
    });

    test('a private notification from the server names the recipient as owner', () async {
      final arrived = reader.notifications.first.timeout(const Duration(seconds: 20));
      final sent = await owner.sendMessage(recipient: reader.host.id, payload: text('hello'));
      expect(sent.success, isTrue);

      final n = await arrived;

      expect((n.ownerPeerId, n.mailboxPath), (reader.host.id.toBase58(), 'inbox'));
    }, timeout: const Timeout(Duration(minutes: 1)));
  }, skip: skip);

  group('MailboxNotification', () {
    test('reads the owner, and takes one only when the server sent none', () {
      final json = {'mailboxPath': 'inbox', 'mailboxType': 'shared', 'messageCount': 1, 'timestamp': 1792800000};
      final old = MailboxNotification.fromJson(json);
      expect(old.ownerPeerId, isNull);
      expect(old.withOwnerIfMissing('12D3KooWOwner').ownerPeerId, '12D3KooWOwner');

      final sent = MailboxNotification.fromJson({...json, 'ownerPeerId': '12D3KooWServerSaid'});
      expect(sent.withOwnerIfMissing('12D3KooWOwner').ownerPeerId, '12D3KooWServerSaid');
      expect(sent.withServerPeerId('12D3KooWServer').ownerPeerId, '12D3KooWServerSaid');
      expect(sent.toJson()['ownerPeerId'], '12D3KooWServerSaid');
    });
  });
}

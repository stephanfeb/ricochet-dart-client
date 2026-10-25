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
import 'package:ricochet/core/mailbox_types.dart';
import 'package:ricochet/protocol/maa/access_frame.dart';
import 'package:ricochet/registry/peer_preferences.dart';
import 'package:test/test.dart';

import 'support/ricochet_server.dart';
import 'support/test_host.dart';

/// Claim mailboxes (go-ricochet 1.6.0): the owner fills one, other peers
/// claim from it, and each message goes to one claimer only.
void main() async {
  final skip = await RicochetTestServer.available();

  group('SFClient claim', () {
    late RicochetTestServer server;
    final hosts = <BasicHost>[];
    final clients = <SFClient>[];
    late SFClient owner;
    late SFClient alice;
    late SFClient bob;
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
      alice = await connect(serverId, addr);
      bob = await connect(serverId, addr);
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

    test('each stored message is claimed once, then none is left', () async {
      await owner.mailboxes.createMailbox(folderPath: 'signal/otk', type: MailboxType.claim, retentionDays: 30);
      for (final key in ['k1', 'k2', 'k3']) {
        final sent = await owner.sendMessage(recipient: owner.host.id, payload: text(key), folderPath: 'signal/otk', persistent: true);
        expect(sent.success, isTrue, reason: sent.errorMessage);
      }
      final info = await owner.mailboxes.getMailboxInfo(folderPath: 'signal/otk', type: MailboxType.claim);
      expect(info.messageCount, 3);

      final claimed = <String>[];
      for (final claimer in [alice, bob, alice]) {
        final msg = await claimer.claimMessage(ownerPeerId: owner.host.id, folderPath: 'signal/otk');
        claimed.add(utf8.decode(msg!.payload));
      }
      expect(claimed, ['k1', 'k2', 'k3']);
      expect(await bob.claimMessage(ownerPeerId: owner.host.id, folderPath: 'signal/otk'), isNull);
      final after = await owner.mailboxes.getMailboxInfo(folderPath: 'signal/otk', type: MailboxType.claim);
      expect(after.messageCount, 0);
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('a claim mailbox is not listed by others, and a public one is not claimed from', () async {
      await owner.mailboxes.createMailbox(folderPath: 'signal/otk2', type: MailboxType.claim);
      await owner.sendMessage(recipient: owner.host.id, payload: text('k'), folderPath: 'signal/otk2', persistent: true);
      await expectLater(
        alice.retrieveMessages(targetPeerId: owner.host.id, folderPath: 'signal/otk2', throwOnFailure: true),
        throwsA(isA<RetrieveRefusedException>().having((e) => e.status, 'status', 403)),
      );

      await owner.mailboxes.createMailbox(folderPath: 'posts', type: MailboxType.public);
      await owner.sendMessage(recipient: owner.host.id, payload: text('a post'), folderPath: 'posts', persistent: true);
      await expectLater(
        alice.claimMessage(ownerPeerId: owner.host.id, folderPath: 'posts'),
        throwsA(isA<RetrieveRefusedException>().having((e) => e.status, 'status', 403)),
      );
      await expectLater(
        alice.claimMessage(ownerPeerId: owner.host.id, folderPath: 'nothing-here'),
        throwsA(isA<RetrieveRefusedException>().having((e) => e.status, 'status', 404)),
      );
    }, timeout: const Timeout(Duration(minutes: 1)));
  }, skip: skip);
}

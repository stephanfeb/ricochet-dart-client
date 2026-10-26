import 'package:dart_libp2p/core/crypto/ed25519.dart' as crypto_ed25519;
import 'package:dart_libp2p/core/multiaddr.dart';
import 'package:dart_libp2p/core/network/context.dart' as core_context;
import 'package:dart_libp2p/core/peer/addr_info.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/p2p/host/basic/basic_host.dart';
import 'package:ricochet/client/sf_client.dart';
import 'package:ricochet/client/sf_client_config.dart';
import 'package:ricochet/core/mailbox_types.dart';
import 'package:ricochet/registry/peer_preferences.dart';
import 'package:test/test.dart';

import 'support/ricochet_server.dart';
import 'support/test_host.dart';

/// Listing an owner's mailboxes: go-ricochet answers in `mailboxes`, with
/// each folder and type, and only the owner's own are listed.
void main() async {
  final skip = await RicochetTestServer.available();

  group('MailboxManager.listMailboxes', () {
    late RicochetTestServer server;
    final hosts = <BasicHost>[];
    final clients = <SFClient>[];
    late SFClient owner;
    late SFClient alice;

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

    test("lists each of the owner's mailboxes with its folder and type", () async {
      expect(await owner.mailboxes.listMailboxes(), isEmpty);
      await owner.mailboxes.createMailbox(folderPath: 'signal/v2/bundle', type: MailboxType.public, retentionDays: 30);
      await owner.mailboxes.createMailbox(folderPath: 'signal/v2/one-time-keys', type: MailboxType.claim);
      await owner.mailboxes.createMailbox(folderPath: 'notes', type: MailboxType.private);
      await alice.mailboxes.createMailbox(folderPath: 'hers', type: MailboxType.private);

      final listed = await owner.mailboxes.listMailboxes();
      expect({for (final m in listed) m.address.folderPath: m.address.type}, {
        'signal/v2/bundle': MailboxType.public,
        'signal/v2/one-time-keys': MailboxType.claim,
        'notes': MailboxType.private,
      });
      expect(listed.map((m) => m.address.ownerId), everyElement(owner.host.id));
      expect(listed.firstWhere((m) => m.address.folderPath == 'signal/v2/bundle').retentionDays, 30);
    }, timeout: const Timeout(Duration(minutes: 1)));
  }, skip: skip);
}

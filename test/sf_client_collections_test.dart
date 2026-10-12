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
import 'package:ricochet/protocol/sca/collection_handler.dart';
import 'package:ricochet/registry/peer_preferences.dart';
import 'package:test/test.dart';

import 'support/ricochet_server.dart';
import 'support/test_host.dart';

/// Who may read a collection: the server makes one private unless its owner
/// says otherwise, so a collection meant for others (a catalog) must be
/// created public or made public afterwards.
void main() async {
  final skip = await RicochetTestServer.available();

  group('SFClient collection visibility', () {
    late RicochetTestServer server;
    final hosts = <BasicHost>[];
    final clients = <SFClient>[];
    late SFClient owner;
    late SFClient reader;
    final item = Uint8List.fromList(utf8.encode('{"title":"Episode 1"}'));

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

    test('a collection created public is read by another peer', () async {
      final created = await owner.createCollection(path: 'casts', name: 'Casts', visibility: CollectionVisibility.public);
      expect(created?.name, 'Casts');
      expect((await owner.putCollectionItem(path: 'casts', key: 'e1', content: item))?.isSuccess, isTrue);

      final read = await reader.getCollectionItem(ownerPeerId: owner.host.id, path: 'casts', key: 'e1');

      expect(read?.content['title'], 'Episode 1');
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('a collection created without a visibility is the owner\'s alone until made public', () async {
      await owner.createCollection(path: 'drafts', name: 'Drafts');
      await owner.putCollectionItem(path: 'drafts', key: 'd1', content: item);
      expect(await owner.getCollectionItem(ownerPeerId: owner.host.id, path: 'drafts', key: 'd1'), isNotNull);
      expect(await reader.getCollectionItem(ownerPeerId: owner.host.id, path: 'drafts', key: 'd1'), isNull);

      final set = await owner.setCollectionVisibility(path: 'drafts', visibility: CollectionVisibility.public);

      expect((set?.status, set?.visibility), (200, 'public'));
      final read = await reader.getCollectionItem(ownerPeerId: owner.host.id, path: 'drafts', key: 'd1');
      expect(read?.content['title'], 'Episode 1');
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('setting the visibility of a collection that does not exist answers 404', () async {
      final set = await owner.setCollectionVisibility(path: 'none', visibility: CollectionVisibility.public);

      expect(set?.status, 404);
    }, timeout: const Timeout(Duration(minutes: 1)));
  }, skip: skip);
}

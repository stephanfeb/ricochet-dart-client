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
import 'package:ricochet/protocol/sda/document_handler.dart';
import 'package:ricochet/registry/peer_preferences.dart';
import 'package:test/test.dart';

import 'support/ricochet_server.dart';
import 'support/test_host.dart';

/// Document version history (go-ricochet ricochet-opd, N19): off until the
/// owner turns it on with a PUT, then the kept versions can be listed,
/// fetched and restored.
void main() async {
  final skip = await RicochetTestServer.available();

  group('SFClient document history', () {
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

    test('history is turned on by a PUT, listed, fetched and restored', () async {
      final me = owner.host.id;
      await owner.putDocument(path: 'notes', content: text('v1'), contentType: 'text/plain');
      expect(await owner.getDocumentHistory(ownerPeerId: me, path: 'notes'), isEmpty);
      expect((await owner.headDocument(ownerPeerId: me, path: 'notes'))?.history, 0);

      await owner.putDocument(path: 'notes', content: text('v2'), contentType: 'text/plain', history: 5);
      final put3 = await owner.putDocument(path: 'notes', content: text('v3'), contentType: 'text/plain');

      final meta = await owner.headDocument(ownerPeerId: me, path: 'notes');
      expect((meta?.history, meta?.version), (5, 3));
      final versions = await owner.getDocumentHistory(ownerPeerId: me, path: 'notes');
      expect(versions?.map((v) => v.versionNumber), [2, 1]);
      expect(versions!.first.createdAt, greaterThan(1000000000000));
      final v1 = await owner.getDocumentVersion(ownerPeerId: me, path: 'notes', versionNumber: 1);
      expect(utf8.decode(v1!.content!), 'v1');

      final restored = await owner.restoreDocumentVersion(path: 'notes', versionNumber: 1, ifMatch: put3!.etag);
      expect((restored?.status, restored?.version), (200, 4));
      final doc = await owner.getDocument(ownerPeerId: me, path: 'notes');
      expect((utf8.decode(doc!.content!), doc.version), ('v1', 4));

      final stale = await owner.restoreDocumentVersion(path: 'notes', versionNumber: 1, ifMatch: put3.etag);
      expect(stale?.status, 409);
      final missing = await owner.restoreDocumentVersion(path: 'notes', versionNumber: 99);
      expect(missing?.status, 404);
      expect(await owner.getDocumentVersion(ownerPeerId: me, path: 'notes', versionNumber: 99), isNull);

      await owner.putDocument(path: 'notes', content: text('v5'), contentType: 'text/plain', history: 0);
      expect(await owner.getDocumentHistory(ownerPeerId: me, path: 'notes'), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('another peer reads the history of a public document but cannot restore it', () async {
      final me = owner.host.id;
      await owner.putDocument(path: 'blog', content: text('b1'), visibility: DocumentVisibility.public);
      await owner.putDocument(path: 'blog', content: text('b2'), history: 3);
      final versions = await reader.getDocumentHistory(ownerPeerId: me, path: 'blog');
      expect(versions?.map((v) => v.versionNumber), [1]);
      // restoreDocumentVersion always names the caller's own document.
      final restored = await reader.restoreDocumentVersion(path: 'blog', versionNumber: 1);
      expect(restored?.status, 404);
    }, timeout: const Timeout(Duration(minutes: 1)));
  }, skip: skip);
}

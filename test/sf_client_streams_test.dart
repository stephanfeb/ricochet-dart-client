import 'dart:typed_data';

import 'package:dart_libp2p/core/multiaddr.dart';
import 'package:dart_libp2p/core/network/context.dart' as core_context;
import 'package:dart_libp2p/core/peer/addr_info.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/crypto/ed25519.dart' as crypto_ed25519;
import 'package:dart_libp2p/p2p/host/basic/basic_host.dart';
import 'package:ricochet/client/sf_client.dart';
import 'package:ricochet/client/sf_client_config.dart';
import 'package:ricochet/registry/peer_preferences.dart';
import 'package:test/test.dart';

import 'support/ricochet_server.dart';
import 'support/test_host.dart';

void main() async {
  final skip = await RicochetTestServer.available();

  group('SFClient streams', () {
    late RicochetTestServer server;
    late BasicHost host;
    late SFClient client;
    late PeerId serverId;

    setUpAll(() async {
      server = (await RicochetTestServer.start())!;
      serverId = PeerId.fromString(server.peerId!);
      final addr = MultiAddr(server.address.split('/p2p/').first);
      host = await testHost(await crypto_ed25519.generateEd25519KeyPair());
      await host.start();
      await host.peerStore.addrBook.addAddr(serverId, addr, const Duration(hours: 24));
      await host.connect(AddrInfo(serverId, [addr]), context: core_context.Context())
          .timeout(const Duration(seconds: 20));
      host.connManager.protect(serverId, 'ricochet-sf-server');
      client = SFClient(
        host: host,
        config: SFClientConfig(
          preferredServers: [SFServerPreference(serverId: serverId, priority: 10)],
          connectionTimeout: const Duration(seconds: 20),
          messageTimeout: const Duration(seconds: 20),
        ),
      );
      client.registerServerAddress(serverId, addr);
      await client.start();
    });

    tearDownAll(() async {
      try {
        await client.stop();
      } catch (_) {}
      try {
        await host.close();
      } catch (_) {}
      await server.dispose();
    });

    // Every send opened a stream and left it open. yamux frees a stream's
    // slot when the stream closes, so an unclosed one holds its slot for the
    // life of the session and the connection dies at its 256th call with
    // "Bad state: Maximum streams reached". 400 is comfortably past that.
    test('400 sends on one connection: no stream is left holding a slot', () async {
      // Addressed to ourselves, so the next test can read them back.
      final to = host.id;
      for (var i = 0; i < 400; i++) {
        final r = await client.sendMessage(
          recipient: to,
          payload: Uint8List.fromList([i % 256]),
          folderPath: 'streams-test',
          persistent: true,
        );
        expect(r.success, isTrue, reason: 'send $i failed: ${r.errorMessage}');
      }
    }, timeout: const Timeout(Duration(minutes: 5)));

    // The mailbox calls open a stream each as well, so the same exhaustion
    // hits a long-lived reader that never sends. Retrieval always closed its
    // stream; mark-delivered did not, so it takes more than 256 of those
    // calls to show the leak.
    test('300 mark-delivered calls leave the connection usable', () async {
      final msgs = await client.retrieveMessages(folderPath: 'streams-test', maxMessages: 1);
      expect(msgs, isNotEmpty, reason: 'the send test should have left messages here');
      final ids = [msgs.first.messageId];
      for (var i = 0; i < 300; i++) {
        final ack = await client.markMessagesDelivered(ids, folderPath: 'streams-test');
        expect(ack, isNotNull, reason: 'mark delivered $i returned null');
      }
      // The connection still works after all those calls.
      final after = await client.retrieveMessages(folderPath: 'streams-test', maxMessages: 1);
      expect(after, isNotEmpty);
    }, timeout: const Timeout(Duration(minutes: 5)));
  }, skip: skip);
}

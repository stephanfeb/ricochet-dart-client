import 'package:dart_libp2p/config/config.dart' as p2p_config;
import 'package:dart_libp2p/core/crypto/keys.dart';
import 'package:dart_libp2p/core/multiaddr.dart';
import 'package:dart_libp2p/core/network/conn.dart';
import 'package:dart_libp2p/core/network/transport_conn.dart';
import 'package:dart_libp2p/core/crypto/ed25519.dart' as crypto_ed25519;
import 'package:dart_libp2p/p2p/host/basic/basic_host.dart';
import 'package:dart_libp2p/p2p/transport/connection_manager.dart';
import 'package:dart_libp2p/p2p/security/noise/noise_protocol.dart';
import 'package:dart_libp2p/p2p/transport/multiplexing/multiplexer.dart';
import 'package:dart_libp2p/p2p/transport/multiplexing/yamux/session.dart';
import 'package:dart_libp2p/p2p/transport/udx_transport.dart';
import 'package:ricochet/client/sf_client.dart';
import 'package:ricochet/client/sf_client_config.dart';
import 'package:test/test.dart';

import 'package:ricochet/protocol/maa/access_frame.dart';

/// A host with UDX, Noise and yamux and nothing else, matching how a client
/// talks to one configured server. `maxStreams` is yamux's default of 256:
/// the point of these tests is that a client stays under it by closing every
/// stream it opens, however many calls it makes.
Future<BasicHost> _host(KeyPair keyPair) async {
  final connMgr = ConnectionManager(idleTimeout: const Duration(seconds: 60));
  final yamux = MultiplexerConfig(
    keepAliveInterval: const Duration(seconds: 60),
    maxStreamWindowSize: 1024 * 1024,
    initialStreamWindowSize: 256 * 1024,
    streamWriteTimeout: const Duration(seconds: 30),
    maxStreams: 256,
  );
  return await p2p_config.Libp2p.new_(<p2p_config.Option>[
    p2p_config.Libp2p.identity(keyPair),
    p2p_config.Libp2p.connManager(connMgr),
    p2p_config.Libp2p.transport(UDXTransport(connManager: connMgr)),
    p2p_config.Libp2p.security(await NoiseSecurity.create(keyPair)),
    p2p_config.Libp2p.muxer('/yamux/1.0.0', (Conn secureConn, bool isClient) {
      if (secureConn is! TransportConn) {
        throw ArgumentError('yamux expects a TransportConn, got ${secureConn.runtimeType}');
      }
      return YamuxSession(secureConn, yamux, isClient, null);
    }),
    p2p_config.Libp2p.listenAddrs([MultiAddr('/ip4/0.0.0.0/udp/0/udx')]),
  ]) as BasicHost;
}

void main() {
  group('a retrieval that cannot be done', () {
    late BasicHost host;
    late SFClient client;

    setUpAll(() async {
      host = await _host(await crypto_ed25519.generateEd25519KeyPair());
      await host.start();
      // No S&F server at all: nothing can be retrieved.
      client = SFClient(host: host, config: SFClientConfig(preferredServers: const []));
    });

    tearDownAll(() async {
      await host.close();
    });

    test('returns an empty list by default, as before', () async {
      expect(await client.retrieveMessages(folderPath: 'inbox'), isEmpty);
    });

    test('throws RetrieveFailedException when the caller asks for it', () async {
      expect(
        () => client.retrieveMessages(folderPath: 'inbox', throwOnFailure: true),
        throwsA(isA<RetrieveFailedException>()),
      );
    });
  });
}

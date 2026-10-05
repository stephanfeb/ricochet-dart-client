import 'dart:io' show InternetAddress, RawDatagramSocket;

import 'package:dart_libp2p/config/config.dart' as p2p_config;
import 'package:dart_libp2p/core/crypto/ed25519.dart' as crypto_ed25519;
import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/multiaddr.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/p2p/security/noise/noise_protocol.dart';
import 'package:dart_libp2p/p2p/transport/connection_manager.dart';
import 'package:dart_libp2p/p2p/transport/udx_transport.dart';
import 'package:ricochet/client/server_selector.dart';
import 'package:ricochet/protocol/mma/admin_protocol.dart';
import 'package:ricochet/registry/peer_preferences.dart';
import 'package:test/test.dart';

Future<Host> _host() async {
  final keyPair = await crypto_ed25519.generateEd25519KeyPair();
  final connMgr = ConnectionManager();
  final host = await p2p_config.Libp2p.new_([
    p2p_config.Libp2p.identity(keyPair),
    p2p_config.Libp2p.connManager(connMgr),
    p2p_config.Libp2p.transport(UDXTransport(connManager: connMgr)),
    p2p_config.Libp2p.security(await NoiseSecurity.create(keyPair)),
    p2p_config.Libp2p.listenAddrs([MultiAddr('/ip4/127.0.0.1/udp/0/udx')]),
  ]);
  await host.start();
  return host;
}

void main() {
  // The availability check opened an MMA (admin) stream and closed it with
  // no request. The server logged each one as a failed request
  // (`op=unrouted`, 500). The check now only dials the server.
  group('ServerSelector availability', () {
    late Host client;
    late Host server;
    var adminStreams = 0;

    setUp(() async {
      client = await _host();
      server = await _host();
      adminStreams = 0;
      server.setStreamHandler(adminProtocolId, (stream, _) async {
        adminStreams++;
        await stream.close();
      });
    });

    tearDown(() async {
      await client.close();
      await server.close();
    });

    test('dials a server it is not connected to, with no admin stream', () async {
      final selector = ServerSelector(host: client)
        ..registerServerAddress(server.id, server.network.listenAddresses.first);

      expect(await selector.isServerAvailable(server.id), isTrue);
      expect(client.network.connsToPeer(server.id), isNotEmpty);
      await Future.delayed(const Duration(milliseconds: 300));
      expect(adminStreams, 0);
    });

    test('selects a reachable server', () async {
      final selector = ServerSelector(host: client)
        ..registerServerAddress(server.id, server.network.listenAddresses.first);

      final selected = await selector.selectServer([SFServerPreference(serverId: server.id, priority: 0)]);

      expect(selected, server.id);
      expect(adminStreams, 0);
    });

    test('reports an unreachable server as unavailable', () async {
      final silent = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(silent.close);
      final absent = await PeerId.random();
      final selector = ServerSelector(host: client)
        ..registerServerAddress(absent, MultiAddr('/ip4/127.0.0.1/udp/${silent.port}/udx'));

      expect(await selector.isServerAvailable(absent), isFalse);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}

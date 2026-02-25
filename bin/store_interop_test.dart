/// Store interoperability integration test.
///
/// Usage: store_interop_test <multiaddr/p2p/peerid> <role>
///
/// role: "primary" runs write tests + writes coordination files
///       "secondary" waits for primary, runs cross-client read tests
///
/// Exit code: 0 = all tests pass, 1 = one or more failures.
import 'dart:io';

import 'package:dart_libp2p/core/crypto/ed25519.dart' as crypto_ed25519;
import 'package:dart_libp2p/core/crypto/keys.dart';
import 'package:dart_libp2p/core/multiaddr.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/peer/addr_info.dart';
import 'package:dart_libp2p/core/network/context.dart' as core_context;
import 'package:dart_libp2p/config/config.dart' as p2p_config;
import 'package:dart_libp2p/p2p/host/basic/basic_host.dart';
import 'package:dart_libp2p/p2p/security/noise/noise_protocol.dart';
import 'package:dart_libp2p/p2p/transport/connection_manager.dart';
import 'package:dart_libp2p/p2p/transport/multiplexing/multiplexer.dart';
import 'package:dart_libp2p/p2p/transport/multiplexing/yamux/session.dart';
import 'package:dart_libp2p/p2p/transport/udx_transport.dart';
import 'package:dart_libp2p/p2p/multiaddr/protocol.dart';
import 'package:dart_libp2p/core/network/conn.dart';
import 'package:dart_libp2p/core/network/transport_conn.dart';

import 'package:ricochet/test_harness/test_runner.dart';
import 'package:ricochet/test_harness/document_tests.dart';
import 'package:ricochet/test_harness/collection_tests.dart';
import 'package:ricochet/test_harness/feed_tests.dart';
import 'package:ricochet/test_harness/mailbox_tests.dart';

/// Creates a minimal libp2p host for store testing.
/// No relay, no DHT, no AutoNAT — just UDX + Noise + Yamux.
Future<BasicHost> createHost(KeyPair keyPair) async {
  final connMgr = ConnectionManager(
    idleTimeout: const Duration(seconds: 60),
  );
  final udxTransport = UDXTransport(connManager: connMgr);

  final yamuxConfig = MultiplexerConfig(
    keepAliveInterval: const Duration(seconds: 60),
    maxStreamWindowSize: 1024 * 1024,
    initialStreamWindowSize: 256 * 1024,
    streamWriteTimeout: const Duration(seconds: 30),
    maxStreams: 256,
  );

  final hostOptions = <p2p_config.Option>[
    await p2p_config.Libp2p.identity(keyPair),
    await p2p_config.Libp2p.connManager(connMgr),
    await p2p_config.Libp2p.transport(udxTransport),
    await p2p_config.Libp2p.security(await NoiseSecurity.create(keyPair)),
    await p2p_config.Libp2p.muxer(
      '/yamux/1.0.0',
      (Conn secureConn, bool isClient) {
        if (secureConn is! TransportConn) {
          throw ArgumentError(
              'YamuxMuxer factory expects a TransportConn, got ${secureConn.runtimeType}');
        }
        return YamuxSession(secureConn, yamuxConfig, isClient, null);
      },
    ),
    await p2p_config.Libp2p.listenAddrs([MultiAddr('/ip4/0.0.0.0/udp/0/udx')]),
  ];

  final host = await p2p_config.Libp2p.new_(hostOptions) as BasicHost;
  return host;
}

Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) {
    stderr.writeln('Usage: store_interop_test <multiaddr/p2p/peerid> <role>');
    stderr.writeln('  role: "primary" or "secondary"');
    exit(1);
  }

  final targetAddrStr = arguments[0];
  final role = arguments[1];

  if (role != 'primary' && role != 'secondary') {
    stderr.writeln('ERROR: role must be "primary" or "secondary"');
    exit(1);
  }

  // Parse target multiaddr
  final targetMa = MultiAddr(targetAddrStr);
  final targetPeerIdStr = targetMa.valueForProtocol(Protocols.p2p.name);
  if (targetPeerIdStr == null) {
    stderr.writeln('ERROR: multiaddr must include /p2p/<peer-id>');
    exit(1);
  }
  final serverPeerId = PeerId.fromString(targetPeerIdStr);
  final connectAddr = targetMa.decapsulate(Protocols.p2p.name)!;

  // Generate local identity
  final localKeyPair = await crypto_ed25519.generateEd25519KeyPair();
  final localPeerId = PeerId.fromPublicKey(localKeyPair.publicKey);

  stderr.writeln('');
  stderr.writeln('============================================');
  stderr.writeln('  Store Integration Test ($role)');
  stderr.writeln('============================================');
  stderr.writeln('Server: $targetAddrStr');
  stderr.writeln('Local PeerId: ${localPeerId.toBase58()}');
  stderr.writeln('');

  late BasicHost host;

  try {
    // Create and start host
    host = await createHost(localKeyPair);
    await host.start();
    stderr.writeln('Host started on: ${host.addrs}');

    // Connect to server
    stderr.writeln('Connecting to server...');
    const maxRetries = 5;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await host.connect(
          AddrInfo(serverPeerId, [connectAddr]),
          context: core_context.Context(),
        );
        break;
      } catch (e) {
        if (attempt == maxRetries) {
          stderr.writeln('FATAL: Failed to connect after $maxRetries attempts: $e');
          exit(1);
        }
        stderr.writeln('  Connect attempt $attempt/$maxRetries failed ($e), retrying...');
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    stderr.writeln('Connected to server');
    stderr.writeln('');

    final ctx = TestContext(
      host: host,
      serverPeerId: serverPeerId,
      localPeerId: localPeerId,
      role: role,
    );

    if (role == 'primary') {
      await _runPrimaryTests(ctx);
    } else {
      await _runSecondaryTests(ctx);
    }
  } catch (e, s) {
    stderr.writeln('FATAL: $e');
    stderr.writeln(s);
    failed++;
  } finally {
    stderr.writeln('');
    stderr.writeln('============================================');
    stderr.writeln('  Results: $passed passed, $failed failed');
    stderr.writeln('============================================');
    try {
      await host.close();
    } catch (_) {}
  }

  exit(failed > 0 ? 1 : 0);
}

Future<void> _runPrimaryTests(TestContext ctx) async {
  // Write PeerId early so secondary can read it while primary runs tests
  _writePrimaryPeerId(ctx.localPeerId);

  // --- Document Store (SDA) ---
  stderr.writeln('--- Document Store (SDA) ---');
  await runPrimaryDocumentTests(ctx);
  stderr.writeln('');

  // --- Collection Store (SCA) ---
  stderr.writeln('--- Collection Store (SCA) ---');
  await runPrimaryCollectionTests(ctx);
  stderr.writeln('');

  // --- Feed Store (SFA) ---
  stderr.writeln('--- Feed Store (SFA) ---');
  await runPrimaryFeedTests(ctx);
  stderr.writeln('');

  // --- Mailbox (MSA/MAA/MMA) ---
  stderr.writeln('--- Mailbox (MSA/MAA/MMA) ---');
  await runPrimaryMailboxTests(ctx);

  // Wait briefly for secondary's PeerId, then set up cross-client mailbox
  stderr.writeln('Waiting for secondary PeerId...');
  final secondaryPeerId = await _waitForSecondaryPeerId();
  if (secondaryPeerId != null) {
    stderr.writeln('Secondary PeerId: ${secondaryPeerId.toBase58()}');
    await setupCrossClientMailbox(ctx, secondaryPeerId);
  } else {
    stderr.writeln('Warning: Secondary PeerId not available, skipping cross-client mailbox setup');
  }
  stderr.writeln('');

  // Signal primary completion
  _writePrimaryDone();
}

Future<void> _runSecondaryTests(TestContext ctx) async {
  // Write own PeerId early so primary can set up cross-client mailbox ACL
  _writeSecondaryPeerId(ctx.localPeerId);

  // Wait for primary to finish
  stderr.writeln('Waiting for primary to complete...');
  final primaryPeerId = await _waitForPrimaryCompletion();
  if (primaryPeerId == null) {
    stderr.writeln('ERROR: Timed out waiting for primary');
    failed++;
    return;
  }
  stderr.writeln('Primary PeerId: ${primaryPeerId.toBase58()}');

  // Give a moment for any ACL setup to propagate
  await Future.delayed(const Duration(seconds: 2));
  stderr.writeln('');

  // --- Cross-client Document reads ---
  stderr.writeln('--- Cross-client Document reads (SDA) ---');
  await runSecondaryDocumentTests(ctx, primaryPeerId);
  stderr.writeln('');

  // --- Cross-client Collection reads ---
  stderr.writeln('--- Cross-client Collection reads (SCA) ---');
  await runSecondaryCollectionTests(ctx, primaryPeerId);
  stderr.writeln('');

  // --- Cross-client Feed reads ---
  stderr.writeln('--- Cross-client Feed reads (SFA) ---');
  await runSecondaryFeedTests(ctx, primaryPeerId);
  stderr.writeln('');

  // --- Cross-client Mailbox messaging ---
  stderr.writeln('--- Cross-client Mailbox messaging (MBX) ---');
  await runSecondaryMailboxTests(ctx, primaryPeerId);
  stderr.writeln('');

  // Also run secondary's own store tests
  stderr.writeln('--- Secondary own Document tests (SDA) ---');
  await runPrimaryDocumentTests(ctx);
  stderr.writeln('');

  stderr.writeln('--- Secondary own Collection tests (SCA) ---');
  await runPrimaryCollectionTests(ctx);
  stderr.writeln('');

  stderr.writeln('--- Secondary own Feed tests (SFA) ---');
  await runPrimaryFeedTests(ctx);
  stderr.writeln('');
}

// ============================================================================
// File-based coordination
// ============================================================================

void _writePrimaryPeerId(PeerId peerId) {
  try {
    File('/client_shared/client_a_peer_id').writeAsStringSync(peerId.toBase58());
    stderr.writeln('Wrote primary PeerId to /client_shared/client_a_peer_id');
  } catch (e) {
    stderr.writeln('Warning: Could not write primary PeerId: $e');
  }
}

void _writePrimaryDone() {
  try {
    File('/client_shared/client_a_done').writeAsStringSync('done');
    stderr.writeln('Wrote primary completion marker');
  } catch (e) {
    stderr.writeln('Warning: Could not write completion marker: $e');
  }
}

void _writeSecondaryPeerId(PeerId peerId) {
  try {
    File('/client_shared/client_b_peer_id').writeAsStringSync(peerId.toBase58());
    stderr.writeln('Wrote secondary PeerId to /client_shared/client_b_peer_id');
  } catch (e) {
    stderr.writeln('Warning: Could not write secondary PeerId: $e');
  }
}

Future<PeerId?> _waitForSecondaryPeerId() async {
  const timeout = 30; // seconds — secondary should write PeerId quickly
  for (int i = 0; i < timeout; i++) {
    try {
      final file = File('/client_shared/client_b_peer_id');
      if (await file.exists()) {
        final str = (await file.readAsString()).trim();
        if (str.isNotEmpty) return PeerId.fromString(str);
      }
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 1));
  }
  return null;
}

Future<PeerId?> _waitForPrimaryCompletion() async {
  const timeout = 120; // seconds
  for (int i = 0; i < timeout; i++) {
    try {
      final doneFile = File('/client_shared/client_a_done');
      final peerFile = File('/client_shared/client_a_peer_id');
      if (await doneFile.exists() && await peerFile.exists()) {
        final str = (await peerFile.readAsString()).trim();
        if (str.isNotEmpty) return PeerId.fromString(str);
      }
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 1));
  }
  return null;
}

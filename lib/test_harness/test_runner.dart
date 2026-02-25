/// Shared test infrastructure for store integration tests.
///
/// Provides pass/fail reporting, stream helpers, and assertion utilities.
library;

import 'dart:io';
import 'package:dart_libp2p/core/network/context.dart' as core_context;
import 'package:dart_libp2p/core/network/stream.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/p2p/host/basic/basic_host.dart';

int passed = 0;
int failed = 0;

/// Report a test result to stderr.
void report(String tag, String name, bool ok, [String? detail]) {
  if (ok) {
    passed++;
    stderr.writeln('  [$tag] PASS: $name');
  } else {
    failed++;
    stderr.writeln('  [$tag] FAIL: $name${detail != null ? " — $detail" : ""}');
  }
}

/// Open a new protocol stream to the server with retry logic.
Future<P2PStream> openStream(
  BasicHost host,
  PeerId serverPeerId,
  String protocolId, {
  int maxRetries = 3,
}) async {
  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      final stream = await host.newStream(serverPeerId, [protocolId], core_context.Context());
      return stream;
    } catch (e) {
      if (attempt == maxRetries) rethrow;
      stderr.writeln('    Stream open attempt $attempt/$maxRetries failed ($e), retrying...');
      await Future.delayed(const Duration(seconds: 1));
    }
  }
  throw StateError('unreachable');
}

/// Assert two values are equal.
bool assertEqual<T>(T actual, T expected, String context) {
  if (actual != expected) {
    stderr.writeln('    assertEqual failed: $context — expected $expected, got $actual');
    return false;
  }
  return true;
}

/// Assert a value is not null.
bool assertNotNull(Object? value, String context) {
  if (value == null) {
    stderr.writeln('    assertNotNull failed: $context — got null');
    return false;
  }
  return true;
}

/// Assert a condition is true.
bool assertTrue(bool condition, String context) {
  if (!condition) {
    stderr.writeln('    assertTrue failed: $context');
    return false;
  }
  return true;
}

/// Context for a test run.
class TestContext {
  final BasicHost host;
  final PeerId serverPeerId;
  final PeerId localPeerId;
  final String role;

  TestContext({
    required this.host,
    required this.serverPeerId,
    required this.localPeerId,
    required this.role,
  });
}

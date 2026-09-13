import 'package:ricochet/presence/heartbeat_assembler.dart';
import 'package:ricochet/presence/presence_event.dart';
import 'package:test/test.dart';

PresenceHeartbeat page(
  int seq,
  int page,
  int count,
  List<String> online, {
  String server = 'server-a',
}) =>
    PresenceHeartbeat(
      serverId: server,
      timestamp: 0,
      onlineCount: online.length,
      onlinePeerIds: online,
      heartbeatSequence: seq,
      page: page,
      pageCount: count,
    );

void main() {
  group('HeartbeatAssembler', () {
    test('an unpaged heartbeat completes on its own', () {
      final asm = HeartbeatAssembler();
      expect(asm.add(page(1, 0, 1, ['x'])), {'x'});
      expect(asm.add(page(2, 0, 0, ['y'])), {'y'});
      expect(asm.pendingCount, 0);
    });

    test('a paged sequence completes only when every page is in', () {
      final asm = HeartbeatAssembler();
      expect(asm.add(page(1, 0, 3, ['x'])), isNull);
      expect(asm.add(page(1, 2, 3, ['z'])), isNull);
      expect(asm.pendingCount, 1);
      expect(asm.add(page(1, 1, 3, ['y'])), {'x', 'y', 'z'});
      expect(asm.pendingCount, 0);
    });

    test('a duplicate page does not complete a sequence early', () {
      final asm = HeartbeatAssembler();
      expect(asm.add(page(1, 0, 2, ['x'])), isNull);
      expect(asm.add(page(1, 0, 2, ['x'])), isNull);
      expect(asm.add(page(1, 1, 2, ['y'])), {'x', 'y'});
    });

    test('a page from another sequence discards the pending one', () {
      final asm = HeartbeatAssembler();
      expect(asm.add(page(3, 0, 2, ['stale'])), isNull);
      expect(asm.add(page(4, 0, 2, ['x'])), isNull);
      expect(asm.add(page(4, 1, 2, ['y'])), {'x', 'y'});
      // The straggler from sequence 3 starts over rather than completing.
      expect(asm.add(page(3, 1, 2, ['stale'])), isNull);
      // A restarted server's low sequence is still accepted.
      expect(asm.add(page(1, 0, 2, ['r'])), isNull);
      expect(asm.add(page(1, 1, 2, [])), {'r'});
      expect(asm.pendingCount, 0);
    });

    test('servers are assembled independently', () {
      final asm = HeartbeatAssembler();
      expect(asm.add(page(1, 0, 2, ['a'], server: 'server-a')), isNull);
      expect(asm.add(page(1, 0, 2, ['b'], server: 'server-b')), isNull);
      expect(asm.add(page(1, 1, 2, ['a2'], server: 'server-a')), {'a', 'a2'});
      expect(asm.pendingCount, 1);
      asm.forget('server-b');
      expect(asm.pendingCount, 0);
    });

    test('an out-of-range page is ignored', () {
      final asm = HeartbeatAssembler();
      expect(asm.add(page(1, 2, 2, ['x'])), isNull);
      expect(asm.pendingCount, 0);
    });
  });

  group('PresenceHeartbeat.fromJson', () {
    test('reads the page fields the Go server sends', () {
      final hb = PresenceHeartbeat.fromJson({
        'type': 'heartbeat',
        'serverId': 's',
        'timestamp': '2026-09-13T10:00:00.123456789Z',
        'onlineCount': 5000,
        'onlinePeerIds': ['x'],
        'heartbeatSequence': 7,
        'page': 1,
        'pageCount': 2,
      });
      expect(hb.page, 1);
      expect(hb.pageCount, 2);
      expect(hb.isComplete, isFalse);
      expect(hb.toJson()['pageCount'], 2);
    });

    test('a heartbeat without page fields is complete', () {
      final hb = PresenceHeartbeat.fromJson({
        'type': 'heartbeat',
        'serverId': 's',
        'timestamp': 0,
        'onlineCount': 1,
        'onlinePeerIds': ['x'],
        'heartbeatSequence': 1,
      });
      expect(hb.page, 0);
      expect(hb.pageCount, 1);
      expect(hb.isComplete, isTrue);
      expect(hb.toJson().containsKey('pageCount'), isFalse);
    });
  });
}

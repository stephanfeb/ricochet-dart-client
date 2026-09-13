/// Reassembly of paged presence heartbeats.
library;

import 'presence_event.dart';

/// Folds the pages of a server's heartbeat back into one online set.
///
/// A server with more online peers than fit in one GossipSub message splits
/// its heartbeat into pages that share a sequence number. Acting on one page
/// alone would mark every contact on the other pages offline, so a paged
/// sequence is only reported once every page has arrived. A page from a
/// different sequence discards whatever was pending for that server: the
/// server has moved on, and the old set would be stale anyway. Sequence
/// numbers restart when a server restarts, so a lower sequence is not
/// treated as stale on its face.
class HeartbeatAssembler {
  final Map<String, _Pending> _pending = {};

  /// Adds one heartbeat page and returns the complete online set when the
  /// page finishes its sequence, or null while pages are still missing.
  /// An unpaged heartbeat completes immediately.
  Set<String>? add(PresenceHeartbeat hb) {
    if (hb.isComplete) {
      _pending.remove(hb.serverId);
      return hb.onlinePeerIds.toSet();
    }
    if (hb.page < 0 || hb.page >= hb.pageCount) {
      return null;
    }

    var pending = _pending[hb.serverId];
    if (pending == null ||
        pending.sequence != hb.heartbeatSequence ||
        pending.pageCount != hb.pageCount) {
      pending = _Pending(hb.heartbeatSequence, hb.pageCount);
      _pending[hb.serverId] = pending;
    }
    pending.pages.add(hb.page);
    pending.online.addAll(hb.onlinePeerIds);
    if (pending.pages.length < pending.pageCount) {
      return null;
    }
    _pending.remove(hb.serverId);
    return pending.online;
  }

  /// Number of servers with a sequence still being assembled.
  int get pendingCount => _pending.length;

  /// Drops any partial sequence held for [serverId].
  void forget(String serverId) => _pending.remove(serverId);
}

class _Pending {
  final int sequence;
  final int pageCount;
  final Set<int> pages = {};
  final Set<String> online = {};

  _Pending(this.sequence, this.pageCount);
}

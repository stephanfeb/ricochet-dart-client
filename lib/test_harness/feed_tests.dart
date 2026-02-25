/// Feed Store (SFA) integration tests.
///
/// Tests CREATE, GET, APPEND, DELETE, LIST operations
/// and cross-client visibility.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:dart_libp2p/core/peer/peer_id.dart';

import '../protocol/sfa/feed_handler.dart';
import 'test_runner.dart';

const _tag = 'SFA';

/// Run primary feed tests (write + read-back).
Future<void> runPrimaryFeedTests(TestContext ctx) async {
  await _testCreateAndGet(ctx);
  await _testAppendAndGetEntry(ctx);
  await _testAppendMultiple(ctx);
  await _testListFeeds(ctx);
  await _testDeleteFeed(ctx);
}

/// Run secondary feed tests (cross-client reads).
Future<void> runSecondaryFeedTests(TestContext ctx, PeerId primaryPeerId) async {
  await _testCrossClientRead(ctx, primaryPeerId);
}

Future<void> _testCreateAndGet(TestContext ctx) async {
  try {
    // CREATE
    var stream = await openStream(ctx.host, ctx.serverPeerId, FeedHandler.protocolId);
    final createResp = await FeedHandler.createFeed(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-feed',
      title: 'Test Feed',
      description: 'Integration test feed',
    );
    await stream.close();

    // GET metadata
    stream = await openStream(ctx.host, ctx.serverPeerId, FeedHandler.protocolId);
    final getResp = await FeedHandler.getFeed(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-feed',
    );
    await stream.close();

    bool metadataOk = false;
    if (getResp.body != null) {
      final data = jsonDecode(utf8.decode(getResp.body!)) as Map<String, dynamic>;
      metadataOk = data['title'] == 'Test Feed' && data['currentSequence'] == 0;
    }

    report(_tag, 'Create and GET feed', createResp.isSuccess && getResp.isSuccess && metadataOk,
        !createResp.isSuccess ? 'CREATE status ${createResp.status}' :
        !getResp.isSuccess ? 'GET status ${getResp.status}' :
        !metadataOk ? 'metadata mismatch' : null);
  } catch (e) {
    report(_tag, 'Create and GET feed', false, '$e');
  }
}

Future<void> _testAppendAndGetEntry(TestContext ctx) async {
  try {
    final content = Uint8List.fromList(utf8.encode('{"event":"user_signup","userId":"u-001"}'));

    // APPEND
    var stream = await openStream(ctx.host, ctx.serverPeerId, FeedHandler.protocolId);
    final appendResp = await FeedHandler.appendFeedEntry(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-feed',
      content: content,
      entryType: 'user_event',
    );
    await stream.close();

    final seq = appendResp.sequence;
    final appendOk = appendResp.isSuccess && seq != null && seq == 1;

    // GET entry by sequence
    stream = await openStream(ctx.host, ctx.serverPeerId, FeedHandler.protocolId);
    final getResp = await FeedHandler.getFeedEntry(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-feed',
      sequenceNumber: 1,
    );
    await stream.close();

    report(_tag, 'Append and GET entry', appendOk && getResp.isSuccess,
        !appendOk ? 'APPEND failed: status ${appendResp.status}, seq $seq' :
        !getResp.isSuccess ? 'GET entry status ${getResp.status}' : null);
  } catch (e) {
    report(_tag, 'Append and GET entry', false, '$e');
  }
}

Future<void> _testAppendMultiple(TestContext ctx) async {
  try {
    // Append 4 more entries (seq 2-5, entry 1 already created above)
    for (int i = 2; i <= 5; i++) {
      final stream = await openStream(ctx.host, ctx.serverPeerId, FeedHandler.protocolId);
      await FeedHandler.appendFeedEntry(
        stream,
        ownerPeerId: ctx.localPeerId,
        path: 'interop-test-feed',
        content: Uint8List.fromList(utf8.encode('{"event":"entry_$i","index":$i}')),
        entryType: 'batch_event',
      );
      await stream.close();
    }

    // GET range (entries 1-5)
    final stream = await openStream(ctx.host, ctx.serverPeerId, FeedHandler.protocolId);
    final resp = await FeedHandler.getFeedEntries(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-feed',
      fromSequence: 1,
      toSequence: 5,
    );
    await stream.close();

    bool rangeOk = false;
    if (resp.body != null) {
      final data = jsonDecode(utf8.decode(resp.body!));
      if (data is Map<String, dynamic> && data['entries'] is List) {
        rangeOk = (data['entries'] as List).length == 5;
      } else if (data is List) {
        rangeOk = data.length == 5;
      }
    }

    report(_tag, 'Append multiple + range query', resp.isSuccess && rangeOk,
        !resp.isSuccess ? 'status ${resp.status}' :
        !rangeOk ? 'expected 5 entries in range' : null);
  } catch (e) {
    report(_tag, 'Append multiple + range query', false, '$e');
  }
}

Future<void> _testListFeeds(TestContext ctx) async {
  try {
    // Create a second feed
    var stream = await openStream(ctx.host, ctx.serverPeerId, FeedHandler.protocolId);
    await FeedHandler.createFeed(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-feed-2',
      title: 'Second Feed',
    );
    await stream.close();

    // LIST
    stream = await openStream(ctx.host, ctx.serverPeerId, FeedHandler.protocolId);
    final resp = await FeedHandler.listFeeds(
      stream,
      ownerPeerId: ctx.localPeerId,
    );
    await stream.close();

    bool enoughFeeds = false;
    if (resp.body != null) {
      final data = jsonDecode(utf8.decode(resp.body!));
      if (data is List) {
        enoughFeeds = data.length >= 2;
      }
    }

    report(_tag, 'List feeds', resp.isSuccess && enoughFeeds,
        !resp.isSuccess ? 'status ${resp.status}' :
        !enoughFeeds ? 'expected >= 2 feeds' : null);
  } catch (e) {
    report(_tag, 'List feeds', false, '$e');
  }
}

Future<void> _testDeleteFeed(TestContext ctx) async {
  try {
    // Create a temp feed
    var stream = await openStream(ctx.host, ctx.serverPeerId, FeedHandler.protocolId);
    await FeedHandler.createFeed(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-feed-temp',
      title: 'Temp Feed',
    );
    await stream.close();

    // Append an entry
    stream = await openStream(ctx.host, ctx.serverPeerId, FeedHandler.protocolId);
    await FeedHandler.appendFeedEntry(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-feed-temp',
      content: Uint8List.fromList(utf8.encode('{"temp":true}')),
    );
    await stream.close();

    // DELETE
    stream = await openStream(ctx.host, ctx.serverPeerId, FeedHandler.protocolId);
    final delResp = await FeedHandler.deleteFeed(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-feed-temp',
    );
    await stream.close();

    // GET should return 404
    stream = await openStream(ctx.host, ctx.serverPeerId, FeedHandler.protocolId);
    final getResp = await FeedHandler.getFeed(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-feed-temp',
    );
    await stream.close();

    report(_tag, 'Delete feed', delResp.isSuccess && getResp.isNotFound,
        !delResp.isSuccess ? 'DELETE status ${delResp.status}' :
        !getResp.isNotFound ? 'GET after delete: ${getResp.status}' : null);
  } catch (e) {
    report(_tag, 'Delete feed', false, '$e');
  }
}

Future<void> _testCrossClientRead(TestContext ctx, PeerId primaryPeerId) async {
  try {
    // Read entries from primary's feed
    final stream = await openStream(ctx.host, ctx.serverPeerId, FeedHandler.protocolId);
    final resp = await FeedHandler.getFeedEntries(
      stream,
      ownerPeerId: primaryPeerId,
      path: 'interop-test-feed',
      fromSequence: 1,
      limit: 5,
    );
    await stream.close();

    bool hasEntries = false;
    if (resp.body != null) {
      final data = jsonDecode(utf8.decode(resp.body!));
      if (data is Map<String, dynamic> && data['entries'] is List) {
        hasEntries = (data['entries'] as List).isNotEmpty;
      } else if (data is List) {
        hasEntries = data.isNotEmpty;
      }
    }

    report(_tag, 'Cross-client read feed entries', resp.isSuccess && hasEntries,
        !resp.isSuccess ? 'status ${resp.status}' :
        !hasEntries ? 'no entries found' : null);
  } catch (e) {
    report(_tag, 'Cross-client read feed entries', false, '$e');
  }
}

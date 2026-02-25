/// Collection Store (SCA) integration tests.
///
/// Tests CREATE, GET, PUT, DELETE, LIST, QUERY operations,
/// optimistic locking, and cross-client visibility.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:dart_libp2p/core/peer/peer_id.dart';

import '../protocol/sca/collection_handler.dart';
import 'test_runner.dart';

const _tag = 'SCA';

/// Run primary collection tests (write + read-back).
Future<void> runPrimaryCollectionTests(TestContext ctx) async {
  await _testCreateAndGet(ctx);
  await _testPutAndGetItem(ctx);
  await _testUpdateItem(ctx);
  await _testOptimisticLocking(ctx);
  await _testDeleteItem(ctx);
  await _testDeleteCollection(ctx);
  await _testListKeys(ctx);
  await _testQueryEquality(ctx);
  await _testQueryComparison(ctx);
  await _testQueryCompound(ctx);
  await _testListCollections(ctx);
}

/// Run secondary collection tests (cross-client reads).
Future<void> runSecondaryCollectionTests(TestContext ctx, PeerId primaryPeerId) async {
  await _testCrossClientItemRead(ctx, primaryPeerId);
}

Future<void> _testCreateAndGet(TestContext ctx) async {
  try {
    // CREATE
    var stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    final createResp = await CollectionHandler.createCollection(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-products',
      name: 'Product Catalog',
    );
    await stream.close();

    // GET metadata
    stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    final getResp = await CollectionHandler.getCollection(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-products',
    );
    await stream.close();

    final body = getResp.body != null ? jsonDecode(utf8.decode(getResp.body!)) as Map<String, dynamic> : null;
    final nameOk = body != null && body['name'] == 'Product Catalog';
    final countOk = body != null && body['recordCount'] == 0;

    report(_tag, 'Create and GET collection', createResp.isSuccess && getResp.isSuccess && nameOk && countOk,
        !createResp.isSuccess ? 'CREATE status ${createResp.status}' :
        !getResp.isSuccess ? 'GET status ${getResp.status}' :
        !nameOk ? 'name mismatch' :
        !countOk ? 'recordCount not 0' : null);
  } catch (e) {
    report(_tag, 'Create and GET collection', false, '$e');
  }
}

Future<void> _testPutAndGetItem(TestContext ctx) async {
  try {
    final content = Uint8List.fromList(utf8.encode('{"name":"Drill","price":49.99,"category":"tools"}'));

    // PUT item
    var stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    final putResp = await CollectionHandler.putCollectionItem(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-products',
      key: 'sku-001',
      content: content,
    );
    await stream.close();

    final created = putResp.status == 201;
    final hasEtag = putResp.etag != null && putResp.etag!.isNotEmpty;
    final version1 = putResp.version == 1;

    // GET item
    stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    final getResp = await CollectionHandler.getCollectionItem(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-products',
      key: 'sku-001',
    );
    await stream.close();

    bool contentOk = false;
    if (getResp.body != null) {
      final parsed = jsonDecode(utf8.decode(getResp.body!)) as Map<String, dynamic>;
      contentOk = parsed['name'] == 'Drill';
    }

    report(_tag, 'PUT and GET item', created && hasEtag && version1 && contentOk,
        !created ? 'expected 201, got ${putResp.status}' :
        !hasEtag ? 'missing ETag' :
        !version1 ? 'expected version 1, got ${putResp.version}' :
        !contentOk ? 'content mismatch' : null);
  } catch (e) {
    report(_tag, 'PUT and GET item', false, '$e');
  }
}

Future<void> _testUpdateItem(TestContext ctx) async {
  try {
    // PUT same key with updated content
    final stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    final resp = await CollectionHandler.putCollectionItem(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-products',
      key: 'sku-001',
      content: Uint8List.fromList(utf8.encode('{"name":"Drill","price":39.99,"category":"tools"}')),
    );
    await stream.close();

    final isUpdate = resp.status == 200;
    final version2 = resp.version == 2;

    report(_tag, 'Update item (version increment)', isUpdate && version2,
        !isUpdate ? 'expected 200, got ${resp.status}' :
        !version2 ? 'expected version 2, got ${resp.version}' : null);
  } catch (e) {
    report(_tag, 'Update item (version increment)', false, '$e');
  }
}

Future<void> _testOptimisticLocking(TestContext ctx) async {
  try {
    // GET current ETag
    var stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    final getResp = await CollectionHandler.getCollectionItem(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-products',
      key: 'sku-001',
    );
    await stream.close();

    final currentEtag = getResp.etag;

    // PUT with correct If-Match should succeed
    stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    final okResp = await CollectionHandler.putCollectionItem(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-products',
      key: 'sku-001',
      content: Uint8List.fromList(utf8.encode('{"name":"Drill","price":34.99}')),
      ifMatch: currentEtag,
    );
    await stream.close();

    // PUT with old (stale) If-Match should fail with 409
    stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    final failResp = await CollectionHandler.putCollectionItem(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-products',
      key: 'sku-001',
      content: Uint8List.fromList(utf8.encode('{"name":"Drill","price":29.99}')),
      ifMatch: currentEtag, // now stale
    );
    await stream.close();

    report(_tag, 'Optimistic locking (If-Match)', okResp.isSuccess && failResp.isConflict,
        !okResp.isSuccess ? 'correct If-Match failed: ${okResp.status}' :
        !failResp.isConflict ? 'stale If-Match expected 409, got ${failResp.status}' : null);
  } catch (e) {
    report(_tag, 'Optimistic locking (If-Match)', false, '$e');
  }
}

Future<void> _testDeleteItem(TestContext ctx) async {
  try {
    // Add a temporary item
    var stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    await CollectionHandler.putCollectionItem(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-products',
      key: 'sku-temp',
      content: Uint8List.fromList(utf8.encode('{"name":"Temp"}')),
    );
    await stream.close();

    // DELETE it
    stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    final delResp = await CollectionHandler.deleteCollectionItem(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-products',
      key: 'sku-temp',
    );
    await stream.close();

    // GET should return 404
    stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    final getResp = await CollectionHandler.getCollectionItem(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-products',
      key: 'sku-temp',
    );
    await stream.close();

    report(_tag, 'Delete collection item', delResp.isSuccess && getResp.isNotFound,
        !delResp.isSuccess ? 'DELETE status ${delResp.status}' :
        !getResp.isNotFound ? 'GET after delete: ${getResp.status}' : null);
  } catch (e) {
    report(_tag, 'Delete collection item', false, '$e');
  }
}

Future<void> _testDeleteCollection(TestContext ctx) async {
  try {
    // Create a temp collection with items
    var stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    await CollectionHandler.createCollection(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-temp-coll',
      name: 'Temp',
    );
    await stream.close();

    stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    await CollectionHandler.putCollectionItem(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-temp-coll',
      key: 'k1',
      content: Uint8List.fromList(utf8.encode('{"x":1}')),
    );
    await stream.close();

    // DELETE collection
    stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    final delResp = await CollectionHandler.deleteCollection(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-temp-coll',
    );
    await stream.close();

    // GET should return 404
    stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    final getResp = await CollectionHandler.getCollection(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-temp-coll',
    );
    await stream.close();

    report(_tag, 'Delete collection', delResp.isSuccess && getResp.isNotFound,
        !delResp.isSuccess ? 'DELETE status ${delResp.status}' :
        !getResp.isNotFound ? 'GET after delete: ${getResp.status}' : null);
  } catch (e) {
    report(_tag, 'Delete collection', false, '$e');
  }
}

Future<void> _testListKeys(TestContext ctx) async {
  try {
    // Create a collection with known items
    var stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    await CollectionHandler.createCollection(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-keys',
      name: 'Keys Test',
    );
    await stream.close();

    for (final key in ['sku-003', 'sku-001', 'sku-002']) {
      stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
      await CollectionHandler.putCollectionItem(
        stream,
        ownerPeerId: ctx.localPeerId,
        path: 'interop-test-keys',
        key: key,
        content: Uint8List.fromList(utf8.encode('{"name":"Item"}')),
      );
      await stream.close();
    }

    // LIST keys
    stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    final resp = await CollectionHandler.listCollectionKeys(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-keys',
    );
    await stream.close();

    bool keysOk = false;
    if (resp.body != null) {
      final data = jsonDecode(utf8.decode(resp.body!));
      if (data is Map<String, dynamic> && data['keys'] is List) {
        final keys = (data['keys'] as List).cast<String>();
        keysOk = keys.length == 3 &&
            keys[0] == 'sku-001' &&
            keys[1] == 'sku-002' &&
            keys[2] == 'sku-003';
      }
    }

    report(_tag, 'List collection keys (sorted)', resp.isSuccess && keysOk,
        !resp.isSuccess ? 'status ${resp.status}' :
        !keysOk ? 'keys not sorted or wrong count' : null);
  } catch (e) {
    report(_tag, 'List collection keys (sorted)', false, '$e');
  }
}

Future<void> _testQueryEquality(TestContext ctx) async {
  try {
    // Create a single collection with items having both category and price fields.
    // This collection is reused by the comparison and compound query tests below.
    var stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    await CollectionHandler.createCollection(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-query',
      name: 'Query Test',
    );
    await stream.close();

    final items = {
      'q-001': '{"name":"Drill","price":49.99,"category":"tools"}',
      'q-002': '{"name":"Paint","price":29.99,"category":"supplies"}',
      'q-003': '{"name":"Hammer","price":19.99,"category":"tools"}',
    };

    for (final entry in items.entries) {
      stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
      await CollectionHandler.putCollectionItem(
        stream,
        ownerPeerId: ctx.localPeerId,
        path: 'interop-test-query',
        key: entry.key,
        content: Uint8List.fromList(utf8.encode(entry.value)),
      );
      await stream.close();
    }

    // QUERY for tools only
    stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    final resp = await CollectionHandler.queryCollection(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-query',
      filter: {'category': 'tools'},
    );
    await stream.close();

    final count = resp.totalCount ?? 0;
    report(_tag, 'Query equality filter', resp.isSuccess && count == 2,
        !resp.isSuccess ? 'status ${resp.status}' :
        count != 2 ? 'expected 2 results, got $count' : null);
  } catch (e) {
    report(_tag, 'Query equality filter', false, '$e');
  }
}

Future<void> _testQueryComparison(TestContext ctx) async {
  try {
    // Reuse interop-test-query collection (created by _testQueryEquality).
    // Items: Drill=49.99, Paint=29.99, Hammer=19.99 → 2 items under $30.
    final stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    final resp = await CollectionHandler.queryCollection(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-query',
      filter: {'price': {'\$lt': 30}},
    );
    await stream.close();

    final count = resp.totalCount ?? 0;
    report(_tag, 'Query comparison (\$lt)', resp.isSuccess && count == 2,
        !resp.isSuccess ? 'status ${resp.status}' :
        count != 2 ? 'expected 2 results, got $count' : null);
  } catch (e) {
    report(_tag, 'Query comparison (\$lt)', false, '$e');
  }
}

Future<void> _testQueryCompound(TestContext ctx) async {
  try {
    // Reuse interop-test-query collection (created by _testQueryEquality).
    // Items: Drill(tools,49.99), Paint(supplies,29.99), Hammer(tools,19.99)
    // Query: tools AND price < 30 → only Hammer matches.
    final stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    final resp = await CollectionHandler.queryCollection(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test-query',
      filter: {
        '\$and': [
          {'category': 'tools'},
          {'price': {'\$lt': 30}},
        ],
      },
    );
    await stream.close();

    final count = resp.totalCount ?? 0;
    report(_tag, 'Query compound (\$and)', resp.isSuccess && count == 1,
        !resp.isSuccess ? 'status ${resp.status}' :
        count != 1 ? 'expected 1 result, got $count' : null);
  } catch (e) {
    report(_tag, 'Query compound (\$and)', false, '$e');
  }
}

Future<void> _testListCollections(TestContext ctx) async {
  try {
    // LIST all collections (several created above)
    final stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    final resp = await CollectionHandler.listCollections(
      stream,
      ownerPeerId: ctx.localPeerId,
    );
    await stream.close();

    bool enoughCollections = false;
    if (resp.body != null) {
      final data = jsonDecode(utf8.decode(resp.body!));
      if (data is List) {
        enoughCollections = data.length >= 2;
      }
    }

    report(_tag, 'List collections', resp.isSuccess && enoughCollections,
        !resp.isSuccess ? 'status ${resp.status}' :
        !enoughCollections ? 'expected >= 2 collections' : null);
  } catch (e) {
    report(_tag, 'List collections', false, '$e');
  }
}

Future<void> _testCrossClientItemRead(TestContext ctx, PeerId primaryPeerId) async {
  try {
    // Read sku-001 from primary's collection
    final stream = await openStream(ctx.host, ctx.serverPeerId, CollectionHandler.protocolId);
    final resp = await CollectionHandler.getCollectionItem(
      stream,
      ownerPeerId: primaryPeerId,
      path: 'interop-test-products',
      key: 'sku-001',
    );
    await stream.close();

    bool contentOk = false;
    if (resp.body != null) {
      final parsed = jsonDecode(utf8.decode(resp.body!)) as Map<String, dynamic>;
      contentOk = parsed['name'] == 'Drill';
    }

    report(_tag, 'Cross-client read collection item', resp.isSuccess && contentOk,
        !resp.isSuccess ? 'status ${resp.status}' :
        !contentOk ? 'content mismatch' : null);
  } catch (e) {
    report(_tag, 'Cross-client read collection item', false, '$e');
  }
}

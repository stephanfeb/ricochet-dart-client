/// Document Store (SDA) integration tests.
///
/// Tests PUT, GET, conditional GET/PUT, HEAD, DELETE, LIST, PATCH operations
/// and cross-client visibility.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:dart_libp2p/core/peer/peer_id.dart';

import '../protocol/sda/document_handler.dart';
import 'test_runner.dart';

const _tag = 'SDA';

/// Run primary document tests (write + read-back).
Future<void> runPrimaryDocumentTests(TestContext ctx) async {
  await _testPutAndGet(ctx);
  await _testConditionalGet(ctx);
  await _testConditionalPut(ctx);
  await _testHead(ctx);
  await _testPatch(ctx);
  await _testList(ctx);
  await _testDelete(ctx);
}

/// Run secondary document tests (cross-client reads).
Future<void> runSecondaryDocumentTests(TestContext ctx, PeerId primaryPeerId) async {
  await _testCrossClientRead(ctx, primaryPeerId);
}

Future<void> _testPutAndGet(TestContext ctx) async {
  try {
    final content = Uint8List.fromList(utf8.encode('{"name":"test-doc","value":42}'));

    // PUT
    var stream = await openStream(ctx.host, ctx.serverPeerId, DocumentHandler.protocolId);
    final putResp = await DocumentHandler.putDocument(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test/doc-1',
      content: content,
    );
    await stream.close();

    final etagOk = putResp.etag != null && putResp.etag!.isNotEmpty;
    final statusOk = putResp.isSuccess;

    // GET
    stream = await openStream(ctx.host, ctx.serverPeerId, DocumentHandler.protocolId);
    final getResp = await DocumentHandler.getDocument(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test/doc-1',
    );
    await stream.close();

    final contentMatch = getResp.body != null && utf8.decode(getResp.body!) == '{"name":"test-doc","value":42}';
    final etagMatch = getResp.etag == putResp.etag;

    report(_tag, 'PUT and GET document', statusOk && etagOk && contentMatch && etagMatch,
        !statusOk ? 'PUT status ${putResp.status}' :
        !etagOk ? 'missing ETag' :
        !contentMatch ? 'content mismatch' :
        !etagMatch ? 'ETag mismatch' : null);
  } catch (e) {
    report(_tag, 'PUT and GET document', false, '$e');
  }
}

Future<void> _testConditionalGet(TestContext ctx) async {
  try {
    // PUT a doc
    var stream = await openStream(ctx.host, ctx.serverPeerId, DocumentHandler.protocolId);
    final putResp = await DocumentHandler.putDocument(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test/cond-get',
      content: Uint8List.fromList(utf8.encode('{"cached":true}')),
    );
    await stream.close();

    // GET with matching ETag should return 304
    stream = await openStream(ctx.host, ctx.serverPeerId, DocumentHandler.protocolId);
    final getResp = await DocumentHandler.getDocument(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test/cond-get',
      ifNoneMatch: putResp.etag,
    );
    await stream.close();

    report(_tag, 'Conditional GET (304)', getResp.isNotModified,
        getResp.isNotModified ? null : 'expected 304, got ${getResp.status}');
  } catch (e) {
    report(_tag, 'Conditional GET (304)', false, '$e');
  }
}

Future<void> _testConditionalPut(TestContext ctx) async {
  try {
    // PUT v1
    var stream = await openStream(ctx.host, ctx.serverPeerId, DocumentHandler.protocolId);
    await DocumentHandler.putDocument(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test/cond-put',
      content: Uint8List.fromList(utf8.encode('{"v":1}')),
    );
    await stream.close();

    // PUT v2 with stale ETag should return 409
    stream = await openStream(ctx.host, ctx.serverPeerId, DocumentHandler.protocolId);
    final resp = await DocumentHandler.putDocument(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test/cond-put',
      content: Uint8List.fromList(utf8.encode('{"v":2}')),
      ifMatch: 'stale-etag',
    );
    await stream.close();

    report(_tag, 'Conditional PUT (409 conflict)', resp.isConflict,
        resp.isConflict ? null : 'expected 409, got ${resp.status}');
  } catch (e) {
    report(_tag, 'Conditional PUT (409 conflict)', false, '$e');
  }
}

Future<void> _testHead(TestContext ctx) async {
  try {
    // PUT first
    var stream = await openStream(ctx.host, ctx.serverPeerId, DocumentHandler.protocolId);
    await DocumentHandler.putDocument(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test/head-test',
      content: Uint8List.fromList(utf8.encode('{"head":"test"}')),
      contentType: 'application/json',
    );
    await stream.close();

    // HEAD
    stream = await openStream(ctx.host, ctx.serverPeerId, DocumentHandler.protocolId);
    final resp = await DocumentHandler.headDocument(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test/head-test',
    );
    await stream.close();

    final hasEtag = resp.etag != null && resp.etag!.isNotEmpty;
    final hasContentType = resp.contentType == 'application/json';

    report(_tag, 'HEAD document', resp.isSuccess && hasEtag && hasContentType,
        !resp.isSuccess ? 'status ${resp.status}' :
        !hasEtag ? 'missing ETag' :
        !hasContentType ? 'content-type: ${resp.contentType}' : null);
  } catch (e) {
    report(_tag, 'HEAD document', false, '$e');
  }
}

Future<void> _testPatch(TestContext ctx) async {
  try {
    // PUT initial
    var stream = await openStream(ctx.host, ctx.serverPeerId, DocumentHandler.protocolId);
    await DocumentHandler.putDocument(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test/patchable',
      content: Uint8List.fromList(utf8.encode('{"name":"original","count":1}')),
      contentType: 'application/json',
    );
    await stream.close();

    // PATCH
    stream = await openStream(ctx.host, ctx.serverPeerId, DocumentHandler.protocolId);
    await DocumentHandler.patchDocument(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test/patchable',
      patch: {'count': 2, 'extra': 'field'},
    );
    await stream.close();

    // GET and verify merge
    stream = await openStream(ctx.host, ctx.serverPeerId, DocumentHandler.protocolId);
    final getResp = await DocumentHandler.getDocument(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test/patchable',
    );
    await stream.close();

    if (getResp.body == null) {
      report(_tag, 'PATCH document', false, 'GET returned null body');
      return;
    }

    final result = jsonDecode(utf8.decode(getResp.body!)) as Map<String, dynamic>;
    final nameOk = result['name'] == 'original';
    final countOk = result['count'] == 2;
    final extraOk = result['extra'] == 'field';

    report(_tag, 'PATCH document', nameOk && countOk && extraOk,
        !nameOk ? 'name mismatch: ${result['name']}' :
        !countOk ? 'count mismatch: ${result['count']}' :
        !extraOk ? 'extra mismatch: ${result['extra']}' : null);
  } catch (e) {
    report(_tag, 'PATCH document', false, '$e');
  }
}

Future<void> _testList(TestContext ctx) async {
  try {
    // PUT several docs (some already created above)
    for (final name in ['interop-test/list-a', 'interop-test/list-b', 'interop-test/list-c']) {
      final stream = await openStream(ctx.host, ctx.serverPeerId, DocumentHandler.protocolId);
      await DocumentHandler.putDocument(
        stream,
        ownerPeerId: ctx.localPeerId,
        path: name,
        content: Uint8List.fromList(utf8.encode('content-$name')),
      );
      await stream.close();
    }

    // LIST
    final stream = await openStream(ctx.host, ctx.serverPeerId, DocumentHandler.protocolId);
    final resp = await DocumentHandler.listDocuments(
      stream,
      ownerPeerId: ctx.localPeerId,
    );
    await stream.close();

    // Parse response body — server returns JSON array of document info
    final hasBody = resp.body != null;
    bool enoughDocs = false;
    if (hasBody) {
      final docs = jsonDecode(utf8.decode(resp.body!));
      if (docs is List) {
        enoughDocs = docs.length >= 3;
      }
    }

    report(_tag, 'LIST documents', resp.isSuccess && enoughDocs,
        !resp.isSuccess ? 'status ${resp.status}' :
        !enoughDocs ? 'expected >= 3 docs' : null);
  } catch (e) {
    report(_tag, 'LIST documents', false, '$e');
  }
}

Future<void> _testDelete(TestContext ctx) async {
  try {
    // PUT a doc to delete
    var stream = await openStream(ctx.host, ctx.serverPeerId, DocumentHandler.protocolId);
    await DocumentHandler.putDocument(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test/to-delete',
      content: Uint8List.fromList(utf8.encode('delete me')),
    );
    await stream.close();

    // DELETE
    stream = await openStream(ctx.host, ctx.serverPeerId, DocumentHandler.protocolId);
    final delResp = await DocumentHandler.deleteDocument(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test/to-delete',
    );
    await stream.close();

    // GET should return 404
    stream = await openStream(ctx.host, ctx.serverPeerId, DocumentHandler.protocolId);
    final getResp = await DocumentHandler.getDocument(
      stream,
      ownerPeerId: ctx.localPeerId,
      path: 'interop-test/to-delete',
    );
    await stream.close();

    report(_tag, 'DELETE document', delResp.isSuccess && getResp.isNotFound,
        !delResp.isSuccess ? 'DELETE status ${delResp.status}' :
        !getResp.isNotFound ? 'GET after delete: status ${getResp.status}' : null);
  } catch (e) {
    report(_tag, 'DELETE document', false, '$e');
  }
}

Future<void> _testCrossClientRead(TestContext ctx, PeerId primaryPeerId) async {
  try {
    // Read doc-1 written by primary
    final stream = await openStream(ctx.host, ctx.serverPeerId, DocumentHandler.protocolId);
    final resp = await DocumentHandler.getDocument(
      stream,
      ownerPeerId: primaryPeerId,
      path: 'interop-test/doc-1',
    );
    await stream.close();

    final hasContent = resp.body != null;
    bool contentOk = false;
    if (hasContent) {
      final parsed = jsonDecode(utf8.decode(resp.body!)) as Map<String, dynamic>;
      contentOk = parsed['name'] == 'test-doc' && parsed['value'] == 42;
    }

    report(_tag, 'Cross-client read document', resp.isSuccess && contentOk,
        !resp.isSuccess ? 'status ${resp.status}' :
        !contentOk ? 'content mismatch' : null);
  } catch (e) {
    report(_tag, 'Cross-client read document', false, '$e');
  }
}

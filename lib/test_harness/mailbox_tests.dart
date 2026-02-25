/// Mailbox (MSA/MAA/MMA) integration tests.
///
/// Tests mailbox creation, message submission/retrieval, deletion,
/// and cross-client ACL-based messaging.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:dart_libp2p/core/network/stream.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';

import '../core/mailbox_address.dart';
import '../core/mailbox_types.dart';
import '../core/message_types.dart';
import '../protocol/mma/admin_frame.dart';
import '../protocol/mma/admin_protocol.dart';
import '../protocol/msa/submission_handler.dart';
import '../protocol/maa/access_handler.dart';
import 'test_runner.dart';

const _tag = 'MBX';

/// Run primary mailbox tests (create, submit, retrieve, delete).
Future<void> runPrimaryMailboxTests(TestContext ctx) async {
  await _testCreateMailbox(ctx);
  await _testSubmitAndRetrieve(ctx);
  await _testDeleteMessages(ctx);
}

/// Run primary mailbox setup for cross-client tests.
/// Creates a shared mailbox and grants ACL to secondary.
Future<void> setupCrossClientMailbox(TestContext ctx, PeerId secondaryPeerId) async {
  await _setupSharedMailbox(ctx, secondaryPeerId);
}

/// Run secondary mailbox tests (cross-client messaging).
Future<void> runSecondaryMailboxTests(TestContext ctx, PeerId primaryPeerId) async {
  await _testCrossClientMessaging(ctx, primaryPeerId);
}

// Helper to send MMA requests (no static handler exists for MMA)
Future<MailboxOperationResponse> _sendMmaRequest(
  P2PStream stream,
  MailboxMgmtRequest request,
) async {
  final requestBytes = AdminFrame.encodeRequest(request);

  // Write length-prefixed frame
  final lengthBytes = ByteData(4)..setUint32(0, requestBytes.length);
  final combined = Uint8List(4 + requestBytes.length);
  combined.setRange(0, 4, lengthBytes.buffer.asUint8List());
  combined.setRange(4, 4 + requestBytes.length, requestBytes);
  await stream.write(combined);

  // Read length-prefixed response
  final respLenBytes = await _readExact(stream, 4);
  final respLen = ByteData.sublistView(respLenBytes).getUint32(0);
  final respBytes = await _readExact(stream, respLen);

  return AdminFrame.decodeResponse(respBytes);
}

Future<Uint8List> _readExact(P2PStream stream, int length) async {
  final buffer = <int>[];
  while (buffer.length < length) {
    final remaining = length - buffer.length;
    final chunk = await stream.read(remaining);
    if (chunk.isEmpty) {
      throw StateError('Stream closed after reading ${buffer.length} of $length bytes');
    }
    buffer.addAll(chunk);
  }
  return Uint8List.fromList(buffer);
}

Future<void> _testCreateMailbox(TestContext ctx) async {
  try {
    final address = MailboxAddress(
      ownerId: ctx.localPeerId,
      folderPath: 'interop-test-inbox',
      type: MailboxType.private,
    );

    // Create mailbox via MMA
    var stream = await openStream(ctx.host, ctx.serverPeerId, adminProtocolId);
    final createResp = await _sendMmaRequest(stream, CreateMailboxRequest(
      address: address,
      maxMessages: 100,
      retentionDays: 7,
    ));
    await stream.close();

    // Get mailbox info
    stream = await openStream(ctx.host, ctx.serverPeerId, adminProtocolId);
    final infoResp = await _sendMmaRequest(stream, GetMailboxInfoRequest(
      address: address,
    ));
    await stream.close();

    report(_tag, 'Create mailbox', createResp.success && infoResp.success,
        !createResp.success ? 'create failed: ${createResp.errorMessage}' :
        !infoResp.success ? 'getInfo failed: ${infoResp.errorMessage}' : null);
  } catch (e) {
    report(_tag, 'Create mailbox', false, '$e');
  }
}

Future<void> _testSubmitAndRetrieve(TestContext ctx) async {
  try {
    final payload = Uint8List.fromList(utf8.encode('Hello from integration test!'));

    // Submit message via MSA
    var stream = await openStream(ctx.host, ctx.serverPeerId, SubmissionHandler.protocolId);
    final ack = await SubmissionHandler.submitMessage(
      stream,
      ctx.localPeerId,
      payload,
      priority: MessagePriority.normal,
      folderPath: 'interop-test-inbox',
      persistent: true,
    );
    await stream.close();

    // Retrieve via MAA
    stream = await openStream(ctx.host, ctx.serverPeerId, AccessHandler.protocolId);
    final retrieveResp = await AccessHandler.retrieveMessages(
      stream,
      ctx.localPeerId,
      folderPath: 'interop-test-inbox',
      maxMessages: 10,
    );
    await stream.close();

    final hasMessages = retrieveResp.messages.isNotEmpty;
    bool payloadMatch = false;
    if (hasMessages) {
      payloadMatch = utf8.decode(retrieveResp.messages.first.payload) == 'Hello from integration test!';
    }

    report(_tag, 'Submit and retrieve message', ack.success && hasMessages && payloadMatch,
        !ack.success ? 'submit failed: ${ack.errorMessage}' :
        !hasMessages ? 'no messages retrieved' :
        !payloadMatch ? 'payload mismatch' : null);
  } catch (e) {
    report(_tag, 'Submit and retrieve message', false, '$e');
  }
}

Future<void> _testDeleteMessages(TestContext ctx) async {
  try {
    // First retrieve to get message IDs
    var stream = await openStream(ctx.host, ctx.serverPeerId, AccessHandler.protocolId);
    final retrieveResp = await AccessHandler.retrieveMessages(
      stream,
      ctx.localPeerId,
      folderPath: 'interop-test-inbox',
      maxMessages: 10,
    );
    await stream.close();

    if (retrieveResp.messages.isEmpty) {
      report(_tag, 'Delete messages', false, 'no messages to delete');
      return;
    }

    final messageIds = retrieveResp.messages.map((m) => m.messageId).toList();

    // Delete
    stream = await openStream(ctx.host, ctx.serverPeerId, AccessHandler.protocolId);
    final delAck = await AccessHandler.deleteMessages(stream, messageIds);
    await stream.close();

    // Retrieve again — should be empty
    stream = await openStream(ctx.host, ctx.serverPeerId, AccessHandler.protocolId);
    final afterResp = await AccessHandler.retrieveMessages(
      stream,
      ctx.localPeerId,
      folderPath: 'interop-test-inbox',
      maxMessages: 10,
    );
    await stream.close();

    report(_tag, 'Delete messages', delAck.success && afterResp.messages.isEmpty,
        !delAck.success ? 'delete failed: ${delAck.errorMessage}' :
        afterResp.messages.isNotEmpty ? 'messages still present after delete' : null);
  } catch (e) {
    report(_tag, 'Delete messages', false, '$e');
  }
}

Future<void> _setupSharedMailbox(TestContext ctx, PeerId secondaryPeerId) async {
  try {
    final address = MailboxAddress(
      ownerId: ctx.localPeerId,
      folderPath: 'interop-test-shared',
      type: MailboxType.shared,
    );

    // Create shared mailbox
    var stream = await openStream(ctx.host, ctx.serverPeerId, adminProtocolId);
    final createResp = await _sendMmaRequest(stream, CreateMailboxRequest(
      address: address,
      maxMessages: 100,
      retentionDays: 7,
    ));
    await stream.close();

    // Grant write access to secondary
    stream = await openStream(ctx.host, ctx.serverPeerId, adminProtocolId);
    final grantResp = await _sendMmaRequest(stream, GrantAccessRequest(
      address: address,
      targetPeerId: secondaryPeerId,
      accessMode: AccessMode.readWrite,
    ));
    await stream.close();

    report(_tag, 'Setup shared mailbox + ACL grant', createResp.success && grantResp.success,
        !createResp.success ? 'create failed: ${createResp.errorMessage}' :
        !grantResp.success ? 'grant failed: ${grantResp.errorMessage}' : null);
  } catch (e) {
    report(_tag, 'Setup shared mailbox + ACL grant', false, '$e');
  }
}

Future<void> _testCrossClientMessaging(TestContext ctx, PeerId primaryPeerId) async {
  try {
    final payload = Uint8List.fromList(utf8.encode('Hello from secondary client!'));

    // Secondary submits message to primary's shared mailbox
    var stream = await openStream(ctx.host, ctx.serverPeerId, SubmissionHandler.protocolId);
    final ack = await SubmissionHandler.submitMessage(
      stream,
      primaryPeerId,
      payload,
      priority: MessagePriority.normal,
      folderPath: 'interop-test-shared',
      persistent: true,
    );
    await stream.close();

    // Secondary reads from primary's shared mailbox (has readWrite ACL)
    stream = await openStream(ctx.host, ctx.serverPeerId, AccessHandler.protocolId);
    final retrieveResp = await AccessHandler.retrieveMessages(
      stream,
      primaryPeerId,
      folderPath: 'interop-test-shared',
      maxMessages: 10,
    );
    await stream.close();

    final hasMessages = retrieveResp.messages.isNotEmpty;
    bool payloadMatch = false;
    if (hasMessages) {
      for (final msg in retrieveResp.messages) {
        if (utf8.decode(msg.payload) == 'Hello from secondary client!') {
          payloadMatch = true;
          break;
        }
      }
    }

    report(_tag, 'Cross-client messaging (ACL)', ack.success && hasMessages && payloadMatch,
        !ack.success ? 'submit failed: ${ack.errorMessage}' :
        !hasMessages ? 'no messages in shared mailbox' :
        !payloadMatch ? 'payload not found' : null);
  } catch (e) {
    report(_tag, 'Cross-client messaging (ACL)', false, '$e');
  }
}

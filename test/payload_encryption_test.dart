import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_libp2p/core/crypto/ed25519.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:ricochet/core/message_types.dart';
import 'package:ricochet/core/sf_message.dart';
import 'package:ricochet/crypto/payload_encryption.dart';
import 'package:test/test.dart';

// The same fixed keys and nonce as go-ricochet pkg/client
// TestCrossLanguageVectors; the hex below was produced there.
final senderSeed = Uint8List.fromList(List.filled(32, 0x01));
final recipientSeed = Uint8List.fromList(List.filled(32, 0x02));
final nonce = Uint8List.fromList(List.generate(24, (i) => i));
const senderPeer = '12D3KooWK99VoVxNE7XzyBwXEzW7xhK7Gpv85r9F3V3fyKSUKPH5';
const recipientPeer = '12D3KooWJWoaqZhDaoEFshF7Rh1bpY9ohihFhzcW6d69Lr2NASuq';
const senderX25519Pub = '1b1b58dd50ea14b60da17b790cd02754d970c9bab864ebb3c0f3016fe51d3f57';
const recipientX25519Pub = '60346e7c911a5f6ba154129174cafe75b294ac3bbd5549632f48cec6266f8410';
const senderX25519Priv = '58e86efb75fa4e2c410f46e16de9f6acae1a1703528651b69bc176c088bef36e';
const boundVector =
    '52434532000102030405060708090a0b0c0d0e0f1011121314151617ad5b0b77e4fab9d141c726d795e7d5e1c34cec901852e78daff0992911dd6d9572ff54a3060d404fde16c276f12f2c5ee365806eb4b0b188d1af9784bc21670864cfaf883cd5948da726bed74461f8afee37590c852eb9e0bd7128c220a61df5a036436f5961';
const legacyVector =
    '000102030405060708090a0b0c0d0e0f10111213141516177141d087ac9990c11975e82fa8c06a05ab1db1ce334d8c90a9c4bc1d16d968';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
Uint8List unhex(String s) =>
    Uint8List.fromList([for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);

Future<PeerId> peerOf(Uint8List seed) async =>
    PeerId.fromPublicKey((await generateEd25519KeyPairFromSeed(seed)).publicKey);

void main() {
  late PeerId sender;
  late PeerId recipient;
  late PayloadEncryptor senderEnc;
  late PayloadEncryptor recipientEnc;
  final binding = const PayloadBinding(
      recipientPeerId: recipientPeer, folderPath: 'inbox', messageId: 'msg-0001');

  setUp(() async {
    sender = await peerOf(senderSeed);
    recipient = await peerOf(recipientSeed);
    senderEnc = PayloadEncryptor.fromEd25519Seed(senderSeed);
    recipientEnc = PayloadEncryptor.fromEd25519Seed(recipientSeed);
  });

  test('the fixed seeds give the peer ids the Go client derives', () {
    expect(sender.toBase58(), senderPeer);
    expect(recipient.toBase58(), recipientPeer);
  });

  test('Ed25519 to X25519 conversion matches the Go client', () async {
    expect(hex(ed25519SeedToX25519(senderSeed)), senderX25519Priv);
    expect(hex(senderEnc.x25519PublicKey), senderX25519Pub);
    expect(hex(await peerIdToX25519PublicKey(sender)), senderX25519Pub);
    expect(hex(await peerIdToX25519PublicKey(recipient)), recipientX25519Pub);
  });

  test('sealing with the fixed nonce reproduces the Go ciphertext byte for byte', () async {
    final sealed = await senderEnc.encryptBound(
        Uint8List.fromList(utf8.encode('hello, ricochet')), binding, recipient, nonce: nonce);
    expect(hex(sealed), boundVector);
    final legacy = await senderEnc.encryptLegacy(
        Uint8List.fromList(utf8.encode('hello, ricochet')), recipient, nonce: nonce);
    expect(hex(legacy), legacyVector);
  });

  test('the Go bound ciphertext opens with its binding and is reported bound', () async {
    final got = await recipientEnc.decryptBound(unhex(boundVector), binding, sender);
    expect(utf8.decode(got.payload), 'hello, ricochet');
    expect(got.bound, isTrue);
  });

  test('the Go legacy ciphertext still opens and is reported unbound', () async {
    final got = await recipientEnc.decryptBound(unhex(legacyVector), binding, sender);
    expect(utf8.decode(got.payload), 'hello, ricochet');
    expect(got.bound, isFalse);
  });

  test('a ciphertext moved to another folder, id or recipient is refused', () async {
    final data = unhex(boundVector);
    for (final relabelled in [
      const PayloadBinding(recipientPeerId: recipientPeer, folderPath: 'archive', messageId: 'msg-0001'),
      const PayloadBinding(recipientPeerId: recipientPeer, folderPath: 'inbox', messageId: 'msg-0002'),
      const PayloadBinding(recipientPeerId: senderPeer, folderPath: 'inbox', messageId: 'msg-0001'),
    ]) {
      await expectLater(recipientEnc.decryptBound(data, relabelled, sender),
          throwsA(isA<BoundToAnotherMessageException>()));
    }
  });

  test('the wrong sender or a corrupted byte does not open', () async {
    await expectLater(recipientEnc.decryptBound(unhex(boundVector), binding, recipient),
        throwsA(isA<PayloadDecryptException>()));
    final corrupted = unhex(boundVector)..[40] ^= 1;
    await expectLater(recipientEnc.decryptBound(corrupted, binding, sender),
        throwsA(isA<PayloadDecryptException>()));
  });

  test('a fresh nonce round-trips and an empty folder binds as inbox', () async {
    final b = PayloadBinding.forMessage(recipientPeerId: recipient, folderPath: '', messageId: 'x');
    expect(b.folderPath, 'inbox');
    final sealed = await senderEnc.encryptBound(Uint8List.fromList([1, 2, 3]), b, recipient);
    expect(sealed.sublist(0, 4), boundMagic);
    final got = await recipientEnc.decryptBound(sealed, b, sender);
    expect(got.payload, [1, 2, 3]);
    expect(got.bound, isTrue);
  });

  group('openIfEncrypted', () {
    SFMessage arrived({String? folder, String id = 'msg-0001'}) => SFMessage(
          messageId: id,
          recipientPeerId: recipient,
          senderPeerId: sender,
          payload: unhex(boundVector),
          expiryTimestamp: 0,
          flags: const SFMessageFlags(SFMessageFlags.encrypted),
          folderPath: folder,
        );

    test('opens a message against the envelope it arrived in and clears the flag', () async {
      final opened = await openIfEncrypted(arrived(), recipientEnc);
      expect(utf8.decode(opened.payload), 'hello, ricochet');
      expect(opened.flags.isEncrypted, isFalse);
      expect(opened.messageId, 'msg-0001');
      // An explicit inbox folder is the same envelope.
      expect(utf8.decode((await openIfEncrypted(arrived(folder: 'inbox'), recipientEnc)).payload), 'hello, ricochet');
    });

    test('refuses a message the server re-filed', () async {
      await expectLater(openIfEncrypted(arrived(folder: 'archive'), recipientEnc),
          throwsA(isA<BoundToAnotherMessageException>()));
      await expectLater(openIfEncrypted(arrived(id: 'msg-0002'), recipientEnc),
          throwsA(isA<BoundToAnotherMessageException>()));
    });

    test('names its own layer when there is no key to open with', () async {
      await expectLater(openIfEncrypted(arrived(), null),
          throwsA(predicate((e) => e is PayloadDecryptException && e.toString().startsWith('ricochet payload layer'))));
    });

    test('leaves an unencrypted message alone', () async {
      final plain = arrived().withPayload(Uint8List.fromList([7]), flags: SFMessageFlags.none);
      expect(identical(await openIfEncrypted(plain, null), plain), isTrue);
    });
  });
}

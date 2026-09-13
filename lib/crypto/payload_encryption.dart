/// Payload encryption compatible with the Go client's bound NaCl box
/// (go-ricochet `pkg/client/encryption.go`).
///
/// Wire format sent: `"RCE2"` ‖ 24-byte nonce ‖ box(header ‖ payload), where
/// the box is NaCl box (X25519 agreement between the two identity keys,
/// XSalsa20-Poly1305) and the header is the [PayloadBinding] as three
/// big-endian u16-length-prefixed fields. The binding ties the ciphertext to
/// the message that carries it, so a ciphertext the server moved to another
/// folder, or presented under another id or to another recipient, is
/// refused on decrypt. The legacy unbound format (nonce ‖ box(payload)),
/// which old Go clients sent, still opens and is reported as unbound.
///
/// What this layer is not: it has no forward secrecy (one static key pair
/// per identity, by design; a ratchet belongs above it, as OverNode's Signal
/// sessions are) and it does not detect a replay of the same ciphertext
/// into the same folder.
library;

import 'dart:typed_data';

import 'package:dart_libp2p/core/crypto/keys.dart' as libp2p;
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:pinenacl/tweetnacl.dart';
import 'package:pinenacl/x25519.dart' as nacl;

import '../core/message_types.dart';
import '../core/sf_message.dart';

/// The four bytes that open a bound ciphertext.
const boundMagic = [0x52, 0x43, 0x45, 0x32]; // "RCE2"

const _nonceSize = 24;
const _boxOverhead = 16;
const _maxBindingField = 0xffff;

/// Decryption failed at the Ricochet payload layer, as opposed to any
/// end-to-end layer an application runs above it.
class PayloadDecryptException implements Exception {
  final String message;
  PayloadDecryptException(this.message);
  @override
  String toString() => 'ricochet payload layer: $message';
}

/// The ciphertext opened, but it was sealed for a different message.
class BoundToAnotherMessageException extends PayloadDecryptException {
  final PayloadBinding sealedFor;
  BoundToAnotherMessageException(this.sealedFor)
      : super('ciphertext is bound to another message (recipient '
            '${sealedFor.recipientPeerId}, folder "${sealedFor.folderPath}", '
            'id ${sealedFor.messageId})');
}

/// What a ciphertext is tied to: the message it must arrive as.
class PayloadBinding {
  final String recipientPeerId;
  final String folderPath;
  final String messageId;

  const PayloadBinding({
    required this.recipientPeerId,
    required this.folderPath,
    required this.messageId,
  });

  /// The binding of a message as it will be, or was, submitted. An empty
  /// folder is the inbox, which is where the server delivers it.
  factory PayloadBinding.forMessage({
    required PeerId recipientPeerId,
    required String? folderPath,
    required String messageId,
  }) =>
      PayloadBinding(
        recipientPeerId: recipientPeerId.toBase58(),
        folderPath: (folderPath == null || folderPath.isEmpty) ? 'inbox' : folderPath,
        messageId: messageId,
      );

  factory PayloadBinding.of(SFMessage message) => PayloadBinding.forMessage(
        recipientPeerId: message.recipientPeerId,
        folderPath: message.folderPath,
        messageId: message.messageId,
      );

  /// The binding as length-prefixed fields.
  Uint8List header() {
    final fields = [recipientPeerId, folderPath, messageId].map(_utf8).toList();
    final out = BytesBuilder(copy: false);
    for (final f in fields) {
      if (f.length > _maxBindingField) {
        throw ArgumentError('binding field exceeds $_maxBindingField bytes');
      }
      out.add([f.length >> 8, f.length & 0xff]);
      out.add(f);
    }
    return out.toBytes();
  }

  /// Separates a sealed plaintext into its binding and payload.
  static (PayloadBinding, Uint8List) split(Uint8List plain) {
    final fields = <String>[];
    var offset = 0;
    for (var i = 0; i < 3; i++) {
      if (plain.length - offset < 2) {
        throw PayloadDecryptException('bound payload header truncated');
      }
      final n = (plain[offset] << 8) | plain[offset + 1];
      offset += 2;
      if (plain.length - offset < n) {
        throw PayloadDecryptException('bound payload header truncated');
      }
      fields.add(String.fromCharCodes(plain.sublist(offset, offset + n)));
      offset += n;
    }
    return (
      PayloadBinding(recipientPeerId: fields[0], folderPath: fields[1], messageId: fields[2]),
      Uint8List.sublistView(plain, offset),
    );
  }

  static Uint8List _utf8(String s) => Uint8List.fromList(s.codeUnits);

  @override
  bool operator ==(Object other) =>
      other is PayloadBinding &&
      other.recipientPeerId == recipientPeerId &&
      other.folderPath == folderPath &&
      other.messageId == messageId;

  @override
  int get hashCode => Object.hash(recipientPeerId, folderPath, messageId);

  @override
  String toString() => 'PayloadBinding($recipientPeerId, $folderPath, $messageId)';
}

/// A decrypted payload and whether its ciphertext carried a binding. A
/// caller that wants the replay protection should treat `bound == false`
/// as a downgrade.
class DecryptedPayload {
  final Uint8List payload;
  final bool bound;
  const DecryptedPayload(this.payload, {required this.bound});
}

/// Converts an Ed25519 seed (the 32-byte private key) to the X25519 secret
/// the Go client derives: SHA-512 of the seed, first 32 bytes, clamped.
Uint8List ed25519SeedToX25519(Uint8List seed) {
  if (seed.length != 32) {
    throw ArgumentError('Ed25519 seed must be 32 bytes, got ${seed.length}');
  }
  final out = Uint8List(32);
  TweetNaClExt.crypto_sign_ed25519_sk_to_x25519_sk(out, seed);
  return out;
}

/// Converts an Ed25519 public key to X25519 by the birational map from
/// Edwards to Montgomery form, as the Go client does.
Uint8List ed25519PublicKeyToX25519(Uint8List edPublic) {
  if (edPublic.length != 32) {
    throw ArgumentError('Ed25519 public key must be 32 bytes, got ${edPublic.length}');
  }
  final out = Uint8List(32);
  if (TweetNaClExt.crypto_sign_ed25519_pk_to_x25519_pk(out, edPublic) != 0) {
    throw ArgumentError('invalid Ed25519 public key');
  }
  return out;
}

/// The X25519 public key of a peer, from the Ed25519 key its id embeds.
Future<Uint8List> peerIdToX25519PublicKey(PeerId id) async {
  final pub = await id.extractPublicKey();
  if (pub == null) {
    throw ArgumentError('peer id ${id.toBase58()} does not embed a public key');
  }
  return ed25519PublicKeyToX25519(pub.raw);
}

/// Seals and opens payloads with one identity's key.
class PayloadEncryptor {
  final Uint8List _secret;

  PayloadEncryptor._(this._secret);

  /// From the identity's Ed25519 seed (32 bytes).
  PayloadEncryptor.fromEd25519Seed(Uint8List seed) : this._(ed25519SeedToX25519(seed));

  /// From a libp2p private key. Only a key that still holds its seed can be
  /// used: dart-libp2p keeps it for keys built from a seed with
  /// `Ed25519PrivateKey.fromRawBytes`, and not for others.
  factory PayloadEncryptor.fromLibp2pKey(libp2p.PrivateKey key) {
    final Uint8List raw;
    try {
      raw = key.raw;
    } on UnimplementedError {
      throw StateError('the libp2p private key does not expose its seed; '
          'build the PayloadEncryptor from the Ed25519 seed instead');
    }
    if (raw.length == 64) {
      return PayloadEncryptor.fromEd25519Seed(Uint8List.sublistView(raw, 0, 32));
    }
    return PayloadEncryptor.fromEd25519Seed(raw);
  }

  /// This identity's X25519 public key, for tests and diagnostics.
  Uint8List get x25519PublicKey =>
      Uint8List.fromList(nacl.PrivateKey(_secret).publicKey.asTypedList);

  nacl.Box _boxWith(Uint8List theirX25519) => nacl.Box(
        myPrivateKey: nacl.PrivateKey(_secret),
        theirPublicKey: nacl.PublicKey(theirX25519),
      );

  /// Seals [payload] for [recipient], tied to [binding]. This is what the
  /// client sends. A caller-supplied [nonce] is for test vectors only.
  Future<Uint8List> encryptBound(
    Uint8List payload,
    PayloadBinding binding,
    PeerId recipient, {
    Uint8List? nonce,
  }) async {
    final plain = BytesBuilder(copy: false)
      ..add(binding.header())
      ..add(payload);
    final sealed = await encryptLegacy(plain.toBytes(), recipient, nonce: nonce);
    final out = BytesBuilder(copy: false)
      ..add(boundMagic)
      ..add(sealed);
    return out.toBytes();
  }

  /// Seals [payload] in the legacy unbound format: nonce ‖ box(payload).
  /// Nothing ties it to a message; the client sends [encryptBound].
  Future<Uint8List> encryptLegacy(Uint8List payload, PeerId recipient, {Uint8List? nonce}) async {
    if (nonce != null && nonce.length != _nonceSize) {
      throw ArgumentError('nonce must be $_nonceSize bytes');
    }
    final box = _boxWith(await peerIdToX25519PublicKey(recipient));
    final sealed = box.encrypt(payload, nonce: nonce);
    return Uint8List.fromList(sealed.asTypedList);
  }

  /// Opens a ciphertext and checks that it was sealed for exactly the
  /// message it arrived as ([want]). A legacy ciphertext still opens and
  /// is reported as unbound.
  Future<DecryptedPayload> decryptBound(Uint8List encrypted, PayloadBinding want, PeerId sender) async {
    final box = _boxWith(await peerIdToX25519PublicKey(sender));
    if (encrypted.length > boundMagic.length && _hasMagic(encrypted)) {
      final plain = _open(box, Uint8List.sublistView(encrypted, boundMagic.length));
      if (plain != null) {
        final (got, payload) = PayloadBinding.split(plain);
        if (got != want) {
          throw BoundToAnotherMessageException(got);
        }
        return DecryptedPayload(Uint8List.fromList(payload), bound: true);
      }
      // A legacy nonce that happens to begin with the magic falls through.
    }
    final plain = _open(box, encrypted);
    if (plain == null) {
      throw PayloadDecryptException('decryption failed (wrong key or corrupted data)');
    }
    return DecryptedPayload(plain, bound: false);
  }

  static bool _hasMagic(Uint8List data) {
    for (var i = 0; i < boundMagic.length; i++) {
      if (data[i] != boundMagic[i]) return false;
    }
    return true;
  }

  static Uint8List? _open(nacl.Box box, Uint8List sealed) {
    if (sealed.length < _nonceSize + _boxOverhead) return null;
    try {
      return box.decrypt(nacl.EncryptedMessage.fromList(sealed));
    } catch (_) {
      return null;
    }
  }
}

/// Returns [message] with its payload opened when it is flagged encrypted,
/// checked against the envelope it arrived in; otherwise unchanged.
///
/// Throws [PayloadDecryptException] naming this layer when there is no
/// [encryptor] to open it with, or the ciphertext does not open, or it was
/// sealed for a different message.
Future<SFMessage> openIfEncrypted(SFMessage message, PayloadEncryptor? encryptor) async {
  if (!message.flags.isEncrypted) return message;
  if (encryptor == null) {
    throw PayloadDecryptException(
        'message ${message.messageId} is encrypted and this client has no PayloadEncryptor to open it');
  }
  final opened = await encryptor.decryptBound(message.payload, PayloadBinding.of(message), message.senderPeerId);
  return message.withPayload(opened.payload, flags: message.flags.withoutFlag(SFMessageFlags.encrypted));
}

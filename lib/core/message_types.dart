/// Store-and-Forward message types extending OBP protocol
/// 
/// These message types (0x30-0x3B) extend the OverNode Binary Protocol (OBP)
/// to support store-and-forward messaging operations.

/// S&F Message Types (0x30-0x3B range)
enum SFMessageType {
  // Storage Operations (0x30-0x31)
  storeMessage(0x30),
  storeAck(0x31),
  
  // Retrieval Operations (0x32-0x35)
  retrieveMessages(0x32),
  retrieveResp(0x33),
  markDelivered(0x34),
  markDeliveredAck(0x35),
  
  // Forwarding Operations (0x36-0x37)
  forwardMessage(0x36),
  forwardAck(0x37),
  
  // Management Operations (0x38-0x3B)
  queryCapacity(0x38),
  capacityResp(0x39),
  setPriority(0x3A),
  setExpiry(0x3B),
  
  // IMAP-Style Flag Operations (0x3C-0x3F)
  updateFlags(0x3C),
  updateFlagsAck(0x3D),
  expunge(0x3E),
  expungeAck(0x3F),
  
  // Direct Message Deletion (0x40-0x41)
  deleteMessages(0x40),
  deleteMessagesAck(0x41);
  
  const SFMessageType(this.value);
  
  final int value;
  
  static SFMessageType fromValue(int value) {
    for (final type in SFMessageType.values) {
      if (type.value == value) return type;
    }
    throw ArgumentError('Unknown S&F message type: 0x${value.toRadixString(16)}');
  }
  
  @override
  String toString() => 'SFMessageType.${name}(0x${value.toRadixString(16)})';
}

/// Message priority levels
enum MessagePriority {
  low(0),
  normal(1),
  high(2),
  urgent(3);
  
  const MessagePriority(this.value);
  
  final int value;
  
  static MessagePriority fromValue(int value) {
    if (value < 0 || value > 3) {
      throw ArgumentError('Invalid priority value: $value (must be 0-3)');
    }
    return MessagePriority.values[value];
  }
  
  @override
  String toString() => name;
}

/// Message flags for S&F operations
class SFMessageFlags {
  final int value;
  
  const SFMessageFlags(this.value);
  
  // Flag bits
  static const int encrypted = 1 << 0;  // Message payload is encrypted
  static const int signed = 1 << 1;     // Message is cryptographically signed
  static const int compressed = 1 << 2; // Payload is compressed
  static const int requireAck = 1 << 3; // Requires delivery acknowledgment
  static const int forwarded = 1 << 4;  // Message has been forwarded
  
  static const SFMessageFlags none = SFMessageFlags(0);
  
  bool hasFlag(int flag) => (value & flag) != 0;
  
  bool get isEncrypted => hasFlag(encrypted);
  bool get isSigned => hasFlag(signed);
  bool get isCompressed => hasFlag(compressed);
  bool get requiresAck => hasFlag(requireAck);
  bool get isForwarded => hasFlag(forwarded);
  
  SFMessageFlags withFlag(int flag) => SFMessageFlags(value | flag);
  SFMessageFlags withoutFlag(int flag) => SFMessageFlags(value & ~flag);
  
  @override
  String toString() {
    final flags = <String>[];
    if (isEncrypted) flags.add('encrypted');
    if (isSigned) flags.add('signed');
    if (isCompressed) flags.add('compressed');
    if (requiresAck) flags.add('requireAck');
    if (isForwarded) flags.add('forwarded');
    return flags.isEmpty ? 'none' : flags.join('|');
  }
  
  @override
  bool operator ==(Object other) =>
      other is SFMessageFlags && other.value == value;
  
  @override
  int get hashCode => value.hashCode;
}


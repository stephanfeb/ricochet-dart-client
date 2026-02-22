/// IMAP-style message flags
library;

/// Message flags using bitmap for efficient storage
class MessageFlags {
  final int bitmap;
  
  /// Flag constants
  static const int seen = 1 << 0;      // Message has been read
  static const int flagged = 1 << 1;   // Message is flagged/starred
  static const int deleted = 1 << 2;   // Message marked for deletion
  static const int draft = 1 << 3;     // Message is a draft
  
  const MessageFlags(this.bitmap);
  const MessageFlags.none() : bitmap = 0;
  
  /// Check individual flags
  bool get isSeen => (bitmap & seen) != 0;
  bool get isFlagged => (bitmap & flagged) != 0;
  bool get isDeleted => (bitmap & deleted) != 0;
  bool get isDraft => (bitmap & draft) != 0;
  
  /// Create new flags with additional flag set
  MessageFlags withSeen() => MessageFlags(bitmap | seen);
  MessageFlags withFlagged() => MessageFlags(bitmap | flagged);
  MessageFlags withDeleted() => MessageFlags(bitmap | deleted);
  MessageFlags withDraft() => MessageFlags(bitmap | draft);
  
  /// Create new flags with flag removed
  MessageFlags withoutSeen() => MessageFlags(bitmap & ~seen);
  MessageFlags withoutFlagged() => MessageFlags(bitmap & ~flagged);
  MessageFlags withoutDeleted() => MessageFlags(bitmap & ~deleted);
  MessageFlags withoutDraft() => MessageFlags(bitmap & ~draft);
  
  @override
  String toString() {
    final flags = <String>[];
    if (isSeen) flags.add('seen');
    if (isFlagged) flags.add('flagged');
    if (isDeleted) flags.add('deleted');
    if (isDraft) flags.add('draft');
    return flags.isEmpty ? 'none' : flags.join(', ');
  }
  
  @override
  bool operator ==(Object other) =>
      other is MessageFlags && other.bitmap == bitmap;
  
  @override
  int get hashCode => bitmap.hashCode;
}


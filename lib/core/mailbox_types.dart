/// Mailbox type definitions for store-and-forward system
library;

/// Type of mailbox determining access patterns
enum MailboxType {
  /// Private mailbox - single owner, single reader
  /// Messages deleted after retrieval unless marked persistent
  private,
  
  /// Shared mailbox - multiple authorized readers with independent cursors
  /// Messages persist, each reader tracks their own position
  shared,
  
  /// Public mailbox - anyone can read, only authorized can write
  /// Implements retention policies (time/count based)
  public,
}

/// Access mode for mailbox ACL
enum AccessMode {
  /// Can only read messages
  readOnly,
  
  /// Can only write messages (e.g., publishers in public mailboxes)
  writeOnly,
  
  /// Full read and write access
  readWrite,
}


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

  /// Claim mailbox - items its owner hands out one at a time, such as
  /// Signal one-time prekeys. Only the owner stores into it or lists it;
  /// anyone may claim one with [SFClient.claimMessage], which takes the
  /// oldest message and deletes it, so no two claimers get the same one.
  /// Needs go-ricochet 1.6.0 or later.
  claim,
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


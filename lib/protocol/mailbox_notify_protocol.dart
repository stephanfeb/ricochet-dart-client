/// Libp2p protocol for mailbox notifications
/// 
/// Implements hybrid push notification system:
/// - Private mailboxes: Direct P2P stream protocol (1:1 efficient delivery)
/// - Public/Shared mailboxes: GossipSub topics (1:many efficient broadcasting)
library;

import '../core/mailbox_types.dart';

/// Direct stream protocol for private mailbox notifications
const String mailboxNotifyProtocolId = '/ricochet/mailbox-notify/1.0.0';

/// GossipSub topic pattern for public/shared mailboxes
/// Format: /ricochet/mailbox/{ownerPeerId}/{folderPath}
String getMailboxTopic(String ownerPeerId, String folderPath) =>
  '/ricochet/mailbox/$ownerPeerId/${folderPath.replaceAll('/', '_')}';

/// Notification message format (used by both mechanisms)
class MailboxNotification {
  final String mailboxPath;
  final MailboxType mailboxType;
  final int messageCount;
  final int timestamp;
  
  /// The S&F server that sent this notification (for direct P2P notifications).
  /// Null for GossipSub notifications. Used to ensure retrieval happens from
  /// the same server that has the message.
  final String? serverPeerId;
  
  MailboxNotification({
    required this.mailboxPath,
    required this.mailboxType,
    required this.messageCount,
    required this.timestamp,
    this.serverPeerId,
  });
  
  /// Create a copy with a different serverPeerId
  MailboxNotification withServerPeerId(String peerId) => MailboxNotification(
    mailboxPath: mailboxPath,
    mailboxType: mailboxType,
    messageCount: messageCount,
    timestamp: timestamp,
    serverPeerId: peerId,
  );
  
  Map<String, dynamic> toJson() => {
    'mailboxPath': mailboxPath,
    'mailboxType': mailboxType.name,
    'messageCount': messageCount,
    'timestamp': timestamp,
    if (serverPeerId != null) 'serverPeerId': serverPeerId,
  };
  
  factory MailboxNotification.fromJson(Map<String, dynamic> json) =>
    MailboxNotification(
      mailboxPath: json['mailboxPath'] as String,
      mailboxType: MailboxType.values.byName(json['mailboxType'] as String),
      messageCount: json['messageCount'] as int,
      timestamp: json['timestamp'] as int,
      serverPeerId: json['serverPeerId'] as String?,
    );
  
  @override
  String toString() => 'MailboxNotification(${mailboxType.name}: $mailboxPath, count: $messageCount, server: ${serverPeerId?.substring(0, 12) ?? 'none'}...)';
}


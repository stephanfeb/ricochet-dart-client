/// Mailbox addressing for folder-based store-and-forward
library;

import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'mailbox_types.dart';

/// Address for a specific mailbox (peer + folder)
class MailboxAddress {
  final PeerId ownerId;
  final String folderPath;
  final MailboxType type;
  
  MailboxAddress({
    required this.ownerId,
    required this.folderPath,
    required this.type,
  }) {
    _validateFolderPath(folderPath);
  }
  
  /// Validate folder path format
  static void _validateFolderPath(String path) {
    if (path.isEmpty) {
      throw ArgumentError('Folder path cannot be empty');
    }
    if (path.startsWith('/')) {
      throw ArgumentError('Folder path cannot start with /');
    }
    if (path.endsWith('/')) {
      throw ArgumentError('Folder path cannot end with /');
    }
    if (path.contains('//')) {
      throw ArgumentError('Folder path cannot contain //');
    }
  }
  
  /// Full path identifier: "peerID/folder/path"
  String get fullPath => '${ownerId.toBase58()}/$folderPath';
  
  /// Create default inbox address for a peer
  factory MailboxAddress.inbox(PeerId ownerId) {
    return MailboxAddress(
      ownerId: ownerId,
      folderPath: 'inbox',
      type: MailboxType.private,
    );
  }
  
  /// Parse from full path string: "12D3KooW.../folder/path"
  factory MailboxAddress.parse(String fullPath, {MailboxType? type}) {
    final parts = fullPath.split('/');
    if (parts.length < 2) {
      throw ArgumentError('Invalid mailbox path: $fullPath');
    }
    
    final peerIdStr = parts[0];
    final folder = parts.sublist(1).join('/');
    
    return MailboxAddress(
      ownerId: PeerId.fromString(peerIdStr),
      folderPath: folder,
      type: type ?? MailboxType.private,  // Default to private if not specified
    );
  }
  
  @override
  String toString() => fullPath;
  
  @override
  bool operator ==(Object other) =>
      other is MailboxAddress &&
      other.ownerId == ownerId &&
      other.folderPath == folderPath &&
      other.type == type;
  
  @override
  int get hashCode => Object.hash(ownerId, folderPath, type);
}


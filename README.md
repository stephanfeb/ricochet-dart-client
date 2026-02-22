# Ricochet Dart Client

Dart client library for the Ricochet P2P store-and-forward messaging network.

This is a **protocol-level client library** — it provides a high-level API for
sending/receiving messages, managing mailboxes, storing documents, and tracking
presence over the Ricochet S&F protocol. It is designed to work with any
Ricochet-compatible server implementation.

**This library does not manage networking.** It expects a fully configured
`dart_libp2p` Host (and optionally PubSub) to be injected by the application.
The application is responsible for creating the libp2p host, configuring
transports, discovery, and connection management. This library only operates
on top of that stack by opening libp2p streams to S&F servers using the
Ricochet protocol IDs.

## Installation

```yaml
dependencies:
  ricochet:
    path: ../ricochet-dart-client
```

## Usage

```dart
import 'package:ricochet/ricochet.dart';
```

### Prerequisites

The application must provide:

- A **`dart_libp2p` Host** — already started, with transports configured and
  the S&F server addresses in its peerstore.
- A **`PubSub` instance** (optional) — only needed for presence tracking.
  The same GossipSub instance used by the rest of the application.

This library never creates or manages these — it only uses them.

### Create and start the client

```dart
// The application creates and owns the libp2p host and pubsub
final host = await buildLibp2pHost(...);  // your setup
final pubsub = PubSub(host);             // your setup

// Configure with your preferred S&F servers (MX-style priority)
final config = SFClientConfig.withServers([
  SFServerPreference(serverId: serverPeerId, priority: 10),
]);

// Inject the host and pubsub into the client
final client = SFClient(
  host: host,        // required — application-managed libp2p Host
  config: config,
  pubsub: pubsub,   // optional — enables presence tracking
);

await client.start();
```

### Send a message

Messages are automatically routed via S&F servers for offline delivery.

```dart
final result = await client.sendMessage(
  recipient: recipientPeerId,
  payload: utf8.encode('Hello!'),
  priority: MessagePriority.normal,
  folderPath: 'inbox',       // target folder (default: inbox)
  persistent: false,          // remove after reading
);

if (result.success) {
  print('Stored at server: ${result.storedAtServer}');
}
```

### Retrieve messages

```dart
// Own messages
final messages = await client.retrieveMessages();

// From another peer's public mailbox
final publicMessages = await client.retrieveMessages(
  targetPeerId: otherPeerId,
  folderPath: 'announcements',
);
```

### IMAP-style flag operations

```dart
// Mark as read
await client.markDelivered(messageIds: ['msg-1', 'msg-2']);

// Update flags
await client.updateFlags(messageId: 'msg-1', addFlags: MessageFlags.flagged);

// Soft-delete then expunge
await client.updateFlags(messageId: 'msg-1', addFlags: MessageFlags.deleted);
await client.expunge();

// Hard-delete
await client.deleteMessages(messageIds: ['msg-1']);
```

### Mailbox management

```dart
final mailboxes = client.mailboxes;

// Create a shared mailbox
await mailboxes.createMailbox(
  folderPath: 'team-updates',
  type: MailboxType.shared,
);

// Grant access
await mailboxes.grantAccess(
  folderPath: 'team-updates',
  type: MailboxType.shared,
  targetPeerId: colleaguePeerId,
  accessMode: AccessMode.readWrite,
);

// List ACLs
final acl = await mailboxes.listACL(
  folderPath: 'team-updates',
  type: MailboxType.shared,
);
```

### Document store

Per-user key-value document storage with ETag versioning.

```dart
// Store a document
final putResult = await client.putDocument(
  path: 'profile',
  content: utf8.encode(jsonEncode({'name': 'Alice'})),
  contentType: 'application/json',
);

// Retrieve a document
final doc = await client.getDocument(path: 'profile');

// Conditional GET (returns 304 if unchanged)
final doc2 = await client.getDocument(
  path: 'profile',
  ifNoneMatch: putResult.etag,
);

// JSON Merge Patch
await client.patchDocument(
  path: 'profile',
  patch: {'bio': 'Updated bio'},
);

// List all documents
final listing = await client.listDocuments();
```

### Peer directory

Opt-in server directory for peer discovery.

```dart
// Join the directory
await client.joinDirectory(displayName: 'Alice', bio: 'Hello!');

// Browse the directory
final results = await client.browseDirectory(limit: 20);

// Leave the directory
await client.leaveDirectory();
```

### Presence tracking

Requires PubSub (GossipSub) to be passed when constructing `SFClient`.

```dart
final tracker = client.presenceTracker;

// Track a contact's online/offline status
tracker.trackContact(contactPeerId, serverPeerId);

// Listen for changes
tracker.contactPresenceChanges.listen((change) {
  print('${change.peerId} is now ${change.state.name}');
});

// Check status
if (tracker.isOnline(contactPeerId)) {
  print('Contact is online');
}
```

### Ricochet URIs

Stable, owner-centric resource addressing.

```dart
// Format: ricochet://<ownerPeerId>/<resourceType>/<path>[?servers=...]
final uri = RicochetUri(
  ownerPeerId: peerId,
  resourceType: RicochetResourceType.doc,
  path: 'profile',
);

print(uri.toString());
// ricochet://12D3KooW.../doc/profile
```

## Architecture

```
lib/
  ricochet.dart              # Barrel export file
  client/
    sf_client.dart           # High-level client API (main entry point)
    sf_client_config.dart    # Client configuration
    mailbox_manager.dart     # Mailbox CRUD and ACL management
    message_sender.dart      # Message routing with retries & failover
    server_selector.dart     # MX-style server selection & health checking
    presence_tracker.dart    # GossipSub presence subscription
  core/
    sf_message.dart          # Core message type + request/response types
    mailbox_address.dart     # Mailbox addressing (owner/folder/type)
    mailbox_types.dart       # MailboxType, AccessMode enums
    message_types.dart       # MessagePriority enum
    message_flags.dart       # IMAP-style flags (seen, flagged, deleted, draft)
  protocol/
    maa/                     # Mail Access Agent (read path)
      access_handler.dart    # Client-side retrieve, flags, expunge, delete
      access_frame.dart      # Wire encoding/decoding
    msa/                     # Mail Submission Agent (write path)
      submission_handler.dart  # Client-side message submission
      submission_frame.dart    # Wire encoding/decoding
    mma/                     # Mailbox Management Agent (admin)
      admin_protocol.dart    # Request/response/error types
      admin_frame.dart       # Wire encoding/decoding
    sda/                     # Store Document Access
      document_handler.dart  # Client-side GET/PUT/PATCH/HEAD/DELETE/LIST
      document_frame.dart    # Wire encoding/decoding
      document_crdt.dart     # CRDT merge support
    mailbox_notify_protocol.dart  # Push notification protocol
    sf_frame.dart            # Legacy frame utilities
    stream_utils.dart        # Stream read helpers
  presence/
    presence_cache.dart      # TTL-based presence cache
    presence_event.dart      # Presence event/heartbeat types
  registry/
    peer_preferences.dart    # MX-style server preference records
  uri/
    ricochet_uri.dart        # Owner-centric URI scheme
    ricochet_uri_resolver.dart  # URI resolution via DHT/direct
```

## Protocol IDs

| Protocol | ID | Purpose |
|----------|----|---------|
| MSA | `/sf-network/submit/1.0.0` | Message submission |
| MAA | `/sf-network/access/1.0.0` | Message retrieval & flags |
| MMA | `/sf-network/admin/1.0.0` | Mailbox management |
| SDA | `/ricochet/store/doc/1.0.0` | Document storage |
| Notify | `/ricochet/mailbox-notify/1.0.0` | Push notifications |

## Server compatibility

This client works with any server implementing the above protocols:

- [ricochet](../ricochet) — Reference S&F server implementation
- [go-ricochet](../go-ricochet) — Go S&F server implementation

/// Ricochet — Dart client library for P2P store-and-forward messaging.
///
/// A protocol-level client that provides a high-level API for sending/receiving
/// messages and managing documents via Ricochet S&F servers over libp2p.
///
/// **This library does not manage networking.** It expects a fully configured
/// `dart_libp2p` [Host] (and optionally [PubSub]) to be injected by the
/// application. It only opens libp2p streams to S&F servers using the Ricochet
/// protocol IDs.
///
/// ## Quick start
///
/// ```dart
/// import 'package:ricochet/ricochet.dart';
///
/// // Application creates and owns the libp2p host
/// final host = await buildLibp2pHost(...);
///
/// // Configure with your preferred S&F servers
/// final config = SFClientConfig.withServers([
///   SFServerPreference(serverId: serverPeerId, priority: 10),
/// ]);
///
/// // Inject the host into the client
/// final client = SFClient(host: host, config: config);
/// await client.start();
///
/// // Send a message (routed via S&F server)
/// final result = await client.sendMessage(
///   recipient: recipientPeerId,
///   payload: utf8.encode('Hello!'),
/// );
///
/// // Retrieve pending messages
/// final messages = await client.retrieveMessages();
/// ```
///
/// ## Protocols
///
/// The client communicates with Ricochet S&F servers using four libp2p
/// stream protocols:
///
/// - **MSA** (Mail Submission Agent) — Submit messages for delivery
/// - **MAA** (Mail Access Agent) — Retrieve messages and manage flags
/// - **MMA** (Mailbox Management Agent) — Create/delete mailboxes, manage ACLs
/// - **SDA** (Store Document Access) — GET/PUT/PATCH/DELETE documents
///
/// Server selection uses MX-style priority records ([SFServerPreference])
/// with automatic failover and capacity-based routing.
///
/// ## Key classes
///
/// - [SFClient] — Main entry point (requires an injected [Host])
/// - [SFClientConfig] — Client configuration
/// - [MailboxManager] — Mailbox lifecycle and ACL management
/// - [PresenceTracker] — Contact online/offline tracking (requires injected [PubSub])
/// - [RicochetUri] — Owner-centric URI scheme for addressing resources
library ricochet;

// ---------------------------------------------------------------------------
// Client API
// ---------------------------------------------------------------------------
export 'client/sf_client.dart';
export 'client/sf_client_config.dart';
export 'client/mailbox_manager.dart';
export 'client/message_sender.dart' show SendResult;
export 'client/server_selector.dart';
export 'client/presence_tracker.dart';

// ---------------------------------------------------------------------------
// Core types
// ---------------------------------------------------------------------------
export 'core/sf_message.dart';
export 'core/mailbox_address.dart';
export 'core/mailbox_types.dart';
export 'core/message_types.dart';
export 'core/message_flags.dart';

// ---------------------------------------------------------------------------
// Protocol types (shared request/response definitions)
// ---------------------------------------------------------------------------
export 'protocol/mma/admin_protocol.dart';
export 'protocol/mma/admin_frame.dart';
export 'protocol/mailbox_notify_protocol.dart';
export 'protocol/sda/document_frame.dart';
export 'protocol/sda/document_handler.dart';
export 'protocol/sfa/feed_frame.dart';
export 'protocol/sfa/feed_handler.dart';
export 'protocol/sca/collection_frame.dart';
export 'protocol/sca/collection_handler.dart';
export 'protocol/overmedia/overmedia_frame.dart';
export 'protocol/overmedia/token_handler.dart';
export 'protocol/overmedia/room_handler.dart';
export 'protocol/overmedia/session_handler.dart';
export 'protocol/overmedia/discovery_handler.dart';
export 'protocol/overmedia/recording_handler.dart';

// ---------------------------------------------------------------------------
// Presence
// ---------------------------------------------------------------------------
export 'presence/presence_cache.dart';
export 'presence/presence_event.dart';

// ---------------------------------------------------------------------------
// Server preferences & URI
// ---------------------------------------------------------------------------
export 'registry/peer_preferences.dart';
export 'uri/ricochet_uri.dart';
export 'uri/ricochet_uri_resolver.dart';

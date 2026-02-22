import 'package:dart_libp2p/core/peer/peer_id.dart';

/// Resource types supported by Ricochet URI scheme
enum RicochetResourceType {
  /// Document Store resources
  doc,
  
  /// Mailbox resources
  mailbox;
  
  /// Parse from string representation
  static RicochetResourceType fromString(String value) {
    switch (value) {
      case 'doc':
        return RicochetResourceType.doc;
      case 'mailbox':
        return RicochetResourceType.mailbox;
      default:
        throw FormatException('Invalid resource type: $value');
    }
  }
  
  /// Convert to string representation
  String toStringValue() {
    switch (this) {
      case RicochetResourceType.doc:
        return 'doc';
      case RicochetResourceType.mailbox:
        return 'mailbox';
    }
  }
}

/// Represents a stable owner-centric URI in the Ricochet P2P network
/// 
/// Format: ricochet://<ownerPeerId>/<resourceType>/<path>[?servers=<s1>,<s2>][&etag=<etag>]
/// 
/// The URI identifies resources by owner (stable identity), with servers as
/// resolution hints that can change without affecting resource identity.
/// 
/// Examples:
/// - ricochet://12D3KooWBob.../doc/profile?servers=12D3KooWRico...
/// - ricochet://12D3KooWBob.../doc/avatar?servers=12D3KooWRico1...,12D3KooWRico2...
/// - ricochet://12D3KooWBob.../mailbox/INBOX?servers=12D3KooWRico...
class RicochetUri {
  /// The peer who owns this resource (stable identity)
  final PeerId ownerPeerId;
  
  /// Type of resource (doc or mailbox)
  final RicochetResourceType resourceType;
  
  /// Resource path (e.g., "profile", "avatar", "INBOX")
  final String path;
  
  /// Server PeerIds in priority order (resolution hints)
  final List<PeerId> servers;
  
  /// Optional ETag for conditional requests/caching
  final String? etag;
  
  RicochetUri({
    required this.ownerPeerId,
    required this.resourceType,
    required this.path,
    List<PeerId>? servers,
    this.etag,
  }) : servers = servers ?? [];
  
  /// Create a document URI
  factory RicochetUri.document({
    required PeerId owner,
    required String path,
    List<PeerId>? servers,
    String? etag,
  }) {
    return RicochetUri(
      ownerPeerId: owner,
      resourceType: RicochetResourceType.doc,
      path: path,
      servers: servers,
      etag: etag,
    );
  }
  
  /// Create a mailbox URI
  factory RicochetUri.mailbox({
    required PeerId owner,
    required String path,
    List<PeerId>? servers,
    String? etag,
  }) {
    return RicochetUri(
      ownerPeerId: owner,
      resourceType: RicochetResourceType.mailbox,
      path: path,
      servers: servers,
      etag: etag,
    );
  }
  
  /// Parse a Ricochet URI from string
  /// 
  /// Throws [FormatException] if the URI is malformed
  factory RicochetUri.parse(String uriString) {
    final uri = Uri.parse(uriString);
    
    // Validate scheme
    if (uri.scheme != 'ricochet') {
      throw FormatException('Invalid scheme: ${uri.scheme}, expected "ricochet"');
    }
    
    // Parse owner PeerId from authority
    if (uri.host.isEmpty) {
      throw FormatException('Missing owner PeerId in authority');
    }
    final ownerPeerId = PeerId.fromString(uri.host);
    
    // Parse path segments: /<resourceType>/<path>
    if (uri.pathSegments.isEmpty) {
      throw FormatException('Missing resource type in path');
    }
    if (uri.pathSegments.length < 2) {
      throw FormatException('Missing resource path');
    }
    
    final resourceType = RicochetResourceType.fromString(uri.pathSegments[0]);
    final path = uri.pathSegments.sublist(1).join('/');
    
    // Parse query parameters
    List<PeerId> servers = [];
    if (uri.queryParameters.containsKey('servers')) {
      final serversList = uri.queryParameters['servers']!.split(',');
      servers = serversList.map((s) => PeerId.fromString(s.trim())).toList();
    }
    
    final etag = uri.queryParameters['etag'];
    
    return RicochetUri(
      ownerPeerId: ownerPeerId,
      resourceType: resourceType,
      path: path,
      servers: servers,
      etag: etag,
    );
  }
  
  /// Convert to full URI string with all query parameters
  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('ricochet://');
    buffer.write(ownerPeerId.toCid().toString());
    buffer.write('/');
    buffer.write(resourceType.toStringValue());
    buffer.write('/');
    buffer.write(path);
    
    // Add query parameters if present
    final queryParams = <String>[];
    if (servers.isNotEmpty) {
      final serverList = servers.map((s) => s.toCid().toString()).join(',');
      queryParams.add('servers=$serverList');
    }
    if (etag != null) {
      queryParams.add('etag=$etag');
    }
    
    if (queryParams.isNotEmpty) {
      buffer.write('?');
      buffer.write(queryParams.join('&'));
    }
    
    return buffer.toString();
  }
  
  /// Get canonical form (no query params) for identity comparison
  /// 
  /// Two URIs with the same canonical form reference the same resource,
  /// regardless of server hints or ETags.
  String toCanonical() {
    return 'ricochet://${ownerPeerId.toCid().toString()}/${resourceType.toStringValue()}/$path';
  }
  
  /// Two URIs are equal if their canonical forms match
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RicochetUri) return false;
    return toCanonical() == other.toCanonical();
  }
  
  @override
  int get hashCode => toCanonical().hashCode;
  
  /// Create a copy with updated server hints
  RicochetUri withServers(List<PeerId> newServers) {
    return RicochetUri(
      ownerPeerId: ownerPeerId,
      resourceType: resourceType,
      path: path,
      servers: newServers,
      etag: etag,
    );
  }
  
  /// Create a copy with updated ETag
  RicochetUri withEtag(String? newEtag) {
    return RicochetUri(
      ownerPeerId: ownerPeerId,
      resourceType: resourceType,
      path: path,
      servers: servers,
      etag: newEtag,
    );
  }
  
  /// Create a copy with specified fields updated
  RicochetUri copyWith({
    PeerId? ownerPeerId,
    RicochetResourceType? resourceType,
    String? path,
    List<PeerId>? servers,
    String? etag,
  }) {
    return RicochetUri(
      ownerPeerId: ownerPeerId ?? this.ownerPeerId,
      resourceType: resourceType ?? this.resourceType,
      path: path ?? this.path,
      servers: servers ?? this.servers,
      etag: etag ?? this.etag,
    );
  }
}


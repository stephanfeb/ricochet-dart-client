import 'dart:typed_data';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:logging/logging.dart';
import 'package:ricochet/client/sf_client.dart';
import 'package:ricochet/uri/ricochet_uri.dart';

/// Result of resolving a document URI
class ResolvedDocument {
  /// Document content bytes
  final Uint8List content;
  
  /// MIME content type
  final String contentType;
  
  /// ETag for caching/versioning
  final String etag;
  
  /// Last modification timestamp
  final DateTime lastModified;
  
  /// Which server successfully provided the document
  final PeerId resolvedFromServer;
  
  /// Original URI that was resolved
  final RicochetUri originalUri;
  
  ResolvedDocument({
    required this.content,
    required this.contentType,
    required this.etag,
    required this.lastModified,
    required this.resolvedFromServer,
    required this.originalUri,
  });
  
  /// Get optimized URI with successful server prioritized
  RicochetUri get optimizedUri {
    // Move the successful server to the front
    final optimizedServers = [
      resolvedFromServer,
      ...originalUri.servers.where((s) => s != resolvedFromServer),
    ];
    
    return originalUri.withServers(optimizedServers).withEtag(etag);
  }
}

/// Result of resolving a mailbox URI
class ResolvedMailbox {
  /// Mailbox path
  final String mailboxPath;
  
  /// Which server successfully provided the mailbox
  final PeerId resolvedFromServer;
  
  /// Original URI that was resolved
  final RicochetUri originalUri;
  
  ResolvedMailbox({
    required this.mailboxPath,
    required this.resolvedFromServer,
    required this.originalUri,
  });
  
  /// Get optimized URI with successful server prioritized
  RicochetUri get optimizedUri {
    // Move the successful server to the front
    final optimizedServers = [
      resolvedFromServer,
      ...originalUri.servers.where((s) => s != resolvedFromServer),
    ];
    
    return originalUri.withServers(optimizedServers);
  }
}

/// Resolves Ricochet URIs to their content by trying multiple servers
/// 
/// Implements multi-server fallback: tries each server in priority order
/// until one succeeds, providing automatic resilience.
class RicochetUriResolver {
  static final Logger _logger = Logger('RicochetUriResolver');
  
  /// SFClient for making requests
  final SFClient client;
  
  /// Default timeout per server attempt
  final Duration defaultPerServerTimeout;
  
  RicochetUriResolver(
    this.client, {
    this.defaultPerServerTimeout = const Duration(seconds: 10),
  });
  
  /// Resolve a document URI to its content
  /// 
  /// Tries each server in the URI's server list until one succeeds.
  /// Returns null if all servers fail or if the document doesn't exist.
  /// 
  /// [uri] The document URI to resolve
  /// [perServerTimeout] Timeout for each server attempt (default: 10s)
  Future<ResolvedDocument?> resolveDocument(
    RicochetUri uri, {
    Duration? perServerTimeout,
  }) async {
    if (uri.resourceType != RicochetResourceType.doc) {
      throw ArgumentError('URI must be a document resource type');
    }
    
    if (uri.servers.isEmpty) {
      _logger.warning('No servers specified in URI: ${uri.toCanonical()}');
      return null;
    }
    
    final timeout = perServerTimeout ?? defaultPerServerTimeout;
    
    _logger.fine('Resolving document: ${uri.toCanonical()}');
    _logger.fine('Trying ${uri.servers.length} server(s)');
    
    // Try each server in priority order
    for (var i = 0; i < uri.servers.length; i++) {
      final serverId = uri.servers[i];
      _logger.fine('Attempt ${i + 1}/${uri.servers.length}: server ${serverId.toBase58().substring(0, 12)}...');
      
      try {
        final response = await client.getDocument(
          ownerPeerId: uri.ownerPeerId,
          path: uri.path,
          ifNoneMatch: uri.etag,
          fromServer: serverId,
        ).timeout(timeout);
        
        if (response == null) {
          _logger.fine('Server returned null response');
          continue;
        }
        
        if (response.isNotFound) {
          _logger.fine('Document not found (404)');
          // Don't try other servers if document doesn't exist
          return null;
        }
        
        if (response.isNotModified) {
          _logger.fine('Document not modified (304)');
          // Not modified is a successful response
          return null;
        }
        
        if (!response.isSuccess || response.content == null) {
          _logger.fine('Failed with status ${response.status}');
          continue;
        }
        
        // Success!
        _logger.info('✅ Resolved from server ${serverId.toBase58().substring(0, 12)}...');
        
        return ResolvedDocument(
          content: response.content!,
          contentType: response.contentType ?? 'application/octet-stream',
          etag: response.etag ?? '',
          lastModified: response.lastModified != null
              ? DateTime.fromMillisecondsSinceEpoch(response.lastModified!)
              : DateTime.now(),
          resolvedFromServer: serverId,
          originalUri: uri,
        );
      } catch (e) {
        _logger.fine('Error from server: $e');
        // Try next server
        continue;
      }
    }
    
    _logger.warning('❌ Failed to resolve from all ${uri.servers.length} server(s)');
    return null;
  }
  
  /// Resolve a mailbox URI
  /// 
  /// Note: This is a placeholder for future mailbox resolution support.
  /// Currently, mailbox access is not implemented via URI resolution.
  Future<ResolvedMailbox?> resolveMailbox(
    RicochetUri uri, {
    Duration? perServerTimeout,
  }) async {
    if (uri.resourceType != RicochetResourceType.mailbox) {
      throw ArgumentError('URI must be a mailbox resource type');
    }
    
    if (uri.servers.isEmpty) {
      _logger.warning('No servers specified in URI: ${uri.toCanonical()}');
      return null;
    }
    
    _logger.warning('Mailbox URI resolution not yet implemented');
    return null;
  }
  
  /// Resolve any URI by detecting its type
  Future<dynamic> resolve(
    RicochetUri uri, {
    Duration? perServerTimeout,
  }) async {
    switch (uri.resourceType) {
      case RicochetResourceType.doc:
        return resolveDocument(uri, perServerTimeout: perServerTimeout);
      case RicochetResourceType.mailbox:
        return resolveMailbox(uri, perServerTimeout: perServerTimeout);
    }
  }
}


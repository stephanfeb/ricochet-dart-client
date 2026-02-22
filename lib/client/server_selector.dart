import 'dart:async';
import 'dart:typed_data';
import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/multiaddr.dart';
import 'package:dart_libp2p/core/network/context.dart';
import 'package:dart_libp2p/core/network/network.dart';
import 'package:logging/logging.dart';
import '../registry/peer_preferences.dart';
import '../core/sf_message.dart';
import '../protocol/mma/admin_frame.dart';
import '../protocol/mma/admin_protocol.dart';

/// Server selection strategy for S&F operations
class ServerSelector {
  static final Logger _logger = Logger('ServerSelector');

  final Host host;
  final Map<String, DateTime> _unavailableServers = {};
  final Map<String, ServerCapacity> _capacityCache = {};
  final Map<String, MultiAddr> _knownServerAddresses = {};
  final Duration _unavailableTimeout;
  final Duration _capacityCacheDuration;

  ServerSelector({
    required this.host,
    Duration? unavailableTimeout,
    Duration? capacityCacheDuration,
  })  : _unavailableTimeout = unavailableTimeout ?? const Duration(seconds: 30),
        _capacityCacheDuration = capacityCacheDuration ?? const Duration(minutes: 1);

  /// Register a known server address so it can be refreshed in the peerstore
  /// when reconnection is needed.
  void registerServerAddress(PeerId serverId, MultiAddr addr) {
    _knownServerAddresses[serverId.toString()] = addr;
  }
  
  /// Select best available server from preference list
  Future<PeerId?> selectServer(List<SFServerPreference> preferences) async {
    if (preferences.isEmpty) {
      _logger.warning('No preferred servers configured');
      return null;
    }
    
    // Sort by priority (lower value = higher priority)
    final sorted = preferences.toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    
    // Try each server in priority order
    for (final pref in sorted) {
      final serverId = pref.serverId;
      
      // Skip if recently marked unavailable
      if (_isMarkedUnavailable(serverId)) {
        _logger.warning('Skipping unavailable server: ${serverId.toString().substring(0, 12)}...');
        continue;
      }
      
      // Check if server is reachable
      if (await isServerAvailable(serverId)) {
        _logger.info('Selected server: ${serverId.toString().substring(0, 12)}... (priority: ${pref.priority})');
        return serverId;
      } else {
        // Mark as unavailable temporarily
        markServerUnavailable(serverId);
      }
    }
    
    _logger.warning('No available servers found from ${preferences.length} preferences');
    return null;
  }
  
  /// Check if a server is available
  Future<bool> isServerAvailable(PeerId serverId) async {
    try {
      // Fast path: check if we already have a live connection to this peer.
      // This avoids the expensive stream probe (yamux SYN/ACK + identify +
      // multistream negotiation) which can take up to 60s and poisons
      // connection health metrics on failure.
      final connectedness = host.network.connectedness(serverId);
      if (connectedness == Connectedness.connected ||
          connectedness == Connectedness.limited) {
        _unavailableServers.remove(serverId.toString());
        return true;
      }

      // Slow path: not currently connected — refresh peerstore address TTL
      // before dialing, in case the address has expired since initialization.
      final knownAddr = _knownServerAddresses[serverId.toString()];
      if (knownAddr != null) {
        await host.peerStore.addrBook.addAddr(
          serverId, knownAddr, const Duration(hours: 1),
        );
        _logger.fine('Refreshed peerstore address for ${serverId.toString().substring(0, 12)}...');
      }

      final context = Context();
      final stream = await host.newStream(
        serverId,
        [adminProtocolId],
        context,
      ).timeout(const Duration(seconds: 10));

      await stream.close();
      _unavailableServers.remove(serverId.toString());
      return true;

    } catch (e) {
      _logger.fine('Server unavailable: ${serverId.toString().substring(0, 12)}... ($e)');
      return false;
    }
  }
  
  /// Mark server as temporarily unavailable
  void markServerUnavailable(PeerId serverId) {
    _unavailableServers[serverId.toString()] = DateTime.now();
    _logger.fine('Marked server unavailable: ${serverId.toString().substring(0, 12)}...');
  }
  
  /// Check if server is marked unavailable
  bool _isMarkedUnavailable(PeerId serverId) {
    final markedTime = _unavailableServers[serverId.toString()];
    if (markedTime == null) return false;
    
    // Check if timeout has expired
    final age = DateTime.now().difference(markedTime);
    if (age > _unavailableTimeout) {
      _unavailableServers.remove(serverId.toString());
      return false;
    }
    
    return true;
  }
  
  /// Query server capacity (with caching)
  Future<ServerCapacity?> queryServerCapacity(PeerId serverId) async {
    final cacheKey = serverId.toString();
    
    // Check cache first
    final cached = _capacityCache[cacheKey];
    if (cached != null) {
      _logger.fine('Using cached capacity for ${serverId.toString().substring(0, 12)}...');
      return cached;
    }
    
    try {
      // Open stream and query capacity via MMA (admin) protocol
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [adminProtocolId],
        context,
      );
      
      // Create query capacity request
      final request = QueryCapacityRequest();
      final requestBytes = AdminFrame.encodeRequest(request);
      
      // Send with length prefix
      final lengthBytes = ByteData(4)..setUint32(0, requestBytes.length);
      final combined = Uint8List(4 + requestBytes.length);
      combined.setRange(0, 4, lengthBytes.buffer.asUint8List());
      combined.setRange(4, 4 + requestBytes.length, requestBytes);
      
      await stream.write(combined);
      
      // Read response length
      final responseLengthBytes = await stream.read(4);
      if (responseLengthBytes.length < 4) {
        throw StateError('Failed to read response length');
      }
      
      final responseLength = responseLengthBytes.buffer.asByteData().getUint32(0);
      
      // Read response
      final responseBytes = await stream.read(responseLength);
      if (responseBytes.length < responseLength) {
        throw StateError('Failed to read complete response');
      }
      
      final response = AdminFrame.decodeResponse(responseBytes);
      await stream.close();
      
      if (!response.success || response.data == null) {
        _logger.warning('Server capacity query failed: ${response.errorMessage}');
        return null;
      }
      
      final capacity = ServerCapacity.fromJson(response.data as Map<String, dynamic>);
      
      // Cache the result
      _capacityCache[cacheKey] = capacity;
      
      // Schedule cache cleanup
      Future.delayed(_capacityCacheDuration, () {
        _capacityCache.remove(cacheKey);
      });
      
      return capacity;
      
    } catch (e) {
      _logger.warning('Failed to query server capacity: $e');
      return null;
    }
  }
  
  /// Select server with best capacity
  Future<PeerId?> selectServerByCapacity(List<SFServerPreference> preferences) async {
    if (preferences.isEmpty) return null;
    
    final sorted = preferences.toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    
    PeerId? bestServer;
    double bestScore = -1;
    
    for (final pref in sorted) {
      if (_isMarkedUnavailable(pref.serverId)) continue;
      
      final capacity = await queryServerCapacity(pref.serverId);
      if (capacity == null) {
        markServerUnavailable(pref.serverId);
        continue;
      }
      
      // Calculate score based on available capacity and health
      final availablePercent = (capacity.availableStorageBytes / capacity.totalStorageBytes) * 100;
      final score = (availablePercent * 0.7) + (capacity.healthScore * 30);
      
      if (score > bestScore) {
        bestScore = score;
        bestServer = pref.serverId;
      }
    }
    
    return bestServer;
  }
  
  /// Clear unavailable server marks
  void clearUnavailableMarks() {
    _unavailableServers.clear();
  }
  
  /// Clear capacity cache
  void clearCapacityCache() {
    _capacityCache.clear();
  }
  
  /// Get statistics
  Map<String, dynamic> getStats() {
    return {
      'unavailableServers': _unavailableServers.length,
      'cachedCapacity': _capacityCache.length,
    };
  }
}


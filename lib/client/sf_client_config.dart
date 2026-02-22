import '../registry/peer_preferences.dart';

/// Configuration for S&F client
class SFClientConfig {
  /// Preferred S&F servers (MX-like)
  final List<SFServerPreference> preferredServers;
  
  /// Enable automatic message retrieval
  final bool enableAutoRetrieval;
  
  /// Interval between automatic retrieval attempts
  final Duration retrievalInterval;
  
  /// Maximum retry attempts for failed operations
  final int maxRetries;
  
  /// Connection timeout
  final Duration connectionTimeout;
  
  /// Message operation timeout
  final Duration messageTimeout;
  
  /// Initial retry delay (exponential backoff)
  final Duration initialRetryDelay;
  
  /// Maximum retry delay
  final Duration maxRetryDelay;
  
  const SFClientConfig({
    this.preferredServers = const [],
    this.enableAutoRetrieval = false,
    this.retrievalInterval = const Duration(minutes: 1),
    this.maxRetries = 3,
    this.connectionTimeout = const Duration(seconds: 10),
    this.messageTimeout = const Duration(seconds: 30),
    this.initialRetryDelay = const Duration(seconds: 1),
    this.maxRetryDelay = const Duration(seconds: 30),
  });
  
  /// Create default configuration
  factory SFClientConfig.defaults() {
    return const SFClientConfig();
  }
  
  /// Create configuration with specific servers
  factory SFClientConfig.withServers(List<SFServerPreference> servers) {
    return SFClientConfig(preferredServers: servers);
  }
  
  /// Create configuration with auto-retrieval enabled
  factory SFClientConfig.withAutoRetrieval({
    required List<SFServerPreference> servers,
    Duration retrievalInterval = const Duration(minutes: 1),
  }) {
    return SFClientConfig(
      preferredServers: servers,
      enableAutoRetrieval: true,
      retrievalInterval: retrievalInterval,
    );
  }
  
  /// Copy with modifications
  SFClientConfig copyWith({
    List<SFServerPreference>? preferredServers,
    bool? enableAutoRetrieval,
    Duration? retrievalInterval,
    int? maxRetries,
    Duration? connectionTimeout,
    Duration? messageTimeout,
    Duration? initialRetryDelay,
    Duration? maxRetryDelay,
  }) {
    return SFClientConfig(
      preferredServers: preferredServers ?? this.preferredServers,
      enableAutoRetrieval: enableAutoRetrieval ?? this.enableAutoRetrieval,
      retrievalInterval: retrievalInterval ?? this.retrievalInterval,
      maxRetries: maxRetries ?? this.maxRetries,
      connectionTimeout: connectionTimeout ?? this.connectionTimeout,
      messageTimeout: messageTimeout ?? this.messageTimeout,
      initialRetryDelay: initialRetryDelay ?? this.initialRetryDelay,
      maxRetryDelay: maxRetryDelay ?? this.maxRetryDelay,
    );
  }
  
  /// Validate configuration
  bool isValid() {
    if (maxRetries < 0) return false;
    if (connectionTimeout.inMilliseconds <= 0) return false;
    if (messageTimeout.inMilliseconds <= 0) return false;
    if (enableAutoRetrieval && retrievalInterval.inMilliseconds <= 0) return false;
    return true;
  }
  
  @override
  String toString() {
    return 'SFClientConfig(servers: ${preferredServers.length}, '
           'autoRetrieval: $enableAutoRetrieval, '
           'retrievalInterval: ${retrievalInterval.inSeconds}s)';
  }
}


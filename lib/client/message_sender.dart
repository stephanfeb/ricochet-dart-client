import 'dart:async';
import 'dart:typed_data';
import 'package:dart_libp2p/core/host/host.dart';
import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:dart_libp2p/core/network/context.dart';
import 'package:logging/logging.dart';
import '../core/message_types.dart';
import '../protocol/msa/submission_handler.dart';
import 'sf_client_config.dart';
import 'server_selector.dart';

/// Result of a send operation
class SendResult {
  final bool deliveredDirectly;
  final PeerId? storedAtServer;
  final String? messageId;
  final Duration? estimatedDeliveryTime;
  final bool success;
  final String? errorMessage;
  
  const SendResult({
    required this.success,
    this.deliveredDirectly = false,
    this.storedAtServer,
    this.messageId,
    this.estimatedDeliveryTime,
    this.errorMessage,
  });
  
  factory SendResult.success({
    required bool deliveredDirectly,
    PeerId? storedAtServer,
    required String messageId,
    Duration? estimatedDeliveryTime,
  }) {
    return SendResult(
      success: true,
      deliveredDirectly: deliveredDirectly,
      storedAtServer: storedAtServer,
      messageId: messageId,
      estimatedDeliveryTime: estimatedDeliveryTime,
    );
  }
  
  factory SendResult.failure(String errorMessage) {
    return SendResult(
      success: false,
      errorMessage: errorMessage,
    );
  }
  
  @override
  String toString() {
    if (success) {
      return 'SendResult(success: true, direct: $deliveredDirectly, '
             'server: ${storedAtServer?.toString().substring(0, 12)}, '
             'messageId: $messageId)';
    } else {
      return 'SendResult(success: false, error: $errorMessage)';
    }
  }
}

/// Handles message sending with retries and failover
class MessageSender {
  static final Logger _logger = Logger('MessageSender');
  
  final Host host;
  final SFClientConfig config;
  final ServerSelector serverSelector;
  
  // Statistics
  int _sendAttempts = 0;
  int _successfulSends = 0;
  int _failedSends = 0;
  int _directDeliveries = 0;
  int _storedMessages = 0;
  
  MessageSender({
    required this.host,
    required this.config,
    required this.serverSelector,
  });
  
  /// Send message with automatic retry and failover
  Future<SendResult> sendMessage({
    required PeerId recipient,
    required Uint8List payload,
    String? folderPath,  // Target folder
    MessagePriority priority = MessagePriority.normal,
    Duration? expiry,
    bool persistent = false,  // Keep after reading
    bool tryDirectFirst = true,
  }) async {
    _sendAttempts++;
    
    // Try direct delivery first if requested
    if (tryDirectFirst) {
      final directResult = await sendDirect(
        recipient,
        payload,
        priority,
        expiry,
        folderPath: folderPath,
        persistent: persistent,
      );
      if (directResult.success) {
        _successfulSends++;
        _directDeliveries++;
        return directResult;
      }
    }
    
    // Fallback to S&F server storage
    final sfResult = await _sendViaServerWithRetry(
      recipient,
      payload,
      priority,
      expiry,
      folderPath: folderPath,
      persistent: persistent,
    );
    
    if (sfResult.success) {
      _successfulSends++;
      _storedMessages++;
    } else {
      _failedSends++;
    }
    
    return sfResult;
  }
  
  /// Attempt direct delivery to recipient
  Future<SendResult> sendDirect(
    PeerId recipient,
    Uint8List payload,
    MessagePriority priority,
    Duration? expiry, {
    String? folderPath,
    bool persistent = false,
  }) async {
    // Direct delivery not yet implemented — fall through to S&F
    _logger.fine('Direct delivery not implemented, skipping to S&F');
    return SendResult.failure('Direct delivery not implemented');
  }
  
  /// Send via S&F server with retry logic
  Future<SendResult> _sendViaServerWithRetry(
    PeerId recipient,
    Uint8List payload,
    MessagePriority priority,
    Duration? expiry, {
    String? folderPath,
    bool persistent = false,
  }) async {
    int attempt = 0;
    Duration retryDelay = config.initialRetryDelay;
    
    while (attempt < config.maxRetries) {
      attempt++;
      
      _logger.fine('Send attempt $attempt/${config.maxRetries}');
      
      // Select server
      final serverId = await serverSelector.selectServer(config.preferredServers);
      if (serverId == null) {
        _logger.warning('No available S&F servers');
        if (attempt < config.maxRetries) {
          await Future.delayed(retryDelay);
          retryDelay = _calculateNextDelay(retryDelay);
          continue;
        }
        return SendResult.failure('No available S&F servers');
      }
      
      // Try to send via selected server
      try {
        final result = await sendViaServer(
          serverId,
          recipient,
          payload,
          priority,
          expiry,
          folderPath: folderPath,
          persistent: persistent,
        );
        
        return result;
        
      } catch (e) {
        _logger.warning('Send via server failed (attempt $attempt): $e');
        
        // Mark server as unavailable
        serverSelector.markServerUnavailable(serverId);
        
        // Retry with exponential backoff
        if (attempt < config.maxRetries) {
          await Future.delayed(retryDelay);
          retryDelay = _calculateNextDelay(retryDelay);
        }
      }
    }
    
    return SendResult.failure('All retry attempts failed');
  }
  
  /// Send message via specific S&F server
  Future<SendResult> sendViaServer(
    PeerId serverId,
    PeerId recipient,
    Uint8List payload,
    MessagePriority priority,
    Duration? expiry, {
    String? folderPath,
    bool persistent = false,
  }) async {
    _logger.info('Sending via server: ${serverId.toString().substring(0, 12)}...');
    
    try {
      // Open stream to S&F server using MSA (Mail Submission Agent) protocol
      final context = Context();
      final stream = await host.newStream(
        serverId,
        [SubmissionHandler.protocolId],
        context,
      ).timeout(config.connectionTimeout);
      
      // Submit message to server via MSA
      final ack = await SubmissionHandler.submitMessage(
        stream,
        recipient,
        payload,
        priority: priority,
        expiry: expiry,
        folderPath: folderPath,
        persistent: persistent,
      ).timeout(config.messageTimeout);
      
      if (ack.success) {
        _logger.info('Message stored successfully: ${ack.messageId}');
        
        // Protect the S&F server connection so it won't be closed by cleanup
        host.connManager.protect(serverId, 'ricochet-sf-server');
        _logger.fine('Protected connection to S&F server ${serverId.toBase58().substring(0, 12)}...');
        
        return SendResult.success(
          deliveredDirectly: false,
          storedAtServer: serverId,
          messageId: ack.messageId,
          estimatedDeliveryTime: ack.estimatedDeliveryTime != null
              ? Duration(milliseconds: ack.estimatedDeliveryTime!)
              : null,
        );
      } else {
        return SendResult.failure(ack.errorMessage ?? 'Store failed');
      }
      
    } on TimeoutException {
      throw Exception('Operation timed out');
    } catch (e) {
      throw Exception('Failed to send via server: $e');
    }
  }
  
  /// Calculate next retry delay with exponential backoff
  Duration _calculateNextDelay(Duration currentDelay) {
    final nextDelay = currentDelay * 2;
    return nextDelay > config.maxRetryDelay ? config.maxRetryDelay : nextDelay;
  }
  
  /// Get statistics
  Map<String, dynamic> getStats() {
    return {
      'sendAttempts': _sendAttempts,
      'successfulSends': _successfulSends,
      'failedSends': _failedSends,
      'directDeliveries': _directDeliveries,
      'storedMessages': _storedMessages,
      'successRate': _sendAttempts > 0
          ? '${((_successfulSends / _sendAttempts) * 100).toStringAsFixed(1)}%'
          : '0.0%',
    };
  }
  
  /// Reset statistics
  void resetStats() {
    _sendAttempts = 0;
    _successfulSends = 0;
    _failedSends = 0;
    _directDeliveries = 0;
    _storedMessages = 0;
  }
}


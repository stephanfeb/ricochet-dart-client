import 'dart:convert';
import 'dart:typed_data';

import 'package:ricochet/protocol/maa/access_frame.dart';
import 'package:ricochet/core/sf_message.dart';
import 'package:test/test.dart';

void main() {
  group('AccessFrame.decodeRetrieveResponse', () {
    test('decodes a compound response', () {
      final bytes = AccessFrame.encodeRetrieveResponse(
        RetrieveMessagesResponse(messages: const [], hasMore: false),
      );
      final response = AccessFrame.decodeRetrieveResponse(bytes);
      expect(response.messages, isEmpty);
      expect(response.hasMore, isFalse);
    });

    test('throws the server\'s refusal instead of misreading it', () {
      final bytes = Uint8List.fromList(
        utf8.encode(jsonEncode({'error': 'access denied', 'status': 403})),
      );
      expect(
        () => AccessFrame.decodeRetrieveResponse(bytes),
        throwsA(isA<RetrieveRefusedException>()
            .having((e) => e.status, 'status', 403)
            .having((e) => e.error, 'error', 'access denied')),
      );
    });

    test('takes a refusal without a status', () {
      final bytes = Uint8List.fromList(utf8.encode('{"error":"invalid peer ID"}'));
      expect(
        () => AccessFrame.decodeRetrieveResponse(bytes),
        throwsA(isA<RetrieveRefusedException>().having((e) => e.status, 'status', isNull)),
      );
    });
  });
}

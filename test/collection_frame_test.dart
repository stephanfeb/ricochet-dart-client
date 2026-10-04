import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_libp2p/core/peer/peer_id.dart';
import 'package:ricochet/protocol/sca/collection_frame.dart';
import 'package:test/test.dart';

Uint8List _json(Object value) => Uint8List.fromList(utf8.encode(jsonEncode(value)));

Map<String, dynamic> _decode(Uint8List bytes) => jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

void main() {
  final owner = PeerId.fromString('12D3KooWNgThKhH4Fye45QFtAm3rdsDkA4jaRBXTc8dzYyvwBwCQ');

  group('CollectionFrame.decodeResponse', () {
    test('reads a payload sent as raw JSON in data', () {
      final response = CollectionFrame.decodeResponse(_json({
        'status': 200,
        'headers': {'ETag': '"abc"', 'X-Version': 1},
        'data': {'name': 'Drill', 'price': 49.99},
      }));
      expect(response.isSuccess, isTrue);
      expect(jsonDecode(utf8.decode(response.body!)), {'name': 'Drill', 'price': 49.99});
      expect(response.etag, '"abc"');
    });

    test('still reads a base64 body from an older server', () {
      final response = CollectionFrame.decodeResponse(_json({
        'status': 200,
        'body': base64Encode(utf8.encode('{"name":"Drill"}')),
      }));
      expect(utf8.decode(response.body!), '{"name":"Drill"}');
    });

    test('has no body when the response carries none', () {
      final response = CollectionFrame.decodeResponse(_json({'status': 204}));
      expect(response.body, isNull);
    });

    test('exposes the page cursor and the visibility', () {
      final response = CollectionFrame.decodeResponse(_json({
        'status': 200,
        'headers': {'X-Has-More': true, 'Next-Cursor': 'c1', 'Visibility': 'public'},
        'data': {'items': []},
      }));
      expect(response.hasMore, isTrue);
      expect(response.nextCursor, 'c1');
      expect(response.visibility, 'public');
      expect(response.totalCount, isNull);
    });
  });

  group('CollectionFrame.encodeRequest', () {
    test('sends the paging, total and access fields when set', () {
      final request = _decode(CollectionFrame.encodeRequest(
        operation: 'QUERY',
        ownerPeerId: owner,
        path: 'products',
        filter: {'category': 'tools'},
        cursor: 'c1',
        wantTotal: true,
      ));
      expect(request['cursor'], 'c1');
      expect(request['wantTotal'], isTrue);

      final access = _decode(CollectionFrame.encodeRequest(
        operation: 'ACCESS',
        ownerPeerId: owner,
        path: 'products',
        accessAction: 'set',
        visibility: 'public',
      ));
      expect(access['accessAction'], 'set');
      expect(access['visibility'], 'public');
    });

    test('leaves the optional fields out by default', () {
      final request = _decode(CollectionFrame.encodeRequest(
        operation: 'QUERY',
        ownerPeerId: owner,
        path: 'products',
      ));
      expect(request.keys, unorderedEquals(['operation', 'ownerPeerId', 'path']));
    });
  });
}

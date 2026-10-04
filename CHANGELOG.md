## 0.2.1

- **Collection items and query results arrive again.** go-ricochet now sends an item's content and a QUERY page as raw JSON in the response's `data` field, not as base64 in `body`. The client read only `body`, so `getCollectionItem` and `queryCollection` returned no body. `CollectionFrame.decodeResponse` now reads `data`, and still reads `body` from older servers. In both cases the payload is in `CollectionFrameResponse.body`.
- **`queryCollection` takes `wantTotal`.** A filtered query gets `X-Total-Count` only when it asks for it, because the server must scan all matches to count them. Without `wantTotal`, `totalCount` is null; count the returned `items` instead.
- **Paging with a cursor.** `queryCollection` and `listCollectionKeys` take `cursor`, and `CollectionFrameResponse.nextCursor` gives the cursor of the next page. A cursor takes precedence over `offset`.
- **Collection visibility.** `createCollection` takes `visibility`, and the new `setCollectionVisibility` changes it later. The server makes a collection private when no visibility is given, so only its owner can read it. The new `CollectionVisibility` enum has the values `private`, `shared` and `public`.
- The store interop harness in `bin/` makes the document and the collection that the second client reads public, and asks for the query totals. Against go-ricochet, all 27 checks now pass on both clients (before: 23 and 21).

## 0.2.0

- **Works with dart_libp2p 3.x and 4.x.** `dart_libp2p` is now `>=1.0.0 <5.0.0`. None of those releases changes an API this package uses. The upper bound had made `ricochet` unresolvable next to dart_libp2p 3.0.0 or later, including 4.1.0, which fixes hole punching for hosts behind NAT. All 30 tests pass against dart_libp2p 4.1.0, and the store interop suite in `bin/` gives the same results against go-ricochet as 0.1.0 did.
- **No longer depends on `dart_libp2p_merkle_crdt` or `merkledag`.** Nothing in the package imports them, and `dart_libp2p_merkle_crdt` 1.0.0 also requires `dart_libp2p <3.0.0`. An app that imports either package must now list it in its own `pubspec.yaml`.

## 0.1.0

- First release on pub.dev.
- Depends on `dart_libp2p_merkle_crdt` and `merkledag` from pub.dev instead of local paths.

## 0.2.0

- **Works with dart_libp2p 3.x and 4.x.** `dart_libp2p` is now `>=1.0.0 <5.0.0`. None of those releases changes an API this package uses. The upper bound had made `ricochet` unresolvable next to dart_libp2p 3.0.0 or later, including 4.1.0, which fixes hole punching for hosts behind NAT. All 30 tests pass against dart_libp2p 4.1.0, and the store interop suite in `bin/` gives the same results against go-ricochet as 0.1.0 did.
- **No longer depends on `dart_libp2p_merkle_crdt` or `merkledag`.** Nothing in the package imports them, and `dart_libp2p_merkle_crdt` 1.0.0 also requires `dart_libp2p <3.0.0`. An app that imports either package must now list it in its own `pubspec.yaml`.

## 0.1.0

- First release on pub.dev.
- Depends on `dart_libp2p_merkle_crdt` and `merkledag` from pub.dev instead of local paths.

## 0.3.1

- **`mailboxes.listMailboxes()` lists the owner's mailboxes.** It returned an empty list whatever the owner had: go-ricochet sends the entries in `mailboxes`, and the client read only `data`. Each entry names the folder and type but not the owner, so `MailboxInfo.fromListEntry` builds the address with the asking peer as owner. go-ricochet's list sends no message count, last access or retention count, so a listed `MailboxInfo` has 0, 0 and null for them; `getMailboxInfo` has them. `MailboxOperationResponse` has a new `mailboxes` field.

## 0.3.0

- **Claim mailboxes.** `MailboxType.claim` is a mailbox whose owner hands its messages out one at a time, such as Signal one-time prekeys: only the owner stores into it or lists it, and `SFClient.claimMessage(ownerPeerId:, folderPath:)` takes the oldest message and deletes it on the server, so no two claimers get the same one. It returns null when none is left, which is also the answer once the mailbox has handed out its share for the hour (go-ricochet allows 30 claims an hour per mailbox by default). A refusal throws `RetrieveRefusedException`: status 400 from a server older than go-ricochet 1.6.0, 403 when the folder is not a claim mailbox, 404 when it does not exist. Create the mailbox with `mailboxes.createMailbox(type: MailboxType.claim)` before storing into it, and give it no `retentionCount`. `MailboxType` has a new value, so an exhaustive `switch` over it needs a case for `claim`.
- **A notification names the mailbox's owner.** `MailboxNotification.ownerPeerId` says whose mailbox `mailboxPath` (the folder alone) is in, so a client following several owners' shared or public mailboxes can tell two folders of the same name apart. go-ricochet sends it (its N23); for a server that does not, `SFClient` fills it in: the client's own peer id on a private notification, the subscribed owner on a GossipSub one.
- **Document version history.** go-ricochet can now turn history on (its N19). `putDocument` takes `history`: how many earlier versions the document keeps, starting with the one that write replaces (the server clamps it to its `max_document_history_versions`, 10 by default); `history: 0` turns it off and deletes them. New: `getDocumentHistory` (newest first, sizes but no bodies), `getDocumentVersion` (one version with its body) and `restoreDocumentVersion` (makes a kept version current again as a new version, so it can be undone; `ifMatch` makes it conditional). `getDocument` and `headDocument` report `version` and `history`. `DocumentHandler` has the matching stream-level methods. Needs a go-ricochet with RESTORE and the `history` field; an older server ignores `history` and answers RESTORE with an error.
- **Encrypted messages to a folder outside ASCII open in Go and JS, and theirs open here.** The payload binding encoded the recipient, folder and message id with `String.codeUnits`, which keeps the low byte of each UTF-16 code unit; the Go and JS clients encode them as UTF-8. The two agree only for ASCII: a folder such as `café/日記` sealed to different bytes, so the other side refused it as bound to another message. The binding is now UTF-8 (`utf8.encode`/`utf8.decode`), checked against a Go-sealed vector. A message this client sealed to a non-ASCII folder before this change no longer opens; ASCII folders, ids and peer ids are unaffected.

## 0.2.4

- **`SFClient` can make a collection public.** `createCollection` takes `visibility`, and the new `setCollectionVisibility` changes it later; its response's `visibility` is the collection's visibility afterwards (404 when there is no such collection). The 0.2.1 entry said this already, but 0.2.1 added visibility only to `CollectionHandler`: through `SFClient` every collection was private, so no other peer could read it. `queryCollection`'s `wantTotal` and `cursor`, also in that entry, are still on `CollectionHandler` only.
- The test files run one at a time (`dart_test.yaml`): two files that each start a Ricochet server time out dialing when run side by side.

## 0.2.3

- **Works with dart_libp2p_pubsub 2.x and 3.x.** `dart_libp2p_pubsub` is now `>=1.1.0 <5.0.0` (before: `>=1.1.0 <2.0.0`). None of those releases changes an API this package uses. The upper bound had made `ricochet` unresolvable next to dart_libp2p_pubsub 2.0.0 or later. All tests pass against dart_libp2p_pubsub 3.0.0 and against 1.1.0.

## 0.2.2

- **The server availability check no longer opens an empty MMA stream.** When the client was not connected to a server, `ServerSelector` opened an admin (MMA) stream and closed it with no request. go-ricochet logged each one as a failed request (`op=unrouted`, 500). The check now only dials the server (`host.connect`). With dart_libp2p 4.1.6 or later, a check that runs while another dial to the server is in progress joins that dial.
- **A server that is connected is not marked unavailable.** When the check failed but another dial had connected the server in the meantime, `selectServer` marked the server unavailable for 30 s, and requests in that time found no server. `selectServer` now checks the connection again before it marks a server. `selectServerByCapacity` no longer marks a connected server unavailable when it does not answer the capacity query; it leaves the server out of that choice only.
- **`retrieveMessages(throwOnFailure: true)` reports a failed retrieval.** A retrieval that gets no answer (no server, a timeout, another error) throws `RetrieveFailedException` instead of returning an empty list, so a caller can tell an empty mailbox from one it could not read. Without the option, the behaviour does not change.

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

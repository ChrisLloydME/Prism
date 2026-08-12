# Prism backend communication architecture

Status: approved implementation design  
Protocol: Prism Backend Protocol (PBP) v1  
Platform baseline: macOS 14, SwiftUI/AppKit client, C++/Qt backend

This design replaces UI-shaped bridge calls and one-process-per-launch helper
arguments with a stable local service boundary. It is intentionally independent
of the current native UI. A redesigned UI, a command-line client, or tests may
consume the same protocol without changing backend domain behavior.

Normative wire rules are in [PROTOCOL_V1.md](PROTOCOL_V1.md). The v1 surface is
in [METHODS_V1.md](METHODS_V1.md). `protocol-v1.schema.json` validates the
transport-level JSON-RPC messages; method payload schemas are generated from the
same protocol model used by C++ and Swift.

## 1. Decisions

| Area | Decision | Reason |
| --- | --- | --- |
| Process model | One long-lived backend per canonical data root | One writer, reconnectable tasks, game lifetime independent of UI |
| Transport | Unix-domain `SOCK_STREAM` socket | Local, bidirectional, low overhead, supported by Qt and macOS POSIX APIs |
| RPC | JSON-RPC 2.0, named parameters, no batch in v1 | Existing standard for request correlation and notifications; easy diagnostics and fixtures |
| Framing | 4-byte unsigned big-endian payload length followed by UTF-8 JSON | Stream-safe; unaffected by whitespace, newlines, or fragmented reads |
| State delivery | Atomic snapshot plus ordered event stream | No list/watch race and deterministic reconnection |
| Mutations | Persistent idempotency key and aggregate revision check | Safe retries and explicit conflict handling |
| Long work | Persistent hierarchical tasks | Download, install, authentication, and launch survive UI reconnection |
| User decisions | Persistent typed prompts that block a task | Backend never creates UI and decisions cannot be lost on disconnect |
| Storage | Existing Prism domain files plus a private SQLite control database | Avoid domain-format rewrite while gaining transactions and recovery |
| Large/binary data | Paginated/chunked reads or validated file references; never unbounded JSON | Bounded memory and predictable backpressure |
| Public UI boundary | Swift sees Foundation models through a protocol client | No Qt/C++ type or backend ownership reaches SwiftUI/AppKit |

JSON-RPC is transport-independent and defines requests, responses,
notifications, standard errors, and correlation IDs. JSON is UTF-8 as required
by RFC 8259. UUID strings follow RFC 9562 and timestamps use uppercase UTC RFC
3339. Qt's local-socket permission flags are not effective access controls on
macOS, so accepted sockets are authenticated with `getpeereid(3)`.

## 2. Target architecture

```text
SwiftUI / AppKit
  └─ BackendClient actor (Foundation values, reconnect, cache)
      └─ Objective-C++/C++ transport adapter
          └─ Unix-domain socket / PBP v1
              └─ prism_backend --daemon
                  ├─ ProtocolServer + SessionRegistry
                  ├─ CommandRouter + serializers
                  ├─ Snapshot/EventStore
                  ├─ TaskRegistry + PromptRegistry
                  ├─ FrontendFacade application services
                  └─ Existing Prism domain services
                      ├─ instances/components/providers
                      ├─ metadata/download/cache/archive
                      ├─ accounts/Java/settings
                      └─ Minecraft update/launch/process lifecycle
```

The current `FrontendFacade` remains useful, but moves behind the server as an
application-service boundary. The native process must not link or instantiate
mutable backend services after cutover. Its bridge becomes a protocol client
and Foundation model converter only.

The backend transport may use `QLocalServer`/`QLocalSocket` to integrate with
its Qt event loop, but verifies each accepted native descriptor with
`getpeereid`. The native client uses a nonblocking POSIX socket on a dedicated
serial dispatch queue behind a Swift actor; it does not add Qt socket ownership
to Swift or AppKit. Both implementations share golden wire vectors rather than
sharing framework-specific runtime types.

### Dependency rules

1. Backend code never imports SwiftUI, AppKit, or Objective-C UI types.
2. Protocol DTOs contain values, stable identifiers, revisions, and opaque
   references; never Qt objects, callbacks, widgets, or ownership pointers.
3. Swift never constructs Minecraft commands, resolves downloads, refreshes
   credentials, mutates Prism files, or infers task success from log text.
4. Once a domain is cut over, only the daemon may mutate that domain's files.
5. The protocol describes domain intent and state, not screens, sheets, rows,
   button states, or navigation.

## 3. Service lifecycle and rendezvous

There is exactly one backend holding an exclusive advisory lock for one
canonical data root. The root is canonicalized with symlink resolution before
its SHA-256 root identifier is calculated. A client must reject a root outside
its configured application-support namespace.

The socket uses a short path to stay below `sockaddr_un.sun_path` limits:

```text
$TMPDIR/com.lloydME.Prism/ipc/<uid>/<first-32-hex-of-root-hash>.sock
```

The parent directories are created without following symlinks and mode `0700`.
The control database and lock remain under:

```text
<data-root>/runtime/backend-state.sqlite3
<data-root>/runtime/backend.lock
```

Client startup is:

1. Canonicalize and validate the data root.
2. Attempt a socket connection and authenticate the peer UID.
3. If unavailable, spawn the bundled helper with `--daemon`, explicit root and
   socket path. No credentials are placed in arguments or environment.
4. Wait on a dedicated readiness pipe with a bounded timeout; do not scrape
   stdout.
5. If two clients race, one backend wins the root lock. The loser exits with a
   defined `already-running` status and both clients reconnect to the winner.
6. Perform `system.hello`; reject incompatible protocol or product identity.
7. Acquire the controller lease if this client needs mutations.
8. Open an atomic state subscription and render only its snapshot.

Stale sockets are removed only by a process that holds the root lock and has
proved that connecting to the path fails. PID files alone are never trusted.

### Backend states

```text
starting → accepting → draining → stopping → stopped
                  ↘ crashed (observed by the next process)
```

The backend stays alive while any client, nonterminal task, unresolved prompt,
or managed game process exists. With none of those, it exits after a 60-second
idle grace period. Client disconnect never cancels work. `system.shutdown`
enters draining, rejects new mutations, flushes durable state, and exits only
when safe. Forced termination is a separate, explicitly confirmed recovery
operation.

When a new app version meets an older compatible backend, work continues. When
the backend is incompatible, the client asks it to drain; active work is not
killed for an update. A new backend starts only after the old root lock is
released.

## 4. Ownership, concurrency, and consistency

### Single writer

The daemon is the sole writer for instances, settings, accounts, cache indexes,
task state, and launch state. UI reads are snapshots. UI-local edits are drafts
until a command succeeds and a newer authoritative revision is observed.

During incremental migration, ownership is assigned per domain in a checked-in
matrix. A domain is either `in_process` or `daemon`, never both. The final state
has every mutable domain owned by the daemon.

### Sessions and controller lease

Multiple connections may observe. Mutations require a controller lease:

- lease duration: 30 seconds;
- client renews every 10 seconds through `session.renewControl`;
- losing a connection does not cancel accepted tasks;
- another client may acquire control after expiry;
- prompt responses and destructive commands require control;
- the lease ID is connection-bound and is never persisted.

This prevents two app windows or a future CLI from racing interactive choices.
The backend still enforces revisions and idempotency; the lease is not a data
integrity substitute.

### Revisions

Every mutable aggregate has an unsigned 64-bit revision represented as a
decimal JSON string: global settings, account collection, each instance, each
task, each prompt, and each launch. Successful mutation increments its owning
revision transactionally. Commands that edit existing state carry
`expectedRevision`; mismatch returns `conflict.revision` and the current
snapshot or revision.

Filesystem watchers are hints, not transaction boundaries. Debounced external
changes are rescanned and converted into a new aggregate revision/event. Before
commit, a mutating task revalidates the files/revisions it read; an overlapping
external edit produces a typed conflict or safe rollback rather than being
overwritten. Watch overflow, dropped events, wake from sleep, and backend
restart trigger bounded reconciliation scans.

### Idempotency

Every side-effecting command carries a UUID `idempotencyKey`. The backend stores
method, canonical request digest, response/task ID, and outcome in SQLite.

- Same key + same method/payload returns the original acceptance result.
- Same key + different method/payload returns `conflict.idempotency_key`.
- Records survive restart and are retained at least seven days after terminal
  completion.
- Query methods need no idempotency key.
- Cancel and prompt response are intrinsically idempotent but still carry keys
  for uniform retry behavior.

An RPC response to a long operation means accepted, not completed. It returns a
task ID; task terminal state is the completion authority.

## 5. State synchronization

`state.open` atomically registers an event subscription and creates the initial
snapshot. Its result contains `backendEpoch`, `snapshotSequence`, requested
collections, tasks, prompts, and launches. Events occurring while the snapshot
is serialized are queued and delivered afterward, so no list/watch gap exists.

Each daemon process has an RFC 9562 UUID `backendEpoch` and a monotonically
increasing unsigned sequence. Events contain both. The backend retains a
bounded replay buffer (minimum 10,000 events and 16 MiB). Reconnection sends
the previous epoch and last applied sequence:

- same epoch and cursor retained: replay missing events;
- epoch changed or cursor evicted: return `snapshotRequired: true`;
- the client then calls `state.open` and replaces its cache atomically.

Snapshots are authoritative. Events are deltas carrying aggregate revisions.
A client ignores duplicate/out-of-order revisions and requests a fresh snapshot
if it detects a sequence gap or an impossible state transition.

Progress events may be coalesced to at most 10 per second per task. State
transitions, prompt changes, terminal outcomes, and revisioned domain changes
are never dropped.

## 6. Task and prompt model

All mutations, downloads, installs, managed processes, user-blocked work, and
work that must survive disconnection are tasks. Tasks form a tree. Bounded,
read-only discovery queries may remain request-scoped: they have deadlines, are
cancelled when their connection goes away, never mutate domain state, and are
not promised across reconnection.

Required task fields include:

- stable task ID, kind, title localization key, parent/root ID;
- state: `queued`, `running`, `blocked`, `cancelling`, `succeeded`, `failed`,
  `cancelled`, or `interrupted`;
- progress: `none`, `indeterminate`, or determinate completed/total/unit;
- phase code and optional current item label;
- capabilities: cancellable, retryable, resumable;
- aggregate revision and UTC timestamps;
- structured terminal result/error and rollback outcome;
- related instance/account/launch IDs.

Download progress uses integer byte counts encoded as decimal strings and may
include instantaneous and smoothed bytes/second. Parent progress is calculated
in the backend from weighted children; the UI does not invent weights.

On crash recovery, persisted `running`, `blocked`, or `cancelling` tasks become
`interrupted`. A task-specific recovery policy then marks them resumable,
retryable, or failed after staging/journal reconciliation. A task is never
silently reported successful because its child process disappeared.

The scheduler enforces one mutating task per instance, one authentication task
per account, bounded global/provider download concurrency, and explicit locks
for shared cache writes. Read-only work may run concurrently against immutable
snapshots. Locks are acquired in a documented global order; tasks never hold a
database transaction while awaiting network, subprocess, or user input.

### Prompts

A prompt is persisted state, not a synchronous callback. Creating one moves its
task to `blocked`. It has a typed kind, safe payload, allowed responses,
revision, optional expiry, and default-on-expiry policy. Examples include:

- optional or blocked mod files;
- insufficient disk or memory warning;
- account expired / authentication required;
- incompatible Java choice;
- overwrite/conflict resolution;
- destructive rollback choice.

`prompt.respond` requires the controller lease, idempotency key, prompt ID,
expected revision, and one allowed typed response. Exactly one response wins.
Disconnect does not select a default. OAuth bearer/refresh tokens never enter
prompt payloads. A provider-required short user code or authorization result
may cross only in a field classified `ephemeralSensitive`: it is redacted from
logs, excluded from durable storage and ordinary snapshots, and expires with
the authentication attempt. Backend restart interrupts that attempt rather
than recovering the ephemeral value from disk.

## 7. Persistence and recovery

`backend-state.sqlite3` stores only orchestration data:

- schema version and backend epoch history;
- tasks, task edges, terminal outcomes, and resumability metadata;
- prompts and decisions;
- idempotency records;
- managed launch records and last known process identity;
- durable diagnostic IDs.

Existing instance, account, settings, metadata, and cache formats remain their
domain stores. SQLite does not duplicate them as an alternative source of
truth. Domain commits use staging plus atomic rename where supported. Task
acceptance, prompt creation/response, terminal transitions, and idempotency
results are transactions. High-frequency progress is checkpointed at most once
per second and may use relaxed durability; terminal state is synchronously
committed.

At startup the backend:

1. validates/migrates its private control schema transactionally;
2. reconciles staging directories and interrupted transactions;
3. validates persisted managed PIDs by process start identity, not PID alone;
4. reconstructs interrupted tasks and launch state;
5. starts listening only after the snapshot is internally consistent.

Migration failure leaves the previous database intact, starts no mutations,
and reports a diagnostic through the readiness channel.

## 8. Security and privacy

Threat model: protect against other OS users, accidental clients, malformed or
oversized messages, path traversal, symlink escape, credential disclosure, and
confused-deputy filesystem operations. A malicious process already running as
the same user is out of scope for v1 because it can read or modify the user's
Prism data directly. If that threat becomes required, move the transport to a
code-signature-constrained XPC service; a bearer token stored in the same user
account would not solve it.

Required controls:

1. Both peers call `getpeereid` and require the configured effective UID before
   reading the first frame. Do not rely on `QLocalServer::UserAccessOption` on
   macOS; Qt documents that these permissions have no effect there.
2. Runtime directories reject symlinks and have mode `0700`; regular control
   files use `0600`. Socket names derive from a validated root hash.
3. Limit frames to 8 MiB, nesting to 64, collection counts per schema, and
   outstanding requests to 128 per connection.
4. Use bounded queues, read/write deadlines, strict UTF-8 and schema validation.
5. Do not support arbitrary `readFile`, `writeFile`, `execute`, shell command,
   environment injection, or URL-fetch RPCs.
6. Local imports accept only explicit user-selected paths and immediately
   canonicalize, inspect, and copy into controlled staging. Backend-owned file
   references are opaque, scoped, read-only, expiring values.
7. Credentials remain in backend account storage/Keychain boundaries. Tokens,
   cookies, device codes, authorization headers, complete environment blocks,
   and launch secrets are prohibited from protocol payloads and logs.
8. Every log field passes a central redactor before disk or IPC. Unknown
   sensitive fields fail closed in authentication serializers.
9. Remote URLs are allowlisted per domain adapter; redirects, size limits,
   hashes, archive traversal, decompression ratios, and MIME/type mismatches are
   validated by backend code.

The current app is not sandboxed. If sandboxing is introduced, the socket moves
into an App Group container and imported files use security-scoped bookmarks or
XPC file-descriptor transfer. This is a planned transport adaptation, not a
reason to leak sandbox concerns into domain methods.

## 9. Backpressure, logs, and large values

Each connection has an 8 MiB/10,000-message outbound budget. Before reaching it
the server coalesces only superseded progress and presence events. It never
drops responses, terminal transitions, prompts, or revisioned mutations. A
client that remains slow is disconnected with a recorded reason and recovers by
snapshot.

Task logs are stored in rotating backend files with stable cursors. The event
stream carries bounded `task.logAppended` hints/chunks (maximum 64 KiB), while
`task.log.read` pages historical redacted entries. A client may unsubscribe from
log events without losing task state.

Images, archives, skins, screenshots, and crash bundles are not base64-inlined
in collection snapshots. They use an `artifactRef` containing an opaque ID,
MIME type, size, digest, expiry, and allowed operation. `artifact.read` is
bounded and paginated; `artifact.materialize` returns a validated read-only
local URL only when the UI needs a native file API.

Client-selected files use a typed `localGrant`: path, expected file/directory
kind, requested read/write operation, and optional security-scoped bookmark.
The backend reopens and canonicalizes the target immediately before use,
rejects symlink/type changes, and never treats a path string as a general
filesystem grant. Destination writes stage a sibling temporary file and
atomically replace only the confirmed destination when possible.

## 10. Observability and performance budgets

Backend logs are structured and include backend epoch, connection ID, RPC ID,
idempotency key, task ID, and diagnostic ID where applicable. User-visible text
is selected by the client from semantic domain/task/phase codes and typed
fields. Backend localization keys and substitutions are compatibility fallbacks,
not backend-owned product copy. `diagnosticText` is developer detail and is
never the sole user-facing error.

Initial budgets on a supported Mac with warm filesystem cache:

- connect + peer verification + hello: p95 under 250 ms;
- 1,000-instance summary snapshot: p95 under 750 ms and under 8 MiB;
- accepted command response: p95 under 100 ms before work begins;
- non-coalesced state event delivery: p95 under 100 ms;
- no unbounded queue, log, snapshot, or artifact allocation;
- idle daemon memory target below 150 MiB during the transitional Qt build.

Metrics are local diagnostics only in v1; no telemetry upload is implied.

## 11. Validation strategy

The protocol is not complete until both implementations pass:

- C++ and Swift golden-vector encode/decode tests for every method and event;
- JSON Schema validation and unknown/missing/invalid enum cases;
- fragmented, combined, zero-length, oversized, invalid UTF-8, deep nesting,
  timeout, half-close, and abrupt-disconnect transport tests;
- fuzzing of the frame decoder, JSON parser boundary, and command router;
- idempotent retry, revision conflict, multi-client lease, prompt race, replay
  gap, epoch change, and slow-client backpressure tests;
- kill-at-every-checkpoint recovery tests for install, download, account refresh,
  launch, cancellation, and final commit;
- path traversal, symlink swap, peer UID, secret redaction, archive bomb, and
  malformed provider fixture security tests;
- protocol v1 compatibility tests against the previous released client and
  server fixture before any additive release;
- synthetic end-to-end creation → download → launch → stop, without production
  credentials or live service dependence.

## 12. Implementation sequence and exit gates

1. **Protocol foundation:** checked-in schemas, generated DTOs, framing,
   peer authentication, hello, fixture server/client, fuzz target.
2. **Read-only daemon:** singleton/root lock, `state.open`, instances/settings/
   accounts snapshots, event ordering, controller lease.
3. **Durable tasks:** SQLite registry, logs, cancellation, idempotency,
   revisions, prompts, restart reconciliation.
4. **Golden path:** creation/import/install, Java, authentication, complete
   update/download/launch/stop behind RPC. Replace current launch arguments.
5. **Domain cutover:** migrate remaining mutations one domain at a time with an
   ownership matrix and dual-path prohibition.
6. **Native client cutover:** `BackendClient` becomes the only production bridge
   composition; Swift models consume snapshots/events and keep only drafts.
7. **Hardening:** compatibility, fault injection, security, performance,
   upgrade/drain, crash recovery, signed distribution verification.
8. **Backend slimming:** split UI code from domain targets and change daemon to
   `QCoreApplication`; remove QtWidgets/QtGui only after behavior parity.

Exit gate: no production native call mutates backend files in-process; no Qt UI
is instantiated by the daemon; every long operation is reconnectable and has a
terminal task result; every interaction is a typed prompt; Debug and Release
bundles pass protocol, recovery, launch, closure, signing, and upgrade tests.

### Proposed source layout

```text
launcher/backend/ipc/
  FrameCodec.*             # bounded stream framing
  PeerAuthenticator.*      # getpeereid and root identity
  ProtocolServer.*         # JSON-RPC dispatch and connection queues
  SessionRegistry.*        # handshake, subscription, control lease
  SnapshotStore.*          # revisions, event sequence and replay
  TaskStore.* / PromptStore.*
  BackendDaemon.*          # lock, lifecycle, recovery, scheduler

launcher/backend/protocol/v1/
  schemas/*.json           # canonical envelope and method payload schemas
  fixtures/*.json          # accepted and rejected golden vectors
  ProtocolTypes.*          # C++ value types/serializers

macos/PrismNative/BackendClient/
  BackendConnection.mm     # POSIX fd, dispatch queue, frame delivery
  BackendClient.swift      # actor, RPC correlation, reconnect, state cache
  ProtocolV1/*.swift       # Codable value types
```

Schemas and fixtures are public-contract source. C++ and Swift types may be
generated or handwritten, but CI validates every encoder output and decoder
input against the same schemas and bidirectional golden vectors. No method may
ship with only one side's private DTO definition.

## 13. Failure-behavior review

| Scenario | Defined behavior |
| --- | --- |
| UI crashes or is redesigned | Backend tasks/game continue; new client authenticates, resumes or replaces snapshot |
| Backend crashes mid-install | Startup reconciliation marks task interrupted, validates staging, offers audited resume/retry/rollback |
| Reply is lost after command acceptance | Client retries same idempotency key and receives original task/result |
| Duplicate/out-of-order event | Epoch/sequence and aggregate revision make application idempotent |
| Replay cursor evicted | Backend requires atomic snapshot; client never guesses missing state |
| Two clients mutate | One renewable controller lease plus revision checks serializes interaction |
| User disconnects while prompt is open | Task remains blocked; no default is selected implicitly |
| Disk becomes full | Task fails/blocks with typed error; staging reconciliation preserves prior committed instance |
| Network disappears or Mac sleeps | Request-scoped reads time out; durable tasks enter retry/backoff state using monotonic timers |
| Wall clock jumps | Ordering uses sequence/revision and deadlines use monotonic time; UTC is descriptive only |
| UI is slow | Progress is coalesced; critical events retained; persistently slow client is disconnected and resyncs |
| App updates while game/download runs | Old compatible daemon continues; new version waits for drain/root-lock handoff |
| PID is reused after crash | Managed process identity includes start identity; PID alone is never killed |
| Socket path is pre-created or symlinked | Secure parent/path checks and root-lock ownership reject/remove only proven stale endpoints |
| Unsupported new field/method | Negotiated capability and compatibility rules decide ignore vs explicit rejection |
| Backend becomes unresponsive | Client reports disconnected state, keeps idempotency keys, and offers separately confirmed force recovery |

This matrix is a required design-review checklist. Adding a new task family must
define its row-equivalent behavior for disconnect, crash, cancellation,
rollback, retry, upgrade, and secret handling.

## 14. Rejected alternatives

- **Continue adding Objective-C bridge methods:** couples backend shape to the
  current UI process and cannot preserve work across UI restart.
- **stdin/stdout JSON lines:** lifecycle and logs compete with protocol output;
  framing, reconnect, multiple clients, and peer authentication are weak.
- **One helper per task:** permits competing writers and cannot provide one
  authoritative snapshot or cross-task scheduling.
- **XPC in v1:** strongest macOS identity integration, but adds an Objective-C
  service boundary around a Qt/C++ core and complicates future non-UI tools.
  Reconsider for sandboxing or same-user hostile-process requirements.
- **gRPC/Protobuf:** good schema and streaming support but a large runtime/build
  addition for a local, single-product protocol. The PBP model remains suitable
  for later Protobuf encoding if profiling proves JSON inadequate.
- **WebSocket/local HTTP:** unnecessary network surface, origin/authentication
  work, and weaker local process semantics.
- **Persist every event forever:** high write amplification. Durable snapshots
  and task journals plus bounded replay provide recovery without an event-sourced
  rewrite of Prism.

## 15. Primary references

- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)
- [RFC 8259: JSON](https://www.rfc-editor.org/info/rfc8259/)
- [RFC 3339: Internet timestamps](https://www.rfc-editor.org/info/rfc3339/)
- [RFC 9562: UUIDs](https://www.rfc-editor.org/info/rfc9562/)
- [Qt QLocalServer documentation](https://doc.qt.io/qt-6/qlocalserver.html)
- [Apple `getpeereid(3)` manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/getpeereid.3.html)
- [Apple App Groups IPC documentation](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.application-groups)

# Backend implementation guide for agents

Last reviewed: 2026-08-12

Use this guide when changing native UI integration, bridge code, backend
adapters, or PBP. Read [current architecture](CURRENT_ARCHITECTURE.md) and the
[capability matrix](CAPABILITY_MATRIX.md) before editing.

## 1. First classify the requested work

| Request | Correct primary layer |
| --- | --- |
| Layout, navigation, formatting, draft editing, panels | SwiftUI/AppKit |
| UI-independent Swift state/cache/reconnect facade | Swift backend protocol/client |
| Foundation-to-C++ conversion or callback lifetime | Objective-C++ bridge |
| Stable application operation and DTO | `FrontendFacade` |
| Filesystem, archive, provider, account, Java, process algorithm | `Production*Runtime` or existing Prism domain service |
| Cross-process framing/session/task ownership | backend PBP server and native IPC client |

Do not copy an algorithm into a more convenient layer. If the request spans
layers, define the value contract first and implement one vertical capability
at a time.

## 2. Rules that must remain true

1. SwiftUI/AppKit own presentation; backend code creates no native or Qt UI.
2. Qt and C++ types never appear in public Objective-C headers or Swift.
3. Swift does not build launch commands, parse archives, refresh credentials,
   select provider URLs, or write Prism domain files.
4. The native data root comes only from `PRApplicationIdentity` and remains
   `~/Library/Application Support/com.lloydME.Prism`.
5. No code inspects, imports, or mutates the user's upstream Prism Launcher
   Application Support, preferences, or Keychain data.
6. Existing QtCore/QtNetwork backend use is permitted. Do not reimplement
   difficult proven behavior solely to remove Qt.
7. New Objective-C++ methods convert values and lifecycle only; they do not
   become a second domain-service layer.
8. A domain has one production mutation owner. Never run in-process and daemon
   writers against the same root after IPC cutover.
9. Secrets never enter Swift DTOs, logs, command-line arguments, environment
   variables, fixtures, or protocol diagnostics.
10. A method appearing in PBP documentation does not mean it is implemented.

## 3. Guidance for UI work now

Existing models may continue using `PRPrismBridge` while they are maintained.
New or substantially redesigned surfaces should use a Swift-owned abstraction:

```swift
protocol PrismBackendProviding: Sendable {
    func openInstanceState() async throws -> InstanceStateSnapshot
    func launch(instanceID: String) async throws -> TaskSnapshot
    func cancel(taskID: String) async throws -> TaskSnapshot
}
```

The exact API should be split by capability rather than placed in one enormous
protocol. Recommended roles are read stores plus command services, for example
`InstanceStore`, `TaskStore`, `AccountService`, and `ProviderService`.

Initially implement those roles with a `BridgeBackendClient` that wraps
`PRPrismBridge`. Later implement the same roles with `IPCBackendClient`. Views
consume Swift domain snapshots, never `PR*` Objective-C objects directly.

Keep these concerns in Swift:

- loading/empty/error presentation;
- navigation and selection;
- editable drafts and client-side field formatting;
- AppKit open/save panels and security-scope UI lifecycle;
- accessibility labels, focus, commands, and window behavior.

Keep confirmed state and operations in backend-facing stores. After a mutation,
prefer the backend-confirmed snapshot/event over optimistic duplication unless
the contract explicitly defines reconciliation.

## 4. Adding or completing an in-process capability

Follow this order:

1. **Inventory before writing.** Search `FrontendFacade.h`, the relevant
   `Production*Runtime`, `PrismBridge.h`, and Swift models. Many apparent gaps
   are missing composition or UI inputs rather than missing algorithms.
2. **Reuse the hard backend behavior.** Adapt the existing Prism domain code
   when it owns complex launch, metadata, provider, archive, Java, or account
   semantics. Paraphrase simple value/conversion code only when licensing and
   project conventions allow it.
3. **Define typed values.** Add stable identifiers, request/result enums,
   localization keys, retryability, and bounded diagnostics to the facade.
4. **Implement production ownership.** Put filesystem/network/process behavior
   in a focused `Production*Runtime`, with cancellation and rollback where the
   operation is long or destructive.
5. **Wire default composition.** Install the dependency in
   `productionInstanceRuntimeDependencies(...)`. Without this step the feature
   is only a contract.
6. **Bridge values.** Add Foundation-only models and an Objective-C++ converter.
   Validate enum/input exhaustively and deliver callbacks on the expected
   native executor.
7. **Expose through a Swift service/store.** Avoid adding bridge calls directly
   inside views.
8. **Update the capability matrix.** Record partial dependencies honestly.

Do not declare completion from compilation alone. Exercise the default
composition, not only injected test fakes.

## 5. Implementing PBP

The normative design and order are in `docs/backend-ipc`. The minimum safe
sequence is:

1. frame codec, bounds, JSON validation, fixtures, and fuzz entry point;
2. peer UID/root authentication, rendezvous, singleton lock, and `system.hello`;
3. read-only instance/settings/account snapshots with atomic subscription;
4. Swift actor client with correlation, reconnect, cache, and event ordering;
5. controller lease, revisions, and idempotent mutation routing;
6. durable task/log/prompt registry and crash reconciliation;
7. creation/install/download, authentication, and launch process cutover;
8. remaining domain cutover and removal of each old mutation path;
9. helper slimming from `QApplication` toward `QCoreApplication` after parity.

For each method, implement all of the following together:

- canonical request/response/event schema or generated type;
- accepted and rejected golden vectors;
- C++ routing and serialization;
- Swift decoding and typed client method;
- error, timeout, cancellation, and disconnect behavior;
- authorization/lease/revision/idempotency rules where applicable;
- capability matrix status and cutover ownership record.

Never create a generic `execute`, `invoke`, property bag, arbitrary path, shell
command, or opaque UI callback method. PBP expresses domain intent.

## 6. Domain cutover checklist

A domain is IPC-backed only when all answers are yes:

- Does the packaged app connect through the production IPC client by default?
- Does the daemon exclusively own mutations for this domain?
- Are snapshots and events revisioned and reconnect-safe?
- Are long operations durable, cancellable, and terminal after recovery?
- Are user decisions represented as typed persistent prompts?
- Are secrets redacted and local file grants validated?
- Do compatibility, invalid-input, disconnect, restart, and slow-client tests
  pass?
- Has the in-process production mutation route been removed or made
  unreachable?

Until then, mark the IPC column `No` or `Partial`; never `Yes`.

## 7. Verification expectations

Choose tests proportional to the changed layer:

| Changed layer | Minimum evidence |
| --- | --- |
| Documentation only | links/paths checked, terminology consistent, `git diff --check` |
| Swift model/client | focused XCTest for states, cancellation, stale delivery, and errors |
| Objective-C++ bridge | contract and integration tests, public-header forbidden-type scan |
| Production runtime | focused C++ production test using an isolated synthetic root |
| Packaging/helper | normal signed Xcode build, runtime closure check, strict `codesign` verification |
| PBP codec/session | bidirectional golden vectors plus fragmented/coalesced/oversize/invalid tests |
| Durable task/domain cutover | kill/restart/reconnect/idempotency/revision/failure-injection tests |

Tests must not use the user's real support root, accounts, credentials, Keychain,
or installed upstream application. Use unique synthetic roots and controlled
network/process dependencies.

## 8. Common wrong turns

- Treating `docs/backend-ipc/METHODS_V1.md` as implemented code.
- Calling the current launch helper an RPC daemon.
- Adding a second one-to-one bridge method for every new screen without a
  Swift service boundary.
- Moving launch/provider/archive/account logic into Swift for convenience.
- Considering a fake-injected test proof of default production composition.
- Marking Microsoft authentication complete because DTOs and a state machine
  exist while production HTTP/browser/Keychain ports still reject.
- Assuming a persisted launch JSON file provides resumable daemon ownership.
- Removing QtCore/QtNetwork before behavioral parity.
- Reading upstream Prism Launcher storage to “verify compatibility.”
- Writing both through the bridge and daemon during a migration.

## 9. Handoff template

An agent completing backend-facing work should report:

```text
Capability:
Production call path:
Default dependency wired:
UI-facing abstraction:
Persistence/mutation owner:
Cancellation/recovery semantics:
Secrets/local-file boundary:
Tests run:
Known partial dependencies:
Capability-matrix rows updated:
```

This makes the difference between contract coverage, production backing, UI
surface, and IPC cutover reviewable without re-reading the entire bridge.

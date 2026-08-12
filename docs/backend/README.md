# Prism backend support guide

Status: current implementation guide
Last reviewed: 2026-08-12
Branch baseline: `macos-native` at or after `fbb5ebed4`

This directory explains what the native backend supports **today** and how to
extend it safely. It is deliberately separate from `docs/backend-ipc`, which
describes the approved target architecture rather than shipped code.

## Read this first

| Question | Document |
| --- | --- |
| What process and call path exists now? | [Current architecture](CURRENT_ARCHITECTURE.md) |
| Is a specific feature production-backed, bridged, and visible to Swift? | [Capability matrix](CAPABILITY_MATRIX.md) |
| Where should an agent make a change and what must it test? | [Agent implementation guide](AGENT_IMPLEMENTATION_GUIDE.md) |
| What should the eventual independent backend protocol look like? | [IPC architecture](../backend-ipc/README.md) |
| What are the normative target wire rules and methods? | [PBP v1](../backend-ipc/PROTOCOL_V1.md) and [method catalog](../backend-ipc/METHODS_V1.md) |
| Why were the current adapters created and what historical gates exist? | [Native migration progress](../macos-native-migration/PROGRESS.md) |

The migration plan and progress ledger are historical architecture evidence,
not an automatic goal-management system. The current user request and session
instructions determine the active scope; agents should not activate, complete,
or rewrite ledger work units unless explicitly asked.

## The short version

The current production path is in-process:

```text
SwiftUI / AppKit
  -> Swift models and coordinators
  -> PRPrismBridge (Objective-C++)
  -> FrontendFacade
  -> Production*Runtime adapters
  -> existing Prism domain/filesystem/network code
```

`prism_backend` is bundled and used by the launch runtime as a separate
Minecraft launch helper. It is **not** currently a long-lived PBP server. There
is no production Unix-socket RPC server, Swift `BackendClient` actor, protocol
handshake, state replay, controller lease, persistent prompt registry, or
general durable task daemon yet.

The existing bridge is useful and should remain operational while the UI is
redesigned. New UI code should, however, be placed behind a Swift-owned backend
protocol instead of increasing direct `PRPrismBridge` coupling. A bridge-backed
implementation can serve that protocol until an IPC-backed implementation is
ready.

## Status vocabulary

These words have precise meanings throughout this directory:

- **Production-backed**: the default native composition calls a real adapter
  against the bundle-scoped Prism data root. It does not mean every live
  provider path has passed a release end-to-end test.
- **Contract-backed**: DTOs, bridge methods, or tests exist, but the default
  production dependency may still be a fake, rejecting port, or incomplete
  composition.
- **UI-surfaced**: a Swift model/coordinator and some native presentation exist.
  It does not imply final product design or complete UX.
- **IPC-backed**: the production native app reaches the capability through PBP
  and the independent daemon. No domain currently meets this definition.
- **Release-proven**: the complete live workflow has passed its stated release
  gates, including failure and recovery behavior. Do not infer this from unit
  tests or from a public method alone.

## Sources of truth

When documents and code disagree, use this order:

1. Default production composition in
   `launcher/frontend/ProductionInstanceRuntime.cpp` and
   `macos/PrismNative/Bridge/PrismBridge.mm`.
2. Public callable surfaces in `launcher/frontend/FrontendFacade.h` and
   `macos/PrismNative/Bridge/PrismBridge.h`.
3. Production adapter tests and native bridge/infrastructure tests.
4. [Capability matrix](CAPABILITY_MATRIX.md).
5. Historical migration ledgers and plans.

Update the capability matrix whenever a default dependency changes, a bridge
method is added or removed, a Swift surface is connected, or an IPC domain is
cut over. Never mark a target IPC method implemented merely because it appears
in `METHODS_V1.md`.

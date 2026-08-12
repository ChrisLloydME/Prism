# Current native backend architecture

Status: description of the implementation that exists now
Last reviewed: 2026-08-12

This document is descriptive, not aspirational. The independent service design
lives in [`docs/backend-ipc`](../backend-ipc/README.md).

## 1. Current production call path

```text
PrismNativeApp
  -> SwiftUI view / Swift ObservableObject or coordinator
  -> PRPrismBridge Objective-C API
  -> PrismBridge.mm Foundation <-> C++ conversion
  -> FrontendFacade
  -> FrontendRuntimeDependencies
  -> ProductionInstanceRuntime composition
       |- ProductionSettingsRuntime
       |- ProductionJavaRuntime
       |- ProductionAccountRuntime
       |- ProductionInstanceAcquisitionRuntime
       |- ProductionProviderRuntime
       |- ProductionInstanceDetailRuntime
       |- ProductionLaunchRuntime
       `- ProductionUtilityRuntime
```

The app constructs one `PRApplicationIdentity` and one `PRPrismBridge` in
`PrismNativeApp.swift`. The bridge creates a process-scoped `QCoreApplication`
on the main thread and composes `FrontendFacade` with production runtime
dependencies. Most backend work therefore runs in the native app process.

The Foundation boundary is real and valuable: public Objective-C headers do
not expose Qt or C++ types, and Swift receives immutable Foundation DTOs plus
callbacks. It is not a process boundary.

## 2. Current processes

| Process | Current responsibility | What it is not |
| --- | --- | --- |
| `Prism.app/Contents/MacOS/Prism` | SwiftUI/AppKit presentation, Objective-C++ bridge, `FrontendFacade`, most production runtimes, task observers | A thin PBP client |
| `Prism.app/Contents/MacOS/prism_backend` | Separate helper selected by `ProductionLaunchRuntime` for the proven Minecraft launch graph | A long-lived RPC daemon or general backend owner |
| Java / Minecraft processes | Launcher Java entry point and the game process initiated by the launch path | PBP clients |

`launcher/backend_main.cpp` currently constructs the legacy `Application` and
enters its event loop. It deliberately suppresses foreground-app behavior but
temporarily retains `QApplication`, QtGui, and QtWidgets because the extracted
launch graph still contains those types. Its packaging proves a separate
process seam; it does not implement `--daemon`, PBP framing, RPC routing, state
subscriptions, or multi-client ownership.

Do not rename the current helper to “daemon” in code or documentation until it
actually implements the service lifecycle and protocol gates.

## 3. Responsibilities by layer

### SwiftUI and Swift models

Swift owns presentation state, navigation, drafts, system panels, formatting,
and accessibility. Existing models frequently hold `PRPrismBridge` directly.
That is an accepted migration state, not the desired endpoint for new UI.

Swift must not construct Minecraft command lines, parse provider archives,
refresh credentials, directly modify Prism domain files, or infer completion
from log strings.

### Objective-C++ bridge

`PrismBridge.h`, `PrismBridgeModels.h`, and `PrismBridgeErrors.h` form the
Foundation-only public surface. `PrismBridge.mm` validates inputs, converts
DTOs, dispatches work, suppresses delivery after cancellation, and delivers
callbacks to the native side.

The bridge is currently a one-to-one adapter around `FrontendFacade`. It is not
the future `BackendClient`, not a wire-protocol implementation, and not a place
for duplicated domain algorithms.

### `FrontendFacade`

`FrontendFacade` is the UI-independent application-service boundary. It owns
stable request/result structures and delegates behavior through
`FrontendRuntimeDependencies`. It covers instances, details, resources,
settings, Java, accounts, creation/import, providers, utilities, launch, tasks,
and logs.

This boundary is intended to survive the IPC migration: the future server can
route PBP methods into the facade or more focused services without moving the
domain behavior into the protocol layer.

### Production runtimes

The `Production*Runtime` classes own real bundle-rooted persistence, validation,
network/archive work, process execution, cancellation, and conversion to facade
results. `productionInstanceRuntimeDependencies(...)` is the main composition
root. A class or method existing is insufficient evidence of production use;
the dependency must be installed by this default composition.

### Existing Prism domain code

The production adapters intentionally reuse technically difficult, proven
Prism behavior. QtCore and QtNetwork remain valid implementation dependencies
inside the backend. Qt UI types must not cross the public facade or bridge
boundaries. QtWidgets/QtGui retirement is a later slimming task, not a
precondition for native UI work.

## 4. Storage and identity

The native product identity is fixed:

```text
bundle identifier: com.lloydME.Prism
data root: ~/Library/Application Support/com.lloydME.Prism
```

`PRApplicationIdentity` is the only production origin for the native root. New
adapters must receive the root through composition. They must not rediscover it
from display names, executable names, `QStandardPaths`, environment variables,
parent-directory scans, or upstream Prism Launcher paths.

Existing Prism file formats remain the domain store. The future daemon control
database described by PBP does not exist yet. In particular, there is no
general SQLite task/prompt/idempotency store in current production code.

## 5. Tasks, cancellation, and recovery today

The facade and bridge expose task snapshots, task observation, bounded logs,
and cancellation. Creation, import, copy, export, provider operations, account
authentication, and launch can report progress through their current adapters.

These task semantics are primarily process-local:

- cancellation tokens suppress late bridge delivery and are observed by the
  active runtime;
- closing or crashing the UI process does not provide the PBP reconnect model;
- there is no global durable task registry or persistent typed prompt owner;
- there is no ordered event sequence/replay cursor shared with a new client;
- launch records are persisted by `ProductionLaunchRuntime`, but an unfinished
  record reconstructed after the app was absent is finalized as cancelled;
  this is not resumable daemon-owned launch recovery.

Do not describe current tasks as reconnectable or daemon-durable.

## 6. Known production gaps and transitional constraints

1. **No independent IPC service.** The PBP implementation sequence has not
   started in production code.
2. **Direct bridge coupling in Swift.** Existing UI models commonly depend on
   `PRPrismBridge`; introduce a Swift backend protocol before expanding a
   redesigned UI surface.
3. **Microsoft authentication ports.** The account authentication state machine
   is implemented and bridged, but the default production dependencies use
   rejecting HTTP/browser/Keychain ports. Snapshot loading, selection, and
   offline identity are separate capabilities and must not be used as evidence
   that live Microsoft login works.
4. **Creation UX inputs.** The production vanilla creation adapter exists, but
   the current `ContentView` initializes version and loader choices as empty.
   A redesigned creation flow needs a real catalog source and validation.
5. **Helper still carries UI framework dependencies.** `prism_backend` retains
   `QApplication`, QtGui, and QtWidgets while reusing the legacy launch graph.
   It must never create launcher presentation.
6. **No multi-client or controller lease.** Current mutation ownership assumes
   the one in-process bridge composition.
7. **Live end-to-end evidence is narrower than API coverage.** Unit and fixture
   tests prove contracts and many real filesystem paths; they do not prove
   every provider, credential, network, update, and launch combination against
   live services.

## 7. Source map

| Concern | Primary sources |
| --- | --- |
| Facade DTOs and operations | `launcher/frontend/FrontendFacade.h/.cpp` |
| Production composition | `launcher/frontend/ProductionInstanceRuntime.cpp` |
| Instances and observation | `ProductionInstanceRuntime.*` |
| Details/resources/copy/export | `ProductionInstanceDetailRuntime.*` |
| Creation/import/download staging | `ProductionInstanceAcquisitionRuntime.*` |
| Provider browse/version/install | `ProductionProviderRuntime.*` |
| Settings | `ProductionSettingsRuntime.*` |
| Java | `ProductionJavaRuntime.*` |
| Accounts/auth/offline identity | `ProductionAccountRuntime.*` |
| Launch/process/task/logs | `ProductionLaunchRuntime.*`, `ProductionMinecraftLaunch.*` |
| News/update/shortcut/skin | `ProductionUtilityRuntime.*` |
| Foundation bridge | `macos/PrismNative/Bridge/*` |
| Swift models and current UI | `macos/PrismNative/App/*` |
| Launch helper entry point | `launcher/backend_main.cpp` |
| Helper packaging | `macos/scripts/deploy-qt-runtime.sh` |

## 8. Target transition

The intended transition is incremental:

```text
today:
UI -> PRPrismBridge -> FrontendFacade -> Production runtimes

UI migration seam:
UI -> Swift BackendProviding protocol -> BridgeBackendClient -> PRPrismBridge

target:
UI -> IPCBackendClient -> PBP -> prism_backend --daemon -> FrontendFacade
```

During transition, one domain has exactly one production mutation owner. A
domain must not be writable through both the in-process bridge and daemon. Read
shadowing is allowed only in tests with explicit comparison and no shared
mutation.

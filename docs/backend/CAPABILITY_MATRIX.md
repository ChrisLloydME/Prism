# Native backend capability matrix

Last reviewed: 2026-08-12

This matrix reports default production composition, not merely the existence
of a type, method, mock, or design entry. See [status vocabulary](README.md#status-vocabulary).

Legend:

- **Yes**: production-backed at that layer.
- **Partial**: meaningful implementation exists but a required dependency,
  user flow, recovery property, or release proof is missing.
- **Contract**: callable/test contract exists without a complete default
  production path.
- **No**: not implemented at that layer.
- **N/A**: not applicable to that layer.

No capability is currently IPC-backed. `METHODS_V1.md` is a target catalog, not
an implementation ledger.

## Core library and instance management

| Capability | C++ production runtime | ObjC++ bridge | Current Swift surface | Independent IPC | Notes / remaining work |
| --- | --- | --- | --- | --- | --- |
| Instance snapshots | Yes | Yes | Yes | No | Bundle-rooted discovery through `ProductionInstanceRuntime` |
| Instance change observation | Yes | Yes | Yes | No | Process-local observation; no revision/replay cursor |
| Metadata-only instance creation | Yes | Yes | Limited | No | Primarily a narrow facade capability; not the main creation UX |
| Details and notes | Yes | Yes | Yes | No | Immutable details plus confirmed notes mutation |
| Components/version list | Yes | Yes | Yes | No | Read path is present; full loader-management UX remains separate |
| Instance settings | Yes | Yes | Yes | No | Typed snapshot/update path |
| Global settings | Yes | Yes | Yes | No | Typed bundle-rooted snapshot/update path |
| Mods/resource packs | Yes | Yes | Yes | No | Read and explicit mutation actions |
| Worlds/servers/screenshots/log files | Yes | Yes | Yes | No | Read surfaces and supported explicit mutations |
| Bounded instance log content | Yes | Yes | Yes | No | Not a daemon log stream |
| Copy instance | Yes | Yes | Yes | No | Progress/cancellation and staging are adapter-owned |
| Export instance | Yes | Yes | Yes | No | System save destination originates in native UI |
| Delete instance | Yes | Yes | Yes | No | Requires explicit confirmation; recovery behavior stays adapter-owned |

## Acquisition, providers, and downloads

| Capability | C++ production runtime | ObjC++ bridge | Current Swift surface | Independent IPC | Notes / remaining work |
| --- | --- | --- | --- | --- | --- |
| Vanilla instance creation | Yes | Yes | Partial | No | Runtime stages/downloads/commits; current UI supplies empty version/loader catalogs |
| Local archive import | Yes | Yes | Yes | No | System-selected URL and backend-owned extraction/validation |
| Remote HTTP(S) import | Yes | Yes | Yes | No | Process-local task; not reconnectable |
| Provider browse/search | Yes | Yes | Yes | No | Provider filters, pagination, cache, cancellation represented |
| Provider version discovery | Yes | Yes | Yes | No | Used by installation preparation |
| Provider pack installation | Yes | Yes | Yes | No | Staging, rollback, optional/blocked decisions modeled in adapter contract |
| General artifact/download task service | Partial | Contract | Partial | No | Downloads exist inside workflows; no shared durable artifact/task registry |
| Restart-resumable downloads | No | No | No | No | Required by target durable-task design |
| Persistent typed conflict prompts | No | Contract-like recovery results | Partial ad hoc UI | No | Must become daemon-owned `prompt.*` records |

## Java, accounts, identity, and skins

| Capability | C++ production runtime | ObjC++ bridge | Current Swift surface | Independent IPC | Notes / remaining work |
| --- | --- | --- | --- | --- | --- |
| Java discovery | Yes | Yes | Yes | No | Real installation discovery and typed rows |
| Java selection/persistence | Yes | Yes | Yes | No | Stable identifier selected by backend |
| Account snapshot loading | Yes | Yes | Yes | No | Non-secret bundle-rooted account rows |
| Active-account selection | Yes | Yes | Yes | No | Includes clearing selection |
| Offline/demo launch identity | Yes | Yes | Yes | No | Separate from Microsoft authentication |
| Microsoft device-code login/refresh state machine | Partial | Yes | Yes | No | Default HTTP/browser/Keychain ports reject; live production auth is not complete |
| Credential persistence in Keychain | Contract | Hidden behind bridge | N/A | No | Default production Keychain port is not wired |
| Skin/cape loading and actions | Partial | Yes | Yes | No | Utility logic exists; authenticated credential supply depends on incomplete live auth |

## Launch, process ownership, tasks, and logs

| Capability | C++ production runtime | ObjC++ bridge | Current Swift surface | Independent IPC | Notes / remaining work |
| --- | --- | --- | --- | --- | --- |
| Build Minecraft launch specification | Yes | Hidden | N/A | No | Java command/environment remains backend-owned |
| Launch Minecraft through bundled helper | Yes | Yes | Yes | No | Real helper path; release/live matrix still needs parity audit |
| Stop/cancel active launch | Yes | Yes | Yes | No | Owned by current in-process `ProductionLaunchRuntime` |
| Task snapshots and observation | Yes | Yes | Yes | No | Process-local observer semantics |
| Bounded task logs | Yes | Yes | Yes | No | Launch runtime persists bounded entries |
| Persist terminal launch record | Yes | Yes | Yes | No | Unfinished reconstructed launches become cancelled |
| UI-disconnect-independent task ownership | No | No | No | No | Requires daemon cutover |
| Reconnect and ordered event replay | No | No | No | No | Requires PBP session/snapshot/event implementation |
| Managed game survives UI lifecycle with authoritative recovery | Partial | Partial | Partial | No | Separate helper exists, but no daemon process registry/reconnect contract |

## Utilities

| Capability | C++ production runtime | ObjC++ bridge | Current Swift surface | Independent IPC | Notes / remaining work |
| --- | --- | --- | --- | --- | --- |
| News feed | Yes | Yes | Yes | No | Bounded feed loading |
| Update check/decision | Yes | Yes | Yes | No | Distribution/notarization release behavior still needs release proof |
| Shortcut creation | Yes | Yes | Yes | No | Uses native-selected context and backend utility logic |
| System file panels | N/A | Foundation URL contracts | Yes | N/A | Presentation remains AppKit/SwiftUI-owned |
| About/content rendering | Partial | Yes where backend data is needed | Yes | No | UI utility, not a core daemon domain |

## Communication platform

| Capability | Current state | Completion gate |
| --- | --- | --- |
| Swift UI-facing backend protocol | No shared production abstraction | Redesigned UI depends on protocol/store, not `PRPrismBridge` directly |
| Bridge-backed client adapter | No | Implements the Swift protocol using current bridge without changing domain behavior |
| PBP frame codec | No | C++ and native fragmented/coalesced/oversize tests pass |
| Peer authentication and rendezvous | No | UID/root validation and race tests pass |
| Hello/version negotiation | No | Golden vectors and compatibility fixtures pass |
| Atomic snapshot + ordered events | No | No list/watch race; reconnect/replay tests pass |
| Controller lease and revisions | No | Multi-client mutation conflict tests pass |
| Durable task/prompt registry | No | Kill/restart reconciliation tests pass |
| Swift IPC `BackendClient` actor | No | Reconnect, correlation, cancellation, cache, and backpressure tests pass |
| Domain cutover | No domains | In-process mutation path removed for each cut-over domain |

## Practical UI readiness

The native team can redesign the application shell, instance library, details,
settings, provider browser, account presentation, and task/log presentation
now. Before that redesign expands, add a small Swift-owned backend protocol and
a bridge-backed implementation. Do not wait for the entire PBP daemon, and do
not bind new views directly to Objective-C DTOs.

Treat these as backend work that remains on the critical path:

1. live Microsoft HTTP/browser/Keychain composition;
2. real version/loader catalog feeding vanilla creation;
3. independent IPC foundation and Swift client abstraction;
4. durable task/prompt and reconnect semantics;
5. release-level creation/download/launch/stop parity and failure testing.

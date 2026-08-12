# PBP v1 method and event catalog

This catalog defines the complete v1 capability surface. It is not a promise
that every method ships in the first implementation patch. `system.hello`
capabilities declare what the connected backend implements. Once advertised,
the method must satisfy this contract.

Conventions:

- `Q` is a read-only query.
- `M` is a mutation requiring `mutation.idempotencyKey` and controller lease.
- `T` is a mutation returning a durable task acceptance.
- Existing aggregates edited by `M`/`T` also require `expectedRevision`.
- List methods use opaque cursors and bounded `limit` (default 100, maximum
  500). Ordering and filters are explicit and stable.

## 1. System, session, and state

| Method | Kind | Purpose/result |
| --- | --- | --- |
| `system.hello` | Q | Mandatory negotiation, identity, limits, capabilities, resume availability |
| `system.ping` | Q | Liveness and time diagnostics |
| `system.info` | Q | Safe build, platform, Java/backend feature diagnostics; no paths or secrets by default |
| `system.shutdown` | M | Graceful drain; reports blockers |
| `session.acquireControl` | Q | Acquire the connection-bound interactive lease |
| `session.renewControl` | Q | Renew current lease |
| `session.releaseControl` | Q | Idempotently release current lease |
| `state.open` | Q | Atomically subscribe and return authoritative snapshot |
| `state.resume` | Q | Replay from epoch/sequence or require snapshot |
| `state.updateTopics` | Q | Change future event topics at a defined sequence |
| `state.close` | Q | Stop this connection's subscription |

Snapshot topics are `instances`, `settings`, `accounts`, `java`, `tasks`,
`prompts`, `launches`, `providers`, `news`, and `updates`. Large children such as
mods, worlds, logs, provider search results, and artifacts are loaded separately.

## 2. Instances and components

| Method | Kind | Purpose/result |
| --- | --- | --- |
| `instance.list` | Q | Paginated instance summaries with collection revision |
| `instance.get` | Q | Details, notes, flags, running state, revision |
| `instance.create` | T | Vanilla/loader creation through staging and atomic commit |
| `instance.import` | T | Import explicit local grant or HTTPS source |
| `instance.copy` | T | Copy an existing instance with selected data policy |
| `instance.export` | T | Export through a user-selected destination grant |
| `instance.updateMetadata` | M | Rename, group, icon, notes, and other metadata fields |
| `instance.delete` | T | Confirmed deletion with trash/recovery policy |
| `instance.components.list` | Q | Ordered component snapshot and revision |
| `instance.components.update` | T | Add/change/remove/reorder loader and version components |
| `instance.update` | T | Resolve metadata and bring libraries/assets/loaders to desired state without launch |

Creation params describe intent (`minecraftVersion`, optional loader kind/version,
name/group/icon), never URLs or artifact paths selected by the UI. Version and
loader catalogs are backend queries.

## 3. Instance content

| Method | Kind | Purpose/result |
| --- | --- | --- |
| `resource.list` | Q | Mods/resource packs/shaders/texture packs/data packs |
| `resource.import` | T | Copy and validate explicit user-selected resources |
| `resource.setEnabled` | M | Enable/disable one resource |
| `resource.delete` | T | Confirmed recoverable deletion |
| `resource.update` | T | Update selected resources through their provider metadata |
| `world.list` | Q | World metadata page |
| `world.import` | T | Import and validate a world/archive |
| `world.copy` | T | Copy a world |
| `world.rename` | M | Rename safely |
| `world.delete` | T | Confirmed recoverable deletion |
| `server.list` | Q | Servers and backend-owned ping state |
| `server.upsert` | M | Add/edit server using aggregate revision |
| `server.reorder` | M | Ordered ID update |
| `server.delete` | M | Confirmed delete |
| `server.refreshStatus` | T | Bounded server status refresh |
| `screenshot.list` | Q | Metadata and preview artifact references |
| `screenshot.delete` | T | Confirmed recoverable deletion |
| `log.list` | Q | Current/historical instance log metadata |
| `log.read` | Q | Bounded redacted log page by cursor |
| `log.delete` | T | Confirmed deletion of eligible historical log |

Reveal, open, copy-to-pasteboard, drag/drop, and native share presentation stay
client-side. The backend returns validated `artifactRef` or read-only file
reference; it does not invoke Finder or AppKit.

## 4. Version and provider discovery

| Method | Kind | Purpose/result |
| --- | --- | --- |
| `catalog.minecraftVersions` | Q | Filtered/paginated Minecraft versions and compatibility metadata |
| `catalog.loaderVersions` | Q | Loader versions compatible with selected Minecraft version |
| `provider.list` | Q | Available providers/install kinds and capabilities |
| `provider.search` | Q | Provider search with explicit query, filters, sort, cursor |
| `provider.project.get` | Q | Project metadata and bounded changelog/artifact references |
| `provider.versions` | Q | Compatible project versions and required choices |
| `provider.install` | T | Resolve manifest, prompt for options, download, stage, commit |
| `provider.cache.refresh` | T | Explicit metadata/cache refresh |

Clients do not build provider URLs or parse provider payloads. Provider page
cursors are opaque and scoped to the exact normalized query.

## 5. Tasks, prompts, and artifacts

| Method | Kind | Purpose/result |
| --- | --- | --- |
| `task.list` | Q | Active/recent tasks filtered by state, kind, related aggregate |
| `task.get` | Q | Authoritative task tree/snapshot |
| `task.cancel` | M | Request cancellation; terminal event remains authority |
| `task.retry` | T | Start linked retry after validating policy |
| `task.log.read` | Q | Paginated, redacted structured task logs |
| `prompt.list` | Q | Open/recent prompts visible to this client |
| `prompt.get` | Q | Typed prompt snapshot |
| `prompt.respond` | M | Compare-and-set one allowed response |
| `artifact.get` | Q | Metadata for an opaque artifact reference |
| `artifact.read` | Q | Bounded byte range encoded as base64 for small data |
| `artifact.materialize` | Q | Expiring validated read-only local file reference |
| `artifact.release` | Q | Release an ephemeral materialization early |

`artifact.read` is limited to 1 MiB per call and 8 MiB total per artifact.
Larger content must be materialized. Import source paths are `localGrant`
inputs, not artifact references.

## 6. Accounts, authentication, and skins

| Method | Kind | Purpose/result |
| --- | --- | --- |
| `account.list` | Q | Non-secret account summaries and collection revision |
| `account.setDefault` | M | Select/clear default account |
| `account.login` | T | Start Microsoft authentication task |
| `account.refresh` | T | Refresh selected account |
| `account.remove` | T | Confirmed credential/profile removal |
| `account.offline.upsert` | M | Create/update an offline identity |
| `account.offline.remove` | M | Remove unused offline identity |
| `skin.list` | Q | Skin/cape metadata and preview artifact references |
| `skin.import` | T | Import explicit file/URL/username source through validation |
| `skin.upload` | T | Upload selected skin/model/cape through backend credentials |
| `skin.rename` | M | Rename local skin metadata |
| `skin.delete` | T | Confirmed local deletion |
| `skin.reset` | T | Reset remote skin/cape state |

Authentication waiting state is a task plus typed prompt/status event. A safe
verification URL, expiry, and provider-required short user code may cross IPC.
The user code is `ephemeralSensitive`: it is excluded from logs, durable
snapshots, and cross-epoch replay and expires with the attempt. OAuth access and
refresh tokens, device codes, authorization headers, and cookies never cross.

## 7. Java and settings

| Method | Kind | Purpose/result |
| --- | --- | --- |
| `java.list` | Q | Known/discovered managed and external installations |
| `java.discover` | T | Rescan supported locations |
| `java.validate` | T | Validate one installation against optional instance requirements |
| `java.install` | T | Download, verify, install managed Java |
| `java.selectGlobal` | M | Change global selection |
| `java.selectInstance` | M | Change/reset instance override |
| `settings.global.get` | Q | Typed global settings and revision |
| `settings.global.update` | M | Validated patch with expected revision |
| `settings.instance.get` | Q | Effective values, overrides, and revision |
| `settings.instance.update` | M | Set/reset validated overrides |

Settings methods use typed patch objects. They never expose raw INI keys as a
generic map and never provide arbitrary JVM/environment execution without
backend validation and explicit advanced-setting fields.

## 8. Launch and managed processes

| Method | Kind | Purpose/result |
| --- | --- | --- |
| `launch.prepare` | T | Optional explicit update/download verification without starting game |
| `launch.start` | T | Complete claim/update/Java/natives/launch chain |
| `launch.get` | Q | Managed launch state by launch or instance ID |
| `launch.stop` | T | Graceful stop when supported |
| `launch.kill` | T | Explicit confirmed force kill |
| `launch.sendCommand` | M | Optional bounded stdin command for supported server/process modes |

`launch.start` intent includes instance ID, account/offline identity reference,
optional server/world target, and launch setting overrides from an allowlisted
schema. It never accepts a Java executable, classpath, shell command, arbitrary
environment map, token, or launch script from the client.

Launch state is `preparing`, `downloading`, `awaiting_interaction`, `starting`,
`running`, `stopping`, `exited`, `crashed`, or `failed`. It includes a stable
launch ID, revision, instance ID, safe process metadata, task ID, start/end
timestamps, exit classification, and crash diagnostic/artifact references.
Raw PID is diagnostic and never sufficient process identity for stop/kill.

## 9. Utilities

| Method | Kind | Purpose/result |
| --- | --- | --- |
| `news.list` | Q | Cached/refreshed news entries with safe links |
| `update.check` | T | Check application/backend compatibility and available update |
| `update.applyDecision` | T | Install/remind/skip after explicit UI choice |
| `shortcut.create` | T | Create a validated macOS shortcut at an explicit destination grant |
| `diagnostic.bundle.create` | T | Produce a redacted diagnostic artifact after confirmation |

Application replacement, authorization, relaunch, signing and notarization are
outside generic backend RPC. Update methods must integrate with the designated
macOS updater and drain protocol.

## 10. Event catalog

Every event is delivered through `event.publish` with topic, epoch, sequence,
aggregate ID/revision, and typed `data`.

| Event | Topic | Semantics |
| --- | --- | --- |
| `instance.added` / `instance.changed` / `instance.removed` | `instances` | Authoritative collection/aggregate delta |
| `settings.globalChanged` / `settings.instanceChanged` | `settings` | Confirmed revisioned settings snapshot/delta |
| `account.added` / `account.changed` / `account.removed` | `accounts` | Non-secret account delta |
| `java.changed` | `java` | Discovery/selection change |
| `task.created` / `task.changed` | `tasks` | Task snapshot or delta; terminal never coalesced |
| `task.logAppended` | `tasks` | Bounded redacted log cursor/chunk when subscribed |
| `prompt.created` / `prompt.changed` | `prompts` | Persistent task interaction state |
| `launch.created` / `launch.changed` | `launches` | Managed game process lifecycle |
| `provider.capabilitiesChanged` | `providers` | Provider availability/filter capability changed |
| `session.controlChanged` | `session` | Lease availability changed |
| `backend.draining` / `backend.closing` | `system` | Lifecycle notice; not task success |
| `state.resyncRequired` | `system` | Client queue overflow or server-detected state gap |

Removal events contain tombstone ID and final revision, not an empty object.
Collection reorder events contain the complete ordered stable-ID list or a new
collection revision; clients never infer ordering from event arrival timing.

## 11. Explicitly forbidden generic methods

PBP v1 MUST NOT expose:

- `file.read`, `file.write`, arbitrary glob/list/delete/move;
- `process.execute`, shell strings, raw executable/argument/environment RPC;
- `network.fetch` or arbitrary URL/proxy/header input;
- raw settings-key mutation;
- database query/SQL methods;
- credential/token/keychain read methods;
- backend-generated HTML/Markdown that is rendered without sanitization;
- UI commands such as show dialog, navigate, select row, or update progress bar.

New methods require a domain owner, capability name, request/result schemas,
idempotency/revision semantics, security review, recovery behavior, event
impact, C++/Swift golden vectors, and compatibility classification.

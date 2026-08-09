# Prism macOS Native UI Migration Plan

Status: approved execution design

Branch: `macos-native`

Repository: `ChrisLloydME/Prism`

Native application target: `macos/PrismNative.xcodeproj`, scheme `PrismNative`

Required bundle identifier: `com.lloydME.Prism`

Mutable execution ledger: `docs/macos-native-migration/PROGRESS.md`

## 1. Purpose

This document is the durable command surface for migrating Prism Launcher from Qt Widgets to a macOS-only SwiftUI and AppKit frontend. It is intentionally more explicit than a normal engineering plan because it must remain usable by an agent with limited context and weaker architectural judgment.

The plan owns stable decisions, boundaries, phase order, verification, commit rules, and stop conditions. `PROGRESS.md` owns current state. An agent may update progress and implementation details, but must not silently weaken the constraints in this plan.

### Urgent storage-isolation override (2026-08-09)

The user observed accounts and Java information from their normally used Prism Launcher installation inside Native Prism Settings. This observation invalidates every earlier claim that naming the native data root `Prism` or merely checking non-equality with `PrismLauncher` proves isolation. Treat this as a release-blocking safety defect. Do not inspect the user's real files to confirm it; the observation itself is sufficient evidence that the current contract is unsafe.

Before any remaining migration or cutover work, production composition must prove that Native Prism uses its own bundle-scoped persistence namespace and cannot discover, inherit, import, fall back to, or write any Prism Launcher support state. Fixture-only account and Java tests do not satisfy this requirement.

## 2. Start-of-turn protocol

Every implementation turn must begin in this order:

1. Run `pwd` and `git rev-parse --show-toplevel`. The expected root is `/Users/lloyd/Developer/Xcode/Prism`.
2. Run `git status --short --branch -uall`. Do not discard, stash, overwrite, or clean existing work.
3. Read this file in full.
4. Read `docs/macos-native-migration/PROGRESS.md` in full.
5. Read the last five commits with `git log -5 --oneline` and inspect the latest migration commit body.
6. Select exactly one ready work unit from the active milestone.
7. Re-read every source file named by that work unit before editing.
8. Confirm that the work unit can end in a buildable, testable, independently useful commit.

If the worktree contains unrelated changes, preserve them and commit only files that belong to the selected work unit.

## 3. Executable Goal

```text
/goal Complete the PrismNative Xcode target on the macos-native branch as a feature-complete, Apple-native, macOS-only Prism Launcher frontend. Preserve the existing launcher behavior and data formats, reuse the existing C++ core through a testable QWidget-free backend facade, and expose that facade to Swift only through an Objective-C++ bridge using Foundation value types, commands, state, and events.
验证：At the start of every turn read PLAN.md, PROGRESS.md, git status, and recent commit bodies. Maintain the migration inventory and evidence ledger in PROGRESS.md. Build Debug and Release configurations with xcodebuild, run PrismNativeTests, run the smallest relevant CMake build and C++ tests for backend changes, run git diff --check, and inspect the built Info.plist with plutil to prove that CFBundleIdentifier remains com.lloydME.Prism. Verify UI structure with native API inspection, ViewModel and command tests, accessibility metadata checks, menu and shortcut tests, localization checks, and Apple HIG conformance records. Never launch the application, capture screenshots, record the screen, or use visual snapshot tests as completion evidence.
约束：Keep the bundle identifier fixed at com.lloydME.Prism. The production Application Support root must be exactly the bundle-scoped `~/Library/Application Support/com.lloydME.Prism` namespace, and every other persistent macOS namespace must use `com.lloydME.Prism`; never use the generic `Prism` or upstream `PrismLauncher` identity. Native Prism must not discover, inherit, import, fall back to, read, or write any upstream account, Java, instance, settings, cache, log, preference, saved-state, or Keychain data. Prefer Apple-provided SwiftUI and AppKit controls and behavior. Do not custom-draw a system control. Swift must not import Qt or expose C++ ownership. Objective-C++ exclusively owns C++ and Qt lifetime, threading, cancellation, and type conversion. Do not rewrite stable launcher business logic without a regression test. Do not add a third-party UI framework. Do not weaken accessibility, keyboard operation, localization, cancellation, error recovery, or data compatibility.
边界：Write only under macos, docs/macos-native-migration, directly required launcher backend and build configuration files, and directly related tests. Do not read or modify the installed upstream application, the upstream Application Support directory, real accounts, Keychain items, production API data, signing settings, notarization state, or unrelated platform code. Keep caches, generated output, and fixture data in ignored or temporary directories. Do not push, publish, install, sign, notarize, or open a pull request without separate user authorization.
迭代策略：Implement one work unit at a time. Each unit must have a narrow outcome, tests, documentation update, and independent commit. Before every commit update PROGRESS.md with status, files, commands, results, HIG decisions, risks, and next step. Use a Conventional Commit subject and a detailed body that records behavior, architecture, exact verification, known limits, and follow-up. Never commit failing checks or stale progress. After the same failure twice, stop retrying and obtain new evidence from logs, callers, tests, official Apple documentation, or the legacy implementation. After interruption or context compaction, resume only from PLAN.md, PROGRESS.md, git status, and committed evidence.
完成条件：Every in-scope Qt UI workflow in the migration inventory has a native implementation, a documented facade and bridge contract, automated non-launch verification, and a completed progress entry. PrismNative completes all core launcher workflows without QWidget or QDialog. Debug and Release builds pass, all native and directly relevant C++ tests pass, Bundle ID and bundle-scoped storage isolation contracts pass, and production composition has no generic `Prism`, upstream `PrismLauncher`, legacy fallback, automatic import, shared preferences, or shared Keychain path. No forbidden runtime visual verification was used, every custom-rendering exception is justified, the progress ledger contains a final commit index and remaining non-blocking limitations, and the worktree is clean.
暂停条件：Pause before accessing upstream user data, real accounts, Keychain, credentials, signing, notarization, publishing, pushing, or destructive operations. Pause if a workflow appears to require a third-party UI framework, substantial custom drawing, an irreversible data-format change, an authentication behavior change, or a product decision not settled by this plan. If the same blocker survives three rounds using distinct new evidence, record the blocker and exact recovery requirement in PROGRESS.md, then stop.
```

## 4. Fixed decisions

### 4.1 Product scope

The product is a separate macOS application and fork. Windows and Linux UI compatibility is not a goal. Existing cross-platform backend code may remain cross-platform when changing it would add risk without helping the native frontend.

### 4.2 UI technology

SwiftUI owns scenes, navigation, forms, commands, standard controls, presentation, and most state binding. AppKit is used when it offers the established macOS implementation for a desktop-specific need or when SwiftUI lacks the required capability. Objective-C++ is a bridge, not the primary UI language.

The native target keeps its current macOS 14.0 minimum deployment target unless the user separately approves a change. Agents must choose APIs available at that deployment target or add an availability-safe native fallback.

### 4.3 Backend reuse

Existing instance, account, metadata, download, installation, Java, mod platform, archive, settings, and launch logic remains the behavioral source of truth. The migration extracts a UI-neutral facade rather than recreating that behavior in Swift.

### 4.4 No direct Qt exposure

Swift source must not import Qt headers or receive `QObject`, `QString`, `QVariant`, `QModelIndex`, Qt model objects, QWidget objects, or unmanaged C++ pointers. The public bridge uses immutable Foundation value objects and opaque string identifiers.

### 4.5 Data safety

The native product remains `com.lloydME.Prism` with display name `Prism`. Display name is presentation only and must never determine a persistence path. The earlier `Prism` data-root decision is revoked because a generic product-name directory can collide with or inherit data from another Prism installation.

Production defaults are bundle-scoped and exclusive:

| State class | Required Native Prism namespace |
| --- | --- |
| Application Support, including instances, accounts, Java selection, settings, metadata, downloads, and managed assets | `~/Library/Application Support/com.lloydME.Prism` |
| Caches | `~/Library/Caches/com.lloydME.Prism` |
| Preferences and `UserDefaults` | `~/Library/Preferences/com.lloydME.Prism.plist` and the standard `com.lloydME.Prism` suite only |
| Saved application state | `~/Library/Saved Application State/com.lloydME.Prism.savedState` |
| Logs owned by Native Prism | `~/Library/Logs/com.lloydME.Prism` |
| Keychain service or access-group identifiers, if later authorized | Names beginning with `com.lloydME.Prism`; never an upstream or generic Prism identifier |

The following rules are mandatory:

1. Resolve the default Application Support root from the macOS Application Support directory and append the exact bundle identifier `com.lloydME.Prism`. Do not append the display name, executable name, organization name, `Prism`, or `PrismLauncher`.
2. Production facade construction must receive only this resolved bundle-scoped root. It must not derive a root from Qt `Application`, process arguments, environment variables, the current working directory, a sibling installation, or legacy launcher defaults.
3. Never probe, enumerate, read, merge, migrate, or write `~/Library/Application Support/Prism`, `~/Library/Application Support/PrismLauncher`, any upstream organization/bundle directory, or a parent directory containing them.
4. Do not implement automatic legacy discovery, compatibility fallback, account import, Java import, instance import, settings import, symlink traversal, alias resolution, or shared `UserDefaults` suites. Any future user-requested import must be a separate, explicit, previewable, copy-only workflow with new authorization and must never become a fallback path.
5. Account lists and Java installations shown by Native Prism must come only from the Native Prism root or an explicitly injected test fixture. System-wide Java discovery may be added only as a deliberate scan of system Java installations; it must not read another launcher's saved Java choices, metadata, or settings.
6. No production dependency may receive the user's home directory or the general `Application Support` directory when it only needs the Native Prism root.
7. Tests must inject a synthetic home or temporary data root and assert canonical-path containment. Tests must never inspect the user's actual home, upstream support directories, real accounts, Keychain, or installed application.
8. Existing tests that prove only `Prism != PrismLauncher` are insufficient and must be replaced or strengthened to assert the exact `com.lloydME.Prism` namespace and reject every forbidden alias and fallback.

### 4.6 UI verification

Agents must not launch the application, take screenshots, record the screen, use UI snapshot tests, or claim visual correctness from rendered output. Verification relies on build evidence, unit tests, view-model tests, accessibility contracts, menu and command tests, static API checks, localization validation, and review against official Apple guidance.

## 5. Architecture

```text
SwiftUI scenes and features
        |
        | immutable state, intents, async results
        v
Swift feature stores and view models
        |
        | Foundation DTOs and Objective-C protocols
        v
Objective-C++ bridge
        |
        | ownership, conversion, main-thread delivery, cancellation
        v
C++ frontend facade with no QWidget API
        |
        | existing domain objects and tasks
        v
Prism launcher core using QtCore and QtNetwork where required
        |
        v
Filesystem, Java, authentication, downloads, Minecraft process
```

Dependencies point downward only. The backend must never import SwiftUI or AppKit. The facade must never return a UI object. The bridge may import Foundation and C++ headers. Swift may import only the bridge's public Objective-C headers.

### 5.1 Target structure

The intended repository structure is:

```text
macos/PrismNative.xcodeproj
macos/PrismNative/App
macos/PrismNative/Commands
macos/PrismNative/Features
macos/PrismNative/Models
macos/PrismNative/Services
macos/PrismNative/AppKit
macos/PrismNative/Bridge
macos/PrismNative/Resources
macos/PrismNativeTests
launcher/frontend
docs/macos-native-migration/PLAN.md
docs/macos-native-migration/PROGRESS.md
```

`launcher/frontend` is the preferred home for the C++ facade. It must compile without UI headers in its public surface. If the existing build layout proves that another directly adjacent backend folder is cleaner, record the reason in `PROGRESS.md` before creating it.

### 5.2 Facade responsibilities

The facade provides use-case operations, not raw models. Its responsibilities are:

- Initialize and shut down backend services against an explicit data root.
- Return instance, group, account, task, version, resource, server, world, and settings snapshots.
- Execute commands such as create, import, copy, delete, launch, stop, update, install, export, and edit.
- Provide observable domain events with stable identifiers.
- Expose task progress, cancellation support, error category, recovery action, and diagnostic text.
- Serialize mutations so two UI actions cannot corrupt the same instance.
- Keep authentication secrets out of DTOs and logs.

The facade does not provide row numbers, Qt roles, widget pointers, display colors, pixel geometry, or formatted UI layouts.

### 5.3 Bridge responsibilities

The Objective-C++ bridge owns:

- All C++ object lifetime visible to the native target.
- Conversion between Qt or C++ values and Foundation values.
- Delivery of callbacks to the main actor.
- Cancellation token mapping.
- Error translation into stable native error codes and localized message keys.
- Protection against callbacks after Swift observers are released.
- Startup ordering for QtCore services that require an event dispatcher.

The bridge public headers must be valid Objective-C headers when compiled without C++ mode. A test must scan public bridge headers and reject known Qt and C++ type names.

### 5.4 Swift state model

Each feature has a store or view model with four explicit states:

- Loading: initial or refreshed data is not ready.
- Content: a stable snapshot is available.
- Empty: the operation succeeded but there is no content.
- Failed: an error and available recovery action are present.

Long-running operations additionally expose determinate or indeterminate progress and whether cancellation is safe. Views send intents to stores. Views do not call Objective-C++ objects directly except during composition at the feature boundary.

### 5.5 Threading contract

- SwiftUI state mutations occur on the main actor.
- Backend work remains on existing Prism task queues or explicit worker queues.
- The bridge never synchronously waits on the main thread for network, filesystem, Java, archive, or process work.
- Every callback checks cancellation and observer lifetime before delivery.
- Shutdown rejects new work, cancels safe operations, waits only where required for data integrity, then destroys backend objects in dependency order.
- Tests cover callback delivery after cancellation and observer release.

### 5.6 Error contract

Errors cross the bridge with:

- Stable domain and code.
- Localization key and substitution values.
- Optional diagnostic text safe for logs.
- Recovery kind such as retry, authenticate, choose file, reveal path, open settings, or none.
- Whether partial changes were rolled back.

Do not expose raw exception text as the only user message. Do not log access tokens, refresh tokens, authorization codes, or full user paths from private fixtures.

## 6. Apple-native implementation policy

### 6.1 Default components

Use the system implementation first:

| Need | Preferred implementation |
| --- | --- |
| Main hierarchy | `NavigationSplitView` |
| Sidebar | `List` with sidebar style and system selection |
| Instance collection | `Table`, `List`, or `NSCollectionView` only when collection semantics require it |
| Detail editing | `Form`, `Section`, `LabeledContent`, standard controls |
| Settings | SwiftUI `Settings` scene with system Settings command |
| Frequent actions | `Toolbar`, paired with menu-bar `Commands` |
| Secondary actions | `Menu`, context menu, command groups |
| Search | `.searchable` |
| Open and import | `fileImporter` or `NSOpenPanel` |
| Save and export | `fileExporter` or `NSSavePanel` |
| Destructive confirmation | `confirmationDialog` or AppKit alert when required |
| Error presentation | `alert` with recovery action, or a modeless content state |
| Progress | `ProgressView` or `NSProgressIndicator` |
| Tables | SwiftUI `Table` or `NSTableView` |
| Rich text and large logs | `TextEditor`, `NSTextView`, or TextKit |
| Drag and drop | SwiftUI transferable APIs or AppKit pasteboard APIs |
| Icons | SF Symbols for commands, original instance artwork for content |
| Keyboard shortcuts | `Commands` and standard command groups |
| Window behavior | SwiftUI scenes and AppKit window APIs, never simulated title bars |

### 6.2 Self-drawing prohibition

Do not use Canvas, custom `draw` methods, Core Graphics, Metal, OpenGL, hand-built CALayer rendering, or bitmap replicas to implement controls or window chrome that Apple already provides.

Allowed domain-rendering candidates are limited to Minecraft skin preview, screenshots, pack artwork, instance artwork, and other content whose purpose is the image itself. Before adding one, the agent must record in `PROGRESS.md`:

1. The user need that cannot be expressed by a system view.
2. Apple APIs investigated.
3. Why composition of system views is insufficient.
4. Accessibility representation.
5. Performance and memory limits.
6. Test strategy that does not use screenshots.

### 6.3 HIG rules that agents must preserve

- Important commands exist in the menu bar even when also present in a toolbar.
- Toolbar items are few, contextual, and system-managed where possible.
- Settings are reached through the application Settings command and standard Command-Comma shortcut.
- Sidebars use system accent behavior, remain hideable, and do not put critical actions at the bottom.
- Long-running work uses determinate progress when total work is known and indeterminate progress otherwise.
- Destructive commands are clearly named, separated, and confirmed when reversal is not immediate.
- Keyboard-only operation and VoiceOver names are part of the feature contract.
- Empty and error states explain the next useful action without inventing a custom card system.
- Dynamic Type is not a macOS requirement in the iOS sense, but system fonts, user font preferences where relevant, and truncation behavior must remain legible.
- Localized strings must not be concatenated from fragments.

Official references:

- https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/
- https://developer.apple.com/design/human-interface-guidelines/sidebars
- https://developer.apple.com/design/human-interface-guidelines/toolbars
- https://developer.apple.com/design/human-interface-guidelines/menus
- https://developer.apple.com/design/human-interface-guidelines/settings
- https://developer.apple.com/design/human-interface-guidelines/progress-indicators
- https://developer.apple.com/design/human-interface-guidelines/layout
- https://developer.apple.com/documentation/swiftui/settings

## 7. Migration inventory

The source inventory begins with `launcher/ui`, but agents must trace each surface into its backend collaborators before assigning status.

### 7.1 Application shell

| Legacy source | Native destination | Required behavior |
| --- | --- | --- |
| `launcher/ui/MainWindow` | App shell, sidebar, instance content, toolbar, commands | Selection, groups, search, launch, create, import, edit, context commands |
| `launcher/ui/InstanceWindow` | Instance detail scene or detail navigation | Instance-specific management and logs |
| `launcher/ui/instanceview` | Instance list or collection feature | Grouping, ordering, selection, keyboard, accessibility, context actions |
| `launcher/ui/ViewLogWindow` | Native log window or inspector | Large text, copy, save, search, privacy filtering |

### 7.2 Global settings and accounts

| Legacy source | Native destination |
| --- | --- |
| `ui/pages/global/LauncherPage` | General settings pane |
| `ui/pages/global/AppearancePage` | Appearance settings pane using system appearance choices |
| `ui/pages/global/LanguagePage` | Language settings pane |
| `ui/pages/global/JavaPage` | Java settings pane |
| `ui/pages/global/MinecraftPage` | Minecraft defaults pane |
| `ui/pages/global/ProxyPage` | Network settings pane |
| `ui/pages/global/APIPage` | Service settings pane |
| `ui/pages/global/ExternalToolsPage` | External tools settings pane |
| `ui/pages/global/AccountListPage` | Accounts settings pane |

### 7.3 Instance management

The native instance detail must cover notes, versions and components, mods, data packs, resource packs, texture packs, shader packs, worlds, servers, screenshots, settings, external resources, managed packs, game options, active log, and historical logs.

Primary source families are:

- `launcher/ui/pages/instance`
- `launcher/minecraft`
- `launcher/settings`
- `launcher/launch`
- `launcher/logs`

### 7.4 Creation, installation, and discovery

The native flow must cover vanilla creation, local import, copy, Modrinth, CurseForge or Flame, FTB variants, ATLauncher, Technic, custom packs, optional mods, provider selection, loader selection, blocked mods, updates, exports, and cancellation.

Primary source families are:

- `launcher/ui/pages/modplatform`
- `launcher/ui/dialogs/NewInstanceDialog`
- `launcher/ui/dialogs/InstallLoaderDialog`
- `launcher/ui/dialogs/ResourceDownloadDialog`
- `launcher/modplatform`
- `launcher/meta`

### 7.5 Accounts and authentication

The native flow must cover account list, active account, Microsoft device-code authentication, login progress, cancellation, token refresh errors, offline launch name, profile setup, and profile selection. Real credentials are never used by automated tests.

Primary source families are:

- `launcher/minecraft/auth`
- `launcher/ui/dialogs/MSALoginDialog`
- `launcher/ui/dialogs/ProfileSetupDialog`
- `launcher/ui/dialogs/ProfileSelectDialog`
- `launcher/ui/dialogs/ChooseOfflineNameDialog`

### 7.6 Supporting dialogs

Every legacy dialog must be classified as one of:

- Replaced by a system presentation modifier.
- Replaced by an AppKit standard panel.
- Replaced by navigation to a dedicated native feature.
- Removed because the native workflow makes it unnecessary.
- Retained temporarily with an explicit blocker and no claim of completion.

Do not reproduce a one-dialog-per-action structure without first checking whether the Mac convention is a sheet, popover, settings pane, inspector, confirmation, open panel, or inline state.

## 8. Milestones and work units

Every milestone is independently mergeable. If work stops after any milestone, the existing Qt application still builds and the native target remains buildable.

### Milestone 1: Contracts, tests, and durable inventory

Outcome: the scaffold has enforceable safety contracts and a complete feature ledger.

Work units:

1. Add a shared `PrismNative` scheme if Xcode does not already expose a stable shared scheme.
2. Add `PrismNativeTests` with test fixtures stored under an ignored temporary root.
3. Test Bundle ID, display name, the exact bundle-scoped Application Support root, canonical containment, and rejection of generic/upstream aliases and fallback paths.
4. Add a bridge-header scan that rejects Qt and C++ types in public headers.
5. Add test helpers for main-actor callbacks, cancellation, and temporary directories.
6. Fill every migration inventory row in `PROGRESS.md` with a source owner and initial status.
7. Add a build script only if it removes repeated command ambiguity; do not add a new build system.

Exit evidence:

- Debug build passes.
- Test target passes without launching the app.
- Info.plist check prints `com.lloydME.Prism`.
- Progress ledger contains every legacy feature family.

### Milestone 2: QWidget-free backend facade

Outcome: a native client can initialize backend services, list fixture instances, observe changes, and shut down without importing UI headers.

Work units:

1. Split source classification in `launcher/CMakeLists.txt` into domain sources, UI sources, and executable composition without changing runtime behavior.
2. Introduce the frontend facade target or library under `launcher/frontend`.
3. Make the facade accept an explicit data root and runtime dependencies.
4. Add instance snapshot and instance-change event contracts.
5. Add lifecycle and shutdown tests.
6. Ensure facade public headers compile without including `launcher/ui`.
7. Keep the existing Qt executable linked and behaviorally unchanged.

Exit evidence:

- Existing Qt target builds.
- Facade tests pass against fixtures.
- A dependency scan finds no QWidget or QDialog in facade public headers.
- Native target still builds independently.

### Milestone 3: Objective-C++ bridge foundation

Outcome: Swift can initialize the facade against a temporary root and receive instance snapshots and events.

Work units:

1. Replace identity-only bridge composition with a lifecycle-owning bridge root.
2. Add immutable Foundation DTOs for instance summary and task status.
3. Add protocols or callback tokens for observation with explicit cancellation.
4. Add error translation and main-actor delivery.
5. Add bridge contract tests for initialization, empty data, fixture data, cancellation, shutdown, and released observers.
6. Link backend output into Xcode without copying launcher implementation files into the app target.

Exit evidence:

- Native tests obtain fixture instance snapshots through the real bridge.
- Thread and cancellation tests pass.
- No Qt or C++ type appears in Swift or public bridge headers.

### Milestone 4: Native application shell and instance library

Outcome: the native target represents the instance library and all shell commands using system navigation and controls.

Work units:

1. Define app commands and keyboard shortcuts before toolbar duplication.
2. Implement sidebar and instance content with `NavigationSplitView`.
3. Implement selection, grouping, sorting, and search in testable Swift state.
4. Implement loading, empty, failed, and content states.
5. Implement contextual menus and toolbar commands through the same command model.
6. Add accessibility labels, help, enabled state, and keyboard tests.
7. Add instance artwork loading with bounded caching; artwork is content, not control chrome.

Exit evidence:

- View-model tests cover instance states, selection, search, grouping, commands, and errors.
- Menu and shortcut definitions are tested.
- Static source review confirms system navigation, list, search, toolbar, and menu APIs.

### Milestone 5: Launch, stop, tasks, and logs

Outcome: the native command model can launch and stop a fixture-controlled instance workflow and present task state and logs without custom controls.

Work units:

1. Add launch and stop facade commands using stable instance identifiers.
2. Add task progress, subtasks, cancellation, and terminal result DTOs.
3. Map task state to `ProgressView` or `NSProgressIndicator` semantics.
4. Add log streaming with bounded memory and privacy filtering.
5. Use TextKit or standard text views for large logs.
6. Add tests for success, launch rejection, cancellation, failure, retry eligibility, shutdown, and log truncation.

Exit evidence:

- All task transitions are covered by deterministic tests.
- No test launches a real Minecraft process or reads a real account.
- The old Qt launch path remains buildable until native parity is complete.

### Milestone 6: Instance detail and editing

Outcome: native instance detail covers metadata, notes, settings, versions, files, and content management.

Work units:

1. Implement metadata and notes.
2. Implement instance settings with `Form` and standard controls.
3. Implement version and component list with `Table` or `List`.
4. Implement mods and pack resources with system tables, search, selection, enable state, drag and drop, import, reveal, and delete confirmation.
5. Implement worlds, servers, screenshots, and logs.
6. Add optimistic-edit rollback where safe, otherwise wait for confirmed backend state.
7. Test permission errors, missing files, conflicts, invalid archives, cancellation, and external changes.

Exit evidence:

- Each detail section has view-model and facade tests.
- File mutations use temporary fixtures.
- Destructive actions have explicit recovery or confirmation behavior.

### Milestone 7: Settings, Java, and accounts

Outcome: global configuration and account workflows use the native Settings scene and system navigation.

Work units:

1. Map settings keys, defaults, validation, and restart requirements.
2. Implement settings panes with standard controls.
3. Implement Java discovery and selection with progress and errors.
4. Implement account snapshots and active-account selection.
5. Implement authentication state machine with fake providers for tests.
6. Implement offline launch identity.
7. Confirm no secret crosses into logs, progress files, DTO descriptions, or test fixtures.

Exit evidence:

- Command-Comma and Settings scene configuration are present.
- Settings round-trip tests pass.
- Account tests use fakes and contain no credentials.

### Milestone 8: Creation, import, discovery, and installation

Outcome: all supported instance acquisition workflows are available through native navigation and system presentations.

Work units:

1. Create vanilla instance.
2. Import from local file and URL.
3. Copy and export instance.
4. Browse providers with shared search, filtering, pagination, version selection, and cancellation models.
5. Install Modrinth, CurseForge or Flame, FTB variants, ATLauncher, Technic, and custom packs through existing backend tasks.
6. Handle optional files, blocked files, provider errors, network errors, disk errors, and rollback.
7. Use system open and save panels rather than custom file pickers.

Exit evidence:

- Provider adapters have fixture tests.
- Install flows verify success, failure, cancellation, and rollback without production network mutation.
- Supported providers in progress ledger match backend capability.

### Milestone 9: Remaining utilities and rendering exceptions

Outcome: remaining dialogs and utilities are classified and migrated, with custom rendering limited to documented content.

Work units:

1. About, news, updates, shortcuts, provider choices, and recovery messages.
2. Skin management and preview.
3. Any retained legacy surface receives an explicit blocking reason and owner.
4. Every custom renderer receives the required exception record and non-screenshot tests.
5. Remove obsolete native placeholders.

Exit evidence:

- No unclassified dialog remains.
- Custom-rendering exception list is complete.
- Accessibility representation exists for rendered content.

### Milestone 10: Native cutover and Qt UI retirement

Outcome: the shipped macOS product uses PrismNative for all in-scope workflows and no longer requires Qt Widgets UI.

Work units:

1. Run the final parity audit against the inventory.
2. Move packaging, resources, versioning, icons, entitlements, and update metadata to the native product target without changing Bundle ID.
3. Build Debug and Release from a clean derived-data path.
4. Remove macOS dependency on QWidget and QDialog only after parity evidence exists.
5. Delete obsolete Qt UI code only when it is macOS-only or safely excluded without harming backend reuse; otherwise leave shared upstream code intact but unused by the macOS product.
6. Produce the final commit index and limitations report.

Exit evidence:

- Final acceptance matrix is complete.
- Native and directly related C++ tests pass.
- Debug and Release builds pass.
- Bundle ID and data-root contracts pass.
- Worktree is clean.

## 9. Verification matrix

### 9.1 Required commands

Run from the repository root. Agents may add narrower checks, but may not omit the checks relevant to their change.

```sh
git diff --check

xcodebuild \
  -project macos/PrismNative.xcodeproj \
  -scheme PrismNative \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .deriveddata-prism-native \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project macos/PrismNative.xcodeproj \
  -scheme PrismNative \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .deriveddata-prism-native-release \
  CODE_SIGNING_ALLOWED=NO \
  build

plutil -extract CFBundleIdentifier raw \
  .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist
```

After `PrismNativeTests` exists, run its test action with an explicit macOS destination and a repository-local derived-data path. Record the exact command in `PROGRESS.md` because Xcode scheme layout can change.

For backend changes, discover and run the smallest relevant existing CMake target and CTest selection. If the configured build directory is unavailable, configure according to `macos/README.md` and record the chosen build directory. Do not silently invent a global test command.

### 9.2 Non-launch UI evidence

Each native feature must provide evidence in all applicable categories:

- Swift compiler type checks.
- View-model state-transition tests.
- Command enabled-state and keyboard-shortcut tests.
- Menu placement and command-group source inspection.
- Accessibility label, value, role, help, and focus-order contracts.
- Localization key existence and formatting tests.
- Empty, loading, error, progress, cancellation, and recovery tests.
- Static scan for forbidden custom drawing and forbidden Qt exposure.
- Apple HIG decision record with official URL.

Build success alone is not proof that a workflow is complete.

### 9.3 Required scenarios

For every use case, tests must cover:

- Happy path.
- Empty state.
- Invalid input.
- Permission or filesystem failure where applicable.
- Network failure where applicable.
- Cancellation where applicable.
- Backend error translation.
- Repeated command or concurrent request where applicable.
- Application shutdown during work where applicable.
- Long localized strings and missing optional metadata.

## 10. Commit protocol

### 10.1 Commit boundary

A commit contains one independently useful work unit, its tests, and its `PROGRESS.md` update. Do not mix unrelated cleanup, another milestone, generated caches, user-specific Xcode state, or formatting churn.

### 10.2 Commit format

Use Conventional Commits. Preferred scopes are `macos`, `bridge`, `frontend`, `instances`, `launch`, `settings`, `accounts`, `resources`, `tests`, and `docs`.

Every implementation commit has a body with these paragraphs:

1. Outcome: behavior or contract completed.
2. Design: native API and HIG decision, including why no custom control was required.
3. Architecture: facade, bridge, state, threading, cancellation, or data changes.
4. Verification: exact commands and results.
5. Limits: remaining limitation and the next ready work unit.

Example shape:

```text
feat(instances): expose native instance snapshots

Outcome: Add immutable instance summaries and change observation for fixture data.

Design: Keep grouping and search in native state so the UI can use system List and searchable behavior without custom cells.

Architecture: Add a QWidget-free facade snapshot and convert it to Foundation objects in Objective-C++ with main-actor delivery.

Verification: Debug build passed. PrismNativeTests instance snapshot and cancellation tests passed. git diff --check passed.

Limits: Launch commands remain on the legacy path. Next unit adds command availability without process execution.
```

### 10.3 Commit gate

Before committing:

1. Re-read `git status --short --branch -uall`.
2. Confirm every staged file belongs to the work unit.
3. Run `git diff --cached --check`.
4. Run relevant builds and tests.
5. Update `PROGRESS.md` with exact evidence and next step.
6. Review the staged diff.
7. Commit with the detailed format.
8. Re-read `git status` and commit log.

Do not amend or rewrite a commit unless the user explicitly asks. Do not push unless the user explicitly asks.

## 11. Progress ledger protocol

`PROGRESS.md` is a live recovery artifact, not a narrative report. Keep it current and compact.

Every work unit entry records:

- Stable identifier such as `M3-W2`.
- Status: queued, ready, active, blocked, complete, or superseded.
- Outcome.
- Files changed.
- Tests and exact commands.
- Result summary.
- HIG or official API decision.
- Commit hash after commit.
- Known risk.
- Exact next work unit.

Rules:

- Only one work unit may be active.
- Only work that has no unmet predecessor may be ready. Later work remains queued.
- A complete unit must have a commit hash and passing evidence.
- A blocked unit must name the blocker, evidence already gathered, and one concrete resume condition.
- Never mark a milestone complete while any required work unit is ready, active, or blocked.
- After context compression, trust committed code and `PROGRESS.md` over memory or earlier chat summaries.
- If progress disagrees with the repository, correct the progress ledger in the next commit and explain the discrepancy.

## 12. Safety and rollback

### 12.1 Protected user state

Never access or mutate:

- `/Applications/Prism Launcher.app`
- `~/Library/Application Support/Prism`
- `~/Library/Application Support/PrismLauncher`
- Any upstream Prism Launcher bundle/organization support directory discovered from legacy code or installed metadata
- `~/Library/Caches/Prism`, `~/Library/Caches/PrismLauncher`, upstream preference domains, upstream saved-state directories, and upstream log directories
- User Keychain entries associated with Prism Launcher or Microsoft authentication
- Real instance directories unless the user separately provides and authorizes a disposable copy

Tests must inject a temporary data root or synthetic home. Destructive operations must resolve symlinks and assert that the canonical target is inside the fixture root before mutation. A path-prefix string comparison without component-boundary and canonicalization checks is not sufficient.

### 12.2 Rollback model

- The legacy Qt target remains buildable until native parity is complete.
- Each work unit is independently revertible.
- Schema changes are avoided. If unavoidable, use backward-compatible reads and writes until separately approved.
- External network mutations are not part of automated verification.
- Packaging, signing, notarization, installation, and publishing are separate authorization boundaries.

### 12.3 Dependency failure

If provider APIs or authentication services are unavailable, validate adapters with fixtures and record the missing live evidence. Do not weaken error handling or use real credentials to force progress.

### 12.4 Scale pressure

Instance lists, logs, mod lists, and search results must be tested at ten times ordinary fixture volume. The first expected pressure points are image caching, log buffering, list diffing, and provider pagination. Prefer system virtualization and bounded caches over custom drawing.

## 13. Pause and escalation rules

Pause and ask the user when:

- A required product behavior remains ambiguous after source inspection, and the alternatives change user data or migration cost.
- Signing, notarization, App Store, update publishing, API keys, or production credentials are required.
- A third-party UI dependency appears necessary.
- An Apple-native implementation cannot be found and substantial self-drawing appears necessary.
- Existing user data must be accessed.
- A destructive command would target anything outside a verified fixture root.
- A data-format or authentication compatibility change is required.
- The same blocker persists for three rounds using distinct evidence sources.

Do not pause merely because a task is large, a build is slow, a dependency needs normal local compilation, or the legacy code is difficult to read.

## 14. Final acceptance matrix

The migration is complete only when all rows are evidenced in `PROGRESS.md`:

| Area | Required evidence |
| --- | --- |
| Product identity | Bundle ID is `com.lloydME.Prism`; production Application Support resolves exactly to the bundle-scoped namespace; all generic/upstream aliases, fallbacks, imports, shared preferences, and shared Keychain identifiers are rejected by tests |
| Build | Debug and Release native builds pass |
| Native tests | All PrismNativeTests pass |
| Backend tests | All directly relevant C++ tests pass |
| Application shell | Native navigation, commands, search, selection, and states are covered |
| Instances | Create, import, copy, edit, launch, stop, delete, and export contracts are covered |
| Accounts | Account state, fake authentication, offline identity, errors, and secret handling are covered |
| Settings | Settings panes, defaults, validation, persistence, and restart semantics are covered |
| Resources | Mods, packs, worlds, servers, screenshots, versions, and providers are covered |
| Tasks | Progress, cancellation, errors, retry, shutdown, and log bounds are covered |
| Accessibility | Labels, values, roles, keyboard commands, focus semantics, and help are covered |
| Localization | No missing keys, fragment concatenation, or untested long strings remain |
| HIG | Each major surface has an official API and HIG decision record |
| Custom rendering | Only documented domain-content exceptions remain |
| Legacy UI | No core native workflow requires QWidget or QDialog |
| Documentation | Progress summary, limitations, evidence, and commit index are complete |
| Repository state | Worktree is clean and no generated or user-specific files are tracked |

## 15. Premise and failure mode

This plan assumes the existing Prism business logic can be separated from `QApplication`, global `APPLICATION` access, and QWidget-facing models without rewriting the domain. If that assumption fails for a subsystem, do not port that subsystem to Swift. Isolate the minimum dependency behind the facade, add characterization tests around existing behavior, and record the residual QtCore requirement. If the dependency cannot operate without QWidget, pause with a call graph and evidence before changing direction.

## 16. Out of scope without separate authorization

- Windows or Linux native UI.
- Rewriting Minecraft launch, authentication, provider, archive, or download logic in Swift for stylistic reasons.
- New cloud services, analytics, accounts, or paid dependencies.
- Redesigning instance or account data formats.
- Importing the user's production Prism Launcher data.
- Application signing, notarization, installation, distribution, release, push, or pull request creation.
- Visual acceptance through launching the application or capturing screenshots.

## 17. Next ready work unit

Historical milestone ordering is temporarily overridden by the 2026-08-09 storage-isolation incident. The next agent must execute `S0-W1` from `PROGRESS.md` before resuming M9-W4, M10, or production-adapter work. It must correct production composition to use the exact bundle-scoped persistence namespace, add the required positive and negative isolation tests without reading real user data, update `PROGRESS.md`, and commit the work with detailed verification evidence before selecting another unit.

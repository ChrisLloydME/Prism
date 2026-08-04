# Prism macOS Native Migration Progress

Last updated: 2026-08-04

Branch: `macos-native`

Plan: `docs/macos-native-migration/PLAN.md`

Current milestone: Milestone 1, contracts, tests, and durable inventory

Active work unit: none

Next ready work unit: `M1-W3`

## Safety baseline

| Contract | Status | Evidence |
| --- | --- | --- |
| Bundle ID is `com.lloydME.Prism` | complete | Commit `6de92da18`; built Info.plist checked with `plutil` |
| Native product name is `Prism` | complete | Commit `6de92da18`; built Info.plist checked with `plutil` |
| Default data identity differs from upstream `PrismLauncher` | complete | `Prism` application identity in `program_info/CMakeLists.txt` and native bridge; M1-W1 temporary-root contract test |
| Native Xcode target exists | complete | Commit `5172b3a75` |
| Objective-C++ public bridge exposes only Foundation types | complete, not yet automated | Commit `5172b3a75`; architecture review found no Qt or C++ type in public header |
| Native tests target exists | complete | M1-W1; shared scheme and standalone `PrismNativeTests.xctest` target |
| Upstream application and data are untouched | complete for current work | No application launch or installation was performed |

## Milestone status

| Milestone | Status | Completion requirement |
| --- | --- | --- |
| 1. Contracts, tests, and inventory | active | Native contract tests and complete feature ledger |
| 2. QWidget-free backend facade | queued | Facade lists fixture instances without UI headers |
| 3. Objective-C++ bridge foundation | queued | Swift receives real fixture snapshots and events |
| 4. Native shell and instance library | queued | System-native shell state and commands are tested |
| 5. Launch, tasks, and logs | queued | Deterministic launch-task contracts are tested |
| 6. Instance detail and editing | queued | Instance management surfaces have native contracts |
| 7. Settings, Java, and accounts | queued | Settings and fake-account workflows are covered |
| 8. Creation, discovery, and installation | queued | All supported providers and import flows are covered |
| 9. Utilities and rendering exceptions | queued | Remaining dialogs are classified and migrated |
| 10. Native cutover | queued | Final acceptance matrix is complete |

## Legacy feature inventory (M1-W2)

Inventory status: complete for the current `launcher/ui` source tree. Every source directory is assigned to a native destination, a backend owner, a verification class, and a migration milestone. Inventory rows are initial `queued` implementation status; completing this work unit does not claim that the native workflow already exists.

Source-scan evidence:

- `rg --files launcher/ui | sort` — 366 source, header, Objective-C++, and Qt Designer files.
- `rg --files launcher/ui -g '*.ui' | sort` — 62 Qt Designer forms.
- `find launcher/ui -type d -print | sort` — root shell plus `dialogs`, `instanceview`, `java`, `pagedialog`, `pages`, `setupwizard`, `themes`, and `widgets`; provider subfamilies are listed separately below.
- `rg -n '^class [A-Za-z0-9_]+|^struct [A-Za-z0-9_]+' launcher/ui --glob '*.h'` — class and model ownership scan used to identify UI-only models, page containers, accessibility adapters, and backend collaborators.

| ID | Legacy source family and observed members | Native destination | Backend owner / contract boundary | Verification class | Milestone / status |
| --- | --- | --- | --- | --- | --- |
| S1 | `launcher/ui/{MainWindow,InstanceWindow,ViewLogWindow,GuiUtil,ToolTipFilter}` and `MainWindow.ui` | SwiftUI app shell with `NavigationSplitView`, toolbar, `Commands`, instance detail navigation, and a log inspector | `Application`, `InstanceList`, `LaunchController`, `InstanceTask`, `NewsChecker`, `Task`, `logs/LogParser`, and `settings`; bridge exposes snapshots and commands only | Shell view-model states, selection/search/grouping, command enabled state, menu placement, shortcuts, accessibility, and log privacy/bounds | M4/M5, queued |
| D1 | `launcher/ui/dialogs`: `AboutDialog`, `BlockedModsDialog`, `ChooseOfflineNameDialog`, `ChooseProviderDialog`, `CopyInstanceDialog`, `CreateShortcutDialog`, `CustomMessageBox`, `ExportInstanceDialog`, `ExportPackDialog`, `ExportToModListDialog`, `IconPickerDialog`, `ImportResourceDialog`, `InstallLoaderDialog`, `MSALoginDialog`, `NetworkJobFailedDialog`, `NewComponentDialog`, `NewInstanceDialog`, `NewsDialog`, `ProfileSelectDialog`, `ProfileSetupDialog`, `ProgressDialog`, `ResourceDownloadDialog`, `ResourceUpdateDialog`, `ReviewMessageBox`, `ScrollMessageBox`, `UpdateAvailableDialog`, and `VersionSelectDialog` | Replace one-dialog-per-action flows with system sheets, alerts, menus, `fileImporter`, `fileExporter`, settings navigation, or dedicated native features | `InstanceCopyTask`, `InstanceImportTask`, `ResourceDownloadTask`, `ResourceUpdateTask`, `BaseInstaller`, `launcher/tasks`, `minecraft/auth`, `news`, `meta`, and updater contracts | Intent/state tests, error/recovery/cancellation tests, localization keys and long strings, file-panel contracts, and destructive confirmation checks | M5/M7/M8/M9, queued |
| D2 | `launcher/ui/dialogs/skins`: `SkinManageDialog`, `BoxGeometry`, `Scene`, and `SkinOpenGLWindow` | Skin management feature; preview is domain content and must use the documented exception process before any renderer is added | `minecraft/skins/{SkinList,SkinModel,SkinUpload,SkinDelete,CapeChange}` and asset loading; no renderer or Qt type crosses the bridge | Skin list/edit tests, accessibility representation, bounded image memory, and non-screenshot renderer tests | M9, queued; custom-rendering exception not approved |
| V1 | `launcher/ui/instanceview`: `InstanceView`, `InstanceProxyModel`, `InstanceDelegate`, `VisualGroup`, `AccessibleInstanceView`, and private accessibility support | System `List`/`Table` instance library with native selection, grouping, sorting, search, context menus, and VoiceOver metadata | `InstanceList`, `InstanceGroup`, `BaseInstance`, icon/artwork services, and stable instance identifiers | State transitions, ten-times fixture volume, keyboard selection, command availability, accessibility role/name/value/help, and bounded artwork cache | M4, queued |
| J1 | `launcher/ui/java`: `InstallJavaDialog`/`Java::InstallDialog` and `VersionList` | Settings Java pane with system list/table, standard open panel, progress, and error recovery | `launcher/java/{JavaChecker,JavaInstall,JavaInstallList,JavaMetadata,JavaUtils,JavaVersion}` and `tasks` | Discovery/selection round trips, missing/incompatible Java, cancellation, filesystem errors, progress, and localization | M7, queued |
| N1 | `launcher/ui/pagedialog`, `pages/{BasePage,BasePageContainer,BasePageProvider}`, and `widgets/{PageContainer,PageModel,PageView}` | SwiftUI navigation destinations, sheets, and `NavigationStack`; no generic Qt page container in the native public contract | Page-specific facade use cases; bridge returns immutable page snapshots and command results rather than page/widget objects | Static no-Qt bridge scan, navigation state, focus order, empty/loading/failed states, and command routing | M3/M4/M6/M7/M8, queued |
| G1 | `launcher/ui/pages/global`: `LauncherPage`, `AppearancePage`, `LanguagePage`, `JavaPage`, `MinecraftPage`, `ProxyPage`, `APIPage`, `ExternalToolsPage`, and `AccountListPage` | SwiftUI `Settings` scene with standard `Form`, `Section`, `Picker`, `TextField`, toggles, tables, and system Settings command | `settings`, `minecraft`, `java`, `minecraft/auth`, `Application`, network/proxy services, and external-tool settings | Settings key/default/validation/restart matrix, round trips against temporary roots, fake accounts/auth, Command-Comma, accessibility, and localization | M7, queued |
| I1 | `launcher/ui/pages/instance`: `NotesPage`, `VersionPage`, `InstanceSettingsPage`, `GameOptionsPage`, `ExternalResourcesPage`, `ModFolderPage`, `DataPackPage`, `ResourcePackPage`, `TexturePackPage`, `ShaderPackPage`, `ManagedPackPage`, `WorldListPage`, `ServersPage`, `ScreenshotsPage`, `LogPage`, `OtherLogsPage`, plus `McClient`, `McResolver`, and `ServerPingTask` | Native instance detail sections using `Form`, `Table`/`List`, `.searchable`, `TextEditor`/TextKit, system file panels, confirmation dialogs, and navigation | `BaseInstance`, `MinecraftInstance`, `PackProfile`, `minecraft/mod`, `minecraft/WorldList` and tasks, `settings`, `launch`, `logs`, screenshot services, and server metadata | Facade fixture mutations, permission/missing-file/conflict/invalid-archive cases, rollback, cancellation, external-change handling, log bounds, and accessibility | M5/M6, queued |
| P0 | `launcher/ui/pages/modplatform` shared layer: `CustomPage`, `ImportPage`, `ResourcePage`, `ModPage`, `DataPackPage`, `ResourcePackPage`, `ShaderPackPage`, `TexturePackPage`, `ModpackProviderBasePage`, resource models, and `OptionalModDialog` | Shared native provider browser and installation navigation with standard lists/tables, search/filter controls, system open panels, progress, and confirmation | `modplatform/{ModIndex,ResourceAPI,ResourceType}`, `meta`, `ResourceDownloadTask`, `InstanceTask`, archive/file services, and provider adapters | Fixture provider responses, search/filter/pagination, version selection, optional/blocked files, network/disk errors, cancellation, rollback, and localization | M8, queued |
| P1 | `launcher/ui/pages/modplatform/atlauncher`: `AtlPage`, `AtlListModel`, `AtlFilterModel`, `AtlOptionalModDialog`, and `AtlUserInteractionSupportImpl` | ATLauncher provider destination in the shared browser; optional files use native confirmation/selection | `modplatform/atlauncher/{ATLPackIndex,ATLPackInstallTask,ATLPackManifest,ATLShareCode}` | Fixture adapter, pagination/search/filter, optional files, install success/failure/cancellation/rollback, and no live network mutation | M8, queued |
| P2 | `launcher/ui/pages/modplatform/flame`: `FlamePage`, `FlameModel`, `FlameResourceModels`, and `FlameResourcePages` | CurseForge/Flame provider destination and resource subflows in shared native navigation | `modplatform/flame/{FlameAPI,FlameModIndex,FlameInstanceCreationTask,FlamePackExportTask,FlameCheckUpdate,FileResolvingTask}` | Fixture API and archive tests, selected version/resource state, blocked files, disk/network failures, cancellation, rollback, export contracts | M8, queued |
| P3 | `launcher/ui/pages/modplatform/ftb`: `FtbPage`, `FtbListModel`, and `FtbFilterModel` | FTB provider browser and install flow in shared native navigation | `modplatform/ftb/{FTBPackInstallTask,FTBPackManifest}` and `meta` | Fixture listing/install tests, filter/search/version selection, failure/cancellation/rollback, accessibility and long localized strings | M8, queued |
| P4 | `launcher/ui/pages/modplatform/import_ftb`: `ImportFTBPage` and `ListModel` | FTB local import flow using `fileImporter` and an import progress/error state | `modplatform/import_ftb` and `InstanceImportTask`; explicit temporary-root contract | Temporary directory fixture, invalid/missing manifest, permission failure, cancellation, rollback, and selected-pack state | M8, queued |
| P5 | `launcher/ui/pages/modplatform/legacy_ftb`: `Page` and `ListModel` | Legacy FTB provider/import destination, retained only as a capability row until adapter parity is proven | `modplatform/legacy_ftb` and existing import/install tasks | Fixture compatibility matrix, empty/error/blocked states, cancellation, and explicit unsupported-version recovery | M8, queued |
| P6 | `launcher/ui/pages/modplatform/modrinth`: `ModrinthPage`, `ModrinthModel`, and `ModrinthResourcePages` | Modrinth provider browser and resource pages in shared native navigation | `modplatform/modrinth/{ModrinthAPI,ModrinthPackIndex,ModrinthInstanceCreationTask,ModrinthPackExportTask,ModrinthCheckUpdate}` | Fixture API responses, debounce/search/filter, pagination, version selection, install/export/update, cancellation, rollback, and localization | M8, queued |
| P7 | `launcher/ui/pages/modplatform/technic`: `TechnicPage`, `TechnicModel`, and `TechnicData` | Technic provider browser and install flow in shared native navigation | `modplatform/technic` plus `meta` and existing install tasks | Fixture listing/install tests, selection/filtering, missing metadata, network/disk errors, cancellation, and rollback | M8, queued |
| W1 | `launcher/ui/setupwizard`: `SetupWizard`, `BaseWizardPage`, `AutoJavaWizardPage`, `JavaWizardPage`, `LanguageWizardPage`, `LoginWizardPage`, `PasteWizardPage`, and `ThemeWizardPage` | Native first-run onboarding using navigation and standard forms; settings remain reachable through the system Settings scene | `settings`, `java`, `minecraft/auth`, language services, and theme preferences | Step transitions, validation, cancellation/retry, fake authentication, Java discovery, localization, keyboard focus, and restart semantics | M7, queued |
| T1 | `launcher/ui/themes`: `ITheme`, `BrightTheme`, `DarkTheme`, `CustomTheme`, `FusionTheme`, `SystemTheme`, `ThemeManager`, `IconTheme`, `CatPack`, `CatPainter`, and `HintOverrideProxyStyle` | Appearance settings using system appearance/color-scheme behavior; icons and artwork are content resources, not custom window chrome | `settings`, resource/theme files, and domain artwork; Qt palette/style helpers remain shared only until native parity | Settings round trip, system appearance selection, resource fallback, accessibility contrast review, static custom-control scan, and no custom title-bar drawing | M7/M9, queued |
| U1 | `launcher/ui/widgets`: `AppearanceWidget`, `CheckComboBox`, `Common`, `CustomCommands`, `EnvironmentVariables`, `IconLabel`, `InfoFrame`, `JavaSettingsWidget`, `JavaWizardWidget`, `LabeledToolButton`, `LanguageSelectionWidget`, `LogView`, `MinecraftSettingsWidget`, `ModFilterWidget`, `ModListView`, `PageContainer`, `PageContainer_p`, `ProgressWidget`, `ProjectDescriptionPage`, `ProjectItem`, `SubTaskProgressBar`, `VariableSizedImageObject`, `VersionListView`, `VersionSelectWidget`, and `WideBar` | Replace with standard SwiftUI/AppKit controls, `Form`, `Table`/`List`, `ProgressView`, `TextEditor`, `Link`, SF Symbols, and system focus/selection behavior; no one-for-one widget port | Underlying owners from G1/I1/P0/P1-P7/J1; helper classes never become public facade types | Static API scan, view-model/command tests, accessibility metadata, localization, progress/cancellation, large-list bounds, and no self-drawn system control | M4-M9 by consuming feature, queued |

Classification decisions:

- All enumerated dialogs are assigned to a system presentation, a standard file panel, a settings pane, or a dedicated native feature. No dialog is marked retained or complete; the migration units will record any genuine blocker before implementation.
- All enumerated pages are assigned to native navigation, settings, instance detail, onboarding, or provider discovery. Qt page/model classes are implementation evidence only and are not allowed to cross the future facade boundary.
- `SkinOpenGLWindow`, `Scene`, and `BoxGeometry` are the only currently identified custom-rendering candidate. No exception is approved; M9 must record the required user need, Apple APIs investigated, accessibility representation, memory/performance limits, and non-screenshot tests before implementation.
- The scan found no additional source directory under `launcher/ui` outside the rows above. Provider-specific model/support files are included in their provider row rather than treated as unclassified UI.

## Inventory verification record

M1-W2 is a documentation-only unit. It does not claim native behavior or backend extraction. The source scan was performed without opening the installed upstream application or reading any Application Support data. The next unit adds automated bridge-header and fixture infrastructure so the manually recorded boundary classifications become executable checks.

## Work units

### M1-W1: Shared scheme and native safety contract tests

Status: complete

Outcome: add a stable shared `PrismNative` scheme and a `PrismNativeTests` target covering Bundle ID and data-root isolation without launching the app.

Files changed: `macos/PrismNative.xcodeproj/project.pbxproj`, `macos/PrismNative.xcodeproj/xcshareddata/xcschemes/PrismNative.xcscheme`, `macos/PrismNativeTests/PrismNativeIdentityTests.swift`, `macos/PrismNative/Bridge/PrismBridge.h`, `macos/PrismNative/Bridge/PrismBridge.mm`, and this progress file.

Tests and exact commands:

- `git diff --check` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; 2 tests, 0 failures.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `plutil -extract CFBundleIdentifier raw .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.

Result summary: the shared scheme builds the app and its standalone XCTest bundle. Tests inspect the built app Info.plist without launching it, inject a temporary fixture root into the Foundation-only identity bridge, assert the native `Prism` root, and assert explicit non-equality with the upstream `PrismLauncher` namespace. No upstream application, Application Support data, account, Keychain, or production data was accessed.

HIG decision: none, this unit protects product identity and test infrastructure.

Risk: the test resolves `Prism.app` as a sibling of the XCTest bundle, so the shared scheme must continue to build the application target before running identity tests. Runtime backend isolation remains a later facade responsibility.

Commit: `3308191dd`

Next after completion: `M1-W2`, inventory every legacy UI family and map it to facade capabilities and native destination.

### M1-W2: Complete legacy feature inventory

Status: complete

Outcome: expand this ledger so every source family under `launcher/ui` has a native destination, backend owner, verification class, and migration milestone.

Files changed: `docs/macos-native-migration/PROGRESS.md`.

Tests and exact commands:

- `rg --files launcher/ui | sort` — completed; 366 files inventoried.
- `rg --files launcher/ui -g '*.ui' | sort` — completed; 62 forms inventoried.
- `find launcher/ui -type d -print | sort` — completed; every source directory mapped in the family table.
- `rg -n '^class [A-Za-z0-9_]+|^struct [A-Za-z0-9_]+' launcher/ui --glob '*.h'` — completed; UI, model, accessibility, and task collaborators traced into the table.
- `git diff --check` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; 2 tests, 0 failures.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `plutil -extract CFBundleIdentifier raw .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.

Result summary: every current UI directory, dialog family, page family, provider adapter, helper/model family, and custom-rendering candidate has a native destination, backend owner, verification class, and milestone. The ledger contains no unclassified dialog or page.

HIG decision: classify system controls and presentations by need before implementation: `NavigationSplitView`/`List`/`Table` for hierarchy and collections, `Form`/`Settings` for configuration, standard file panels for import/export, `ProgressView` for tasks, and alerts/confirmation dialogs for errors and destructive actions. No custom system control is approved.

Risk: the inventory is a snapshot of the current source tree; future additions under `launcher/ui` could escape a manually maintained ledger. M1-W3 should add a negative/positive source scan and bridge fixture helpers, and every later unit must update this section when tracing a new collaborator.

Commit: pending; record the exact hash in the next ledger update after commit creation.

Next after completion: `M1-W3`, automate the public bridge-header scan and temporary-root, callback, cancellation, and fixture helpers.

### M1-W3: Bridge boundary and fixture infrastructure

Status: ready

Outcome: automate the public bridge-header scan and provide temporary-root, callback, cancellation, and fixture helpers for later milestones.

Required evidence: native tests pass, forbidden-type scan has a negative test, fixture root cannot resolve to the upstream Application Support path.

Commit: not created.

## Completed commit index

| Commit | Outcome | Verification |
| --- | --- | --- |
| `6de92da18` | Isolated macOS fork identity and ignored local dependencies | CMake configuration and Qt baseline build; generated Info.plist Bundle ID check |
| `5172b3a75` | Added SwiftUI Xcode target and Objective-C++ bridge scaffold | arm64 Debug build; generated Info.plist Bundle ID check; architecture review |
| `3308191dd` | Added shared native scheme and Bundle ID/data-root contract tests | Debug and Release builds; 2 native tests; Debug/Release `plutil`; `git diff --check` |

## Current architecture findings

1. Prism currently builds `Launcher_logic` as a monolithic static library containing both domain and Qt UI sources.
2. `Application` derives from `QApplication` and exposes global application state.
3. `InstanceList` and `AccountList` derive from Qt list models.
4. `LaunchController` derives from the existing task system.
5. The native Xcode target does not yet link a backend library.
6. The first backend task is separation and characterization, not Swift reimplementation.

## Custom rendering exceptions

No exception is approved.

Minecraft skin preview is a candidate only. It requires the complete exception record from `PLAN.md` before implementation.

## Blockers

No current blocker.

## Resume instructions

Read `PLAN.md`, run `git status --short --branch -uall`, inspect the last five commits, then continue only with ready `M1-W3`. Do not begin backend extraction or visual design until the bridge boundary and fixture infrastructure are committed.

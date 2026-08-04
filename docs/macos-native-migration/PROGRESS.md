# Prism macOS Native Migration Progress

Last updated: 2026-08-04

Branch: `macos-native`

Plan: `docs/macos-native-migration/PLAN.md`

Current milestone: Milestone 2, QWidget-free backend facade

Active work unit: none (M2-W6 complete; activate M2-W7 at next round start)

Next ready work unit: M2-W7

## Safety baseline

| Contract | Status | Evidence |
| --- | --- | --- |
| Bundle ID is `com.lloydME.Prism` | complete | Commit `6de92da18`; built Info.plist checked with `plutil` |
| Native product name is `Prism` | complete | Commit `6de92da18`; built Info.plist checked with `plutil` |
| Default data identity differs from upstream `PrismLauncher` | complete | `Prism` application identity in `program_info/CMakeLists.txt` and native bridge; M1-W1 temporary-root contract test |
| Native Xcode target exists | complete | Commit `5172b3a75` |
| Objective-C++ public bridge exposes only Foundation types | complete | Commit `5172b3a75`; M1-W3 automated public-header scan and forbidden-token negative test |
| Native tests target exists | complete | M1-W1; shared scheme and standalone `PrismNativeTests.xctest` target |
| Upstream application and data are untouched | complete for current work | No application launch or installation was performed |

## Milestone status

| Milestone | Status | Completion requirement |
| --- | --- | --- |
| 1. Contracts, tests, and inventory | complete | Native contract tests, complete feature ledger, and automated bridge/fixture infrastructure |
| 2. QWidget-free backend facade | active | Facade lists fixture instances without UI headers |
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

Commit: `2158ad5db`

Next after completion: `M1-W3`, automate the public bridge-header scan and temporary-root, callback, cancellation, and fixture helpers.

### M1-W3: Bridge boundary and fixture infrastructure

Status: complete

Outcome: automate the public bridge-header scan and provide temporary-root, callback, cancellation, and fixture helpers for later milestones. The test target now enumerates only public `.h` files under the bridge directory, rejects Qt/C++ boundary tokens with a synthetic negative test, and supplies isolated temporary fixtures without reading upstream Application Support data.

Files changed: `macos/PrismNative.xcodeproj/project.pbxproj`, `macos/PrismNativeTests/PrismNativeIdentityTests.swift`, `macos/PrismNativeTests/PrismNativeInfrastructureTests.swift`, `macos/PrismNativeTests/PrismNativeTestSupport.swift`, and this progress file.

Tests and exact commands:

- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; 6 tests, 0 failures.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `git diff --check` — passed.

Result summary: the public-header scan passed for `PrismBridge.h`; the synthetic forbidden-type fixture detected both `QWidget` and `std::`; the fixture helper created and read a JSON file under a unique temporary root while proving it is outside the upstream `PrismLauncher` Application Support namespace; and the callback recorder delivered only the pre-cancellation value. No application launch, screenshot, upstream data access, account, Keychain, or production-data access occurred.

HIG decision: none, this unit adds only non-UI test infrastructure. The public bridge remains Foundation-only and no system control or custom rendering was introduced.

Risk: the scanner uses a maintained forbidden-token list and resolves the bridge directory from the test source path; later facade headers must remain under that directory or extend the scanner contract. Fixture cleanup is limited to each helper's unique temporary root, and the upstream path is constructed for comparison rather than read.

Commit: `5a9e80e3e`

Next after completion: `M2-W1`, split `launcher/CMakeLists.txt` source classification into domain, UI, and executable composition without changing Qt runtime behavior.

### M2-W1: Split backend source classification without behavior change

Status: complete

Outcome: split the launcher CMake source classification into explicit domain, UI, application-composition, and executable-entry buckets while preserving the existing Qt target's runtime source composition and link behavior. Java UI sources no longer sit in the domain candidate list; the existing `Launcher_logic` target still combines all runtime sources so no backend extraction or Qt behavior change occurs in this unit.

Files changed: `launcher/CMakeLists.txt` and this progress file.

Implementation evidence: `LAUNCHER_DOMAIN_SOURCES` replaces the ambiguous `LOGIC_SOURCES`; `JAVA_UI_SOURCES` is kept separate; the legacy application/UI list is partitioned into `LAUNCHER_APPLICATION_SOURCES` and `LAUNCHER_UI_SOURCES`; `LAUNCHER_EXECUTABLE_SOURCES` owns `main.cpp` and platform resource entry files; and `LAUNCHER_RUNTIME_SOURCES` preserves the current `Launcher_logic` composition. Configure-time checks fail if the legacy partition drops an entry or if the final runtime source list contains duplicates.

Tests and exact commands:

- Successful isolated CMake configuration used the repository's existing package directories without manifest installation, network access, or Sparkle download:

  ```sh
  env PKG_CONFIG_PATH="/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libarchive_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/bzip2_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/liblzma_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/lzo_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/lz4_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zstd_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/tomlplusplus_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libqrencode_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zlib_arm64-osx/lib/pkgconfig:/opt/homebrew/lib/pkgconfig" \
    cmake -S . -B /private/tmp/prism-m2-cmake-pkgconfig -G Ninja -DCMAKE_PREFIX_PATH="/opt/homebrew/opt/qt;/opt/homebrew/opt/cmark;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/ecm_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/cmark_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libarchive_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/tomlplusplus_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zlib_arm64-osx" -DVCPKG_MANIFEST_MODE=OFF -DCMAKE_DISABLE_FIND_PACKAGE_LibArchive=TRUE -DBUILD_TESTING=ON -DLauncher_USE_PCH=OFF -DLauncher_ENABLE_JAVA_DOWNLOADER=OFF -DMACOSX_SPARKLE_UPDATE_PUBLIC_KEY="" -DMACOSX_SPARKLE_UPDATE_FEED_URL=""
  ```
- `cmake --build /private/tmp/prism-m2-cmake-pkgconfig --target Launcher_logic FileSystem Task JavaVersion Version --parallel 2` — passed; full 448-step target/test build and all requested links succeeded.
- `ctest --test-dir /private/tmp/prism-m2-cmake-pkgconfig --output-on-failure -R '^(FileSystem|Task|JavaVersion|Version)$'` — passed; 4/4 tests.
- `cmake --build /private/tmp/prism-m2-cmake-pkgconfig --target Prism --parallel 2` — passed; existing Qt `prismlauncher.app` target linked without being executed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; 6 native tests, 0 failures.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `git diff --check` — passed.

Result summary: CMake configure-time source ownership and duplicate checks passed; the existing Qt logic library and executable linked; the four selected C++ tests passed; native tests and both native configurations passed; and no application, Qt launcher, screenshot, or visual snapshot was launched or captured. No upstream application, Application Support data, account, Keychain, production API, signing, installation, or publishing state was accessed.

HIG decision: none, this unit changes only backend build classification. No SwiftUI/AppKit control, custom drawing, or UI behavior was added.

Risk: the UI/application partition uses an explicit path/name classification rule over the legacy list; a newly added non-`ui/` presentation helper must update that rule. `Launcher_logic` intentionally remains a combined Qt target until M2-W2 introduces the facade, so the domain bucket is a source-ownership contract rather than proof that every domain implementation is already QWidget-free.

Non-blocking limits: the default CMake path could not resolve Homebrew `libarchive`, the vcpkg manifest path attempted registry/cache access, and the default macOS configure attempted to download Sparkle. Verification therefore used the already-present repository package artifacts, pkg-config transitive dependencies, `CMAKE_DISABLE_FIND_PACKAGE_LibArchive=TRUE`, and empty temporary Sparkle key/feed cache values. The existing AutoUIC layout-name warning and missing `clang-format` warning remain unchanged.

Commit: `19b45a465`

Next after completion: `M2-W2`, introduce the frontend facade target or library under `launcher/frontend`.

### M2-W2: Introduce the frontend facade target

Status: complete

Outcome: introduce the first `launcher/frontend` target or library as the QWidget-free backend facade boundary, without changing the existing Qt executable's link or runtime behavior.

Files changed: `launcher/frontend/CMakeLists.txt`, `launcher/frontend/FrontendFacade.h`, `launcher/frontend/FrontendFacade.cpp`, `launcher/frontend/FrontendFacadeContractTest.cpp`, `launcher/CMakeLists.txt`, and this progress file.

Design: add an independent static `Launcher_frontend` target with no Qt or `launcher/ui` link dependency. Its initial public contract is an inert, non-copyable and non-movable facade root; explicit data-root and runtime-dependency construction remains the next work unit. The contract test creates a uniquely named temporary fixture, writes only a local marker, constructs and destroys the facade, and verifies that the fixture remains unchanged.

Tests and exact commands:

- `git diff --check` — passed.
- `env PKG_CONFIG_PATH="/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libarchive_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/bzip2_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/liblzma_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/lzo_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/lz4_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zstd_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/tomlplusplus_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libqrencode_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zlib_arm64-osx/lib/pkgconfig:/opt/homebrew/lib/pkgconfig" cmake -S . -B /private/tmp/prism-m2-cmake-pkgconfig -G Ninja -DCMAKE_PREFIX_PATH="/opt/homebrew/opt/qt;/opt/homebrew/opt/cmark;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/ecm_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/cmark_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libarchive_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/tomlplusplus_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zlib_arm64-osx" -DVCPKG_MANIFEST_MODE=OFF -DCMAKE_DISABLE_FIND_PACKAGE_LibArchive=TRUE -DBUILD_TESTING=ON -DLauncher_USE_PCH=OFF -DLauncher_ENABLE_JAVA_DOWNLOADER=OFF -DMACOSX_SPARKLE_UPDATE_PUBLIC_KEY="" -DMACOSX_SPARKLE_UPDATE_FEED_URL=""` — passed; existing clang-format and AutoUIC warnings remain non-blocking.
- `cmake --build /private/tmp/prism-m2-cmake-pkgconfig --target Launcher_frontend Launcher_frontend_contract_test --parallel 2` — passed; independent facade library and contract executable linked.
- `ctest --test-dir /private/tmp/prism-m2-cmake-pkgconfig --output-on-failure -R '^FrontendFacadeContract$'` — passed; 1/1.
- `cmake --build /private/tmp/prism-m2-cmake-pkgconfig --target Prism --parallel 2` — passed; existing Qt launcher target linked without a frontend dependency.
- `ctest --test-dir /private/tmp/prism-m2-cmake-pkgconfig --output-on-failure -R '^(FrontendFacadeContract|FileSystem|Task|JavaVersion|Version)$'` — passed; 5/5.
- `rg -n "launcher/ui|QWidget|QDialog|QtWidgets|QAbstractItemModel|QAbstractListModel|QObject|QModelIndex" launcher/frontend --glob '*.h'` — passed with no public-header matches.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; 6 tests, 0 failures.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `git diff --check` — passed after verification.

Result summary: the new facade and fixture test configure and build without UI headers, the facade target has no Qt or launcher-core link dependency, and the existing Qt `Prism` target remains buildable and linked. The native target remains independent; both native configurations and all 6 standalone native tests pass. No application or launcher executable was launched, and no upstream application, Application Support data, account, Keychain, production API, signing, installation, or publishing state was accessed.

HIG decision: this is a backend-only boundary unit, so it adds no SwiftUI/AppKit control or custom drawing. Future native surfaces remain governed by the system-component policy in `PLAN.md`.

Risk: the facade is intentionally inert until M2-W3 adds explicit data-root and runtime-dependency construction; instance snapshots, events, and lifecycle semantics are not claimed by this unit. The existing AutoUIC duplicate-layout-name warning and missing `clang-format` warning remain unchanged.

Commit: `e87f35fc0`

Next after completion: `M2-W3`, make the facade accept an explicit data root and runtime dependencies.

### M2-W3: Explicit data root and runtime dependencies

Status: complete

Outcome: make the frontend facade require an explicit absolute data root and injected runtime dependencies without creating directories, reading global `Application` state, or performing network work.

Files changed: `launcher/frontend/FrontendFacade.h`, `launcher/frontend/FrontendFacade.cpp`, `launcher/frontend/FrontendFacadeContractTest.cpp`, and this progress file.

Design: use `std::filesystem::path` for an explicit absolute root and normalize it lexically without touching the filesystem. Require injected dispatch and clock ports through `FrontendRuntimeDependencies`; reject incomplete dependencies before any backend work. The facade remains UI-free and does not discover `Application`, process arguments, environment variables, or system application paths.

Tests and exact commands:

- `git diff --check` — passed.
- `env PKG_CONFIG_PATH="/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libarchive_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/bzip2_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/liblzma_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/lzo_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/lz4_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zstd_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/tomlplusplus_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libqrencode_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zlib_arm64-osx/lib/pkgconfig:/opt/homebrew/lib/pkgconfig" cmake -S . -B /private/tmp/prism-m2-cmake-pkgconfig -G Ninja -DCMAKE_PREFIX_PATH="/opt/homebrew/opt/qt;/opt/homebrew/opt/cmark;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/ecm_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/cmark_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libarchive_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/tomlplusplus_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zlib_arm64-osx" -DVCPKG_MANIFEST_MODE=OFF -DCMAKE_DISABLE_FIND_PACKAGE_LibArchive=TRUE -DBUILD_TESTING=ON -DLauncher_USE_PCH=OFF -DLauncher_ENABLE_JAVA_DOWNLOADER=OFF -DMACOSX_SPARKLE_UPDATE_PUBLIC_KEY="" -DMACOSX_SPARKLE_UPDATE_FEED_URL=""` — passed; existing clang-format and AutoUIC warnings remain non-blocking.
- `cmake --build /private/tmp/prism-m2-cmake-pkgconfig --target Launcher_frontend Launcher_frontend_contract_test --parallel 2` — passed.
- `ctest --test-dir /private/tmp/prism-m2-cmake-pkgconfig --output-on-failure -R '^FrontendFacadeContract$'` — passed; 1/1 after the lexical path-normalization fix. The initial run returned exit code 3; direct diagnostic showed the actual root retained a trailing separator while dependencies were complete, so the fix was based on new evidence rather than a blind retry.
- `cmake --build /private/tmp/prism-m2-cmake-pkgconfig --target Prism --parallel 2` — passed; existing Qt launcher target linked without a frontend dependency.
- `ctest --test-dir /private/tmp/prism-m2-cmake-pkgconfig --output-on-failure -R '^(FrontendFacadeContract|FileSystem|Task|JavaVersion|Version)$'` — passed; 5/5.
- `rg -n "launcher/ui|QWidget|QDialog|QtWidgets|QAbstractItemModel|QAbstractListModel|QObject|QModelIndex" launcher/frontend --glob '*.h'` — passed with no public-header matches.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; 6 tests, 0 failures.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `git diff --check` — passed after verification.

Result summary: the facade now receives an explicit fixture root and deterministic runtime ports while construction remains side-effect free. Empty, relative, and incomplete-dependency inputs are rejected; the fixture marker remains intact. Existing Qt behavior and the native target remain independent. No application or launcher executable was launched, and no upstream application, Application Support data, account, Keychain, production API, signing, installation, or publishing state was accessed.

HIG decision: this is a backend construction unit, so it adds no SwiftUI/AppKit control or custom drawing. Future native surfaces remain governed by the system-component policy in `PLAN.md`.

Risk: root validation is absolute and lexical, not a symlink-resolving containment policy; later mutation units must assert every write is inside the injected fixture root. The dispatch and clock ports are seams only; backend service initialization and instance behavior remain future work. Existing AutoUIC and missing `clang-format` warnings remain unchanged.

Commit: `6d1b08f3b`

Next after completion: `M2-W4`, add instance snapshot and instance-change event contracts.

### M2-W4: Instance snapshots and change events

Status: complete

Outcome: add immutable instance summary snapshots and stable instance-change event contracts to the QWidget-free facade.

Files changed: `launcher/frontend/FrontendFacade.h`, `launcher/frontend/FrontendFacade.cpp`, `launcher/frontend/FrontendFacadeContractTest.cpp`, and this progress file.

Design: define standard C++ value snapshots with stable string identifiers, optional display/group metadata, and an explicit Added/Updated/Removed event kind. Injected loaders receive the normalized data root and return copies; the facade validates non-empty unique snapshot IDs and known event kinds without exposing Qt rows, roles, model pointers, or UI types. Missing loaders produce a deterministic empty result; observation and shutdown remain later contracts.

Tests and exact commands:

- `git diff --check` — passed.
- `env PKG_CONFIG_PATH="/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libarchive_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/bzip2_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/liblzma_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/lzo_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/lz4_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zstd_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/tomlplusplus_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libqrencode_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zlib_arm64-osx/lib/pkgconfig:/opt/homebrew/lib/pkgconfig" cmake -S . -B /private/tmp/prism-m2-cmake-pkgconfig -G Ninja -DCMAKE_PREFIX_PATH="/opt/homebrew/opt/qt;/opt/homebrew/opt/cmark;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/ecm_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/cmark_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libarchive_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/tomlplusplus_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zlib_arm64-osx" -DVCPKG_MANIFEST_MODE=OFF -DCMAKE_DISABLE_FIND_PACKAGE_LibArchive=TRUE -DBUILD_TESTING=ON -DLauncher_USE_PCH=OFF -DLauncher_ENABLE_JAVA_DOWNLOADER=OFF -DMACOSX_SPARKLE_UPDATE_PUBLIC_KEY="" -DMACOSX_SPARKLE_UPDATE_FEED_URL=""` — passed; existing clang-format and AutoUIC warnings remain non-blocking.
- `cmake --build /private/tmp/prism-m2-cmake-pkgconfig --target Launcher_frontend Launcher_frontend_contract_test --parallel 2` — passed.
- `ctest --test-dir /private/tmp/prism-m2-cmake-pkgconfig --output-on-failure -R '^FrontendFacadeContract$'` — passed; 1/1 covering empty, fixture, validation, and event contracts.
- `cmake --build /private/tmp/prism-m2-cmake-pkgconfig --target Prism --parallel 2` — passed; existing Qt launcher target linked without a frontend dependency.
- `ctest --test-dir /private/tmp/prism-m2-cmake-pkgconfig --output-on-failure -R '^(FrontendFacadeContract|FileSystem|Task|JavaVersion|Version)$'` — passed; 5/5.
- `rg -n "launcher/ui|QWidget|QDialog|QtWidgets|QAbstractItemModel|QAbstractListModel|QObject|QModelIndex" launcher/frontend --glob '*.h'` — passed with no public-header matches.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; 6 tests, 0 failures.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `git diff --check` — passed after verification.

Result summary: empty and fixture-backed snapshots are returned through temporary-root loaders, the loader receives the normalized fixture root, stable IDs and metadata survive the value boundary, and Added/Updated/Removed events are validated in order. Invalid empty IDs and unknown event kinds are rejected. The target remains independent from `InstanceList` and Qt Widgets. No application or launcher executable was launched, and no upstream application, Application Support data, account, Keychain, production API, signing, installation, or publishing state was accessed.

HIG decision: this is a backend value-contract unit, so it adds no SwiftUI/AppKit control or custom drawing. Native collection behavior remains a later consumer decision under the system `List`/`Table` policy in `PLAN.md`.

Risk: the loader callbacks are fixture/adaptor seams and do not yet connect to the legacy `InstanceList`; event observation, cancellation, lifecycle, and shutdown are intentionally deferred. Existing AutoUIC and missing `clang-format` warnings remain unchanged.

Commit: `d19b2144f`

Next after completion: `M2-W5`, add lifecycle and shutdown tests around the facade.

### M2-W5: Lifecycle and shutdown tests

Status: complete

Outcome: add deterministic facade lifecycle and shutdown contracts, including rejection of new work and safe release of injected resources.

Scope: `launcher/frontend` and directly required fixture tests only. Do not add Swift, Objective-C++, native UI, launch process execution, or real backend credentials.

Required evidence: construction, running, shutdown, repeated shutdown, rejected post-shutdown work, callback cancellation/release, temporary-root containment, and existing Qt/native build independence.

HIG decision: none, this unit remains backend lifecycle infrastructure without controls or rendering.

Files changed: `launcher/frontend/FrontendFacade.h`, `launcher/frontend/FrontendFacade.cpp`, `launcher/frontend/FrontendFacadeContractTest.cpp`, and this progress file.

Design: define explicit `Running`, `ShuttingDown`, and `Stopped` states. The first shutdown is idempotently accepted, cancels pending work, invokes the release callback while the facade reports `ShuttingDown`, clears injected ports, and rejects later snapshot or event reads. Destruction performs the same safe shutdown path; no UI controls, custom drawing, process launch, or real credentials are involved.

Tests and exact commands:

- `git diff --check` — passed before and after implementation changes.
- `env PKG_CONFIG_PATH="/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libarchive_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/bzip2_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/liblzma_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/lzo_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/lz4_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zstd_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/tomlplusplus_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libqrencode_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zlib_arm64-osx/lib/pkgconfig:/opt/homebrew/lib/pkgconfig" cmake -S . -B /private/tmp/prism-m2-cmake-pkgconfig -G Ninja -DCMAKE_PREFIX_PATH="/opt/homebrew/opt/qt;/opt/homebrew/opt/cmark;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/ecm_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/cmark_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libarchive_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/tomlplusplus_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zlib_arm64-osx" -DVCPKG_MANIFEST_MODE=OFF -DCMAKE_DISABLE_FIND_PACKAGE_LibArchive=TRUE -DBUILD_TESTING=ON -DLauncher_USE_PCH=OFF -DLauncher_ENABLE_JAVA_DOWNLOADER=OFF -DMACOSX_SPARKLE_UPDATE_PUBLIC_KEY="" -DMACOSX_SPARKLE_UPDATE_FEED_URL=""` — passed; existing clang-format and AutoUIC warnings remain non-blocking.
- `cmake --build /private/tmp/prism-m2-cmake-pkgconfig --target Launcher_frontend Launcher_frontend_contract_test --parallel 2` — passed; lifecycle facade library and contract executable linked.
- `ctest --test-dir /private/tmp/prism-m2-cmake-pkgconfig --output-on-failure -R '^FrontendFacadeContract$'` — passed; 1/1 covering construction, running, shutdown, repeated shutdown, post-shutdown rejection, callback release, destructor shutdown, and fixture containment.
- `cmake --build /private/tmp/prism-m2-cmake-pkgconfig --target Prism --parallel 2` — passed; existing Qt launcher target linked without a frontend dependency.
- `ctest --test-dir /private/tmp/prism-m2-cmake-pkgconfig --output-on-failure -R '^(FrontendFacadeContract|FileSystem|Task|JavaVersion|Version)$'` — passed; 5/5.
- `rg -n "launcher/ui|QWidget|QDialog|QtWidgets|QAbstractItemModel|QAbstractListModel|QObject|QModelIndex" launcher/frontend --glob '*.h'` — passed with no public-header matches.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; 6 tests, 0 failures.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `git diff --check` — passed after verification.

Result summary: lifecycle callbacks are explicit runtime ports, run at most once, and are released after shutdown. Reads after stopping fail deterministically without invoking loaders; the temporary fixture marker remains protected. Existing Qt behavior and the native target remain independent. No application or launcher executable was launched, and no upstream application, Application Support data, account, Keychain, production API, signing, installation, or publishing state was accessed.

Risk: the lifecycle boundary is a synchronous callback contract and does not yet own real backend observers, task workers, or launch processes; those remain later facade units. Existing AutoUIC and missing `clang-format` warnings remain unchanged.

Commit: `4b466150b`

Next after completion: `M2-W6`, ensure all facade public headers compile without `launcher/ui`.

### M2-W6: Facade public-header compile boundary

Status: complete

Outcome: compile every `launcher/frontend` public header in a target that cannot include `launcher/ui` or depend on QWidget ownership.

Scope: `launcher/frontend` and directly related compile-test/CMake files only. Do not add native visual surfaces, Objective-C++, Swift, process launch, or real backend credentials.

Required evidence: standalone public-header compilation, no forbidden UI/model tokens, independent facade and existing Qt builds, native Debug/Release builds and tests, Bundle ID checks, and `git diff --check`.

HIG decision: none, this unit remains a compile-boundary check without controls or rendering.

Files changed: `launcher/frontend/CMakeLists.txt`, `launcher/frontend/FrontendFacadePublicHeaderTest.cpp`, and this progress file.

Design: maintain an explicit `LAUNCHER_FRONTEND_PUBLIC_HEADERS` list and compile the current public header in a standalone executable that does not link `Launcher_frontend`, `Launcher_logic`, Qt, or `launcher/ui`. The compile test instantiates only standard C++ facade value contracts and checks enum values at compile time; no native control or custom drawing is required.

Tests and exact commands:

- `git diff --check` — passed before and after implementation changes.
- `env PKG_CONFIG_PATH="/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libarchive_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/bzip2_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/liblzma_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/lzo_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/lz4_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zstd_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/tomlplusplus_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libqrencode_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zlib_arm64-osx/lib/pkgconfig:/opt/homebrew/lib/pkgconfig" cmake -S . -B /private/tmp/prism-m2-cmake-pkgconfig -G Ninja -DCMAKE_PREFIX_PATH="/opt/homebrew/opt/qt;/opt/homebrew/opt/cmark;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/ecm_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/cmark_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libarchive_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/tomlplusplus_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zlib_arm64-osx" -DVCPKG_MANIFEST_MODE=OFF -DCMAKE_DISABLE_FIND_PACKAGE_LibArchive=TRUE -DBUILD_TESTING=ON -DLauncher_USE_PCH=OFF -DLauncher_ENABLE_JAVA_DOWNLOADER=OFF -DMACOSX_SPARKLE_UPDATE_PUBLIC_KEY="" -DMACOSX_SPARKLE_UPDATE_FEED_URL=""` — passed; existing clang-format and AutoUIC warnings remain non-blocking.
- `cmake --build /private/tmp/prism-m2-cmake-pkgconfig --target Launcher_frontend Launcher_frontend_contract_test Launcher_frontend_public_header_test --parallel 2` — passed; facade, existing contract, and standalone header targets linked.
- `ctest --test-dir /private/tmp/prism-m2-cmake-pkgconfig --output-on-failure -R '^(FrontendFacadeContract|FrontendFacadePublicHeaders)$'` — passed; 2/2.
- `cmake --build /private/tmp/prism-m2-cmake-pkgconfig --target Prism --parallel 2` — passed; existing Qt launcher target linked independently.
- `ctest --test-dir /private/tmp/prism-m2-cmake-pkgconfig --output-on-failure -R '^(FrontendFacadeContract|FrontendFacadePublicHeaders|FileSystem|Task|JavaVersion|Version)$'` — passed; 6/6.
- `rg --files launcher/frontend -g '*.h' | sort` — completed; the current public-header list contains `FrontendFacade.h` only.
- `rg -n "launcher/ui|QWidget|QDialog|QtWidgets|QAbstractItemModel|QAbstractListModel|QObject|QModelIndex" launcher/frontend --glob '*.h'` — passed with no public-header matches.
- `rg -n "target_link_libraries\\(Launcher_frontend|target_link_libraries\\(Launcher_frontend_public_header_test|LAUNCHER_FRONTEND_PUBLIC_HEADERS" launcher/frontend/CMakeLists.txt` — passed; the standalone header test has no link dependency and the facade target has no Qt/UI link.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; 6 tests, 0 failures.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `git diff --check` — passed after verification.

Result summary: the current facade public header compiles and runs through an isolated no-link target, the facade contract remains buildable, and no forbidden Qt/UI token appears in public headers. The existing Qt target and native target remain independent. No application or launcher executable was launched, and no upstream application, Application Support data, account, Keychain, production API, signing, installation, or publishing state was accessed.

Risk: the public-header list is explicit and must be updated with any future public facade header; the standalone test proves the current header boundary but does not claim that backend adapters are already QWidget-free. Existing AutoUIC and missing `clang-format` warnings remain unchanged.

Commit: `78d8354be`

Next after completion: `M2-W7`, preserve the existing Qt executable link and behavior while keeping the facade target independent.

### M2-W7: Preserve existing Qt executable composition

Status: ready

Outcome: add a direct build/link contract proving the existing Qt `Prism` executable remains linked through `Launcher_logic` and behaviorally independent from `Launcher_frontend`.

Scope: `launcher/CMakeLists.txt`, directly related build/test assertions, and this progress file only. Do not launch the Qt executable, add native visual surfaces, alter backend behavior, or access real data.

Required evidence: explicit target/link-graph inspection, isolated Qt `Prism` build, selected C++ tests, independent facade build/tests, native Debug/Release builds and tests, Bundle ID checks, and `git diff --check`.

HIG decision: none, this unit preserves legacy backend composition without controls or rendering.

Commit: not created.

Next after completion: Milestone 3 M3-W1, replace the identity-only bridge composition with a lifecycle-owning bridge root.

## Completed commit index

| Commit | Outcome | Verification |
| --- | --- | --- |
| `6de92da18` | Isolated macOS fork identity and ignored local dependencies | CMake configuration and Qt baseline build; generated Info.plist Bundle ID check |
| `5172b3a75` | Added SwiftUI Xcode target and Objective-C++ bridge scaffold | arm64 Debug build; generated Info.plist Bundle ID check; architecture review |
| `3308191dd` | Added shared native scheme and Bundle ID/data-root contract tests | Debug and Release builds; 2 native tests; Debug/Release `plutil`; `git diff --check` |
| `2158ad5db` | Completed the legacy UI feature inventory and native destination ledger | Source-directory, Qt-form, class-ownership, Debug/Release build, native-test, `plutil`, and `git diff --check` verification |
| `5a9e80e3e` | Enforced public bridge and isolated fixture contracts | Debug and Release builds; 6 native tests; Debug/Release `plutil`; `git diff --check` |
| `19b45a465` | Classified launcher source ownership without changing Qt composition | Isolated CMake configure/build; Launcher_logic and selected C++ tests; existing Prism target link; native Debug/Release builds; 6 native tests; Debug/Release `plutil`; `git diff --check` |
| `e87f35fc0` | Added the independent QWidget-free frontend facade target and fixture contract | Facade target and contract test; existing Prism target; selected C++ tests 5/5; native Debug/Release builds; 6 native tests; Debug/Release `plutil`; public-header scan; `git diff --check` |
| `6d1b08f3b` | Required explicit data-root and runtime dependency inputs for the facade | Facade fixture contract; selected C++ tests 5/5; existing Prism target; native Debug/Release builds; 6 native tests; Debug/Release `plutil`; public-header scan; `git diff --check` |
| `d19b2144f` | Added immutable instance snapshots and Added/Updated/Removed change contracts | Empty and fixture facade contracts; selected C++ tests 5/5; existing Prism target; native Debug/Release builds; 6 native tests; Debug/Release `plutil`; public-header scan; `git diff --check` |
| `4b466150b` | Added explicit facade lifecycle, shutdown, cancellation, and resource-release contracts | Lifecycle fixture contract 1/1; selected C++ tests 5/5; existing Prism target; native Debug/Release builds; 6 native tests; Debug/Release `plutil`; public-header scan; `git diff --check` |
| `78d8354be` | Added a standalone compile contract for every current facade public header | Facade and public-header tests 2/2; selected C++ tests 6/6; existing Prism target; native Debug/Release builds; 6 native tests; Debug/Release `plutil`; public-header scan; `git diff --check` |

## Current architecture findings

1. Prism currently builds `Launcher_logic` as a monolithic static library containing both domain and Qt UI sources.
2. `Application` derives from `QApplication` and exposes global application state.
3. `InstanceList` and `AccountList` derive from Qt list models.
4. `LaunchController` derives from the existing task system.
5. The native Xcode target does not yet link a backend library.
6. The first backend task is separation and characterization, not Swift reimplementation.
7. M2-W1 keeps the existing Qt composition in `Launcher_logic` while exposing domain, UI, application, and executable-entry source ownership for the upcoming facade target.
8. M2-W2 is the first independent `launcher/frontend` target; it must remain compilable without `launcher/ui` and must not alter the existing Qt target's link graph.
9. M2-W2's facade root is deliberately inert; M2-W3 owns the first explicit data-root and runtime-dependency contract.
10. The native facade must receive an absolute data root and injected runtime ports rather than deriving paths from `Application`, process arguments, environment variables, or global Qt application state.
11. M2-W3 normalizes the root lexically and rejects invalid construction before any service work; filesystem mutation and backend instance loading remain separate contracts.
12. M2-W4 exposes snapshots and ordered instance-change values through loader ports; `InstanceList` remains an internal legacy model and cannot cross the facade boundary.
13. M2-W5 makes lifecycle ownership explicit: cancellation and release callbacks run once during `ShuttingDown`, injected ports are cleared at `Stopped`, and post-stop facade work is rejected without touching loaders.
14. M2-W6 makes the facade public-header boundary executable: the current header list is compiled by a standalone no-link target, while forbidden Qt/UI tokens remain absent from the public surface.

## Custom rendering exceptions

No exception is approved.

Minecraft skin preview is a candidate only. It requires the complete exception record from `PLAN.md` before implementation.

## Blockers

No current blocker.

## Resume instructions

Read `PLAN.md`, run `git status --short --branch -uall`, inspect the last five commits, then activate only ready `M2-W7`. Do not begin Milestone 3 or native visual implementation until the existing Qt composition contract is committed.

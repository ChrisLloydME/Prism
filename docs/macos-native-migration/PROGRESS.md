# Prism macOS Native Migration Progress

Last updated: 2026-08-05

Branch: `macos-native`

Plan: `docs/macos-native-migration/PLAN.md`

Current milestone: Milestone 5, Launch, stop, tasks, and logs

Active work unit: M5-W2

Next ready work unit: none (M5-W2 active)

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
| 2. QWidget-free backend facade | complete | Facade lists fixture instances without UI headers |
| 3. Objective-C++ bridge foundation | complete | Swift receives real fixture snapshots and events |
| 4. Native shell and instance library | complete | System-native shell state and commands are tested |
| 5. Launch, tasks, and logs | active | Deterministic launch-task contracts are tested |
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

Status: complete

Outcome: add a direct build/link contract proving the existing Qt `Prism` executable remains linked through `Launcher_logic` and behaviorally independent from `Launcher_frontend`.

Scope: `launcher/CMakeLists.txt`, directly related build/test assertions, and this progress file only. Do not launch the Qt executable, add native visual surfaces, alter backend behavior, or access real data.

Required evidence: explicit target/link-graph inspection, isolated Qt `Prism` build, selected C++ tests, independent facade build/tests, native Debug/Release builds and tests, Bundle ID checks, and `git diff --check`.

HIG decision: none, this unit preserves legacy backend composition without controls or rendering.

Files changed: `launcher/CMakeLists.txt` and this progress file.

Design: add configure-time target-property assertions that require `${Launcher_Name}` to link `Launcher_logic`, forbid direct `${Launcher_Name}` or `Launcher_logic` links to `Launcher_frontend`, and require `Launcher_logic` to retain `Qt${QT_VERSION_MAJOR}::Widgets`. The existing source composition and runtime code remain unchanged; no UI control or custom drawing is involved.

Tests and exact commands:

- `git diff --check` — passed before and after implementation changes.
- `env PKG_CONFIG_PATH="/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libarchive_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/bzip2_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/liblzma_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/lzo_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/lz4_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zstd_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/tomlplusplus_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libqrencode_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zlib_arm64-osx/lib/pkgconfig:/opt/homebrew/lib/pkgconfig" cmake -S . -B /private/tmp/prism-m2-cmake-pkgconfig -G Ninja -DCMAKE_PREFIX_PATH="/opt/homebrew/opt/qt;/opt/homebrew/opt/cmark;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/ecm_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/cmark_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libarchive_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/tomlplusplus_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zlib_arm64-osx" -DVCPKG_MANIFEST_MODE=OFF -DCMAKE_DISABLE_FIND_PACKAGE_LibArchive=TRUE -DBUILD_TESTING=ON -DLauncher_USE_PCH=OFF -DLauncher_ENABLE_JAVA_DOWNLOADER=OFF -DMACOSX_SPARKLE_UPDATE_PUBLIC_KEY="" -DMACOSX_SPARKLE_UPDATE_FEED_URL=""` — passed; output included `Qt launcher composition contract passed: Prism->Launcher_logic; no frontend link`; existing clang-format and AutoUIC warnings remain non-blocking.
- `cmake --build /private/tmp/prism-m2-cmake-pkgconfig --target Launcher_frontend Launcher_frontend_contract_test Launcher_frontend_public_header_test --parallel 2` — passed; independent facade targets remained buildable.
- `cmake --build /private/tmp/prism-m2-cmake-pkgconfig --target Prism --parallel 2` — passed; existing Qt launcher executable linked.
- `ctest --test-dir /private/tmp/prism-m2-cmake-pkgconfig --output-on-failure -R '^(FrontendFacadeContract|FrontendFacadePublicHeaders|FileSystem|Task|JavaVersion|Version)$'` — passed; 6/6.
- `rg -n -A5 -B2 "prismlauncher\\.app/Contents/MacOS/prismlauncher" /private/tmp/prism-m2-cmake-pkgconfig/build.ninja` — passed; generated link rule contains `launcher/libLauncher_logic.a` and Qt Widgets, with no `Launcher_frontend` edge.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; 6 tests, 0 failures.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `git diff --check` — passed after verification.

Result summary: configure-time assertions and the generated Ninja rule prove the Qt executable still goes through `Launcher_logic`, retains Qt Widgets, and has no frontend link edge. The facade and selected C++ tests remain green, and native identity/build/test contracts pass. No application or launcher executable was launched, and no upstream application, Application Support data, account, Keychain, production API, signing, installation, or publishing state was accessed.

Risk: target-property checks prove the configured ownership/link boundary and buildability, not runtime behavior of the unlaunched Qt application; the legacy Qt UI remains in place until native parity. Existing AutoUIC and missing `clang-format` warnings remain unchanged.

Commit: `7bfb98353`

Next after completion: `M3-W1`, replace the identity-only bridge composition with a lifecycle-owning bridge root.

### M3-W1: Lifecycle-owning Objective-C++ bridge root

Status: complete

Outcome: replace the identity-only bridge composition with `PRPrismBridge`, an Objective-C++ root that owns a private native-facade lifecycle state and explicit cancellation/shutdown callback lifetime against an injected temporary data root.

Scope: `macos/PrismNative/Bridge`, directly related native tests and Xcode project files, and this progress file only. Do not access upstream data, real credentials, Keychain, or production services; do not add visual surfaces yet.

Required evidence: Foundation-only public bridge API, explicit fixture-root initialization, deterministic shutdown and cancellation, released observers/callbacks, Swift/Objective-C++ compile, native tests, data isolation, and no Qt/C++ types in public bridge headers.

HIG decision: none, this unit is bridge lifecycle infrastructure without controls or rendering.

Files changed: `macos/PrismNative/Bridge/PrismBridge.h`, `macos/PrismNative/Bridge/PrismBridge.mm`, `macos/PrismNativeTests/PrismNativeInfrastructureTests.swift`, `macos/PrismNativeTests/PrismNativeTestSupport.swift`, and this progress file. The Xcode project already compiled `PrismBridge.mm` for both targets, so no project-file change was required.

Design: add a Foundation-only `PRBridgeLifecycleState` enum, an explicit file-URL initializer, and nullable Foundation block handlers. The private `.mm` implementation normalizes the URL without filesystem discovery or mutation, stores a C++ lifecycle state object behind the Objective-C++ boundary, transitions `Running` → `ShuttingDown` → `Stopped`, invokes cancellation before shutdown, clears both handlers, makes repeated shutdown a no-op, and performs the same shutdown from ARC deinitialization. No QWidget, QDialog, Qt model, C++ value, or ownership type crosses the public header.

Tests and exact commands:

- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; 9 tests, 0 failures.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -fsyntax-only -x objective-c -target arm64-apple-macos14.0 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk macos/PrismNative/Bridge/PrismBridge.h` — passed; the public header compiles as Objective-C without C++ mode.
- `if rg -n "QWidget|QDialog|QObject|QString|QVariant|QModelIndex|QList|QMap|QHash|QUrl|QAbstractItemModel|QAbstractListModel|QAbstractTableModel|Q_OBJECT|std::|shared_ptr|unique_ptr|reinterpret_cast|static_cast|dynamic_cast|template<|namespace " macos/PrismNative/Bridge --glob '*.h'; then exit 1; else exit 0; fi` — passed with no forbidden public-header matches.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `git diff --check` — passed.

Result summary: fixture tests construct the root only from a temporary URL, preserve a marker file, reject non-file and relative roots, and prove the fixture is outside the upstream `PrismLauncher` namespace. Cancellation and shutdown handlers execute once in order; repeated shutdown is rejected; the lifecycle reports `ShuttingDown` to the shutdown callback; ARC deinitialization performs the same shutdown; and a weak observer is released after callbacks are cleared. Swift and Objective-C++ compile through the existing native targets. No application or launcher executable was launched, and no upstream application, Application Support data, account, Keychain, production API, signing, installation, or publishing state was accessed.

Risk: this unit owns the bridge lifecycle state and callback ports but does not yet link or construct the real `FrontendFacade`; backend linking is reserved for M3-W6. Observer tokens, main-actor delivery, Foundation instance/task DTOs, and real fixture snapshots remain later M3 contracts. The existing AppIntents metadata warning and prior non-blocking CMake warnings remain unchanged. No CMake command was required because this unit does not modify launcher backend sources or build configuration.

Commit: `17258dae9`

Next after completion: `M3-W2`, add immutable Foundation DTOs for instance summaries and task status.

### M3-W2: Immutable Foundation instance and task DTOs

Status: complete

Outcome: add immutable Foundation value objects for instance summaries and task status so Swift can receive stable bridge data without Qt models or C++ ownership.

Scope: `macos/PrismNative/Bridge`, directly related native tests and Xcode project files, and this progress file only. Do not add visual surfaces, real backend credentials, live authentication, or production data access.

Required evidence: Objective-C header compile, immutable Foundation properties, stable identifiers and task progress/cancellation metadata, fixture conversion tests, no Qt/C++ public types, native Debug/Release builds, native tests, Bundle ID checks, and `git diff --check`.

HIG decision: none, this unit defines bridge values without controls or rendering.

Files changed: `macos/PrismNative/Bridge/PrismBridgeModels.h`, `macos/PrismNative/Bridge/PrismBridge.h`, `macos/PrismNative/Bridge/PrismBridge.mm`, `macos/PrismNativeTests/PrismNativeInfrastructureTests.swift`, `macos/PrismNative.xcodeproj/project.pbxproj`, and this progress file. The model header is a public Foundation-only file reference and is included by the existing bridging header through `PrismBridge.h`; its implementation remains in the already compiled `PrismBridge.mm` target for both app and tests.

Design: add `PRInstanceSummary` with copied stable identifier/name/icon/group values and `PRTaskStatus` with copied stable task identifiers, explicit state/progress enums, finite progress validation, and cancellation metadata. Both classes expose readonly properties and unavailable default initializers. Empty optional icon/group values normalize to `nil`; determinate progress is restricted to `[0, 1]`, while none/indeterminate progress must carry zero. Unknown enum values and invalid identifiers are rejected before publication. The public headers import Foundation only; Objective-C++ validation and storage stay private to `.mm`. Error translation remains M3-W4, and real backend-to-DTO conversion remains M3-W5/M3-W6.

Tests and exact commands:

- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; 11 tests, 0 failures.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -fsyntax-only -x objective-c -target arm64-apple-macos14.0 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk macos/PrismNative/Bridge/PrismBridge.h` — passed; the umbrella public bridge header and DTO header compile without C++ mode.
- `if rg -n "QWidget|QDialog|QObject|QString|QVariant|QModelIndex|QList|QMap|QHash|QUrl|QAbstractItemModel|QAbstractListModel|QAbstractTableModel|Q_OBJECT|std::|shared_ptr|unique_ptr|reinterpret_cast|static_cast|dynamic_cast|template<|namespace " macos/PrismNative/Bridge --glob '*.h'; then exit 1; else exit 0; fi` — passed with no forbidden public-header matches.
- `if rg -n "#import <Qt|#include|std::|QWidget|QDialog|QObject|QString|QVariant|QModelIndex|QList|QMap|QHash|QUrl|unique_ptr|shared_ptr|reinterpret_cast|static_cast|dynamic_cast" macos/PrismNative/App --glob '*.swift'; then exit 1; fi` — passed; native Swift app sources contain no Qt or C++ boundary types.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `git diff --check` — passed.

Result summary: the fixture test copies mutable input strings before publication, preserves a temporary fixture marker, normalizes empty optional metadata, rejects empty identifiers/names, validates task state/progress ranges and unknown enum values, and preserves cancellation metadata. The public scanner covers both bridge headers, and the native test suite passes without launching the application. The first test compile exposed Swift's failable raw-value enum initializer; the test was corrected to pass an explicitly unwrapped unknown raw value into the Objective-C++ validation path, after which all 11 tests passed. No application or launcher executable was launched, and no upstream application, Application Support data, account, Keychain, production API, signing, installation, or publishing state was accessed.

Risk: these DTOs are bridge contracts and fixture-tested value validation only; the real facade is not linked, backend snapshots are not converted, observation tokens are not registered, and task errors are not translated until later M3 units. No CMake command was required because this unit does not modify launcher backend sources or build configuration. Existing AppIntents metadata and prior non-blocking CMake warnings remain unchanged.

Commit: `65a044abe`

Next after completion: `M3-W3`, add explicitly cancellable observation tokens and callback registration.

### M3-W3: Cancellable bridge observations

Status: complete

Outcome: add explicit Foundation observation registration and cancellation tokens so bridge callbacks cannot outlive their owner or deliver after cancellation.

Scope: `macos/PrismNative/Bridge`, directly related native tests and Xcode project files, and this progress file only. Do not add visual surfaces, live backend credentials, production data access, or UI snapshot tests.

Required evidence: Foundation-only observer/token API, deterministic fixture event delivery, cancellation before and after queued delivery, released observer/token behavior, native Debug/Release builds, native tests, Bundle ID checks, public-header scan, and `git diff --check`.

HIG decision: none, this unit defines event lifetime infrastructure without controls or rendering.

Files changed: `macos/PrismNative/Bridge/PrismBridge.h`, `macos/PrismNative/Bridge/PrismBridge.mm`, `macos/PrismNativeTests/PrismBridgeObservationTests.mm`, `macos/PrismNative.xcodeproj/project.pbxproj`, and this progress file. The new Objective-C++ test source is registered only in the native test target; its category declaration reaches private fixture event ingress methods without widening the public bridge header.

Design: add `PRBridgeObservationToken` with idempotent `cancel` and readonly cancellation state, plus typed instance-summary and task-status handler blocks. The private `.mm` implementation stores observer states behind `NSLock`-protected collections and uses a recursive state lock while a callback is in flight, so cancellation suppresses queued delivery and waits for an active callback to finish. Releasing a token cancels its state, clears the Foundation handler, removes the registration, and releases captured observers. Bridge shutdown removes and cancels every state before lifecycle callbacks, and new registration is rejected after shutdown begins. Fixture event publishing remains a private Objective-C++ ingress for this unit; main-actor delivery and real facade event conversion remain later contracts.

Tests and exact commands:

- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; 17 tests, 0 failures, including 6 observation tests.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO -only-testing:PrismNativeTests/PrismBridgeObservationTests/testReleasedObservationTokenReleasesObserverAndStopsDelivery test` — passed; focused release contract passed after isolating ARC lifetimes in the fixture.
- `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -fsyntax-only -x objective-c -target arm64-apple-macos14.0 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk macos/PrismNative/Bridge/PrismBridge.h` — passed; public bridge and model headers compile without C++ mode.
- `if rg -n "QWidget|QDialog|QObject|QString|QVariant|QModelIndex|QList|QMap|QHash|QUrl|QAbstractItemModel|QAbstractListModel|QAbstractTableModel|Q_OBJECT|std::|shared_ptr|unique_ptr|reinterpret_cast|static_cast|dynamic_cast|template<|namespace " macos/PrismNative/Bridge --glob '*.h'; then exit 1; fi` — passed with no forbidden public-header matches.
- `if rg -n "#import <Qt|#include|std::|QWidget|QDialog|QObject|QString|QVariant|QModelIndex|QList|QMap|QHash|QUrl|unique_ptr|shared_ptr|reinterpret_cast|static_cast|dynamic_cast" macos/PrismNative/App --glob '*.swift'; then exit 1; fi` — passed; native Swift app sources contain no Qt or C++ boundary types.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `git diff --check` — passed.

Result summary: instance and task fixture events reached their typed handlers with immutable DTOs; cancellation was idempotent; cancellation before a queued event suppressed delivery; cancellation after one queued event stopped later delivery; dropping the token released the captured observer and suppressed later callbacks; shutdown cancelled existing tokens and rejected new observers. All fixture roots were temporary and no upstream application or data was accessed. No application or launcher executable was launched.

Risk: observation registration and token lifetime are now deterministic, but callbacks are not yet marshalled to the main actor, errors are not yet translated, and the private publish ingress is not connected to the real `FrontendFacade`. Those contracts remain M3-W4 through M3-W6. No CMake command was required because this unit does not modify launcher backend sources or build configuration. Existing AppIntents metadata and prior non-blocking CMake warnings remain unchanged.

Commit: `cacd8d16f`

Next after completion: `M3-W4`, add error translation and main-actor delivery.

### M3-W4: Error translation and main-actor delivery

Status: complete

Outcome: translate bridge failures into stable Foundation error values and deliver observer callbacks on the main actor without blocking backend work.

Scope: `macos/PrismNative/Bridge`, directly related native tests and Xcode project files, and this progress file only. Do not access real accounts, credentials, Keychain, production services, or add visual surfaces.

Required evidence: stable error domain/code/localization/recovery values, main-actor callback assertions, cancellation and shutdown interaction tests, no Qt/C++ public types, native Debug/Release builds, native tests, Bundle ID checks, public-header scan, and `git diff --check`.

HIG decision: none, this unit defines error and threading contracts without controls or rendering.

Files changed: `macos/PrismNative/Bridge/PrismBridgeErrors.h`, `macos/PrismNative/Bridge/PrismBridge.h`, `macos/PrismNative/Bridge/PrismBridge.mm`, `macos/PrismNativeTests/PrismBridgeObservationTests.mm`, `macos/PrismNative.xcodeproj/project.pbxproj`, and this progress file. The new public error header is Foundation-only and is registered in the native bridge group; no backend source, UI surface, or runtime data path changed.

Design: add immutable `PRBridgeError` values with fixed domain `com.lloydME.Prism.bridge`, explicit error codes, localization keys, copied substitution values, optional safe diagnostic text, recovery kinds, partial-rollback metadata, and a corresponding `NSError` projection. Keep the failure-kind-to-error mapping private to Objective-C++; tests enter through a private category only, so C++ failure types do not cross the public bridge. Change observer delivery from synchronous callbacks to `dispatch_async(dispatch_get_main_queue(), ...)`: publication returns on the backend queue, the queued state rechecks cancellation before invoking the handler, and token release or bridge shutdown clears the handler before queued work can retain an observer. The main queue is the bridge's Objective-C delivery boundary for Swift `@MainActor` state; no custom control or rendering API is involved.

Tests and exact commands:

- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; 20 tests, 0 failures, including 9 bridge-observation tests.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -fsyntax-only -x objective-c -target arm64-apple-macos14.0 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk macos/PrismNative/Bridge/PrismBridge.h` — passed; the umbrella bridge and error/model headers compile without C++ mode.
- `if rg -n "QWidget|QDialog|QObject|QString|QVariant|QModelIndex|QList|QMap|QHash|QUrl|QAbstractItemModel|QAbstractListModel|QAbstractTableModel|Q_OBJECT|std::|shared_ptr|unique_ptr|reinterpret_cast|static_cast|dynamic_cast|template<|namespace " macos/PrismNative/Bridge --glob '*.h'; then exit 1; else exit 0; fi` — passed with no forbidden public-header matches.
- `if rg -n "#import <Qt|#include|std::|QWidget|QDialog|QObject|QString|QVariant|QModelIndex|QList|QMap|QHash|QUrl|unique_ptr|shared_ptr|reinterpret_cast|static_cast|dynamic_cast" macos/PrismNative/App --glob '*.swift'; then exit 1; else exit 0; fi` — passed; native Swift app sources remain outside Qt and C++ types.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `git diff --check` — passed.

Result summary: the native bridge now translates fixture failure categories into stable Foundation error metadata, preserves safe substitution values by copy, and exposes an `NSError` with the same domain/code and structured user-info keys. Instance and task callbacks run on the main thread, backend publication returns before the callback, cancellation suppresses queued delivery, token release still releases captured observers, and shutdown suppresses already-queued delivery while rejecting later registrations. Tests use only temporary fixture roots; no application or launcher executable was launched.

Risk: the failure-kind mapper is fixture-facing infrastructure until M3-W5/M3-W6 connect real facade errors and snapshots; partial-rollback values are conservatively `false` because this unit performs no mutating backend operation. Localization resources, Swift feature stores, and real facade event ingress remain later units. No CMake command was required because launcher backend sources and build configuration were unchanged.

Commit: `a9853cbe2`

Next after completion: `M3-W5`, add complete bridge contract tests for empty and fixture data, cancellation, shutdown, and released observers.

### M3-W5: Complete bridge contract tests

Status: complete

Outcome: exercise initialization, empty and fixture data, cancellation, shutdown, and released-observer behavior through the real native bridge contract.

Scope: `macos/PrismNative/Bridge`, directly related native tests and Xcode project files, and this progress file only. Do not access real accounts, credentials, Keychain, production services, or add visual surfaces.

Required evidence: deterministic empty and fixture-root bridge state, immutable snapshot/event conversion, cancellation and shutdown ordering, released observer behavior, stable error propagation, native Debug/Release builds, native tests, Bundle ID checks, public-header scan, and `git diff --check`.

HIG decision: none, this unit strengthens bridge tests without controls or rendering.

Files changed: `macos/PrismNativeTests/PrismBridgeContractTests.mm`, `macos/PrismNative.xcodeproj/project.pbxproj`, and this progress file. The contract suite is a separate Objective-C++ test source; it reaches only private fixture ingress selectors through a test category and does not widen the Foundation public bridge or link backend code.

Design: keep the bridge contract test-only and deterministic. Use a temporary root for every test, observe instance summaries through the public token API, inject fixture summaries only through the existing private Objective-C++ test ingress, drain the main queue without launching the app, and assert that empty fixtures create no placeholder instance. The suite verifies copied identifier/name/icon/group values, cancellation before queued delivery, lifecycle callback order during shutdown, released observer/token lifetime, and stable error metadata alongside fixture state. No custom rendering or HIG exception is involved.

Tests and exact commands:

- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; 27 tests, 0 failures, including 7 new bridge contract tests.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -fsyntax-only -x objective-c -target arm64-apple-macos14.0 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk macos/PrismNative/Bridge/PrismBridge.h` — passed; all public bridge headers compile without C++ mode.
- `if rg -n "QWidget|QDialog|QObject|QString|QVariant|QModelIndex|QList|QMap|QHash|QUrl|QAbstractItemModel|QAbstractListModel|QAbstractTableModel|Q_OBJECT|std::|shared_ptr|unique_ptr|reinterpret_cast|static_cast|dynamic_cast|template<|namespace " macos/PrismNative/Bridge --glob '*.h'; then exit 1; else exit 0; fi` — passed with no forbidden public-header matches.
- `if rg -n "#import <Qt|#include|std::|QWidget|QDialog|QObject|QString|QVariant|QModelIndex|QList|QMap|QHash|QUrl|unique_ptr|shared_ptr|reinterpret_cast|static_cast|dynamic_cast" macos/PrismNative/App --glob '*.swift'; then exit 1; else exit 0; fi` — passed; native Swift app sources remain outside Qt and C++ types.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `git diff --check` — passed.

Result summary: the bridge contract suite confirmed that a temporary bridge starts in `Running`, uses no upstream namespace, emits no placeholder instance for empty fixture state, delivers immutable fixture metadata on the main actor, suppresses queued callbacks after cancellation or shutdown, invokes lifecycle callbacks in cancellation-then-shutdown order, releases captured observers when tokens are released, and preserves stable Foundation error values. No application or launcher executable was launched and no upstream data was accessed.

Risk: fixture ingress remains private and synthetic until M3-W6 connects the real `FrontendFacade`; this unit intentionally does not claim backend linkage or live data conversion. Existing AppIntents metadata and prior non-blocking CMake warnings remain unchanged. No CMake command was required because this unit changes only native tests and Xcode test-source registration.

Commit: `6711968f7`

Next after completion: `M3-W6`, link the QWidget-free `FrontendFacade` output into Xcode through the Objective-C++ bridge.

### M3-W6: Link the QWidget-free facade into the native bridge

Status: complete

Outcome: link the existing `Launcher_frontend` output into the native Xcode target and convert real facade snapshots, events, lifecycle, and errors through Objective-C++ without copying launcher implementation files into the app target.

Scope: `macos/PrismNative`, `launcher/frontend` and directly required launcher build configuration, directly related native/C++ tests, Xcode project settings, and this progress file only. Preserve the existing Qt `Prism` executable link and do not change unrelated platforms or access real data.

Required evidence: isolated CMake facade build and relevant C++ tests, Xcode link configuration proving `Launcher_frontend` is consumed without `launcher/ui` sources, real fixture snapshot/event conversion through the bridge, lifecycle and error propagation, no Qt/C++ public types, native Debug/Release builds, native tests, Bundle ID checks, link inspection, and `git diff --check`.

HIG decision: none, this unit establishes backend linkage and bridge conversion without controls or rendering.

Files changed: `macos/PrismNative/Bridge/PrismBridge.h`, `macos/PrismNative/Bridge/PrismBridge.mm`, `macos/PrismNative/Bridge/PrismBridgeModels.h`, `macos/PrismNativeTests/PrismBridgeFacadeIntegrationTests.mm`, `macos/PrismNative.xcodeproj/project.pbxproj`, and this progress file. No launcher implementation source was copied into the Xcode target. The native app and test target consume only the ignored universal `libLauncher_frontend.a` output through `-lLauncher_frontend`; the existing Qt `Prism` executable remains linked through `Launcher_logic`.

Design: keep the private Objective-C++ initializer as the only owner and type-conversion boundary for `FrontendFacade` and `FrontendRuntimeDependencies`. The bridge converts validated C++ snapshots and Added/Updated/Removed changes into copied Foundation DTOs, translates facade exceptions to stable `PRBridgeError` values, publishes changes on the existing cancellation-aware main-actor observation path, and cancels one-shot requests before invoking completion. The public bridge headers and Swift app surface remain Foundation-only; no controls, rendering, or HIG exception is involved.

Tests and exact commands:

- `env PKG_CONFIG_PATH="/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libarchive_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/bzip2_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/liblzma_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/lzo_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/lz4_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zstd_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/tomlplusplus_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libqrencode_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zlib_arm64-osx/lib/pkgconfig:/opt/homebrew/lib/pkgconfig" cmake -S . -B /private/tmp/prism-m3-w6-cmake -G Ninja -DCMAKE_PREFIX_PATH="/opt/homebrew/opt/qt;/opt/homebrew/opt/cmark;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/ecm_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/cmark_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libarchive_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/tomlplusplus_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zlib_arm64-osx" -DVCPKG_MANIFEST_MODE=OFF -DCMAKE_DISABLE_FIND_PACKAGE_LibArchive=TRUE -DBUILD_TESTING=ON -DLauncher_USE_PCH=OFF -DLauncher_ENABLE_JAVA_DOWNLOADER=OFF -DMACOSX_SPARKLE_UPDATE_PUBLIC_KEY="" -DMACOSX_SPARKLE_UPDATE_FEED_URL="" -DCMAKE_ARCHIVE_OUTPUT_DIRECTORY="/Users/lloyd/Developer/Xcode/Prism/.deriveddata-prism-native-backend"` — configured successfully.
- `cmake --build /private/tmp/prism-m3-w6-cmake --target Launcher_frontend Launcher_frontend_contract_test Launcher_frontend_public_header_test --parallel 2`, `cmake --build /private/tmp/prism-m3-w6-cmake --target Prism --parallel 2`, and `cmake --build /private/tmp/prism-m3-w6-cmake --target FileSystem Task JavaVersion Version --parallel 2` — all passed.
- `ctest --test-dir /private/tmp/prism-m3-w6-cmake --output-on-failure -R '^(FrontendFacadeContract|FrontendFacadePublicHeaders|FileSystem|Task|JavaVersion|Version)$'` — passed 6/6.
- `env PKG_CONFIG_PATH="/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libarchive_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/bzip2_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/liblzma_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/lzo_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/lz4_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zstd_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/tomlplusplus_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libqrencode_arm64-osx/lib/pkgconfig:/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zlib_arm64-osx/lib/pkgconfig:/opt/homebrew/lib/pkgconfig" cmake -S . -B /private/tmp/prism-m3-w6-universal -G Ninja -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DCMAKE_PREFIX_PATH="/opt/homebrew/opt/qt;/opt/homebrew/opt/cmark;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/ecm_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/cmark_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/libarchive_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/tomlplusplus_arm64-osx;/Users/lloyd/Developer/Xcode/Prism/.deps/vcpkg/packages/zlib_arm64-osx" -DVCPKG_MANIFEST_MODE=OFF -DCMAKE_DISABLE_FIND_PACKAGE_LibArchive=TRUE -DBUILD_TESTING=ON -DLauncher_USE_PCH=OFF -DLauncher_ENABLE_JAVA_DOWNLOADER=OFF -DMACOSX_SPARKLE_UPDATE_PUBLIC_KEY="" -DMACOSX_SPARKLE_UPDATE_FEED_URL="" -DCMAKE_ARCHIVE_OUTPUT_DIRECTORY="/Users/lloyd/Developer/Xcode/Prism/.deriveddata-prism-native-backend"` — configured successfully. `cmake --build /private/tmp/prism-m3-w6-universal --target Launcher_frontend Launcher_frontend_contract_test Launcher_frontend_public_header_test --parallel 2` passed. `file .deriveddata-prism-native-backend/libLauncher_frontend.a` reported a Mach-O universal binary with `x86_64` and `arm64`; `lipo -info .deriveddata-prism-native-backend/libLauncher_frontend.a` reported both architectures.
- `ctest --test-dir /private/tmp/prism-m3-w6-universal --output-on-failure -R '^(FrontendFacadeContract|FrontendFacadePublicHeaders)$'` — passed 2/2.
- `xcodebuild -quiet -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -quiet -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -quiet -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed 32/32.
- `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -fsyntax-only -x objective-c -target arm64-apple-macos14.0 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk macos/PrismNative/Bridge/PrismBridge.h` and `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++ -fsyntax-only -std=c++20 -fobjc-arc -x objective-c++ -target arm64-apple-macos14.0 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk -Ilauncher/frontend macos/PrismNative/Bridge/PrismBridge.mm` — both passed.
- The forbidden public bridge scan and Swift app boundary scan passed with no matches. `rg -n 'launcher/ui|QWidget|QDialog|QtWidgets|QAbstractItemModel|QAbstractListModel|QObject|QModelIndex' launcher/frontend --glob '*.h'` returned no matches. The Xcode project inspection confirms `HEADER_SEARCH_PATHS` points only to `launcher/frontend`, `LIBRARY_SEARCH_PATHS` points to `.deriveddata-prism-native-backend`, and `OTHER_LDFLAGS` contains `-lLauncher_frontend`; the successful link command consumed that archive without `launcher/ui` sources.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` and the corresponding Release command both printed `com.lloydME.Prism`.
- `git diff --check` and `git diff --cached --check` — passed.

Result summary: native tests obtain temporary-fixture snapshots and ordered changes through the real `FrontendFacade` owned by the bridge, verify main-actor delivery, cancellation suppression, stable invalid-input translation, and exactly-once facade shutdown callbacks. The app's default runtime dependencies intentionally provide no loader callbacks yet, so default composition remains empty until a later domain adapter supplies services; no upstream Application Support path is read.

Risk: the universal archive is ignored build output rather than a committed backend artifact. Existing AppIntents metadata, Vulkan/scdoc, AutoUIC, and missing clang-format warnings remain non-blocking and unchanged. No current blocker.

Commit: `4f3d62c21`

Next after completion: `M4-W1`, define native app commands and keyboard shortcuts before toolbar duplication.

### M4-W1: Define native app commands and keyboard shortcuts

Status: complete

Outcome: establish one testable native command model and system menu/shortcut definitions before duplicating toolbar actions, so shell commands have stable enabled state, accessibility metadata, and keyboard behavior.

Scope: `macos/PrismNative/App`, directly related native tests and Xcode project files, and this progress file only. Use SwiftUI `Commands` and system menu APIs; do not begin sidebar/content rendering or modify other platforms.

Required evidence: command/view-model tests for enabled state and invocation routing, menu and keyboard shortcut tests, static source checks for system command/navigation APIs, native Debug/Release builds, native tests, Bundle ID checks, and `git diff --check`. No application launch, screenshot, visual snapshot, real account, Keychain, or upstream data access.

HIG decision: use SwiftUI `Commands`, `CommandGroup`, `CommandMenu`, and `keyboardShortcut` for the app shell; keep toolbar duplication deferred until the command model is tested. No custom-drawn menu or control is allowed.

Files changed: `macos/PrismNative/App/PrismCommandModel.swift`, `macos/PrismNative/App/PrismCommands.swift`, `macos/PrismNative/App/PrismNativeApp.swift`, `macos/PrismNativeTests/PrismCommandTests.swift`, `macos/PrismNative.xcodeproj/project.pbxproj`, and this progress file. The command model is also a direct test-target source so its enabled-state and routing contract is exercised without importing the app executable.

Design: define a stable command manifest with menu placement, static localization keys, accessibility labels, help text, and optional keyboard shortcuts. `PrismCommandModel` is a main-actor observable state seam that gates selection-dependent launch, stop, edit, delete, and undo actions and routes only enabled commands to an injected handler. `PrismCommands` renders the manifest through SwiftUI `CommandGroup` and `CommandMenu`, uses the system `openSettings` action, and adds no toolbar or custom-drawn control. Preserve standard Edit undo/redo placement by leaving instance-deletion undo without a duplicate shortcut; a later mutation unit can connect it to native `UndoManager` semantics.

Tests and exact commands:

- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO -only-testing:PrismNativeTests/PrismCommandTests test` — passed 5/5 command tests.
- `xcodebuild -quiet -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -quiet -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed 37/37.
- `rg -n 'CommandGroup\(|CommandMenu\(|\.keyboardShortcut\(|\.accessibilityLabel\(|\.help\(' macos/PrismNative/App/PrismCommands.swift` — passed; system command/menu and accessibility APIs are present. `rg -n '\.toolbar\(|Canvas\(|draw\(|QWidget|QDialog|Qt|std::|#include' macos/PrismNative/App --glob '*.swift'` — passed with no forbidden matches.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` and the corresponding Release command — both printed `com.lloydME.Prism`.
- `git diff --check` — passed.

Result summary: the native app now attaches a testable system command surface before toolbar work. New Instance uses Command-N, Settings uses Command-Comma and the system Settings scene, Close Window uses Command-W, and Delete uses the system delete key equivalent. Selection and running-state gates are tested, disabled commands do not route, labels/help metadata are non-empty, and source inspection confirms no toolbar duplication or custom drawing. The first test build exposed that app-only Swift sources were invisible to the test target; direct model membership was added to the test Sources phase, after which the focused and full suites passed. No application launch, screenshot, visual snapshot, upstream data, real account, Keychain, signing, or publishing action was used.

Risk: command actions currently terminate at the injected command handler because native instance mutations and launch/stop facade commands are later work; the model intentionally does not invent backend behavior. The legacy instance-deletion Command-Z shortcut is not rebound until a native reversible mutation/`UndoManager` contract exists, avoiding a conflict with standard text undo. Static `LocalizedStringKey` usage establishes localizable command keys; localized resource coverage remains part of the consuming feature units. No CMake command was required because this unit changes only native Swift command composition and tests.

Commit: `127ab52b7`

Next after completion: `M4-W2`, implement the sidebar and instance content with `NavigationSplitView`.

### M4-W2: Sidebar and instance content with NavigationSplitView

Status: complete

Outcome: replace the placeholder native hierarchy with a system `NavigationSplitView` shell containing the instance-library sidebar and a testable detail-content boundary, without duplicating toolbar actions or connecting unverified backend mutations.

Scope: `macos/PrismNative/App`, directly related native tests and Xcode project files, and this progress file only. Use SwiftUI `NavigationSplitView`, `List`, and standard content states; do not implement search/grouping/selection policy beyond the contracts required for this shell unit, and do not modify other platforms.

Required evidence: structural SwiftUI API checks, deterministic sidebar/detail state tests, empty/loading/content placeholder state tests, accessibility labels and selection metadata, native Debug/Release builds, native tests, Bundle ID checks, and `git diff --check`. No application launch, screenshot, visual snapshot, real account, Keychain, or upstream data access.

HIG decision: use system `NavigationSplitView`, sidebar-styled `List`, and `ContentUnavailableView`; keep the sidebar hideable and defer toolbar/contextual command duplication to the shared command model. No custom navigation chrome or self-drawn control is allowed.

Files changed: `macos/PrismNative/App/PrismShellModel.swift`, `macos/PrismNative/App/ContentView.swift`, `macos/PrismNativeTests/PrismShellTests.swift`, `macos/PrismNative.xcodeproj/project.pbxproj`, and this progress file. The shell model and its tests are direct sources of the app and test targets; no backend or bridge source changed.

Design: define a stable sidebar manifest with `Instances` and `Discover` identifiers, SF Symbols, localized title keys, accessibility labels, and hints. `PrismShellModel` is a main-actor observable state seam with optional sidebar selection and explicit `loading`, `empty`, and `content` detail states. `ContentView` binds that state to SwiftUI `List(selection:)` inside `NavigationSplitView`; the detail boundary renders `ProgressView` or system `ContentUnavailableView` placeholders. The shell no longer displays an application-support path and does not infer backend data, grouping, search, or mutation behavior.

Tests and exact commands:

- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO -only-testing:PrismNativeTests/PrismShellTests test` — passed; 5/5 focused shell tests.
- `xcodebuild -quiet -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -quiet -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; 42 tests, 0 failures.
- `rg -n 'NavigationSplitView|List\(|selection:|\.tag\(|\.listStyle\(\.sidebar\)|ContentUnavailableView\(|ProgressView\(|\.accessibilityLabel\(|\.accessibilityHint\(|\.accessibilityIdentifier\(' macos/PrismNative/App/ContentView.swift` — passed; all required system navigation, state, selection, and accessibility APIs are present.
- `rg -n '\.toolbar\(|Canvas\(|draw\(|QWidget|QDialog|Qt|std::|#include' macos/PrismNative/App --glob '*.swift'` — returned no matches (exit 1 as expected); no custom chrome, drawing, or Qt/C++ tokens were introduced.
- `rg -n '#import <Qt|#include|std::|QWidget|QDialog|QObject|QString|QVariant|QModelIndex|QList|QMap|QHash|QUrl|unique_ptr|shared_ptr|reinterpret_cast|static_cast|dynamic_cast' macos/PrismNative/App --glob '*.swift'` — returned no matches (exit 1 as expected); Swift remains outside the bridge ownership/type boundary.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `git diff --check` — passed.

Result summary: deterministic shell tests cover stable sidebar IDs, selection metadata, model defaults, optional selection, and each detail state. Structural inspection confirms system navigation/list/content-state/accessibility APIs and no toolbar duplication or self-drawing. Debug and Release builds, the complete native suite, and both Bundle ID checks passed. No application or launcher executable was launched, and no upstream application, Application Support data, account, Keychain, production API, signing, installation, or publishing state was accessed. No CMake command was required because launcher backend sources and build configuration were unchanged.

Risk: the shell intentionally remains a fixture-free presentation boundary: it does not yet load real instance snapshots, apply selection/grouping/sorting/search policy, or route backend mutations. Those contracts belong to M4-W3 and later units. Existing AppIntents metadata and prior non-blocking CMake warnings remain unchanged.

Commit: `b6007523e`

Next after completion: `M4-W3`, implement selection, grouping, sorting, and search in testable Swift state.

### M4-W3: Selection, grouping, sorting, and search state

Status: complete

Outcome: implement deterministic Swift state for instance selection, grouping, sorting, and search while preserving stable identifiers, keyboard operation, and a backend-neutral view-model boundary.

Scope: `macos/PrismNative/App`, directly related native tests/Xcode/project/progress files, and no other platforms. Keep the unit focused on pure state and system `.searchable` integration; do not add launch, edit, delete, provider, or real-data mutations.

Required evidence: fixture-volume state tests for selection, grouping, sorting, search matching, empty results, keyboard identity, and accessibility metadata; static checks for `.searchable` and system collection APIs; native Debug/Release builds, native tests, Bundle ID checks, and `git diff --check`.

HIG decision: keep collection behavior in testable Swift state and consume system `List`/collection selection plus `.searchable`; do not introduce custom cells, custom filtering chrome, or self-drawn controls.

Files changed: `macos/PrismNative/App/PrismShellModel.swift`, `macos/PrismNative/App/ContentView.swift`, `macos/PrismNativeTests/PrismShellTests.swift`, and this progress file. No backend, bridge, or project configuration changed because the existing shell model source was already a member of both native targets.

Design: add immutable `PrismInstanceRow` values with normalized stable identifiers, names, and optional groups; `PrismShellModel` now owns unique fixture rows, optional stable selection, search text, grouping mode, and deterministic ascending/descending name order. Search matches name, identifier, or group case-insensitively after trimming. Grouped sections use stable group IDs and an explicit `Ungrouped` bucket; equal sort keys use the instance identifier as a tie-breaker. Selection remains an identifier across filtering and sorting and is cleared only when an unknown or removed identifier is supplied. `ContentView` binds search through the system `.searchable` modifier while keeping row rendering and backend mutations for later shell units.

Tests and exact commands:

- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO -only-testing:PrismNativeTests/PrismShellTests test` — passed; 11/11 focused tests after correction.
- The first focused run exposed 2 failures in `testTenTimesFixtureVolumePreservesUniqueRowsAndSelectionIdentity`: the test generated IDs as `fixture.42` but selected `fixture.042`. Source inspection of the test and model call path identified the fixture-only mismatch; no production retry was made. The fixture now uses zero-padded IDs, and `xcodebuild ... -only-testing:PrismNativeTests/PrismShellTests/testTenTimesFixtureVolumePreservesUniqueRowsAndSelectionIdentity test` passed 1/1 before the full focused rerun.
- `xcodebuild -quiet -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -quiet -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; 48 tests, 0 failures.
- `rg -n 'NavigationSplitView|List\(|selection:|\.tag\(|\.searchable\(|\.listStyle\(\.sidebar\)' macos/PrismNative/App/ContentView.swift` — passed; system navigation, collection selection, sidebar styling, and search are present.
- `rg -n 'PrismInstanceGrouping|PrismInstanceSortOrder|visibleInstanceSections|setSearchText\(|setGrouping\(|setSortOrder\(' macos/PrismNative/App/PrismShellModel.swift` — passed; state contracts are explicit.
- `rg -n '\.accessibilityLabel\(|\.accessibilityHint\(|\.accessibilityIdentifier\(' macos/PrismNative/App --glob '*.swift'` — passed; sidebar and detail accessibility metadata remains present.
- `rg -n '\.toolbar\(|Canvas\(|draw\(|QWidget|QDialog|Qt|std::|#include|#import <Qt' macos/PrismNative/App --glob '*.swift'` — returned no matches (exit 1 as expected); no custom controls, drawing, or Qt/C++ exposure was introduced.
- `rg -n '#import <Qt|#include|std::|QWidget|QDialog|QObject|QString|QVariant|QModelIndex|QList|QMap|QHash|QUrl|unique_ptr|shared_ptr|reinterpret_cast|static_cast|dynamic_cast' macos/PrismNative/App --glob '*.swift'` — returned no matches (exit 1 as expected); Swift remains outside the bridge ownership/type boundary.
- `rg -n 'LocalizedStringKey|Text\("|\+|String\(format:' macos/PrismNative/App/ContentView.swift macos/PrismNative/App/PrismShellModel.swift` — passed; changed UI strings use SwiftUI localization-aware `Text`/`LocalizedStringKey` forms without fragment concatenation. No `.strings` or `.stringsdict` resource exists yet in `macos/PrismNative`, so missing-key resource validation remains a later localization unit.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `git diff --check` — passed.

Result summary: focused and full native tests cover stable selection identity, case-insensitive sorting with tie-breakers, deterministic grouped sections, name/ID/group search and empty results, normalized identifiers, and 100-row fixture volume. Debug and Release builds, the complete native suite, structural API scans, accessibility checks, localization-shape checks, and both Bundle ID checks passed. No application or launcher executable was launched, and no upstream application, Application Support data, account, Keychain, production API, signing, installation, or publishing state was accessed. No CMake command was required because backend sources and build configuration were unchanged.

Risk: the state model remains backend-neutral and does not yet render real instance rows, load facade snapshots, expose sort/group controls, or handle failed/loading/content presentation beyond the existing shell boundary. Those contracts belong to M4-W4 and later units. Existing AppIntents metadata and prior non-blocking CMake warnings remain unchanged.

Commit: `1774904a8`

Next after completion: `M4-W4`, implement loading, empty, failed, and content states.

### M4-W4: Loading, empty, failed, and content states

Status: complete

Outcome: complete the shell's explicit detail-state presentation for loading, empty, failed, and content conditions with standard SwiftUI states and deterministic recovery metadata.

Scope: `macos/PrismNative/App`, directly related native tests/Xcode/project/progress files, and no other platforms. Use system `ProgressView`, `ContentUnavailableView`, and standard error recovery presentation; do not connect unverified backend mutations or add custom cards.

Required evidence: state transition tests for loading, empty, failed, content, retry/recovery eligibility, cancellation-safe presentation, accessibility labels/help, localization-shape checks, structural system API checks, native Debug/Release builds, native tests, Bundle ID checks, and `git diff --check`.

HIG decision: use system progress and content-unavailable/error presentation; error states must state the next useful action and must not use self-drawn chrome.

Files changed: `macos/PrismNative/App/PrismShellModel.swift`, `macos/PrismNative/App/ContentView.swift`, `macos/PrismNativeTests/PrismShellTests.swift`, and this progress file. No backend, bridge, or Xcode project configuration changed because the existing shell sources were already members of both native targets.

Design: add Foundation-only `PrismShellFailure` and `PrismShellRecoveryAction` values with stable localized title, message, accessibility-label, help, and retry metadata. Extend the shell detail state with `.failed`, render loading/empty/failed/content through `ProgressView` and `ContentUnavailableView`, and expose only an injected retry intent. The failed state uses a system `Button`, explicit accessibility identifiers, and `.help`; no custom card, toolbar, drawing, or third-party UI is present.

Architecture: keep error presentation and recovery eligibility in the main-actor `PrismShellModel`. `retry()` routes the injected handler only while the state is failed and the recovery action is `.retry`; loading, empty, content, and a transition away from failure cannot route a stale retry. The view adds no `Task`, `.task`, bridge call, backend mutation, or cancellation-unsafe asynchronous ownership; real facade error mapping and retry work remain outside this unit.

Tests and exact commands:

- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO -only-testing:PrismNativeTests/PrismShellTests test` — passed; 12/12 focused shell tests.
- `xcodebuild -quiet -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -quiet -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; 49 tests, 0 failures.
- `rg -n 'NavigationSplitView|List\(|selection:|\.tag\(|\.searchable\(|\.listStyle\(\.sidebar\)|ProgressView\(|ContentUnavailableView|Button \{|\.accessibilityLabel\(|\.help\(|\.accessibilityIdentifier\(' macos/PrismNative/App/ContentView.swift` — passed; native shell, state, recovery, and accessibility APIs are present.
- `rg -n 'PrismShellRecoveryAction|PrismShellFailure|PrismShellDetailState|isRetryAvailable|recoveryAction|func retry\(|setDetailState\(' macos/PrismNative/App/PrismShellModel.swift` — passed; state and recovery contracts are explicit.
- `rg -n '\.accessibilityLabel\(|\.accessibilityHint\(|\.accessibilityIdentifier\(|\.help\(' macos/PrismNative/App --glob '*.swift'` — passed; shell and command surfaces expose accessibility metadata.
- `if rg -n '\.toolbar\(|Canvas\(|draw\(' macos/PrismNative/App --glob '*.swift'; then exit 1; else exit 0; fi` — passed with no custom chrome or drawing.
- `if rg -n '#import <Qt|#include|std::|QWidget|QDialog|QObject|QString|QVariant|QModelIndex|QList|QMap|QHash|QUrl|unique_ptr|shared_ptr|reinterpret_cast|static_cast|dynamic_cast' macos/PrismNative/App --glob '*.swift'; then exit 1; else exit 0; fi` — passed with no Qt, C++, or ownership types in Swift.
- `rg -n 'LocalizedStringKey|Text\("|String\(format:' macos/PrismNative/App/ContentView.swift macos/PrismNative/App/PrismShellModel.swift` — passed; failure and recovery copy uses localization-aware keys without fragment concatenation. `rg --files macos/PrismNative | rg 'Localizable\.strings|\.stringsdict$'` found no resource yet, so resource-key coverage remains a later unit.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `git diff --check` — passed. No CMake command was required because launcher backend sources and build configuration were unchanged.

Result summary: the focused and full native suites cover all four detail states, deterministic failure metadata, retry eligibility, injected retry routing, stale-action suppression after state changes, system presentation APIs, accessibility identifiers/labels/help, localization shape, and forbidden-boundary scans. Debug and Release native builds and both Bundle ID checks passed. No application or launcher executable was launched; no screenshots, visual snapshots, upstream application data, accounts, Keychain, production services, signing, installation, or publishing state were accessed.

Risk: the default shell still has no real facade-backed state and its retry handler remains injected until a later store/facade unit supplies real loading and recovery work. No localization resource has been added yet. The next ready unit adds contextual menus and toolbar commands through the shared command model.

Commit: `19490eac9`

Next after completion: `M4-W5`, route contextual menus and toolbar commands through the shared command model.

### M4-W5: Contextual menus and toolbar commands

Status: complete

Outcome: route instance contextual-menu and toolbar actions through the tested shared command model, preserving one enabled-state, shortcut, accessibility, and invocation contract.

Scope: `macos/PrismNative/App`, directly related native tests/Xcode/project/progress files, and no other platforms. Use system SwiftUI toolbar and context-menu APIs; do not duplicate command handlers or connect unverified backend mutations.

Required evidence: command-model routing tests for toolbar and contextual actions, enabled-state and keyboard behavior, accessibility labels/help, structural system API checks, native Debug/Release builds, native tests, Bundle ID checks, and `git diff --check`.

HIG decision: use system `.toolbar` and `.contextMenu` surfaces backed by `PrismCommandModel`; keep labels, enabled state, shortcuts, and actions shared with the app command manifest. No custom-drawn chrome is allowed.

Files changed: `macos/PrismNative/App/PrismCommandModel.swift`, `macos/PrismNative/App/PrismCommands.swift`, `macos/PrismNative/App/ContentView.swift`, `macos/PrismNative/App/PrismNativeApp.swift`, `macos/PrismNativeTests/PrismCommandTests.swift`, `macos/PrismNativeTests/PrismShellTests.swift`, and this progress file. No Xcode project, backend, bridge, or other-platform file changed because all sources were already members of the native app/test targets.

Design: extend each command descriptor with a stable SF Symbol and centralize the system `Button`/`Label`, enabled state, accessibility label, help, and optional keyboard shortcut in `PrismCommandButton`. `ContentView` passes the app-owned `PrismCommandModel` into system `ToolbarItemGroup` and a detail-bound `.contextMenu`; `PrismCommands` reuses the same button for app menus. No custom-drawn control, duplicate action handler, or third-party UI was added.

Architecture: keep toolbar and contextual command IDs in the main-actor `PrismCommandModel` and route every surface through `model.invoke`. Move the shortcut-to-SwiftUI mapping into the shared command-model source because that file is compiled directly by `PrismNativeTests`; the app-only command surface now contains no hidden target dependency. The ContentView composition remains Swift-only and does not call the bridge or backend.

Tests and exact commands:

- The first focused command test build failed because `PrismCommandModel.swift` referenced `keyEquivalent` and `eventModifiers` that existed only in app-only `PrismCommands.swift`; source and target membership inspection identified the missing shared boundary, so the mapping extension moved into the shared model source. No production retry was made before that correction.
- The next focused run compiled and executed 7 tests but failed 3 structural assertions because the test helper read only `PrismCommands.swift` after shared button modifiers moved to `PrismCommandModel.swift`; the helper was widened to read both sources.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO -only-testing:PrismNativeTests/PrismCommandTests test` — passed; final focused command tests 7/7.
- `xcodebuild -quiet -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -quiet -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; 51 tests, 0 failures.
- `rg -n '\.toolbar\{|ToolbarItemGroup\(|\.contextMenu\{|PrismCommandButton\(|PrismInstanceContextMenu\(|commandModel' macos/PrismNative/App/ContentView.swift macos/PrismNative/App/PrismCommands.swift macos/PrismNative/App/PrismCommandModel.swift` — passed; toolbar and context-menu surfaces use the shared command button/model.
- `rg -n 'CommandGroup\(|CommandMenu\(|\.keyboardShortcut\(|\.disabled\(|\.accessibilityLabel\(|\.help\(|model\.invoke\(|toolbarCommandIDs|contextMenuCommandIDs' macos/PrismNative/App/PrismCommands.swift macos/PrismNative/App/PrismCommandModel.swift` — passed; menu placement, shortcuts, enabled state, accessibility/help, and single invocation path are explicit.
- `rg -n '\.accessibilityLabel\(|\.accessibilityHint\(|\.accessibilityIdentifier\(|\.help\(' macos/PrismNative/App --glob '*.swift'` — passed; native shell and command surfaces expose accessibility metadata.
- `if rg -n 'Canvas\(|draw\(' macos/PrismNative/App --glob '*.swift'; then exit 1; else exit 0; fi` and `if rg -n '#import <Qt|#include|std::|QWidget|QDialog|QObject|QString|QVariant|QModelIndex|QList|QMap|QHash|QUrl|unique_ptr|shared_ptr|reinterpret_cast|static_cast|dynamic_cast' macos/PrismNative/App --glob '*.swift'; then exit 1; else exit 0; fi` — passed with no custom drawing or Qt/C++/ownership types in Swift.
- `rg -n 'LocalizedStringKey|Text\("|String\(format:' macos/PrismNative/App/ContentView.swift macos/PrismNative/App/PrismCommands.swift macos/PrismNative/App/PrismCommandModel.swift` — passed; command and toolbar copy uses localization-aware keys without fragment concatenation. `rg --files macos/PrismNative | rg 'Localizable\.strings|\.stringsdict$'` found no resource yet, so resource-key coverage remains a later unit.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `git diff --check` — passed. No CMake command was required because launcher backend sources and build configuration were unchanged.

Result summary: toolbar and detail context-menu surfaces now consume the same command descriptors, enabled-state gates, invocation handler, accessibility/help metadata, and shortcut contract as app menus. Focused and full native tests, Debug/Release builds, structural UI checks, boundary scans, localization-shape checks, and both Bundle ID checks passed. No application or launcher executable was launched; no screenshots, visual snapshots, upstream application data, accounts, Keychain, production services, signing, installation, or publishing state were accessed.

Risk: toolbar and context-menu actions still terminate at the injected command handler until later units connect fixture-safe facade mutations; the context menu is attached to the current detail boundary while native instance rows remain a later shell/content contract. No localization resource has been added yet. The next ready unit adds cross-surface accessibility, help, enabled-state, and keyboard tests.

Commit: `d5249dd8a`

Next after completion: `M4-W6`, add accessibility labels, help, enabled-state, and keyboard tests across the native shell.

### M4-W6: Cross-surface accessibility, help, enabled state, and keyboard tests

Status: complete

Outcome: extend automated accessibility, help, enabled-state, focus, and keyboard contracts across the shared command manifest, toolbar, context menu, and shell selection surfaces.

Scope: `macos/PrismNative/App`, directly related native tests/Xcode/project/progress files, and no other platforms. Keep tests non-launching and fixture-only; do not add backend mutations or visual snapshot acceptance.

Required evidence: cross-surface command and shell tests for labels, values, roles, help, enabled/disabled behavior, keyboard identity, selection focus semantics, localization shape, structural native APIs, Debug/Release builds, native tests, Bundle ID checks, and `git diff --check`.

HIG decision: validate system SwiftUI accessibility modifiers, keyboard shortcuts, toolbar, context-menu, and List selection semantics; no custom accessibility container or self-drawn control is permitted. The decision follows Apple's macOS design guidance for [sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars), [toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars), and [menus](https://developer.apple.com/design/human-interface-guidelines/menus), plus SwiftUI's [accessibility modifiers](https://developer.apple.com/documentation/swiftui/accessibility).

Files changed: `macos/PrismNative/App/PrismCommandModel.swift`, `macos/PrismNative/App/ContentView.swift`, `macos/PrismNativeTests/PrismCommandTests.swift`, `macos/PrismNativeTests/PrismShellTests.swift`, and this progress file. No Xcode project, backend, bridge, or other-platform file changed because the existing native app/test target membership already covers these sources.

Design: give every shared command a deterministic `prism.command.<raw-command-id>` accessibility identifier and apply it in the system SwiftUI `Button` used by app menus, toolbar items, and context-menu items. Extend the system sidebar `List(selection:)` row with a localized accessibility value and stable row identifier. Tests assert system `Button`, `Label`, `List`, `ToolbarItemGroup`, `.contextMenu`, `.keyboardShortcut`, `.disabled`, `.accessibilityLabel`, `.accessibilityValue`, `.accessibilityIdentifier`, and `.help` usage; no custom accessibility container, focus override, or self-drawn control is introduced.

Architecture: keep semantic identity and enabled-state decisions in the shared main-actor `PrismCommandModel`/`PrismCommandDescriptor`; all command surfaces continue to use `PrismCommandButton`. The shell keeps sidebar selection as a typed `List` binding with `.tag` values, allowing the system list to own keyboard focus and selected-state roles. No Swift/Objective-C++ bridge, QWidget-free facade, backend ownership, task, or fixture data path changed.

Tests and exact commands:

- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO -only-testing:PrismNativeTests/PrismCommandTests -only-testing:PrismNativeTests/PrismShellTests test` — passed; PrismCommandTests 8/8 and PrismShellTests 13/13, 21/21 focused tests.
- `xcodebuild -quiet -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -quiet -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; 53 tests, 0 failures.
- `rg -n 'NavigationSplitView|List\(|selection:|\.tag\(|\.listStyle\(\.sidebar\)|\.toolbar\{|ToolbarItemGroup\(|\.contextMenu\{|PrismCommandButton\(|PrismInstanceContextMenu\(|\.keyboardShortcut\(|\.disabled\(|\.accessibilityLabel\(|\.accessibilityValue\(|\.accessibilityIdentifier\(|\.accessibilityHint\(|\.help\(' macos/PrismNative/App macos/PrismNativeTests` — passed; native shell, toolbar, context-menu, command, accessibility, enabled-state, help, and selection APIs are present.
- `rg -n 'LocalizedStringKey|titleKey|accessibilityLabelKey|accessibilityHintKey|helpKey|Text\(|ContentUnavailableView\(|ProgressView\(' macos/PrismNative/App macos/PrismNativeTests` — passed; visible and accessibility copy retains localization-key-shaped metadata. `if rg --files macos/PrismNative | rg -q 'Localizable\.strings$'; then exit 1; else exit 0; fi` — passed; no resource was added prematurely.
- `if rg -n 'QWidget|QDialog|QtWidgets|QAbstractItemModel|QAbstractListModel|QObject|QModelIndex|std::|#include|Unmanaged|UnsafeMutable|UnsafeRaw' macos/PrismNative --glob '*.swift'; then exit 1; else exit 0; fi` and `if rg -n 'Canvas\(|draw\(|Path\(|Shape|CGContext|NSBezierPath' macos/PrismNative/App --glob '*.swift'; then exit 1; else exit 0; fi` — passed with no forbidden Swift boundary, ownership, Qt/C++, or custom-drawing tokens.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `git diff --check` — passed. No CMake command was required because this unit changes only native SwiftUI source and tests; launcher backend and build configuration were unchanged.

Result summary: the shared command manifest now has stable cross-surface accessibility identity, while focused and full native tests cover labels, localized values, system roles, help, disabled/enabled transitions, shortcut identity, toolbar/context-menu reuse, and List selection/focus semantics. Debug and Release builds, static native API and boundary checks, localization-shape checks, both Bundle ID checks, and diff validation passed. No application or launcher executable was launched; no screenshots, visual snapshots, upstream application data, accounts, Keychain, production services, signing, installation, or publishing state were accessed.

Risk: the command handler still terminates at the injected model callback until later units connect fixture-safe facade mutations; the current context menu remains attached to the detail boundary while native instance rows are a later shell/content unit. The localization resource and runtime accessibility-tree inspection remain later non-launch contracts; system controls own their roles and keyboard focus by design. No custom rendering exception was added.

Commit: `b7d53cf84`

Next after completion: `M4-W7`, add bounded native instance artwork loading as content rather than control chrome.

### M4-W7: Bounded native instance artwork content

Status: complete

Outcome: add a fixture-testable native artwork loader with deterministic count/byte bounds and a system SwiftUI image consumer. Artwork remains instance content and is never used to imitate toolbar, menu, sidebar, or window chrome.

Scope: `macos/PrismNative/App`, directly related native tests/Xcode/project/progress files, and no other platforms. Accept only explicit file URLs supplied by the caller; tests must use temporary fixture files and must not discover or read upstream application data. No backend mutation, bridge contract change, or visual snapshot acceptance.

Required evidence: valid/missing/invalid artwork tests, stable-ID cache hits, deterministic least-recently-used eviction, count and byte limits, oversized-file rejection, ten-times fixture pressure, system `Image` content semantics, accessibility labels, localization shape, Debug/Release builds, native tests, Bundle ID checks, forbidden boundary/drawing checks, and `git diff --check`.

HIG decision: use `NSImage` for file decoding and SwiftUI `Image(nsImage:)`/`resizable`/`scaledToFit` for content only. No Canvas, Core Graphics, custom control, bitmap replica of system chrome, third-party cache, or custom accessibility container is permitted. Apple guidance: [icons](https://developer.apple.com/design/human-interface-guidelines/icons), [images](https://developer.apple.com/design/human-interface-guidelines/images), and [accessibility](https://developer.apple.com/documentation/swiftui/accessibility).

Domain-rendering record required by `PLAN.md` §6.2:

1. User need: instance artwork is user data that identifies an installed instance in the native library; the image itself is the content being presented, not a replacement for an Apple-provided control.
2. Apple APIs investigated: `NSImage(data:)` for AppKit decoding and SwiftUI `Image(nsImage:)`, `resizable`, `scaledToFit`, and accessibility modifiers for presentation; `NSCache` was considered, but deterministic LRU state is required for fixture verification and explicit byte accounting.
3. System-view composition is insufficient for the image payload itself; system `Image` remains sufficient for presentation, so no custom drawing is needed.
4. Accessibility: every rendered artwork view receives a caller-provided localized label; missing artwork has a localized fallback label and never removes the surrounding instance identity.
5. Limits: reject non-file URLs, missing/invalid files, empty files, and files larger than the configured byte budget before decoding; keep at most 32 entries and 8 MiB by default, with deterministic lower limits in tests.
6. Test strategy: use temporary PNG fixture bytes, assert decode/miss/invalid behavior and LRU/count/byte eviction, exercise ten-times fixture volume, and inspect source/API contracts without launching the app or using screenshots.

Files changed: `macos/PrismNative/App/PrismShellModel.swift`, `macos/PrismNative/App/ContentView.swift`, `macos/PrismNativeTests/PrismShellTests.swift`, and this progress file. No Xcode project, bridge, backend, or other-platform file changed because the existing native app/test target membership already covers the modified Swift sources.

Design: add a main-actor `PrismInstanceArtworkStore` that accepts only caller-supplied file URLs, validates file size and `NSImage` decoding, normalizes stable instance IDs, and evicts least-recently-used entries until both count and encoded-byte limits hold. Add `PrismInstanceArtworkView` using system `Image(nsImage:)`, `resizable`, `scaledToFit`, localized accessibility labels, and a localized missing-artwork fallback. No custom drawing or control chrome is introduced.

Architecture: keep artwork state in a Swift-only, main-actor cache seam. The loader does not derive paths, inspect Application Support, call the bridge, or cross into C++/Qt; a later shell/store unit can resolve the bridge's `iconKey` to an explicit fixture-safe file URL and call the store. `removeArtwork` and `removeAll` provide deterministic invalidation for instance updates and lifecycle cleanup.

Tests and exact commands:

- The first focused compile failed with `Covariant 'Self' type cannot be referenced from a default argument expression` for the artwork-store defaults. Source and compiler-log inspection identified the issue; the defaults now reference `PrismInstanceArtworkStore` explicitly, and no blind retry or unrelated change was made.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO -only-testing:PrismNativeTests/PrismShellTests test` — passed; 17/17 focused shell/artwork tests after the evidence-driven correction and final localization-key adjustment.
- `xcodebuild -quiet -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -quiet -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; 57 tests, 0 failures.
- `rg -n 'PrismInstanceArtworkStore|NSImage\(data:|Image\(nsImage:|\.resizable\(\)|\.scaledToFit\(\)|\.fileSizeKey|cachedByteCount|defaultItemLimit|defaultTotalByteLimit|prism\.instance-artwork' macos/PrismNative/App macos/PrismNativeTests` — passed; bounded decoding and system content presentation are explicit.
- `rg -n 'LocalizedStringKey|No Instance Artwork|accessibilityLabelKey|titleKey|Text\(' macos/PrismNative/App/ContentView.swift macos/PrismNative/App/PrismShellModel.swift macos/PrismNativeTests/PrismShellTests.swift` — passed; artwork and fallback accessibility copy retain localization-key shape. `if rg --files macos/PrismNative | rg -q 'Localizable\.strings$'; then exit 1; else exit 0; fi` — passed; no resource was added prematurely.
- `if rg -n 'QWidget|QDialog|QtWidgets|QAbstractItemModel|QAbstractListModel|QObject|QModelIndex|std::|#include|Unmanaged|UnsafeMutable|UnsafeRaw' macos/PrismNative/App --glob '*.swift'; then exit 1; else exit 0; fi`, `if rg -n 'Canvas\(|draw\(|Path\(|Shape|CGContext|NSBezierPath' macos/PrismNative/App --glob '*.swift'; then exit 1; else exit 0; fi`, and `if rg -n 'PrismLauncher|homeDirectoryForCurrentUser|Application Support|URLSession|AsyncImage' macos/PrismNative/App --glob '*.swift'; then exit 1; else exit 0; fi` — passed with no forbidden Swift boundary, ownership, Qt/C++, custom drawing, upstream-data discovery, or implicit network image loading.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `git diff --check` — passed. No CMake command was required because this unit changes only native SwiftUI/AppKit content and fixture tests; launcher backend, bridge, and build configuration were unchanged.

Result summary: native artwork content now has explicit file-boundary validation, valid image decoding, deterministic stable-ID LRU behavior, count/encoded-byte limits, invalidation, 10× fixture pressure coverage, and system SwiftUI presentation/accessibility metadata. Debug and Release builds, full native tests, structural API checks, localization shape, forbidden-boundary/drawing/data scans, Bundle ID checks, and diff validation passed. No application or launcher executable was launched; no screenshots, visual snapshots, upstream application data, accounts, Keychain, production services, signing, installation, or publishing state were accessed.

Risk: the store and view are reusable seams; live `PRInstanceSummary.iconKey` resolution and instance-row integration remain future shell/store work. The cache bounds encoded file bytes and entry count; decoded `NSImage` pixel memory can vary, so a later performance audit may refine pixel-cost accounting without changing the public file-boundary contract. No custom rendering exception was added.

Commit: `33676df3f`

Next after completion: `M5-W1`, add fixture-controlled launch and stop facade commands using stable instance identifiers.

### M5-W1: Fixture-controlled launch and stop facade commands

Status: complete

Outcome: add launch and stop command contracts keyed only by stable instance identifiers across the QWidget-free facade, Objective-C++ bridge, and native command seam. The implementation and verification are complete in commit `fd58b4b40`.

Scope: directly required `launcher/frontend`, `macos/PrismNative/Bridge`, native command/state tests, and this progress file only; no Qt UI composition, other platform behavior, production process, credentials, or real data. Preserve the existing legacy Qt launch path and keep all new runtime ports explicit and injectable.

Required evidence: valid/invalid/unknown stable IDs, launch/stop success and rejection, repeated command behavior, lifecycle/shutdown rejection, Objective-C++ Foundation conversion, Swift command routing, smallest relevant CMake build and C++ tests, native Debug/Release builds, full native tests, Bundle ID checks, bridge/Swift boundary scans, and `git diff --check`.

HIG decision: keep launch and stop as existing menu/toolbar/context command intents backed by the shared Swift command model and SwiftUI `Commands`, `Button`, toolbar, and context-menu surfaces. No new custom control, process UI, or drawing is introduced; task progress and cancellation presentation remain M5-W2/M5-W3 work. This follows the existing [menus](https://developer.apple.com/design/human-interface-guidelines/menus) and [toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) decisions.

Architecture: add `FrontendInstanceCommandResult` with `Succeeded`, `UnknownInstance`, and `Rejected` outcomes. `FrontendFacade` accepts explicit launch/stop callback ports, passes the normalized fixture root and stable identifier without deduplication, rejects empty IDs, rejects post-shutdown work, and returns a deterministic rejection when a command port is not configured. Objective-C++ converts Foundation strings to copied UTF-8 IDs, runs the facade call on its serial backend queue, converts the result to immutable `PRInstanceCommandResult`, delivers completion on the main actor, and cancels the request state during shutdown. Swift receives only `PrismInstanceCommandIntent` with a normalized string ID; if that dedicated handler is absent, the existing generic command handler remains the compatibility path. No process, account, Qt object, QWidget, QDialog, SwiftUI object, or AppKit object is owned by the facade command seam.

Files changed: `launcher/frontend/FrontendFacade.h`, `launcher/frontend/FrontendFacade.cpp`, `launcher/frontend/FrontendFacadeContractTest.cpp`, `launcher/frontend/FrontendFacadePublicHeaderTest.cpp`, `macos/PrismNative/Bridge/PrismBridge.h`, `macos/PrismNative/Bridge/PrismBridgeModels.h`, `macos/PrismNative/Bridge/PrismBridge.mm`, `macos/PrismNativeTests/PrismBridgeFacadeIntegrationTests.mm`, `macos/PrismNative/App/PrismCommandModel.swift`, `macos/PrismNativeTests/PrismCommandTests.swift`, and this progress file.

Tests and exact commands:

- `cmake --build /private/tmp/prism-m3-w6-cmake --target Launcher_frontend Launcher_frontend_contract_test Launcher_frontend_public_header_test --parallel 2` — passed for the arm64 fixture build.
- `ctest --test-dir /private/tmp/prism-m3-w6-cmake --output-on-failure -R '^(FrontendFacadeContract|FrontendFacadePublicHeaders)$'` — passed; 2/2.
- `cmake --build /private/tmp/prism-m3-w6-universal --target Launcher_frontend Launcher_frontend_contract_test Launcher_frontend_public_header_test --parallel 2` — passed with the archive configured for `arm64;x86_64`.
- `file .deriveddata-prism-native-backend/libLauncher_frontend.a && lipo -info .deriveddata-prism-native-backend/libLauncher_frontend.a` — passed; the archive contains arm64 and x86_64 slices.
- `ctest --test-dir /private/tmp/prism-m3-w6-universal --output-on-failure -R '^(FrontendFacadeContract|FrontendFacadePublicHeaders)$'` — passed; 2/2 after the final universal rebuild.
- `cmake --build /private/tmp/prism-m3-w6-cmake --target Prism --parallel 2` — passed in the existing arm64 CMake configuration; the legacy Qt executable target remains buildable without changing its link graph. A separate universal `Prism` link attempt reached the final link but failed only because the pre-existing Qt/libarchive/zlib dependency artifacts have no x86_64 slices; this environment limitation is recorded as non-blocking and was not retried with new dependencies.
- `xcodebuild -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO -only-testing:PrismNativeTests/PrismCommandTests -only-testing:PrismNativeTests/PrismBridgeFacadeIntegrationTests test` — passed; 15/15 focused tests (9 command, 6 bridge-facade).
- The first focused Xcode build failed before tests because the reused backend archive had been rebuilt as arm64-only and the Xcode target also links x86_64. Log inspection showed architecture-mismatch warnings and undefined `FrontendFacade` symbols only for x86_64; rebuilding the explicit universal CMake archive resolved the issue without changing production code.
- `xcodebuild -quiet -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO test` — passed; full native suite, 59/59 tests.
- `xcodebuild -quiet -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native CODE_SIGNING_ALLOWED=NO build` — passed.
- `xcodebuild -quiet -project macos/PrismNative.xcodeproj -scheme PrismNative -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .deriveddata-prism-native-release CODE_SIGNING_ALLOWED=NO build` — passed.
- `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -fsyntax-only -x objective-c -target arm64-apple-macos14.0 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk macos/PrismNative/Bridge/PrismBridge.h` — passed; public bridge headers compile as Objective-C without C++ mode.
- Forbidden public bridge scan for Qt/C++/ownership tokens — passed with no matches. Swift App scan for Qt/C++/ownership tokens — passed with no matches. Swift App scans for `Canvas`, custom drawing, upstream path discovery, and implicit network image loading — passed with no matches. Frontend public-header scan for `launcher/ui` and QWidget/QDialog/model tokens — passed with no matches.
- Command/static API scan for `PRInstanceCommandResult`, launch/stop bridge selectors, `PrismInstanceCommandIntent`, `onInstanceCommand`, `Commands`, and keyboard shortcuts — passed.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `plutil -extract CFBundleIdentifier raw -o - .deriveddata-prism-native-release/Build/Products/Release/Prism.app/Contents/Info.plist` — `com.lloydME.Prism`.
- `git diff --check` — passed.

Result summary: fixture C++ tests cover success, unknown IDs, explicit rejection, missing command ports, invalid IDs, repeated forwarding, root propagation, and post-shutdown rejection. Bridge tests cover copied/trimmed Foundation identifiers, launch and stop result conversion, success/unknown/rejected outcomes, repeated calls, invalid-input error translation, main-thread completion, and shutdown rejection. Swift tests cover stable launch/stop intents, normalized selection IDs, repeated routing, enabled-state gating, and compatibility with the existing generic handler. No application, Minecraft process, screenshot, visual snapshot, upstream application/data, account, Keychain, production service, signing, installation, publishing, or push action was used.

Risk: launch and stop callback ports are still fixture adapters; they do not yet connect `LaunchController`, task progress, cancellation, process state, or account selection. The default bridge composition has no command ports and therefore reports explicit rejection. The universal legacy Qt link remains environment-limited by pre-existing arm64-only third-party artifacts, while the arm64 Qt target and native universal target both build. M5-W2 must add task progress, subtasks, cancellation, and terminal result DTOs.

Commit: `fd58b4b40`

Next after completion: `M5-W2`, add task progress, subtasks, cancellation, and terminal result DTOs.

### M5-W2: Task progress, subtasks, cancellation, and terminal result DTOs

Status: active

Outcome: activated after M5-W1. Add deterministic task-state, subtask, cancellation, and terminal-result contracts across the QWidget-free facade, Objective-C++ bridge, and native state seam without starting processes or accessing production task data.

Scope: directly required `launcher/frontend`, `macos/PrismNative/Bridge`, native task/state tests, and this progress file only. Preserve explicit fixture roots and injected runtime ports; do not change Qt UI composition, other platforms, authentication, or process ownership.

Required evidence: immutable task snapshots, stable task and subtask identifiers, determinate and indeterminate progress, cancellation eligibility and idempotence, terminal success/failure/cancelled results, error and recovery metadata, callback delivery and shutdown behavior, smallest relevant CMake build and C++ tests, native Debug/Release builds, full native tests, Bundle ID checks, bridge/Swift boundary scans, localization/accessibility checks, and `git diff --check`.

HIG decision: represent task state with native `ProgressView`/standard progress semantics and existing command/state surfaces; no custom progress control, drawing, or process UI is introduced. Cancellation remains an explicit command capability and must be exposed through the shared command model and standard button/menu affordances in later feature work.

Architecture: keep task and subtask data immutable and Foundation-only at the bridge boundary. Objective-C++ owns C++ task lifetime, cancellation tokens, conversion, error translation, and main-actor delivery; Swift receives state and intents only. The fixture backend must make every transition deterministic and must not connect to `LaunchController`, real processes, accounts, or upstream data until a later work unit explicitly adds the required contract.

Files changed: not started; activation record only.

Commit: pending implementation.

Next after completion: `M5-W3`, map task state to `ProgressView` or `NSProgressIndicator` semantics.

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
| `7bfb98353` | Preserved the Qt Prism executable link and facade independence with configure-time assertions | Qt composition configure contract; facade/public-header and selected C++ tests 6/6; existing Prism target; native Debug/Release builds; 6 native tests; Debug/Release `plutil`; Ninja link inspection; `git diff --check` |
| `17258dae9` | Added the Foundation-only Objective-C++ lifecycle root with explicit fixture data and callback release contracts | Native Debug XCTest 9/9; Debug/Release builds; Objective-C public-header syntax; forbidden bridge scan; Debug/Release `plutil`; `git diff --check` |
| `65a044abe` | Added immutable Foundation instance and task DTOs with progress and cancellation contracts | Native Debug XCTest 11/11; Debug/Release builds; Objective-C public-header syntax; forbidden bridge and Swift boundary scans; Debug/Release `plutil`; `git diff --check` |
| `cacd8d16f` | Added Foundation observation handlers and cancellable tokens with fixture delivery and release contracts | Native Debug XCTest 17/17; Debug/Release builds; Objective-C public-header syntax; forbidden bridge and Swift boundary scans; Debug/Release `plutil`; `git diff --check` |
| `a9853cbe2` | Added stable Foundation error translation and asynchronous main-actor observation delivery | Native Debug XCTest 20/20; Debug/Release builds; Objective-C public-header syntax; forbidden bridge and Swift boundary scans; Debug/Release `plutil`; `git diff --check` |
| `6711968f7` | Added dedicated native bridge contract coverage for fixture initialization, empty state, immutable snapshots, cancellation, shutdown, released observers, and errors | Native Debug XCTest 27/27; Debug/Release builds; Objective-C public-header syntax; forbidden bridge and Swift boundary scans; Debug/Release `plutil`; `git diff --check` |
| `4f3d62c21` | Linked the real QWidget-free frontend facade into the Objective-C++ bridge and converted fixture snapshots, changes, lifecycle, cancellation, and errors | CMake facade/Prism targets; selected C++ tests 6/6; universal facade tests 2/2; native Debug XCTest 32/32; Debug/Release builds; public-header and Swift-boundary scans; Debug/Release `plutil`; `git diff --check` |
| `127ab52b7` | Added the native command manifest, main-actor command model, SwiftUI menu groups, system shortcuts, enabled-state routing, and accessibility/help metadata | Focused command tests 5/5; native Debug XCTest 37/37; Debug/Release builds; command/accessibility and forbidden API scans; Debug/Release `plutil`; `git diff --check` |
| `b6007523e` | Added the native NavigationSplitView shell, sidebar selection model, detail loading/empty/content states, and accessibility metadata | Focused shell tests 5/5; native Debug XCTest 42/42; Debug/Release builds; shell API and Swift-boundary scans; Debug/Release `plutil`; `git diff --check` |
| `1774904a8` | Added stable instance collection state for selection, grouping, sorting, search, deterministic sections, and ten-times fixture coverage | Focused shell-state tests 11/11; native Debug XCTest 48/48; Debug/Release builds; search/selection/accessibility/localization-shape and forbidden API scans; Debug/Release `plutil`; `git diff --check` |
| `19490eac9` | Added explicit native loading, empty, failed, and content states with deterministic retry recovery metadata | Focused shell-state tests 12/12; native Debug XCTest 49/49; Debug/Release builds; state/accessibility/localization-shape and forbidden API scans; Debug/Release `plutil`; `git diff --check` |
| `d5249dd8a` | Routed native toolbar and detail context-menu actions through the shared command model and system command button | Focused command tests 7/7; native Debug XCTest 51/51; Debug/Release builds; toolbar/context-menu, shortcut/accessibility, localization-shape, and forbidden API scans; Debug/Release `plutil`; `git diff --check` |
| `b7d53cf84` | Hardened cross-surface accessibility identity, localized values, enabled-state, shortcut, and List selection/focus contracts | Focused command and shell tests 21/21; native Debug XCTest 53/53; Debug/Release builds; native API, localization-shape, boundary, no-drawing, Debug/Release `plutil`, and `git diff --check` validations |
| `33676df3f` | Added bounded native instance artwork decoding, deterministic LRU caching, invalidation, and SwiftUI content presentation | Focused artwork/Shell tests 17/17; native Debug XCTest 57/57; Debug/Release builds; artwork/localization, boundary, no-drawing, upstream-data, Debug/Release `plutil`, and `git diff --check` validations |

| `fd58b4b40` | Added fixture-controlled launch and stop commands with stable identifiers, explicit outcomes, cancellation, and main-actor bridge delivery | CMake facade tests 2/2; focused native command/bridge tests 15/15; full native tests 59/59; arm64 legacy Prism target; Debug/Release builds; public boundary, command, localization-shape, Bundle ID, and `git diff --check` validations |

## Current architecture findings

1. Prism currently builds `Launcher_logic` as a monolithic static library containing both domain and Qt UI sources.
2. `Application` derives from `QApplication` and exposes global application state.
3. `InstanceList` and `AccountList` derive from Qt list models.
4. `LaunchController` derives from the existing task system.
5. The native Xcode target links only the QWidget-free `Launcher_frontend` archive from ignored local build output; it does not copy launcher implementation sources into the app target.
6. The first backend task is separation and characterization, not Swift reimplementation.
7. M2-W1 keeps the existing Qt composition in `Launcher_logic` while exposing domain, UI, application, and executable-entry source ownership for the upcoming facade target.
8. M2-W2 is the first independent `launcher/frontend` target; it must remain compilable without `launcher/ui` and must not alter the existing Qt target's link graph.
9. M2-W2's facade root is deliberately inert; M2-W3 owns the first explicit data-root and runtime-dependency contract.
10. The native facade must receive an absolute data root and injected runtime ports rather than deriving paths from `Application`, process arguments, environment variables, or global Qt application state.
11. M2-W3 normalizes the root lexically and rejects invalid construction before any service work; filesystem mutation and backend instance loading remain separate contracts.
12. M2-W4 exposes snapshots and ordered instance-change values through loader ports; `InstanceList` remains an internal legacy model and cannot cross the facade boundary.
13. M2-W5 makes lifecycle ownership explicit: cancellation and release callbacks run once during `ShuttingDown`, injected ports are cleared at `Stopped`, and post-stop facade work is rejected without touching loaders.
14. M2-W6 makes the facade public-header boundary executable: the current header list is compiled by a standalone no-link target, while forbidden Qt/UI tokens remain absent from the public surface.
15. M2-W7 protects the legacy Qt composition with configure-time link assertions: `Prism` continues through `Launcher_logic`, which retains Qt Widgets, while the separate native target consumes `Launcher_frontend` without changing that Qt link graph.
16. M3-W1 added an explicit normalized fixture-root `PRPrismBridge`; its private Objective-C++ implementation owns lifecycle state and callback lifetime, and M3-W6 now supplies the real `FrontendFacade` link.
17. M3-W2 adds Foundation-only immutable `PRInstanceSummary` and `PRTaskStatus` contracts; DTO validation and copying remain private to Objective-C++, while backend conversion and task error translation remain later bridge work.
18. M3-W3 adds typed Foundation observation handlers and private cancellation states; token release removes callbacks deterministically, while main-actor delivery and real facade event wiring remain later bridge work.
19. M3-W4 adds Foundation error translation and structured `NSError` metadata, while main-queue delivery is asynchronous and cancellation-aware; real facade failure mapping and Swift `@MainActor` feature state remain later work.
20. M3-W5 added a dedicated bridge contract suite for temporary-root initialization, empty and fixture snapshots, cancellation, shutdown ordering, released observers, and stable error propagation; M3-W6 extends those contracts through the linked facade.
21. M3-W6 completes the Milestone 3 boundary: the Objective-C++ bridge consumes the existing QWidget-free `Launcher_frontend` target and keeps the Swift-facing bridge free of Qt, C++, and ownership types.
22. M3-W6 proves the linker boundary without source copying: Xcode consumes the ignored universal `libLauncher_frontend.a` through `-lLauncher_frontend`, while `PRPrismBridge` alone owns `FrontendFacade` and converts C++ values into Foundation DTOs; the existing Qt `Prism` link remains unchanged and the public bridge/Swift surfaces remain free of Qt and C++.
23. M4-W1 centralizes native shell actions in a main-actor command manifest; SwiftUI `Commands` consumes the same descriptors for menu placement, shortcuts, enabled state, accessibility labels, and help, while future toolbar and contextual actions must route through the same model.
24. M4-W2 replaces the placeholder hierarchy with a system `NavigationSplitView` and sidebar `List`; `PrismShellModel` keeps sidebar selection and detail loading/empty/content states testable without backend mutations, search, grouping, or custom chrome.
25. M4-W3 keeps instance collection behavior in a main-actor Swift state seam: immutable stable-ID rows feed deterministic search, grouping, sorting, and section identity, while `ContentView` uses system `.searchable` and the existing selection metadata without introducing custom cells or backend mutations.
26. M4-W4 keeps failure presentation in the main-actor Swift state seam: stable Foundation-only failure/recovery metadata drives system `ContentUnavailableView` actions, while retry remains an injected intent and no asynchronous or backend ownership crosses into the view.
27. M4-W5 routes app menus, toolbar buttons, and the detail context menu through one `PrismCommandButton`/`PrismCommandModel` invocation path; shortcut mapping is compiled in the shared command-model source so app and test targets have the same contract.
28. M4-W6 gives every shared command a stable accessibility identifier and validates it across menus, toolbar, and context-menu surfaces; sidebar rows use localized values and typed `List(selection:)`/`.tag` semantics so system accessibility roles and keyboard focus remain native rather than manually recreated.
29. M4-W7 keeps instance artwork behind an explicit file-URL input and a main-actor deterministic LRU store with 32-entry/8 MiB defaults; SwiftUI `Image` owns presentation and accessibility, while bridge icon-key resolution and live row integration remain downstream of this isolated content seam.
30. M5-W1 adds explicit launch and stop callback ports with stable-ID result outcomes; the Objective-C++ bridge copies Foundation identifiers, serializes facade calls, owns cancellation and main-actor delivery, and the Swift command model preserves a generic-handler compatibility path. The default composition intentionally rejects commands until task/process wiring is introduced.

## Custom rendering exceptions

No exception is approved.

Minecraft skin preview is a candidate only. It requires the complete exception record from `PLAN.md` before implementation.

## Blockers

No current blocker.

## Resume instructions

Read `PLAN.md`, run `git status --short --branch -uall`, inspect the last five commits, then activate only ready `M5-W2`. Do not begin M5-W3 or later task/progress implementation until immutable task and subtask DTOs, cancellation, terminal results, and their bridge/facade tests are verified and committed.

# Prism macOS Native Migration Progress

Last updated: 2026-08-04

Branch: `macos-native`

Plan: `docs/macos-native-migration/PLAN.md`

Current milestone: Milestone 1, contracts, tests, and durable inventory

Active work unit: none

Next ready work unit: `M1-W2`

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

Commit: pending; record the exact hash in the next ledger update after commit creation.

Next after completion: `M1-W2`, inventory every legacy UI family and map it to facade capabilities and native destination.

### M1-W2: Complete legacy feature inventory

Status: ready

Outcome: expand this ledger so every source family under `launcher/ui` has a native destination, backend owner, verification class, and migration milestone.

Required evidence: repository source scan, no unclassified dialog or page, `git diff --check`.

Commit: not created.

### M1-W3: Bridge boundary and fixture infrastructure

Status: queued

Outcome: automate the public bridge-header scan and provide temporary-root, callback, cancellation, and fixture helpers for later milestones.

Required evidence: native tests pass, forbidden-type scan has a negative test, fixture root cannot resolve to the upstream Application Support path.

Commit: not created.

## Completed commit index

| Commit | Outcome | Verification |
| --- | --- | --- |
| `6de92da18` | Isolated macOS fork identity and ignored local dependencies | CMake configuration and Qt baseline build; generated Info.plist Bundle ID check |
| `5172b3a75` | Added SwiftUI Xcode target and Objective-C++ bridge scaffold | arm64 Debug build; generated Info.plist Bundle ID check; architecture review |

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

Read `PLAN.md`, run `git status --short --branch -uall`, inspect the last five commits, then start only `M1-W1`. Do not begin backend extraction or visual design until `M1-W1` is committed and this ledger is updated.

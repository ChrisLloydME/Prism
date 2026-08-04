# Prism macOS Native Migration Progress

Last updated: 2026-08-04

Branch: `macos-native`

Plan: `docs/macos-native-migration/PLAN.md`

Current milestone: Milestone 1, contracts, tests, and durable inventory

Active work unit: none

Next ready work unit: `M1-W1`

## Safety baseline

| Contract | Status | Evidence |
| --- | --- | --- |
| Bundle ID is `com.lloydME.Prism` | complete | Commit `6de92da18`; built Info.plist checked with `plutil` |
| Native product name is `Prism` | complete | Commit `6de92da18`; built Info.plist checked with `plutil` |
| Default data identity differs from upstream `PrismLauncher` | complete, not yet automated | `Prism` application identity in `program_info/CMakeLists.txt` and native bridge |
| Native Xcode target exists | complete | Commit `5172b3a75` |
| Objective-C++ public bridge exposes only Foundation types | complete, not yet automated | Commit `5172b3a75`; architecture review found no Qt or C++ type in public header |
| Native tests target exists | ready | First work unit `M1-W1` |
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

Status: ready

Outcome: add a stable shared `PrismNative` scheme and a `PrismNativeTests` target covering Bundle ID and data-root isolation without launching the app.

Required files: Xcode project and shared scheme, `macos/PrismNativeTests`, directly related test helpers, this progress file.

Required evidence: Debug build, native tests, `git diff --check`, Info.plist Bundle ID check.

HIG decision: none, this unit protects product identity and test infrastructure.

Risk: Xcode target settings and the bridge currently hold related identity concepts in different build systems. Tests must detect drift.

Commit: not created.

Next after completion: `M1-W2`, inventory every legacy UI family and map it to facade capabilities and native destination.

### M1-W2: Complete legacy feature inventory

Status: queued

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

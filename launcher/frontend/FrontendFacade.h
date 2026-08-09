// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <functional>
#include <optional>
#include <string>
#include <utility>
#include <vector>

struct FrontendInstanceSnapshot final {
    std::string id;
    std::string name;
    std::string iconKey;
    std::string groupId;

    bool hasStableIdentifier() const noexcept { return !id.empty(); }
};

/// Immutable instance metadata and notes for the native detail surface.
/// Paths, Qt objects, and settings ownership remain outside this value type.
struct FrontendInstanceDetailsSnapshot final {
    std::string id;
    std::string name;
    std::string iconKey;
    std::string groupId;
    std::string instanceType;
    std::string notes;
    bool notesEditable = true;

    bool hasStableIdentifier() const noexcept { return !id.empty(); }
};

enum class FrontendInstanceComponentProblemSeverity : std::uint8_t { None, Warning, Error };

/// Ordered, immutable component data for the native instance version list.
/// The order is meaningful to PackProfile and must be preserved by adapters.
/// File paths, Qt models, and component ownership remain outside this value.
struct FrontendInstanceComponentSnapshot final {
    std::string id;
    std::string name;
    std::string version;
    bool enabled = true;
    bool canBeDisabled = false;
    bool dependencyOnly = false;
    bool important = false;
    bool custom = false;
    FrontendInstanceComponentProblemSeverity problemSeverity = FrontendInstanceComponentProblemSeverity::None;
    std::vector<std::string> problemDescriptions;

    bool hasStableIdentifier() const noexcept { return !id.empty(); }
};

enum class FrontendInstanceResourceKind : std::uint8_t {
    Mods,
    ResourcePacks,
    ShaderPacks,
    TexturePacks,
    DataPacks,
};

enum class FrontendInstanceResourceAction : std::uint8_t { Enable, Disable, Delete, Import, Reveal };

enum class FrontendInstanceResourceMutationOutcome : std::uint8_t {
    Succeeded,
    UnknownInstance,
    UnknownResource,
    Rejected,
    Failed,
};

/// Ordered, immutable external-resource data for the native mods and packs list.
/// Resource paths and model ownership remain in the injected runtime ports.
struct FrontendInstanceResourceSnapshot final {
    std::string id;
    std::string name;
    std::string version;
    std::string fileName;
    std::string provider;
    FrontendInstanceResourceKind kind = FrontendInstanceResourceKind::Mods;
    bool enabled = true;
    bool canBeToggled = true;
    bool canBeDeleted = true;
    bool isDirectory = false;
    bool hasMetadata = false;
    std::vector<std::string> problemDescriptions;

    bool hasStableIdentifier() const noexcept { return !id.empty(); }
};

/// Explicit native resource intent. Delete requires `confirmed`; import requires
/// an absolute source path selected by a system file panel or drop operation.
struct FrontendInstanceResourceMutationRequest final {
    FrontendInstanceResourceAction action = FrontendInstanceResourceAction::Reveal;
    std::string resourceIdentifier;
    std::filesystem::path sourcePath;
    bool confirmed = false;
};

/// Confirmed result for one resource intent. A successful mutation is not an
/// optimistic Swift edit; the native state reloads a confirmed list afterward.
struct FrontendInstanceResourceMutationResult final {
    FrontendInstanceResourceKind kind = FrontendInstanceResourceKind::Mods;
    FrontendInstanceResourceAction action = FrontendInstanceResourceAction::Reveal;
    FrontendInstanceResourceMutationOutcome outcome = FrontendInstanceResourceMutationOutcome::Rejected;
    std::string instanceIdentifier;
    std::string resourceIdentifier;
    std::string localizationKey;
    std::string diagnosticText;
    bool partialChangesRolledBack = false;
};

enum class FrontendInstanceDetailKind : std::uint8_t { Worlds, Servers, Screenshots, Logs };

enum class FrontendInstanceDetailAction : std::uint8_t {
    Add,
    Update,
    Delete,
    MoveUp,
    MoveDown,
    Import,
    Copy,
    Rename,
    Reveal,
    ResetIcon,
    Join,
    Refresh,
    Open,
    CopyImage,
    CopyFiles,
};

enum class FrontendInstanceDetailMutationOutcome : std::uint8_t {
    Succeeded,
    UnknownInstance,
    UnknownItem,
    Rejected,
    Failed,
};

/// Ordered world data for the native instance world list. Timestamps are
/// Unix seconds and sizes are raw bytes; formatting remains a Swift concern.
struct FrontendInstanceWorldSnapshot final {
    std::string id;
    std::string name;
    std::string folderName;
    std::string gameMode;
    std::string iconKey;
    std::string warningDescription;
    std::int64_t lastPlayedUnixSeconds = 0;
    std::uint64_t sizeBytes = 0;
    std::int64_t seed = 0;
    bool hasSeed = false;
    bool isArchive = false;
    bool canBeRenamed = true;
    bool canBeCopied = true;
    bool canBeDeleted = true;
    bool canBeJoined = false;
    bool hasIcon = false;

    bool hasStableIdentifier() const noexcept { return !id.empty(); }
};

enum class FrontendServerResourcePolicy : std::uint8_t { Ask, Always, Never };
enum class FrontendServerStatus : std::uint8_t { Unknown, Online, Offline, Failed };

/// Ordered server-list data. Server icons remain an adapter concern until a
/// native image contract is needed; the list itself exposes only safe text.
struct FrontendInstanceServerSnapshot final {
    std::string id;
    std::string name;
    std::string address;
    FrontendServerResourcePolicy resourcePolicy = FrontendServerResourcePolicy::Ask;
    FrontendServerStatus status = FrontendServerStatus::Unknown;
    std::int64_t onlinePlayers = -1;
    bool canBeEdited = true;
    bool canBeDeleted = true;
    bool canBeJoined = false;

    bool hasStableIdentifier() const noexcept { return !id.empty(); }
};

/// Screenshot file metadata. Image bytes are intentionally not copied into a
/// list snapshot; system file/image actions remain explicit adapter requests.
struct FrontendInstanceScreenshotSnapshot final {
    std::string id;
    std::string fileName;
    std::string displayName;
    std::int64_t modifiedUnixSeconds = 0;
    std::uint64_t sizeBytes = 0;
    bool readable = false;
    bool writable = false;

    bool hasStableIdentifier() const noexcept { return !id.empty(); }
};

/// Historical or current log-file metadata. Content is loaded separately so
/// a large log cannot be forced through a list snapshot.
struct FrontendInstanceLogFileSnapshot final {
    std::string id;
    std::string fileName;
    std::string displayName;
    std::int64_t modifiedUnixSeconds = 0;
    std::uint64_t sizeBytes = 0;
    bool compressed = false;
    bool current = false;
    bool readable = false;
    bool canBeDeleted = false;

    bool hasStableIdentifier() const noexcept { return !id.empty(); }
};

/// One explicit action across the four M6-W5 lists. Fields are interpreted by
/// action: import uses sourcePath; copy/rename/update use targetName/name/
/// address; delete requires confirmed; position is used by server moves.
struct FrontendInstanceDetailMutationRequest final {
    FrontendInstanceDetailKind kind = FrontendInstanceDetailKind::Worlds;
    FrontendInstanceDetailAction action = FrontendInstanceDetailAction::Reveal;
    std::string itemIdentifier;
    std::filesystem::path sourcePath;
    std::string targetName;
    std::string name;
    std::string address;
    FrontendServerResourcePolicy resourcePolicy = FrontendServerResourcePolicy::Ask;
    bool confirmed = false;
    int position = -1;
};

struct FrontendInstanceDetailMutationResult final {
    FrontendInstanceDetailKind kind = FrontendInstanceDetailKind::Worlds;
    FrontendInstanceDetailAction action = FrontendInstanceDetailAction::Reveal;
    FrontendInstanceDetailMutationOutcome outcome = FrontendInstanceDetailMutationOutcome::Rejected;
    std::string instanceIdentifier;
    std::string itemIdentifier;
    std::string localizationKey;
    std::string diagnosticText;
    bool partialChangesRolledBack = false;
};

enum class FrontendInstanceChangeKind : std::uint8_t { Added, Updated, Removed };

enum class FrontendLifecycleState : std::uint8_t { Running, ShuttingDown, Stopped };

enum class FrontendInstanceCommandResult : std::uint8_t { Succeeded, UnknownInstance, Rejected };

enum class FrontendInstanceNotesUpdateOutcome : std::uint8_t { Succeeded, UnknownInstance, Rejected };

struct FrontendInstanceNotesUpdateResult final {
    FrontendInstanceNotesUpdateOutcome outcome = FrontendInstanceNotesUpdateOutcome::Rejected;
    std::string notes;
};

enum class FrontendInstanceJoinTarget : std::uint8_t { None, Server, World };

/// Confirmed, non-secret instance settings for the native settings form.
/// Account selection and environment-variable values deliberately stay out of
/// this value contract until their dedicated security/identity workflows are
/// migrated.
struct FrontendInstanceSettingsSnapshot final {
    std::string id;

    bool windowOverrideEnabled = false;
    bool launchMaximized = false;
    int windowWidth = 854;
    int windowHeight = 480;
    bool closeAfterLaunch = false;
    bool quitAfterGameStop = false;

    bool consoleOverrideEnabled = false;
    bool showConsole = false;
    bool showConsoleOnError = true;
    bool autoCloseConsole = false;

    bool globalDataPacksEnabled = false;
    std::string globalDataPacksPath;

    bool gameTimeOverrideEnabled = false;
    bool showGameTime = false;
    bool recordGameTime = false;
    bool countGameTime = true;

    bool joinServerOnLaunch = false;
    FrontendInstanceJoinTarget joinTarget = FrontendInstanceJoinTarget::None;
    std::string joinServerAddress;
    std::string joinWorld;

    bool overrideModDownloadLoaders = false;
    std::vector<std::string> modDownloadLoaders;

    bool javaLocationOverrideEnabled = false;
    std::string javaPath;
    bool ignoreJavaCompatibility = false;

    bool memoryOverrideEnabled = false;
    int minMemoryMiB = 512;
    int maxMemoryMiB = 1024;
    int permGenMiB = 128;
    bool lowMemoryWarning = true;

    bool javaArgumentsOverrideEnabled = false;
    std::string jvmArguments;

    bool commandOverrideEnabled = false;
    std::string preLaunchCommand;
    std::string wrapperCommand;
    std::string postExitCommand;

    bool legacySettingsOverrideEnabled = false;
    bool onlineFixes = false;

    bool nativeWorkaroundsOverrideEnabled = false;
    bool useNativeGLFW = false;
    std::string customGLFWPath;
    bool useNativeOpenAL = false;
    std::string customOpenALPath;

    bool hasStableIdentifier() const noexcept { return !id.empty(); }
};

enum class FrontendInstanceSettingsUpdateOutcome : std::uint8_t { Succeeded, UnknownInstance, Rejected };

struct FrontendInstanceSettingsUpdateResult final {
    FrontendInstanceSettingsUpdateOutcome outcome = FrontendInstanceSettingsUpdateOutcome::Rejected;
    std::optional<FrontendInstanceSettingsSnapshot> settings;
};

/// Confirmed, non-secret global settings for the native macOS Settings scene.
/// Directory access is represented by one normalized absolute path owned by an
/// injected adapter; bookmark bytes, account state, environment values,
/// commands, and provider credentials are deliberately absent.
struct FrontendGlobalSettingsSnapshot final {
    std::filesystem::path instanceDirectory;
    std::string iconTheme;
    std::string applicationTheme;
    std::string backgroundCat;
    int catOpacity = 100;
    std::string catFit = "fit";
    std::string language;
    bool useSystemLocale = false;
    bool menuBarInsteadOfToolBar = false;
    bool statusBarVisible = true;
    bool toolbarsLocked = false;
    int numberOfConcurrentTasks = 10;
    int numberOfConcurrentDownloads = 6;
    int numberOfManualRetries = 1;
    int requestTimeoutSeconds = 60;
    std::string consoleFont;
    int consoleFontSize = 11;
    int consoleMaxLines = 100000;
    bool consoleOverflowStop = true;
    bool showConsole = false;
    bool autoCloseConsole = false;
    bool showConsoleOnError = true;
    bool logPrePostOutput = true;
};

enum class FrontendGlobalSettingsUpdateOutcome : std::uint8_t { Succeeded, Rejected };

struct FrontendGlobalSettingsUpdateResult final {
    FrontendGlobalSettingsUpdateOutcome outcome = FrontendGlobalSettingsUpdateOutcome::Rejected;
    std::optional<FrontendGlobalSettingsSnapshot> settings;
};

enum class FrontendJavaInstallationValidity : std::uint8_t { Valid, Incompatible, Unavailable };

/// Immutable Java discovery row. The adapter owns process execution and path
/// probing; this value contains only sanitized labels and a display path.
struct FrontendJavaInstallationSnapshot final {
    std::string id;
    std::string version;
    std::string vendor;
    std::string architecture;
    std::filesystem::path executablePath;
    bool is64Bit = false;
    bool managed = false;
    FrontendJavaInstallationValidity validity = FrontendJavaInstallationValidity::Valid;
    std::string diagnosticText;

    bool hasStableIdentifier() const noexcept { return !id.empty(); }
};

enum class FrontendJavaDiscoveryOutcome : std::uint8_t { Succeeded, Failed, Cancelled, Rejected };

/// Confirmed result of one discovery operation. Raw Java stdout/stderr and
/// process ownership deliberately remain outside the native contract.
struct FrontendJavaDiscoveryResult final {
    FrontendJavaDiscoveryOutcome outcome = FrontendJavaDiscoveryOutcome::Rejected;
    std::vector<FrontendJavaInstallationSnapshot> installations;
    std::string localizationKey;
    std::string diagnosticText;
    bool retryable = false;
};

enum class FrontendJavaSelectionOutcome : std::uint8_t { Succeeded, UnknownInstallation, Rejected };

struct FrontendJavaSelectionResult final {
    FrontendJavaSelectionOutcome outcome = FrontendJavaSelectionOutcome::Rejected;
    std::optional<FrontendJavaInstallationSnapshot> installation;
    std::string localizationKey;
    std::string diagnosticText;
};

enum class FrontendAccountType : std::uint8_t { Microsoft, Offline };
enum class FrontendAccountState : std::uint8_t {
    Unchecked,
    Offline,
    Working,
    Online,
    Disabled,
    Errored,
    Expired,
    Gone,
};

/// Immutable, non-secret account metadata for native account selection.
/// Provider-owned authentication state, credentials, profile payloads, and
/// persistence remain outside this value contract.
struct FrontendAccountSnapshot final {
    std::string id;
    std::string displayName;
    FrontendAccountType type = FrontendAccountType::Microsoft;
    FrontendAccountState state = FrontendAccountState::Unchecked;
    bool ownsMinecraft = false;
    bool isBusy = false;
    bool canBeSelected = true;
    std::string diagnosticText;

    bool hasStableIdentifier() const noexcept { return !id.empty(); }
};

enum class FrontendAccountSnapshotOutcome : std::uint8_t { Succeeded, Failed, Cancelled, Rejected };

/// Confirmed result of one account snapshot load. The optional active
/// identifier maps the legacy default account; it does not describe a live
/// authentication task.
struct FrontendAccountSnapshotResult final {
    FrontendAccountSnapshotOutcome outcome = FrontendAccountSnapshotOutcome::Rejected;
    std::vector<FrontendAccountSnapshot> accounts;
    std::optional<std::string> activeAccountIdentifier;
    std::string localizationKey;
    std::string diagnosticText;
    bool retryable = false;
};

enum class FrontendAccountSelectionOutcome : std::uint8_t { Succeeded, UnknownAccount, Rejected };

/// Confirmed result of selecting or clearing the legacy default account.
/// A successful clear has no account value.
struct FrontendAccountSelectionResult final {
    FrontendAccountSelectionOutcome outcome = FrontendAccountSelectionOutcome::Rejected;
    std::optional<FrontendAccountSnapshot> account;
    std::string localizationKey;
    std::string diagnosticText;
};

enum class FrontendAccountAuthenticationAction : std::uint8_t { Login, Refresh };
enum class FrontendAccountAuthenticationPhase : std::uint8_t {
    Preparing,
    AwaitingUser,
    Authenticating,
    Succeeded,
    Failed,
    Cancelled,
};
enum class FrontendAccountAuthenticationOutcome : std::uint8_t { InProgress, Succeeded, Failed, Cancelled, Rejected };

/// Explicit, non-secret authentication request. The adapter owns all
/// provider credentials, authorization codes, tokens, profiles, and network
/// state; this identifier is only a sanitized fixture/runtime key.
struct FrontendAccountAuthenticationRequest final {
    std::string accountIdentifier;
    FrontendAccountAuthenticationAction action = FrontendAccountAuthenticationAction::Login;
};

/// One ordered authentication progress event. Device-code presentation is
/// intentionally limited to a safe verification URL and instruction state;
/// user codes, authorization codes, bearer tokens, and refresh tokens never
/// cross this contract.
struct FrontendAccountAuthenticationProgress final {
    std::string accountIdentifier;
    FrontendAccountAuthenticationAction action = FrontendAccountAuthenticationAction::Login;
    FrontendAccountAuthenticationPhase phase = FrontendAccountAuthenticationPhase::Preparing;
    FrontendAccountAuthenticationOutcome outcome = FrontendAccountAuthenticationOutcome::InProgress;
    std::string providerLabel;
    std::string verificationURL;
    std::string localizationKey;
    std::string diagnosticText;
    std::int32_t expiresInSeconds = 0;
    bool canCancel = true;
    bool retryable = false;
    bool requiresUserAction = false;

    bool isTerminal() const noexcept { return outcome != FrontendAccountAuthenticationOutcome::InProgress; }
};

/// Confirmed authentication result. A successful result carries only the
/// refreshed non-secret account snapshot, never provider-owned auth material.
struct FrontendAccountAuthenticationResult final {
    FrontendAccountAuthenticationOutcome outcome = FrontendAccountAuthenticationOutcome::Rejected;
    std::optional<FrontendAccountSnapshot> account;
    std::string localizationKey;
    std::string diagnosticText;
    bool retryable = false;
};

enum class FrontendOfflineLaunchIdentityMode : std::uint8_t { Offline, Demo };
enum class FrontendOfflineLaunchIdentityLoadOutcome : std::uint8_t { Succeeded, Failed, Cancelled, Rejected };
enum class FrontendOfflineLaunchIdentityUpdateOutcome : std::uint8_t {
    Succeeded,
    InvalidName,
    Failed,
    Cancelled,
    Rejected,
};

/// Safe offline-launch identity context. The adapter owns LastOfflinePlayerName
/// persistence and launch-session/UUID derivation; this value carries only a
/// fixture-safe account key and user-visible fallback name.
struct FrontendOfflineLaunchIdentityRequest final {
    FrontendOfflineLaunchIdentityMode mode = FrontendOfflineLaunchIdentityMode::Offline;
    std::optional<std::string> accountIdentifier;
    std::string fallbackName;
};

/// Confirmed offline-launch identity. The name is user input, not an account
/// credential; the adapter remains responsible for backend compatibility.
struct FrontendOfflineLaunchIdentitySnapshot final {
    FrontendOfflineLaunchIdentityMode mode = FrontendOfflineLaunchIdentityMode::Offline;
    std::optional<std::string> accountIdentifier;
    std::string name;
};

struct FrontendOfflineLaunchIdentityLoadResult final {
    FrontendOfflineLaunchIdentityLoadOutcome outcome = FrontendOfflineLaunchIdentityLoadOutcome::Rejected;
    std::optional<FrontendOfflineLaunchIdentitySnapshot> identity;
    std::string localizationKey;
    std::string diagnosticText;
    bool retryable = false;
};

struct FrontendOfflineLaunchIdentityUpdateRequest final {
    FrontendOfflineLaunchIdentityMode mode = FrontendOfflineLaunchIdentityMode::Offline;
    std::optional<std::string> accountIdentifier;
    std::string name;
    bool allowInvalidName = false;
};

struct FrontendOfflineLaunchIdentityUpdateResult final {
    FrontendOfflineLaunchIdentityUpdateOutcome outcome = FrontendOfflineLaunchIdentityUpdateOutcome::Rejected;
    std::optional<FrontendOfflineLaunchIdentitySnapshot> identity;
    std::string localizationKey;
    std::string diagnosticText;
    bool retryable = false;
};

enum class FrontendTaskState : std::uint8_t { Queued, Running, Cancelling, Succeeded, Failed, Cancelled };

enum class FrontendTaskProgressKind : std::uint8_t { None, Indeterminate, Determinate };

enum class FrontendTaskTerminalOutcome : std::uint8_t { Succeeded, Failed, Cancelled };

enum class FrontendTaskCancellationResult : std::uint8_t { Requested, AlreadyTerminal, UnknownTask, Rejected };

struct FrontendInstanceChange final {
    FrontendInstanceChangeKind kind = FrontendInstanceChangeKind::Updated;
    FrontendInstanceSnapshot instance;
};

struct FrontendTaskTerminalResult final {
    FrontendTaskTerminalOutcome outcome = FrontendTaskTerminalOutcome::Succeeded;
    std::string localizationKey;
    std::vector<std::pair<std::string, std::string>> substitutionValues;
    std::string diagnosticText;
    bool partialChangesRolledBack = false;
};

struct FrontendTaskSubtaskSnapshot final {
    std::string id;
    std::string name;
    FrontendTaskState state = FrontendTaskState::Queued;
    FrontendTaskProgressKind progressKind = FrontendTaskProgressKind::None;
    double progressFraction = 0.0;

    bool hasStableIdentifier() const noexcept { return !id.empty(); }
};

struct FrontendTaskSnapshot final {
    std::string id;
    std::string title;
    FrontendTaskState state = FrontendTaskState::Queued;
    FrontendTaskProgressKind progressKind = FrontendTaskProgressKind::None;
    double progressFraction = 0.0;
    bool cancellationAllowed = false;
    std::vector<FrontendTaskSubtaskSnapshot> subtasks;
    std::optional<FrontendTaskTerminalResult> terminalResult;

    bool hasStableIdentifier() const noexcept { return !id.empty(); }
};

enum class FrontendVanillaCreationOutcome : std::uint8_t { Succeeded, Failed, Cancelled, Rejected };

/// Explicit, non-UI input for the vanilla instance creation adapter. Version
/// descriptors and loader identifiers are metadata values; staging paths,
/// settings ownership, Qt tasks, downloads, and instance commits stay inside
/// the injected backend runner.
struct FrontendVanillaCreationRequest final {
    std::string versionDescriptor;
    std::string versionName;
    std::optional<std::string> loaderIdentifier;
    std::optional<std::string> loaderVersionDescriptor;
    std::string name;
    std::string groupId;
    std::string iconKey = "default";
};

/// Confirmed result for one fixture-controlled vanilla creation request. A
/// successful result carries only the immutable summary of the committed
/// instance; paths and backend task ownership never cross this value type.
struct FrontendVanillaCreationResult final {
    FrontendVanillaCreationOutcome outcome = FrontendVanillaCreationOutcome::Rejected;
    std::optional<FrontendInstanceSnapshot> instance;
    std::string localizationKey;
    std::string diagnosticText;
    bool retryable = false;
};

enum class FrontendInstanceImportSourceKind : std::uint8_t { LocalFile, RemoteURL };
enum class FrontendInstanceImportOutcome : std::uint8_t { Succeeded, Failed, Cancelled, Rejected };

/// Explicit, non-UI input for importing a local archive or an HTTP(S) archive.
/// The local path may be outside the data root because it is caller-selected;
/// all staging, extraction, download, and final instance commits stay inside
/// the injected backend runner and its explicit data root.
struct FrontendInstanceImportRequest final {
    FrontendInstanceImportSourceKind sourceKind = FrontendInstanceImportSourceKind::LocalFile;
    std::string source;
    std::string name;
    std::string groupId;
    std::string iconKey = "default";
};

/// Confirmed result for one fixture-controlled import request. A successful
/// result carries only immutable instance metadata; source paths and task
/// ownership never cross this value type.
struct FrontendInstanceImportResult final {
    FrontendInstanceImportOutcome outcome = FrontendInstanceImportOutcome::Rejected;
    std::optional<FrontendInstanceSnapshot> instance;
    std::string localizationKey;
    std::string diagnosticText;
    bool retryable = false;
    bool partialChangesRolledBack = false;
};

enum class FrontendInstanceCopyOutcome : std::uint8_t { Succeeded, Failed, Cancelled, Rejected };

/// Explicit copy policy carried from the native copy form. The adapter owns
/// the source instance, staging directory, filesystem capability checks, and
/// final commit; these booleans only preserve the legacy policy choices.
struct FrontendInstanceCopyOptions final {
    bool copySaves = true;
    bool keepPlaytime = true;
    bool copyGameOptions = true;
    bool copyResourcePacks = true;
    bool copyShaderPacks = true;
    bool copyServers = true;
    bool copyMods = true;
    bool copyScreenshots = true;
    bool useSymbolicLinks = false;
    bool linkRecursively = false;
    bool useHardLinks = false;
    bool dontLinkSaves = false;
    bool useClone = false;
};

/// Explicit, non-UI input for copying one instance into a new staged
/// instance. No source path or Qt object crosses the facade contract.
struct FrontendInstanceCopyRequest final {
    std::string sourceInstanceIdentifier;
    std::string name;
    std::string groupId;
    std::string iconKey = "default";
    FrontendInstanceCopyOptions options;
};

/// Confirmed result for one fixture-controlled copy task. A successful result
/// carries only the committed immutable instance summary.
struct FrontendInstanceCopyResult final {
    FrontendInstanceCopyOutcome outcome = FrontendInstanceCopyOutcome::Rejected;
    std::optional<FrontendInstanceSnapshot> instance;
    std::string localizationKey;
    std::string diagnosticText;
    bool retryable = false;
    bool partialChangesRolledBack = false;
};

enum class FrontendInstanceExportKind : std::uint8_t { ZipArchive, ModList };
enum class FrontendModListExportFormat : std::uint8_t { HTML, Markdown, PlainText, JSON, CSV, Custom };

inline constexpr std::uint32_t kFrontendModListFieldAuthors = 1U << 0;
inline constexpr std::uint32_t kFrontendModListFieldVersion = 1U << 1;
inline constexpr std::uint32_t kFrontendModListFieldURL = 1U << 2;
inline constexpr std::uint32_t kFrontendModListFieldFilename = 1U << 3;
inline constexpr std::uint32_t kFrontendModListFieldAll = kFrontendModListFieldAuthors
    | kFrontendModListFieldVersion | kFrontendModListFieldURL | kFrontendModListFieldFilename;

enum class FrontendInstanceExportOutcome : std::uint8_t { Succeeded, Failed, Cancelled, Rejected };

/// Explicit local export input. The destination is the URL/path selected by a
/// system save panel; archive writing, mod enumeration, formatting, cleanup,
/// and cancellation remain inside the injected backend runner.
struct FrontendInstanceExportRequest final {
    FrontendInstanceExportKind kind = FrontendInstanceExportKind::ZipArchive;
    std::string sourceInstanceIdentifier;
    std::filesystem::path destinationPath;
    FrontendModListExportFormat modListFormat = FrontendModListExportFormat::HTML;
    std::uint32_t modListFieldMask = 0;
    std::string customTemplate;
};

/// Confirmed result for a local ZIP or mod-list export. The destination is
/// echoed so the UI can report exactly which user-selected URL was handled.
struct FrontendInstanceExportResult final {
    FrontendInstanceExportKind kind = FrontendInstanceExportKind::ZipArchive;
    FrontendInstanceExportOutcome outcome = FrontendInstanceExportOutcome::Rejected;
    std::filesystem::path destinationPath;
    std::string localizationKey;
    std::string diagnosticText;
    bool retryable = false;
    bool partialChangesRolledBack = false;
};

inline constexpr std::size_t kFrontendLogMaxEntries = 512;
inline constexpr std::size_t kFrontendLogMaxBytes = 256 * 1024;

struct FrontendLogEntry final {
    std::uint64_t sequence = 0;
    std::string text;
    bool truncated = false;
};

struct FrontendInstanceLogSnapshot final {
    std::string instanceIdentifier;
    std::string logIdentifier;
    std::vector<FrontendLogEntry> entries;
    std::uint64_t droppedEntryCount = 0;
    std::uint64_t totalByteCount = 0;
    bool truncated = false;
};

struct FrontendLogSnapshot final {
    std::string taskId;
    std::vector<FrontendLogEntry> entries;
    std::uint64_t droppedEntryCount = 0;
    std::uint64_t totalByteCount = 0;
    bool truncated = false;

    bool hasStableIdentifier() const noexcept { return !taskId.empty(); }
};

/// Runtime ports are supplied by the owning composition root so the facade
/// does not discover global application state or create hidden workers.
struct FrontendRuntimeDependencies final {
    using Work = std::function<void()>;
    using Dispatch = std::function<void(Work)>;
    using Clock = std::function<std::chrono::system_clock::time_point()>;
    using CancelPendingWork = std::function<void()>;
    using Shutdown = std::function<void()>;
    using InstanceSnapshotLoader = std::function<std::vector<FrontendInstanceSnapshot>(const std::filesystem::path&)>;
    using InstanceDetailsLoader =
        std::function<std::optional<FrontendInstanceDetailsSnapshot>(const std::filesystem::path&, const std::string&)>;
    using InstanceComponentsLoader = std::function<std::optional<std::vector<FrontendInstanceComponentSnapshot>>(
        const std::filesystem::path&, const std::string&)>;
    using InstanceResourcesLoader = std::function<std::optional<std::vector<FrontendInstanceResourceSnapshot>>(
        const std::filesystem::path&, const std::string&, FrontendInstanceResourceKind)>;
    using InstanceResourceMutator = std::function<FrontendInstanceResourceMutationResult(
        const std::filesystem::path&, const std::string&, FrontendInstanceResourceKind,
        const FrontendInstanceResourceMutationRequest&)>;
    using InstanceWorldsLoader = std::function<std::optional<std::vector<FrontendInstanceWorldSnapshot>>(
        const std::filesystem::path&, const std::string&)>;
    using InstanceServersLoader = std::function<std::optional<std::vector<FrontendInstanceServerSnapshot>>(
        const std::filesystem::path&, const std::string&)>;
    using InstanceScreenshotsLoader = std::function<std::optional<std::vector<FrontendInstanceScreenshotSnapshot>>(
        const std::filesystem::path&, const std::string&)>;
    using InstanceLogFilesLoader = std::function<std::optional<std::vector<FrontendInstanceLogFileSnapshot>>(
        const std::filesystem::path&, const std::string&)>;
    using InstanceLogLoader = std::function<std::optional<FrontendInstanceLogSnapshot>(
        const std::filesystem::path&, const std::string&, const std::string&)>;
    using InstanceDetailMutator = std::function<FrontendInstanceDetailMutationResult(
        const std::filesystem::path&, const std::string&, const FrontendInstanceDetailMutationRequest&)>;
    using InstanceChangeLoader = std::function<std::vector<FrontendInstanceChange>(const std::filesystem::path&)>;
    using InstanceCommand = std::function<FrontendInstanceCommandResult(const std::filesystem::path&, const std::string&)>;
    using InstanceNotesUpdater = std::function<FrontendInstanceNotesUpdateResult(
        const std::filesystem::path&, const std::string&, const std::string&)>;
    using InstanceSettingsLoader = std::function<std::optional<FrontendInstanceSettingsSnapshot>(
        const std::filesystem::path&, const std::string&)>;
    using InstanceSettingsUpdater = std::function<FrontendInstanceSettingsUpdateResult(
        const std::filesystem::path&, const std::string&, const FrontendInstanceSettingsSnapshot&)>;
    using GlobalSettingsLoader =
        std::function<std::optional<FrontendGlobalSettingsSnapshot>(const std::filesystem::path&)>;
    using GlobalSettingsUpdater = std::function<FrontendGlobalSettingsUpdateResult(
        const std::filesystem::path&, const FrontendGlobalSettingsSnapshot&)>;
    using JavaDiscoveryLoader = std::function<FrontendJavaDiscoveryResult(const std::filesystem::path&)>;
    using JavaSelectionUpdater = std::function<FrontendJavaSelectionResult(const std::filesystem::path&, const std::string&)>;
    using AccountSnapshotLoader = std::function<FrontendAccountSnapshotResult(const std::filesystem::path&)>;
    using AccountSelectionUpdater = std::function<FrontendAccountSelectionResult(
        const std::filesystem::path&, const std::optional<std::string>&)>;
    using AccountAuthenticationProgressHandler = std::function<void(const FrontendAccountAuthenticationProgress&)>;
    using AccountAuthenticationRunner = std::function<FrontendAccountAuthenticationResult(
        const std::filesystem::path&, const FrontendAccountAuthenticationRequest&, const AccountAuthenticationProgressHandler&)>;
    using VanillaCreationProgressHandler = std::function<void(const FrontendTaskSnapshot&)>;
    using VanillaCreationCancellationCheck = std::function<bool()>;
    using VanillaCreationRunner = std::function<FrontendVanillaCreationResult(
        const std::filesystem::path&,
        const FrontendVanillaCreationRequest&,
        const VanillaCreationProgressHandler&,
        const VanillaCreationCancellationCheck&)>;
    using InstanceImportProgressHandler = std::function<void(const FrontendTaskSnapshot&)>;
    using InstanceImportCancellationCheck = std::function<bool()>;
    using InstanceImportRunner = std::function<FrontendInstanceImportResult(
        const std::filesystem::path&,
        const FrontendInstanceImportRequest&,
        const InstanceImportProgressHandler&,
        const InstanceImportCancellationCheck&)>;
    using InstanceCopyProgressHandler = std::function<void(const FrontendTaskSnapshot&)>;
    using InstanceCopyCancellationCheck = std::function<bool()>;
    using InstanceCopyRunner = std::function<FrontendInstanceCopyResult(
        const std::filesystem::path&,
        const FrontendInstanceCopyRequest&,
        const InstanceCopyProgressHandler&,
        const InstanceCopyCancellationCheck&)>;
    using InstanceExportProgressHandler = std::function<void(const FrontendTaskSnapshot&)>;
    using InstanceExportCancellationCheck = std::function<bool()>;
    using InstanceExportRunner = std::function<FrontendInstanceExportResult(
        const std::filesystem::path&,
        const FrontendInstanceExportRequest&,
        const InstanceExportProgressHandler&,
        const InstanceExportCancellationCheck&)>;
    using OfflineLaunchIdentityLoader = std::function<FrontendOfflineLaunchIdentityLoadResult(
        const std::filesystem::path&, const FrontendOfflineLaunchIdentityRequest&)>;
    using OfflineLaunchIdentityUpdater = std::function<FrontendOfflineLaunchIdentityUpdateResult(
        const std::filesystem::path&, const FrontendOfflineLaunchIdentityUpdateRequest&)>;
    using TaskSnapshotLoader = std::function<std::optional<FrontendTaskSnapshot>(const std::filesystem::path&, const std::string&)>;
    using TaskCancellation = std::function<FrontendTaskCancellationResult(const std::filesystem::path&, const std::string&)>;
    using LogEntryHandler = std::function<void(FrontendLogEntry)>;
    using TaskLogStreamer = std::function<bool(const std::filesystem::path&, const std::string&, const LogEntryHandler&)>;

    Dispatch dispatch;
    Clock now;
    CancelPendingWork cancelPendingWork;
    Shutdown shutdown;
    InstanceSnapshotLoader loadInstanceSnapshots;
    InstanceDetailsLoader loadInstanceDetails;
    InstanceComponentsLoader loadInstanceComponents;
    InstanceResourcesLoader loadInstanceResources;
    InstanceResourceMutator mutateInstanceResource;
    InstanceWorldsLoader loadInstanceWorlds;
    InstanceServersLoader loadInstanceServers;
    InstanceScreenshotsLoader loadInstanceScreenshots;
    InstanceLogFilesLoader loadInstanceLogFiles;
    InstanceLogLoader loadInstanceLog;
    InstanceDetailMutator mutateInstanceDetail;
    InstanceChangeLoader loadInstanceChanges;
    InstanceCommand launchInstance;
    InstanceCommand stopInstance;
    InstanceNotesUpdater updateInstanceNotes;
    InstanceSettingsLoader loadInstanceSettings;
    InstanceSettingsUpdater updateInstanceSettings;
    GlobalSettingsLoader loadGlobalSettings;
    GlobalSettingsUpdater updateGlobalSettings;
    JavaDiscoveryLoader loadJavaInstallations;
    JavaSelectionUpdater selectJavaInstallation;
    AccountSnapshotLoader loadAccountSnapshots;
    AccountSelectionUpdater selectActiveAccount;
    AccountAuthenticationRunner authenticateAccount;
    VanillaCreationRunner createVanillaInstance;
    InstanceImportRunner importInstance;
    InstanceCopyRunner copyInstance;
    InstanceExportRunner exportInstance;
    OfflineLaunchIdentityLoader loadOfflineLaunchIdentity;
    OfflineLaunchIdentityUpdater updateOfflineLaunchIdentity;
    TaskSnapshotLoader loadTaskSnapshot;
    TaskCancellation cancelTask;
    TaskLogStreamer streamTaskLogs;

    bool isComplete() const noexcept
    {
        return static_cast<bool>(dispatch) && static_cast<bool>(now) && static_cast<bool>(cancelPendingWork)
            && static_cast<bool>(shutdown);
    }
};

/// UI-free entry point for native frontend use cases.
///
/// The facade owns the explicit root and injected runtime ports. Backend
/// services, snapshots, events, and lifecycle operations through explicit
/// value and callback contracts.
class FrontendFacade final {
   public:
    FrontendFacade(std::filesystem::path dataRoot, FrontendRuntimeDependencies runtimeDependencies);
    ~FrontendFacade() noexcept;

    FrontendFacade(const FrontendFacade&) = delete;
    FrontendFacade& operator=(const FrontendFacade&) = delete;
    FrontendFacade(FrontendFacade&&) = delete;
    FrontendFacade& operator=(FrontendFacade&&) = delete;

    const std::filesystem::path& dataRoot() const noexcept { return m_dataRoot; }
    bool hasRuntimeDependencies() const noexcept { return m_runtimeDependencies.isComplete(); }
    FrontendLifecycleState lifecycleState() const noexcept { return m_lifecycleState; }
    bool shutdown() noexcept;
    std::vector<FrontendInstanceSnapshot> instanceSnapshots() const;
    std::optional<FrontendInstanceDetailsSnapshot> instanceDetails(const std::string& instanceIdentifier) const;
    std::optional<std::vector<FrontendInstanceComponentSnapshot>> instanceComponents(
        const std::string& instanceIdentifier) const;
    std::optional<std::vector<FrontendInstanceResourceSnapshot>> instanceResources(
        const std::string& instanceIdentifier, FrontendInstanceResourceKind kind) const;
    FrontendInstanceResourceMutationResult mutateInstanceResource(
        const std::string& instanceIdentifier,
        FrontendInstanceResourceKind kind,
        const FrontendInstanceResourceMutationRequest& request) const;
    std::optional<std::vector<FrontendInstanceWorldSnapshot>> instanceWorlds(const std::string& instanceIdentifier) const;
    std::optional<std::vector<FrontendInstanceServerSnapshot>> instanceServers(const std::string& instanceIdentifier) const;
    std::optional<std::vector<FrontendInstanceScreenshotSnapshot>> instanceScreenshots(
        const std::string& instanceIdentifier) const;
    std::optional<std::vector<FrontendInstanceLogFileSnapshot>> instanceLogFiles(const std::string& instanceIdentifier) const;
    std::optional<FrontendInstanceLogSnapshot> instanceLog(
        const std::string& instanceIdentifier, const std::string& logIdentifier) const;
    FrontendInstanceDetailMutationResult mutateInstanceDetail(
        const std::string& instanceIdentifier, const FrontendInstanceDetailMutationRequest& request) const;
    std::vector<FrontendInstanceChange> instanceChanges() const;
    FrontendInstanceCommandResult launchInstance(const std::string& instanceIdentifier) const;
    FrontendInstanceCommandResult stopInstance(const std::string& instanceIdentifier) const;
    FrontendInstanceNotesUpdateResult updateInstanceNotes(
        const std::string& instanceIdentifier, const std::string& notes) const;
    std::optional<FrontendInstanceSettingsSnapshot> instanceSettings(const std::string& instanceIdentifier) const;
    FrontendInstanceSettingsUpdateResult updateInstanceSettings(
        const std::string& instanceIdentifier, const FrontendInstanceSettingsSnapshot& settings) const;
    std::optional<FrontendGlobalSettingsSnapshot> globalSettings() const;
    FrontendGlobalSettingsUpdateResult updateGlobalSettings(const FrontendGlobalSettingsSnapshot& settings) const;
    FrontendJavaDiscoveryResult javaInstallations() const;
    FrontendJavaSelectionResult selectJavaInstallation(const std::string& installationIdentifier) const;
    FrontendAccountSnapshotResult accountSnapshots() const;
    FrontendAccountSelectionResult selectActiveAccount(const std::optional<std::string>& accountIdentifier) const;
    FrontendAccountAuthenticationResult authenticateAccount(
        const FrontendAccountAuthenticationRequest& request,
        const FrontendRuntimeDependencies::AccountAuthenticationProgressHandler& progressHandler = {}) const;
    FrontendVanillaCreationResult createVanillaInstance(
        const FrontendVanillaCreationRequest& request,
        const FrontendRuntimeDependencies::VanillaCreationProgressHandler& progressHandler = {},
        const FrontendRuntimeDependencies::VanillaCreationCancellationCheck& cancellationCheck = {}) const;
    FrontendInstanceImportResult importInstance(
        const FrontendInstanceImportRequest& request,
        const FrontendRuntimeDependencies::InstanceImportProgressHandler& progressHandler = {},
        const FrontendRuntimeDependencies::InstanceImportCancellationCheck& cancellationCheck = {}) const;
    FrontendInstanceCopyResult copyInstance(
        const FrontendInstanceCopyRequest& request,
        const FrontendRuntimeDependencies::InstanceCopyProgressHandler& progressHandler = {},
        const FrontendRuntimeDependencies::InstanceCopyCancellationCheck& cancellationCheck = {}) const;
    FrontendInstanceExportResult exportInstance(
        const FrontendInstanceExportRequest& request,
        const FrontendRuntimeDependencies::InstanceExportProgressHandler& progressHandler = {},
        const FrontendRuntimeDependencies::InstanceExportCancellationCheck& cancellationCheck = {}) const;
    FrontendOfflineLaunchIdentityLoadResult loadOfflineLaunchIdentity(
        const FrontendOfflineLaunchIdentityRequest& request) const;
    FrontendOfflineLaunchIdentityUpdateResult updateOfflineLaunchIdentity(
        const FrontendOfflineLaunchIdentityUpdateRequest& request) const;
    std::optional<FrontendTaskSnapshot> taskSnapshot(const std::string& taskIdentifier) const;
    FrontendTaskCancellationResult cancelTask(const std::string& taskIdentifier) const;
    std::optional<FrontendLogSnapshot> taskLogSnapshot(const std::string& taskIdentifier) const;

   private:
    std::filesystem::path m_dataRoot;
    FrontendRuntimeDependencies m_runtimeDependencies;
    FrontendLifecycleState m_lifecycleState = FrontendLifecycleState::Running;
};

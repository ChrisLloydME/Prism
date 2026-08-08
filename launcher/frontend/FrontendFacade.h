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
    std::optional<FrontendTaskSnapshot> taskSnapshot(const std::string& taskIdentifier) const;
    FrontendTaskCancellationResult cancelTask(const std::string& taskIdentifier) const;
    std::optional<FrontendLogSnapshot> taskLogSnapshot(const std::string& taskIdentifier) const;

   private:
    std::filesystem::path m_dataRoot;
    FrontendRuntimeDependencies m_runtimeDependencies;
    FrontendLifecycleState m_lifecycleState = FrontendLifecycleState::Running;
};

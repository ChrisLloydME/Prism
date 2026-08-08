#import "PrismBridge.h"

#include "FrontendFacade.h"

#include <chrono>
#include <cmath>
#include <dispatch/dispatch.h>
#include <exception>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <utility>
#include <vector>

namespace {
NSString *const kPrismBundleIdentifier = @"com.lloydME.Prism";
NSString *const kPrismApplicationName = @"Prism";

class NativeFacadeLifecycle final {
public:
    bool beginShutdown() noexcept
    {
        if (m_state != PRBridgeLifecycleStateRunning) {
            return false;
        }
        m_state = PRBridgeLifecycleStateShuttingDown;
        return true;
    }

    void finishShutdown() noexcept
    {
        m_state = PRBridgeLifecycleStateStopped;
    }

    PRBridgeLifecycleState state() const noexcept
    {
        return m_state;
    }

private:
    PRBridgeLifecycleState m_state = PRBridgeLifecycleStateRunning;
};

NSURL *normalizedDataRootURL(NSURL *candidateURL)
{
    if (!candidateURL.isFileURL || candidateURL.path.length == 0 || !candidateURL.path.isAbsolutePath) {
        return nil;
    }

    NSURL *normalizedURL = candidateURL.standardizedURL;
    if (!normalizedURL.isFileURL || normalizedURL.path.length == 0 || !normalizedURL.path.isAbsolutePath) {
        return nil;
    }
    return normalizedURL;
}

void invokeHandler(PRBridgeLifecycleHandler handler) noexcept
{
    if (!handler) {
        return;
    }

    try {
        @try {
            handler();
        } @catch (NSException *) {
        }
    } catch (...) {
    }
}

bool isNonEmptyString(NSString *value)
{
    return [value isKindOfClass:NSString.class] && value.length > 0;
}

bool isKnownInstanceCommandKind(PRInstanceCommandKind kind)
{
    switch (kind) {
        case PRInstanceCommandKindLaunch:
        case PRInstanceCommandKindStop:
            return true;
    }
    return false;
}

bool isKnownInstanceCommandOutcome(PRInstanceCommandOutcome outcome)
{
    switch (outcome) {
        case PRInstanceCommandOutcomeSucceeded:
        case PRInstanceCommandOutcomeUnknownInstance:
        case PRInstanceCommandOutcomeRejected:
            return true;
    }
    return false;
}

bool isKnownInstanceNotesUpdateOutcome(PRInstanceNotesUpdateOutcome outcome)
{
    switch (outcome) {
        case PRInstanceNotesUpdateOutcomeSucceeded:
        case PRInstanceNotesUpdateOutcomeUnknownInstance:
        case PRInstanceNotesUpdateOutcomeRejected:
            return true;
    }
    return false;
}

bool isKnownInstanceJoinTarget(PRInstanceJoinTarget target)
{
    switch (target) {
        case PRInstanceJoinTargetNone:
        case PRInstanceJoinTargetServer:
        case PRInstanceJoinTargetWorld:
            return true;
    }
    return false;
}

bool isKnownInstanceSettingsUpdateOutcome(PRInstanceSettingsUpdateOutcome outcome)
{
    switch (outcome) {
        case PRInstanceSettingsUpdateOutcomeSucceeded:
        case PRInstanceSettingsUpdateOutcomeUnknownInstance:
        case PRInstanceSettingsUpdateOutcomeRejected:
            return true;
    }
    return false;
}

std::string stableIdentifierFromFoundation(NSString *identifier)
{
    if (![identifier isKindOfClass:NSString.class]) {
        throw std::invalid_argument("Instance commands require a string identifier");
    }

    NSString *normalized = [identifier stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (normalized.length == 0) {
        throw std::invalid_argument("Instance commands require a stable identifier");
    }

    const char *utf8 = normalized.UTF8String;
    if (utf8 == nullptr || utf8[0] == '\0') {
        throw std::invalid_argument("Instance commands require valid UTF-8 text");
    }
    return std::string(utf8);
}

std::string utf8TextFromFoundation(NSString *text)
{
    if (![text isKindOfClass:NSString.class]) {
        throw std::invalid_argument("Instance notes require a string value");
    }

    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
    if (!data) {
        throw std::invalid_argument("Instance notes require valid UTF-8 text");
    }
    if (data.length == 0) {
        return {};
    }
    return std::string(static_cast<const char *>(data.bytes), data.length);
}

NSString *nullableStringCopy(NSString *value)
{
    return isNonEmptyString(value) ? [value copy] : nil;
}

PRInstanceCommandOutcome commandOutcomeFromFacadeResult(FrontendInstanceCommandResult result)
{
    switch (result) {
        case FrontendInstanceCommandResult::Succeeded:
            return PRInstanceCommandOutcomeSucceeded;
        case FrontendInstanceCommandResult::UnknownInstance:
            return PRInstanceCommandOutcomeUnknownInstance;
        case FrontendInstanceCommandResult::Rejected:
            return PRInstanceCommandOutcomeRejected;
    }
    throw std::invalid_argument("Facade returned an unknown instance command result");
}

bool isKnownInstanceChangeKind(PRInstanceChangeKind kind)
{
    switch (kind) {
        case PRInstanceChangeKindAdded:
        case PRInstanceChangeKindUpdated:
        case PRInstanceChangeKindRemoved:
            return true;
    }
    return false;
}

FrontendRuntimeDependencies defaultRuntimeDependencies()
{
    FrontendRuntimeDependencies dependencies;
    dependencies.dispatch = [](FrontendRuntimeDependencies::Work work) {
        if (work) {
            work();
        }
    };
    dependencies.now = [] {
        return std::chrono::system_clock::now();
    };
    dependencies.cancelPendingWork = [] {};
    dependencies.shutdown = [] {};
    return dependencies;
}

std::filesystem::path dataRootPathForURL(NSURL *dataRootURL)
{
    const char *fileSystemRepresentation = dataRootURL.fileSystemRepresentation;
    if (fileSystemRepresentation == nullptr || fileSystemRepresentation[0] == '\0') {
        throw std::invalid_argument("Bridge data root must have a filesystem representation");
    }
    return std::filesystem::path(fileSystemRepresentation);
}

NSString *foundationStringFromUTF8(const std::string& value)
{
    if (value.empty()) {
        return nil;
    }

    NSString *string = [NSString stringWithUTF8String:value.c_str()];
    if (!string) {
        throw std::invalid_argument("Facade returned invalid UTF-8 text");
    }
    return string;
}

NSString *foundationStringFromUTF8AllowEmpty(const std::string& value)
{
    if (value.empty()) {
        return @"";
    }
    return foundationStringFromUTF8(value);
}

PRInstanceSummary *summaryFromFacadeSnapshot(const FrontendInstanceSnapshot& snapshot)
{
    NSString *identifier = foundationStringFromUTF8(snapshot.id);
    NSString *name = foundationStringFromUTF8(snapshot.name);
    NSString *iconKey = foundationStringFromUTF8(snapshot.iconKey);
    NSString *groupID = foundationStringFromUTF8(snapshot.groupId);
    PRInstanceSummary *summary = [[PRInstanceSummary alloc] initWithIdentifier:identifier
                                                                             name:name
                                                                          iconKey:iconKey
                                                                          groupID:groupID];
    if (!summary) {
        throw std::invalid_argument("Facade returned an invalid instance snapshot");
    }
    return summary;
}

PRInstanceDetails *detailsFromFacadeSnapshot(const FrontendInstanceDetailsSnapshot& snapshot)
{
    PRInstanceDetails *details = [[PRInstanceDetails alloc]
        initWithIdentifier:foundationStringFromUTF8(snapshot.id)
                       name:foundationStringFromUTF8(snapshot.name)
                    iconKey:foundationStringFromUTF8(snapshot.iconKey)
                    groupID:foundationStringFromUTF8(snapshot.groupId)
              instanceType:foundationStringFromUTF8(snapshot.instanceType)
                     notes:foundationStringFromUTF8AllowEmpty(snapshot.notes)
             notesEditable:snapshot.notesEditable];
    if (!details) {
        throw std::invalid_argument("Facade returned invalid instance details");
    }
    return details;
}

PRInstanceJoinTarget joinTargetFromFacadeTarget(FrontendInstanceJoinTarget target)
{
    switch (target) {
        case FrontendInstanceJoinTarget::None:
            return PRInstanceJoinTargetNone;
        case FrontendInstanceJoinTarget::Server:
            return PRInstanceJoinTargetServer;
        case FrontendInstanceJoinTarget::World:
            return PRInstanceJoinTargetWorld;
    }
    throw std::invalid_argument("Facade returned an unknown instance join target");
}

FrontendInstanceJoinTarget joinTargetFromFoundationTarget(PRInstanceJoinTarget target)
{
    switch (target) {
        case PRInstanceJoinTargetNone:
            return FrontendInstanceJoinTarget::None;
        case PRInstanceJoinTargetServer:
            return FrontendInstanceJoinTarget::Server;
        case PRInstanceJoinTargetWorld:
            return FrontendInstanceJoinTarget::World;
    }
    throw std::invalid_argument("Native settings returned an unknown instance join target");
}

PRInstanceSettings *settingsFromFacadeSnapshot(const FrontendInstanceSettingsSnapshot& snapshot)
{
    NSMutableArray<NSString *> *loaders = [NSMutableArray arrayWithCapacity:snapshot.modDownloadLoaders.size()];
    for (const std::string& loader : snapshot.modDownloadLoaders) {
        NSString *loaderString = foundationStringFromUTF8(loader);
        if (!loaderString) {
            throw std::invalid_argument("Facade returned an invalid mod loader");
        }
        [loaders addObject:loaderString];
    }

    PRInstanceSettings *settings = [[PRInstanceSettings alloc]
        initWithIdentifier:foundationStringFromUTF8(snapshot.id)
        windowOverrideEnabled:snapshot.windowOverrideEnabled
        launchMaximized:snapshot.launchMaximized
        windowWidth:snapshot.windowWidth
        windowHeight:snapshot.windowHeight
        closeAfterLaunch:snapshot.closeAfterLaunch
        quitAfterGameStop:snapshot.quitAfterGameStop
        consoleOverrideEnabled:snapshot.consoleOverrideEnabled
        showConsole:snapshot.showConsole
        showConsoleOnError:snapshot.showConsoleOnError
        autoCloseConsole:snapshot.autoCloseConsole
        globalDataPacksEnabled:snapshot.globalDataPacksEnabled
        globalDataPacksPath:foundationStringFromUTF8AllowEmpty(snapshot.globalDataPacksPath)
        gameTimeOverrideEnabled:snapshot.gameTimeOverrideEnabled
        showGameTime:snapshot.showGameTime
        recordGameTime:snapshot.recordGameTime
        countGameTime:snapshot.countGameTime
        joinServerOnLaunch:snapshot.joinServerOnLaunch
        joinTarget:joinTargetFromFacadeTarget(snapshot.joinTarget)
        joinServerAddress:foundationStringFromUTF8AllowEmpty(snapshot.joinServerAddress)
        joinWorld:foundationStringFromUTF8AllowEmpty(snapshot.joinWorld)
        overrideModDownloadLoaders:snapshot.overrideModDownloadLoaders
        modDownloadLoaders:loaders
        javaLocationOverrideEnabled:snapshot.javaLocationOverrideEnabled
        javaPath:foundationStringFromUTF8AllowEmpty(snapshot.javaPath)
        ignoreJavaCompatibility:snapshot.ignoreJavaCompatibility
        memoryOverrideEnabled:snapshot.memoryOverrideEnabled
        minMemoryMiB:snapshot.minMemoryMiB
        maxMemoryMiB:snapshot.maxMemoryMiB
        permGenMiB:snapshot.permGenMiB
        lowMemoryWarning:snapshot.lowMemoryWarning
        javaArgumentsOverrideEnabled:snapshot.javaArgumentsOverrideEnabled
        jvmArguments:foundationStringFromUTF8AllowEmpty(snapshot.jvmArguments)
        commandOverrideEnabled:snapshot.commandOverrideEnabled
        preLaunchCommand:foundationStringFromUTF8AllowEmpty(snapshot.preLaunchCommand)
        wrapperCommand:foundationStringFromUTF8AllowEmpty(snapshot.wrapperCommand)
        postExitCommand:foundationStringFromUTF8AllowEmpty(snapshot.postExitCommand)
        legacySettingsOverrideEnabled:snapshot.legacySettingsOverrideEnabled
        onlineFixes:snapshot.onlineFixes
        nativeWorkaroundsOverrideEnabled:snapshot.nativeWorkaroundsOverrideEnabled
        useNativeGLFW:snapshot.useNativeGLFW
        customGLFWPath:foundationStringFromUTF8AllowEmpty(snapshot.customGLFWPath)
        useNativeOpenAL:snapshot.useNativeOpenAL
        customOpenALPath:foundationStringFromUTF8AllowEmpty(snapshot.customOpenALPath)];
    if (!settings) {
        throw std::invalid_argument("Facade returned invalid instance settings");
    }
    return settings;
}

FrontendInstanceSettingsSnapshot settingsFromFoundationObject(PRInstanceSettings *settings)
{
    if (!settings) {
        throw std::invalid_argument("Instance settings require a value");
    }

    FrontendInstanceSettingsSnapshot converted;
    converted.id = stableIdentifierFromFoundation(settings.identifier);
    converted.windowOverrideEnabled = settings.windowOverrideEnabled;
    converted.launchMaximized = settings.launchMaximized;
    converted.windowWidth = static_cast<int>(settings.windowWidth);
    converted.windowHeight = static_cast<int>(settings.windowHeight);
    converted.closeAfterLaunch = settings.closeAfterLaunch;
    converted.quitAfterGameStop = settings.quitAfterGameStop;
    converted.consoleOverrideEnabled = settings.consoleOverrideEnabled;
    converted.showConsole = settings.showConsole;
    converted.showConsoleOnError = settings.showConsoleOnError;
    converted.autoCloseConsole = settings.autoCloseConsole;
    converted.globalDataPacksEnabled = settings.globalDataPacksEnabled;
    converted.globalDataPacksPath = utf8TextFromFoundation(settings.globalDataPacksPath);
    converted.gameTimeOverrideEnabled = settings.gameTimeOverrideEnabled;
    converted.showGameTime = settings.showGameTime;
    converted.recordGameTime = settings.recordGameTime;
    converted.countGameTime = settings.countGameTime;
    converted.joinServerOnLaunch = settings.joinServerOnLaunch;
    converted.joinTarget = joinTargetFromFoundationTarget(settings.joinTarget);
    converted.joinServerAddress = utf8TextFromFoundation(settings.joinServerAddress);
    converted.joinWorld = utf8TextFromFoundation(settings.joinWorld);
    converted.overrideModDownloadLoaders = settings.overrideModDownloadLoaders;
    for (id loader in settings.modDownloadLoaders) {
        converted.modDownloadLoaders.push_back(utf8TextFromFoundation((NSString *)loader));
    }
    converted.javaLocationOverrideEnabled = settings.javaLocationOverrideEnabled;
    converted.javaPath = utf8TextFromFoundation(settings.javaPath);
    converted.ignoreJavaCompatibility = settings.ignoreJavaCompatibility;
    converted.memoryOverrideEnabled = settings.memoryOverrideEnabled;
    converted.minMemoryMiB = static_cast<int>(settings.minMemoryMiB);
    converted.maxMemoryMiB = static_cast<int>(settings.maxMemoryMiB);
    converted.permGenMiB = static_cast<int>(settings.permGenMiB);
    converted.lowMemoryWarning = settings.lowMemoryWarning;
    converted.javaArgumentsOverrideEnabled = settings.javaArgumentsOverrideEnabled;
    converted.jvmArguments = utf8TextFromFoundation(settings.jvmArguments);
    converted.commandOverrideEnabled = settings.commandOverrideEnabled;
    converted.preLaunchCommand = utf8TextFromFoundation(settings.preLaunchCommand);
    converted.wrapperCommand = utf8TextFromFoundation(settings.wrapperCommand);
    converted.postExitCommand = utf8TextFromFoundation(settings.postExitCommand);
    converted.legacySettingsOverrideEnabled = settings.legacySettingsOverrideEnabled;
    converted.onlineFixes = settings.onlineFixes;
    converted.nativeWorkaroundsOverrideEnabled = settings.nativeWorkaroundsOverrideEnabled;
    converted.useNativeGLFW = settings.useNativeGLFW;
    converted.customGLFWPath = utf8TextFromFoundation(settings.customGLFWPath);
    converted.useNativeOpenAL = settings.useNativeOpenAL;
    converted.customOpenALPath = utf8TextFromFoundation(settings.customOpenALPath);
    return converted;
}

PRInstanceSettingsUpdateOutcome settingsUpdateOutcomeFromFacadeResult(FrontendInstanceSettingsUpdateOutcome outcome)
{
    switch (outcome) {
        case FrontendInstanceSettingsUpdateOutcome::Succeeded:
            return PRInstanceSettingsUpdateOutcomeSucceeded;
        case FrontendInstanceSettingsUpdateOutcome::UnknownInstance:
            return PRInstanceSettingsUpdateOutcomeUnknownInstance;
        case FrontendInstanceSettingsUpdateOutcome::Rejected:
            return PRInstanceSettingsUpdateOutcomeRejected;
    }
    throw std::invalid_argument("Facade returned an unknown instance settings update outcome");
}

PRInstanceNotesUpdateOutcome notesUpdateOutcomeFromFacadeResult(FrontendInstanceNotesUpdateOutcome outcome)
{
    switch (outcome) {
        case FrontendInstanceNotesUpdateOutcome::Succeeded:
            return PRInstanceNotesUpdateOutcomeSucceeded;
        case FrontendInstanceNotesUpdateOutcome::UnknownInstance:
            return PRInstanceNotesUpdateOutcomeUnknownInstance;
        case FrontendInstanceNotesUpdateOutcome::Rejected:
            return PRInstanceNotesUpdateOutcomeRejected;
    }
    throw std::invalid_argument("Facade returned an unknown instance notes outcome");
}

NSArray<PRInstanceSummary *> *summariesFromFacadeSnapshots(const std::vector<FrontendInstanceSnapshot>& snapshots)
{
    NSMutableArray<PRInstanceSummary *> *converted = [NSMutableArray arrayWithCapacity:snapshots.size()];
    for (const FrontendInstanceSnapshot& snapshot : snapshots) {
        [converted addObject:summaryFromFacadeSnapshot(snapshot)];
    }
    return [converted copy];
}

PRInstanceChange *changeFromFacadeChange(const FrontendInstanceChange& change)
{
    NSString *identifier = foundationStringFromUTF8(change.instance.id);
    if (!identifier) {
        throw std::invalid_argument("Facade returned an instance change without an identifier");
    }

    PRInstanceChangeKind kind = PRInstanceChangeKindUpdated;
    PRInstanceSummary *summary = nil;
    switch (change.kind) {
        case FrontendInstanceChangeKind::Added:
            kind = PRInstanceChangeKindAdded;
            summary = summaryFromFacadeSnapshot(change.instance);
            break;
        case FrontendInstanceChangeKind::Updated:
            kind = PRInstanceChangeKindUpdated;
            summary = summaryFromFacadeSnapshot(change.instance);
            break;
        case FrontendInstanceChangeKind::Removed:
            kind = PRInstanceChangeKindRemoved;
            break;
        default:
            throw std::invalid_argument("Facade returned an unknown instance change kind");
    }

    PRInstanceChange *converted = [[PRInstanceChange alloc] initWithKind:kind
                                                                 identifier:identifier
                                                                    summary:summary];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid instance change");
    }
    return converted;
}

NSArray<PRInstanceChange *> *changesFromFacadeChanges(const std::vector<FrontendInstanceChange>& changes)
{
    NSMutableArray<PRInstanceChange *> *converted = [NSMutableArray arrayWithCapacity:changes.size()];
    for (const FrontendInstanceChange& change : changes) {
        [converted addObject:changeFromFacadeChange(change)];
    }
    return [converted copy];
}

PRTaskTerminalOutcome terminalOutcomeFromFacadeResult(FrontendTaskTerminalOutcome outcome);
PRTaskCancellationOutcome cancellationOutcomeFromFacadeResult(FrontendTaskCancellationResult outcome);

PRTaskState taskStateFromFacadeState(FrontendTaskState state)
{
    switch (state) {
        case FrontendTaskState::Queued:
            return PRTaskStateQueued;
        case FrontendTaskState::Running:
            return PRTaskStateRunning;
        case FrontendTaskState::Cancelling:
            return PRTaskStateCancelling;
        case FrontendTaskState::Succeeded:
            return PRTaskStateSucceeded;
        case FrontendTaskState::Failed:
            return PRTaskStateFailed;
        case FrontendTaskState::Cancelled:
            return PRTaskStateCancelled;
    }
    throw std::invalid_argument("Facade returned an unknown task state");
}

PRTaskProgressKind taskProgressKindFromFacadeKind(FrontendTaskProgressKind progressKind)
{
    switch (progressKind) {
        case FrontendTaskProgressKind::None:
            return PRTaskProgressKindNone;
        case FrontendTaskProgressKind::Indeterminate:
            return PRTaskProgressKindIndeterminate;
        case FrontendTaskProgressKind::Determinate:
            return PRTaskProgressKindDeterminate;
    }
    throw std::invalid_argument("Facade returned an unknown task progress kind");
}

NSDictionary<NSString *, NSString *> *substitutionValuesFromFacade(
    const std::vector<std::pair<std::string, std::string>>& values)
{
    NSMutableDictionary<NSString *, NSString *> *converted = [NSMutableDictionary dictionaryWithCapacity:values.size()];
    for (const auto& [key, value] : values) {
        NSString *foundationKey = foundationStringFromUTF8(key);
        NSString *foundationValue = foundationStringFromUTF8(value);
        if (!foundationKey || !foundationValue) {
            throw std::invalid_argument("Facade returned invalid task substitution values");
        }
        converted[foundationKey] = foundationValue;
    }
    return [converted copy];
}

PRTaskSubtaskStatus *subtaskFromFacadeSnapshot(const FrontendTaskSubtaskSnapshot& subtask)
{
    PRTaskSubtaskStatus *converted = [[PRTaskSubtaskStatus alloc]
        initWithIdentifier:foundationStringFromUTF8(subtask.id)
                       name:foundationStringFromUTF8(subtask.name)
                      state:taskStateFromFacadeState(subtask.state)
               progressKind:taskProgressKindFromFacadeKind(subtask.progressKind)
           progressFraction:subtask.progressFraction];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid task subtask");
    }
    return converted;
}

PRTaskTerminalResult *terminalResultFromFacadeResult(const FrontendTaskTerminalResult& result)
{
    PRTaskTerminalResult *converted = [[PRTaskTerminalResult alloc]
        initWithOutcome:terminalOutcomeFromFacadeResult(result.outcome)
         localizationKey:foundationStringFromUTF8(result.localizationKey)
     substitutionValues:substitutionValuesFromFacade(result.substitutionValues)
         diagnosticText:foundationStringFromUTF8(result.diagnosticText)
partialChangesRolledBack:result.partialChangesRolledBack];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid task terminal result");
    }
    return converted;
}

PRTaskStatus *taskStatusFromFacadeSnapshot(const FrontendTaskSnapshot& snapshot)
{
    NSMutableArray<PRTaskSubtaskStatus *> *subtasks = [NSMutableArray arrayWithCapacity:snapshot.subtasks.size()];
    for (const FrontendTaskSubtaskSnapshot& subtask : snapshot.subtasks) {
        [subtasks addObject:subtaskFromFacadeSnapshot(subtask)];
    }

    PRTaskTerminalResult *terminalResult = snapshot.terminalResult.has_value()
        ? terminalResultFromFacadeResult(*snapshot.terminalResult)
        : nil;
    PRTaskStatus *converted = [[PRTaskStatus alloc]
        initWithIdentifier:foundationStringFromUTF8(snapshot.id)
                      title:foundationStringFromUTF8(snapshot.title)
                      state:taskStateFromFacadeState(snapshot.state)
               progressKind:taskProgressKindFromFacadeKind(snapshot.progressKind)
           progressFraction:snapshot.progressFraction
        cancellationAllowed:snapshot.cancellationAllowed
                  subtasks:subtasks
             terminalResult:terminalResult];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid task snapshot");
    }
    return converted;
}

PRTaskLogEntry *logEntryFromFacadeEntry(const FrontendLogEntry& entry)
{
    NSString *text = [[NSString alloc] initWithBytes:entry.text.data()
                                              length:entry.text.size()
                                            encoding:NSUTF8StringEncoding];
    if (!text) {
        throw std::invalid_argument("Facade returned invalid UTF-8 log text");
    }

    PRTaskLogEntry *converted = [[PRTaskLogEntry alloc] initWithSequence:entry.sequence
                                                                      text:text
                                                                 truncated:entry.truncated];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid log entry");
    }
    return converted;
}

PRTaskLogSnapshot *logSnapshotFromFacadeSnapshot(const FrontendLogSnapshot& snapshot)
{
    NSMutableArray<PRTaskLogEntry *> *entries = [NSMutableArray arrayWithCapacity:snapshot.entries.size()];
    for (const FrontendLogEntry& entry : snapshot.entries) {
        [entries addObject:logEntryFromFacadeEntry(entry)];
    }

    PRTaskLogSnapshot *converted = [[PRTaskLogSnapshot alloc]
        initWithTaskIdentifier:foundationStringFromUTF8(snapshot.taskId)
                        entries:entries
            droppedEntryCount:snapshot.droppedEntryCount
                 totalByteCount:snapshot.totalByteCount
                     truncated:snapshot.truncated];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid log snapshot");
    }
    return converted;
}

bool isKnownTaskState(PRTaskState state)
{
    switch (state) {
        case PRTaskStateQueued:
        case PRTaskStateRunning:
        case PRTaskStateCancelling:
        case PRTaskStateSucceeded:
        case PRTaskStateFailed:
        case PRTaskStateCancelled:
            return true;
    }
    return false;
}

bool isKnownTaskProgressKind(PRTaskProgressKind progressKind)
{
    switch (progressKind) {
        case PRTaskProgressKindNone:
        case PRTaskProgressKindIndeterminate:
        case PRTaskProgressKindDeterminate:
            return true;
    }
    return false;
}

bool isValidProgress(PRTaskProgressKind progressKind, double progressFraction)
{
    if (!std::isfinite(progressFraction) || !isKnownTaskProgressKind(progressKind)) {
        return false;
    }

    if (progressKind == PRTaskProgressKindDeterminate) {
        return progressFraction >= 0.0 && progressFraction <= 1.0;
    }
    return progressFraction == 0.0;
}

bool isTerminalTaskState(PRTaskState state)
{
    return state == PRTaskStateSucceeded || state == PRTaskStateFailed || state == PRTaskStateCancelled;
}

bool isKnownTaskTerminalOutcome(PRTaskTerminalOutcome outcome)
{
    switch (outcome) {
        case PRTaskTerminalOutcomeSucceeded:
        case PRTaskTerminalOutcomeFailed:
        case PRTaskTerminalOutcomeCancelled:
            return true;
    }
    return false;
}

bool isKnownTaskCancellationOutcome(PRTaskCancellationOutcome outcome)
{
    switch (outcome) {
        case PRTaskCancellationOutcomeRequested:
        case PRTaskCancellationOutcomeAlreadyTerminal:
        case PRTaskCancellationOutcomeUnknownTask:
        case PRTaskCancellationOutcomeRejected:
            return true;
    }
    return false;
}

PRTaskTerminalOutcome terminalOutcomeFromFacadeResult(FrontendTaskTerminalOutcome outcome)
{
    switch (outcome) {
        case FrontendTaskTerminalOutcome::Succeeded:
            return PRTaskTerminalOutcomeSucceeded;
        case FrontendTaskTerminalOutcome::Failed:
            return PRTaskTerminalOutcomeFailed;
        case FrontendTaskTerminalOutcome::Cancelled:
            return PRTaskTerminalOutcomeCancelled;
    }
    throw std::invalid_argument("Facade returned an unknown task terminal outcome");
}

PRTaskCancellationOutcome cancellationOutcomeFromFacadeResult(FrontendTaskCancellationResult outcome)
{
    switch (outcome) {
        case FrontendTaskCancellationResult::Requested:
            return PRTaskCancellationOutcomeRequested;
        case FrontendTaskCancellationResult::AlreadyTerminal:
            return PRTaskCancellationOutcomeAlreadyTerminal;
        case FrontendTaskCancellationResult::UnknownTask:
            return PRTaskCancellationOutcomeUnknownTask;
        case FrontendTaskCancellationResult::Rejected:
            return PRTaskCancellationOutcomeRejected;
    }
    throw std::invalid_argument("Facade returned an unknown task cancellation outcome");
}

bool isKnownBridgeErrorCode(PRBridgeErrorCode code)
{
    switch (code) {
        case PRBridgeErrorCodeUnknown:
        case PRBridgeErrorCodeInvalidInput:
        case PRBridgeErrorCodeDataUnavailable:
        case PRBridgeErrorCodeAuthenticationRequired:
        case PRBridgeErrorCodeOperationCancelled:
        case PRBridgeErrorCodePermissionDenied:
        case PRBridgeErrorCodeNetworkUnavailable:
            return true;
    }
    return false;
}

bool isKnownBridgeErrorRecoveryKind(PRBridgeErrorRecoveryKind recoveryKind)
{
    switch (recoveryKind) {
        case PRBridgeErrorRecoveryKindNone:
        case PRBridgeErrorRecoveryKindRetry:
        case PRBridgeErrorRecoveryKindAuthenticate:
        case PRBridgeErrorRecoveryKindChooseFile:
        case PRBridgeErrorRecoveryKindRevealPath:
        case PRBridgeErrorRecoveryKindOpenSettings:
            return true;
    }
    return false;
}

NSDictionary<NSString *, NSString *> *copyStringDictionary(NSDictionary *candidate)
{
    if (![candidate isKindOfClass:NSDictionary.class]) {
        return nil;
    }

    NSMutableDictionary<NSString *, NSString *> *copy = [NSMutableDictionary dictionaryWithCapacity:candidate.count];
    for (id key in candidate) {
        id value = candidate[key];
        if (![key isKindOfClass:NSString.class] || ![value isKindOfClass:NSString.class] || [key length] == 0) {
            return nil;
        }
        copy[[key copy]] = [value copy];
    }
    return [copy copy];
}
}

NSErrorDomain const PRBridgeErrorDomain = @"com.lloydME.Prism.bridge";
NSString *const PRBridgeErrorLocalizationKeyUserInfoKey = @"PRBridgeErrorLocalizationKey";
NSString *const PRBridgeErrorSubstitutionValuesUserInfoKey = @"PRBridgeErrorSubstitutionValues";
NSString *const PRBridgeErrorDiagnosticTextUserInfoKey = @"PRBridgeErrorDiagnosticText";
NSString *const PRBridgeErrorRecoveryKindUserInfoKey = @"PRBridgeErrorRecoveryKind";
NSString *const PRBridgeErrorPartialChangesRolledBackUserInfoKey = @"PRBridgeErrorPartialChangesRolledBack";

namespace {
enum class NativeFacadeFailureKind : NSInteger {
    Unknown = 0,
    InvalidInput = 1,
    DataUnavailable = 2,
    AuthenticationRequired = 3,
    OperationCancelled = 4,
    PermissionDenied = 5,
    NetworkUnavailable = 6,
};

PRBridgeError *translatedErrorForFailureKind(NSInteger failureKind,
                                             NSString *diagnosticText,
                                             NSDictionary<NSString *, NSString *> *substitutionValues)
{
    PRBridgeErrorCode code = PRBridgeErrorCodeUnknown;
    NSString *localizationKey = @"bridge.error.unknown";
    PRBridgeErrorRecoveryKind recoveryKind = PRBridgeErrorRecoveryKindNone;

    switch (static_cast<NativeFacadeFailureKind>(failureKind)) {
        case NativeFacadeFailureKind::Unknown:
            break;
        case NativeFacadeFailureKind::InvalidInput:
            code = PRBridgeErrorCodeInvalidInput;
            localizationKey = @"bridge.error.invalidInput";
            break;
        case NativeFacadeFailureKind::DataUnavailable:
            code = PRBridgeErrorCodeDataUnavailable;
            localizationKey = @"bridge.error.dataUnavailable";
            recoveryKind = PRBridgeErrorRecoveryKindRetry;
            break;
        case NativeFacadeFailureKind::AuthenticationRequired:
            code = PRBridgeErrorCodeAuthenticationRequired;
            localizationKey = @"bridge.error.authenticationRequired";
            recoveryKind = PRBridgeErrorRecoveryKindAuthenticate;
            break;
        case NativeFacadeFailureKind::OperationCancelled:
            code = PRBridgeErrorCodeOperationCancelled;
            localizationKey = @"bridge.error.operationCancelled";
            break;
        case NativeFacadeFailureKind::PermissionDenied:
            code = PRBridgeErrorCodePermissionDenied;
            localizationKey = @"bridge.error.permissionDenied";
            recoveryKind = PRBridgeErrorRecoveryKindOpenSettings;
            break;
        case NativeFacadeFailureKind::NetworkUnavailable:
            code = PRBridgeErrorCodeNetworkUnavailable;
            localizationKey = @"bridge.error.networkUnavailable";
            recoveryKind = PRBridgeErrorRecoveryKindRetry;
            break;
    }

    return [[PRBridgeError alloc] initWithCode:code
                               localizationKey:localizationKey
                           substitutionValues:substitutionValues ?: @{}
                               diagnosticText:diagnosticText
                                  recoveryKind:recoveryKind
                     partialChangesRolledBack:NO];
}
}

typedef void (^PRBridgeObservationDelivery)(id value);
typedef void (^PRBridgeObservationRemovalHandler)(void);

@interface PRBridgeObservationState : NSObject

- (instancetype)initWithHandler:(PRBridgeObservationDelivery)handler;

@property(nonatomic, copy, nullable) PRBridgeObservationRemovalHandler removalHandler;
@property(nonatomic, assign, readonly, getter=isCancelled) BOOL cancelled;

- (BOOL)cancel;
- (void)deliverOnMainActor:(id)value;

@end

@interface PRBridgeObservationState () {
    NSRecursiveLock *_lock;
    PRBridgeObservationDelivery _handler;
    BOOL _cancelled;
}
@end

@implementation PRBridgeObservationState

- (instancetype)initWithHandler:(PRBridgeObservationDelivery)handler
{
    self = [super init];
    if (self) {
        _lock = [[NSRecursiveLock alloc] init];
        _handler = [handler copy];
    }
    return self;
}

- (BOOL)isCancelled
{
    [_lock lock];
    BOOL cancelled = _cancelled;
    [_lock unlock];
    return cancelled;
}

- (BOOL)cancel
{
    [_lock lock];
    if (_cancelled) {
        [_lock unlock];
        return NO;
    }

    _cancelled = YES;
    _handler = nil;
    PRBridgeObservationRemovalHandler removalHandler = [self.removalHandler copy];
    self.removalHandler = nil;
    [_lock unlock];

    if (removalHandler) {
        removalHandler();
    }
    return YES;
}

- (void)deliverOnMainActor:(id)value
{
    [_lock lock];
    BOOL canSchedule = !_cancelled && _handler != nil;
    [_lock unlock];

    if (!canSchedule) {
        return;
    }

    PRBridgeObservationState *state = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [state->_lock lock];
        PRBridgeObservationDelivery handler = (!state->_cancelled && state->_handler) ? [state->_handler copy] : nil;
        if (handler) {
            try {
                @try {
                    handler(value);
                } @catch (NSException *) {
                }
            } catch (...) {
            }
        }
        [state->_lock unlock];
    });
}

- (void)dealloc
{
    [self cancel];
}

@end

@interface PRBridgeArrayResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithValues:(NSArray *)values error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSArray *values;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeArrayResult

- (instancetype)initWithValues:(NSArray *)values error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _values = [values copy] ?: @[];
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeDetailsResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithDetails:(nullable PRInstanceDetails *)details
                           error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRInstanceDetails *details;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeDetailsResult

- (instancetype)initWithDetails:(PRInstanceDetails *)details error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _details = details;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeCommandResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithResult:(nullable PRInstanceCommandResult *)result
                           error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRInstanceCommandResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeCommandResult

- (instancetype)initWithResult:(PRInstanceCommandResult *)result error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _result = result;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeNotesUpdateResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithResult:(nullable PRInstanceNotesUpdateResult *)result
                           error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRInstanceNotesUpdateResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeNotesUpdateResult

- (instancetype)initWithResult:(PRInstanceNotesUpdateResult *)result error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _result = result;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeSettingsResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithSettings:(nullable PRInstanceSettings *)settings
                            error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRInstanceSettings *settings;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeSettingsResult

- (instancetype)initWithSettings:(PRInstanceSettings *)settings error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _settings = settings;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeSettingsUpdateResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithResult:(nullable PRInstanceSettingsUpdateResult *)result
                           error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRInstanceSettingsUpdateResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeSettingsUpdateResult

- (instancetype)initWithResult:(PRInstanceSettingsUpdateResult *)result error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _result = result;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeTaskStatusResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithStatus:(nullable PRTaskStatus *)status
                           error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRTaskStatus *status;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeTaskStatusResult

- (instancetype)initWithStatus:(PRTaskStatus *)status error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _status = status;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeTaskLogResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithSnapshot:(nullable PRTaskLogSnapshot *)snapshot
                             error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRTaskLogSnapshot *snapshot;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeTaskLogResult

- (instancetype)initWithSnapshot:(PRTaskLogSnapshot *)snapshot error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _snapshot = snapshot;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeTaskCancellationResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithResult:(nullable PRTaskCancellationResult *)result
                           error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRTaskCancellationResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeTaskCancellationResult

- (instancetype)initWithResult:(PRTaskCancellationResult *)result error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _result = result;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeObservationToken ()

@property(nonatomic, strong) PRBridgeObservationState *state;
- (instancetype)initWithState:(PRBridgeObservationState *)state NS_DESIGNATED_INITIALIZER;

@end

@implementation PRBridgeObservationToken

- (instancetype)initWithState:(PRBridgeObservationState *)state
{
    self = [super init];
    if (self) {
        self.state = state;
    }
    return self;
}

- (BOOL)isCancelled
{
    return self.state.isCancelled;
}

- (BOOL)cancel
{
    return [self.state cancel];
}

- (void)dealloc
{
    [self.state cancel];
}

@end

@interface PRApplicationIdentity ()

@property(nonatomic, copy, readwrite) NSString *bundleIdentifier;
@property(nonatomic, copy, readwrite) NSURL *applicationSupportDirectory;

@end

@interface PRPrismBridge () {
    std::unique_ptr<NativeFacadeLifecycle> _lifecycle;
    std::unique_ptr<FrontendFacade> _facade;
    std::mutex _lifecycleLock;
    std::mutex _facadeLock;
    dispatch_queue_t _backendQueue;
}

@property(nonatomic, copy, readwrite) NSURL *dataRootURL;
@property(nonatomic, copy, readwrite, nullable) PRBridgeLifecycleHandler cancellationHandler;
@property(nonatomic, copy, readwrite, nullable) PRBridgeLifecycleHandler shutdownHandler;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *instanceObservationStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *instanceChangeObservationStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *taskObservationStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *snapshotRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *changeRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *detailsRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *taskRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *taskLogRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *taskCancellationRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *commandRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *notesUpdateRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *settingsRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *settingsUpdateRequestStates;
@property(nonatomic, strong) NSLock *observationLock;

- (nullable instancetype)initWithDataRootURL:(NSURL *)dataRootURL
                          cancellationHandler:(nullable PRBridgeLifecycleHandler)cancellationHandler
                             shutdownHandler:(nullable PRBridgeLifecycleHandler)shutdownHandler
                   frontendRuntimeDependencies:(FrontendRuntimeDependencies)runtimeDependencies NS_DESIGNATED_INITIALIZER;
- (BOOL)isLifecycleRunning;
- (void)removeInstanceObservation:(PRBridgeObservationState *)observation;
- (void)removeInstanceChangeObservation:(PRBridgeObservationState *)observation;
- (void)removeTaskObservation:(PRBridgeObservationState *)observation;
- (void)removeSnapshotRequest:(PRBridgeObservationState *)request;
- (void)removeChangeRequest:(PRBridgeObservationState *)request;
- (void)removeDetailsRequest:(PRBridgeObservationState *)request;
- (void)removeTaskRequest:(PRBridgeObservationState *)request;
- (void)removeTaskLogRequest:(PRBridgeObservationState *)request;
- (void)removeTaskCancellationRequest:(PRBridgeObservationState *)request;
- (void)removeCommandRequest:(PRBridgeObservationState *)request;
- (void)removeNotesUpdateRequest:(PRBridgeObservationState *)request;
- (void)removeSettingsRequest:(PRBridgeObservationState *)request;
- (void)removeSettingsUpdateRequest:(PRBridgeObservationState *)request;
- (nullable PRBridgeObservationToken *)loadTaskStatusWithIdentifier:(NSString *)identifier
                                                            completion:(PRTaskStatusCompletionHandler)completion;
- (nullable PRBridgeObservationToken *)performTaskCancellationWithIdentifier:(NSString *)identifier
                                                                     completion:(PRTaskCancellationCompletionHandler)completion;
- (nullable PRBridgeObservationToken *)performInstanceCommand:(PRInstanceCommandKind)kind
                                                      identifier:(NSString *)identifier
                                                     completion:(PRInstanceCommandCompletionHandler)completion;
- (void)cancelAllObservations;
- (void)publishInstanceSummary:(PRInstanceSummary *)summary;
- (void)publishInstanceChange:(PRInstanceChange *)change;
- (void)publishTaskStatus:(PRTaskStatus *)status;
- (PRBridgeError *)bridgeErrorForFailureKind:(NSInteger)failureKind
                               diagnosticText:(nullable NSString *)diagnosticText
                           substitutionValues:(NSDictionary<NSString *, NSString *> *)substitutionValues;

@end

@interface PRInstanceSummary ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, copy, readwrite, nullable) NSString *iconKey;
@property(nonatomic, copy, readwrite, nullable) NSString *groupID;

@end

@interface PRInstanceDetails ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, copy, readwrite, nullable) NSString *iconKey;
@property(nonatomic, copy, readwrite, nullable) NSString *groupID;
@property(nonatomic, copy, readwrite, nullable) NSString *instanceType;
@property(nonatomic, copy, readwrite) NSString *notes;
@property(nonatomic, assign, readwrite) BOOL notesEditable;

@end

@interface PRInstanceCommandResult ()

@property(nonatomic, assign, readwrite) PRInstanceCommandKind kind;
@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, assign, readwrite) PRInstanceCommandOutcome outcome;

@end

@interface PRInstanceNotesUpdateResult ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite) NSString *notes;
@property(nonatomic, assign, readwrite) PRInstanceNotesUpdateOutcome outcome;

@end

@interface PRInstanceSettings ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, assign, readwrite) BOOL windowOverrideEnabled;
@property(nonatomic, assign, readwrite) BOOL launchMaximized;
@property(nonatomic, assign, readwrite) NSInteger windowWidth;
@property(nonatomic, assign, readwrite) NSInteger windowHeight;
@property(nonatomic, assign, readwrite) BOOL closeAfterLaunch;
@property(nonatomic, assign, readwrite) BOOL quitAfterGameStop;
@property(nonatomic, assign, readwrite) BOOL consoleOverrideEnabled;
@property(nonatomic, assign, readwrite) BOOL showConsole;
@property(nonatomic, assign, readwrite) BOOL showConsoleOnError;
@property(nonatomic, assign, readwrite) BOOL autoCloseConsole;
@property(nonatomic, assign, readwrite) BOOL globalDataPacksEnabled;
@property(nonatomic, copy, readwrite) NSString *globalDataPacksPath;
@property(nonatomic, assign, readwrite) BOOL gameTimeOverrideEnabled;
@property(nonatomic, assign, readwrite) BOOL showGameTime;
@property(nonatomic, assign, readwrite) BOOL recordGameTime;
@property(nonatomic, assign, readwrite) BOOL countGameTime;
@property(nonatomic, assign, readwrite) BOOL joinServerOnLaunch;
@property(nonatomic, assign, readwrite) PRInstanceJoinTarget joinTarget;
@property(nonatomic, copy, readwrite) NSString *joinServerAddress;
@property(nonatomic, copy, readwrite) NSString *joinWorld;
@property(nonatomic, assign, readwrite) BOOL overrideModDownloadLoaders;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *modDownloadLoaders;
@property(nonatomic, assign, readwrite) BOOL javaLocationOverrideEnabled;
@property(nonatomic, copy, readwrite) NSString *javaPath;
@property(nonatomic, assign, readwrite) BOOL ignoreJavaCompatibility;
@property(nonatomic, assign, readwrite) BOOL memoryOverrideEnabled;
@property(nonatomic, assign, readwrite) NSInteger minMemoryMiB;
@property(nonatomic, assign, readwrite) NSInteger maxMemoryMiB;
@property(nonatomic, assign, readwrite) NSInteger permGenMiB;
@property(nonatomic, assign, readwrite) BOOL lowMemoryWarning;
@property(nonatomic, assign, readwrite) BOOL javaArgumentsOverrideEnabled;
@property(nonatomic, copy, readwrite) NSString *jvmArguments;
@property(nonatomic, assign, readwrite) BOOL commandOverrideEnabled;
@property(nonatomic, copy, readwrite) NSString *preLaunchCommand;
@property(nonatomic, copy, readwrite) NSString *wrapperCommand;
@property(nonatomic, copy, readwrite) NSString *postExitCommand;
@property(nonatomic, assign, readwrite) BOOL legacySettingsOverrideEnabled;
@property(nonatomic, assign, readwrite) BOOL onlineFixes;
@property(nonatomic, assign, readwrite) BOOL nativeWorkaroundsOverrideEnabled;
@property(nonatomic, assign, readwrite) BOOL useNativeGLFW;
@property(nonatomic, copy, readwrite) NSString *customGLFWPath;
@property(nonatomic, assign, readwrite) BOOL useNativeOpenAL;
@property(nonatomic, copy, readwrite) NSString *customOpenALPath;

@end

@interface PRInstanceSettingsUpdateResult ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, strong, readwrite, nullable) PRInstanceSettings *settings;
@property(nonatomic, assign, readwrite) PRInstanceSettingsUpdateOutcome outcome;

@end

@interface PRInstanceChange ()

@property(nonatomic, assign, readwrite) PRInstanceChangeKind kind;
@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, strong, readwrite, nullable) PRInstanceSummary *summary;

@end

@interface PRTaskSubtaskStatus ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, assign, readwrite) PRTaskState state;
@property(nonatomic, assign, readwrite) PRTaskProgressKind progressKind;
@property(nonatomic, assign, readwrite) double progressFraction;

@end

@interface PRTaskTerminalResult ()

@property(nonatomic, assign, readwrite) PRTaskTerminalOutcome outcome;
@property(nonatomic, copy, readwrite) NSString *localizationKey;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, NSString *> *substitutionValues;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readwrite) BOOL partialChangesRolledBack;

@end

@interface PRTaskStatus ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite, nullable) NSString *title;
@property(nonatomic, assign, readwrite) PRTaskState state;
@property(nonatomic, assign, readwrite) PRTaskProgressKind progressKind;
@property(nonatomic, assign, readwrite) double progressFraction;
@property(nonatomic, assign, readwrite) BOOL cancellationAllowed;
@property(nonatomic, copy, readwrite) NSArray<PRTaskSubtaskStatus *> *subtasks;
@property(nonatomic, strong, readwrite, nullable) PRTaskTerminalResult *terminalResult;


@end

@interface PRTaskCancellationResult ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, assign, readwrite) PRTaskCancellationOutcome outcome;

@end

@interface PRTaskLogEntry ()

@property(nonatomic, assign, readwrite) uint64_t sequence;
@property(nonatomic, copy, readwrite) NSString *text;
@property(nonatomic, assign, readwrite) BOOL truncated;

@end

@interface PRTaskLogSnapshot ()

@property(nonatomic, copy, readwrite) NSString *taskIdentifier;
@property(nonatomic, copy, readwrite) NSArray<PRTaskLogEntry *> *entries;
@property(nonatomic, assign, readwrite) uint64_t droppedEntryCount;
@property(nonatomic, assign, readwrite) uint64_t totalByteCount;
@property(nonatomic, assign, readwrite) BOOL truncated;

@end

@interface PRBridgeError ()

@property(nonatomic, copy, readwrite) NSString *domain;
@property(nonatomic, assign, readwrite) PRBridgeErrorCode code;
@property(nonatomic, copy, readwrite) NSString *localizationKey;
@property(nonatomic, copy, readwrite) NSDictionary<NSString *, NSString *> *substitutionValues;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readwrite) PRBridgeErrorRecoveryKind recoveryKind;
@property(nonatomic, assign, readwrite) BOOL partialChangesRolledBack;
@property(nonatomic, copy, readwrite) NSError *foundationError;

@end

@implementation PRApplicationIdentity

+ (NSString *)requiredBundleIdentifier
{
    return kPrismBundleIdentifier;
}

+ (NSString *)applicationName
{
    return kPrismApplicationName;
}

- (instancetype)init
{
    NSURL *baseURL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
                                                            inDomain:NSUserDomainMask
                                                   appropriateForURL:nil
                                                              create:NO
                                                               error:nil];
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier ?: @"";
    return [self initWithBundleIdentifier:bundleIdentifier
            applicationSupportBaseDirectory:baseURL];
}

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier
           applicationSupportBaseDirectory:(NSURL *)applicationSupportBaseDirectory
{
    self = [super init];
    if (self) {
        self.bundleIdentifier = bundleIdentifier;
        self.applicationSupportDirectory = [applicationSupportBaseDirectory URLByAppendingPathComponent:kPrismApplicationName
                                                                                               isDirectory:YES];
    }
    return self;
}

- (NSString *)applicationName
{
    return kPrismApplicationName;
}

@end

@implementation PRInstanceSummary

- (instancetype)initWithIdentifier:(NSString *)identifier
                               name:(NSString *)name
                            iconKey:(NSString *)iconKey
                            groupID:(NSString *)groupID
{
    if (!isNonEmptyString(identifier) || !isNonEmptyString(name)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.name = [name copy];
        self.iconKey = nullableStringCopy(iconKey);
        self.groupID = nullableStringCopy(groupID);
    }
    return self;
}

@end

@implementation PRInstanceDetails

- (instancetype)initWithIdentifier:(NSString *)identifier
                               name:(NSString *)name
                            iconKey:(NSString *)iconKey
                            groupID:(NSString *)groupID
                      instanceType:(NSString *)instanceType
                             notes:(NSString *)notes
                     notesEditable:(BOOL)notesEditable
{
    if (!isNonEmptyString(identifier) || !isNonEmptyString(name) || ![notes isKindOfClass:NSString.class]) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.name = [name copy];
        self.iconKey = nullableStringCopy(iconKey);
        self.groupID = nullableStringCopy(groupID);
        self.instanceType = nullableStringCopy(instanceType);
        self.notes = [notes copy];
        self.notesEditable = notesEditable;
    }
    return self;
}

@end

@implementation PRInstanceCommandResult

- (instancetype)initWithKind:(PRInstanceCommandKind)kind
                   identifier:(NSString *)identifier
                      outcome:(PRInstanceCommandOutcome)outcome
{
    if (!isKnownInstanceCommandKind(kind) || !isNonEmptyString(identifier) || !isKnownInstanceCommandOutcome(outcome)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.kind = kind;
        self.identifier = [identifier copy];
        self.outcome = outcome;
    }
    return self;
}

@end

@implementation PRInstanceNotesUpdateResult

- (instancetype)initWithIdentifier:(NSString *)identifier
                              notes:(NSString *)notes
                            outcome:(PRInstanceNotesUpdateOutcome)outcome
{
    if (!isNonEmptyString(identifier) || ![notes isKindOfClass:NSString.class]
        || !isKnownInstanceNotesUpdateOutcome(outcome)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.notes = [notes copy];
        self.outcome = outcome;
    }
    return self;
}

@end

@implementation PRInstanceSettings

- (instancetype)initWithIdentifier:(NSString *)identifier
              windowOverrideEnabled:(BOOL)windowOverrideEnabled
                     launchMaximized:(BOOL)launchMaximized
                        windowWidth:(NSInteger)windowWidth
                       windowHeight:(NSInteger)windowHeight
                 closeAfterLaunch:(BOOL)closeAfterLaunch
               quitAfterGameStop:(BOOL)quitAfterGameStop
             consoleOverrideEnabled:(BOOL)consoleOverrideEnabled
                      showConsole:(BOOL)showConsole
               showConsoleOnError:(BOOL)showConsoleOnError
                 autoCloseConsole:(BOOL)autoCloseConsole
           globalDataPacksEnabled:(BOOL)globalDataPacksEnabled
             globalDataPacksPath:(NSString *)globalDataPacksPath
           gameTimeOverrideEnabled:(BOOL)gameTimeOverrideEnabled
                   showGameTime:(BOOL)showGameTime
                 recordGameTime:(BOOL)recordGameTime
                  countGameTime:(BOOL)countGameTime
              joinServerOnLaunch:(BOOL)joinServerOnLaunch
                      joinTarget:(PRInstanceJoinTarget)joinTarget
            joinServerAddress:(NSString *)joinServerAddress
                   joinWorld:(NSString *)joinWorld
       overrideModDownloadLoaders:(BOOL)overrideModDownloadLoaders
            modDownloadLoaders:(NSArray<NSString *> *)modDownloadLoaders
       javaLocationOverrideEnabled:(BOOL)javaLocationOverrideEnabled
                       javaPath:(NSString *)javaPath
         ignoreJavaCompatibility:(BOOL)ignoreJavaCompatibility
             memoryOverrideEnabled:(BOOL)memoryOverrideEnabled
                  minMemoryMiB:(NSInteger)minMemoryMiB
                  maxMemoryMiB:(NSInteger)maxMemoryMiB
                     permGenMiB:(NSInteger)permGenMiB
               lowMemoryWarning:(BOOL)lowMemoryWarning
       javaArgumentsOverrideEnabled:(BOOL)javaArgumentsOverrideEnabled
                  jvmArguments:(NSString *)jvmArguments
          commandOverrideEnabled:(BOOL)commandOverrideEnabled
               preLaunchCommand:(NSString *)preLaunchCommand
                 wrapperCommand:(NSString *)wrapperCommand
              postExitCommand:(NSString *)postExitCommand
     legacySettingsOverrideEnabled:(BOOL)legacySettingsOverrideEnabled
                   onlineFixes:(BOOL)onlineFixes
  nativeWorkaroundsOverrideEnabled:(BOOL)nativeWorkaroundsOverrideEnabled
                 useNativeGLFW:(BOOL)useNativeGLFW
               customGLFWPath:(NSString *)customGLFWPath
                 useNativeOpenAL:(BOOL)useNativeOpenAL
               customOpenALPath:(NSString *)customOpenALPath
{
    NSArray<NSString *> *copiedLoaders = [modDownloadLoaders isKindOfClass:NSArray.class] ? [modDownloadLoaders copy] : nil;
    NSArray *loaderValues = copiedLoaders;
    if (!isNonEmptyString(identifier) || ![globalDataPacksPath isKindOfClass:NSString.class]
        || ![joinServerAddress isKindOfClass:NSString.class] || ![joinWorld isKindOfClass:NSString.class]
        || ![javaPath isKindOfClass:NSString.class] || ![jvmArguments isKindOfClass:NSString.class]
        || ![preLaunchCommand isKindOfClass:NSString.class] || ![wrapperCommand isKindOfClass:NSString.class]
        || ![postExitCommand isKindOfClass:NSString.class] || ![customGLFWPath isKindOfClass:NSString.class]
        || ![customOpenALPath isKindOfClass:NSString.class] || !isKnownInstanceJoinTarget(joinTarget)
        || windowWidth < 1 || windowWidth > 65536 || windowHeight < 1 || windowHeight > 65536 || minMemoryMiB < 8
        || minMemoryMiB > 1048576 || maxMemoryMiB < 8 || maxMemoryMiB > 1048576 || minMemoryMiB > maxMemoryMiB
        || permGenMiB < 4 || permGenMiB > 1048576 || !loaderValues) {
        return nil;
    }
    for (id loader in loaderValues) {
        if (!isNonEmptyString((NSString *)loader)) {
            return nil;
        }
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.windowOverrideEnabled = windowOverrideEnabled;
        self.launchMaximized = launchMaximized;
        self.windowWidth = windowWidth;
        self.windowHeight = windowHeight;
        self.closeAfterLaunch = closeAfterLaunch;
        self.quitAfterGameStop = quitAfterGameStop;
        self.consoleOverrideEnabled = consoleOverrideEnabled;
        self.showConsole = showConsole;
        self.showConsoleOnError = showConsoleOnError;
        self.autoCloseConsole = autoCloseConsole;
        self.globalDataPacksEnabled = globalDataPacksEnabled;
        self.globalDataPacksPath = [globalDataPacksPath copy];
        self.gameTimeOverrideEnabled = gameTimeOverrideEnabled;
        self.showGameTime = showGameTime;
        self.recordGameTime = recordGameTime;
        self.countGameTime = countGameTime;
        self.joinServerOnLaunch = joinServerOnLaunch;
        self.joinTarget = joinTarget;
        self.joinServerAddress = [joinServerAddress copy];
        self.joinWorld = [joinWorld copy];
        self.overrideModDownloadLoaders = overrideModDownloadLoaders;
        self.modDownloadLoaders = copiedLoaders;
        self.javaLocationOverrideEnabled = javaLocationOverrideEnabled;
        self.javaPath = [javaPath copy];
        self.ignoreJavaCompatibility = ignoreJavaCompatibility;
        self.memoryOverrideEnabled = memoryOverrideEnabled;
        self.minMemoryMiB = minMemoryMiB;
        self.maxMemoryMiB = maxMemoryMiB;
        self.permGenMiB = permGenMiB;
        self.lowMemoryWarning = lowMemoryWarning;
        self.javaArgumentsOverrideEnabled = javaArgumentsOverrideEnabled;
        self.jvmArguments = [jvmArguments copy];
        self.commandOverrideEnabled = commandOverrideEnabled;
        self.preLaunchCommand = [preLaunchCommand copy];
        self.wrapperCommand = [wrapperCommand copy];
        self.postExitCommand = [postExitCommand copy];
        self.legacySettingsOverrideEnabled = legacySettingsOverrideEnabled;
        self.onlineFixes = onlineFixes;
        self.nativeWorkaroundsOverrideEnabled = nativeWorkaroundsOverrideEnabled;
        self.useNativeGLFW = useNativeGLFW;
        self.customGLFWPath = [customGLFWPath copy];
        self.useNativeOpenAL = useNativeOpenAL;
        self.customOpenALPath = [customOpenALPath copy];
    }
    return self;
}

@end

@implementation PRInstanceSettingsUpdateResult

- (instancetype)initWithIdentifier:(NSString *)identifier
                            settings:(PRInstanceSettings *)settings
                            outcome:(PRInstanceSettingsUpdateOutcome)outcome
{
    if (!isNonEmptyString(identifier) || !isKnownInstanceSettingsUpdateOutcome(outcome)
        || (outcome == PRInstanceSettingsUpdateOutcomeSucceeded && !settings)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.settings = settings;
        self.outcome = outcome;
    }
    return self;
}

@end

@implementation PRTaskSubtaskStatus

- (instancetype)initWithIdentifier:(NSString *)identifier
                               name:(NSString *)name
                              state:(PRTaskState)state
                       progressKind:(PRTaskProgressKind)progressKind
                   progressFraction:(double)progressFraction
{
    if (!isNonEmptyString(identifier) || !isNonEmptyString(name) || !isKnownTaskState(state)
        || !isValidProgress(progressKind, progressFraction)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.name = [name copy];
        self.state = state;
        self.progressKind = progressKind;
        self.progressFraction = progressFraction;
    }
    return self;
}

@end

@implementation PRTaskTerminalResult

- (instancetype)initWithOutcome:(PRTaskTerminalOutcome)outcome
                 localizationKey:(NSString *)localizationKey
             substitutionValues:(NSDictionary<NSString *, NSString *> *)substitutionValues
                 diagnosticText:(NSString *)diagnosticText
        partialChangesRolledBack:(BOOL)partialChangesRolledBack
{
    NSDictionary<NSString *, NSString *> *copiedSubstitutionValues = copyStringDictionary(substitutionValues);
    if (!isKnownTaskTerminalOutcome(outcome) || !isNonEmptyString(localizationKey) || !copiedSubstitutionValues) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.outcome = outcome;
        self.localizationKey = [localizationKey copy];
        self.substitutionValues = copiedSubstitutionValues;
        self.diagnosticText = nullableStringCopy(diagnosticText);
        self.partialChangesRolledBack = partialChangesRolledBack;
    }
    return self;
}

@end

@implementation PRInstanceChange

- (instancetype)initWithKind:(PRInstanceChangeKind)kind
                   identifier:(NSString *)identifier
                      summary:(PRInstanceSummary *)summary
{
    if (!isKnownInstanceChangeKind(kind) || !isNonEmptyString(identifier)) {
        return nil;
    }

    if ((kind == PRInstanceChangeKindAdded || kind == PRInstanceChangeKindUpdated) && !summary) {
        return nil;
    }
    if (summary && ![summary.identifier isEqualToString:identifier]) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.kind = kind;
        self.identifier = [identifier copy];
        self.summary = summary;
    }
    return self;
}

@end

@implementation PRTaskStatus

- (instancetype)initWithIdentifier:(NSString *)identifier
                              state:(PRTaskState)state
                       progressKind:(PRTaskProgressKind)progressKind
                   progressFraction:(double)progressFraction
                cancellationAllowed:(BOOL)cancellationAllowed
{
    return [self initWithIdentifier:identifier
                               title:nil
                               state:state
                        progressKind:progressKind
                    progressFraction:progressFraction
                 cancellationAllowed:cancellationAllowed
                           subtasks:@[]
                      terminalResult:nil];
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                              title:(NSString *)title
                              state:(PRTaskState)state
                       progressKind:(PRTaskProgressKind)progressKind
                   progressFraction:(double)progressFraction
                cancellationAllowed:(BOOL)cancellationAllowed
                          subtasks:(NSArray<PRTaskSubtaskStatus *> *)subtasks
                     terminalResult:(PRTaskTerminalResult *)terminalResult
{
    if (!isNonEmptyString(identifier) || !isKnownTaskState(state) || !isValidProgress(progressKind, progressFraction)
        || ![subtasks isKindOfClass:NSArray.class]) {
        return nil;
    }

    if ((state == PRTaskStateCancelling || isTerminalTaskState(state)) && cancellationAllowed) {
        return nil;
    }

    NSMutableSet<NSString *> *subtaskIdentifiers = [NSMutableSet setWithCapacity:subtasks.count];
    for (id candidate in subtasks) {
        if (![candidate isKindOfClass:PRTaskSubtaskStatus.class]) {
            return nil;
        }
        PRTaskSubtaskStatus *subtask = (PRTaskSubtaskStatus *)candidate;
        if ([subtaskIdentifiers containsObject:subtask.identifier]) {
            return nil;
        }
        [subtaskIdentifiers addObject:subtask.identifier];
    }

    if (terminalResult && !isTerminalTaskState(state)) {
        return nil;
    }
    if (isTerminalTaskState(state) && !terminalResult) {
        return nil;
    }
    if (terminalResult) {
        BOOL matchingOutcome = (state == PRTaskStateSucceeded && terminalResult.outcome == PRTaskTerminalOutcomeSucceeded)
            || (state == PRTaskStateFailed && terminalResult.outcome == PRTaskTerminalOutcomeFailed)
            || (state == PRTaskStateCancelled && terminalResult.outcome == PRTaskTerminalOutcomeCancelled);
        if (!matchingOutcome) {
            return nil;
        }
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.title = nullableStringCopy(title);
        self.state = state;
        self.progressKind = progressKind;
        self.progressFraction = progressFraction;
        self.cancellationAllowed = cancellationAllowed;
        self.subtasks = [subtasks copy];
        self.terminalResult = terminalResult;
    }
    return self;
}

@end

@implementation PRTaskCancellationResult

- (instancetype)initWithIdentifier:(NSString *)identifier outcome:(PRTaskCancellationOutcome)outcome
{
    if (!isNonEmptyString(identifier) || !isKnownTaskCancellationOutcome(outcome)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.outcome = outcome;
    }
    return self;
}

@end

@implementation PRTaskLogEntry

- (instancetype)initWithSequence:(uint64_t)sequence
                              text:(NSString *)text
                         truncated:(BOOL)truncated
{
    if (![text isKindOfClass:NSString.class]) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.sequence = sequence;
        self.text = [text copy];
        self.truncated = truncated;
    }
    return self;
}

@end

@implementation PRTaskLogSnapshot

- (instancetype)initWithTaskIdentifier:(NSString *)taskIdentifier
                                entries:(NSArray<PRTaskLogEntry *> *)entries
                    droppedEntryCount:(uint64_t)droppedEntryCount
                         totalByteCount:(uint64_t)totalByteCount
                             truncated:(BOOL)truncated
{
    if (!isNonEmptyString(taskIdentifier) || ![entries isKindOfClass:NSArray.class]
        || entries.count > kFrontendLogMaxEntries || totalByteCount > kFrontendLogMaxBytes) {
        return nil;
    }

    NSMutableSet<NSNumber *> *sequences = [NSMutableSet setWithCapacity:entries.count];
    uint64_t calculatedByteCount = 0;
    BOOL containsTruncatedEntry = NO;
    for (id candidate in entries) {
        if (![candidate isKindOfClass:PRTaskLogEntry.class]) {
            return nil;
        }
        PRTaskLogEntry *entry = (PRTaskLogEntry *)candidate;
        NSNumber *sequence = @(entry.sequence);
        if ([sequences containsObject:sequence]) {
            return nil;
        }
        [sequences addObject:sequence];

        NSUInteger byteCount = [entry.text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        if (byteCount > kFrontendLogMaxBytes || UINT64_MAX - calculatedByteCount < byteCount) {
            return nil;
        }
        calculatedByteCount += byteCount;
        containsTruncatedEntry = containsTruncatedEntry || entry.truncated;
    }
    if (calculatedByteCount != totalByteCount || (!truncated && (droppedEntryCount > 0 || containsTruncatedEntry))) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.taskIdentifier = [taskIdentifier copy];
        self.entries = [entries copy];
        self.droppedEntryCount = droppedEntryCount;
        self.totalByteCount = totalByteCount;
        self.truncated = truncated;
    }
    return self;
}

@end

@implementation PRBridgeError

- (instancetype)initWithCode:(PRBridgeErrorCode)code
               localizationKey:(NSString *)localizationKey
           substitutionValues:(NSDictionary<NSString *, NSString *> *)substitutionValues
               diagnosticText:(NSString *)diagnosticText
                  recoveryKind:(PRBridgeErrorRecoveryKind)recoveryKind
     partialChangesRolledBack:(BOOL)partialChangesRolledBack
{
    NSDictionary<NSString *, NSString *> *copiedSubstitutionValues = copyStringDictionary(substitutionValues);
    if (!isKnownBridgeErrorCode(code) || !isNonEmptyString(localizationKey) || !copiedSubstitutionValues
        || !isKnownBridgeErrorRecoveryKind(recoveryKind)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.domain = PRBridgeErrorDomain;
        self.code = code;
        self.localizationKey = [localizationKey copy];
        self.substitutionValues = copiedSubstitutionValues;
        self.diagnosticText = nullableStringCopy(diagnosticText);
        self.recoveryKind = recoveryKind;
        self.partialChangesRolledBack = partialChangesRolledBack;

        NSMutableDictionary *userInfo = [@{
            PRBridgeErrorLocalizationKeyUserInfoKey: self.localizationKey,
            PRBridgeErrorSubstitutionValuesUserInfoKey: self.substitutionValues,
            PRBridgeErrorRecoveryKindUserInfoKey: @(self.recoveryKind),
            PRBridgeErrorPartialChangesRolledBackUserInfoKey: @(self.partialChangesRolledBack),
        } mutableCopy];
        if (self.diagnosticText) {
            userInfo[PRBridgeErrorDiagnosticTextUserInfoKey] = self.diagnosticText;
        }
        self.foundationError = [NSError errorWithDomain:self.domain code:self.code userInfo:userInfo];
    }
    return self;
}

@end

@implementation PRPrismBridge

- (instancetype)initWithDataRootURL:(NSURL *)dataRootURL
                  cancellationHandler:(PRBridgeLifecycleHandler)cancellationHandler
                     shutdownHandler:(PRBridgeLifecycleHandler)shutdownHandler
{
    return [self initWithDataRootURL:dataRootURL
                   cancellationHandler:cancellationHandler
                      shutdownHandler:shutdownHandler
            frontendRuntimeDependencies:defaultRuntimeDependencies()];
}

- (instancetype)initWithDataRootURL:(NSURL *)dataRootURL
                  cancellationHandler:(PRBridgeLifecycleHandler)cancellationHandler
                     shutdownHandler:(PRBridgeLifecycleHandler)shutdownHandler
           frontendRuntimeDependencies:(FrontendRuntimeDependencies)runtimeDependencies
{
    NSURL *normalizedURL = normalizedDataRootURL(dataRootURL);
    if (!normalizedURL) {
        return nil;
    }

    std::unique_ptr<FrontendFacade> facade;
    try {
        facade = std::make_unique<FrontendFacade>(dataRootPathForURL(normalizedURL), std::move(runtimeDependencies));
    } catch (...) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.dataRootURL = normalizedURL;
        self.cancellationHandler = cancellationHandler;
        self.shutdownHandler = shutdownHandler;
        self.instanceObservationStates = [NSMutableArray array];
        self.instanceChangeObservationStates = [NSMutableArray array];
        self.taskObservationStates = [NSMutableArray array];
        self.snapshotRequestStates = [NSMutableArray array];
        self.changeRequestStates = [NSMutableArray array];
        self.detailsRequestStates = [NSMutableArray array];
        self.taskRequestStates = [NSMutableArray array];
        self.taskLogRequestStates = [NSMutableArray array];
        self.taskCancellationRequestStates = [NSMutableArray array];
        self.commandRequestStates = [NSMutableArray array];
        self.notesUpdateRequestStates = [NSMutableArray array];
        self.settingsRequestStates = [NSMutableArray array];
        self.settingsUpdateRequestStates = [NSMutableArray array];
        self.observationLock = [[NSLock alloc] init];
        _lifecycle = std::make_unique<NativeFacadeLifecycle>();
        _facade = std::move(facade);
        _backendQueue = dispatch_queue_create("com.lloydME.PrismNative.frontend", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)isLifecycleRunning
{
    std::lock_guard<std::mutex> lock(_lifecycleLock);
    return _lifecycle && _lifecycle->state() == PRBridgeLifecycleStateRunning;
}

- (PRBridgeObservationToken *)observeInstanceSummariesWithHandler:(PRInstanceSummaryObservationHandler)handler
{
    if (!handler || ![self isLifecycleRunning]) {
        return nil;
    }

    PRBridgeObservationState *observation = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        handler((PRInstanceSummary *)value);
    }];
    __weak PRPrismBridge *weakBridge = self;
    __weak PRBridgeObservationState *weakObservation = observation;
    observation.removalHandler = ^{
        [weakBridge removeInstanceObservation:weakObservation];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning]) {
        [self.observationLock unlock];
        [observation cancel];
        return nil;
    }
    [self.instanceObservationStates addObject:observation];
    [self.observationLock unlock];

    return [[PRBridgeObservationToken alloc] initWithState:observation];
}

- (PRBridgeObservationToken *)observeInstanceChangesWithHandler:(PRInstanceChangeObservationHandler)handler
{
    if (!handler || ![self isLifecycleRunning]) {
        return nil;
    }

    PRBridgeObservationState *observation = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        handler((PRInstanceChange *)value);
    }];
    __weak PRPrismBridge *weakBridge = self;
    __weak PRBridgeObservationState *weakObservation = observation;
    observation.removalHandler = ^{
        [weakBridge removeInstanceChangeObservation:weakObservation];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning]) {
        [self.observationLock unlock];
        [observation cancel];
        return nil;
    }
    [self.instanceChangeObservationStates addObject:observation];
    [self.observationLock unlock];

    return [[PRBridgeObservationToken alloc] initWithState:observation];
}

- (PRBridgeObservationToken *)observeTaskStatusWithHandler:(PRTaskStatusObservationHandler)handler
{
    if (!handler || ![self isLifecycleRunning]) {
        return nil;
    }

    PRBridgeObservationState *observation = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        handler((PRTaskStatus *)value);
    }];
    __weak PRPrismBridge *weakBridge = self;
    __weak PRBridgeObservationState *weakObservation = observation;
    observation.removalHandler = ^{
        [weakBridge removeTaskObservation:weakObservation];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning]) {
        [self.observationLock unlock];
        [observation cancel];
        return nil;
    }
    [self.taskObservationStates addObject:observation];
    [self.observationLock unlock];

    return [[PRBridgeObservationToken alloc] initWithState:observation];
}

- (PRBridgeObservationToken *)loadInstanceSummariesWithCompletion:(PRInstanceSummariesCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeArrayResult *result = (PRBridgeArrayResult *)value;
        [weakRequest cancel];
        completion((NSArray<PRInstanceSummary *> *)result.values, result.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeSnapshotRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.snapshotRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        NSArray<PRInstanceSummary *> *summaries = @[];
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    summaries = summariesFromFacadeSnapshots(bridge->_facade->instanceSnapshots());
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid facade snapshot"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Facade operation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Facade data unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown facade failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeArrayResult alloc] initWithValues:summaries error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)loadInstanceChangesWithCompletion:(PRInstanceChangesCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeArrayResult *result = (PRBridgeArrayResult *)value;
        [weakRequest cancel];
        completion((NSArray<PRInstanceChange *> *)result.values, result.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeChangeRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.changeRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        NSArray<PRInstanceChange *> *changes = @[];
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    changes = changesFromFacadeChanges(bridge->_facade->instanceChanges());
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid facade change"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Facade operation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Facade data unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown facade failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled && !error) {
            for (PRInstanceChange *change in changes) {
                if (state.isCancelled) {
                    break;
                }
                [bridge publishInstanceChange:change];
            }
        }
        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeArrayResult alloc] initWithValues:changes error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)loadInstanceDetailsWithIdentifier:(NSString *)identifier
                                                        completion:(PRInstanceDetailsCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeDetailsResult *detailsResult = (PRBridgeDetailsResult *)value;
        [weakRequest cancel];
        completion(detailsResult.details, detailsResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeDetailsRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.detailsRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRInstanceDetails *details = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    const std::string instanceIdentifier = stableIdentifierFromFoundation(identifierCopy);
                    const std::optional<FrontendInstanceDetailsSnapshot> snapshot =
                        bridge->_facade->instanceDetails(instanceIdentifier);
                    if (!snapshot.has_value()) {
                        error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                                   diagnosticText:@"Instance details are not available"
                                               substitutionValues:@{ @"instanceIdentifier": identifierCopy ?: @"" }];
                    } else {
                        details = detailsFromFacadeSnapshot(*snapshot);
                    }
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid instance details identifier"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Instance details operation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Instance details unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown instance details failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeDetailsResult alloc] initWithDetails:details error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)loadTaskStatusWithIdentifier:(NSString *)identifier
                                                  completion:(PRTaskStatusCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeTaskStatusResult *taskResult = (PRBridgeTaskStatusResult *)value;
        [weakRequest cancel];
        completion(taskResult.status, taskResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeTaskRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.taskRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRTaskStatus *status = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    const std::string taskIdentifier = stableIdentifierFromFoundation(identifierCopy);
                    const std::optional<FrontendTaskSnapshot> snapshot = bridge->_facade->taskSnapshot(taskIdentifier);
                    if (!snapshot.has_value()) {
                        error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                                   diagnosticText:@"Task identifier is not available"
                                               substitutionValues:@{ @"taskIdentifier": identifierCopy ?: @"" }];
                    } else {
                        status = taskStatusFromFacadeSnapshot(*snapshot);
                    }
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid task identifier"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Task operation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Task data unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown task failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeTaskStatusResult alloc] initWithStatus:status error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)loadTaskLogWithIdentifier:(NSString *)identifier
                                                 completion:(PRTaskLogCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeTaskLogResult *logResult = (PRBridgeTaskLogResult *)value;
        [weakRequest cancel];
        completion(logResult.snapshot, logResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeTaskLogRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.taskLogRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRTaskLogSnapshot *snapshot = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    const std::string taskIdentifier = stableIdentifierFromFoundation(identifierCopy);
                    const std::optional<FrontendLogSnapshot> logSnapshot = bridge->_facade->taskLogSnapshot(taskIdentifier);
                    if (!logSnapshot.has_value()) {
                        error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                                   diagnosticText:@"Task log is not available"
                                               substitutionValues:@{ @"taskIdentifier": identifierCopy ?: @"" }];
                    } else {
                        snapshot = logSnapshotFromFacadeSnapshot(*logSnapshot);
                    }
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid task log identifier"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Task log operation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Task log data unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown task log failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeTaskLogResult alloc] initWithSnapshot:snapshot error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)performTaskCancellationWithIdentifier:(NSString *)identifier
                                                            completion:(PRTaskCancellationCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeTaskCancellationResult *taskResult = (PRBridgeTaskCancellationResult *)value;
        [weakRequest cancel];
        completion(taskResult.result, taskResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeTaskCancellationRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.taskCancellationRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRTaskCancellationResult *result = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    const std::string taskIdentifier = stableIdentifierFromFoundation(identifierCopy);
                    const FrontendTaskCancellationResult cancellationResult = bridge->_facade->cancelTask(taskIdentifier);
                    NSString *foundationIdentifier = [NSString stringWithUTF8String:taskIdentifier.c_str()];
                    result = [[PRTaskCancellationResult alloc]
                        initWithIdentifier:foundationIdentifier
                                    outcome:cancellationOutcomeFromFacadeResult(cancellationResult)];
                    if (!result) {
                        throw std::invalid_argument("Facade returned an invalid task cancellation result");
                    }
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid task identifier"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Task cancellation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Task cancellation unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown task cancellation failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeTaskCancellationResult alloc] initWithResult:result error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)cancelTaskWithIdentifier:(NSString *)identifier
                                               completion:(PRTaskCancellationCompletionHandler)completion
{
    return [self performTaskCancellationWithIdentifier:identifier completion:completion];
}

- (PRBridgeObservationToken *)performInstanceCommand:(PRInstanceCommandKind)kind
                                           identifier:(NSString *)identifier
                                          completion:(PRInstanceCommandCompletionHandler)completion
{
    if (!completion || !isKnownInstanceCommandKind(kind) || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeCommandResult *commandResult = (PRBridgeCommandResult *)value;
        [weakRequest cancel];
        completion(commandResult.result, commandResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeCommandRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.commandRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRInstanceCommandResult *result = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    const std::string instanceIdentifier = stableIdentifierFromFoundation(identifierCopy);
                    const FrontendInstanceCommandResult commandResult = kind == PRInstanceCommandKindLaunch
                        ? bridge->_facade->launchInstance(instanceIdentifier)
                        : bridge->_facade->stopInstance(instanceIdentifier);
                    NSString *foundationIdentifier = [NSString stringWithUTF8String:instanceIdentifier.c_str()];
                    PRInstanceCommandOutcome outcome = commandOutcomeFromFacadeResult(commandResult);
                    result = [[PRInstanceCommandResult alloc] initWithKind:kind
                                                                   identifier:foundationIdentifier
                                                                      outcome:outcome];
                    if (!result) {
                        throw std::invalid_argument("Facade returned an invalid instance command result");
                    }
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid instance command"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Instance command cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Instance command unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown instance command failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeCommandResult alloc] initWithResult:result error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)launchInstanceWithIdentifier:(NSString *)identifier
                                                  completion:(PRInstanceCommandCompletionHandler)completion
{
    return [self performInstanceCommand:PRInstanceCommandKindLaunch identifier:identifier completion:completion];
}

- (PRBridgeObservationToken *)stopInstanceWithIdentifier:(NSString *)identifier
                                                completion:(PRInstanceCommandCompletionHandler)completion
{
    return [self performInstanceCommand:PRInstanceCommandKindStop identifier:identifier completion:completion];
}

- (PRBridgeObservationToken *)updateInstanceNotesWithIdentifier:(NSString *)identifier
                                                           notes:(NSString *)notes
                                                       completion:(PRInstanceNotesUpdateCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    NSString *notesCopy = [notes copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeNotesUpdateResult *notesResult = (PRBridgeNotesUpdateResult *)value;
        [weakRequest cancel];
        completion(notesResult.result, notesResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeNotesUpdateRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.notesUpdateRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRInstanceNotesUpdateResult *result = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    const std::string instanceIdentifier = stableIdentifierFromFoundation(identifierCopy);
                    const std::string notesValue = utf8TextFromFoundation(notesCopy);
                    const FrontendInstanceNotesUpdateResult updateResult =
                        bridge->_facade->updateInstanceNotes(instanceIdentifier, notesValue);
                    result = [[PRInstanceNotesUpdateResult alloc]
                        initWithIdentifier:foundationStringFromUTF8(instanceIdentifier)
                                      notes:foundationStringFromUTF8AllowEmpty(updateResult.notes)
                                    outcome:notesUpdateOutcomeFromFacadeResult(updateResult.outcome)];
                    if (!result) {
                        throw std::invalid_argument("Facade returned an invalid instance notes result");
                    }
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid instance notes"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Instance notes update cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Instance notes update unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown instance notes failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeNotesUpdateResult alloc] initWithResult:result error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)loadInstanceSettingsWithIdentifier:(NSString *)identifier
                                                          completion:(PRInstanceSettingsCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeSettingsResult *settingsResult = (PRBridgeSettingsResult *)value;
        [weakRequest cancel];
        completion(settingsResult.settings, settingsResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeSettingsRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.settingsRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRInstanceSettings *settings = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    const std::string instanceIdentifier = stableIdentifierFromFoundation(identifierCopy);
                    const std::optional<FrontendInstanceSettingsSnapshot> snapshot =
                        bridge->_facade->instanceSettings(instanceIdentifier);
                    if (!snapshot.has_value()) {
                        error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                                   diagnosticText:@"Instance settings are not available"
                                               substitutionValues:@{ @"instanceIdentifier": identifierCopy ?: @"" }];
                    } else {
                        settings = settingsFromFacadeSnapshot(*snapshot);
                    }
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid instance settings identifier"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Instance settings operation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Instance settings unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown instance settings failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeSettingsResult alloc] initWithSettings:settings error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)updateInstanceSettingsWithIdentifier:(NSString *)identifier
                                                            settings:(PRInstanceSettings *)settings
                                                          completion:(PRInstanceSettingsUpdateCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    PRInstanceSettings *settingsCopy = settings;
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeSettingsUpdateResult *settingsResult = (PRBridgeSettingsUpdateResult *)value;
        [weakRequest cancel];
        completion(settingsResult.result, settingsResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeSettingsUpdateRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.settingsUpdateRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRInstanceSettingsUpdateResult *result = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    const std::string instanceIdentifier = stableIdentifierFromFoundation(identifierCopy);
                    const FrontendInstanceSettingsSnapshot requestedSettings = settingsFromFoundationObject(settingsCopy);
                    const FrontendInstanceSettingsUpdateResult updateResult =
                        bridge->_facade->updateInstanceSettings(instanceIdentifier, requestedSettings);
                    PRInstanceSettings *confirmedSettings = nil;
                    if (updateResult.settings.has_value()) {
                        confirmedSettings = settingsFromFacadeSnapshot(*updateResult.settings);
                    }
                    result = [[PRInstanceSettingsUpdateResult alloc]
                        initWithIdentifier:foundationStringFromUTF8(instanceIdentifier)
                                  settings:confirmedSettings
                                  outcome:settingsUpdateOutcomeFromFacadeResult(updateResult.outcome)];
                    if (!result) {
                        throw std::invalid_argument("Facade returned an invalid instance settings update result");
                    }
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid instance settings"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Instance settings update cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Instance settings update unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown instance settings update failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeSettingsUpdateResult alloc] initWithResult:result error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (void)removeInstanceObservation:(PRBridgeObservationState *)observation
{
    [self.observationLock lock];
    NSUInteger index = [self.instanceObservationStates indexOfObjectIdenticalTo:observation];
    if (index != NSNotFound) {
        [self.instanceObservationStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeInstanceChangeObservation:(PRBridgeObservationState *)observation
{
    [self.observationLock lock];
    NSUInteger index = [self.instanceChangeObservationStates indexOfObjectIdenticalTo:observation];
    if (index != NSNotFound) {
        [self.instanceChangeObservationStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeTaskObservation:(PRBridgeObservationState *)observation
{
    [self.observationLock lock];
    NSUInteger index = [self.taskObservationStates indexOfObjectIdenticalTo:observation];
    if (index != NSNotFound) {
        [self.taskObservationStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeSnapshotRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.snapshotRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.snapshotRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeChangeRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.changeRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.changeRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeDetailsRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.detailsRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.detailsRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeTaskRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.taskRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.taskRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeTaskLogRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.taskLogRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.taskLogRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeTaskCancellationRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.taskCancellationRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.taskCancellationRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeCommandRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.commandRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.commandRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeNotesUpdateRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.notesUpdateRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.notesUpdateRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeSettingsRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.settingsRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.settingsRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeSettingsUpdateRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.settingsUpdateRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.settingsUpdateRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)cancelAllObservations
{
    [self.observationLock lock];
    NSMutableArray<PRBridgeObservationState *> *observations = [NSMutableArray array];
    [observations addObjectsFromArray:self.instanceObservationStates];
    [observations addObjectsFromArray:self.instanceChangeObservationStates];
    [observations addObjectsFromArray:self.taskObservationStates];
    [observations addObjectsFromArray:self.snapshotRequestStates];
    [observations addObjectsFromArray:self.changeRequestStates];
    [observations addObjectsFromArray:self.detailsRequestStates];
    [observations addObjectsFromArray:self.taskRequestStates];
    [observations addObjectsFromArray:self.taskLogRequestStates];
    [observations addObjectsFromArray:self.taskCancellationRequestStates];
    [observations addObjectsFromArray:self.commandRequestStates];
    [observations addObjectsFromArray:self.notesUpdateRequestStates];
    [observations addObjectsFromArray:self.settingsRequestStates];
    [observations addObjectsFromArray:self.settingsUpdateRequestStates];
    [self.instanceObservationStates removeAllObjects];
    [self.instanceChangeObservationStates removeAllObjects];
    [self.taskObservationStates removeAllObjects];
    [self.snapshotRequestStates removeAllObjects];
    [self.changeRequestStates removeAllObjects];
    [self.detailsRequestStates removeAllObjects];
    [self.taskRequestStates removeAllObjects];
    [self.taskLogRequestStates removeAllObjects];
    [self.taskCancellationRequestStates removeAllObjects];
    [self.commandRequestStates removeAllObjects];
    [self.notesUpdateRequestStates removeAllObjects];
    [self.settingsRequestStates removeAllObjects];
    [self.settingsUpdateRequestStates removeAllObjects];
    [self.observationLock unlock];

    for (PRBridgeObservationState *observation in observations) {
        [observation cancel];
    }
}

- (void)publishInstanceSummary:(PRInstanceSummary *)summary
{
    if (!summary) {
        return;
    }

    [self.observationLock lock];
    NSArray<PRBridgeObservationState *> *observations = [self.instanceObservationStates copy];
    [self.observationLock unlock];
    for (PRBridgeObservationState *observation in observations) {
        [observation deliverOnMainActor:summary];
    }
}

- (void)publishInstanceChange:(PRInstanceChange *)change
{
    if (!change) {
        return;
    }

    [self.observationLock lock];
    NSArray<PRBridgeObservationState *> *observations = [self.instanceChangeObservationStates copy];
    [self.observationLock unlock];
    for (PRBridgeObservationState *observation in observations) {
        [observation deliverOnMainActor:change];
    }
}

- (void)publishTaskStatus:(PRTaskStatus *)status
{
    if (!status) {
        return;
    }

    [self.observationLock lock];
    NSArray<PRBridgeObservationState *> *observations = [self.taskObservationStates copy];
    [self.observationLock unlock];
    for (PRBridgeObservationState *observation in observations) {
        [observation deliverOnMainActor:status];
    }
}

- (PRBridgeError *)bridgeErrorForFailureKind:(NSInteger)failureKind
                               diagnosticText:(NSString *)diagnosticText
                           substitutionValues:(NSDictionary<NSString *, NSString *> *)substitutionValues
{
    return translatedErrorForFailureKind(failureKind, diagnosticText, substitutionValues);
}

- (PRBridgeLifecycleState)lifecycleState
{
    std::lock_guard<std::mutex> lock(_lifecycleLock);
    return _lifecycle ? _lifecycle->state() : PRBridgeLifecycleStateStopped;
}

- (BOOL)shutdown
{
    {
        std::lock_guard<std::mutex> lock(_lifecycleLock);
        if (!_lifecycle || !_lifecycle->beginShutdown()) {
            return NO;
        }
    }

    [self cancelAllObservations];
    invokeHandler(self.cancellationHandler);
    {
        std::lock_guard<std::mutex> lock(_facadeLock);
        if (_facade) {
            _facade->shutdown();
        }
    }
    invokeHandler(self.shutdownHandler);

    self.cancellationHandler = nil;
    self.shutdownHandler = nil;
    {
        std::lock_guard<std::mutex> lock(_lifecycleLock);
        if (_lifecycle) {
            _lifecycle->finishShutdown();
        }
    }
    return YES;
}

- (void)dealloc
{
    [self shutdown];
}

@end

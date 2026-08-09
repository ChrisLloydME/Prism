#import "PrismBridge.h"

#include "FrontendFacade.h"
#include "ProductionInstanceRuntime.h"

#include <chrono>
#include <cmath>
#include <dispatch/dispatch.h>
#include <exception>
#include <limits.h>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <sys/stat.h>
#include <utility>
#include <vector>

namespace {
NSString *const kPrismBundleIdentifier = @"com.lloydME.Prism";
NSString *const kPrismApplicationName = @"Prism";

BOOL hasParentPathComponent(NSURL *url)
{
    for (NSString *component in url.path.pathComponents) {
        if ([component isEqualToString:@".."] || [component isEqualToString:@"."]) {
            return YES;
        }
    }
    return NO;
}

BOOL hasAliasPathComponent(NSURL *url)
{
    NSURL *currentURL = [NSURL fileURLWithPath:@"/" isDirectory:YES];
    for (NSString *component in url.path.pathComponents) {
        if ([component isEqualToString:@"/"]) {
            continue;
        }

        currentURL = [currentURL URLByAppendingPathComponent:component isDirectory:YES];
        NSNumber *isAlias = nil;
        NSNumber *isSymbolicLink = nil;
        BOOL hasAliasValue = [currentURL getResourceValue:&isAlias forKey:NSURLIsAliasFileKey error:nil];
        BOOL hasSymbolicLinkValue = [currentURL getResourceValue:&isSymbolicLink
                                                           forKey:NSURLIsSymbolicLinkKey
                                                            error:nil];
        if (hasAliasValue && isAlias.boolValue && (!hasSymbolicLinkValue || !isSymbolicLink.boolValue)) {
            return YES;
        }
    }
    return NO;
}

BOOL hasSymbolicLinkPathComponent(NSURL *url)
{
    NSURL *currentURL = [NSURL fileURLWithPath:@"/" isDirectory:YES];
    for (NSString *component in url.path.pathComponents) {
        if ([component isEqualToString:@"/"]) {
            continue;
        }

        currentURL = [currentURL URLByAppendingPathComponent:component isDirectory:YES];
        struct stat fileInfo = {};
        if (lstat(currentURL.fileSystemRepresentation, &fileInfo) == 0 && S_ISLNK(fileInfo.st_mode)) {
            return YES;
        }
    }
    return NO;
}

NSURL *canonicalURLResolvingExistingPathComponents(NSURL *candidateURL);

NSURL *canonicalDirectoryURL(NSURL *candidateURL)
{
    return canonicalURLResolvingExistingPathComponents(candidateURL);
}

NSURL *bundleScopedDirectoryURL(NSURL *baseURL)
{
    NSURL *candidateURL = [baseURL URLByAppendingPathComponent:kPrismBundleIdentifier isDirectory:YES];
    return canonicalDirectoryURL(candidateURL);
}

NSURL *canonicalURLResolvingExistingPathComponents(NSURL *candidateURL)
{
    if (!candidateURL.isFileURL || candidateURL.path.length == 0 || !candidateURL.path.isAbsolutePath
        || hasParentPathComponent(candidateURL) || hasAliasPathComponent(candidateURL)) {
        return nil;
    }

    NSURL *standardizedURL = candidateURL.standardizedURL;
    NSString *existingPath = standardizedURL.path;
    NSMutableArray<NSString *> *missingComponents = [NSMutableArray array];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    while (![fileManager fileExistsAtPath:existingPath]) {
        if ([existingPath isEqualToString:@"/"]) {
            return nil;
        }

        NSString *lastComponent = existingPath.lastPathComponent;
        if (lastComponent.length == 0) {
            return nil;
        }
        [missingComponents insertObject:lastComponent atIndex:0];
        existingPath = existingPath.stringByDeletingLastPathComponent;
    }

    char resolvedPath[PATH_MAX] = {};
    if (realpath(existingPath.fileSystemRepresentation, resolvedPath) == nullptr) {
        return nil;
    }

    NSString *probePath = existingPath;
    for (NSString *component in missingComponents) {
        probePath = [probePath stringByAppendingPathComponent:component];
        struct stat fileInfo = {};
        if (lstat(probePath.fileSystemRepresentation, &fileInfo) == 0 && S_ISLNK(fileInfo.st_mode)) {
            return nil;
        }
    }

    NSURL *resolvedExistingURL = [NSURL fileURLWithFileSystemRepresentation:resolvedPath
                                                                  isDirectory:YES
                                                                relativeToURL:nil];
    for (NSString *component in missingComponents) {
        resolvedExistingURL = [resolvedExistingURL URLByAppendingPathComponent:component isDirectory:YES];
    }
    return resolvedExistingURL.standardizedURL;
}

BOOL canonicalURLIsContained(NSURL *rootURL, NSURL *candidateURL)
{
    if (hasSymbolicLinkPathComponent(rootURL) || hasSymbolicLinkPathComponent(candidateURL)) {
        return NO;
    }

    NSURL *canonicalRootURL = canonicalURLResolvingExistingPathComponents(rootURL);
    NSURL *canonicalCandidateURL = canonicalURLResolvingExistingPathComponents(candidateURL);
    if (!canonicalRootURL.isFileURL || !canonicalCandidateURL.isFileURL) {
        return NO;
    }

    NSArray<NSString *> *rootComponents = canonicalRootURL.path.pathComponents;
    NSArray<NSString *> *candidateComponents = canonicalCandidateURL.path.pathComponents;
    if (candidateComponents.count < rootComponents.count) {
        return NO;
    }

    for (NSUInteger index = 0; index < rootComponents.count; index += 1) {
        if (![candidateComponents[index] isEqualToString:rootComponents[index]]) {
            return NO;
        }
    }
    return YES;
}

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

bool isKnownInstanceComponentProblemSeverity(PRInstanceComponentProblemSeverity severity)
{
    switch (severity) {
        case PRInstanceComponentProblemSeverityNone:
        case PRInstanceComponentProblemSeverityWarning:
        case PRInstanceComponentProblemSeverityError:
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

bool isKnownGlobalSettingsUpdateOutcome(PRGlobalSettingsUpdateOutcome outcome)
{
    switch (outcome) {
        case PRGlobalSettingsUpdateOutcomeSucceeded:
        case PRGlobalSettingsUpdateOutcomeRejected:
            return true;
    }
    return false;
}

bool isKnownGlobalSettingsCatFit(NSString *catFit)
{
    return [catFit isEqualToString:@"fit"] || [catFit isEqualToString:@"fill"] || [catFit isEqualToString:@"strech"];
}

bool isKnownJavaInstallationValidity(PRJavaInstallationValidity validity)
{
    switch (validity) {
        case PRJavaInstallationValidityValid:
        case PRJavaInstallationValidityIncompatible:
        case PRJavaInstallationValidityUnavailable:
            return true;
    }
    return false;
}

bool isKnownJavaDiscoveryOutcome(PRJavaDiscoveryOutcome outcome)
{
    switch (outcome) {
        case PRJavaDiscoveryOutcomeSucceeded:
        case PRJavaDiscoveryOutcomeFailed:
        case PRJavaDiscoveryOutcomeCancelled:
        case PRJavaDiscoveryOutcomeRejected:
            return true;
    }
    return false;
}

bool isKnownJavaSelectionOutcome(PRJavaSelectionOutcome outcome)
{
    switch (outcome) {
        case PRJavaSelectionOutcomeSucceeded:
        case PRJavaSelectionOutcomeUnknownInstallation:
        case PRJavaSelectionOutcomeRejected:
            return true;
    }
    return false;
}

bool isKnownAccountType(PRAccountType type)
{
    switch (type) {
        case PRAccountTypeMicrosoft:
        case PRAccountTypeOffline:
            return true;
    }
    return false;
}

bool isKnownAccountState(PRAccountState state)
{
    switch (state) {
        case PRAccountStateUnchecked:
        case PRAccountStateOffline:
        case PRAccountStateWorking:
        case PRAccountStateOnline:
        case PRAccountStateDisabled:
        case PRAccountStateErrored:
        case PRAccountStateExpired:
        case PRAccountStateGone:
            return true;
    }
    return false;
}

bool isKnownAccountSnapshotOutcome(PRAccountSnapshotOutcome outcome)
{
    switch (outcome) {
        case PRAccountSnapshotOutcomeSucceeded:
        case PRAccountSnapshotOutcomeFailed:
        case PRAccountSnapshotOutcomeCancelled:
        case PRAccountSnapshotOutcomeRejected:
            return true;
    }
    return false;
}

bool isKnownAccountSelectionOutcome(PRAccountSelectionOutcome outcome)
{
    switch (outcome) {
        case PRAccountSelectionOutcomeSucceeded:
        case PRAccountSelectionOutcomeUnknownAccount:
        case PRAccountSelectionOutcomeRejected:
            return true;
    }
    return false;
}

bool isKnownAccountAuthenticationAction(PRAccountAuthenticationAction action)
{
    switch (action) {
        case PRAccountAuthenticationActionLogin:
        case PRAccountAuthenticationActionRefresh:
            return true;
    }
    return false;
}

bool isKnownAccountAuthenticationPhase(PRAccountAuthenticationPhase phase)
{
    switch (phase) {
        case PRAccountAuthenticationPhasePreparing:
        case PRAccountAuthenticationPhaseAwaitingUser:
        case PRAccountAuthenticationPhaseAuthenticating:
        case PRAccountAuthenticationPhaseSucceeded:
        case PRAccountAuthenticationPhaseFailed:
        case PRAccountAuthenticationPhaseCancelled:
            return true;
    }
    return false;
}

bool isKnownAccountAuthenticationOutcome(PRAccountAuthenticationOutcome outcome)
{
    switch (outcome) {
        case PRAccountAuthenticationOutcomeInProgress:
        case PRAccountAuthenticationOutcomeSucceeded:
        case PRAccountAuthenticationOutcomeFailed:
        case PRAccountAuthenticationOutcomeCancelled:
        case PRAccountAuthenticationOutcomeRejected:
            return true;
    }
    return false;
}

bool isKnownOfflineLaunchIdentityMode(PROfflineLaunchIdentityMode mode)
{
    switch (mode) {
        case PROfflineLaunchIdentityModeOffline:
        case PROfflineLaunchIdentityModeDemo:
            return true;
    }
    return false;
}

bool isKnownOfflineLaunchIdentityLoadOutcome(PROfflineLaunchIdentityLoadOutcome outcome)
{
    switch (outcome) {
        case PROfflineLaunchIdentityLoadOutcomeSucceeded:
        case PROfflineLaunchIdentityLoadOutcomeFailed:
        case PROfflineLaunchIdentityLoadOutcomeCancelled:
        case PROfflineLaunchIdentityLoadOutcomeRejected:
            return true;
    }
    return false;
}

bool isKnownOfflineLaunchIdentityUpdateOutcome(PROfflineLaunchIdentityUpdateOutcome outcome)
{
    switch (outcome) {
        case PROfflineLaunchIdentityUpdateOutcomeSucceeded:
        case PROfflineLaunchIdentityUpdateOutcomeInvalidName:
        case PROfflineLaunchIdentityUpdateOutcomeFailed:
        case PROfflineLaunchIdentityUpdateOutcomeCancelled:
        case PROfflineLaunchIdentityUpdateOutcomeRejected:
            return true;
    }
    return false;
}

bool isKnownProviderKind(PRProviderKind provider)
{
    switch (provider) {
        case PRProviderKindModrinth:
        case PRProviderKindCurseForge:
        case PRProviderKindFTB:
        case PRProviderKindATLauncher:
        case PRProviderKindTechnic:
        case PRProviderKindLegacyFTB:
            return true;
    }
    return false;
}

bool isKnownProviderSort(PRProviderSort sort)
{
    switch (sort) {
        case PRProviderSortRelevance:
        case PRProviderSortPopularity:
        case PRProviderSortNewest:
        case PRProviderSortUpdated:
        case PRProviderSortName:
        case PRProviderSortDownloads:
        case PRProviderSortFollows:
        case PRProviderSortGameVersion:
        case PRProviderSortPlays:
        case PRProviderSortInstalls:
            return true;
    }
    return false;
}

bool isKnownProviderReleaseType(PRProviderReleaseType releaseType)
{
    switch (releaseType) {
        case PRProviderReleaseTypeUnknown:
        case PRProviderReleaseTypeRelease:
        case PRProviderReleaseTypeBeta:
        case PRProviderReleaseTypeAlpha:
            return true;
    }
    return false;
}

bool isKnownProviderSide(PRProviderSide side)
{
    switch (side) {
        case PRProviderSideAny:
        case PRProviderSideClient:
        case PRProviderSideServer:
        case PRProviderSideUniversal:
            return true;
    }
    return false;
}

bool isKnownProviderBrowseOutcome(PRProviderBrowseOutcome outcome)
{
    switch (outcome) {
        case PRProviderBrowseOutcomeSucceeded:
        case PRProviderBrowseOutcomeFailed:
        case PRProviderBrowseOutcomeCancelled:
        case PRProviderBrowseOutcomeRejected:
            return true;
    }
    return false;
}

bool isKnownProviderVersionOutcome(PRProviderVersionOutcome outcome)
{
    switch (outcome) {
        case PRProviderVersionOutcomeSucceeded:
        case PRProviderVersionOutcomeFailed:
        case PRProviderVersionOutcomeCancelled:
        case PRProviderVersionOutcomeRejected:
            return true;
    }
    return false;
}

bool isKnownProviderInstallKind(PRProviderInstallKind kind)
{
    switch (kind) {
        case PRProviderInstallKindModrinth:
        case PRProviderInstallKindCurseForgeFlame:
        case PRProviderInstallKindFTB:
        case PRProviderInstallKindLegacyFTB:
        case PRProviderInstallKindFTBImport:
        case PRProviderInstallKindATLauncher:
        case PRProviderInstallKindTechnicZip:
        case PRProviderInstallKindTechnicSolder:
        case PRProviderInstallKindCustomArchive:
            return true;
    }
    return false;
}

bool isKnownProviderInstallOutcome(PRProviderInstallOutcome outcome)
{
    switch (outcome) {
        case PRProviderInstallOutcomeSucceeded:
        case PRProviderInstallOutcomeFailed:
        case PRProviderInstallOutcomeCancelled:
        case PRProviderInstallOutcomeRejected:
            return true;
    }
    return false;
}

bool isKnownProviderInstallRollbackOutcome(PRProviderInstallRollbackOutcome outcome)
{
    switch (outcome) {
        case PRProviderInstallRollbackOutcomeNotRequired:
        case PRProviderInstallRollbackOutcomeApplied:
        case PRProviderInstallRollbackOutcomeFailed:
            return true;
    }
    return false;
}

bool isKnownProviderInstallRecoveryKind(PRProviderInstallRecoveryKind kind)
{
    switch (kind) {
        case PRProviderInstallRecoveryKindOptionalFiles:
        case PRProviderInstallRecoveryKindBlockedFiles:
        case PRProviderInstallRecoveryKindProviderError:
        case PRProviderInstallRecoveryKindNetworkError:
        case PRProviderInstallRecoveryKindDiskError:
            return true;
    }
    return false;
}

bool isKnownProviderInstallRecoveryAction(PRProviderInstallRecoveryAction action)
{
    switch (action) {
        case PRProviderInstallRecoveryActionContinue:
        case PRProviderInstallRecoveryActionRetry:
        case PRProviderInstallRecoveryActionCancel:
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

FrontendRuntimeDependencies defaultRuntimeDependencies(const std::filesystem::path& dataRoot)
{
    return productionInstanceRuntimeDependencies(dataRoot);
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

NSURL *directoryURLFromFacadePath(const std::filesystem::path& path)
{
    const std::string representation = path.string();
    if (representation.empty() || !path.is_absolute()) {
        throw std::invalid_argument("Facade returned an invalid global settings directory");
    }
    NSString *pathString = [[NSString alloc] initWithBytes:representation.data()
                                                     length:representation.size()
                                                   encoding:NSUTF8StringEncoding];
    if (!pathString) {
        throw std::invalid_argument("Facade returned a non-UTF-8 global settings directory");
    }
    NSURL *directoryURL = [NSURL fileURLWithPath:pathString isDirectory:YES];
    if (!directoryURL || !directoryURL.path.isAbsolutePath) {
        throw std::invalid_argument("Facade returned an invalid global settings directory URL");
    }
    return directoryURL;
}

std::filesystem::path directoryPathFromFoundation(NSURL *directoryURL)
{
    if (!directoryURL || !directoryURL.isFileURL || directoryURL.path.length == 0
        || !directoryURL.path.isAbsolutePath) {
        throw std::invalid_argument("Global settings require an absolute directory URL");
    }
    const char *fileSystemRepresentation = directoryURL.fileSystemRepresentation;
    if (!fileSystemRepresentation || fileSystemRepresentation[0] == '\0') {
        throw std::invalid_argument("Global settings directory requires a filesystem representation");
    }
    return std::filesystem::path(fileSystemRepresentation);
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

PRInstanceComponentProblemSeverity componentProblemSeverityFromFacadeSeverity(
    FrontendInstanceComponentProblemSeverity severity)
{
    switch (severity) {
        case FrontendInstanceComponentProblemSeverity::None:
            return PRInstanceComponentProblemSeverityNone;
        case FrontendInstanceComponentProblemSeverity::Warning:
            return PRInstanceComponentProblemSeverityWarning;
        case FrontendInstanceComponentProblemSeverity::Error:
            return PRInstanceComponentProblemSeverityError;
    }
    throw std::invalid_argument("Facade returned an unknown component problem severity");
}

NSArray<NSString *> *componentProblemDescriptionsFromFacade(
    const std::vector<std::string>& problemDescriptions)
{
    NSMutableArray<NSString *> *converted = [NSMutableArray arrayWithCapacity:problemDescriptions.size()];
    for (const std::string& description : problemDescriptions) {
        NSString *value = foundationStringFromUTF8AllowEmpty(description);
        if (!value) {
            throw std::invalid_argument("Facade returned invalid component problem text");
        }
        [converted addObject:value];
    }
    return [converted copy];
}

PRInstanceComponent *componentFromFacadeSnapshot(const FrontendInstanceComponentSnapshot& snapshot)
{
    PRInstanceComponent *component = [[PRInstanceComponent alloc]
        initWithIdentifier:foundationStringFromUTF8(snapshot.id)
                       name:foundationStringFromUTF8(snapshot.name)
                    version:foundationStringFromUTF8AllowEmpty(snapshot.version)
                    enabled:snapshot.enabled
             canBeDisabled:snapshot.canBeDisabled
             dependencyOnly:snapshot.dependencyOnly
                  important:snapshot.important
                     custom:snapshot.custom
           problemSeverity:componentProblemSeverityFromFacadeSeverity(snapshot.problemSeverity)
         problemDescriptions:componentProblemDescriptionsFromFacade(snapshot.problemDescriptions)];
    if (!component) {
        throw std::invalid_argument("Facade returned an invalid instance component");
    }
    return component;
}

NSArray<PRInstanceComponent *> *componentsFromFacadeSnapshots(
    const std::vector<FrontendInstanceComponentSnapshot>& snapshots)
{
    NSMutableArray<PRInstanceComponent *> *converted = [NSMutableArray arrayWithCapacity:snapshots.size()];
    for (const FrontendInstanceComponentSnapshot& snapshot : snapshots) {
        [converted addObject:componentFromFacadeSnapshot(snapshot)];
    }
    return [converted copy];
}

PRInstanceResourceKind resourceKindFromFacadeKind(FrontendInstanceResourceKind kind)
{
    switch (kind) {
        case FrontendInstanceResourceKind::Mods:
            return PRInstanceResourceKindMods;
        case FrontendInstanceResourceKind::ResourcePacks:
            return PRInstanceResourceKindResourcePacks;
        case FrontendInstanceResourceKind::ShaderPacks:
            return PRInstanceResourceKindShaderPacks;
        case FrontendInstanceResourceKind::TexturePacks:
            return PRInstanceResourceKindTexturePacks;
        case FrontendInstanceResourceKind::DataPacks:
            return PRInstanceResourceKindDataPacks;
    }
    throw std::invalid_argument("Facade returned an unknown resource kind");
}

FrontendInstanceResourceKind resourceKindFromFoundationKind(PRInstanceResourceKind kind)
{
    switch (kind) {
        case PRInstanceResourceKindMods:
            return FrontendInstanceResourceKind::Mods;
        case PRInstanceResourceKindResourcePacks:
            return FrontendInstanceResourceKind::ResourcePacks;
        case PRInstanceResourceKindShaderPacks:
            return FrontendInstanceResourceKind::ShaderPacks;
        case PRInstanceResourceKindTexturePacks:
            return FrontendInstanceResourceKind::TexturePacks;
        case PRInstanceResourceKindDataPacks:
            return FrontendInstanceResourceKind::DataPacks;
    }
    throw std::invalid_argument("Resource operations require a known resource kind");
}

PRInstanceResourceAction resourceActionFromFacadeAction(FrontendInstanceResourceAction action)
{
    switch (action) {
        case FrontendInstanceResourceAction::Enable:
            return PRInstanceResourceActionEnable;
        case FrontendInstanceResourceAction::Disable:
            return PRInstanceResourceActionDisable;
        case FrontendInstanceResourceAction::Delete:
            return PRInstanceResourceActionDelete;
        case FrontendInstanceResourceAction::Import:
            return PRInstanceResourceActionImport;
        case FrontendInstanceResourceAction::Reveal:
            return PRInstanceResourceActionReveal;
    }
    throw std::invalid_argument("Facade returned an unknown resource action");
}

FrontendInstanceResourceAction resourceActionFromFoundationAction(PRInstanceResourceAction action)
{
    switch (action) {
        case PRInstanceResourceActionEnable:
            return FrontendInstanceResourceAction::Enable;
        case PRInstanceResourceActionDisable:
            return FrontendInstanceResourceAction::Disable;
        case PRInstanceResourceActionDelete:
            return FrontendInstanceResourceAction::Delete;
        case PRInstanceResourceActionImport:
            return FrontendInstanceResourceAction::Import;
        case PRInstanceResourceActionReveal:
            return FrontendInstanceResourceAction::Reveal;
    }
    throw std::invalid_argument("Resource operations require a known action");
}

PRInstanceResourceMutationOutcome resourceMutationOutcomeFromFacadeOutcome(
    FrontendInstanceResourceMutationOutcome outcome)
{
    switch (outcome) {
        case FrontendInstanceResourceMutationOutcome::Succeeded:
            return PRInstanceResourceMutationOutcomeSucceeded;
        case FrontendInstanceResourceMutationOutcome::UnknownInstance:
            return PRInstanceResourceMutationOutcomeUnknownInstance;
        case FrontendInstanceResourceMutationOutcome::UnknownResource:
            return PRInstanceResourceMutationOutcomeUnknownResource;
        case FrontendInstanceResourceMutationOutcome::Rejected:
            return PRInstanceResourceMutationOutcomeRejected;
        case FrontendInstanceResourceMutationOutcome::Failed:
            return PRInstanceResourceMutationOutcomeFailed;
    }
    throw std::invalid_argument("Facade returned an unknown resource mutation outcome");
}

bool isKnownResourceKind(PRInstanceResourceKind kind)
{
    switch (kind) {
        case PRInstanceResourceKindMods:
        case PRInstanceResourceKindResourcePacks:
        case PRInstanceResourceKindShaderPacks:
        case PRInstanceResourceKindTexturePacks:
        case PRInstanceResourceKindDataPacks:
            return true;
    }
    return false;
}

bool isKnownResourceAction(PRInstanceResourceAction action)
{
    switch (action) {
        case PRInstanceResourceActionEnable:
        case PRInstanceResourceActionDisable:
        case PRInstanceResourceActionDelete:
        case PRInstanceResourceActionImport:
        case PRInstanceResourceActionReveal:
            return true;
    }
    return false;
}

bool isKnownResourceMutationOutcome(PRInstanceResourceMutationOutcome outcome)
{
    switch (outcome) {
        case PRInstanceResourceMutationOutcomeSucceeded:
        case PRInstanceResourceMutationOutcomeUnknownInstance:
        case PRInstanceResourceMutationOutcomeUnknownResource:
        case PRInstanceResourceMutationOutcomeRejected:
        case PRInstanceResourceMutationOutcomeFailed:
            return true;
    }
    return false;
}

bool isKnownInstanceDetailKind(PRInstanceDetailKind kind)
{
    switch (kind) {
        case PRInstanceDetailKindWorlds:
        case PRInstanceDetailKindServers:
        case PRInstanceDetailKindScreenshots:
        case PRInstanceDetailKindLogs:
            return true;
    }
    return false;
}

bool isKnownInstanceDetailAction(PRInstanceDetailAction action)
{
    switch (action) {
        case PRInstanceDetailActionAdd:
        case PRInstanceDetailActionUpdate:
        case PRInstanceDetailActionDelete:
        case PRInstanceDetailActionMoveUp:
        case PRInstanceDetailActionMoveDown:
        case PRInstanceDetailActionImport:
        case PRInstanceDetailActionCopy:
        case PRInstanceDetailActionRename:
        case PRInstanceDetailActionReveal:
        case PRInstanceDetailActionResetIcon:
        case PRInstanceDetailActionJoin:
        case PRInstanceDetailActionRefresh:
        case PRInstanceDetailActionOpen:
        case PRInstanceDetailActionCopyImage:
        case PRInstanceDetailActionCopyFiles:
            return true;
    }
    return false;
}

bool isKnownInstanceDetailMutationOutcome(PRInstanceDetailMutationOutcome outcome)
{
    switch (outcome) {
        case PRInstanceDetailMutationOutcomeSucceeded:
        case PRInstanceDetailMutationOutcomeUnknownInstance:
        case PRInstanceDetailMutationOutcomeUnknownItem:
        case PRInstanceDetailMutationOutcomeRejected:
        case PRInstanceDetailMutationOutcomeFailed:
            return true;
    }
    return false;
}

bool isKnownServerResourcePolicy(PRInstanceServerResourcePolicy policy)
{
    switch (policy) {
        case PRInstanceServerResourcePolicyAsk:
        case PRInstanceServerResourcePolicyAlways:
        case PRInstanceServerResourcePolicyNever:
            return true;
    }
    return false;
}

bool isKnownServerStatus(PRInstanceServerStatus status)
{
    switch (status) {
        case PRInstanceServerStatusUnknown:
        case PRInstanceServerStatusOnline:
        case PRInstanceServerStatusOffline:
        case PRInstanceServerStatusFailed:
            return true;
    }
    return false;
}

NSArray<PRInstanceResource *> *resourcesFromFacadeSnapshots(
    const std::vector<FrontendInstanceResourceSnapshot>& snapshots)
{
    NSMutableArray<PRInstanceResource *> *converted = [NSMutableArray arrayWithCapacity:snapshots.size()];
    for (const FrontendInstanceResourceSnapshot& snapshot : snapshots) {
        NSArray<NSString *> *problemDescriptions = componentProblemDescriptionsFromFacade(snapshot.problemDescriptions);
        PRInstanceResource *resource = [[PRInstanceResource alloc]
            initWithIdentifier:foundationStringFromUTF8(snapshot.id)
                           name:foundationStringFromUTF8(snapshot.name)
                        version:foundationStringFromUTF8AllowEmpty(snapshot.version)
                       fileName:foundationStringFromUTF8(snapshot.fileName)
                       provider:foundationStringFromUTF8AllowEmpty(snapshot.provider)
                           kind:resourceKindFromFacadeKind(snapshot.kind)
                        enabled:snapshot.enabled
                 canBeToggled:snapshot.canBeToggled
                 canBeDeleted:snapshot.canBeDeleted
                   isDirectory:snapshot.isDirectory
                   hasMetadata:snapshot.hasMetadata
            problemDescriptions:problemDescriptions];
        if (!resource) {
            throw std::invalid_argument("Facade returned an invalid instance resource");
        }
        [converted addObject:resource];
    }
    return [converted copy];
}

PRInstanceResourceMutationResult *resourceMutationResultFromFacadeResult(
    const FrontendInstanceResourceMutationResult& result)
{
    PRInstanceResourceMutationResult *converted = [[PRInstanceResourceMutationResult alloc]
        initWithInstanceIdentifier:foundationStringFromUTF8(result.instanceIdentifier)
                  resourceIdentifier:foundationStringFromUTF8(result.resourceIdentifier)
                                kind:resourceKindFromFacadeKind(result.kind)
                              action:resourceActionFromFacadeAction(result.action)
                            outcome:resourceMutationOutcomeFromFacadeOutcome(result.outcome)
                     localizationKey:foundationStringFromUTF8(result.localizationKey)
                      diagnosticText:foundationStringFromUTF8(result.diagnosticText)
           partialChangesRolledBack:result.partialChangesRolledBack];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid resource mutation result");
    }
    return converted;
}

PRInstanceDetailKind detailKindFromFacadeKind(FrontendInstanceDetailKind kind)
{
    switch (kind) {
        case FrontendInstanceDetailKind::Worlds:
            return PRInstanceDetailKindWorlds;
        case FrontendInstanceDetailKind::Servers:
            return PRInstanceDetailKindServers;
        case FrontendInstanceDetailKind::Screenshots:
            return PRInstanceDetailKindScreenshots;
        case FrontendInstanceDetailKind::Logs:
            return PRInstanceDetailKindLogs;
    }
    throw std::invalid_argument("Facade returned an unknown instance detail kind");
}

FrontendInstanceDetailKind detailKindFromFoundationKind(PRInstanceDetailKind kind)
{
    switch (kind) {
        case PRInstanceDetailKindWorlds:
            return FrontendInstanceDetailKind::Worlds;
        case PRInstanceDetailKindServers:
            return FrontendInstanceDetailKind::Servers;
        case PRInstanceDetailKindScreenshots:
            return FrontendInstanceDetailKind::Screenshots;
        case PRInstanceDetailKindLogs:
            return FrontendInstanceDetailKind::Logs;
    }
    throw std::invalid_argument("Instance detail operations require a known kind");
}

PRInstanceDetailAction detailActionFromFacadeAction(FrontendInstanceDetailAction action)
{
    switch (action) {
        case FrontendInstanceDetailAction::Add:
            return PRInstanceDetailActionAdd;
        case FrontendInstanceDetailAction::Update:
            return PRInstanceDetailActionUpdate;
        case FrontendInstanceDetailAction::Delete:
            return PRInstanceDetailActionDelete;
        case FrontendInstanceDetailAction::MoveUp:
            return PRInstanceDetailActionMoveUp;
        case FrontendInstanceDetailAction::MoveDown:
            return PRInstanceDetailActionMoveDown;
        case FrontendInstanceDetailAction::Import:
            return PRInstanceDetailActionImport;
        case FrontendInstanceDetailAction::Copy:
            return PRInstanceDetailActionCopy;
        case FrontendInstanceDetailAction::Rename:
            return PRInstanceDetailActionRename;
        case FrontendInstanceDetailAction::Reveal:
            return PRInstanceDetailActionReveal;
        case FrontendInstanceDetailAction::ResetIcon:
            return PRInstanceDetailActionResetIcon;
        case FrontendInstanceDetailAction::Join:
            return PRInstanceDetailActionJoin;
        case FrontendInstanceDetailAction::Refresh:
            return PRInstanceDetailActionRefresh;
        case FrontendInstanceDetailAction::Open:
            return PRInstanceDetailActionOpen;
        case FrontendInstanceDetailAction::CopyImage:
            return PRInstanceDetailActionCopyImage;
        case FrontendInstanceDetailAction::CopyFiles:
            return PRInstanceDetailActionCopyFiles;
    }
    throw std::invalid_argument("Facade returned an unknown instance detail action");
}

FrontendInstanceDetailAction detailActionFromFoundationAction(PRInstanceDetailAction action)
{
    switch (action) {
        case PRInstanceDetailActionAdd:
            return FrontendInstanceDetailAction::Add;
        case PRInstanceDetailActionUpdate:
            return FrontendInstanceDetailAction::Update;
        case PRInstanceDetailActionDelete:
            return FrontendInstanceDetailAction::Delete;
        case PRInstanceDetailActionMoveUp:
            return FrontendInstanceDetailAction::MoveUp;
        case PRInstanceDetailActionMoveDown:
            return FrontendInstanceDetailAction::MoveDown;
        case PRInstanceDetailActionImport:
            return FrontendInstanceDetailAction::Import;
        case PRInstanceDetailActionCopy:
            return FrontendInstanceDetailAction::Copy;
        case PRInstanceDetailActionRename:
            return FrontendInstanceDetailAction::Rename;
        case PRInstanceDetailActionReveal:
            return FrontendInstanceDetailAction::Reveal;
        case PRInstanceDetailActionResetIcon:
            return FrontendInstanceDetailAction::ResetIcon;
        case PRInstanceDetailActionJoin:
            return FrontendInstanceDetailAction::Join;
        case PRInstanceDetailActionRefresh:
            return FrontendInstanceDetailAction::Refresh;
        case PRInstanceDetailActionOpen:
            return FrontendInstanceDetailAction::Open;
        case PRInstanceDetailActionCopyImage:
            return FrontendInstanceDetailAction::CopyImage;
        case PRInstanceDetailActionCopyFiles:
            return FrontendInstanceDetailAction::CopyFiles;
    }
    throw std::invalid_argument("Instance detail operations require a known action");
}

PRInstanceDetailMutationOutcome detailMutationOutcomeFromFacadeOutcome(
    FrontendInstanceDetailMutationOutcome outcome)
{
    switch (outcome) {
        case FrontendInstanceDetailMutationOutcome::Succeeded:
            return PRInstanceDetailMutationOutcomeSucceeded;
        case FrontendInstanceDetailMutationOutcome::UnknownInstance:
            return PRInstanceDetailMutationOutcomeUnknownInstance;
        case FrontendInstanceDetailMutationOutcome::UnknownItem:
            return PRInstanceDetailMutationOutcomeUnknownItem;
        case FrontendInstanceDetailMutationOutcome::Rejected:
            return PRInstanceDetailMutationOutcomeRejected;
        case FrontendInstanceDetailMutationOutcome::Failed:
            return PRInstanceDetailMutationOutcomeFailed;
    }
    throw std::invalid_argument("Facade returned an unknown instance detail mutation outcome");
}

FrontendInstanceDetailMutationOutcome detailMutationOutcomeFromFoundationOutcome(
    PRInstanceDetailMutationOutcome outcome)
{
    switch (outcome) {
        case PRInstanceDetailMutationOutcomeSucceeded:
            return FrontendInstanceDetailMutationOutcome::Succeeded;
        case PRInstanceDetailMutationOutcomeUnknownInstance:
            return FrontendInstanceDetailMutationOutcome::UnknownInstance;
        case PRInstanceDetailMutationOutcomeUnknownItem:
            return FrontendInstanceDetailMutationOutcome::UnknownItem;
        case PRInstanceDetailMutationOutcomeRejected:
            return FrontendInstanceDetailMutationOutcome::Rejected;
        case PRInstanceDetailMutationOutcomeFailed:
            return FrontendInstanceDetailMutationOutcome::Failed;
    }
    throw std::invalid_argument("Instance detail operations require a known mutation outcome");
}

PRInstanceServerResourcePolicy serverResourcePolicyFromFacadePolicy(FrontendServerResourcePolicy policy)
{
    switch (policy) {
        case FrontendServerResourcePolicy::Ask:
            return PRInstanceServerResourcePolicyAsk;
        case FrontendServerResourcePolicy::Always:
            return PRInstanceServerResourcePolicyAlways;
        case FrontendServerResourcePolicy::Never:
            return PRInstanceServerResourcePolicyNever;
    }
    throw std::invalid_argument("Facade returned an unknown server resource policy");
}

FrontendServerResourcePolicy serverResourcePolicyFromFoundationPolicy(PRInstanceServerResourcePolicy policy)
{
    switch (policy) {
        case PRInstanceServerResourcePolicyAsk:
            return FrontendServerResourcePolicy::Ask;
        case PRInstanceServerResourcePolicyAlways:
            return FrontendServerResourcePolicy::Always;
        case PRInstanceServerResourcePolicyNever:
            return FrontendServerResourcePolicy::Never;
    }
    throw std::invalid_argument("Server operations require a known resource policy");
}

PRInstanceServerStatus serverStatusFromFacadeStatus(FrontendServerStatus status)
{
    switch (status) {
        case FrontendServerStatus::Unknown:
            return PRInstanceServerStatusUnknown;
        case FrontendServerStatus::Online:
            return PRInstanceServerStatusOnline;
        case FrontendServerStatus::Offline:
            return PRInstanceServerStatusOffline;
        case FrontendServerStatus::Failed:
            return PRInstanceServerStatusFailed;
    }
    throw std::invalid_argument("Facade returned an unknown server status");
}

NSArray<PRInstanceWorld *> *worldsFromFacadeSnapshots(
    const std::vector<FrontendInstanceWorldSnapshot>& snapshots)
{
    NSMutableArray<PRInstanceWorld *> *converted = [NSMutableArray arrayWithCapacity:snapshots.size()];
    for (const FrontendInstanceWorldSnapshot& snapshot : snapshots) {
        NSNumber *seed = snapshot.hasSeed ? @(snapshot.seed) : nil;
        PRInstanceWorld *world = [[PRInstanceWorld alloc]
            initWithIdentifier:foundationStringFromUTF8(snapshot.id)
                           name:foundationStringFromUTF8(snapshot.name)
                     folderName:foundationStringFromUTF8(snapshot.folderName)
                       gameMode:foundationStringFromUTF8AllowEmpty(snapshot.gameMode)
                       iconKey:foundationStringFromUTF8(snapshot.iconKey)
             warningDescription:foundationStringFromUTF8(snapshot.warningDescription)
          lastPlayedUnixSeconds:static_cast<NSInteger>(snapshot.lastPlayedUnixSeconds)
                      sizeBytes:snapshot.sizeBytes
                           seed:seed
                      isArchive:snapshot.isArchive
                 canBeRenamed:snapshot.canBeRenamed
                  canBeCopied:snapshot.canBeCopied
                 canBeDeleted:snapshot.canBeDeleted
                   canBeJoined:snapshot.canBeJoined
                     hasIcon:snapshot.hasIcon];
        if (!world) {
            throw std::invalid_argument("Facade returned an invalid instance world");
        }
        [converted addObject:world];
    }
    return [converted copy];
}

NSArray<PRInstanceServer *> *serversFromFacadeSnapshots(
    const std::vector<FrontendInstanceServerSnapshot>& snapshots)
{
    NSMutableArray<PRInstanceServer *> *converted = [NSMutableArray arrayWithCapacity:snapshots.size()];
    for (const FrontendInstanceServerSnapshot& snapshot : snapshots) {
        PRInstanceServer *server = [[PRInstanceServer alloc]
            initWithIdentifier:foundationStringFromUTF8(snapshot.id)
                           name:foundationStringFromUTF8(snapshot.name)
                        address:foundationStringFromUTF8(snapshot.address)
                 resourcePolicy:serverResourcePolicyFromFacadePolicy(snapshot.resourcePolicy)
                         status:serverStatusFromFacadeStatus(snapshot.status)
                  onlinePlayers:static_cast<NSInteger>(snapshot.onlinePlayers)
                    canBeEdited:snapshot.canBeEdited
                   canBeDeleted:snapshot.canBeDeleted
                     canBeJoined:snapshot.canBeJoined];
        if (!server) {
            throw std::invalid_argument("Facade returned an invalid instance server");
        }
        [converted addObject:server];
    }
    return [converted copy];
}

NSArray<PRInstanceScreenshot *> *screenshotsFromFacadeSnapshots(
    const std::vector<FrontendInstanceScreenshotSnapshot>& snapshots)
{
    NSMutableArray<PRInstanceScreenshot *> *converted = [NSMutableArray arrayWithCapacity:snapshots.size()];
    for (const FrontendInstanceScreenshotSnapshot& snapshot : snapshots) {
        PRInstanceScreenshot *screenshot = [[PRInstanceScreenshot alloc]
            initWithIdentifier:foundationStringFromUTF8(snapshot.id)
                       fileName:foundationStringFromUTF8(snapshot.fileName)
                   displayName:foundationStringFromUTF8(snapshot.displayName)
          modifiedUnixSeconds:static_cast<NSInteger>(snapshot.modifiedUnixSeconds)
                      sizeBytes:snapshot.sizeBytes
                       readable:snapshot.readable
                       writable:snapshot.writable];
        if (!screenshot) {
            throw std::invalid_argument("Facade returned an invalid instance screenshot");
        }
        [converted addObject:screenshot];
    }
    return [converted copy];
}

NSArray<PRInstanceLogFile *> *logFilesFromFacadeSnapshots(
    const std::vector<FrontendInstanceLogFileSnapshot>& snapshots)
{
    NSMutableArray<PRInstanceLogFile *> *converted = [NSMutableArray arrayWithCapacity:snapshots.size()];
    for (const FrontendInstanceLogFileSnapshot& snapshot : snapshots) {
        PRInstanceLogFile *logFile = [[PRInstanceLogFile alloc]
            initWithIdentifier:foundationStringFromUTF8(snapshot.id)
                       fileName:foundationStringFromUTF8(snapshot.fileName)
                   displayName:foundationStringFromUTF8(snapshot.displayName)
          modifiedUnixSeconds:static_cast<NSInteger>(snapshot.modifiedUnixSeconds)
                      sizeBytes:snapshot.sizeBytes
                     compressed:snapshot.compressed
                        current:snapshot.current
                       readable:snapshot.readable
                 canBeDeleted:snapshot.canBeDeleted];
        if (!logFile) {
            throw std::invalid_argument("Facade returned an invalid instance log file");
        }
        [converted addObject:logFile];
    }
    return [converted copy];
}

PRTaskLogEntry *logEntryFromFacadeEntry(const FrontendLogEntry& entry);

PRInstanceLogSnapshot *instanceLogSnapshotFromFacadeSnapshot(const FrontendInstanceLogSnapshot& snapshot)
{
    NSMutableArray<PRTaskLogEntry *> *entries = [NSMutableArray arrayWithCapacity:snapshot.entries.size()];
    for (const FrontendLogEntry& entry : snapshot.entries) {
        [entries addObject:logEntryFromFacadeEntry(entry)];
    }

    PRInstanceLogSnapshot *converted = [[PRInstanceLogSnapshot alloc]
        initWithInstanceIdentifier:foundationStringFromUTF8(snapshot.instanceIdentifier)
                      logIdentifier:foundationStringFromUTF8(snapshot.logIdentifier)
                            entries:entries
                 droppedEntryCount:snapshot.droppedEntryCount
                      totalByteCount:snapshot.totalByteCount
                          truncated:snapshot.truncated];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid instance log snapshot");
    }
    return converted;
}

PRInstanceDetailMutationResult *detailMutationResultFromFacadeResult(
    const FrontendInstanceDetailMutationResult& result)
{
    PRInstanceDetailMutationResult *converted = [[PRInstanceDetailMutationResult alloc]
        initWithKind:detailKindFromFacadeKind(result.kind)
               action:detailActionFromFacadeAction(result.action)
             outcome:detailMutationOutcomeFromFacadeOutcome(result.outcome)
   instanceIdentifier:foundationStringFromUTF8(result.instanceIdentifier)
        itemIdentifier:foundationStringFromUTF8AllowEmpty(result.itemIdentifier)
       localizationKey:foundationStringFromUTF8(result.localizationKey)
        diagnosticText:foundationStringFromUTF8(result.diagnosticText)
     partialChangesRolledBack:result.partialChangesRolledBack];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid instance detail mutation result");
    }
    return converted;
}

std::filesystem::path resourceSourcePathFromFoundation(NSURL *sourceURL)
{
    if (!sourceURL || !sourceURL.isFileURL || sourceURL.path.length == 0 || !sourceURL.path.isAbsolutePath) {
        throw std::invalid_argument("Resource import requires an absolute local file URL");
    }
    const char *fileSystemRepresentation = sourceURL.fileSystemRepresentation;
    if (!fileSystemRepresentation || fileSystemRepresentation[0] == '\0') {
        throw std::invalid_argument("Resource import requires a filesystem representation");
    }
    return std::filesystem::path(fileSystemRepresentation);
}

std::filesystem::path exportDestinationPathFromFoundation(NSURL *destinationURL)
{
    if (!destinationURL || !destinationURL.isFileURL || destinationURL.path.length == 0
        || !destinationURL.path.isAbsolutePath) {
        throw std::invalid_argument("Instance export requires an absolute destination URL");
    }
    const char *fileSystemRepresentation = destinationURL.fileSystemRepresentation;
    if (!fileSystemRepresentation || fileSystemRepresentation[0] == '\0') {
        throw std::invalid_argument("Instance export requires a filesystem representation");
    }
    return std::filesystem::path(fileSystemRepresentation).lexically_normal();
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

PRGlobalSettings *globalSettingsFromFacadeSnapshot(const FrontendGlobalSettingsSnapshot& snapshot)
{
    PRGlobalSettings *settings = [[PRGlobalSettings alloc]
        initWithInstanceDirectoryURL:directoryURLFromFacadePath(snapshot.instanceDirectory)
                            iconTheme:foundationStringFromUTF8AllowEmpty(snapshot.iconTheme)
                    applicationTheme:foundationStringFromUTF8AllowEmpty(snapshot.applicationTheme)
                      backgroundCat:foundationStringFromUTF8AllowEmpty(snapshot.backgroundCat)
                        catOpacity:snapshot.catOpacity
                            catFit:foundationStringFromUTF8AllowEmpty(snapshot.catFit)
                          language:foundationStringFromUTF8AllowEmpty(snapshot.language)
                  useSystemLocale:snapshot.useSystemLocale
           menuBarInsteadOfToolBar:snapshot.menuBarInsteadOfToolBar
                 statusBarVisible:snapshot.statusBarVisible
                   toolbarsLocked:snapshot.toolbarsLocked
                numberOfConcurrentTasks:snapshot.numberOfConcurrentTasks
            numberOfConcurrentDownloads:snapshot.numberOfConcurrentDownloads
                  numberOfManualRetries:snapshot.numberOfManualRetries
                      requestTimeoutSeconds:snapshot.requestTimeoutSeconds
                               consoleFont:foundationStringFromUTF8AllowEmpty(snapshot.consoleFont)
                           consoleFontSize:snapshot.consoleFontSize
                            consoleMaxLines:snapshot.consoleMaxLines
                         consoleOverflowStop:snapshot.consoleOverflowStop
                                 showConsole:snapshot.showConsole
                              autoCloseConsole:snapshot.autoCloseConsole
                            showConsoleOnError:snapshot.showConsoleOnError
                             logPrePostOutput:snapshot.logPrePostOutput];
    if (!settings) {
        throw std::invalid_argument("Facade returned invalid global settings");
    }
    return settings;
}

FrontendGlobalSettingsSnapshot globalSettingsFromFoundationObject(PRGlobalSettings *settings)
{
    if (!settings) {
        throw std::invalid_argument("Global settings require a value");
    }

    FrontendGlobalSettingsSnapshot converted;
    converted.instanceDirectory = directoryPathFromFoundation(settings.instanceDirectoryURL);
    converted.iconTheme = utf8TextFromFoundation(settings.iconTheme);
    converted.applicationTheme = utf8TextFromFoundation(settings.applicationTheme);
    converted.backgroundCat = utf8TextFromFoundation(settings.backgroundCat);
    converted.catOpacity = static_cast<int>(settings.catOpacity);
    converted.catFit = utf8TextFromFoundation(settings.catFit);
    converted.language = utf8TextFromFoundation(settings.language);
    converted.useSystemLocale = settings.useSystemLocale;
    converted.menuBarInsteadOfToolBar = settings.menuBarInsteadOfToolBar;
    converted.statusBarVisible = settings.statusBarVisible;
    converted.toolbarsLocked = settings.toolbarsLocked;
    converted.numberOfConcurrentTasks = static_cast<int>(settings.numberOfConcurrentTasks);
    converted.numberOfConcurrentDownloads = static_cast<int>(settings.numberOfConcurrentDownloads);
    converted.numberOfManualRetries = static_cast<int>(settings.numberOfManualRetries);
    converted.requestTimeoutSeconds = static_cast<int>(settings.requestTimeoutSeconds);
    converted.consoleFont = utf8TextFromFoundation(settings.consoleFont);
    converted.consoleFontSize = static_cast<int>(settings.consoleFontSize);
    converted.consoleMaxLines = static_cast<int>(settings.consoleMaxLines);
    converted.consoleOverflowStop = settings.consoleOverflowStop;
    converted.showConsole = settings.showConsole;
    converted.autoCloseConsole = settings.autoCloseConsole;
    converted.showConsoleOnError = settings.showConsoleOnError;
    converted.logPrePostOutput = settings.logPrePostOutput;
    return converted;
}

PRGlobalSettingsUpdateOutcome globalSettingsUpdateOutcomeFromFacadeResult(FrontendGlobalSettingsUpdateOutcome outcome)
{
    switch (outcome) {
        case FrontendGlobalSettingsUpdateOutcome::Succeeded:
            return PRGlobalSettingsUpdateOutcomeSucceeded;
        case FrontendGlobalSettingsUpdateOutcome::Rejected:
            return PRGlobalSettingsUpdateOutcomeRejected;
    }
    throw std::invalid_argument("Facade returned an unknown global settings update outcome");
}

PRJavaInstallationValidity javaInstallationValidityFromFacadeResult(FrontendJavaInstallationValidity validity)
{
    switch (validity) {
        case FrontendJavaInstallationValidity::Valid:
            return PRJavaInstallationValidityValid;
        case FrontendJavaInstallationValidity::Incompatible:
            return PRJavaInstallationValidityIncompatible;
        case FrontendJavaInstallationValidity::Unavailable:
            return PRJavaInstallationValidityUnavailable;
    }
    throw std::invalid_argument("Facade returned an unknown Java installation validity");
}

PRJavaDiscoveryOutcome javaDiscoveryOutcomeFromFacadeResult(FrontendJavaDiscoveryOutcome outcome)
{
    switch (outcome) {
        case FrontendJavaDiscoveryOutcome::Succeeded:
            return PRJavaDiscoveryOutcomeSucceeded;
        case FrontendJavaDiscoveryOutcome::Failed:
            return PRJavaDiscoveryOutcomeFailed;
        case FrontendJavaDiscoveryOutcome::Cancelled:
            return PRJavaDiscoveryOutcomeCancelled;
        case FrontendJavaDiscoveryOutcome::Rejected:
            return PRJavaDiscoveryOutcomeRejected;
    }
    throw std::invalid_argument("Facade returned an unknown Java discovery outcome");
}

PRJavaSelectionOutcome javaSelectionOutcomeFromFacadeResult(FrontendJavaSelectionOutcome outcome)
{
    switch (outcome) {
        case FrontendJavaSelectionOutcome::Succeeded:
            return PRJavaSelectionOutcomeSucceeded;
        case FrontendJavaSelectionOutcome::UnknownInstallation:
            return PRJavaSelectionOutcomeUnknownInstallation;
        case FrontendJavaSelectionOutcome::Rejected:
            return PRJavaSelectionOutcomeRejected;
    }
    throw std::invalid_argument("Facade returned an unknown Java selection outcome");
}

PRJavaInstallation *javaInstallationFromFacadeSnapshot(const FrontendJavaInstallationSnapshot& snapshot)
{
    const std::string executablePath = snapshot.executablePath.string();
    PRJavaInstallation *installation = [[PRJavaInstallation alloc]
        initWithIdentifier:foundationStringFromUTF8(snapshot.id)
                    version:foundationStringFromUTF8AllowEmpty(snapshot.version)
                     vendor:foundationStringFromUTF8AllowEmpty(snapshot.vendor)
               architecture:foundationStringFromUTF8AllowEmpty(snapshot.architecture)
            executablePath:foundationStringFromUTF8(executablePath)
                  is64Bit:snapshot.is64Bit
                   managed:snapshot.managed
                  validity:javaInstallationValidityFromFacadeResult(snapshot.validity)
            diagnosticText:foundationStringFromUTF8(snapshot.diagnosticText)];
    if (!installation) {
        throw std::invalid_argument("Facade returned an invalid Java installation");
    }
    return installation;
}

NSArray<PRJavaInstallation *> *javaInstallationsFromFacadeSnapshots(
    const std::vector<FrontendJavaInstallationSnapshot>& snapshots)
{
    NSMutableArray<PRJavaInstallation *> *converted = [NSMutableArray arrayWithCapacity:snapshots.size()];
    for (const FrontendJavaInstallationSnapshot& snapshot : snapshots) {
        [converted addObject:javaInstallationFromFacadeSnapshot(snapshot)];
    }
    return [converted copy];
}

PRJavaDiscoveryResult *javaDiscoveryResultFromFacadeResult(const FrontendJavaDiscoveryResult& result)
{
    PRJavaDiscoveryResult *converted = [[PRJavaDiscoveryResult alloc]
        initWithInstallations:javaInstallationsFromFacadeSnapshots(result.installations)
                       outcome:javaDiscoveryOutcomeFromFacadeResult(result.outcome)
               localizationKey:foundationStringFromUTF8AllowEmpty(result.localizationKey)
                 diagnosticText:foundationStringFromUTF8(result.diagnosticText)
                     retryable:result.retryable
        selectedInstallationIdentifier:foundationStringFromUTF8(result.selectedInstallationIdentifier.value_or(std::string()))];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid Java discovery result");
    }
    return converted;
}

PRJavaSelectionResult *javaSelectionResultFromFacadeResult(const FrontendJavaSelectionResult& result)
{
    PRJavaInstallation *installation = result.installation.has_value()
        ? javaInstallationFromFacadeSnapshot(*result.installation)
        : nil;
    PRJavaSelectionResult *converted = [[PRJavaSelectionResult alloc]
        initWithInstallation:installation
                       outcome:javaSelectionOutcomeFromFacadeResult(result.outcome)
               localizationKey:foundationStringFromUTF8AllowEmpty(result.localizationKey)
                 diagnosticText:foundationStringFromUTF8(result.diagnosticText)];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid Java selection result");
    }
    return converted;
}

PRAccountType accountTypeFromFacadeResult(FrontendAccountType type)
{
    switch (type) {
        case FrontendAccountType::Microsoft:
            return PRAccountTypeMicrosoft;
        case FrontendAccountType::Offline:
            return PRAccountTypeOffline;
    }
    throw std::invalid_argument("Facade returned an unknown account type");
}

PRAccountState accountStateFromFacadeResult(FrontendAccountState state)
{
    switch (state) {
        case FrontendAccountState::Unchecked:
            return PRAccountStateUnchecked;
        case FrontendAccountState::Offline:
            return PRAccountStateOffline;
        case FrontendAccountState::Working:
            return PRAccountStateWorking;
        case FrontendAccountState::Online:
            return PRAccountStateOnline;
        case FrontendAccountState::Disabled:
            return PRAccountStateDisabled;
        case FrontendAccountState::Errored:
            return PRAccountStateErrored;
        case FrontendAccountState::Expired:
            return PRAccountStateExpired;
        case FrontendAccountState::Gone:
            return PRAccountStateGone;
    }
    throw std::invalid_argument("Facade returned an unknown account state");
}

PRAccountSnapshotOutcome accountSnapshotOutcomeFromFacadeResult(FrontendAccountSnapshotOutcome outcome)
{
    switch (outcome) {
        case FrontendAccountSnapshotOutcome::Succeeded:
            return PRAccountSnapshotOutcomeSucceeded;
        case FrontendAccountSnapshotOutcome::Failed:
            return PRAccountSnapshotOutcomeFailed;
        case FrontendAccountSnapshotOutcome::Cancelled:
            return PRAccountSnapshotOutcomeCancelled;
        case FrontendAccountSnapshotOutcome::Rejected:
            return PRAccountSnapshotOutcomeRejected;
    }
    throw std::invalid_argument("Facade returned an unknown account snapshot outcome");
}

PRAccountSelectionOutcome accountSelectionOutcomeFromFacadeResult(FrontendAccountSelectionOutcome outcome)
{
    switch (outcome) {
        case FrontendAccountSelectionOutcome::Succeeded:
            return PRAccountSelectionOutcomeSucceeded;
        case FrontendAccountSelectionOutcome::UnknownAccount:
            return PRAccountSelectionOutcomeUnknownAccount;
        case FrontendAccountSelectionOutcome::Rejected:
            return PRAccountSelectionOutcomeRejected;
    }
    throw std::invalid_argument("Facade returned an unknown account selection outcome");
}

PRAccountSnapshot *accountSnapshotFromFacadeSnapshot(const FrontendAccountSnapshot& snapshot)
{
    PRAccountSnapshot *account = [[PRAccountSnapshot alloc]
        initWithIdentifier:foundationStringFromUTF8(snapshot.id)
               displayName:foundationStringFromUTF8(snapshot.displayName)
                      type:accountTypeFromFacadeResult(snapshot.type)
                     state:accountStateFromFacadeResult(snapshot.state)
             ownsMinecraft:snapshot.ownsMinecraft
                    isBusy:snapshot.isBusy
            canBeSelected:snapshot.canBeSelected
            diagnosticText:foundationStringFromUTF8(snapshot.diagnosticText)];
    if (!account) {
        throw std::invalid_argument("Facade returned an invalid account snapshot");
    }
    return account;
}

NSArray<PRAccountSnapshot *> *accountSnapshotsFromFacadeSnapshots(
    const std::vector<FrontendAccountSnapshot>& snapshots)
{
    NSMutableArray<PRAccountSnapshot *> *converted = [NSMutableArray arrayWithCapacity:snapshots.size()];
    for (const FrontendAccountSnapshot& snapshot : snapshots) {
        [converted addObject:accountSnapshotFromFacadeSnapshot(snapshot)];
    }
    return [converted copy];
}

PRAccountSnapshotResult *accountSnapshotResultFromFacadeResult(const FrontendAccountSnapshotResult& result)
{
    PRAccountSnapshotResult *converted = [[PRAccountSnapshotResult alloc]
        initWithAccounts:accountSnapshotsFromFacadeSnapshots(result.accounts)
               activeAccountIdentifier:result.activeAccountIdentifier.has_value()
                   ? foundationStringFromUTF8(*result.activeAccountIdentifier)
                   : nil
                              outcome:accountSnapshotOutcomeFromFacadeResult(result.outcome)
                      localizationKey:foundationStringFromUTF8AllowEmpty(result.localizationKey)
                        diagnosticText:foundationStringFromUTF8(result.diagnosticText)
                            retryable:result.retryable];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid account snapshot result");
    }
    return converted;
}

PRAccountSelectionResult *accountSelectionResultFromFacadeResult(const FrontendAccountSelectionResult& result)
{
    PRAccountSnapshot *account = result.account.has_value()
        ? accountSnapshotFromFacadeSnapshot(*result.account)
        : nil;
    PRAccountSelectionResult *converted = [[PRAccountSelectionResult alloc]
        initWithAccount:account
                 outcome:accountSelectionOutcomeFromFacadeResult(result.outcome)
          localizationKey:foundationStringFromUTF8AllowEmpty(result.localizationKey)
            diagnosticText:foundationStringFromUTF8(result.diagnosticText)];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid account selection result");
    }
    return converted;
}

PRAccountAuthenticationAction accountAuthenticationActionFromFacadeResult(FrontendAccountAuthenticationAction action)
{
    switch (action) {
        case FrontendAccountAuthenticationAction::Login:
            return PRAccountAuthenticationActionLogin;
        case FrontendAccountAuthenticationAction::Refresh:
            return PRAccountAuthenticationActionRefresh;
    }
    throw std::invalid_argument("Facade returned an unknown account authentication action");
}

PRAccountAuthenticationPhase accountAuthenticationPhaseFromFacadeResult(FrontendAccountAuthenticationPhase phase)
{
    switch (phase) {
        case FrontendAccountAuthenticationPhase::Preparing:
            return PRAccountAuthenticationPhasePreparing;
        case FrontendAccountAuthenticationPhase::AwaitingUser:
            return PRAccountAuthenticationPhaseAwaitingUser;
        case FrontendAccountAuthenticationPhase::Authenticating:
            return PRAccountAuthenticationPhaseAuthenticating;
        case FrontendAccountAuthenticationPhase::Succeeded:
            return PRAccountAuthenticationPhaseSucceeded;
        case FrontendAccountAuthenticationPhase::Failed:
            return PRAccountAuthenticationPhaseFailed;
        case FrontendAccountAuthenticationPhase::Cancelled:
            return PRAccountAuthenticationPhaseCancelled;
    }
    throw std::invalid_argument("Facade returned an unknown account authentication phase");
}

PRAccountAuthenticationOutcome accountAuthenticationOutcomeFromFacadeResult(
    FrontendAccountAuthenticationOutcome outcome)
{
    switch (outcome) {
        case FrontendAccountAuthenticationOutcome::InProgress:
            return PRAccountAuthenticationOutcomeInProgress;
        case FrontendAccountAuthenticationOutcome::Succeeded:
            return PRAccountAuthenticationOutcomeSucceeded;
        case FrontendAccountAuthenticationOutcome::Failed:
            return PRAccountAuthenticationOutcomeFailed;
        case FrontendAccountAuthenticationOutcome::Cancelled:
            return PRAccountAuthenticationOutcomeCancelled;
        case FrontendAccountAuthenticationOutcome::Rejected:
            return PRAccountAuthenticationOutcomeRejected;
    }
    throw std::invalid_argument("Facade returned an unknown account authentication outcome");
}

PRAccountAuthenticationProgress *accountAuthenticationProgressFromFacadeProgress(
    const FrontendAccountAuthenticationProgress& progress)
{
    PRAccountAuthenticationProgress *converted = [[PRAccountAuthenticationProgress alloc]
        initWithAccountIdentifier:foundationStringFromUTF8(progress.accountIdentifier)
                            action:accountAuthenticationActionFromFacadeResult(progress.action)
                             phase:accountAuthenticationPhaseFromFacadeResult(progress.phase)
                           outcome:accountAuthenticationOutcomeFromFacadeResult(progress.outcome)
                     providerLabel:foundationStringFromUTF8(progress.providerLabel)
                   verificationURL:foundationStringFromUTF8(progress.verificationURL)
                   localizationKey:foundationStringFromUTF8AllowEmpty(progress.localizationKey)
                     diagnosticText:foundationStringFromUTF8(progress.diagnosticText)
                  expiresInSeconds:progress.expiresInSeconds
                        canCancel:progress.canCancel
                         retryable:progress.retryable
                requiresUserAction:progress.requiresUserAction];
    if (!converted) {
        throw std::invalid_argument("Facade returned invalid account authentication progress");
    }
    return converted;
}

PRAccountAuthenticationResult *accountAuthenticationResultFromFacadeResult(
    const FrontendAccountAuthenticationResult& result)
{
    PRAccountSnapshot *account = result.account.has_value()
        ? accountSnapshotFromFacadeSnapshot(*result.account)
        : nil;
    PRAccountAuthenticationResult *converted = [[PRAccountAuthenticationResult alloc]
        initWithAccount:account
                 outcome:accountAuthenticationOutcomeFromFacadeResult(result.outcome)
          localizationKey:foundationStringFromUTF8AllowEmpty(result.localizationKey)
            diagnosticText:foundationStringFromUTF8(result.diagnosticText)
                retryable:result.retryable];
    if (!converted) {
        throw std::invalid_argument("Facade returned invalid account authentication result");
    }
    return converted;
}

PROfflineLaunchIdentityMode offlineLaunchIdentityModeFromFacadeResult(FrontendOfflineLaunchIdentityMode mode)
{
    switch (mode) {
        case FrontendOfflineLaunchIdentityMode::Offline:
            return PROfflineLaunchIdentityModeOffline;
        case FrontendOfflineLaunchIdentityMode::Demo:
            return PROfflineLaunchIdentityModeDemo;
    }
    throw std::invalid_argument("Facade returned an unknown offline launch identity mode");
}

PROfflineLaunchIdentityLoadOutcome offlineLaunchIdentityLoadOutcomeFromFacadeResult(
    FrontendOfflineLaunchIdentityLoadOutcome outcome)
{
    switch (outcome) {
        case FrontendOfflineLaunchIdentityLoadOutcome::Succeeded:
            return PROfflineLaunchIdentityLoadOutcomeSucceeded;
        case FrontendOfflineLaunchIdentityLoadOutcome::Failed:
            return PROfflineLaunchIdentityLoadOutcomeFailed;
        case FrontendOfflineLaunchIdentityLoadOutcome::Cancelled:
            return PROfflineLaunchIdentityLoadOutcomeCancelled;
        case FrontendOfflineLaunchIdentityLoadOutcome::Rejected:
            return PROfflineLaunchIdentityLoadOutcomeRejected;
    }
    throw std::invalid_argument("Facade returned an unknown offline launch identity load outcome");
}

PROfflineLaunchIdentityUpdateOutcome offlineLaunchIdentityUpdateOutcomeFromFacadeResult(
    FrontendOfflineLaunchIdentityUpdateOutcome outcome)
{
    switch (outcome) {
        case FrontendOfflineLaunchIdentityUpdateOutcome::Succeeded:
            return PROfflineLaunchIdentityUpdateOutcomeSucceeded;
        case FrontendOfflineLaunchIdentityUpdateOutcome::InvalidName:
            return PROfflineLaunchIdentityUpdateOutcomeInvalidName;
        case FrontendOfflineLaunchIdentityUpdateOutcome::Failed:
            return PROfflineLaunchIdentityUpdateOutcomeFailed;
        case FrontendOfflineLaunchIdentityUpdateOutcome::Cancelled:
            return PROfflineLaunchIdentityUpdateOutcomeCancelled;
        case FrontendOfflineLaunchIdentityUpdateOutcome::Rejected:
            return PROfflineLaunchIdentityUpdateOutcomeRejected;
    }
    throw std::invalid_argument("Facade returned an unknown offline launch identity update outcome");
}

PROfflineLaunchIdentity *offlineLaunchIdentityFromFacadeSnapshot(
    const FrontendOfflineLaunchIdentitySnapshot& snapshot)
{
    PROfflineLaunchIdentity *converted = [[PROfflineLaunchIdentity alloc]
        initWithMode:offlineLaunchIdentityModeFromFacadeResult(snapshot.mode)
   accountIdentifier:snapshot.accountIdentifier.has_value()
       ? foundationStringFromUTF8(*snapshot.accountIdentifier)
       : nil
                 name:foundationStringFromUTF8(snapshot.name)];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid offline launch identity");
    }
    return converted;
}

PROfflineLaunchIdentityLoadResult *offlineLaunchIdentityLoadResultFromFacadeResult(
    const FrontendOfflineLaunchIdentityLoadResult& result)
{
    PROfflineLaunchIdentity *identity = result.identity.has_value()
        ? offlineLaunchIdentityFromFacadeSnapshot(*result.identity)
        : nil;
    PROfflineLaunchIdentityLoadResult *converted = [[PROfflineLaunchIdentityLoadResult alloc]
        initWithIdentity:identity
                 outcome:offlineLaunchIdentityLoadOutcomeFromFacadeResult(result.outcome)
          localizationKey:foundationStringFromUTF8AllowEmpty(result.localizationKey)
            diagnosticText:foundationStringFromUTF8(result.diagnosticText)
                retryable:result.retryable];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid offline launch identity load result");
    }
    return converted;
}

PROfflineLaunchIdentityUpdateResult *offlineLaunchIdentityUpdateResultFromFacadeResult(
    const FrontendOfflineLaunchIdentityUpdateResult& result)
{
    PROfflineLaunchIdentity *identity = result.identity.has_value()
        ? offlineLaunchIdentityFromFacadeSnapshot(*result.identity)
        : nil;
    PROfflineLaunchIdentityUpdateResult *converted = [[PROfflineLaunchIdentityUpdateResult alloc]
        initWithIdentity:identity
                 outcome:offlineLaunchIdentityUpdateOutcomeFromFacadeResult(result.outcome)
          localizationKey:foundationStringFromUTF8AllowEmpty(result.localizationKey)
            diagnosticText:foundationStringFromUTF8(result.diagnosticText)
                retryable:result.retryable];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid offline launch identity update result");
    }
    return converted;
}

PRVanillaCreationOutcome vanillaCreationOutcomeFromFacadeResult(FrontendVanillaCreationOutcome outcome)
{
    switch (outcome) {
        case FrontendVanillaCreationOutcome::Succeeded:
            return PRVanillaCreationOutcomeSucceeded;
        case FrontendVanillaCreationOutcome::Failed:
            return PRVanillaCreationOutcomeFailed;
        case FrontendVanillaCreationOutcome::Cancelled:
            return PRVanillaCreationOutcomeCancelled;
        case FrontendVanillaCreationOutcome::Rejected:
            return PRVanillaCreationOutcomeRejected;
    }
    throw std::invalid_argument("Facade returned an unknown vanilla creation outcome");
}

PRVanillaCreationResult *vanillaCreationResultFromFacadeResult(const FrontendVanillaCreationResult& result)
{
    PRInstanceSummary *instance = result.instance.has_value() ? summaryFromFacadeSnapshot(*result.instance) : nil;
    PRVanillaCreationResult *converted = [[PRVanillaCreationResult alloc]
        initWithInstance:instance
                  outcome:vanillaCreationOutcomeFromFacadeResult(result.outcome)
           localizationKey:foundationStringFromUTF8AllowEmpty(result.localizationKey)
             diagnosticText:foundationStringFromUTF8(result.diagnosticText)
                 retryable:result.retryable];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid vanilla creation result");
    }
    return converted;
}

PRInstanceImportSourceKind instanceImportSourceKindFromFacadeKind(FrontendInstanceImportSourceKind kind)
{
    switch (kind) {
        case FrontendInstanceImportSourceKind::LocalFile:
            return PRInstanceImportSourceKindLocalFile;
        case FrontendInstanceImportSourceKind::RemoteURL:
            return PRInstanceImportSourceKindRemoteURL;
    }
    throw std::invalid_argument("Facade returned an unknown instance import source kind");
}

PRInstanceImportOutcome instanceImportOutcomeFromFacadeResult(FrontendInstanceImportOutcome outcome)
{
    switch (outcome) {
        case FrontendInstanceImportOutcome::Succeeded:
            return PRInstanceImportOutcomeSucceeded;
        case FrontendInstanceImportOutcome::Failed:
            return PRInstanceImportOutcomeFailed;
        case FrontendInstanceImportOutcome::Cancelled:
            return PRInstanceImportOutcomeCancelled;
        case FrontendInstanceImportOutcome::Rejected:
            return PRInstanceImportOutcomeRejected;
    }
    throw std::invalid_argument("Facade returned an unknown instance import outcome");
}

PRInstanceImportResult *instanceImportResultFromFacadeResult(const FrontendInstanceImportResult& result)
{
    PRInstanceSummary *instance = result.instance.has_value() ? summaryFromFacadeSnapshot(*result.instance) : nil;
    PRInstanceImportResult *converted = [[PRInstanceImportResult alloc]
        initWithInstance:instance
                  outcome:instanceImportOutcomeFromFacadeResult(result.outcome)
           localizationKey:foundationStringFromUTF8AllowEmpty(result.localizationKey)
             diagnosticText:foundationStringFromUTF8(result.diagnosticText)
                 retryable:result.retryable
  partialChangesRolledBack:result.partialChangesRolledBack];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid instance import result");
    }
    return converted;
}

PRInstanceCopyOutcome instanceCopyOutcomeFromFacadeResult(FrontendInstanceCopyOutcome outcome)
{
    switch (outcome) {
        case FrontendInstanceCopyOutcome::Succeeded:
            return PRInstanceCopyOutcomeSucceeded;
        case FrontendInstanceCopyOutcome::Failed:
            return PRInstanceCopyOutcomeFailed;
        case FrontendInstanceCopyOutcome::Cancelled:
            return PRInstanceCopyOutcomeCancelled;
        case FrontendInstanceCopyOutcome::Rejected:
            return PRInstanceCopyOutcomeRejected;
    }
    throw std::invalid_argument("Facade returned an unknown instance copy outcome");
}

PRInstanceCopyResult *instanceCopyResultFromFacadeResult(const FrontendInstanceCopyResult& result)
{
    PRInstanceSummary *instance = result.instance.has_value() ? summaryFromFacadeSnapshot(*result.instance) : nil;
    PRInstanceCopyResult *converted = [[PRInstanceCopyResult alloc]
        initWithInstance:instance
                  outcome:instanceCopyOutcomeFromFacadeResult(result.outcome)
           localizationKey:foundationStringFromUTF8AllowEmpty(result.localizationKey)
             diagnosticText:foundationStringFromUTF8(result.diagnosticText)
                 retryable:result.retryable
  partialChangesRolledBack:result.partialChangesRolledBack];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid instance copy result");
    }
    return converted;
}

PRInstanceExportKind instanceExportKindFromFacadeKind(FrontendInstanceExportKind kind)
{
    switch (kind) {
        case FrontendInstanceExportKind::ZipArchive:
            return PRInstanceExportKindZipArchive;
        case FrontendInstanceExportKind::ModList:
            return PRInstanceExportKindModList;
    }
    throw std::invalid_argument("Facade returned an unknown instance export kind");
}

PRModListExportFormat modListExportFormatFromFacadeFormat(FrontendModListExportFormat format)
{
    switch (format) {
        case FrontendModListExportFormat::HTML:
            return PRModListExportFormatHTML;
        case FrontendModListExportFormat::Markdown:
            return PRModListExportFormatMarkdown;
        case FrontendModListExportFormat::PlainText:
            return PRModListExportFormatPlainText;
        case FrontendModListExportFormat::JSON:
            return PRModListExportFormatJSON;
        case FrontendModListExportFormat::CSV:
            return PRModListExportFormatCSV;
        case FrontendModListExportFormat::Custom:
            return PRModListExportFormatCustom;
    }
    throw std::invalid_argument("Facade returned an unknown mod-list export format");
}

PRInstanceExportOutcome instanceExportOutcomeFromFacadeResult(FrontendInstanceExportOutcome outcome)
{
    switch (outcome) {
        case FrontendInstanceExportOutcome::Succeeded:
            return PRInstanceExportOutcomeSucceeded;
        case FrontendInstanceExportOutcome::Failed:
            return PRInstanceExportOutcomeFailed;
        case FrontendInstanceExportOutcome::Cancelled:
            return PRInstanceExportOutcomeCancelled;
        case FrontendInstanceExportOutcome::Rejected:
            return PRInstanceExportOutcomeRejected;
    }
    throw std::invalid_argument("Facade returned an unknown instance export outcome");
}

NSURL *fileURLFromFacadePath(const std::filesystem::path& path)
{
    if (path.empty() || !path.is_absolute()) {
        throw std::invalid_argument("Facade returned an invalid instance export destination");
    }
    const std::string representation = path.string();
    NSString *pathString = [[NSString alloc] initWithBytes:representation.data()
                                                     length:representation.size()
                                                   encoding:NSUTF8StringEncoding];
    NSURL *url = pathString ? [NSURL fileURLWithPath:pathString] : nil;
    if (!url || !url.isFileURL || url.path.length == 0 || !url.path.isAbsolutePath) {
        throw std::invalid_argument("Facade returned an invalid instance export destination URL");
    }
    return url;
}

PRInstanceExportResult *instanceExportResultFromFacadeResult(const FrontendInstanceExportResult& result)
{
    PRInstanceExportResult *converted = [[PRInstanceExportResult alloc]
        initWithKind:instanceExportKindFromFacadeKind(result.kind)
              outcome:instanceExportOutcomeFromFacadeResult(result.outcome)
       destinationURL:fileURLFromFacadePath(result.destinationPath)
     localizationKey:foundationStringFromUTF8AllowEmpty(result.localizationKey)
       diagnosticText:foundationStringFromUTF8(result.diagnosticText)
           retryable:result.retryable
    partialChangesRolledBack:result.partialChangesRolledBack];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid instance export result");
    }
    return converted;
}

FrontendProviderKind providerKindFromFoundation(PRProviderKind provider)
{
    switch (provider) {
        case PRProviderKindModrinth:
            return FrontendProviderKind::Modrinth;
        case PRProviderKindCurseForge:
            return FrontendProviderKind::CurseForge;
        case PRProviderKindFTB:
            return FrontendProviderKind::FTB;
        case PRProviderKindATLauncher:
            return FrontendProviderKind::ATLauncher;
        case PRProviderKindTechnic:
            return FrontendProviderKind::Technic;
        case PRProviderKindLegacyFTB:
            return FrontendProviderKind::LegacyFTB;
    }
    throw std::invalid_argument("Unknown provider kind");
}

PRProviderKind providerKindFromFacadeKind(FrontendProviderKind provider)
{
    switch (provider) {
        case FrontendProviderKind::Modrinth:
            return PRProviderKindModrinth;
        case FrontendProviderKind::CurseForge:
            return PRProviderKindCurseForge;
        case FrontendProviderKind::FTB:
            return PRProviderKindFTB;
        case FrontendProviderKind::ATLauncher:
            return PRProviderKindATLauncher;
        case FrontendProviderKind::Technic:
            return PRProviderKindTechnic;
        case FrontendProviderKind::LegacyFTB:
            return PRProviderKindLegacyFTB;
    }
    throw std::invalid_argument("Facade returned an unknown provider kind");
}

FrontendProviderSort providerSortFromFoundation(PRProviderSort sort)
{
    switch (sort) {
        case PRProviderSortRelevance:
            return FrontendProviderSort::Relevance;
        case PRProviderSortPopularity:
            return FrontendProviderSort::Popularity;
        case PRProviderSortNewest:
            return FrontendProviderSort::Newest;
        case PRProviderSortUpdated:
            return FrontendProviderSort::Updated;
        case PRProviderSortName:
            return FrontendProviderSort::Name;
        case PRProviderSortDownloads:
            return FrontendProviderSort::Downloads;
        case PRProviderSortFollows:
            return FrontendProviderSort::Follows;
        case PRProviderSortGameVersion:
            return FrontendProviderSort::GameVersion;
        case PRProviderSortPlays:
            return FrontendProviderSort::Plays;
        case PRProviderSortInstalls:
            return FrontendProviderSort::Installs;
    }
    throw std::invalid_argument("Unknown provider sort");
}

FrontendProviderReleaseType providerReleaseTypeFromFoundation(PRProviderReleaseType releaseType)
{
    switch (releaseType) {
        case PRProviderReleaseTypeUnknown:
            return FrontendProviderReleaseType::Unknown;
        case PRProviderReleaseTypeRelease:
            return FrontendProviderReleaseType::Release;
        case PRProviderReleaseTypeBeta:
            return FrontendProviderReleaseType::Beta;
        case PRProviderReleaseTypeAlpha:
            return FrontendProviderReleaseType::Alpha;
    }
    throw std::invalid_argument("Unknown provider release type");
}

PRProviderReleaseType providerReleaseTypeFromFacadeType(FrontendProviderReleaseType releaseType)
{
    switch (releaseType) {
        case FrontendProviderReleaseType::Unknown:
            return PRProviderReleaseTypeUnknown;
        case FrontendProviderReleaseType::Release:
            return PRProviderReleaseTypeRelease;
        case FrontendProviderReleaseType::Beta:
            return PRProviderReleaseTypeBeta;
        case FrontendProviderReleaseType::Alpha:
            return PRProviderReleaseTypeAlpha;
    }
    throw std::invalid_argument("Facade returned an unknown provider release type");
}

FrontendProviderSide providerSideFromFoundation(PRProviderSide side)
{
    switch (side) {
        case PRProviderSideAny:
            return FrontendProviderSide::Any;
        case PRProviderSideClient:
            return FrontendProviderSide::Client;
        case PRProviderSideServer:
            return FrontendProviderSide::Server;
        case PRProviderSideUniversal:
            return FrontendProviderSide::Universal;
    }
    throw std::invalid_argument("Unknown provider side");
}

NSArray<NSString *> *foundationStringsFromUTF8(const std::vector<std::string>& values)
{
    NSMutableArray<NSString *> *converted = [NSMutableArray arrayWithCapacity:values.size()];
    for (const auto& value : values) {
        NSString *string = foundationStringFromUTF8(value);
        if (!string || string.length == 0) {
            throw std::invalid_argument("Facade returned an invalid provider string list");
        }
        [converted addObject:string];
    }
    return [converted copy];
}

std::vector<std::string> utf8StringsFromFoundation(NSArray<NSString *> *values, const char* description)
{
    if (![values isKindOfClass:NSArray.class]) {
        throw std::invalid_argument(description);
    }
    std::vector<std::string> converted;
    converted.reserve(values.count);
    for (id value in values) {
        if (![value isKindOfClass:NSString.class]) {
            throw std::invalid_argument(description);
        }
        const std::string string = utf8TextFromFoundation((NSString *)value);
        if (string.empty()) {
            throw std::invalid_argument(description);
        }
        converted.push_back(string);
    }
    return converted;
}

PRProviderPack *providerPackFromFacadeSnapshot(const FrontendProviderPackSnapshot& pack)
{
    PRProviderPack *converted = [[PRProviderPack alloc]
        initWithProvider:providerKindFromFacadeKind(pack.provider)
              identifier:foundationStringFromUTF8(pack.id)
                    name:foundationStringFromUTF8(pack.name)
                     slug:foundationStringFromUTF8(pack.slug)
                  summary:foundationStringFromUTF8(pack.summary)
                   author:foundationStringFromUTF8(pack.author)
               categories:foundationStringsFromUTF8(pack.categories)
      versionsAvailable:pack.versionsAvailable
 supportsVersionSelection:pack.supportsVersionSelection];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid provider pack");
    }
    return converted;
}

PRProviderBrowsePage *providerBrowsePageFromFacadePage(const FrontendProviderBrowsePage& page)
{
    NSMutableArray<PRProviderPack *> *packs = [NSMutableArray arrayWithCapacity:page.packs.size()];
    for (const auto& pack : page.packs) {
        [packs addObject:providerPackFromFacadeSnapshot(pack)];
    }
    NSNumber *nextOffset = page.nextOffset.has_value()
        ? @(static_cast<NSInteger>(page.nextOffset.value()))
        : nil;
    PRProviderBrowsePage *converted = [[PRProviderBrowsePage alloc]
        initWithProvider:providerKindFromFacadeKind(page.provider)
                  offset:static_cast<NSInteger>(page.offset)
                pageSize:static_cast<NSInteger>(page.pageSize)
             nextOffset:nextOffset
                   packs:packs];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid provider browse page");
    }
    return converted;
}

PRProviderBrowseOutcome providerBrowseOutcomeFromFacadeOutcome(FrontendProviderBrowseOutcome outcome)
{
    switch (outcome) {
        case FrontendProviderBrowseOutcome::Succeeded:
            return PRProviderBrowseOutcomeSucceeded;
        case FrontendProviderBrowseOutcome::Failed:
            return PRProviderBrowseOutcomeFailed;
        case FrontendProviderBrowseOutcome::Cancelled:
            return PRProviderBrowseOutcomeCancelled;
        case FrontendProviderBrowseOutcome::Rejected:
            return PRProviderBrowseOutcomeRejected;
    }
    throw std::invalid_argument("Facade returned an unknown provider browse outcome");
}

PRProviderBrowseResult *providerBrowseResultFromFacadeResult(const FrontendProviderBrowseResult& result)
{
    PRProviderBrowseResult *converted = [[PRProviderBrowseResult alloc]
        initWithPage:result.page.has_value() ? providerBrowsePageFromFacadePage(*result.page) : nil
              outcome:providerBrowseOutcomeFromFacadeOutcome(result.outcome)
       localizationKey:foundationStringFromUTF8AllowEmpty(result.localizationKey)
         diagnosticText:foundationStringFromUTF8(result.diagnosticText)
              retryable:result.retryable];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid provider browse result");
    }
    return converted;
}

PRProviderVersion *providerVersionFromFacadeSnapshot(const FrontendProviderVersionSnapshot& version)
{
    PRProviderVersion *converted = [[PRProviderVersion alloc]
        initWithProvider:providerKindFromFacadeKind(version.provider)
              identifier:foundationStringFromUTF8(version.id)
          packIdentifier:foundationStringFromUTF8(version.packIdentifier)
                    name:foundationStringFromUTF8(version.name)
                 version:foundationStringFromUTF8(version.version)
           gameVersions:foundationStringsFromUTF8(version.gameVersions)
               loaders:foundationStringsFromUTF8(version.loaders)
           releaseType:providerReleaseTypeFromFacadeType(version.releaseType)
publishedUnixSeconds:static_cast<NSInteger>(version.publishedUnixSeconds)
            recommended:version.recommended];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid provider version");
    }
    return converted;
}

PRProviderVersionOutcome providerVersionOutcomeFromFacadeOutcome(FrontendProviderVersionOutcome outcome)
{
    switch (outcome) {
        case FrontendProviderVersionOutcome::Succeeded:
            return PRProviderVersionOutcomeSucceeded;
        case FrontendProviderVersionOutcome::Failed:
            return PRProviderVersionOutcomeFailed;
        case FrontendProviderVersionOutcome::Cancelled:
            return PRProviderVersionOutcomeCancelled;
        case FrontendProviderVersionOutcome::Rejected:
            return PRProviderVersionOutcomeRejected;
    }
    throw std::invalid_argument("Facade returned an unknown provider version outcome");
}

PRProviderVersionResult *providerVersionResultFromFacadeResult(const FrontendProviderVersionResult& result)
{
    NSMutableArray<PRProviderVersion *> *versions = [NSMutableArray arrayWithCapacity:result.versions.size()];
    for (const auto& version : result.versions) {
        [versions addObject:providerVersionFromFacadeSnapshot(version)];
    }
    PRProviderVersionResult *converted = [[PRProviderVersionResult alloc]
        initWithProvider:providerKindFromFacadeKind(result.provider)
            packIdentifier:foundationStringFromUTF8(result.packIdentifier)
                 versions:versions
                  outcome:providerVersionOutcomeFromFacadeOutcome(result.outcome)
           localizationKey:foundationStringFromUTF8AllowEmpty(result.localizationKey)
             diagnosticText:foundationStringFromUTF8(result.diagnosticText)
                  retryable:result.retryable];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid provider version result");
    }
    return converted;
}

FrontendProviderInstallKind providerInstallKindFromFoundation(PRProviderInstallKind kind)
{
    switch (kind) {
        case PRProviderInstallKindModrinth:
            return FrontendProviderInstallKind::Modrinth;
        case PRProviderInstallKindCurseForgeFlame:
            return FrontendProviderInstallKind::CurseForgeFlame;
        case PRProviderInstallKindFTB:
            return FrontendProviderInstallKind::FTB;
        case PRProviderInstallKindLegacyFTB:
            return FrontendProviderInstallKind::LegacyFTB;
        case PRProviderInstallKindFTBImport:
            return FrontendProviderInstallKind::FTBImport;
        case PRProviderInstallKindATLauncher:
            return FrontendProviderInstallKind::ATLauncher;
        case PRProviderInstallKindTechnicZip:
            return FrontendProviderInstallKind::TechnicZip;
        case PRProviderInstallKindTechnicSolder:
            return FrontendProviderInstallKind::TechnicSolder;
        case PRProviderInstallKindCustomArchive:
            return FrontendProviderInstallKind::CustomArchive;
    }
    throw std::invalid_argument("Unknown provider installation kind");
}

PRProviderInstallKind providerInstallKindFromFacadeKind(FrontendProviderInstallKind kind)
{
    switch (kind) {
        case FrontendProviderInstallKind::Modrinth:
            return PRProviderInstallKindModrinth;
        case FrontendProviderInstallKind::CurseForgeFlame:
            return PRProviderInstallKindCurseForgeFlame;
        case FrontendProviderInstallKind::FTB:
            return PRProviderInstallKindFTB;
        case FrontendProviderInstallKind::LegacyFTB:
            return PRProviderInstallKindLegacyFTB;
        case FrontendProviderInstallKind::FTBImport:
            return PRProviderInstallKindFTBImport;
        case FrontendProviderInstallKind::ATLauncher:
            return PRProviderInstallKindATLauncher;
        case FrontendProviderInstallKind::TechnicZip:
            return PRProviderInstallKindTechnicZip;
        case FrontendProviderInstallKind::TechnicSolder:
            return PRProviderInstallKindTechnicSolder;
        case FrontendProviderInstallKind::CustomArchive:
            return PRProviderInstallKindCustomArchive;
    }
    throw std::invalid_argument("Facade returned an unknown provider installation kind");
}

FrontendProviderInstallRecoveryKind providerInstallRecoveryKindFromFoundation(PRProviderInstallRecoveryKind kind)
{
    switch (kind) {
        case PRProviderInstallRecoveryKindOptionalFiles:
            return FrontendProviderInstallRecoveryKind::OptionalFiles;
        case PRProviderInstallRecoveryKindBlockedFiles:
            return FrontendProviderInstallRecoveryKind::BlockedFiles;
        case PRProviderInstallRecoveryKindProviderError:
            return FrontendProviderInstallRecoveryKind::ProviderError;
        case PRProviderInstallRecoveryKindNetworkError:
            return FrontendProviderInstallRecoveryKind::NetworkError;
        case PRProviderInstallRecoveryKindDiskError:
            return FrontendProviderInstallRecoveryKind::DiskError;
    }
    throw std::invalid_argument("Unknown provider installation recovery kind");
}

PRProviderInstallRecoveryKind providerInstallRecoveryKindFromFacadeKind(FrontendProviderInstallRecoveryKind kind)
{
    switch (kind) {
        case FrontendProviderInstallRecoveryKind::OptionalFiles:
            return PRProviderInstallRecoveryKindOptionalFiles;
        case FrontendProviderInstallRecoveryKind::BlockedFiles:
            return PRProviderInstallRecoveryKindBlockedFiles;
        case FrontendProviderInstallRecoveryKind::ProviderError:
            return PRProviderInstallRecoveryKindProviderError;
        case FrontendProviderInstallRecoveryKind::NetworkError:
            return PRProviderInstallRecoveryKindNetworkError;
        case FrontendProviderInstallRecoveryKind::DiskError:
            return PRProviderInstallRecoveryKindDiskError;
    }
    throw std::invalid_argument("Facade returned an unknown provider installation recovery kind");
}

FrontendProviderInstallRecoveryAction providerInstallRecoveryActionFromFoundation(PRProviderInstallRecoveryAction action)
{
    switch (action) {
        case PRProviderInstallRecoveryActionContinue:
            return FrontendProviderInstallRecoveryAction::Continue;
        case PRProviderInstallRecoveryActionRetry:
            return FrontendProviderInstallRecoveryAction::Retry;
        case PRProviderInstallRecoveryActionCancel:
            return FrontendProviderInstallRecoveryAction::Cancel;
    }
    throw std::invalid_argument("Unknown provider installation recovery action");
}

PRProviderInstallFileOption *providerInstallFileOptionFromFacadeOption(
    const FrontendProviderInstallFileOption& option)
{
    PRProviderInstallFileOption *converted = [[PRProviderInstallFileOption alloc]
        initWithIdentifier:foundationStringFromUTF8(option.id)
                      name:foundationStringFromUTF8(option.name)
                targetPath:foundationStringFromUTF8(option.targetPath)
                  required:option.required
                   blocked:option.blocked
                  selected:option.selected];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid provider recovery file option");
    }
    return converted;
}

PRProviderInstallRecoveryPrompt *providerInstallRecoveryPromptFromFacadePrompt(
    const FrontendProviderInstallRecoveryPrompt& prompt)
{
    NSMutableArray<PRProviderInstallFileOption *> *files = [NSMutableArray arrayWithCapacity:prompt.files.size()];
    for (const auto& file : prompt.files) {
        [files addObject:providerInstallFileOptionFromFacadeOption(file)];
    }
    PRProviderInstallRecoveryPrompt *converted = [[PRProviderInstallRecoveryPrompt alloc]
        initWithKind:providerInstallRecoveryKindFromFacadeKind(prompt.kind)
                files:files
      localizationKey:foundationStringFromUTF8(prompt.localizationKey)
        diagnosticText:foundationStringFromUTF8(prompt.diagnosticText)
            retryable:prompt.retryable];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid provider recovery prompt");
    }
    return converted;
}

FrontendProviderInstallRecoveryDecision recoveryDecisionFromFoundation(
    PRProviderInstallRecoveryDecision *decision)
{
    if (!decision) {
        throw std::invalid_argument("Missing provider recovery decision");
    }
    FrontendProviderInstallRecoveryDecision converted;
    converted.kind = providerInstallRecoveryKindFromFoundation(decision.kind);
    converted.action = providerInstallRecoveryActionFromFoundation(decision.action);
    converted.selectedFileIdentifiers =
        utf8StringsFromFoundation(decision.selectedFileIdentifiers, "Provider recovery selections require strings");
    converted.resolvedBlockedFileIdentifiers = utf8StringsFromFoundation(
        decision.resolvedBlockedFileIdentifiers, "Blocked-file resolutions require strings");
    return converted;
}

PRProviderInstallOutcome providerInstallOutcomeFromFacadeOutcome(FrontendProviderInstallOutcome outcome)
{
    switch (outcome) {
        case FrontendProviderInstallOutcome::Succeeded:
            return PRProviderInstallOutcomeSucceeded;
        case FrontendProviderInstallOutcome::Failed:
            return PRProviderInstallOutcomeFailed;
        case FrontendProviderInstallOutcome::Cancelled:
            return PRProviderInstallOutcomeCancelled;
        case FrontendProviderInstallOutcome::Rejected:
            return PRProviderInstallOutcomeRejected;
    }
    throw std::invalid_argument("Facade returned an unknown provider installation outcome");
}

PRProviderInstallRollbackOutcome providerInstallRollbackOutcomeFromFacadeOutcome(
    FrontendProviderInstallRollbackOutcome outcome)
{
    switch (outcome) {
        case FrontendProviderInstallRollbackOutcome::NotRequired:
            return PRProviderInstallRollbackOutcomeNotRequired;
        case FrontendProviderInstallRollbackOutcome::Applied:
            return PRProviderInstallRollbackOutcomeApplied;
        case FrontendProviderInstallRollbackOutcome::Failed:
            return PRProviderInstallRollbackOutcomeFailed;
    }
    throw std::invalid_argument("Facade returned an unknown provider installation rollback outcome");
}

PRProviderInstallResult *providerInstallResultFromFacadeResult(const FrontendProviderInstallResult& result)
{
    PRProviderInstallResult *converted = [[PRProviderInstallResult alloc]
        initWithKind:providerInstallKindFromFacadeKind(result.kind)
       packIdentifier:foundationStringFromUTF8(result.packIdentifier)
   versionIdentifier:foundationStringFromUTF8(result.versionIdentifier)
            instance:result.instance.has_value() ? summaryFromFacadeSnapshot(*result.instance) : nil
             outcome:providerInstallOutcomeFromFacadeOutcome(result.outcome)
             rollbackOutcome:providerInstallRollbackOutcomeFromFacadeOutcome(result.rollbackOutcome)
      localizationKey:foundationStringFromUTF8AllowEmpty(result.localizationKey)
        diagnosticText:foundationStringFromUTF8(result.diagnosticText)
             retryable:result.retryable
        recoveryPrompt:result.recoveryPrompt.has_value()
            ? providerInstallRecoveryPromptFromFacadePrompt(*result.recoveryPrompt)
            : nil];
    if (!converted) {
        throw std::invalid_argument("Facade returned an invalid provider installation result");
    }
    return converted;
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

@interface PRBridgeComponentsResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithComponents:(nullable NSArray<PRInstanceComponent *> *)components
                              error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly, nullable) NSArray<PRInstanceComponent *> *components;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeComponentsResult

- (instancetype)initWithComponents:(NSArray<PRInstanceComponent *> *)components error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _components = [components copy];
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeResourcesResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithResources:(nullable NSArray<PRInstanceResource *> *)resources
                             error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly, nullable) NSArray<PRInstanceResource *> *resources;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeResourcesResult

- (instancetype)initWithResources:(NSArray<PRInstanceResource *> *)resources error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _resources = [resources copy];
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeResourceMutationResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithResult:(nullable PRInstanceResourceMutationResult *)result
                           error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRInstanceResourceMutationResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeResourceMutationResult

- (instancetype)initWithResult:(PRInstanceResourceMutationResult *)result error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _result = result;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeInstanceWorldsResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithWorlds:(nullable NSArray<PRInstanceWorld *> *)worlds
                          error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly, nullable) NSArray<PRInstanceWorld *> *worlds;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeInstanceWorldsResult

- (instancetype)initWithWorlds:(NSArray<PRInstanceWorld *> *)worlds error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _worlds = [worlds copy];
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeInstanceServersResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithServers:(nullable NSArray<PRInstanceServer *> *)servers
                           error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly, nullable) NSArray<PRInstanceServer *> *servers;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeInstanceServersResult

- (instancetype)initWithServers:(NSArray<PRInstanceServer *> *)servers error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _servers = [servers copy];
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeInstanceScreenshotsResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithScreenshots:(nullable NSArray<PRInstanceScreenshot *> *)screenshots
                               error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly, nullable) NSArray<PRInstanceScreenshot *> *screenshots;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeInstanceScreenshotsResult

- (instancetype)initWithScreenshots:(NSArray<PRInstanceScreenshot *> *)screenshots error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _screenshots = [screenshots copy];
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeInstanceLogFilesResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithLogFiles:(nullable NSArray<PRInstanceLogFile *> *)logFiles
                            error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly, nullable) NSArray<PRInstanceLogFile *> *logFiles;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeInstanceLogFilesResult

- (instancetype)initWithLogFiles:(NSArray<PRInstanceLogFile *> *)logFiles error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _logFiles = [logFiles copy];
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeInstanceLogResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithSnapshot:(nullable PRInstanceLogSnapshot *)snapshot
                             error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRInstanceLogSnapshot *snapshot;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeInstanceLogResult

- (instancetype)initWithSnapshot:(PRInstanceLogSnapshot *)snapshot error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _snapshot = snapshot;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeInstanceDetailMutationResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithResult:(nullable PRInstanceDetailMutationResult *)result
                           error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRInstanceDetailMutationResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeInstanceDetailMutationResult

- (instancetype)initWithResult:(PRInstanceDetailMutationResult *)result error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _result = result;
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

@interface PRBridgeGlobalSettingsResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithSettings:(nullable PRGlobalSettings *)settings
                            error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRGlobalSettings *settings;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeGlobalSettingsResult

- (instancetype)initWithSettings:(PRGlobalSettings *)settings error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _settings = settings;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeGlobalSettingsUpdateResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithResult:(nullable PRGlobalSettingsUpdateResult *)result
                           error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRGlobalSettingsUpdateResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeGlobalSettingsUpdateResult

- (instancetype)initWithResult:(PRGlobalSettingsUpdateResult *)result error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _result = result;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeJavaDiscoveryResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithResult:(nullable PRJavaDiscoveryResult *)result
                          error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRJavaDiscoveryResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeJavaDiscoveryResult

- (instancetype)initWithResult:(PRJavaDiscoveryResult *)result error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _result = result;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeJavaSelectionResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithResult:(nullable PRJavaSelectionResult *)result
                          error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRJavaSelectionResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeJavaSelectionResult

- (instancetype)initWithResult:(PRJavaSelectionResult *)result error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _result = result;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeAccountSnapshotResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithResult:(nullable PRAccountSnapshotResult *)result
                          error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRAccountSnapshotResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeAccountSnapshotResult

- (instancetype)initWithResult:(PRAccountSnapshotResult *)result error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _result = result;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeAccountSelectionResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithResult:(nullable PRAccountSelectionResult *)result
                          error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRAccountSelectionResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeAccountSelectionResult

- (instancetype)initWithResult:(PRAccountSelectionResult *)result error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _result = result;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeAccountAuthenticationDelivery : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithProgress:(nullable PRAccountAuthenticationProgress *)progress
                            result:(nullable PRAccountAuthenticationResult *)result
                             error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRAccountAuthenticationProgress *progress;
@property(nonatomic, strong, readonly, nullable) PRAccountAuthenticationResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeAccountAuthenticationDelivery

- (instancetype)initWithProgress:(PRAccountAuthenticationProgress *)progress
                            result:(PRAccountAuthenticationResult *)result
                             error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _progress = progress;
        _result = result;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeVanillaCreationDelivery : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithProgress:(nullable PRTaskStatus *)progress
                           result:(nullable PRVanillaCreationResult *)result
                            error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRTaskStatus *progress;
@property(nonatomic, strong, readonly, nullable) PRVanillaCreationResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeVanillaCreationDelivery

- (instancetype)initWithProgress:(PRTaskStatus *)progress
                           result:(PRVanillaCreationResult *)result
                            error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _progress = progress;
        _result = result;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeInstanceCopyDelivery : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithProgress:(nullable PRTaskStatus *)progress
                           result:(nullable PRInstanceCopyResult *)result
                            error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRTaskStatus *progress;
@property(nonatomic, strong, readonly, nullable) PRInstanceCopyResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeInstanceCopyDelivery

- (instancetype)initWithProgress:(PRTaskStatus *)progress
                           result:(PRInstanceCopyResult *)result
                            error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _progress = progress;
        _result = result;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeInstanceExportDelivery : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithProgress:(nullable PRTaskStatus *)progress
                           result:(nullable PRInstanceExportResult *)result
                            error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRTaskStatus *progress;
@property(nonatomic, strong, readonly, nullable) PRInstanceExportResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeInstanceExportDelivery

- (instancetype)initWithProgress:(PRTaskStatus *)progress
                           result:(PRInstanceExportResult *)result
                            error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _progress = progress;
        _result = result;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeProviderBrowseDelivery : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithProgress:(nullable PRTaskStatus *)progress
                           result:(nullable PRProviderBrowseResult *)result
                            error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRTaskStatus *progress;
@property(nonatomic, strong, readonly, nullable) PRProviderBrowseResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeProviderBrowseDelivery

- (instancetype)initWithProgress:(PRTaskStatus *)progress
                           result:(PRProviderBrowseResult *)result
                            error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _progress = progress;
        _result = result;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeProviderVersionDelivery : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithProgress:(nullable PRTaskStatus *)progress
                           result:(nullable PRProviderVersionResult *)result
                            error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRTaskStatus *progress;
@property(nonatomic, strong, readonly, nullable) PRProviderVersionResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeProviderVersionDelivery

- (instancetype)initWithProgress:(PRTaskStatus *)progress
                           result:(PRProviderVersionResult *)result
                            error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _progress = progress;
        _result = result;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeProviderInstallDelivery : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithProgress:(nullable PRTaskStatus *)progress
                           result:(nullable PRProviderInstallResult *)result
                            error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRTaskStatus *progress;
@property(nonatomic, strong, readonly, nullable) PRProviderInstallResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeProviderInstallDelivery

- (instancetype)initWithProgress:(PRTaskStatus *)progress
                           result:(PRProviderInstallResult *)result
                            error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _progress = progress;
        _result = result;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeInstanceImportDelivery : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithProgress:(nullable PRTaskStatus *)progress
                           result:(nullable PRInstanceImportResult *)result
                            error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRTaskStatus *progress;
@property(nonatomic, strong, readonly, nullable) PRInstanceImportResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeInstanceImportDelivery

- (instancetype)initWithProgress:(PRTaskStatus *)progress
                           result:(PRInstanceImportResult *)result
                            error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _progress = progress;
        _result = result;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeOfflineLaunchIdentityLoadDelivery : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithResult:(nullable PROfflineLaunchIdentityLoadResult *)result
                          error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PROfflineLaunchIdentityLoadResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeOfflineLaunchIdentityLoadDelivery

- (instancetype)initWithResult:(PROfflineLaunchIdentityLoadResult *)result error:(PRBridgeError *)error
{
    self = [super init];
    if (self) {
        _result = result;
        _error = error;
    }
    return self;
}

@end

@interface PRBridgeOfflineLaunchIdentityUpdateDelivery : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithResult:(nullable PROfflineLaunchIdentityUpdateResult *)result
                          error:(nullable PRBridgeError *)error NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PROfflineLaunchIdentityUpdateResult *result;
@property(nonatomic, strong, readonly, nullable) PRBridgeError *error;

@end

@implementation PRBridgeOfflineLaunchIdentityUpdateDelivery

- (instancetype)initWithResult:(PROfflineLaunchIdentityUpdateResult *)result error:(PRBridgeError *)error
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
@property(nonatomic, copy, readwrite) NSURL *cacheDirectory;
@property(nonatomic, copy, readwrite) NSURL *logsDirectory;
@property(nonatomic, copy, readwrite) NSURL *savedApplicationStateDirectory;
@property(nonatomic, copy, readwrite) NSString *preferencesSuiteName;
@property(nonatomic, copy, readwrite) NSString *keychainServicePrefix;

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
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *componentsRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *resourcesRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *resourceMutationRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *worldsRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *serversRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *screenshotsRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *logFilesRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *instanceLogRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *instanceDetailMutationRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *taskRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *taskLogRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *taskCancellationRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *commandRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *notesUpdateRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *settingsRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *settingsUpdateRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *javaDiscoveryRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *javaSelectionRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *accountSnapshotRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *accountSelectionRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *accountAuthenticationRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *vanillaCreationRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *instanceImportRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *instanceCopyRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *instanceExportRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *providerBrowseRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *providerVersionRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *providerInstallRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *offlineIdentityLoadRequestStates;
@property(nonatomic, strong) NSMutableArray<PRBridgeObservationState *> *offlineIdentityUpdateRequestStates;
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
- (void)removeComponentsRequest:(PRBridgeObservationState *)request;
- (void)removeResourcesRequest:(PRBridgeObservationState *)request;
- (void)removeResourceMutationRequest:(PRBridgeObservationState *)request;
- (void)removeWorldsRequest:(PRBridgeObservationState *)request;
- (void)removeServersRequest:(PRBridgeObservationState *)request;
- (void)removeScreenshotsRequest:(PRBridgeObservationState *)request;
- (void)removeLogFilesRequest:(PRBridgeObservationState *)request;
- (void)removeInstanceLogRequest:(PRBridgeObservationState *)request;
- (void)removeInstanceDetailMutationRequest:(PRBridgeObservationState *)request;
- (void)removeTaskRequest:(PRBridgeObservationState *)request;
- (void)removeTaskLogRequest:(PRBridgeObservationState *)request;
- (void)removeTaskCancellationRequest:(PRBridgeObservationState *)request;
- (void)removeCommandRequest:(PRBridgeObservationState *)request;
- (void)removeNotesUpdateRequest:(PRBridgeObservationState *)request;
- (void)removeSettingsRequest:(PRBridgeObservationState *)request;
- (void)removeSettingsUpdateRequest:(PRBridgeObservationState *)request;
- (void)removeJavaDiscoveryRequest:(PRBridgeObservationState *)request;
- (void)removeJavaSelectionRequest:(PRBridgeObservationState *)request;
- (void)removeAccountSnapshotRequest:(PRBridgeObservationState *)request;
- (void)removeAccountSelectionRequest:(PRBridgeObservationState *)request;
- (void)removeAccountAuthenticationRequest:(PRBridgeObservationState *)request;
- (void)removeVanillaCreationRequest:(PRBridgeObservationState *)request;
- (void)removeInstanceImportRequest:(PRBridgeObservationState *)request;
- (void)removeInstanceCopyRequest:(PRBridgeObservationState *)request;
- (void)removeInstanceExportRequest:(PRBridgeObservationState *)request;
- (void)removeProviderBrowseRequest:(PRBridgeObservationState *)request;
- (void)removeProviderVersionRequest:(PRBridgeObservationState *)request;
- (void)removeProviderInstallRequest:(PRBridgeObservationState *)request;
- (void)removeOfflineIdentityLoadRequest:(PRBridgeObservationState *)request;
- (void)removeOfflineIdentityUpdateRequest:(PRBridgeObservationState *)request;
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

@interface PRVanillaCreationRequest ()

@property(nonatomic, copy, readwrite) NSString *versionDescriptor;
@property(nonatomic, copy, readwrite) NSString *versionName;
@property(nonatomic, copy, readwrite, nullable) NSString *loaderIdentifier;
@property(nonatomic, copy, readwrite, nullable) NSString *loaderVersionDescriptor;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, copy, readwrite, nullable) NSString *groupID;
@property(nonatomic, copy, readwrite) NSString *iconKey;

@end

@interface PRVanillaCreationResult ()

@property(nonatomic, strong, readwrite, nullable) PRInstanceSummary *instance;
@property(nonatomic, assign, readwrite) PRVanillaCreationOutcome outcome;
@property(nonatomic, copy, readwrite) NSString *localizationKey;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readwrite) BOOL retryable;

@end

@interface PRInstanceImportRequest ()

@property(nonatomic, copy, readwrite) NSURL *sourceURL;
@property(nonatomic, assign, readwrite) PRInstanceImportSourceKind sourceKind;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, copy, readwrite, nullable) NSString *groupID;
@property(nonatomic, copy, readwrite) NSString *iconKey;

@end

@interface PRInstanceImportResult ()

@property(nonatomic, strong, readwrite, nullable) PRInstanceSummary *instance;
@property(nonatomic, assign, readwrite) PRInstanceImportOutcome outcome;
@property(nonatomic, copy, readwrite) NSString *localizationKey;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readwrite) BOOL retryable;
@property(nonatomic, assign, readwrite) BOOL partialChangesRolledBack;

@end

@interface PRInstanceCopyRequest ()

@property(nonatomic, copy, readwrite) NSString *sourceInstanceIdentifier;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, copy, readwrite, nullable) NSString *groupID;
@property(nonatomic, copy, readwrite) NSString *iconKey;
@property(nonatomic, assign, readwrite) BOOL copySaves;
@property(nonatomic, assign, readwrite) BOOL keepPlaytime;
@property(nonatomic, assign, readwrite) BOOL copyGameOptions;
@property(nonatomic, assign, readwrite) BOOL copyResourcePacks;
@property(nonatomic, assign, readwrite) BOOL copyShaderPacks;
@property(nonatomic, assign, readwrite) BOOL copyServers;
@property(nonatomic, assign, readwrite) BOOL copyMods;
@property(nonatomic, assign, readwrite) BOOL copyScreenshots;
@property(nonatomic, assign, readwrite) BOOL useSymbolicLinks;
@property(nonatomic, assign, readwrite) BOOL linkRecursively;
@property(nonatomic, assign, readwrite) BOOL useHardLinks;
@property(nonatomic, assign, readwrite) BOOL dontLinkSaves;
@property(nonatomic, assign, readwrite) BOOL useClone;

@end

@interface PRInstanceCopyResult ()

@property(nonatomic, strong, readwrite, nullable) PRInstanceSummary *instance;
@property(nonatomic, assign, readwrite) PRInstanceCopyOutcome outcome;
@property(nonatomic, copy, readwrite) NSString *localizationKey;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readwrite) BOOL retryable;
@property(nonatomic, assign, readwrite) BOOL partialChangesRolledBack;

@end

@interface PRInstanceExportRequest ()

@property(nonatomic, copy, readwrite) NSString *sourceInstanceIdentifier;
@property(nonatomic, copy, readwrite) NSURL *destinationURL;
@property(nonatomic, assign, readwrite) PRInstanceExportKind kind;
@property(nonatomic, assign, readwrite) PRModListExportFormat modListFormat;
@property(nonatomic, assign, readwrite) BOOL includeAuthors;
@property(nonatomic, assign, readwrite) BOOL includeVersion;
@property(nonatomic, assign, readwrite) BOOL includeURL;
@property(nonatomic, assign, readwrite) BOOL includeFilename;
@property(nonatomic, copy, readwrite) NSString *customTemplate;

@end

@interface PRInstanceExportResult ()

@property(nonatomic, assign, readwrite) PRInstanceExportKind kind;
@property(nonatomic, assign, readwrite) PRInstanceExportOutcome outcome;
@property(nonatomic, copy, readwrite) NSURL *destinationURL;
@property(nonatomic, copy, readwrite) NSString *localizationKey;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readwrite) BOOL retryable;
@property(nonatomic, assign, readwrite) BOOL partialChangesRolledBack;

@end

@interface PRProviderBrowseRequest ()

@property(nonatomic, assign, readwrite) PRProviderKind provider;
@property(nonatomic, copy, readwrite) NSString *query;
@property(nonatomic, assign, readwrite) NSInteger offset;
@property(nonatomic, assign, readwrite) NSInteger pageSize;
@property(nonatomic, assign, readwrite) PRProviderSort sort;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *gameVersions;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *loaders;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *categories;
@property(nonatomic, copy, readwrite) NSArray<NSNumber *> *releaseTypes;
@property(nonatomic, assign, readwrite) PRProviderSide side;
@property(nonatomic, assign, readwrite) BOOL openSource;
@property(nonatomic, assign, readwrite) BOOL hideInstalled;

@end

@interface PRProviderPack ()

@property(nonatomic, assign, readwrite) PRProviderKind provider;
@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, copy, readwrite, nullable) NSString *slug;
@property(nonatomic, copy, readwrite, nullable) NSString *summary;
@property(nonatomic, copy, readwrite, nullable) NSString *author;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *categories;
@property(nonatomic, assign, readwrite) BOOL versionsAvailable;
@property(nonatomic, assign, readwrite) BOOL supportsVersionSelection;

@end

@interface PRProviderBrowsePage ()

@property(nonatomic, assign, readwrite) PRProviderKind provider;
@property(nonatomic, assign, readwrite) NSInteger offset;
@property(nonatomic, assign, readwrite) NSInteger pageSize;
@property(nonatomic, strong, readwrite, nullable) NSNumber *nextOffset;
@property(nonatomic, copy, readwrite) NSArray<PRProviderPack *> *packs;

@end

@interface PRProviderBrowseResult ()

@property(nonatomic, strong, readwrite, nullable) PRProviderBrowsePage *page;
@property(nonatomic, assign, readwrite) PRProviderBrowseOutcome outcome;
@property(nonatomic, copy, readwrite) NSString *localizationKey;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readwrite) BOOL retryable;

@end

@interface PRProviderVersionRequest ()

@property(nonatomic, assign, readwrite) PRProviderKind provider;
@property(nonatomic, copy, readwrite) NSString *packIdentifier;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *gameVersions;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *loaders;

@end

@interface PRProviderVersion ()

@property(nonatomic, assign, readwrite) PRProviderKind provider;
@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite) NSString *packIdentifier;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, copy, readwrite) NSString *version;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *gameVersions;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *loaders;
@property(nonatomic, assign, readwrite) PRProviderReleaseType releaseType;
@property(nonatomic, assign, readwrite) NSInteger publishedUnixSeconds;
@property(nonatomic, assign, readwrite) BOOL recommended;

@end

@interface PRProviderVersionResult ()

@property(nonatomic, assign, readwrite) PRProviderKind provider;
@property(nonatomic, copy, readwrite) NSString *packIdentifier;
@property(nonatomic, copy, readwrite) NSArray<PRProviderVersion *> *versions;
@property(nonatomic, assign, readwrite) PRProviderVersionOutcome outcome;
@property(nonatomic, copy, readwrite) NSString *localizationKey;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readwrite) BOOL retryable;

@end

@interface PRProviderInstallRequest ()

@property(nonatomic, assign, readwrite) PRProviderInstallKind kind;
@property(nonatomic, copy, readwrite) NSString *packIdentifier;
@property(nonatomic, copy, readwrite) NSString *versionIdentifier;
@property(nonatomic, copy, readwrite, nullable) NSURL *sourceURL;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, copy, readwrite, nullable) NSString *groupID;
@property(nonatomic, copy, readwrite) NSString *iconKey;
@property(nonatomic, strong, readwrite, nullable) PRProviderInstallRecoveryDecision *recoveryDecision;

@end

@interface PRProviderInstallFileOption ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, copy, readwrite) NSString *targetPath;
@property(nonatomic, assign, readwrite) BOOL required;
@property(nonatomic, assign, readwrite) BOOL blocked;
@property(nonatomic, assign, readwrite) BOOL selected;

@end

@interface PRProviderInstallRecoveryPrompt ()

@property(nonatomic, assign, readwrite) PRProviderInstallRecoveryKind kind;
@property(nonatomic, copy, readwrite) NSArray<PRProviderInstallFileOption *> *files;
@property(nonatomic, copy, readwrite) NSString *localizationKey;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readwrite) BOOL retryable;

@end

@interface PRProviderInstallRecoveryDecision ()

@property(nonatomic, assign, readwrite) PRProviderInstallRecoveryKind kind;
@property(nonatomic, assign, readwrite) PRProviderInstallRecoveryAction action;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *selectedFileIdentifiers;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *resolvedBlockedFileIdentifiers;

@end

@interface PRProviderInstallResult ()

@property(nonatomic, assign, readwrite) PRProviderInstallKind kind;
@property(nonatomic, copy, readwrite) NSString *packIdentifier;
@property(nonatomic, copy, readwrite) NSString *versionIdentifier;
@property(nonatomic, strong, readwrite, nullable) PRInstanceSummary *instance;
@property(nonatomic, assign, readwrite) PRProviderInstallOutcome outcome;
@property(nonatomic, assign, readwrite) PRProviderInstallRollbackOutcome rollbackOutcome;
@property(nonatomic, copy, readwrite) NSString *localizationKey;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readwrite) BOOL retryable;
@property(nonatomic, strong, readwrite, nullable) PRProviderInstallRecoveryPrompt *recoveryPrompt;

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

@interface PRInstanceComponent ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, copy, readwrite) NSString *version;
@property(nonatomic, assign, readwrite) BOOL enabled;
@property(nonatomic, assign, readwrite) BOOL canBeDisabled;
@property(nonatomic, assign, readwrite) BOOL dependencyOnly;
@property(nonatomic, assign, readwrite) BOOL important;
@property(nonatomic, assign, readwrite) BOOL custom;
@property(nonatomic, assign, readwrite) PRInstanceComponentProblemSeverity problemSeverity;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *problemDescriptions;

@end

@interface PRInstanceResource ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, copy, readwrite) NSString *version;
@property(nonatomic, copy, readwrite) NSString *fileName;
@property(nonatomic, copy, readwrite) NSString *provider;
@property(nonatomic, assign, readwrite) PRInstanceResourceKind kind;
@property(nonatomic, assign, readwrite) BOOL enabled;
@property(nonatomic, assign, readwrite) BOOL canBeToggled;
@property(nonatomic, assign, readwrite) BOOL canBeDeleted;
@property(nonatomic, assign, readwrite) BOOL directory;
@property(nonatomic, assign, readwrite) BOOL hasMetadata;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *problemDescriptions;

@end

@interface PRInstanceResourceMutationResult ()

@property(nonatomic, copy, readwrite) NSString *instanceIdentifier;
@property(nonatomic, copy, readwrite) NSString *resourceIdentifier;
@property(nonatomic, assign, readwrite) PRInstanceResourceKind kind;
@property(nonatomic, assign, readwrite) PRInstanceResourceAction action;
@property(nonatomic, assign, readwrite) PRInstanceResourceMutationOutcome outcome;
@property(nonatomic, copy, readwrite, nullable) NSString *localizationKey;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readwrite) BOOL partialChangesRolledBack;

@end

@interface PRInstanceWorld ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, copy, readwrite) NSString *folderName;
@property(nonatomic, copy, readwrite) NSString *gameMode;
@property(nonatomic, copy, readwrite, nullable) NSString *iconKey;
@property(nonatomic, copy, readwrite, nullable) NSString *warningDescription;
@property(nonatomic, assign, readwrite) NSInteger lastPlayedUnixSeconds;
@property(nonatomic, assign, readwrite) uint64_t sizeBytes;
@property(nonatomic, strong, readwrite, nullable) NSNumber *seed;
@property(nonatomic, assign, readwrite) BOOL archive;
@property(nonatomic, assign, readwrite) BOOL canBeRenamed;
@property(nonatomic, assign, readwrite) BOOL canBeCopied;
@property(nonatomic, assign, readwrite) BOOL canBeDeleted;
@property(nonatomic, assign, readwrite) BOOL canBeJoined;
@property(nonatomic, assign, readwrite) BOOL hasIcon;

@end

@interface PRInstanceServer ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, copy, readwrite) NSString *address;
@property(nonatomic, assign, readwrite) PRInstanceServerResourcePolicy resourcePolicy;
@property(nonatomic, assign, readwrite) PRInstanceServerStatus status;
@property(nonatomic, assign, readwrite) NSInteger onlinePlayers;
@property(nonatomic, assign, readwrite) BOOL canBeEdited;
@property(nonatomic, assign, readwrite) BOOL canBeDeleted;
@property(nonatomic, assign, readwrite) BOOL canBeJoined;

@end

@interface PRInstanceScreenshot ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite) NSString *fileName;
@property(nonatomic, copy, readwrite) NSString *displayName;
@property(nonatomic, assign, readwrite) NSInteger modifiedUnixSeconds;
@property(nonatomic, assign, readwrite) uint64_t sizeBytes;
@property(nonatomic, assign, readwrite) BOOL readable;
@property(nonatomic, assign, readwrite) BOOL writable;

@end

@interface PRInstanceLogFile ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite) NSString *fileName;
@property(nonatomic, copy, readwrite) NSString *displayName;
@property(nonatomic, assign, readwrite) NSInteger modifiedUnixSeconds;
@property(nonatomic, assign, readwrite) uint64_t sizeBytes;
@property(nonatomic, assign, readwrite) BOOL compressed;
@property(nonatomic, assign, readwrite) BOOL current;
@property(nonatomic, assign, readwrite) BOOL readable;
@property(nonatomic, assign, readwrite) BOOL canBeDeleted;

@end

@interface PRInstanceLogSnapshot ()

@property(nonatomic, copy, readwrite) NSString *instanceIdentifier;
@property(nonatomic, copy, readwrite) NSString *logIdentifier;
@property(nonatomic, copy, readwrite) NSArray<PRTaskLogEntry *> *entries;
@property(nonatomic, assign, readwrite) uint64_t droppedEntryCount;
@property(nonatomic, assign, readwrite) uint64_t totalByteCount;
@property(nonatomic, assign, readwrite) BOOL truncated;

@end

@interface PRInstanceDetailMutationRequest ()

@property(nonatomic, assign, readwrite) PRInstanceDetailKind kind;
@property(nonatomic, assign, readwrite) PRInstanceDetailAction action;
@property(nonatomic, copy, readwrite) NSString *itemIdentifier;
@property(nonatomic, copy, readwrite, nullable) NSURL *sourceURL;
@property(nonatomic, copy, readwrite) NSString *targetName;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, copy, readwrite) NSString *address;
@property(nonatomic, assign, readwrite) PRInstanceServerResourcePolicy resourcePolicy;
@property(nonatomic, assign, readwrite) BOOL confirmed;
@property(nonatomic, assign, readwrite) NSInteger position;

@end

@interface PRInstanceDetailMutationResult ()

@property(nonatomic, assign, readwrite) PRInstanceDetailKind kind;
@property(nonatomic, assign, readwrite) PRInstanceDetailAction action;
@property(nonatomic, assign, readwrite) PRInstanceDetailMutationOutcome outcome;
@property(nonatomic, copy, readwrite) NSString *instanceIdentifier;
@property(nonatomic, copy, readwrite) NSString *itemIdentifier;
@property(nonatomic, copy, readwrite, nullable) NSString *localizationKey;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readwrite) BOOL partialChangesRolledBack;

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

@interface PRGlobalSettings ()

@property(nonatomic, copy, readwrite) NSURL *instanceDirectoryURL;
@property(nonatomic, copy, readwrite) NSString *iconTheme;
@property(nonatomic, copy, readwrite) NSString *applicationTheme;
@property(nonatomic, copy, readwrite) NSString *backgroundCat;
@property(nonatomic, assign, readwrite) NSInteger catOpacity;
@property(nonatomic, copy, readwrite) NSString *catFit;
@property(nonatomic, copy, readwrite) NSString *language;
@property(nonatomic, assign, readwrite) BOOL useSystemLocale;
@property(nonatomic, assign, readwrite) BOOL menuBarInsteadOfToolBar;
@property(nonatomic, assign, readwrite) BOOL statusBarVisible;
@property(nonatomic, assign, readwrite) BOOL toolbarsLocked;
@property(nonatomic, assign, readwrite) NSInteger numberOfConcurrentTasks;
@property(nonatomic, assign, readwrite) NSInteger numberOfConcurrentDownloads;
@property(nonatomic, assign, readwrite) NSInteger numberOfManualRetries;
@property(nonatomic, assign, readwrite) NSInteger requestTimeoutSeconds;
@property(nonatomic, copy, readwrite) NSString *consoleFont;
@property(nonatomic, assign, readwrite) NSInteger consoleFontSize;
@property(nonatomic, assign, readwrite) NSInteger consoleMaxLines;
@property(nonatomic, assign, readwrite) BOOL consoleOverflowStop;
@property(nonatomic, assign, readwrite) BOOL showConsole;
@property(nonatomic, assign, readwrite) BOOL autoCloseConsole;
@property(nonatomic, assign, readwrite) BOOL showConsoleOnError;
@property(nonatomic, assign, readwrite) BOOL logPrePostOutput;

@end

@interface PRGlobalSettingsUpdateResult ()

@property(nonatomic, strong, readwrite, nullable) PRGlobalSettings *settings;
@property(nonatomic, assign, readwrite) PRGlobalSettingsUpdateOutcome outcome;

@end

@interface PRJavaInstallation ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite) NSString *version;
@property(nonatomic, copy, readwrite) NSString *vendor;
@property(nonatomic, copy, readwrite) NSString *architecture;
@property(nonatomic, copy, readwrite) NSString *executablePath;
@property(nonatomic, assign, readwrite) BOOL is64Bit;
@property(nonatomic, assign, readwrite) BOOL managed;
@property(nonatomic, assign, readwrite) PRJavaInstallationValidity validity;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;

@end

@interface PRJavaDiscoveryResult ()

@property(nonatomic, copy, readwrite) NSArray<PRJavaInstallation *> *installations;
@property(nonatomic, assign, readwrite) PRJavaDiscoveryOutcome outcome;
@property(nonatomic, copy, readwrite) NSString *localizationKey;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readwrite) BOOL retryable;
@property(nonatomic, copy, readwrite, nullable) NSString *selectedInstallationIdentifier;

@end

@interface PRJavaSelectionResult ()

@property(nonatomic, strong, readwrite, nullable) PRJavaInstallation *installation;
@property(nonatomic, assign, readwrite) PRJavaSelectionOutcome outcome;
@property(nonatomic, copy, readwrite) NSString *localizationKey;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;

@end

@interface PRAccountSnapshot ()

@property(nonatomic, copy, readwrite) NSString *identifier;
@property(nonatomic, copy, readwrite) NSString *displayName;
@property(nonatomic, assign, readwrite) PRAccountType type;
@property(nonatomic, assign, readwrite) PRAccountState state;
@property(nonatomic, assign, readwrite) BOOL ownsMinecraft;
@property(nonatomic, assign, readwrite) BOOL isBusy;
@property(nonatomic, assign, readwrite) BOOL canBeSelected;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;

@end

@interface PRAccountSnapshotResult ()

@property(nonatomic, copy, readwrite) NSArray<PRAccountSnapshot *> *accounts;
@property(nonatomic, copy, readwrite, nullable) NSString *activeAccountIdentifier;
@property(nonatomic, assign, readwrite) PRAccountSnapshotOutcome outcome;
@property(nonatomic, copy, readwrite) NSString *localizationKey;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readwrite) BOOL retryable;

@end

@interface PRAccountSelectionResult ()

@property(nonatomic, strong, readwrite, nullable) PRAccountSnapshot *account;
@property(nonatomic, assign, readwrite) PRAccountSelectionOutcome outcome;
@property(nonatomic, copy, readwrite) NSString *localizationKey;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;

@end

@interface PRAccountAuthenticationProgress ()

@property(nonatomic, copy, readwrite) NSString *accountIdentifier;
@property(nonatomic, assign, readwrite) PRAccountAuthenticationAction action;
@property(nonatomic, assign, readwrite) PRAccountAuthenticationPhase phase;
@property(nonatomic, assign, readwrite) PRAccountAuthenticationOutcome outcome;
@property(nonatomic, copy, readwrite) NSString *providerLabel;
@property(nonatomic, copy, readwrite, nullable) NSString *verificationURL;
@property(nonatomic, copy, readwrite) NSString *localizationKey;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readwrite) NSInteger expiresInSeconds;
@property(nonatomic, assign, readwrite) BOOL canCancel;
@property(nonatomic, assign, readwrite) BOOL retryable;
@property(nonatomic, assign, readwrite) BOOL requiresUserAction;
@property(nonatomic, assign, readwrite, getter=isTerminal) BOOL terminal;

@end

@interface PRAccountAuthenticationResult ()

@property(nonatomic, strong, readwrite, nullable) PRAccountSnapshot *account;
@property(nonatomic, assign, readwrite) PRAccountAuthenticationOutcome outcome;
@property(nonatomic, copy, readwrite) NSString *localizationKey;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readwrite) BOOL retryable;

@end

@interface PROfflineLaunchIdentity ()

@property(nonatomic, assign, readwrite) PROfflineLaunchIdentityMode mode;
@property(nonatomic, copy, readwrite, nullable) NSString *accountIdentifier;
@property(nonatomic, copy, readwrite) NSString *name;

@end

@interface PROfflineLaunchIdentityLoadResult ()

@property(nonatomic, strong, readwrite, nullable) PROfflineLaunchIdentity *identity;
@property(nonatomic, assign, readwrite) PROfflineLaunchIdentityLoadOutcome outcome;
@property(nonatomic, copy, readwrite) NSString *localizationKey;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readwrite) BOOL retryable;

@end

@interface PROfflineLaunchIdentityUpdateResult ()

@property(nonatomic, strong, readwrite, nullable) PROfflineLaunchIdentity *identity;
@property(nonatomic, assign, readwrite) PROfflineLaunchIdentityUpdateOutcome outcome;
@property(nonatomic, copy, readwrite) NSString *localizationKey;
@property(nonatomic, copy, readwrite, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readwrite) BOOL retryable;

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
    if (![bundleIdentifier isEqualToString:kPrismBundleIdentifier]) {
        return nil;
    }

    NSURL *normalizedBaseURL = canonicalDirectoryURL(applicationSupportBaseDirectory);
    if (!normalizedBaseURL || ![normalizedBaseURL.lastPathComponent isEqualToString:@"Application Support"]) {
        return nil;
    }

    NSURL *libraryURL = normalizedBaseURL.URLByDeletingLastPathComponent;
    if (![libraryURL.lastPathComponent isEqualToString:@"Library"]) {
        return nil;
    }

    NSURL *applicationSupportURL = bundleScopedDirectoryURL(normalizedBaseURL);
    NSURL *cacheURL = bundleScopedDirectoryURL([libraryURL URLByAppendingPathComponent:@"Caches" isDirectory:YES]);
    NSURL *logsURL = bundleScopedDirectoryURL([libraryURL URLByAppendingPathComponent:@"Logs" isDirectory:YES]);
    NSURL *savedStateURL = bundleScopedDirectoryURL(
        [libraryURL URLByAppendingPathComponent:@"Saved Application State" isDirectory:YES]
    );
    if (!applicationSupportURL || !cacheURL || !logsURL || !savedStateURL) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.bundleIdentifier = kPrismBundleIdentifier;
        self.applicationSupportDirectory = applicationSupportURL;
        self.cacheDirectory = cacheURL;
        self.logsDirectory = logsURL;
        self.savedApplicationStateDirectory = savedStateURL;
        self.preferencesSuiteName = kPrismBundleIdentifier;
        self.keychainServicePrefix = kPrismBundleIdentifier;
    }
    return self;
}

- (NSString *)applicationName
{
    return kPrismApplicationName;
}

- (BOOL)containsURL:(NSURL *)candidateURL
{
    return canonicalURLIsContained(self.applicationSupportDirectory, candidateURL);
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

@implementation PRVanillaCreationRequest

- (instancetype)initWithVersionDescriptor:(NSString *)versionDescriptor
                               versionName:(NSString *)versionName
                         loaderIdentifier:(NSString *)loaderIdentifier
                    loaderVersionDescriptor:(NSString *)loaderVersionDescriptor
                                       name:(NSString *)name
                                   groupID:(NSString *)groupID
                                   iconKey:(NSString *)iconKey
{
    if (!isNonEmptyString(versionDescriptor) || !isNonEmptyString(versionName) || !isNonEmptyString(name)
        || !isNonEmptyString(iconKey) || (loaderIdentifier && !isNonEmptyString(loaderIdentifier))
        || (loaderVersionDescriptor && !isNonEmptyString(loaderVersionDescriptor))
        || ((loaderIdentifier == nil) != (loaderVersionDescriptor == nil))) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.versionDescriptor = [versionDescriptor copy];
        self.versionName = [versionName copy];
        self.loaderIdentifier = [loaderIdentifier copy];
        self.loaderVersionDescriptor = [loaderVersionDescriptor copy];
        self.name = [name copy];
        self.groupID = nullableStringCopy(groupID);
        self.iconKey = [iconKey copy];
    }
    return self;
}

@end

@implementation PRVanillaCreationResult

- (instancetype)initWithInstance:(PRInstanceSummary *)instance
                          outcome:(PRVanillaCreationOutcome)outcome
                   localizationKey:(NSString *)localizationKey
                     diagnosticText:(NSString *)diagnosticText
                         retryable:(BOOL)retryable
{
    switch (outcome) {
        case PRVanillaCreationOutcomeSucceeded:
        case PRVanillaCreationOutcomeFailed:
        case PRVanillaCreationOutcomeCancelled:
        case PRVanillaCreationOutcomeRejected:
            break;
        default:
            return nil;
    }
    if (!isNonEmptyString(localizationKey) || (instance && ![instance isKindOfClass:PRInstanceSummary.class])
        || (outcome == PRVanillaCreationOutcomeSucceeded && !instance)
        || (outcome != PRVanillaCreationOutcomeSucceeded && instance)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.instance = instance;
        self.outcome = outcome;
        self.localizationKey = [localizationKey copy];
        self.diagnosticText = [diagnosticText copy];
        self.retryable = retryable;
    }
    return self;
}

@end

@implementation PRInstanceImportRequest

- (instancetype)initWithSourceURL:(NSURL *)sourceURL
                        sourceKind:(PRInstanceImportSourceKind)sourceKind
                              name:(NSString *)name
                           groupID:(NSString *)groupID
                           iconKey:(NSString *)iconKey
{
    switch (sourceKind) {
        case PRInstanceImportSourceKindLocalFile:
            if (![sourceURL isKindOfClass:NSURL.class] || !sourceURL.isFileURL || sourceURL.path.length == 0
                || !sourceURL.path.isAbsolutePath) {
                return nil;
            }
            break;
        case PRInstanceImportSourceKindRemoteURL: {
            if (![sourceURL isKindOfClass:NSURL.class] || sourceURL.isFileURL || sourceURL.host.length == 0) {
                return nil;
            }
            NSString *scheme = sourceURL.scheme.lowercaseString;
            if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
                return nil;
            }
            break;
        }
        default:
            return nil;
    }
    if (!isNonEmptyString(name) || !isNonEmptyString(iconKey)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.sourceURL = [sourceURL copy];
        self.sourceKind = sourceKind;
        self.name = [name copy];
        self.groupID = nullableStringCopy(groupID);
        self.iconKey = [iconKey copy];
    }
    return self;
}

@end

@implementation PRInstanceImportResult

- (instancetype)initWithInstance:(PRInstanceSummary *)instance
                          outcome:(PRInstanceImportOutcome)outcome
                   localizationKey:(NSString *)localizationKey
                     diagnosticText:(NSString *)diagnosticText
                         retryable:(BOOL)retryable
          partialChangesRolledBack:(BOOL)partialChangesRolledBack
{
    switch (outcome) {
        case PRInstanceImportOutcomeSucceeded:
        case PRInstanceImportOutcomeFailed:
        case PRInstanceImportOutcomeCancelled:
        case PRInstanceImportOutcomeRejected:
            break;
        default:
            return nil;
    }
    if (!isNonEmptyString(localizationKey) || (instance && ![instance isKindOfClass:PRInstanceSummary.class])
        || (outcome == PRInstanceImportOutcomeSucceeded && !instance)
        || (outcome != PRInstanceImportOutcomeSucceeded && instance)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.instance = instance;
        self.outcome = outcome;
        self.localizationKey = [localizationKey copy];
        self.diagnosticText = [diagnosticText copy];
        self.retryable = retryable;
        self.partialChangesRolledBack = partialChangesRolledBack;
    }
    return self;
}

@end

@implementation PRInstanceCopyRequest

- (instancetype)initWithSourceInstanceIdentifier:(NSString *)sourceInstanceIdentifier
                                              name:(NSString *)name
                                           groupID:(NSString *)groupID
                                           iconKey:(NSString *)iconKey
                                         copySaves:(BOOL)copySaves
                                      keepPlaytime:(BOOL)keepPlaytime
                                  copyGameOptions:(BOOL)copyGameOptions
                               copyResourcePacks:(BOOL)copyResourcePacks
                                copyShaderPacks:(BOOL)copyShaderPacks
                                     copyServers:(BOOL)copyServers
                                        copyMods:(BOOL)copyMods
                                 copyScreenshots:(BOOL)copyScreenshots
                              useSymbolicLinks:(BOOL)useSymbolicLinks
                                linkRecursively:(BOOL)linkRecursively
                                  useHardLinks:(BOOL)useHardLinks
                                  dontLinkSaves:(BOOL)dontLinkSaves
                                        useClone:(BOOL)useClone
{
    if (!isNonEmptyString(sourceInstanceIdentifier) || !isNonEmptyString(name) || !isNonEmptyString(iconKey)) {
        return nil;
    }
    const BOOL usesLinks = useSymbolicLinks || useHardLinks;
    if ((useClone && usesLinks) || (useHardLinks && !linkRecursively) || (dontLinkSaves && (!usesLinks || !copySaves))) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.sourceInstanceIdentifier = [sourceInstanceIdentifier copy];
        self.name = [name copy];
        self.groupID = nullableStringCopy(groupID);
        self.iconKey = [iconKey copy];
        self.copySaves = copySaves;
        self.keepPlaytime = keepPlaytime;
        self.copyGameOptions = copyGameOptions;
        self.copyResourcePacks = copyResourcePacks;
        self.copyShaderPacks = copyShaderPacks;
        self.copyServers = copyServers;
        self.copyMods = copyMods;
        self.copyScreenshots = copyScreenshots;
        self.useSymbolicLinks = useSymbolicLinks;
        self.linkRecursively = linkRecursively;
        self.useHardLinks = useHardLinks;
        self.dontLinkSaves = dontLinkSaves;
        self.useClone = useClone;
    }
    return self;
}

@end

@implementation PRInstanceCopyResult

- (instancetype)initWithInstance:(PRInstanceSummary *)instance
                          outcome:(PRInstanceCopyOutcome)outcome
                   localizationKey:(NSString *)localizationKey
                     diagnosticText:(NSString *)diagnosticText
                         retryable:(BOOL)retryable
          partialChangesRolledBack:(BOOL)partialChangesRolledBack
{
    switch (outcome) {
        case PRInstanceCopyOutcomeSucceeded:
        case PRInstanceCopyOutcomeFailed:
        case PRInstanceCopyOutcomeCancelled:
        case PRInstanceCopyOutcomeRejected:
            break;
        default:
            return nil;
    }
    if (!isNonEmptyString(localizationKey) || (instance && ![instance isKindOfClass:PRInstanceSummary.class])
        || (outcome == PRInstanceCopyOutcomeSucceeded && !instance)
        || (outcome != PRInstanceCopyOutcomeSucceeded && instance)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.instance = instance;
        self.outcome = outcome;
        self.localizationKey = [localizationKey copy];
        self.diagnosticText = [diagnosticText copy];
        self.retryable = retryable;
        self.partialChangesRolledBack = partialChangesRolledBack;
    }
    return self;
}

@end

@implementation PRInstanceExportRequest

- (instancetype)initWithSourceInstanceIdentifier:(NSString *)sourceInstanceIdentifier
                                      destinationURL:(NSURL *)destinationURL
                                               kind:(PRInstanceExportKind)kind
                                     modListFormat:(PRModListExportFormat)modListFormat
                                       includeAuthors:(BOOL)includeAuthors
                                       includeVersion:(BOOL)includeVersion
                                            includeURL:(BOOL)includeURL
                                        includeFilename:(BOOL)includeFilename
                                       customTemplate:(NSString *)customTemplate
{
    if (!isNonEmptyString(sourceInstanceIdentifier) || !destinationURL.isFileURL || destinationURL.path.length == 0
        || !destinationURL.path.isAbsolutePath || ![customTemplate isKindOfClass:NSString.class]) {
        return nil;
    }
    switch (kind) {
        case PRInstanceExportKindZipArchive:
            if (includeAuthors || includeVersion || includeURL || includeFilename || customTemplate.length != 0) {
                return nil;
            }
            break;
        case PRInstanceExportKindModList:
            switch (modListFormat) {
                case PRModListExportFormatHTML:
                case PRModListExportFormatMarkdown:
                case PRModListExportFormatPlainText:
                case PRModListExportFormatJSON:
                case PRModListExportFormatCSV:
                    if (customTemplate.length != 0) {
                        return nil;
                    }
                    break;
                case PRModListExportFormatCustom:
                    if (customTemplate.length == 0) {
                        return nil;
                    }
                    break;
                default:
                    return nil;
            }
            break;
        default:
            return nil;
    }

    self = [super init];
    if (self) {
        self.sourceInstanceIdentifier = [sourceInstanceIdentifier copy];
        self.destinationURL = [destinationURL.standardizedURL copy];
        self.kind = kind;
        self.modListFormat = modListFormat;
        self.includeAuthors = includeAuthors;
        self.includeVersion = includeVersion;
        self.includeURL = includeURL;
        self.includeFilename = includeFilename;
        self.customTemplate = [customTemplate copy];
    }
    return self;
}

@end

@implementation PRInstanceExportResult

- (instancetype)initWithKind:(PRInstanceExportKind)kind
                      outcome:(PRInstanceExportOutcome)outcome
               destinationURL:(NSURL *)destinationURL
             localizationKey:(NSString *)localizationKey
               diagnosticText:(NSString *)diagnosticText
                   retryable:(BOOL)retryable
    partialChangesRolledBack:(BOOL)partialChangesRolledBack
{
    switch (kind) {
        case PRInstanceExportKindZipArchive:
        case PRInstanceExportKindModList:
            break;
        default:
            return nil;
    }
    switch (outcome) {
        case PRInstanceExportOutcomeSucceeded:
        case PRInstanceExportOutcomeFailed:
        case PRInstanceExportOutcomeCancelled:
        case PRInstanceExportOutcomeRejected:
            break;
        default:
            return nil;
    }
    if (!destinationURL.isFileURL || destinationURL.path.length == 0 || !destinationURL.path.isAbsolutePath
        || !isNonEmptyString(localizationKey)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.kind = kind;
        self.outcome = outcome;
        self.destinationURL = [destinationURL.standardizedURL copy];
        self.localizationKey = [localizationKey copy];
        self.diagnosticText = [diagnosticText copy];
        self.retryable = retryable;
        self.partialChangesRolledBack = partialChangesRolledBack;
    }
    return self;
}

@end

@implementation PRProviderBrowseRequest

- (instancetype)initWithProvider:(PRProviderKind)provider
                             query:(NSString *)query
                            offset:(NSInteger)offset
                          pageSize:(NSInteger)pageSize
                              sort:(PRProviderSort)sort
                      gameVersions:(NSArray<NSString *> *)gameVersions
                          loaders:(NSArray<NSString *> *)loaders
                        categories:(NSArray<NSString *> *)categories
                      releaseTypes:(NSArray<NSNumber *> *)releaseTypes
                              side:(PRProviderSide)side
                        openSource:(BOOL)openSource
                     hideInstalled:(BOOL)hideInstalled
{
    if (!isKnownProviderKind(provider) || !isKnownProviderSort(sort) || !isKnownProviderSide(side)
        || ![query isKindOfClass:NSString.class] || offset < 0 || pageSize <= 0 || pageSize > 100
        || ![gameVersions isKindOfClass:NSArray.class] || ![loaders isKindOfClass:NSArray.class]
        || ![categories isKindOfClass:NSArray.class] || ![releaseTypes isKindOfClass:NSArray.class]) {
        return nil;
    }
    for (id value in gameVersions) {
        if (![value isKindOfClass:NSString.class] || !isNonEmptyString(value)) {
            return nil;
        }
    }
    for (id value in loaders) {
        if (![value isKindOfClass:NSString.class] || !isNonEmptyString(value)) {
            return nil;
        }
    }
    for (id value in categories) {
        if (![value isKindOfClass:NSString.class] || !isNonEmptyString(value)) {
            return nil;
        }
    }
    for (id value in releaseTypes) {
        if (![value isKindOfClass:NSNumber.class]
            || !isKnownProviderReleaseType((PRProviderReleaseType)[value integerValue])) {
            return nil;
        }
    }

    self = [super init];
    if (self) {
        self.provider = provider;
        self.query = [query copy];
        self.offset = offset;
        self.pageSize = pageSize;
        self.sort = sort;
        self.gameVersions = [gameVersions copy];
        self.loaders = [loaders copy];
        self.categories = [categories copy];
        self.releaseTypes = [releaseTypes copy];
        self.side = side;
        self.openSource = openSource;
        self.hideInstalled = hideInstalled;
    }
    return self;
}

@end

@implementation PRProviderPack

- (instancetype)initWithProvider:(PRProviderKind)provider
                         identifier:(NSString *)identifier
                               name:(NSString *)name
                                slug:(NSString *)slug
                             summary:(NSString *)summary
                              author:(NSString *)author
                          categories:(NSArray<NSString *> *)categories
                 versionsAvailable:(BOOL)versionsAvailable
            supportsVersionSelection:(BOOL)supportsVersionSelection
{
    if (!isKnownProviderKind(provider) || !isNonEmptyString(identifier) || !isNonEmptyString(name)
        || ![categories isKindOfClass:NSArray.class]) {
        return nil;
    }
    for (id value in categories) {
        if (![value isKindOfClass:NSString.class] || !isNonEmptyString(value)) {
            return nil;
        }
    }

    self = [super init];
    if (self) {
        self.provider = provider;
        self.identifier = [identifier copy];
        self.name = [name copy];
        self.slug = nullableStringCopy(slug);
        self.summary = nullableStringCopy(summary);
        self.author = nullableStringCopy(author);
        self.categories = [categories copy];
        self.versionsAvailable = versionsAvailable;
        self.supportsVersionSelection = supportsVersionSelection;
    }
    return self;
}

@end

@implementation PRProviderBrowsePage

- (instancetype)initWithProvider:(PRProviderKind)provider
                            offset:(NSInteger)offset
                          pageSize:(NSInteger)pageSize
                       nextOffset:(NSNumber *)nextOffset
                             packs:(NSArray<PRProviderPack *> *)packs
{
    if (!isKnownProviderKind(provider) || offset < 0 || pageSize <= 0 || pageSize > 100
        || ![packs isKindOfClass:NSArray.class] || (nextOffset && [nextOffset integerValue] <= offset)) {
        return nil;
    }
    for (id value in packs) {
        if (![value isKindOfClass:PRProviderPack.class] || ((PRProviderPack *)value).provider != provider) {
            return nil;
        }
    }

    self = [super init];
    if (self) {
        self.provider = provider;
        self.offset = offset;
        self.pageSize = pageSize;
        self.nextOffset = [nextOffset copy];
        self.packs = [packs copy];
    }
    return self;
}

@end

@implementation PRProviderBrowseResult

- (instancetype)initWithPage:(PRProviderBrowsePage *)page
                       outcome:(PRProviderBrowseOutcome)outcome
                localizationKey:(NSString *)localizationKey
                  diagnosticText:(NSString *)diagnosticText
                       retryable:(BOOL)retryable
{
    if (!isKnownProviderBrowseOutcome(outcome) || !isNonEmptyString(localizationKey)
        || (outcome == PRProviderBrowseOutcomeSucceeded && !page)
        || (outcome != PRProviderBrowseOutcomeSucceeded && page)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.page = page;
        self.outcome = outcome;
        self.localizationKey = [localizationKey copy];
        self.diagnosticText = [diagnosticText copy];
        self.retryable = retryable;
    }
    return self;
}

@end

@implementation PRProviderVersionRequest

- (instancetype)initWithProvider:(PRProviderKind)provider
                    packIdentifier:(NSString *)packIdentifier
                      gameVersions:(NSArray<NSString *> *)gameVersions
                          loaders:(NSArray<NSString *> *)loaders
{
    if (!isKnownProviderKind(provider) || !isNonEmptyString(packIdentifier)
        || ![gameVersions isKindOfClass:NSArray.class] || ![loaders isKindOfClass:NSArray.class]) {
        return nil;
    }
    for (id value in gameVersions) {
        if (![value isKindOfClass:NSString.class] || !isNonEmptyString(value)) {
            return nil;
        }
    }
    for (id value in loaders) {
        if (![value isKindOfClass:NSString.class] || !isNonEmptyString(value)) {
            return nil;
        }
    }

    self = [super init];
    if (self) {
        self.provider = provider;
        self.packIdentifier = [packIdentifier copy];
        self.gameVersions = [gameVersions copy];
        self.loaders = [loaders copy];
    }
    return self;
}

@end

@implementation PRProviderVersion

- (instancetype)initWithProvider:(PRProviderKind)provider
                         identifier:(NSString *)identifier
                     packIdentifier:(NSString *)packIdentifier
                               name:(NSString *)name
                            version:(NSString *)version
                      gameVersions:(NSArray<NSString *> *)gameVersions
                          loaders:(NSArray<NSString *> *)loaders
                      releaseType:(PRProviderReleaseType)releaseType
           publishedUnixSeconds:(NSInteger)publishedUnixSeconds
                        recommended:(BOOL)recommended
{
    if (!isKnownProviderKind(provider) || !isKnownProviderReleaseType(releaseType) || !isNonEmptyString(identifier)
        || !isNonEmptyString(packIdentifier) || !isNonEmptyString(name) || !isNonEmptyString(version)
        || ![gameVersions isKindOfClass:NSArray.class] || ![loaders isKindOfClass:NSArray.class]) {
        return nil;
    }
    for (id value in gameVersions) {
        if (![value isKindOfClass:NSString.class] || !isNonEmptyString(value)) {
            return nil;
        }
    }
    for (id value in loaders) {
        if (![value isKindOfClass:NSString.class] || !isNonEmptyString(value)) {
            return nil;
        }
    }

    self = [super init];
    if (self) {
        self.provider = provider;
        self.identifier = [identifier copy];
        self.packIdentifier = [packIdentifier copy];
        self.name = [name copy];
        self.version = [version copy];
        self.gameVersions = [gameVersions copy];
        self.loaders = [loaders copy];
        self.releaseType = releaseType;
        self.publishedUnixSeconds = publishedUnixSeconds;
        self.recommended = recommended;
    }
    return self;
}

@end

@implementation PRProviderVersionResult

- (instancetype)initWithProvider:(PRProviderKind)provider
                    packIdentifier:(NSString *)packIdentifier
                           versions:(NSArray<PRProviderVersion *> *)versions
                            outcome:(PRProviderVersionOutcome)outcome
                     localizationKey:(NSString *)localizationKey
                       diagnosticText:(NSString *)diagnosticText
                            retryable:(BOOL)retryable
{
    if (!isKnownProviderKind(provider) || !isKnownProviderVersionOutcome(outcome)
        || !isNonEmptyString(packIdentifier) || ![versions isKindOfClass:NSArray.class]
        || !isNonEmptyString(localizationKey)) {
        return nil;
    }
    if (outcome != PRProviderVersionOutcomeSucceeded && versions.count != 0) {
        return nil;
    }
    for (id value in versions) {
        PRProviderVersion *version = (PRProviderVersion *)value;
        if (![value isKindOfClass:PRProviderVersion.class] || version.provider != provider
            || ![version.packIdentifier isEqualToString:packIdentifier]) {
            return nil;
        }
    }

    self = [super init];
    if (self) {
        self.provider = provider;
        self.packIdentifier = [packIdentifier copy];
        self.versions = [versions copy];
        self.outcome = outcome;
        self.localizationKey = [localizationKey copy];
        self.diagnosticText = [diagnosticText copy];
        self.retryable = retryable;
    }
    return self;
}

@end

@implementation PRProviderInstallFileOption

- (instancetype)initWithIdentifier:(NSString *)identifier
                               name:(NSString *)name
                         targetPath:(NSString *)targetPath
                           required:(BOOL)required
                            blocked:(BOOL)blocked
                           selected:(BOOL)selected
{
    if (!isNonEmptyString(identifier) || !isNonEmptyString(name) || !isNonEmptyString(targetPath)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.name = [name copy];
        self.targetPath = [targetPath copy];
        self.required = required;
        self.blocked = blocked;
        self.selected = selected;
    }
    return self;
}

@end

@implementation PRProviderInstallRecoveryPrompt

- (instancetype)initWithKind:(PRProviderInstallRecoveryKind)kind
                         files:(NSArray<PRProviderInstallFileOption *> *)files
               localizationKey:(NSString *)localizationKey
                 diagnosticText:(NSString *)diagnosticText
                     retryable:(BOOL)retryable
{
    if (!isKnownProviderInstallRecoveryKind(kind) || !retryable || !isNonEmptyString(localizationKey)
        || ![files isKindOfClass:NSArray.class]) {
        return nil;
    }

    const bool isFilePrompt = kind == PRProviderInstallRecoveryKindOptionalFiles
        || kind == PRProviderInstallRecoveryKindBlockedFiles;
    if (isFilePrompt != (files.count > 0)) {
        return nil;
    }

    NSMutableSet<NSString *> *identifiers = [NSMutableSet setWithCapacity:files.count];
    for (id value in files) {
        if (![value isKindOfClass:PRProviderInstallFileOption.class]) {
            return nil;
        }
        PRProviderInstallFileOption *file = (PRProviderInstallFileOption *)value;
        if (![identifiers containsObject:file.identifier]) {
            [identifiers addObject:file.identifier];
        } else {
            return nil;
        }
        if (kind == PRProviderInstallRecoveryKindOptionalFiles && (file.required || file.blocked)) {
            return nil;
        }
        if (kind == PRProviderInstallRecoveryKindBlockedFiles && !file.blocked) {
            return nil;
        }
    }

    self = [super init];
    if (self) {
        self.kind = kind;
        self.files = [files copy];
        self.localizationKey = [localizationKey copy];
        self.diagnosticText = [diagnosticText copy];
        self.retryable = retryable;
    }
    return self;
}

@end

@implementation PRProviderInstallRecoveryDecision

- (instancetype)initWithKind:(PRProviderInstallRecoveryKind)kind
                        action:(PRProviderInstallRecoveryAction)action
     selectedFileIdentifiers:(NSArray<NSString *> *)selectedFileIdentifiers
resolvedBlockedFileIdentifiers:(NSArray<NSString *> *)resolvedBlockedFileIdentifiers
{
    if (!isKnownProviderInstallRecoveryKind(kind) || !isKnownProviderInstallRecoveryAction(action)
        || ![selectedFileIdentifiers isKindOfClass:NSArray.class]
        || ![resolvedBlockedFileIdentifiers isKindOfClass:NSArray.class]) {
        return nil;
    }

    NSMutableSet<NSString *> *selected = [NSMutableSet setWithCapacity:selectedFileIdentifiers.count];
    for (id value in selectedFileIdentifiers) {
        if (![value isKindOfClass:NSString.class] || !isNonEmptyString((NSString *)value)
            || [selected containsObject:value]) {
            return nil;
        }
        [selected addObject:value];
    }
    NSMutableSet<NSString *> *resolved = [NSMutableSet setWithCapacity:resolvedBlockedFileIdentifiers.count];
    for (id value in resolvedBlockedFileIdentifiers) {
        if (![value isKindOfClass:NSString.class] || !isNonEmptyString((NSString *)value)
            || [resolved containsObject:value]) {
            return nil;
        }
        [resolved addObject:value];
    }

    const bool isFilePrompt = kind == PRProviderInstallRecoveryKindOptionalFiles
        || kind == PRProviderInstallRecoveryKindBlockedFiles;
    if (isFilePrompt) {
        if (action != PRProviderInstallRecoveryActionContinue
            || (kind == PRProviderInstallRecoveryKindOptionalFiles && resolved.count != 0)
            || (kind == PRProviderInstallRecoveryKindBlockedFiles && selected.count != 0)) {
            return nil;
        }
    } else if (action == PRProviderInstallRecoveryActionContinue || selected.count != 0 || resolved.count != 0) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.kind = kind;
        self.action = action;
        self.selectedFileIdentifiers = [selectedFileIdentifiers copy];
        self.resolvedBlockedFileIdentifiers = [resolvedBlockedFileIdentifiers copy];
    }
    return self;
}

@end

@implementation PRProviderInstallRequest

- (instancetype)initWithKind:(PRProviderInstallKind)kind
               packIdentifier:(NSString *)packIdentifier
           versionIdentifier:(NSString *)versionIdentifier
                   sourceURL:(NSURL *)sourceURL
                        name:(NSString *)name
                     groupID:(NSString *)groupID
                     iconKey:(NSString *)iconKey
{
    return [self initWithKind:kind
               packIdentifier:packIdentifier
           versionIdentifier:versionIdentifier
                   sourceURL:sourceURL
                        name:name
                     groupID:groupID
                     iconKey:iconKey
           recoveryDecision:nil];
}

- (instancetype)initWithKind:(PRProviderInstallKind)kind
               packIdentifier:(NSString *)packIdentifier
           versionIdentifier:(NSString *)versionIdentifier
                   sourceURL:(NSURL *)sourceURL
                        name:(NSString *)name
                     groupID:(NSString *)groupID
                     iconKey:(NSString *)iconKey
           recoveryDecision:(PRProviderInstallRecoveryDecision *)recoveryDecision
{
    if (!isKnownProviderInstallKind(kind) || !isNonEmptyString(packIdentifier)
        || !isNonEmptyString(versionIdentifier) || !isNonEmptyString(name) || !isNonEmptyString(iconKey)
        || (recoveryDecision && ![recoveryDecision isKindOfClass:PRProviderInstallRecoveryDecision.class])) {
        return nil;
    }

    const bool requiresLocalSource = kind == PRProviderInstallKindCustomArchive
        || kind == PRProviderInstallKindFTBImport;
    if (requiresLocalSource) {
        if (![sourceURL isKindOfClass:NSURL.class] || !sourceURL.isFileURL || sourceURL.path.length == 0
            || !sourceURL.path.isAbsolutePath) {
            return nil;
        }
    } else if (sourceURL) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.kind = kind;
        self.packIdentifier = [packIdentifier copy];
        self.versionIdentifier = [versionIdentifier copy];
        self.sourceURL = [sourceURL.standardizedURL copy];
        self.name = [name copy];
        self.groupID = nullableStringCopy(groupID);
        self.iconKey = [iconKey copy];
        self.recoveryDecision = recoveryDecision;
    }
    return self;
}

@end

@implementation PRProviderInstallResult

- (instancetype)initWithKind:(PRProviderInstallKind)kind
               packIdentifier:(NSString *)packIdentifier
           versionIdentifier:(NSString *)versionIdentifier
                    instance:(PRInstanceSummary *)instance
                     outcome:(PRProviderInstallOutcome)outcome
             rollbackOutcome:(PRProviderInstallRollbackOutcome)rollbackOutcome
              localizationKey:(NSString *)localizationKey
                diagnosticText:(NSString *)diagnosticText
                     retryable:(BOOL)retryable
{
    return [self initWithKind:kind
               packIdentifier:packIdentifier
           versionIdentifier:versionIdentifier
                    instance:instance
                     outcome:outcome
             rollbackOutcome:rollbackOutcome
              localizationKey:localizationKey
                diagnosticText:diagnosticText
                     retryable:retryable
            recoveryPrompt:nil];
}

- (instancetype)initWithKind:(PRProviderInstallKind)kind
               packIdentifier:(NSString *)packIdentifier
           versionIdentifier:(NSString *)versionIdentifier
                    instance:(PRInstanceSummary *)instance
                     outcome:(PRProviderInstallOutcome)outcome
             rollbackOutcome:(PRProviderInstallRollbackOutcome)rollbackOutcome
              localizationKey:(NSString *)localizationKey
                diagnosticText:(NSString *)diagnosticText
                     retryable:(BOOL)retryable
            recoveryPrompt:(PRProviderInstallRecoveryPrompt *)recoveryPrompt
{
    if (!isKnownProviderInstallKind(kind) || !isKnownProviderInstallOutcome(outcome)
        || !isKnownProviderInstallRollbackOutcome(rollbackOutcome) || !isNonEmptyString(packIdentifier)
        || !isNonEmptyString(versionIdentifier) || !isNonEmptyString(localizationKey)
        || (instance && ![instance isKindOfClass:PRInstanceSummary.class])
        || (outcome == PRProviderInstallOutcomeSucceeded && !instance)
        || (outcome != PRProviderInstallOutcomeSucceeded && instance)
        || (outcome == PRProviderInstallOutcomeSucceeded
            && rollbackOutcome != PRProviderInstallRollbackOutcomeNotRequired)
        || (outcome == PRProviderInstallOutcomeRejected
            && rollbackOutcome != PRProviderInstallRollbackOutcomeNotRequired)
        || (recoveryPrompt && (!retryable || outcome != PRProviderInstallOutcomeFailed
                               || ![recoveryPrompt isKindOfClass:PRProviderInstallRecoveryPrompt.class]))) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.kind = kind;
        self.packIdentifier = [packIdentifier copy];
        self.versionIdentifier = [versionIdentifier copy];
        self.instance = instance;
        self.outcome = outcome;
        self.rollbackOutcome = rollbackOutcome;
        self.localizationKey = [localizationKey copy];
        self.diagnosticText = [diagnosticText copy];
        self.retryable = retryable;
        self.recoveryPrompt = recoveryPrompt;
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

@implementation PRInstanceComponent

- (instancetype)initWithIdentifier:(NSString *)identifier
                               name:(NSString *)name
                            version:(NSString *)version
                            enabled:(BOOL)enabled
                     canBeDisabled:(BOOL)canBeDisabled
                     dependencyOnly:(BOOL)dependencyOnly
                          important:(BOOL)important
                             custom:(BOOL)custom
                   problemSeverity:(PRInstanceComponentProblemSeverity)problemSeverity
                 problemDescriptions:(NSArray<NSString *> *)problemDescriptions
{
    NSArray<NSString *> *copiedDescriptions = [problemDescriptions isKindOfClass:NSArray.class]
        ? [problemDescriptions copy]
        : nil;
    if (!isNonEmptyString(identifier) || !isNonEmptyString(name) || ![version isKindOfClass:NSString.class]
        || !copiedDescriptions || !isKnownInstanceComponentProblemSeverity(problemSeverity)
        || (!canBeDisabled && !enabled)) {
        return nil;
    }
    for (id description in copiedDescriptions) {
        if (![description isKindOfClass:NSString.class]) {
            return nil;
        }
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.name = [name copy];
        self.version = [version copy];
        self.enabled = enabled;
        self.canBeDisabled = canBeDisabled;
        self.dependencyOnly = dependencyOnly;
        self.important = important;
        self.custom = custom;
        self.problemSeverity = problemSeverity;
        self.problemDescriptions = copiedDescriptions;
    }
    return self;
}

@end

@implementation PRInstanceResource

- (instancetype)initWithIdentifier:(NSString *)identifier
                               name:(NSString *)name
                            version:(NSString *)version
                           fileName:(NSString *)fileName
                           provider:(NSString *)provider
                               kind:(PRInstanceResourceKind)kind
                            enabled:(BOOL)enabled
                     canBeToggled:(BOOL)canBeToggled
                     canBeDeleted:(BOOL)canBeDeleted
                       isDirectory:(BOOL)isDirectory
                       hasMetadata:(BOOL)hasMetadata
                problemDescriptions:(NSArray<NSString *> *)problemDescriptions
{
    NSArray<NSString *> *copiedDescriptions = [problemDescriptions isKindOfClass:NSArray.class]
        ? [problemDescriptions copy]
        : nil;
    if (!isNonEmptyString(identifier) || !isNonEmptyString(name) || !isNonEmptyString(fileName)
        || ![version isKindOfClass:NSString.class] || ![provider isKindOfClass:NSString.class]
        || !isKnownResourceKind(kind) || (isDirectory && canBeToggled) || !copiedDescriptions) {
        return nil;
    }
    for (id description in copiedDescriptions) {
        if (![description isKindOfClass:NSString.class]) {
            return nil;
        }
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.name = [name copy];
        self.version = [version copy];
        self.fileName = [fileName copy];
        self.provider = [provider copy];
        self.kind = kind;
        self.enabled = enabled;
        self.canBeToggled = canBeToggled;
        self.canBeDeleted = canBeDeleted;
        self.directory = isDirectory;
        self.hasMetadata = hasMetadata;
        self.problemDescriptions = copiedDescriptions;
    }
    return self;
}

@end

@implementation PRInstanceResourceMutationResult

- (instancetype)initWithInstanceIdentifier:(NSString *)instanceIdentifier
                          resourceIdentifier:(NSString *)resourceIdentifier
                                        kind:(PRInstanceResourceKind)kind
                                      action:(PRInstanceResourceAction)action
                                     outcome:(PRInstanceResourceMutationOutcome)outcome
                              localizationKey:(NSString *)localizationKey
                               diagnosticText:(NSString *)diagnosticText
                    partialChangesRolledBack:(BOOL)partialChangesRolledBack
{
    if (!isNonEmptyString(instanceIdentifier) || !isNonEmptyString(resourceIdentifier)
        || !isKnownResourceKind(kind) || !isKnownResourceAction(action)
        || !isKnownResourceMutationOutcome(outcome)
        || (localizationKey && ![localizationKey isKindOfClass:NSString.class])
        || (diagnosticText && ![diagnosticText isKindOfClass:NSString.class])) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.instanceIdentifier = [instanceIdentifier copy];
        self.resourceIdentifier = [resourceIdentifier copy];
        self.kind = kind;
        self.action = action;
        self.outcome = outcome;
        self.localizationKey = [localizationKey copy];
        self.diagnosticText = [diagnosticText copy];
        self.partialChangesRolledBack = partialChangesRolledBack;
    }
    return self;
}

@end

@implementation PRInstanceWorld

- (instancetype)initWithIdentifier:(NSString *)identifier
                               name:(NSString *)name
                         folderName:(NSString *)folderName
                           gameMode:(NSString *)gameMode
                           iconKey:(NSString *)iconKey
                 warningDescription:(NSString *)warningDescription
              lastPlayedUnixSeconds:(NSInteger)lastPlayedUnixSeconds
                          sizeBytes:(uint64_t)sizeBytes
                               seed:(NSNumber *)seed
                          isArchive:(BOOL)isArchive
                     canBeRenamed:(BOOL)canBeRenamed
                      canBeCopied:(BOOL)canBeCopied
                     canBeDeleted:(BOOL)canBeDeleted
                       canBeJoined:(BOOL)canBeJoined
                         hasIcon:(BOOL)hasIcon
{
    if (!isNonEmptyString(identifier) || !isNonEmptyString(name) || !isNonEmptyString(folderName)
        || ![gameMode isKindOfClass:NSString.class] || (iconKey && ![iconKey isKindOfClass:NSString.class])
        || (warningDescription && ![warningDescription isKindOfClass:NSString.class])
        || (seed && ![seed isKindOfClass:NSNumber.class])) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.name = [name copy];
        self.folderName = [folderName copy];
        self.gameMode = [gameMode copy];
        self.iconKey = [iconKey copy];
        self.warningDescription = [warningDescription copy];
        self.lastPlayedUnixSeconds = lastPlayedUnixSeconds;
        self.sizeBytes = sizeBytes;
        self.seed = [seed copy];
        self.archive = isArchive;
        self.canBeRenamed = canBeRenamed;
        self.canBeCopied = canBeCopied;
        self.canBeDeleted = canBeDeleted;
        self.canBeJoined = canBeJoined;
        self.hasIcon = hasIcon;
    }
    return self;
}

@end

@implementation PRInstanceServer

- (instancetype)initWithIdentifier:(NSString *)identifier
                               name:(NSString *)name
                            address:(NSString *)address
                     resourcePolicy:(PRInstanceServerResourcePolicy)resourcePolicy
                             status:(PRInstanceServerStatus)status
                      onlinePlayers:(NSInteger)onlinePlayers
                        canBeEdited:(BOOL)canBeEdited
                       canBeDeleted:(BOOL)canBeDeleted
                        canBeJoined:(BOOL)canBeJoined
{
    if (!isNonEmptyString(identifier) || !isNonEmptyString(name) || !isNonEmptyString(address)
        || !isKnownServerResourcePolicy(resourcePolicy) || !isKnownServerStatus(status) || onlinePlayers < -1) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.name = [name copy];
        self.address = [address copy];
        self.resourcePolicy = resourcePolicy;
        self.status = status;
        self.onlinePlayers = onlinePlayers;
        self.canBeEdited = canBeEdited;
        self.canBeDeleted = canBeDeleted;
        self.canBeJoined = canBeJoined;
    }
    return self;
}

@end

@implementation PRInstanceScreenshot

- (instancetype)initWithIdentifier:(NSString *)identifier
                           fileName:(NSString *)fileName
                       displayName:(NSString *)displayName
              modifiedUnixSeconds:(NSInteger)modifiedUnixSeconds
                          sizeBytes:(uint64_t)sizeBytes
                           readable:(BOOL)readable
                           writable:(BOOL)writable
{
    if (!isNonEmptyString(identifier) || !isNonEmptyString(fileName) || !isNonEmptyString(displayName)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.fileName = [fileName copy];
        self.displayName = [displayName copy];
        self.modifiedUnixSeconds = modifiedUnixSeconds;
        self.sizeBytes = sizeBytes;
        self.readable = readable;
        self.writable = writable;
    }
    return self;
}

@end

@implementation PRInstanceLogFile

- (instancetype)initWithIdentifier:(NSString *)identifier
                           fileName:(NSString *)fileName
                       displayName:(NSString *)displayName
              modifiedUnixSeconds:(NSInteger)modifiedUnixSeconds
                          sizeBytes:(uint64_t)sizeBytes
                         compressed:(BOOL)compressed
                            current:(BOOL)current
                           readable:(BOOL)readable
                       canBeDeleted:(BOOL)canBeDeleted
{
    if (!isNonEmptyString(identifier) || !isNonEmptyString(fileName) || !isNonEmptyString(displayName)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.fileName = [fileName copy];
        self.displayName = [displayName copy];
        self.modifiedUnixSeconds = modifiedUnixSeconds;
        self.sizeBytes = sizeBytes;
        self.compressed = compressed;
        self.current = current;
        self.readable = readable;
        self.canBeDeleted = canBeDeleted;
    }
    return self;
}

@end

@implementation PRInstanceLogSnapshot

- (instancetype)initWithInstanceIdentifier:(NSString *)instanceIdentifier
                               logIdentifier:(NSString *)logIdentifier
                                     entries:(NSArray<PRTaskLogEntry *> *)entries
                          droppedEntryCount:(uint64_t)droppedEntryCount
                               totalByteCount:(uint64_t)totalByteCount
                                   truncated:(BOOL)truncated
{
    if (!isNonEmptyString(instanceIdentifier) || !isNonEmptyString(logIdentifier)
        || ![entries isKindOfClass:NSArray.class] || entries.count > kFrontendLogMaxEntries
        || totalByteCount > kFrontendLogMaxBytes) {
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
        self.instanceIdentifier = [instanceIdentifier copy];
        self.logIdentifier = [logIdentifier copy];
        self.entries = [entries copy];
        self.droppedEntryCount = droppedEntryCount;
        self.totalByteCount = totalByteCount;
        self.truncated = truncated;
    }
    return self;
}

@end

@implementation PRInstanceDetailMutationRequest

- (instancetype)initWithKind:(PRInstanceDetailKind)kind
                        action:(PRInstanceDetailAction)action
               itemIdentifier:(NSString *)itemIdentifier
                    sourceURL:(NSURL *)sourceURL
                   targetName:(NSString *)targetName
                          name:(NSString *)name
                       address:(NSString *)address
                resourcePolicy:(PRInstanceServerResourcePolicy)resourcePolicy
                     confirmed:(BOOL)confirmed
                      position:(NSInteger)position
{
    if (!isKnownInstanceDetailKind(kind) || !isKnownInstanceDetailAction(action)
        || ![itemIdentifier isKindOfClass:NSString.class] || (sourceURL && ![sourceURL isKindOfClass:NSURL.class])
        || ![targetName isKindOfClass:NSString.class] || ![name isKindOfClass:NSString.class]
        || ![address isKindOfClass:NSString.class] || !isKnownServerResourcePolicy(resourcePolicy)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.kind = kind;
        self.action = action;
        self.itemIdentifier = [itemIdentifier copy];
        self.sourceURL = [sourceURL copy];
        self.targetName = [targetName copy];
        self.name = [name copy];
        self.address = [address copy];
        self.resourcePolicy = resourcePolicy;
        self.confirmed = confirmed;
        self.position = position;
    }
    return self;
}

@end

@implementation PRInstanceDetailMutationResult

- (instancetype)initWithKind:(PRInstanceDetailKind)kind
                        action:(PRInstanceDetailAction)action
                      outcome:(PRInstanceDetailMutationOutcome)outcome
            instanceIdentifier:(NSString *)instanceIdentifier
                 itemIdentifier:(NSString *)itemIdentifier
                localizationKey:(NSString *)localizationKey
                 diagnosticText:(NSString *)diagnosticText
      partialChangesRolledBack:(BOOL)partialChangesRolledBack
{
    if (!isKnownInstanceDetailKind(kind) || !isKnownInstanceDetailAction(action)
        || !isKnownInstanceDetailMutationOutcome(outcome) || !isNonEmptyString(instanceIdentifier)
        || ![itemIdentifier isKindOfClass:NSString.class]
        || (localizationKey && ![localizationKey isKindOfClass:NSString.class])
        || (diagnosticText && ![diagnosticText isKindOfClass:NSString.class])) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.kind = kind;
        self.action = action;
        self.outcome = outcome;
        self.instanceIdentifier = [instanceIdentifier copy];
        self.itemIdentifier = [itemIdentifier copy];
        self.localizationKey = [localizationKey copy];
        self.diagnosticText = [diagnosticText copy];
        self.partialChangesRolledBack = partialChangesRolledBack;
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

@implementation PRGlobalSettings

- (instancetype)initWithInstanceDirectoryURL:(NSURL *)instanceDirectoryURL
                                     iconTheme:(NSString *)iconTheme
                             applicationTheme:(NSString *)applicationTheme
                               backgroundCat:(NSString *)backgroundCat
                                 catOpacity:(NSInteger)catOpacity
                                     catFit:(NSString *)catFit
                                   language:(NSString *)language
                           useSystemLocale:(BOOL)useSystemLocale
                    menuBarInsteadOfToolBar:(BOOL)menuBarInsteadOfToolBar
                          statusBarVisible:(BOOL)statusBarVisible
                            toolbarsLocked:(BOOL)toolbarsLocked
                 numberOfConcurrentTasks:(NSInteger)numberOfConcurrentTasks
             numberOfConcurrentDownloads:(NSInteger)numberOfConcurrentDownloads
                   numberOfManualRetries:(NSInteger)numberOfManualRetries
                       requestTimeoutSeconds:(NSInteger)requestTimeoutSeconds
                                consoleFont:(NSString *)consoleFont
                            consoleFontSize:(NSInteger)consoleFontSize
                             consoleMaxLines:(NSInteger)consoleMaxLines
                          consoleOverflowStop:(BOOL)consoleOverflowStop
                                  showConsole:(BOOL)showConsole
                               autoCloseConsole:(BOOL)autoCloseConsole
                             showConsoleOnError:(BOOL)showConsoleOnError
                              logPrePostOutput:(BOOL)logPrePostOutput
{
    if (!instanceDirectoryURL.isFileURL || instanceDirectoryURL.path.length == 0
        || !instanceDirectoryURL.path.isAbsolutePath || ![iconTheme isKindOfClass:NSString.class]
        || ![applicationTheme isKindOfClass:NSString.class] || ![backgroundCat isKindOfClass:NSString.class]
        || ![catFit isKindOfClass:NSString.class] || !isKnownGlobalSettingsCatFit(catFit)
        || ![language isKindOfClass:NSString.class] || ![consoleFont isKindOfClass:NSString.class]
        || catOpacity < 0 || catOpacity > 100 || numberOfConcurrentTasks < 1
        || numberOfConcurrentDownloads < 1 || numberOfManualRetries < 0 || requestTimeoutSeconds < 0
        || consoleFontSize < 5 || consoleFontSize > 16 || consoleMaxLines < 10000
        || consoleMaxLines > 1000000) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.instanceDirectoryURL = [instanceDirectoryURL copy];
        self.iconTheme = [iconTheme copy];
        self.applicationTheme = [applicationTheme copy];
        self.backgroundCat = [backgroundCat copy];
        self.catOpacity = catOpacity;
        self.catFit = [catFit copy];
        self.language = [language copy];
        self.useSystemLocale = useSystemLocale;
        self.menuBarInsteadOfToolBar = menuBarInsteadOfToolBar;
        self.statusBarVisible = statusBarVisible;
        self.toolbarsLocked = toolbarsLocked;
        self.numberOfConcurrentTasks = numberOfConcurrentTasks;
        self.numberOfConcurrentDownloads = numberOfConcurrentDownloads;
        self.numberOfManualRetries = numberOfManualRetries;
        self.requestTimeoutSeconds = requestTimeoutSeconds;
        self.consoleFont = [consoleFont copy];
        self.consoleFontSize = consoleFontSize;
        self.consoleMaxLines = consoleMaxLines;
        self.consoleOverflowStop = consoleOverflowStop;
        self.showConsole = showConsole;
        self.autoCloseConsole = autoCloseConsole;
        self.showConsoleOnError = showConsoleOnError;
        self.logPrePostOutput = logPrePostOutput;
    }
    return self;
}

@end

@implementation PRGlobalSettingsUpdateResult

- (instancetype)initWithSettings:(PRGlobalSettings *)settings outcome:(PRGlobalSettingsUpdateOutcome)outcome
{
    if (!isKnownGlobalSettingsUpdateOutcome(outcome)
        || (outcome == PRGlobalSettingsUpdateOutcomeSucceeded && !settings)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.settings = settings;
        self.outcome = outcome;
    }
    return self;
}

@end

@implementation PRJavaInstallation

- (instancetype)initWithIdentifier:(NSString *)identifier
                             version:(NSString *)version
                              vendor:(NSString *)vendor
                        architecture:(NSString *)architecture
                     executablePath:(NSString *)executablePath
                           is64Bit:(BOOL)is64Bit
                            managed:(BOOL)managed
                           validity:(PRJavaInstallationValidity)validity
                     diagnosticText:(NSString *)diagnosticText
{
    if (!isNonEmptyString(identifier) || ![version isKindOfClass:NSString.class]
        || ![vendor isKindOfClass:NSString.class] || ![architecture isKindOfClass:NSString.class]
        || !isNonEmptyString(executablePath) || !isKnownJavaInstallationValidity(validity)
        || (validity == PRJavaInstallationValidityValid
            && (!isNonEmptyString(version) || !isNonEmptyString(architecture)))) {
        return nil;
    }

    if (diagnosticText && ![diagnosticText isKindOfClass:NSString.class]) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.version = [version copy];
        self.vendor = [vendor copy];
        self.architecture = [architecture copy];
        self.executablePath = [executablePath copy];
        self.is64Bit = is64Bit;
        self.managed = managed;
        self.validity = validity;
        self.diagnosticText = [diagnosticText copy];
    }
    return self;
}

@end

@implementation PRJavaDiscoveryResult

- (instancetype)initWithInstallations:(NSArray<PRJavaInstallation *> *)installations
                                outcome:(PRJavaDiscoveryOutcome)outcome
                        localizationKey:(NSString *)localizationKey
                          diagnosticText:(NSString *)diagnosticText
                              retryable:(BOOL)retryable
{
    return [self initWithInstallations:installations
                               outcome:outcome
                       localizationKey:localizationKey
                         diagnosticText:diagnosticText
                             retryable:retryable
          selectedInstallationIdentifier:nil];
}

- (instancetype)initWithInstallations:(NSArray<PRJavaInstallation *> *)installations
                                outcome:(PRJavaDiscoveryOutcome)outcome
                        localizationKey:(NSString *)localizationKey
                          diagnosticText:(NSString *)diagnosticText
                              retryable:(BOOL)retryable
           selectedInstallationIdentifier:(NSString *)selectedInstallationIdentifier
{
    if (![installations isKindOfClass:NSArray.class] || !isKnownJavaDiscoveryOutcome(outcome)
        || ![localizationKey isKindOfClass:NSString.class]
        || (outcome != PRJavaDiscoveryOutcomeSucceeded && !isNonEmptyString(localizationKey))) {
        return nil;
    }
    for (id installation in installations) {
        if (![installation isKindOfClass:PRJavaInstallation.class]) {
            return nil;
        }
    }
    if (diagnosticText && ![diagnosticText isKindOfClass:NSString.class]) {
        return nil;
    }
    if (selectedInstallationIdentifier && !isNonEmptyString(selectedInstallationIdentifier)) {
        return nil;
    }
    if (selectedInstallationIdentifier) {
        BOOL found = NO;
        for (PRJavaInstallation *installation in installations) {
            if ([installation.identifier isEqualToString:selectedInstallationIdentifier]) {
                found = installation.validity == PRJavaInstallationValidityValid;
                break;
            }
        }
        if (!found || outcome != PRJavaDiscoveryOutcomeSucceeded) {
            return nil;
        }
    }

    self = [super init];
    if (self) {
        self.installations = [installations copy];
        self.outcome = outcome;
        self.localizationKey = [localizationKey copy];
        self.diagnosticText = [diagnosticText copy];
        self.retryable = retryable;
        self.selectedInstallationIdentifier = [selectedInstallationIdentifier copy];
    }
    return self;
}

@end

@implementation PRJavaSelectionResult

- (instancetype)initWithInstallation:(PRJavaInstallation *)installation
                               outcome:(PRJavaSelectionOutcome)outcome
                       localizationKey:(NSString *)localizationKey
                         diagnosticText:(NSString *)diagnosticText
{
    if (!isKnownJavaSelectionOutcome(outcome) || ![localizationKey isKindOfClass:NSString.class]
        || (outcome == PRJavaSelectionOutcomeSucceeded
            && (!installation || installation.validity != PRJavaInstallationValidityValid))
        || (outcome != PRJavaSelectionOutcomeSucceeded && !isNonEmptyString(localizationKey))) {
        return nil;
    }
    if (diagnosticText && ![diagnosticText isKindOfClass:NSString.class]) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.installation = installation;
        self.outcome = outcome;
        self.localizationKey = [localizationKey copy];
        self.diagnosticText = [diagnosticText copy];
    }
    return self;
}

@end

@implementation PRAccountSnapshot

- (instancetype)initWithIdentifier:(NSString *)identifier
                        displayName:(NSString *)displayName
                               type:(PRAccountType)type
                              state:(PRAccountState)state
                      ownsMinecraft:(BOOL)ownsMinecraft
                             isBusy:(BOOL)isBusy
                     canBeSelected:(BOOL)canBeSelected
                     diagnosticText:(NSString *)diagnosticText
{
    if (!isNonEmptyString(identifier) || !isNonEmptyString(displayName) || !isKnownAccountType(type)
        || !isKnownAccountState(state)) {
        return nil;
    }
    if (diagnosticText && ![diagnosticText isKindOfClass:NSString.class]) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.identifier = [identifier copy];
        self.displayName = [displayName copy];
        self.type = type;
        self.state = state;
        self.ownsMinecraft = ownsMinecraft;
        self.isBusy = isBusy;
        self.canBeSelected = canBeSelected;
        self.diagnosticText = [diagnosticText copy];
    }
    return self;
}

@end

@implementation PRAccountSnapshotResult

- (instancetype)initWithAccounts:(NSArray<PRAccountSnapshot *> *)accounts
             activeAccountIdentifier:(NSString *)activeAccountIdentifier
                            outcome:(PRAccountSnapshotOutcome)outcome
                    localizationKey:(NSString *)localizationKey
                      diagnosticText:(NSString *)diagnosticText
                          retryable:(BOOL)retryable
{
    if (![accounts isKindOfClass:NSArray.class] || !isKnownAccountSnapshotOutcome(outcome)
        || ![localizationKey isKindOfClass:NSString.class]
        || (outcome != PRAccountSnapshotOutcomeSucceeded && !isNonEmptyString(localizationKey))) {
        return nil;
    }

    NSMutableSet<NSString *> *identifiers = [NSMutableSet setWithCapacity:accounts.count];
    for (id account in accounts) {
        if (![account isKindOfClass:PRAccountSnapshot.class]
            || [identifiers containsObject:((PRAccountSnapshot *)account).identifier]) {
            return nil;
        }
        [identifiers addObject:((PRAccountSnapshot *)account).identifier];
    }
    if (activeAccountIdentifier
        && (![activeAccountIdentifier isKindOfClass:NSString.class]
            || ![identifiers containsObject:activeAccountIdentifier])) {
        return nil;
    }
    if (diagnosticText && ![diagnosticText isKindOfClass:NSString.class]) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.accounts = [accounts copy];
        self.activeAccountIdentifier = [activeAccountIdentifier copy];
        self.outcome = outcome;
        self.localizationKey = [localizationKey copy];
        self.diagnosticText = [diagnosticText copy];
        self.retryable = retryable;
    }
    return self;
}

@end

@implementation PRAccountSelectionResult

- (instancetype)initWithAccount:(PRAccountSnapshot *)account
                          outcome:(PRAccountSelectionOutcome)outcome
                   localizationKey:(NSString *)localizationKey
                     diagnosticText:(NSString *)diagnosticText
{
    if (!isKnownAccountSelectionOutcome(outcome) || ![localizationKey isKindOfClass:NSString.class]
        || (outcome == PRAccountSelectionOutcomeSucceeded && account
            && (!account.canBeSelected || account.isBusy))
        || (outcome != PRAccountSelectionOutcomeSucceeded && !isNonEmptyString(localizationKey))) {
        return nil;
    }
    if (diagnosticText && ![diagnosticText isKindOfClass:NSString.class]) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.account = account;
        self.outcome = outcome;
        self.localizationKey = [localizationKey copy];
        self.diagnosticText = [diagnosticText copy];
    }
    return self;
}

@end

@implementation PRAccountAuthenticationProgress

- (instancetype)initWithAccountIdentifier:(NSString *)accountIdentifier
                                    action:(PRAccountAuthenticationAction)action
                                     phase:(PRAccountAuthenticationPhase)phase
                                   outcome:(PRAccountAuthenticationOutcome)outcome
                             providerLabel:(NSString *)providerLabel
                           verificationURL:(NSString *)verificationURL
                           localizationKey:(NSString *)localizationKey
                             diagnosticText:(NSString *)diagnosticText
                          expiresInSeconds:(NSInteger)expiresInSeconds
                                canCancel:(BOOL)canCancel
                                 retryable:(BOOL)retryable
                        requiresUserAction:(BOOL)requiresUserAction
{
    if (!isNonEmptyString(accountIdentifier) || !isKnownAccountAuthenticationAction(action)
        || !isKnownAccountAuthenticationPhase(phase) || !isKnownAccountAuthenticationOutcome(outcome)
        || !isNonEmptyString(providerLabel) || !isNonEmptyString(localizationKey) || expiresInSeconds < 0) {
        return nil;
    }
    if (verificationURL && ![verificationURL isKindOfClass:NSString.class]) {
        return nil;
    }
    if (diagnosticText && ![diagnosticText isKindOfClass:NSString.class]) {
        return nil;
    }

    const BOOL awaitingUser = phase == PRAccountAuthenticationPhaseAwaitingUser;
    if (awaitingUser) {
        if (outcome != PRAccountAuthenticationOutcomeInProgress || !requiresUserAction
            || !isNonEmptyString(verificationURL) || !canCancel) {
            return nil;
        }
    } else if (requiresUserAction || verificationURL.length > 0) {
        return nil;
    }

    switch (phase) {
        case PRAccountAuthenticationPhasePreparing:
        case PRAccountAuthenticationPhaseAuthenticating:
            if (outcome != PRAccountAuthenticationOutcomeInProgress) {
                return nil;
            }
            break;
        case PRAccountAuthenticationPhaseSucceeded:
            if (outcome != PRAccountAuthenticationOutcomeSucceeded || canCancel || retryable) {
                return nil;
            }
            break;
        case PRAccountAuthenticationPhaseFailed:
            if (outcome != PRAccountAuthenticationOutcomeFailed || canCancel) {
                return nil;
            }
            break;
        case PRAccountAuthenticationPhaseCancelled:
            if (outcome != PRAccountAuthenticationOutcomeCancelled || canCancel || retryable) {
                return nil;
            }
            break;
        case PRAccountAuthenticationPhaseAwaitingUser:
            break;
    }

    self = [super init];
    if (self) {
        self.accountIdentifier = [accountIdentifier copy];
        self.action = action;
        self.phase = phase;
        self.outcome = outcome;
        self.providerLabel = [providerLabel copy];
        self.verificationURL = [verificationURL copy];
        self.localizationKey = [localizationKey copy];
        self.diagnosticText = [diagnosticText copy];
        self.expiresInSeconds = expiresInSeconds;
        self.canCancel = canCancel;
        self.retryable = retryable;
        self.requiresUserAction = requiresUserAction;
        self.terminal = outcome != PRAccountAuthenticationOutcomeInProgress;
    }
    return self;
}

@end

@implementation PRAccountAuthenticationResult

- (instancetype)initWithAccount:(PRAccountSnapshot *)account
                          outcome:(PRAccountAuthenticationOutcome)outcome
                   localizationKey:(NSString *)localizationKey
                     diagnosticText:(NSString *)diagnosticText
                         retryable:(BOOL)retryable
{
    if (!isKnownAccountAuthenticationOutcome(outcome) || outcome == PRAccountAuthenticationOutcomeInProgress
        || !isNonEmptyString(localizationKey)) {
        return nil;
    }
    if (account && ![account isKindOfClass:PRAccountSnapshot.class]) {
        return nil;
    }
    if (account && account.identifier.length == 0) {
        return nil;
    }
    if (outcome == PRAccountAuthenticationOutcomeSucceeded
        && (!account || account.type != PRAccountTypeMicrosoft || account.state != PRAccountStateOnline
            || account.isBusy || !account.canBeSelected)) {
        return nil;
    }
    if (diagnosticText && ![diagnosticText isKindOfClass:NSString.class]) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.account = account;
        self.outcome = outcome;
        self.localizationKey = [localizationKey copy];
        self.diagnosticText = [diagnosticText copy];
        self.retryable = retryable;
    }
    return self;
}

@end

@implementation PROfflineLaunchIdentity

- (instancetype)initWithMode:(PROfflineLaunchIdentityMode)mode
            accountIdentifier:(NSString *)accountIdentifier
                          name:(NSString *)name
{
    if (!isKnownOfflineLaunchIdentityMode(mode) || (accountIdentifier && !isNonEmptyString(accountIdentifier))
        || !isNonEmptyString(name)) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.mode = mode;
        self.accountIdentifier = [accountIdentifier copy];
        self.name = [name copy];
    }
    return self;
}

@end

@implementation PROfflineLaunchIdentityLoadResult

- (instancetype)initWithIdentity:(PROfflineLaunchIdentity *)identity
                           outcome:(PROfflineLaunchIdentityLoadOutcome)outcome
                    localizationKey:(NSString *)localizationKey
                      diagnosticText:(NSString *)diagnosticText
                          retryable:(BOOL)retryable
{
    if (!isKnownOfflineLaunchIdentityLoadOutcome(outcome) || !isNonEmptyString(localizationKey)
        || (outcome == PROfflineLaunchIdentityLoadOutcomeSucceeded && !identity)
        || (outcome != PROfflineLaunchIdentityLoadOutcomeSucceeded && identity)) {
        return nil;
    }
    if (diagnosticText && ![diagnosticText isKindOfClass:NSString.class]) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.identity = identity;
        self.outcome = outcome;
        self.localizationKey = [localizationKey copy];
        self.diagnosticText = [diagnosticText copy];
        self.retryable = retryable;
    }
    return self;
}

@end

@implementation PROfflineLaunchIdentityUpdateResult

- (instancetype)initWithIdentity:(PROfflineLaunchIdentity *)identity
                           outcome:(PROfflineLaunchIdentityUpdateOutcome)outcome
                    localizationKey:(NSString *)localizationKey
                      diagnosticText:(NSString *)diagnosticText
                          retryable:(BOOL)retryable
{
    if (!isKnownOfflineLaunchIdentityUpdateOutcome(outcome) || !isNonEmptyString(localizationKey)
        || (outcome == PROfflineLaunchIdentityUpdateOutcomeSucceeded && !identity)
        || (outcome != PROfflineLaunchIdentityUpdateOutcomeSucceeded && identity)) {
        return nil;
    }
    if (diagnosticText && ![diagnosticText isKindOfClass:NSString.class]) {
        return nil;
    }

    self = [super init];
    if (self) {
        self.identity = identity;
        self.outcome = outcome;
        self.localizationKey = [localizationKey copy];
        self.diagnosticText = [diagnosticText copy];
        self.retryable = retryable;
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

- (instancetype)initWithApplicationIdentity:(PRApplicationIdentity *)identity
                          cancellationHandler:(PRBridgeLifecycleHandler)cancellationHandler
                             shutdownHandler:(PRBridgeLifecycleHandler)shutdownHandler
{
    if (!identity) {
        return nil;
    }

    return [self initWithDataRootURL:identity.applicationSupportDirectory
                   cancellationHandler:cancellationHandler
                      shutdownHandler:shutdownHandler];
}

- (instancetype)initWithDataRootURL:(NSURL *)dataRootURL
                  cancellationHandler:(PRBridgeLifecycleHandler)cancellationHandler
                     shutdownHandler:(PRBridgeLifecycleHandler)shutdownHandler
{
    NSURL *normalizedURL = normalizedDataRootURL(dataRootURL);
    if (!normalizedURL) {
        return nil;
    }

    try {
        return [self initWithDataRootURL:normalizedURL
                       cancellationHandler:cancellationHandler
                          shutdownHandler:shutdownHandler
                frontendRuntimeDependencies:defaultRuntimeDependencies(dataRootPathForURL(normalizedURL))];
    } catch (...) {
        return nil;
    }
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
        self.componentsRequestStates = [NSMutableArray array];
        self.resourcesRequestStates = [NSMutableArray array];
        self.resourceMutationRequestStates = [NSMutableArray array];
        self.worldsRequestStates = [NSMutableArray array];
        self.serversRequestStates = [NSMutableArray array];
        self.screenshotsRequestStates = [NSMutableArray array];
        self.logFilesRequestStates = [NSMutableArray array];
        self.instanceLogRequestStates = [NSMutableArray array];
        self.instanceDetailMutationRequestStates = [NSMutableArray array];
        self.taskRequestStates = [NSMutableArray array];
        self.taskLogRequestStates = [NSMutableArray array];
        self.taskCancellationRequestStates = [NSMutableArray array];
        self.commandRequestStates = [NSMutableArray array];
        self.notesUpdateRequestStates = [NSMutableArray array];
        self.settingsRequestStates = [NSMutableArray array];
        self.settingsUpdateRequestStates = [NSMutableArray array];
        self.javaDiscoveryRequestStates = [NSMutableArray array];
        self.javaSelectionRequestStates = [NSMutableArray array];
        self.accountSnapshotRequestStates = [NSMutableArray array];
        self.accountSelectionRequestStates = [NSMutableArray array];
        self.accountAuthenticationRequestStates = [NSMutableArray array];
        self.vanillaCreationRequestStates = [NSMutableArray array];
        self.instanceImportRequestStates = [NSMutableArray array];
        self.instanceCopyRequestStates = [NSMutableArray array];
        self.instanceExportRequestStates = [NSMutableArray array];
        self.providerBrowseRequestStates = [NSMutableArray array];
        self.providerVersionRequestStates = [NSMutableArray array];
        self.providerInstallRequestStates = [NSMutableArray array];
        self.offlineIdentityLoadRequestStates = [NSMutableArray array];
        self.offlineIdentityUpdateRequestStates = [NSMutableArray array];
        self.observationLock = [[NSLock alloc] init];
        _lifecycle = std::make_unique<NativeFacadeLifecycle>();
        _facade = std::move(facade);
        _backendQueue = dispatch_queue_create("com.lloydME.PrismNative.frontend", DISPATCH_QUEUE_SERIAL);

        __weak PRPrismBridge *weakBridge = self;
        try {
            _facade->startInstanceObservation([weakBridge](const FrontendInstanceChange& change) {
                PRPrismBridge *bridge = weakBridge;
                if (!bridge) {
                    return;
                }
                try {
                    [bridge publishInstanceChange:changeFromFacadeChange(change)];
                } catch (...) {
                }
            });
        } catch (...) {
        }
        try {
            _facade->startTaskObservation([weakBridge](const FrontendTaskSnapshot& snapshot) {
                PRPrismBridge *bridge = weakBridge;
                if (!bridge) {
                    return;
                }
                try {
                    [bridge publishTaskStatus:taskStatusFromFacadeSnapshot(snapshot)];
                } catch (...) {
                }
            });
        } catch (...) {
        }
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

- (PRBridgeObservationToken *)createMetadataOnlyInstanceWithIdentifier:(NSString *)identifier
                                                                     name:(NSString *)name
                                                                   iconKey:(NSString *)iconKey
                                                               completion:(PRMetadataInstanceCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeArrayResult *result = (PRBridgeArrayResult *)value;
        PRInstanceSummary *summary = result.values.firstObject;
        [weakRequest cancel];
        completion(summary, result.error);
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

        PRInstanceSummary *summary = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    FrontendMetadataInstanceRequest requestValue{
                        stableIdentifierFromFoundation(identifier),
                        utf8TextFromFoundation(name),
                        utf8TextFromFoundation(iconKey),
                    };
                    const auto result = bridge->_facade->createMetadataInstance(requestValue);
                    switch (result.outcome) {
                        case FrontendMetadataInstanceOutcome::Succeeded:
                            summary = result.instance.has_value() ? summaryFromFacadeSnapshot(*result.instance) : nil;
                            break;
                        case FrontendMetadataInstanceOutcome::InvalidInput:
                            error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                                       diagnosticText:foundationStringFromUTF8(result.diagnosticText)
                                                   substitutionValues:@{}];
                            break;
                        case FrontendMetadataInstanceOutcome::Failed:
                            error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                                       diagnosticText:foundationStringFromUTF8(result.diagnosticText)
                                                   substitutionValues:@{}];
                            break;
                    }
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid metadata instance request"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Facade operation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Metadata instance unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown metadata instance failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            NSArray *values = summary ? @[ summary ] : @[];
            [state deliverOnMainActor:[[PRBridgeArrayResult alloc] initWithValues:values error:error]];
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

- (PRBridgeObservationToken *)loadInstanceComponentsWithIdentifier:(NSString *)identifier
                                                           completion:(PRInstanceComponentsCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeComponentsResult *componentsResult = (PRBridgeComponentsResult *)value;
        [weakRequest cancel];
        completion(componentsResult.components, componentsResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeComponentsRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.componentsRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        NSArray<PRInstanceComponent *> *components = nil;
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
                    const std::optional<std::vector<FrontendInstanceComponentSnapshot>> snapshots =
                        bridge->_facade->instanceComponents(instanceIdentifier);
                    if (!snapshots.has_value()) {
                        error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                                   diagnosticText:@"Instance components are not available"
                                               substitutionValues:@{ @"instanceIdentifier": identifierCopy ?: @"" }];
                    } else {
                        components = componentsFromFacadeSnapshots(*snapshots);
                    }
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid instance components identifier"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Instance components operation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Instance components unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown instance components failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeComponentsResult alloc] initWithComponents:components error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)loadInstanceResourcesWithIdentifier:(NSString *)identifier
                                                               kind:(PRInstanceResourceKind)kind
                                                         completion:(PRInstanceResourcesCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeResourcesResult *resourcesResult = (PRBridgeResourcesResult *)value;
        [weakRequest cancel];
        completion(resourcesResult.resources, resourcesResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeResourcesRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.resourcesRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        NSArray<PRInstanceResource *> *resources = nil;
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
                    const FrontendInstanceResourceKind resourceKind = resourceKindFromFoundationKind(kind);
                    const std::optional<std::vector<FrontendInstanceResourceSnapshot>> snapshots =
                        bridge->_facade->instanceResources(instanceIdentifier, resourceKind);
                    if (!snapshots.has_value()) {
                        error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                                   diagnosticText:@"Instance resources are not available"
                                               substitutionValues:@{ @"instanceIdentifier": identifierCopy ?: @"" }];
                    } else {
                        resources = resourcesFromFacadeSnapshots(*snapshots);
                    }
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid instance resources request"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Instance resources operation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Instance resources unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown instance resources failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeResourcesResult alloc] initWithResources:resources error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)applyInstanceResourceActionWithIdentifier:(NSString *)identifier
                                                                    kind:(PRInstanceResourceKind)kind
                                                                  action:(PRInstanceResourceAction)action
                                                        resourceIdentifier:(NSString *)resourceIdentifier
                                                               sourceURL:(NSURL *)sourceURL
                                                               confirmed:(BOOL)confirmed
                                                               completion:(PRInstanceResourceMutationCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    NSString *resourceIdentifierCopy = [resourceIdentifier copy];
    NSURL *sourceURLCopy = [sourceURL copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeResourceMutationResult *mutationResult = (PRBridgeResourceMutationResult *)value;
        [weakRequest cancel];
        completion(mutationResult.result, mutationResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeResourceMutationRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.resourceMutationRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRInstanceResourceMutationResult *result = nil;
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
                    const std::string resourceIdentifier = stableIdentifierFromFoundation(resourceIdentifierCopy);
                    const FrontendInstanceResourceKind resourceKind = resourceKindFromFoundationKind(kind);
                    const FrontendInstanceResourceAction resourceAction = resourceActionFromFoundationAction(action);
                    FrontendInstanceResourceMutationRequest requestValue;
                    requestValue.action = resourceAction;
                    requestValue.resourceIdentifier = resourceIdentifier;
                    requestValue.confirmed = confirmed;
                    if (sourceURLCopy) {
                        requestValue.sourcePath = resourceSourcePathFromFoundation(sourceURLCopy);
                    }
                    result = resourceMutationResultFromFacadeResult(
                        bridge->_facade->mutateInstanceResource(instanceIdentifier, resourceKind, requestValue));
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid instance resource action"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Instance resource action cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Instance resource action unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown instance resource action failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeResourceMutationResult alloc] initWithResult:result error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)loadInstanceWorldsWithIdentifier:(NSString *)identifier
                                                     completion:(PRInstanceWorldsCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeInstanceWorldsResult *worldsResult = (PRBridgeInstanceWorldsResult *)value;
        [weakRequest cancel];
        completion(worldsResult.worlds, worldsResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeWorldsRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.worldsRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        NSArray<PRInstanceWorld *> *worlds = nil;
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
                    const std::optional<std::vector<FrontendInstanceWorldSnapshot>> snapshots =
                        bridge->_facade->instanceWorlds(instanceIdentifier);
                    if (!snapshots.has_value()) {
                        error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                                   diagnosticText:@"Instance worlds are not available"
                                               substitutionValues:@{ @"instanceIdentifier": identifierCopy ?: @"" }];
                    } else {
                        worlds = worldsFromFacadeSnapshots(*snapshots);
                    }
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid instance worlds request"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Instance worlds operation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Instance worlds unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown instance worlds failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeInstanceWorldsResult alloc] initWithWorlds:worlds error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)loadInstanceServersWithIdentifier:(NSString *)identifier
                                                      completion:(PRInstanceServersCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeInstanceServersResult *serversResult = (PRBridgeInstanceServersResult *)value;
        [weakRequest cancel];
        completion(serversResult.servers, serversResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeServersRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.serversRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        NSArray<PRInstanceServer *> *servers = nil;
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
                    const std::optional<std::vector<FrontendInstanceServerSnapshot>> snapshots =
                        bridge->_facade->instanceServers(instanceIdentifier);
                    if (!snapshots.has_value()) {
                        error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                                   diagnosticText:@"Instance servers are not available"
                                               substitutionValues:@{ @"instanceIdentifier": identifierCopy ?: @"" }];
                    } else {
                        servers = serversFromFacadeSnapshots(*snapshots);
                    }
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid instance servers request"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Instance servers operation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Instance servers unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown instance servers failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeInstanceServersResult alloc] initWithServers:servers error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)loadInstanceScreenshotsWithIdentifier:(NSString *)identifier
                                                            completion:(PRInstanceScreenshotsCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeInstanceScreenshotsResult *screenshotsResult = (PRBridgeInstanceScreenshotsResult *)value;
        [weakRequest cancel];
        completion(screenshotsResult.screenshots, screenshotsResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeScreenshotsRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.screenshotsRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        NSArray<PRInstanceScreenshot *> *screenshots = nil;
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
                    const std::optional<std::vector<FrontendInstanceScreenshotSnapshot>> snapshots =
                        bridge->_facade->instanceScreenshots(instanceIdentifier);
                    if (!snapshots.has_value()) {
                        error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                                   diagnosticText:@"Instance screenshots are not available"
                                               substitutionValues:@{ @"instanceIdentifier": identifierCopy ?: @"" }];
                    } else {
                        screenshots = screenshotsFromFacadeSnapshots(*snapshots);
                    }
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid instance screenshots request"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Instance screenshots operation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Instance screenshots unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown instance screenshots failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeInstanceScreenshotsResult alloc]
                initWithScreenshots:screenshots error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)loadInstanceLogFilesWithIdentifier:(NSString *)identifier
                                                         completion:(PRInstanceLogFilesCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeInstanceLogFilesResult *logFilesResult = (PRBridgeInstanceLogFilesResult *)value;
        [weakRequest cancel];
        completion(logFilesResult.logFiles, logFilesResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeLogFilesRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.logFilesRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        NSArray<PRInstanceLogFile *> *logFiles = nil;
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
                    const std::optional<std::vector<FrontendInstanceLogFileSnapshot>> snapshots =
                        bridge->_facade->instanceLogFiles(instanceIdentifier);
                    if (!snapshots.has_value()) {
                        error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                                   diagnosticText:@"Instance log files are not available"
                                               substitutionValues:@{ @"instanceIdentifier": identifierCopy ?: @"" }];
                    } else {
                        logFiles = logFilesFromFacadeSnapshots(*snapshots);
                    }
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid instance log files request"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Instance log files operation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Instance log files unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown instance log files failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeInstanceLogFilesResult alloc]
                initWithLogFiles:logFiles error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)loadInstanceLogWithIdentifier:(NSString *)identifier
                                               logIdentifier:(NSString *)logIdentifier
                                                   completion:(PRInstanceLogCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    NSString *logIdentifierCopy = [logIdentifier copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeInstanceLogResult *logResult = (PRBridgeInstanceLogResult *)value;
        [weakRequest cancel];
        completion(logResult.snapshot, logResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeInstanceLogRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.instanceLogRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRInstanceLogSnapshot *snapshot = nil;
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
                    const std::string logIdentifier = stableIdentifierFromFoundation(logIdentifierCopy);
                    const std::optional<FrontendInstanceLogSnapshot> facadeSnapshot =
                        bridge->_facade->instanceLog(instanceIdentifier, logIdentifier);
                    if (!facadeSnapshot.has_value()) {
                        error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                                   diagnosticText:@"Instance log is not available"
                                               substitutionValues:@{ @"instanceIdentifier": identifierCopy ?: @"",
                                                                      @"logIdentifier": logIdentifierCopy ?: @"" }];
                    } else {
                        snapshot = instanceLogSnapshotFromFacadeSnapshot(*facadeSnapshot);
                    }
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid instance log request"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Instance log operation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Instance log unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown instance log failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeInstanceLogResult alloc]
                initWithSnapshot:snapshot error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)applyInstanceDetailActionWithIdentifier:(NSString *)identifier
                                                                request:(PRInstanceDetailMutationRequest *)detailRequest
                                                            completion:(PRInstanceDetailMutationCompletionHandler)completion
{
    if (!completion || !detailRequest || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    PRInstanceDetailKind kind = detailRequest.kind;
    PRInstanceDetailAction action = detailRequest.action;
    NSString *itemIdentifierCopy = [detailRequest.itemIdentifier copy];
    NSURL *sourceURLCopy = [detailRequest.sourceURL copy];
    NSString *targetNameCopy = [detailRequest.targetName copy];
    NSString *nameCopy = [detailRequest.name copy];
    NSString *addressCopy = [detailRequest.address copy];
    PRInstanceServerResourcePolicy resourcePolicy = detailRequest.resourcePolicy;
    BOOL confirmed = detailRequest.confirmed;
    NSInteger position = detailRequest.position;

    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeInstanceDetailMutationResult *mutationResult = (PRBridgeInstanceDetailMutationResult *)value;
        [weakRequest cancel];
        completion(mutationResult.result, mutationResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeInstanceDetailMutationRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.instanceDetailMutationRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRInstanceDetailMutationResult *result = nil;
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
                    FrontendInstanceDetailMutationRequest requestValue;
                    requestValue.kind = detailKindFromFoundationKind(kind);
                    requestValue.action = detailActionFromFoundationAction(action);
                    requestValue.itemIdentifier = utf8TextFromFoundation(itemIdentifierCopy);
                    requestValue.targetName = utf8TextFromFoundation(targetNameCopy);
                    requestValue.name = utf8TextFromFoundation(nameCopy);
                    requestValue.address = utf8TextFromFoundation(addressCopy);
                    requestValue.resourcePolicy = serverResourcePolicyFromFoundationPolicy(resourcePolicy);
                    requestValue.confirmed = confirmed;
                    requestValue.position = static_cast<int>(position);
                    if (sourceURLCopy) {
                        requestValue.sourcePath = resourceSourcePathFromFoundation(sourceURLCopy);
                    }
                    result = detailMutationResultFromFacadeResult(
                        bridge->_facade->mutateInstanceDetail(instanceIdentifier, requestValue));
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid instance detail action"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Instance detail action cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Instance detail action unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown instance detail action failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeInstanceDetailMutationResult alloc]
                initWithResult:result error:error]];
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

- (PRBridgeObservationToken *)loadGlobalSettingsWithCompletion:(PRGlobalSettingsCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeGlobalSettingsResult *settingsResult = (PRBridgeGlobalSettingsResult *)value;
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

        PRGlobalSettings *settings = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    const std::optional<FrontendGlobalSettingsSnapshot> snapshot = bridge->_facade->globalSettings();
                    if (!snapshot.has_value()) {
                        error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                                   diagnosticText:@"Global settings are not available"
                                               substitutionValues:@{}];
                    } else {
                        settings = globalSettingsFromFacadeSnapshot(*snapshot);
                    }
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid global settings"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Global settings operation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Global settings unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown global settings failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeGlobalSettingsResult alloc] initWithSettings:settings error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)updateGlobalSettings:(PRGlobalSettings *)settings
                                          completion:(PRGlobalSettingsUpdateCompletionHandler)completion
{
    if (!completion || !settings || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    PRGlobalSettings *settingsCopy = settings;
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeGlobalSettingsUpdateResult *settingsResult = (PRBridgeGlobalSettingsUpdateResult *)value;
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

        PRGlobalSettingsUpdateResult *result = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    const FrontendGlobalSettingsSnapshot requestedSettings = globalSettingsFromFoundationObject(settingsCopy);
                    const FrontendGlobalSettingsUpdateResult updateResult =
                        bridge->_facade->updateGlobalSettings(requestedSettings);
                    PRGlobalSettings *confirmedSettings = nil;
                    if (updateResult.settings.has_value()) {
                        confirmedSettings = globalSettingsFromFacadeSnapshot(*updateResult.settings);
                    }
                    result = [[PRGlobalSettingsUpdateResult alloc]
                        initWithSettings:confirmedSettings
                                 outcome:globalSettingsUpdateOutcomeFromFacadeResult(updateResult.outcome)];
                    if (!result) {
                        throw std::invalid_argument("Facade returned an invalid global settings update result");
                    }
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid global settings"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Global settings update cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Global settings update unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown global settings update failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeGlobalSettingsUpdateResult alloc]
                initWithResult:result
                          error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)loadJavaInstallationsWithCompletion:(PRJavaDiscoveryCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeJavaDiscoveryResult *javaResult = (PRBridgeJavaDiscoveryResult *)value;
        [weakRequest cancel];
        completion(javaResult.result, javaResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeJavaDiscoveryRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.javaDiscoveryRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRJavaDiscoveryResult *result = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    result = javaDiscoveryResultFromFacadeResult(bridge->_facade->javaInstallations());
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid Java discovery result"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Java discovery cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Java discovery unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown Java discovery failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeJavaDiscoveryResult alloc] initWithResult:result error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)selectJavaInstallationWithIdentifier:(NSString *)identifier
                                                            completion:(PRJavaSelectionCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeJavaSelectionResult *javaResult = (PRBridgeJavaSelectionResult *)value;
        [weakRequest cancel];
        completion(javaResult.result, javaResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeJavaSelectionRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.javaSelectionRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRJavaSelectionResult *result = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    const std::string installationIdentifier = stableIdentifierFromFoundation(identifierCopy);
                    result = javaSelectionResultFromFacadeResult(
                        bridge->_facade->selectJavaInstallation(installationIdentifier));
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid Java selection"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Java selection cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Java selection unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown Java selection failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeJavaSelectionResult alloc] initWithResult:result error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)loadAccountSnapshotsWithCompletion:(PRAccountSnapshotCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeAccountSnapshotResult *accountResult = (PRBridgeAccountSnapshotResult *)value;
        [weakRequest cancel];
        completion(accountResult.result, accountResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeAccountSnapshotRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.accountSnapshotRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRAccountSnapshotResult *result = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    result = accountSnapshotResultFromFacadeResult(bridge->_facade->accountSnapshots());
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid account snapshot result"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Account snapshot load cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Account snapshots unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown account snapshot failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeAccountSnapshotResult alloc] initWithResult:result error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)selectActiveAccountWithIdentifier:(NSString *)identifier
                                                         completion:(PRAccountSelectionCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeAccountSelectionResult *accountResult = (PRBridgeAccountSelectionResult *)value;
        [weakRequest cancel];
        completion(accountResult.result, accountResult.error);
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeAccountSelectionRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.accountSelectionRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRAccountSelectionResult *result = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    std::optional<std::string> accountIdentifier;
                    if (identifierCopy) {
                        accountIdentifier = stableIdentifierFromFoundation(identifierCopy);
                    }
                    result = accountSelectionResultFromFacadeResult(
                        bridge->_facade->selectActiveAccount(accountIdentifier));
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid account selection"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Account selection cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Account selection unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown account selection failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeAccountSelectionResult alloc] initWithResult:result error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)authenticateAccountWithIdentifier:(NSString *)identifier
                                                           action:(PRAccountAuthenticationAction)action
                                                         progress:(PRAccountAuthenticationProgressHandler)progress
                                                       completion:(PRAccountAuthenticationCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }
    if (!isKnownAccountAuthenticationAction(action)) {
        return nil;
    }

    NSString *identifierCopy = [identifier copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeAccountAuthenticationDelivery *delivery = (PRBridgeAccountAuthenticationDelivery *)value;
        if (delivery.progress && progress) {
            progress(delivery.progress);
        }
        if (delivery.result || delivery.error) {
            [weakRequest cancel];
            completion(delivery.result, delivery.error);
        }
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeAccountAuthenticationRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.accountAuthenticationRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRAccountAuthenticationResult *result = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    FrontendAccountAuthenticationRequest authenticationRequest;
                    authenticationRequest.accountIdentifier = stableIdentifierFromFoundation(identifierCopy);
                    switch (action) {
                        case PRAccountAuthenticationActionLogin:
                            authenticationRequest.action = FrontendAccountAuthenticationAction::Login;
                            break;
                        case PRAccountAuthenticationActionRefresh:
                            authenticationRequest.action = FrontendAccountAuthenticationAction::Refresh;
                            break;
                    }

                    const FrontendAccountAuthenticationResult authenticationResult =
                        bridge->_facade->authenticateAccount(
                            authenticationRequest,
                            [&](const FrontendAccountAuthenticationProgress& authenticationProgress) {
                                if (state.isCancelled) {
                                    return;
                                }
                                PRAccountAuthenticationProgress *convertedProgress =
                                    accountAuthenticationProgressFromFacadeProgress(authenticationProgress);
                                [state deliverOnMainActor:[[PRBridgeAccountAuthenticationDelivery alloc]
                                    initWithProgress:convertedProgress
                                               result:nil
                                                error:nil]];
                            });
                    result = accountAuthenticationResultFromFacadeResult(authenticationResult);
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid account authentication"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Account authentication cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Account authentication unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown account authentication failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeAccountAuthenticationDelivery alloc]
                initWithProgress:nil
                           result:result
                            error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)createVanillaInstanceWithRequest:(PRVanillaCreationRequest *)request
                                                       progress:(PRVanillaCreationProgressHandler)progress
                                                     completion:(PRVanillaCreationCompletionHandler)completion
{
    if (!request || !completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    PRVanillaCreationRequest *requestCopy = request;
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *observation = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeVanillaCreationDelivery *delivery = (PRBridgeVanillaCreationDelivery *)value;
        if (delivery.progress && progress) {
            progress(delivery.progress);
        }
        if (delivery.result || delivery.error) {
            [weakRequest cancel];
            completion(delivery.result, delivery.error);
        }
    }];
    weakRequest = observation;
    observation.removalHandler = ^{
        [weakBridge removeVanillaCreationRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [observation cancel];
        return nil;
    }
    [self.vanillaCreationRequestStates addObject:observation];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRVanillaCreationResult *result = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    FrontendVanillaCreationRequest creationRequest;
                    creationRequest.versionDescriptor = utf8TextFromFoundation(requestCopy.versionDescriptor);
                    creationRequest.versionName = utf8TextFromFoundation(requestCopy.versionName);
                    if (requestCopy.loaderIdentifier) {
                        creationRequest.loaderIdentifier = stableIdentifierFromFoundation(requestCopy.loaderIdentifier);
                        creationRequest.loaderVersionDescriptor =
                            utf8TextFromFoundation(requestCopy.loaderVersionDescriptor);
                    }
                    creationRequest.name = utf8TextFromFoundation(requestCopy.name);
                    creationRequest.groupId = requestCopy.groupID ? utf8TextFromFoundation(requestCopy.groupID) : "";
                    creationRequest.iconKey = stableIdentifierFromFoundation(requestCopy.iconKey);
                    const FrontendVanillaCreationResult creationResult = bridge->_facade->createVanillaInstance(
                        creationRequest,
                        [&](const FrontendTaskSnapshot& snapshot) {
                            if (state.isCancelled) {
                                return;
                            }
                            PRTaskStatus *convertedStatus = taskStatusFromFacadeSnapshot(snapshot);
                            [state deliverOnMainActor:[[PRBridgeVanillaCreationDelivery alloc]
                                initWithProgress:convertedStatus
                                           result:nil
                                            error:nil]];
                        },
                        [&] { return state.isCancelled; });
                    result = vanillaCreationResultFromFacadeResult(creationResult);
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid vanilla creation request"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Vanilla creation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Vanilla creation unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown vanilla creation failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeVanillaCreationDelivery alloc]
                initWithProgress:nil
                           result:result
                            error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:observation];
}

- (PRBridgeObservationToken *)importInstanceWithRequest:(PRInstanceImportRequest *)request
                                                progress:(PRInstanceImportProgressHandler)progress
                                              completion:(PRInstanceImportCompletionHandler)completion
{
    if (!request || !completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    PRInstanceImportRequest *requestCopy = request;
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *observation = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeInstanceImportDelivery *delivery = (PRBridgeInstanceImportDelivery *)value;
        if (delivery.progress && progress) {
            progress(delivery.progress);
        }
        if (delivery.result || delivery.error) {
            [weakRequest cancel];
            completion(delivery.result, delivery.error);
        }
    }];
    weakRequest = observation;
    observation.removalHandler = ^{
        [weakBridge removeInstanceImportRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [observation cancel];
        return nil;
    }
    [self.instanceImportRequestStates addObject:observation];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRInstanceImportResult *result = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    FrontendInstanceImportRequest importRequest;
                    switch (requestCopy.sourceKind) {
                        case PRInstanceImportSourceKindLocalFile: {
                            importRequest.sourceKind = FrontendInstanceImportSourceKind::LocalFile;
                            const char *fileSystemRepresentation = requestCopy.sourceURL.fileSystemRepresentation;
                            if (fileSystemRepresentation == nullptr || fileSystemRepresentation[0] == '\0') {
                                throw std::invalid_argument("Local instance imports require a filesystem representation");
                            }
                            importRequest.source = std::filesystem::path(fileSystemRepresentation).lexically_normal().string();
                            break;
                        }
                        case PRInstanceImportSourceKindRemoteURL:
                            importRequest.sourceKind = FrontendInstanceImportSourceKind::RemoteURL;
                            importRequest.source = utf8TextFromFoundation(requestCopy.sourceURL.absoluteString);
                            break;
                        default:
                            throw std::invalid_argument("Unknown instance import source kind");
                    }
                    importRequest.name = utf8TextFromFoundation(requestCopy.name);
                    importRequest.groupId = requestCopy.groupID ? utf8TextFromFoundation(requestCopy.groupID) : "";
                    importRequest.iconKey = utf8TextFromFoundation(requestCopy.iconKey);
                    const FrontendInstanceImportResult importResult = bridge->_facade->importInstance(
                        importRequest,
                        [&](const FrontendTaskSnapshot& snapshot) {
                            if (state.isCancelled) {
                                return;
                            }
                            PRTaskStatus *convertedStatus = taskStatusFromFacadeSnapshot(snapshot);
                            [state deliverOnMainActor:[[PRBridgeInstanceImportDelivery alloc]
                                initWithProgress:convertedStatus
                                           result:nil
                                            error:nil]];
                        },
                        [&] { return state.isCancelled; });
                    result = instanceImportResultFromFacadeResult(importResult);
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid instance import request"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Instance import cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Instance import unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown instance import failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeInstanceImportDelivery alloc]
                initWithProgress:nil
                           result:result
                            error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:observation];
}

- (PRBridgeObservationToken *)copyInstanceWithRequest:(PRInstanceCopyRequest *)request
                                              progress:(PRInstanceCopyProgressHandler)progress
                                            completion:(PRInstanceCopyCompletionHandler)completion
{
    if (!request || !completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    PRInstanceCopyRequest *requestCopy = request;
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *observation = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeInstanceCopyDelivery *delivery = (PRBridgeInstanceCopyDelivery *)value;
        if (delivery.progress && progress) {
            progress(delivery.progress);
        }
        if (delivery.result || delivery.error) {
            [weakRequest cancel];
            completion(delivery.result, delivery.error);
        }
    }];
    weakRequest = observation;
    observation.removalHandler = ^{
        [weakBridge removeInstanceCopyRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [observation cancel];
        return nil;
    }
    [self.instanceCopyRequestStates addObject:observation];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRInstanceCopyResult *result = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    FrontendInstanceCopyRequest copyRequest;
                    copyRequest.sourceInstanceIdentifier = stableIdentifierFromFoundation(
                        requestCopy.sourceInstanceIdentifier);
                    copyRequest.name = utf8TextFromFoundation(requestCopy.name);
                    copyRequest.groupId = requestCopy.groupID ? utf8TextFromFoundation(requestCopy.groupID) : "";
                    copyRequest.iconKey = stableIdentifierFromFoundation(requestCopy.iconKey);
                    copyRequest.options.copySaves = requestCopy.copySaves;
                    copyRequest.options.keepPlaytime = requestCopy.keepPlaytime;
                    copyRequest.options.copyGameOptions = requestCopy.copyGameOptions;
                    copyRequest.options.copyResourcePacks = requestCopy.copyResourcePacks;
                    copyRequest.options.copyShaderPacks = requestCopy.copyShaderPacks;
                    copyRequest.options.copyServers = requestCopy.copyServers;
                    copyRequest.options.copyMods = requestCopy.copyMods;
                    copyRequest.options.copyScreenshots = requestCopy.copyScreenshots;
                    copyRequest.options.useSymbolicLinks = requestCopy.useSymbolicLinks;
                    copyRequest.options.linkRecursively = requestCopy.linkRecursively;
                    copyRequest.options.useHardLinks = requestCopy.useHardLinks;
                    copyRequest.options.dontLinkSaves = requestCopy.dontLinkSaves;
                    copyRequest.options.useClone = requestCopy.useClone;
                    const FrontendInstanceCopyResult copyResult = bridge->_facade->copyInstance(
                        copyRequest,
                        [&](const FrontendTaskSnapshot& snapshot) {
                            if (state.isCancelled) {
                                return;
                            }
                            PRTaskStatus *convertedStatus = taskStatusFromFacadeSnapshot(snapshot);
                            [state deliverOnMainActor:[[PRBridgeInstanceCopyDelivery alloc]
                                initWithProgress:convertedStatus
                                           result:nil
                                            error:nil]];
                        },
                        [&] { return state.isCancelled; });
                    result = instanceCopyResultFromFacadeResult(copyResult);
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid instance copy request"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Instance copy cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Instance copy unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown instance copy failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeInstanceCopyDelivery alloc]
                initWithProgress:nil
                           result:result
                            error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:observation];
}

- (PRBridgeObservationToken *)exportInstanceWithRequest:(PRInstanceExportRequest *)request
                                                progress:(PRInstanceExportProgressHandler)progress
                                              completion:(PRInstanceExportCompletionHandler)completion
{
    if (!request || !completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    PRInstanceExportRequest *requestCopy = request;
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *observation = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeInstanceExportDelivery *delivery = (PRBridgeInstanceExportDelivery *)value;
        if (delivery.progress && progress) {
            progress(delivery.progress);
        }
        if (delivery.result || delivery.error) {
            [weakRequest cancel];
            completion(delivery.result, delivery.error);
        }
    }];
    weakRequest = observation;
    observation.removalHandler = ^{
        [weakBridge removeInstanceExportRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [observation cancel];
        return nil;
    }
    [self.instanceExportRequestStates addObject:observation];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRInstanceExportResult *result = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    FrontendInstanceExportRequest exportRequest;
                    switch (requestCopy.kind) {
                        case PRInstanceExportKindZipArchive:
                            exportRequest.kind = FrontendInstanceExportKind::ZipArchive;
                            break;
                        case PRInstanceExportKindModList:
                            exportRequest.kind = FrontendInstanceExportKind::ModList;
                            break;
                        default:
                            throw std::invalid_argument("Unknown instance export kind");
                    }
                    switch (requestCopy.modListFormat) {
                        case PRModListExportFormatHTML:
                            exportRequest.modListFormat = FrontendModListExportFormat::HTML;
                            break;
                        case PRModListExportFormatMarkdown:
                            exportRequest.modListFormat = FrontendModListExportFormat::Markdown;
                            break;
                        case PRModListExportFormatPlainText:
                            exportRequest.modListFormat = FrontendModListExportFormat::PlainText;
                            break;
                        case PRModListExportFormatJSON:
                            exportRequest.modListFormat = FrontendModListExportFormat::JSON;
                            break;
                        case PRModListExportFormatCSV:
                            exportRequest.modListFormat = FrontendModListExportFormat::CSV;
                            break;
                        case PRModListExportFormatCustom:
                            exportRequest.modListFormat = FrontendModListExportFormat::Custom;
                            break;
                        default:
                            throw std::invalid_argument("Unknown mod-list export format");
                    }
                    exportRequest.sourceInstanceIdentifier = stableIdentifierFromFoundation(
                        requestCopy.sourceInstanceIdentifier);
                    exportRequest.destinationPath = exportDestinationPathFromFoundation(requestCopy.destinationURL);
                    if (requestCopy.includeAuthors) {
                        exportRequest.modListFieldMask |= kFrontendModListFieldAuthors;
                    }
                    if (requestCopy.includeVersion) {
                        exportRequest.modListFieldMask |= kFrontendModListFieldVersion;
                    }
                    if (requestCopy.includeURL) {
                        exportRequest.modListFieldMask |= kFrontendModListFieldURL;
                    }
                    if (requestCopy.includeFilename) {
                        exportRequest.modListFieldMask |= kFrontendModListFieldFilename;
                    }
                    exportRequest.customTemplate = utf8TextFromFoundation(requestCopy.customTemplate);
                    const FrontendInstanceExportResult exportResult = bridge->_facade->exportInstance(
                        exportRequest,
                        [&](const FrontendTaskSnapshot& snapshot) {
                            if (state.isCancelled) {
                                return;
                            }
                            PRTaskStatus *convertedStatus = taskStatusFromFacadeSnapshot(snapshot);
                            [state deliverOnMainActor:[[PRBridgeInstanceExportDelivery alloc]
                                initWithProgress:convertedStatus
                                           result:nil
                                            error:nil]];
                        },
                        [&] { return state.isCancelled; });
                    result = instanceExportResultFromFacadeResult(exportResult);
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid instance export request"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Instance export cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Instance export unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown instance export failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeInstanceExportDelivery alloc]
                initWithProgress:nil
                           result:result
                            error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:observation];
}

- (PRBridgeObservationToken *)browseProviderWithRequest:(PRProviderBrowseRequest *)request
                                                progress:(PRProviderBrowseProgressHandler)progress
                                              completion:(PRProviderBrowseCompletionHandler)completion
{
    if (!request || !completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    PRProviderBrowseRequest *requestCopy = request;
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *observation = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeProviderBrowseDelivery *delivery = (PRBridgeProviderBrowseDelivery *)value;
        if (delivery.progress && progress) {
            progress(delivery.progress);
        }
        if (delivery.result || delivery.error) {
            [weakRequest cancel];
            completion(delivery.result, delivery.error);
        }
    }];
    weakRequest = observation;
    observation.removalHandler = ^{
        [weakBridge removeProviderBrowseRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [observation cancel];
        return nil;
    }
    [self.providerBrowseRequestStates addObject:observation];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRProviderBrowseResult *result = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    FrontendProviderBrowseRequest browseRequest;
                    browseRequest.provider = providerKindFromFoundation(requestCopy.provider);
                    browseRequest.query = utf8TextFromFoundation(requestCopy.query);
                    if (requestCopy.offset < 0 || requestCopy.pageSize <= 0) {
                        throw std::invalid_argument("Provider browse pagination must be non-negative");
                    }
                    browseRequest.offset = static_cast<std::size_t>(requestCopy.offset);
                    browseRequest.pageSize = static_cast<std::size_t>(requestCopy.pageSize);
                    browseRequest.sort = providerSortFromFoundation(requestCopy.sort);
                    browseRequest.gameVersions = utf8StringsFromFoundation(
                        requestCopy.gameVersions, "Invalid provider game-version filters");
                    browseRequest.loaders = utf8StringsFromFoundation(
                        requestCopy.loaders, "Invalid provider loader filters");
                    browseRequest.categories = utf8StringsFromFoundation(
                        requestCopy.categories, "Invalid provider category filters");
                    for (NSNumber *releaseType in requestCopy.releaseTypes) {
                        if (![releaseType isKindOfClass:NSNumber.class]) {
                            throw std::invalid_argument("Invalid provider release filters");
                        }
                        browseRequest.releaseTypes.push_back(
                            providerReleaseTypeFromFoundation((PRProviderReleaseType)releaseType.integerValue));
                    }
                    browseRequest.side = providerSideFromFoundation(requestCopy.side);
                    browseRequest.openSource = requestCopy.openSource;
                    browseRequest.hideInstalled = requestCopy.hideInstalled;
                    const FrontendProviderBrowseResult browseResult = bridge->_facade->browseProvider(
                        browseRequest,
                        [&](const FrontendTaskSnapshot& snapshot) {
                            if (state.isCancelled) {
                                return;
                            }
                            PRTaskStatus *convertedStatus = taskStatusFromFacadeSnapshot(snapshot);
                            [state deliverOnMainActor:[[PRBridgeProviderBrowseDelivery alloc]
                                initWithProgress:convertedStatus
                                           result:nil
                                            error:nil]];
                        },
                        [&] { return state.isCancelled; });
                    result = providerBrowseResultFromFacadeResult(browseResult);
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid provider browse request"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Provider browse cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Provider browse unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown provider browse failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeProviderBrowseDelivery alloc]
                initWithProgress:nil
                           result:result
                            error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:observation];
}

- (PRBridgeObservationToken *)loadProviderVersionsWithRequest:(PRProviderVersionRequest *)request
                                                       progress:(PRProviderVersionProgressHandler)progress
                                                     completion:(PRProviderVersionCompletionHandler)completion
{
    if (!request || !completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    PRProviderVersionRequest *requestCopy = request;
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *observation = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeProviderVersionDelivery *delivery = (PRBridgeProviderVersionDelivery *)value;
        if (delivery.progress && progress) {
            progress(delivery.progress);
        }
        if (delivery.result || delivery.error) {
            [weakRequest cancel];
            completion(delivery.result, delivery.error);
        }
    }];
    weakRequest = observation;
    observation.removalHandler = ^{
        [weakBridge removeProviderVersionRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [observation cancel];
        return nil;
    }
    [self.providerVersionRequestStates addObject:observation];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRProviderVersionResult *result = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    FrontendProviderVersionRequest versionRequest;
                    versionRequest.provider = providerKindFromFoundation(requestCopy.provider);
                    versionRequest.packIdentifier = stableIdentifierFromFoundation(requestCopy.packIdentifier);
                    versionRequest.gameVersions = utf8StringsFromFoundation(
                        requestCopy.gameVersions, "Invalid provider version game filters");
                    versionRequest.loaders = utf8StringsFromFoundation(
                        requestCopy.loaders, "Invalid provider version loader filters");
                    const FrontendProviderVersionResult versionResult = bridge->_facade->providerVersions(
                        versionRequest,
                        [&](const FrontendTaskSnapshot& snapshot) {
                            if (state.isCancelled) {
                                return;
                            }
                            PRTaskStatus *convertedStatus = taskStatusFromFacadeSnapshot(snapshot);
                            [state deliverOnMainActor:[[PRBridgeProviderVersionDelivery alloc]
                                initWithProgress:convertedStatus
                                           result:nil
                                            error:nil]];
                        },
                        [&] { return state.isCancelled; });
                    result = providerVersionResultFromFacadeResult(versionResult);
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid provider version request"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Provider version loading cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Provider version loading unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown provider version failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeProviderVersionDelivery alloc]
                initWithProgress:nil
                           result:result
                            error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:observation];
}

- (PRBridgeObservationToken *)installProviderPackWithRequest:(PRProviderInstallRequest *)request
                                                       progress:(PRProviderInstallProgressHandler)progress
                                                     completion:(PRProviderInstallCompletionHandler)completion
{
    if (!request || !completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }

    PRProviderInstallRequest *requestCopy = request;
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *observation = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeProviderInstallDelivery *delivery = (PRBridgeProviderInstallDelivery *)value;
        if (delivery.progress && progress) {
            progress(delivery.progress);
        }
        if (delivery.result || delivery.error) {
            [weakRequest cancel];
            completion(delivery.result, delivery.error);
        }
    }];
    weakRequest = observation;
    observation.removalHandler = ^{
        [weakBridge removeProviderInstallRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [observation cancel];
        return nil;
    }
    [self.providerInstallRequestStates addObject:observation];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PRProviderInstallResult *result = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    FrontendProviderInstallRequest installRequest;
                    installRequest.kind = providerInstallKindFromFoundation(requestCopy.kind);
                    installRequest.packIdentifier = stableIdentifierFromFoundation(requestCopy.packIdentifier);
                    installRequest.versionIdentifier = stableIdentifierFromFoundation(requestCopy.versionIdentifier);
                    if (requestCopy.sourceURL) {
                        installRequest.sourcePath = resourceSourcePathFromFoundation(requestCopy.sourceURL);
                    }
                    installRequest.name = utf8TextFromFoundation(requestCopy.name);
                    installRequest.groupId = requestCopy.groupID ? utf8TextFromFoundation(requestCopy.groupID) : "";
                    installRequest.iconKey = stableIdentifierFromFoundation(requestCopy.iconKey);
                    if (requestCopy.recoveryDecision) {
                        installRequest.recoveryDecision = recoveryDecisionFromFoundation(requestCopy.recoveryDecision);
                    }
                    const FrontendProviderInstallResult installResult = bridge->_facade->installProviderPack(
                        installRequest,
                        [&](const FrontendTaskSnapshot& snapshot) {
                            if (state.isCancelled) {
                                return;
                            }
                            PRTaskStatus *convertedStatus = taskStatusFromFacadeSnapshot(snapshot);
                            [state deliverOnMainActor:[[PRBridgeProviderInstallDelivery alloc]
                                initWithProgress:convertedStatus
                                           result:nil
                                            error:nil]];
                        },
                        [&] { return state.isCancelled; });
                    result = providerInstallResultFromFacadeResult(installResult);
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid provider installation request"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Provider installation cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Provider installation unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown provider installation failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeProviderInstallDelivery alloc]
                initWithProgress:nil
                           result:result
                            error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:observation];
}

- (PRBridgeObservationToken *)loadOfflineLaunchIdentityWithMode:(PROfflineLaunchIdentityMode)mode
                                                accountIdentifier:(NSString *)accountIdentifier
                                                     fallbackName:(NSString *)fallbackName
                                                      completion:(PROfflineLaunchIdentityLoadCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }
    if (!isKnownOfflineLaunchIdentityMode(mode)) {
        return nil;
    }

    NSString *accountIdentifierCopy = [accountIdentifier copy];
    NSString *fallbackNameCopy = [fallbackName copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeOfflineLaunchIdentityLoadDelivery *delivery = (PRBridgeOfflineLaunchIdentityLoadDelivery *)value;
        if (delivery.result || delivery.error) {
            [weakRequest cancel];
            completion(delivery.result, delivery.error);
        }
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeOfflineIdentityLoadRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.offlineIdentityLoadRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PROfflineLaunchIdentityLoadResult *result = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    FrontendOfflineLaunchIdentityRequest identityRequest;
                    switch (mode) {
                        case PROfflineLaunchIdentityModeOffline:
                            identityRequest.mode = FrontendOfflineLaunchIdentityMode::Offline;
                            break;
                        case PROfflineLaunchIdentityModeDemo:
                            identityRequest.mode = FrontendOfflineLaunchIdentityMode::Demo;
                            break;
                    }
                    if (accountIdentifierCopy) {
                        identityRequest.accountIdentifier = stableIdentifierFromFoundation(accountIdentifierCopy);
                    }
                    identityRequest.fallbackName = utf8TextFromFoundation(fallbackNameCopy);
                    result = offlineLaunchIdentityLoadResultFromFacadeResult(
                        bridge->_facade->loadOfflineLaunchIdentity(identityRequest));
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid offline launch identity"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Offline launch identity load cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Offline launch identity unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown offline launch identity load failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeOfflineLaunchIdentityLoadDelivery alloc]
                initWithResult:result
                          error:error]];
        }
    });

    return [[PRBridgeObservationToken alloc] initWithState:request];
}

- (PRBridgeObservationToken *)updateOfflineLaunchIdentityWithMode:(PROfflineLaunchIdentityMode)mode
                                                  accountIdentifier:(NSString *)accountIdentifier
                                                               name:(NSString *)name
                                                  allowInvalidName:(BOOL)allowInvalidName
                                                        completion:(PROfflineLaunchIdentityUpdateCompletionHandler)completion
{
    if (!completion || ![self isLifecycleRunning] || !_facade || !_backendQueue) {
        return nil;
    }
    if (!isKnownOfflineLaunchIdentityMode(mode)) {
        return nil;
    }

    NSString *accountIdentifierCopy = [accountIdentifier copy];
    NSString *nameCopy = [name copy];
    __weak PRPrismBridge *weakBridge = self;
    __block __weak PRBridgeObservationState *weakRequest = nil;
    PRBridgeObservationState *request = [[PRBridgeObservationState alloc] initWithHandler:^(id value) {
        PRBridgeOfflineLaunchIdentityUpdateDelivery *delivery = (PRBridgeOfflineLaunchIdentityUpdateDelivery *)value;
        if (delivery.result || delivery.error) {
            [weakRequest cancel];
            completion(delivery.result, delivery.error);
        }
    }];
    weakRequest = request;
    request.removalHandler = ^{
        [weakBridge removeOfflineIdentityUpdateRequest:weakRequest];
    };

    [self.observationLock lock];
    if (![self isLifecycleRunning] || !_facade) {
        [self.observationLock unlock];
        [request cancel];
        return nil;
    }
    [self.offlineIdentityUpdateRequestStates addObject:request];
    [self.observationLock unlock];

    dispatch_async(_backendQueue, ^{
        PRPrismBridge *bridge = weakBridge;
        PRBridgeObservationState *state = weakRequest;
        if (!bridge || !state || state.isCancelled) {
            return;
        }

        PROfflineLaunchIdentityUpdateResult *result = nil;
        PRBridgeError *error = nil;
        {
            std::lock_guard<std::mutex> facadeLock(bridge->_facadeLock);
            if (!bridge->_facade || bridge->_facade->lifecycleState() != FrontendLifecycleState::Running) {
                error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                           diagnosticText:@"Frontend facade is no longer running"
                                       substitutionValues:@{}];
            } else {
                try {
                    FrontendOfflineLaunchIdentityUpdateRequest identityRequest;
                    switch (mode) {
                        case PROfflineLaunchIdentityModeOffline:
                            identityRequest.mode = FrontendOfflineLaunchIdentityMode::Offline;
                            break;
                        case PROfflineLaunchIdentityModeDemo:
                            identityRequest.mode = FrontendOfflineLaunchIdentityMode::Demo;
                            break;
                    }
                    if (accountIdentifierCopy) {
                        identityRequest.accountIdentifier = stableIdentifierFromFoundation(accountIdentifierCopy);
                    }
                    identityRequest.name = utf8TextFromFoundation(nameCopy);
                    identityRequest.allowInvalidName = allowInvalidName;
                    result = offlineLaunchIdentityUpdateResultFromFacadeResult(
                        bridge->_facade->updateOfflineLaunchIdentity(identityRequest));
                } catch (const std::invalid_argument& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::InvalidInput
                                               diagnosticText:diagnosticText ?: @"Invalid offline launch identity"
                                           substitutionValues:@{}];
                } catch (const std::logic_error& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::OperationCancelled
                                               diagnosticText:diagnosticText ?: @"Offline launch identity update cancelled"
                                           substitutionValues:@{}];
                } catch (const std::exception& exception) {
                    NSString *diagnosticText = [NSString stringWithUTF8String:exception.what()];
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::DataUnavailable
                                               diagnosticText:diagnosticText ?: @"Offline launch identity unavailable"
                                           substitutionValues:@{}];
                } catch (...) {
                    error = [bridge bridgeErrorForFailureKind:(NSInteger)NativeFacadeFailureKind::Unknown
                                               diagnosticText:@"Unknown offline launch identity update failure"
                                           substitutionValues:@{}];
                }
            }
        }

        if (!state.isCancelled) {
            [state deliverOnMainActor:[[PRBridgeOfflineLaunchIdentityUpdateDelivery alloc]
                initWithResult:result
                          error:error]];
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

- (void)removeComponentsRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.componentsRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.componentsRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeResourcesRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.resourcesRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.resourcesRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeResourceMutationRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.resourceMutationRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.resourceMutationRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeWorldsRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.worldsRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.worldsRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeServersRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.serversRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.serversRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeScreenshotsRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.screenshotsRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.screenshotsRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeLogFilesRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.logFilesRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.logFilesRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeInstanceLogRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.instanceLogRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.instanceLogRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeInstanceDetailMutationRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.instanceDetailMutationRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.instanceDetailMutationRequestStates removeObjectAtIndex:index];
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

- (void)removeJavaDiscoveryRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.javaDiscoveryRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.javaDiscoveryRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeJavaSelectionRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.javaSelectionRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.javaSelectionRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeAccountSnapshotRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.accountSnapshotRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.accountSnapshotRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeAccountSelectionRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.accountSelectionRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.accountSelectionRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeAccountAuthenticationRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.accountAuthenticationRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.accountAuthenticationRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeVanillaCreationRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.vanillaCreationRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.vanillaCreationRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeInstanceImportRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.instanceImportRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.instanceImportRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeInstanceCopyRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.instanceCopyRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.instanceCopyRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeInstanceExportRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.instanceExportRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.instanceExportRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeProviderBrowseRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.providerBrowseRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.providerBrowseRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeProviderVersionRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.providerVersionRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.providerVersionRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeProviderInstallRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.providerInstallRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.providerInstallRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeOfflineIdentityLoadRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.offlineIdentityLoadRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.offlineIdentityLoadRequestStates removeObjectAtIndex:index];
    }
    [self.observationLock unlock];
}

- (void)removeOfflineIdentityUpdateRequest:(PRBridgeObservationState *)request
{
    [self.observationLock lock];
    NSUInteger index = [self.offlineIdentityUpdateRequestStates indexOfObjectIdenticalTo:request];
    if (index != NSNotFound) {
        [self.offlineIdentityUpdateRequestStates removeObjectAtIndex:index];
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
    [observations addObjectsFromArray:self.componentsRequestStates];
    [observations addObjectsFromArray:self.resourcesRequestStates];
    [observations addObjectsFromArray:self.resourceMutationRequestStates];
    [observations addObjectsFromArray:self.worldsRequestStates];
    [observations addObjectsFromArray:self.serversRequestStates];
    [observations addObjectsFromArray:self.screenshotsRequestStates];
    [observations addObjectsFromArray:self.logFilesRequestStates];
    [observations addObjectsFromArray:self.instanceLogRequestStates];
    [observations addObjectsFromArray:self.instanceDetailMutationRequestStates];
    [observations addObjectsFromArray:self.taskRequestStates];
    [observations addObjectsFromArray:self.taskLogRequestStates];
    [observations addObjectsFromArray:self.taskCancellationRequestStates];
    [observations addObjectsFromArray:self.commandRequestStates];
    [observations addObjectsFromArray:self.notesUpdateRequestStates];
    [observations addObjectsFromArray:self.settingsRequestStates];
    [observations addObjectsFromArray:self.settingsUpdateRequestStates];
    [observations addObjectsFromArray:self.javaDiscoveryRequestStates];
    [observations addObjectsFromArray:self.javaSelectionRequestStates];
    [observations addObjectsFromArray:self.accountSnapshotRequestStates];
    [observations addObjectsFromArray:self.accountSelectionRequestStates];
    [observations addObjectsFromArray:self.accountAuthenticationRequestStates];
    [observations addObjectsFromArray:self.vanillaCreationRequestStates];
    [observations addObjectsFromArray:self.instanceImportRequestStates];
    [observations addObjectsFromArray:self.instanceCopyRequestStates];
    [observations addObjectsFromArray:self.instanceExportRequestStates];
    [observations addObjectsFromArray:self.providerBrowseRequestStates];
    [observations addObjectsFromArray:self.providerVersionRequestStates];
    [observations addObjectsFromArray:self.providerInstallRequestStates];
    [observations addObjectsFromArray:self.offlineIdentityLoadRequestStates];
    [observations addObjectsFromArray:self.offlineIdentityUpdateRequestStates];
    [self.instanceObservationStates removeAllObjects];
    [self.instanceChangeObservationStates removeAllObjects];
    [self.taskObservationStates removeAllObjects];
    [self.snapshotRequestStates removeAllObjects];
    [self.changeRequestStates removeAllObjects];
    [self.detailsRequestStates removeAllObjects];
    [self.componentsRequestStates removeAllObjects];
    [self.resourcesRequestStates removeAllObjects];
    [self.resourceMutationRequestStates removeAllObjects];
    [self.worldsRequestStates removeAllObjects];
    [self.serversRequestStates removeAllObjects];
    [self.screenshotsRequestStates removeAllObjects];
    [self.logFilesRequestStates removeAllObjects];
    [self.instanceLogRequestStates removeAllObjects];
    [self.instanceDetailMutationRequestStates removeAllObjects];
    [self.taskRequestStates removeAllObjects];
    [self.taskLogRequestStates removeAllObjects];
    [self.taskCancellationRequestStates removeAllObjects];
    [self.commandRequestStates removeAllObjects];
    [self.notesUpdateRequestStates removeAllObjects];
    [self.settingsRequestStates removeAllObjects];
    [self.settingsUpdateRequestStates removeAllObjects];
    [self.javaDiscoveryRequestStates removeAllObjects];
    [self.javaSelectionRequestStates removeAllObjects];
    [self.accountSnapshotRequestStates removeAllObjects];
    [self.accountSelectionRequestStates removeAllObjects];
    [self.accountAuthenticationRequestStates removeAllObjects];
    [self.vanillaCreationRequestStates removeAllObjects];
    [self.instanceImportRequestStates removeAllObjects];
    [self.instanceCopyRequestStates removeAllObjects];
    [self.instanceExportRequestStates removeAllObjects];
    [self.providerBrowseRequestStates removeAllObjects];
    [self.providerVersionRequestStates removeAllObjects];
    [self.providerInstallRequestStates removeAllObjects];
    [self.offlineIdentityLoadRequestStates removeAllObjects];
    [self.offlineIdentityUpdateRequestStates removeAllObjects];
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

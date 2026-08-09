#import <Foundation/Foundation.h>

#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

@class PRTaskLogEntry;
@class PRTaskStatus;

typedef NS_ENUM(NSInteger, PRTaskState) {
    PRTaskStateQueued = 0,
    PRTaskStateRunning,
    PRTaskStateCancelling,
    PRTaskStateSucceeded,
    PRTaskStateFailed,
    PRTaskStateCancelled,
};

typedef NS_ENUM(NSInteger, PRTaskProgressKind) {
    PRTaskProgressKindNone = 0,
    PRTaskProgressKindIndeterminate,
    PRTaskProgressKindDeterminate,
};

typedef NS_ENUM(NSInteger, PRTaskTerminalOutcome) {
    PRTaskTerminalOutcomeSucceeded = 0,
    PRTaskTerminalOutcomeFailed,
    PRTaskTerminalOutcomeCancelled,
};

typedef NS_ENUM(NSInteger, PRTaskCancellationOutcome) {
    PRTaskCancellationOutcomeRequested = 0,
    PRTaskCancellationOutcomeAlreadyTerminal,
    PRTaskCancellationOutcomeUnknownTask,
    PRTaskCancellationOutcomeRejected,
};

typedef NS_ENUM(NSInteger, PRInstanceChangeKind) {
    PRInstanceChangeKindAdded = 0,
    PRInstanceChangeKindUpdated,
    PRInstanceChangeKindRemoved,
};

typedef NS_ENUM(NSInteger, PRInstanceCommandKind) {
    PRInstanceCommandKindLaunch = 0,
    PRInstanceCommandKindStop,
};

typedef NS_ENUM(NSInteger, PRInstanceCommandOutcome) {
    PRInstanceCommandOutcomeSucceeded = 0,
    PRInstanceCommandOutcomeUnknownInstance,
    PRInstanceCommandOutcomeRejected,
};

typedef NS_ENUM(NSInteger, PRInstanceNotesUpdateOutcome) {
    PRInstanceNotesUpdateOutcomeSucceeded = 0,
    PRInstanceNotesUpdateOutcomeUnknownInstance,
    PRInstanceNotesUpdateOutcomeRejected,
};

/// Immutable instance metadata that is safe to pass into Swift state.
@interface PRInstanceSummary : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithIdentifier:(NSString *)identifier
                                        name:(NSString *)name
                                     iconKey:(nullable NSString *)iconKey
                                     groupID:(nullable NSString *)groupID NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly, nullable) NSString *iconKey;
@property(nonatomic, copy, readonly, nullable) NSString *groupID;

@end

typedef NS_ENUM(NSInteger, PRVanillaCreationOutcome) {
    PRVanillaCreationOutcomeSucceeded = 0,
    PRVanillaCreationOutcomeFailed,
    PRVanillaCreationOutcomeCancelled,
    PRVanillaCreationOutcomeRejected,
};

/// Foundation-only input for a vanilla instance creation request. The
/// adapter owns staging paths, settings, downloads, and final commits.
@interface PRVanillaCreationRequest : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithVersionDescriptor:(NSString *)versionDescriptor
                                         versionName:(NSString *)versionName
                                   loaderIdentifier:(nullable NSString *)loaderIdentifier
                              loaderVersionDescriptor:(nullable NSString *)loaderVersionDescriptor
                                                 name:(NSString *)name
                                             groupID:(nullable NSString *)groupID
                                             iconKey:(NSString *)iconKey NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *versionDescriptor;
@property(nonatomic, copy, readonly) NSString *versionName;
@property(nonatomic, copy, readonly, nullable) NSString *loaderIdentifier;
@property(nonatomic, copy, readonly, nullable) NSString *loaderVersionDescriptor;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly, nullable) NSString *groupID;
@property(nonatomic, copy, readonly) NSString *iconKey;

@end

/// Immutable confirmed result for one vanilla creation task. Only the
/// resulting instance summary crosses the bridge; staging and task ownership
/// remain in the injected facade adapter.
@interface PRVanillaCreationResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithInstance:(nullable PRInstanceSummary *)instance
                                  outcome:(PRVanillaCreationOutcome)outcome
                           localizationKey:(NSString *)localizationKey
                             diagnosticText:(nullable NSString *)diagnosticText
                                 retryable:(BOOL)retryable NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRInstanceSummary *instance;
@property(nonatomic, assign, readonly) PRVanillaCreationOutcome outcome;
@property(nonatomic, copy, readonly) NSString *localizationKey;
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readonly) BOOL retryable;

@end

typedef NS_ENUM(NSInteger, PRInstanceImportSourceKind) {
    PRInstanceImportSourceKindLocalFile = 0,
    PRInstanceImportSourceKindRemoteURL,
};

/// Foundation-only input for importing a caller-selected local archive or an
/// HTTP(S) archive. Staging, extraction, downloads, and commits remain in the
/// injected facade runner.
@interface PRInstanceImportRequest : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithSourceURL:(NSURL *)sourceURL
                                sourceKind:(PRInstanceImportSourceKind)sourceKind
                                      name:(NSString *)name
                                   groupID:(nullable NSString *)groupID
                                   iconKey:(NSString *)iconKey NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSURL *sourceURL;
@property(nonatomic, assign, readonly) PRInstanceImportSourceKind sourceKind;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly, nullable) NSString *groupID;
@property(nonatomic, copy, readonly) NSString *iconKey;

@end

typedef NS_ENUM(NSInteger, PRInstanceImportOutcome) {
    PRInstanceImportOutcomeSucceeded = 0,
    PRInstanceImportOutcomeFailed,
    PRInstanceImportOutcomeCancelled,
    PRInstanceImportOutcomeRejected,
};

/// Immutable confirmed result for one instance import task. A successful
/// result carries only the committed instance summary.
@interface PRInstanceImportResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithInstance:(nullable PRInstanceSummary *)instance
                                  outcome:(PRInstanceImportOutcome)outcome
                           localizationKey:(NSString *)localizationKey
                             diagnosticText:(nullable NSString *)diagnosticText
                                 retryable:(BOOL)retryable
                  partialChangesRolledBack:(BOOL)partialChangesRolledBack NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRInstanceSummary *instance;
@property(nonatomic, assign, readonly) PRInstanceImportOutcome outcome;
@property(nonatomic, copy, readonly) NSString *localizationKey;
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readonly) BOOL retryable;
@property(nonatomic, assign, readonly) BOOL partialChangesRolledBack;

@end

typedef NS_ENUM(NSInteger, PRInstanceCopyOutcome) {
    PRInstanceCopyOutcomeSucceeded = 0,
    PRInstanceCopyOutcomeFailed,
    PRInstanceCopyOutcomeCancelled,
    PRInstanceCopyOutcomeRejected,
};

/// Foundation-only copy policy. Source paths, staging, filesystem capability
/// checks, and the final commit remain inside the adapter runner.
@interface PRInstanceCopyRequest : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithSourceInstanceIdentifier:(NSString *)sourceInstanceIdentifier
                                                      name:(NSString *)name
                                                   groupID:(nullable NSString *)groupID
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
                                                useClone:(BOOL)useClone NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *sourceInstanceIdentifier;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly, nullable) NSString *groupID;
@property(nonatomic, copy, readonly) NSString *iconKey;
@property(nonatomic, assign, readonly) BOOL copySaves;
@property(nonatomic, assign, readonly) BOOL keepPlaytime;
@property(nonatomic, assign, readonly) BOOL copyGameOptions;
@property(nonatomic, assign, readonly) BOOL copyResourcePacks;
@property(nonatomic, assign, readonly) BOOL copyShaderPacks;
@property(nonatomic, assign, readonly) BOOL copyServers;
@property(nonatomic, assign, readonly) BOOL copyMods;
@property(nonatomic, assign, readonly) BOOL copyScreenshots;
@property(nonatomic, assign, readonly) BOOL useSymbolicLinks;
@property(nonatomic, assign, readonly) BOOL linkRecursively;
@property(nonatomic, assign, readonly) BOOL useHardLinks;
@property(nonatomic, assign, readonly) BOOL dontLinkSaves;
@property(nonatomic, assign, readonly) BOOL useClone;

@end

/// Immutable confirmed result for one fixture-controlled instance copy task.
@interface PRInstanceCopyResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithInstance:(nullable PRInstanceSummary *)instance
                                  outcome:(PRInstanceCopyOutcome)outcome
                           localizationKey:(NSString *)localizationKey
                             diagnosticText:(nullable NSString *)diagnosticText
                                 retryable:(BOOL)retryable
                  partialChangesRolledBack:(BOOL)partialChangesRolledBack NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRInstanceSummary *instance;
@property(nonatomic, assign, readonly) PRInstanceCopyOutcome outcome;
@property(nonatomic, copy, readonly) NSString *localizationKey;
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readonly) BOOL retryable;
@property(nonatomic, assign, readonly) BOOL partialChangesRolledBack;

@end

typedef NS_ENUM(NSInteger, PRInstanceExportKind) {
    PRInstanceExportKindZipArchive = 0,
    PRInstanceExportKindModList,
};

typedef NS_ENUM(NSInteger, PRModListExportFormat) {
    PRModListExportFormatHTML = 0,
    PRModListExportFormatMarkdown,
    PRModListExportFormatPlainText,
    PRModListExportFormatJSON,
    PRModListExportFormatCSV,
    PRModListExportFormatCustom,
};

typedef NS_ENUM(NSInteger, PRInstanceExportOutcome) {
    PRInstanceExportOutcomeSucceeded = 0,
    PRInstanceExportOutcomeFailed,
    PRInstanceExportOutcomeCancelled,
    PRInstanceExportOutcomeRejected,
};

/// Foundation-only local export input. The destination URL must come from a
/// system save panel; no backend path or file contents cross this boundary.
@interface PRInstanceExportRequest : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithSourceInstanceIdentifier:(NSString *)sourceInstanceIdentifier
                                              destinationURL:(NSURL *)destinationURL
                                                       kind:(PRInstanceExportKind)kind
                                             modListFormat:(PRModListExportFormat)modListFormat
                                               includeAuthors:(BOOL)includeAuthors
                                               includeVersion:(BOOL)includeVersion
                                                    includeURL:(BOOL)includeURL
                                                includeFilename:(BOOL)includeFilename
                                               customTemplate:(NSString *)customTemplate NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *sourceInstanceIdentifier;
@property(nonatomic, copy, readonly) NSURL *destinationURL;
@property(nonatomic, assign, readonly) PRInstanceExportKind kind;
@property(nonatomic, assign, readonly) PRModListExportFormat modListFormat;
@property(nonatomic, assign, readonly) BOOL includeAuthors;
@property(nonatomic, assign, readonly) BOOL includeVersion;
@property(nonatomic, assign, readonly) BOOL includeURL;
@property(nonatomic, assign, readonly) BOOL includeFilename;
@property(nonatomic, copy, readonly) NSString *customTemplate;

@end

/// Immutable confirmed result for one local ZIP or mod-list export.
@interface PRInstanceExportResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithKind:(PRInstanceExportKind)kind
                              outcome:(PRInstanceExportOutcome)outcome
                       destinationURL:(NSURL *)destinationURL
                     localizationKey:(NSString *)localizationKey
                       diagnosticText:(nullable NSString *)diagnosticText
                           retryable:(BOOL)retryable
            partialChangesRolledBack:(BOOL)partialChangesRolledBack NS_DESIGNATED_INITIALIZER;

@property(nonatomic, assign, readonly) PRInstanceExportKind kind;
@property(nonatomic, assign, readonly) PRInstanceExportOutcome outcome;
@property(nonatomic, copy, readonly) NSURL *destinationURL;
@property(nonatomic, copy, readonly) NSString *localizationKey;
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readonly) BOOL retryable;
@property(nonatomic, assign, readonly) BOOL partialChangesRolledBack;

@end

typedef NS_ENUM(NSInteger, PRProviderKind) {
    PRProviderKindModrinth = 0,
    PRProviderKindCurseForge,
    PRProviderKindFTB,
    PRProviderKindATLauncher,
    PRProviderKindTechnic,
    PRProviderKindLegacyFTB,
};

typedef NS_ENUM(NSInteger, PRProviderSort) {
    PRProviderSortRelevance = 0,
    PRProviderSortPopularity,
    PRProviderSortNewest,
    PRProviderSortUpdated,
    PRProviderSortName,
    PRProviderSortDownloads,
    PRProviderSortFollows,
    PRProviderSortGameVersion,
    PRProviderSortPlays,
    PRProviderSortInstalls,
};

typedef NS_ENUM(NSInteger, PRProviderReleaseType) {
    PRProviderReleaseTypeUnknown = 0,
    PRProviderReleaseTypeRelease,
    PRProviderReleaseTypeBeta,
    PRProviderReleaseTypeAlpha,
};

typedef NS_ENUM(NSInteger, PRProviderSide) {
    PRProviderSideAny = 0,
    PRProviderSideClient,
    PRProviderSideServer,
    PRProviderSideUniversal,
};

/// Foundation-only provider browse input. Provider endpoints, credentials,
/// cache paths, and network task ownership remain inside Objective-C++.
@interface PRProviderBrowseRequest : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithProvider:(PRProviderKind)provider
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
                             hideInstalled:(BOOL)hideInstalled NS_DESIGNATED_INITIALIZER;

@property(nonatomic, assign, readonly) PRProviderKind provider;
@property(nonatomic, copy, readonly) NSString *query;
@property(nonatomic, assign, readonly) NSInteger offset;
@property(nonatomic, assign, readonly) NSInteger pageSize;
@property(nonatomic, assign, readonly) PRProviderSort sort;
@property(nonatomic, copy, readonly) NSArray<NSString *> *gameVersions;
@property(nonatomic, copy, readonly) NSArray<NSString *> *loaders;
@property(nonatomic, copy, readonly) NSArray<NSString *> *categories;
@property(nonatomic, copy, readonly) NSArray<NSNumber *> *releaseTypes;
@property(nonatomic, assign, readonly) PRProviderSide side;
@property(nonatomic, assign, readonly) BOOL openSource;
@property(nonatomic, assign, readonly) BOOL hideInstalled;

@end

/// Immutable provider browse row. Images and download/install payloads are
/// intentionally absent; Swift uses system text/list controls for this data.
@interface PRProviderPack : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithProvider:(PRProviderKind)provider
                               identifier:(NSString *)identifier
                                     name:(NSString *)name
                                      slug:(nullable NSString *)slug
                                   summary:(nullable NSString *)summary
                                    author:(nullable NSString *)author
                                categories:(NSArray<NSString *> *)categories
                       versionsAvailable:(BOOL)versionsAvailable
                  supportsVersionSelection:(BOOL)supportsVersionSelection NS_DESIGNATED_INITIALIZER;

@property(nonatomic, assign, readonly) PRProviderKind provider;
@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly, nullable) NSString *slug;
@property(nonatomic, copy, readonly, nullable) NSString *summary;
@property(nonatomic, copy, readonly, nullable) NSString *author;
@property(nonatomic, copy, readonly) NSArray<NSString *> *categories;
@property(nonatomic, assign, readonly) BOOL versionsAvailable;
@property(nonatomic, assign, readonly) BOOL supportsVersionSelection;

@end

/// Immutable provider browse page with an explicit optional next offset.
@interface PRProviderBrowsePage : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithProvider:(PRProviderKind)provider
                                    offset:(NSInteger)offset
                                  pageSize:(NSInteger)pageSize
                               nextOffset:(nullable NSNumber *)nextOffset
                                     packs:(NSArray<PRProviderPack *> *)packs NS_DESIGNATED_INITIALIZER;

@property(nonatomic, assign, readonly) PRProviderKind provider;
@property(nonatomic, assign, readonly) NSInteger offset;
@property(nonatomic, assign, readonly) NSInteger pageSize;
@property(nonatomic, strong, readonly, nullable) NSNumber *nextOffset;
@property(nonatomic, copy, readonly) NSArray<PRProviderPack *> *packs;

@end

typedef NS_ENUM(NSInteger, PRProviderBrowseOutcome) {
    PRProviderBrowseOutcomeSucceeded = 0,
    PRProviderBrowseOutcomeFailed,
    PRProviderBrowseOutcomeCancelled,
    PRProviderBrowseOutcomeRejected,
};

/// Immutable confirmed provider browse result.
@interface PRProviderBrowseResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithPage:(nullable PRProviderBrowsePage *)page
                              outcome:(PRProviderBrowseOutcome)outcome
                       localizationKey:(NSString *)localizationKey
                         diagnosticText:(nullable NSString *)diagnosticText
                              retryable:(BOOL)retryable NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRProviderBrowsePage *page;
@property(nonatomic, assign, readonly) PRProviderBrowseOutcome outcome;
@property(nonatomic, copy, readonly) NSString *localizationKey;
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readonly) BOOL retryable;

@end

/// Foundation-only version-list request for one selected provider pack.
@interface PRProviderVersionRequest : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithProvider:(PRProviderKind)provider
                              packIdentifier:(NSString *)packIdentifier
                                gameVersions:(NSArray<NSString *> *)gameVersions
                                    loaders:(NSArray<NSString *> *)loaders NS_DESIGNATED_INITIALIZER;

@property(nonatomic, assign, readonly) PRProviderKind provider;
@property(nonatomic, copy, readonly) NSString *packIdentifier;
@property(nonatomic, copy, readonly) NSArray<NSString *> *gameVersions;
@property(nonatomic, copy, readonly) NSArray<NSString *> *loaders;

@end

/// Immutable version-selection row. Download URLs, archives, and changelog
/// payloads are deliberately deferred to the installation work units.
@interface PRProviderVersion : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithProvider:(PRProviderKind)provider
                               identifier:(NSString *)identifier
                           packIdentifier:(NSString *)packIdentifier
                                     name:(NSString *)name
                                  version:(NSString *)version
                            gameVersions:(NSArray<NSString *> *)gameVersions
                                loaders:(NSArray<NSString *> *)loaders
                            releaseType:(PRProviderReleaseType)releaseType
                 publishedUnixSeconds:(NSInteger)publishedUnixSeconds
                              recommended:(BOOL)recommended NS_DESIGNATED_INITIALIZER;

@property(nonatomic, assign, readonly) PRProviderKind provider;
@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *packIdentifier;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly) NSString *version;
@property(nonatomic, copy, readonly) NSArray<NSString *> *gameVersions;
@property(nonatomic, copy, readonly) NSArray<NSString *> *loaders;
@property(nonatomic, assign, readonly) PRProviderReleaseType releaseType;
@property(nonatomic, assign, readonly) NSInteger publishedUnixSeconds;
@property(nonatomic, assign, readonly) BOOL recommended;

@end

typedef NS_ENUM(NSInteger, PRProviderVersionOutcome) {
    PRProviderVersionOutcomeSucceeded = 0,
    PRProviderVersionOutcomeFailed,
    PRProviderVersionOutcomeCancelled,
    PRProviderVersionOutcomeRejected,
};

/// Immutable confirmed version-selection result.
@interface PRProviderVersionResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithProvider:(PRProviderKind)provider
                            packIdentifier:(NSString *)packIdentifier
                                 versions:(NSArray<PRProviderVersion *> *)versions
                                  outcome:(PRProviderVersionOutcome)outcome
                           localizationKey:(NSString *)localizationKey
                             diagnosticText:(nullable NSString *)diagnosticText
                                  retryable:(BOOL)retryable NS_DESIGNATED_INITIALIZER;

@property(nonatomic, assign, readonly) PRProviderKind provider;
@property(nonatomic, copy, readonly) NSString *packIdentifier;
@property(nonatomic, copy, readonly) NSArray<PRProviderVersion *> *versions;
@property(nonatomic, assign, readonly) PRProviderVersionOutcome outcome;
@property(nonatomic, copy, readonly) NSString *localizationKey;
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readonly) BOOL retryable;

@end

typedef NS_ENUM(NSInteger, PRProviderInstallKind) {
    PRProviderInstallKindModrinth = 0,
    PRProviderInstallKindCurseForgeFlame,
    PRProviderInstallKindFTB,
    PRProviderInstallKindLegacyFTB,
    PRProviderInstallKindFTBImport,
    PRProviderInstallKindATLauncher,
    PRProviderInstallKindTechnicZip,
    PRProviderInstallKindTechnicSolder,
    PRProviderInstallKindCustomArchive,
};

typedef NS_ENUM(NSInteger, PRProviderInstallOutcome) {
    PRProviderInstallOutcomeSucceeded = 0,
    PRProviderInstallOutcomeFailed,
    PRProviderInstallOutcomeCancelled,
    PRProviderInstallOutcomeRejected,
};

typedef NS_ENUM(NSInteger, PRProviderInstallRollbackOutcome) {
    PRProviderInstallRollbackOutcomeNotRequired = 0,
    PRProviderInstallRollbackOutcomeApplied,
    PRProviderInstallRollbackOutcomeFailed,
};

/// Foundation-only provider installation input. Staging, manifests, task
/// ownership, optional/blocked-file choices, and final instance commits remain
/// in Objective-C++. A source URL is allowed only for a local custom archive
/// or FTB App import directory.
@interface PRProviderInstallRequest : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithKind:(PRProviderInstallKind)kind
                       packIdentifier:(NSString *)packIdentifier
                   versionIdentifier:(NSString *)versionIdentifier
                           sourceURL:(nullable NSURL *)sourceURL
                                name:(NSString *)name
                             groupID:(nullable NSString *)groupID
                             iconKey:(NSString *)iconKey NS_DESIGNATED_INITIALIZER;

@property(nonatomic, assign, readonly) PRProviderInstallKind kind;
@property(nonatomic, copy, readonly) NSString *packIdentifier;
@property(nonatomic, copy, readonly) NSString *versionIdentifier;
@property(nonatomic, copy, readonly, nullable) NSURL *sourceURL;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly, nullable) NSString *groupID;
@property(nonatomic, copy, readonly) NSString *iconKey;

@end

/// Immutable confirmed provider installation result. Instance metadata is the
/// only successful payload; rollback status remains explicit on failures.
@interface PRProviderInstallResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithKind:(PRProviderInstallKind)kind
                       packIdentifier:(NSString *)packIdentifier
                   versionIdentifier:(NSString *)versionIdentifier
                            instance:(nullable PRInstanceSummary *)instance
                             outcome:(PRProviderInstallOutcome)outcome
                     rollbackOutcome:(PRProviderInstallRollbackOutcome)rollbackOutcome
                      localizationKey:(NSString *)localizationKey
                        diagnosticText:(nullable NSString *)diagnosticText
                             retryable:(BOOL)retryable NS_DESIGNATED_INITIALIZER;

@property(nonatomic, assign, readonly) PRProviderInstallKind kind;
@property(nonatomic, copy, readonly) NSString *packIdentifier;
@property(nonatomic, copy, readonly) NSString *versionIdentifier;
@property(nonatomic, strong, readonly, nullable) PRInstanceSummary *instance;
@property(nonatomic, assign, readonly) PRProviderInstallOutcome outcome;
@property(nonatomic, assign, readonly) PRProviderInstallRollbackOutcome rollbackOutcome;
@property(nonatomic, copy, readonly) NSString *localizationKey;
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readonly) BOOL retryable;

@end

/// Immutable instance metadata and notes for the native detail form.
@interface PRInstanceDetails : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithIdentifier:(NSString *)identifier
                                        name:(NSString *)name
                                     iconKey:(nullable NSString *)iconKey
                                     groupID:(nullable NSString *)groupID
                               instanceType:(nullable NSString *)instanceType
                                      notes:(NSString *)notes
                              notesEditable:(BOOL)notesEditable NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly, nullable) NSString *iconKey;
@property(nonatomic, copy, readonly, nullable) NSString *groupID;
@property(nonatomic, copy, readonly, nullable) NSString *instanceType;
@property(nonatomic, copy, readonly) NSString *notes;
@property(nonatomic, assign, readonly) BOOL notesEditable;

@end

typedef NS_ENUM(NSInteger, PRInstanceComponentProblemSeverity) {
    PRInstanceComponentProblemSeverityNone = 0,
    PRInstanceComponentProblemSeverityWarning,
    PRInstanceComponentProblemSeverityError,
};

/// Immutable ordered component data for the native version list.
@interface PRInstanceComponent : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithIdentifier:(NSString *)identifier
                                        name:(NSString *)name
                                     version:(NSString *)version
                                     enabled:(BOOL)enabled
                              canBeDisabled:(BOOL)canBeDisabled
                              dependencyOnly:(BOOL)dependencyOnly
                                   important:(BOOL)important
                                      custom:(BOOL)custom
                            problemSeverity:(PRInstanceComponentProblemSeverity)problemSeverity
                          problemDescriptions:(NSArray<NSString *> *)problemDescriptions NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly) NSString *version;
@property(nonatomic, assign, readonly) BOOL enabled;
@property(nonatomic, assign, readonly) BOOL canBeDisabled;
@property(nonatomic, assign, readonly) BOOL dependencyOnly;
@property(nonatomic, assign, readonly) BOOL important;
@property(nonatomic, assign, readonly) BOOL custom;
@property(nonatomic, assign, readonly) PRInstanceComponentProblemSeverity problemSeverity;
@property(nonatomic, copy, readonly) NSArray<NSString *> *problemDescriptions;

@end

typedef NS_ENUM(NSInteger, PRInstanceResourceKind) {
    PRInstanceResourceKindMods = 0,
    PRInstanceResourceKindResourcePacks,
    PRInstanceResourceKindShaderPacks,
    PRInstanceResourceKindTexturePacks,
    PRInstanceResourceKindDataPacks,
};

typedef NS_ENUM(NSInteger, PRInstanceResourceAction) {
    PRInstanceResourceActionEnable = 0,
    PRInstanceResourceActionDisable,
    PRInstanceResourceActionDelete,
    PRInstanceResourceActionImport,
    PRInstanceResourceActionReveal,
};

typedef NS_ENUM(NSInteger, PRInstanceResourceMutationOutcome) {
    PRInstanceResourceMutationOutcomeSucceeded = 0,
    PRInstanceResourceMutationOutcomeUnknownInstance,
    PRInstanceResourceMutationOutcomeUnknownResource,
    PRInstanceResourceMutationOutcomeRejected,
    PRInstanceResourceMutationOutcomeFailed,
};

/// Immutable external-resource data for native mods and pack tables.
@interface PRInstanceResource : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithIdentifier:(NSString *)identifier
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
                         problemDescriptions:(NSArray<NSString *> *)problemDescriptions NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly) NSString *version;
@property(nonatomic, copy, readonly) NSString *fileName;
@property(nonatomic, copy, readonly) NSString *provider;
@property(nonatomic, assign, readonly) PRInstanceResourceKind kind;
@property(nonatomic, assign, readonly) BOOL enabled;
@property(nonatomic, assign, readonly) BOOL canBeToggled;
@property(nonatomic, assign, readonly) BOOL canBeDeleted;
@property(nonatomic, assign, readonly) BOOL directory;
@property(nonatomic, assign, readonly) BOOL hasMetadata;
@property(nonatomic, copy, readonly) NSArray<NSString *> *problemDescriptions;

@end

/// Immutable confirmed result for one explicit resource action.
@interface PRInstanceResourceMutationResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithInstanceIdentifier:(NSString *)instanceIdentifier
                                      resourceIdentifier:(NSString *)resourceIdentifier
                                                    kind:(PRInstanceResourceKind)kind
                                                  action:(PRInstanceResourceAction)action
                                                outcome:(PRInstanceResourceMutationOutcome)outcome
                                         localizationKey:(nullable NSString *)localizationKey
                                          diagnosticText:(nullable NSString *)diagnosticText
                               partialChangesRolledBack:(BOOL)partialChangesRolledBack NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *instanceIdentifier;
@property(nonatomic, copy, readonly) NSString *resourceIdentifier;
@property(nonatomic, assign, readonly) PRInstanceResourceKind kind;
@property(nonatomic, assign, readonly) PRInstanceResourceAction action;
@property(nonatomic, assign, readonly) PRInstanceResourceMutationOutcome outcome;
@property(nonatomic, copy, readonly, nullable) NSString *localizationKey;
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readonly) BOOL partialChangesRolledBack;

@end

typedef NS_ENUM(NSInteger, PRInstanceDetailKind) {
    PRInstanceDetailKindWorlds = 0,
    PRInstanceDetailKindServers,
    PRInstanceDetailKindScreenshots,
    PRInstanceDetailKindLogs,
};

typedef NS_ENUM(NSInteger, PRInstanceDetailAction) {
    PRInstanceDetailActionAdd = 0,
    PRInstanceDetailActionUpdate,
    PRInstanceDetailActionDelete,
    PRInstanceDetailActionMoveUp,
    PRInstanceDetailActionMoveDown,
    PRInstanceDetailActionImport,
    PRInstanceDetailActionCopy,
    PRInstanceDetailActionRename,
    PRInstanceDetailActionReveal,
    PRInstanceDetailActionResetIcon,
    PRInstanceDetailActionJoin,
    PRInstanceDetailActionRefresh,
    PRInstanceDetailActionOpen,
    PRInstanceDetailActionCopyImage,
    PRInstanceDetailActionCopyFiles,
};

typedef NS_ENUM(NSInteger, PRInstanceDetailMutationOutcome) {
    PRInstanceDetailMutationOutcomeSucceeded = 0,
    PRInstanceDetailMutationOutcomeUnknownInstance,
    PRInstanceDetailMutationOutcomeUnknownItem,
    PRInstanceDetailMutationOutcomeRejected,
    PRInstanceDetailMutationOutcomeFailed,
};

typedef NS_ENUM(NSInteger, PRInstanceServerResourcePolicy) {
    PRInstanceServerResourcePolicyAsk = 0,
    PRInstanceServerResourcePolicyAlways,
    PRInstanceServerResourcePolicyNever,
};

typedef NS_ENUM(NSInteger, PRInstanceServerStatus) {
    PRInstanceServerStatusUnknown = 0,
    PRInstanceServerStatusOnline,
    PRInstanceServerStatusOffline,
    PRInstanceServerStatusFailed,
};

/// Immutable world row metadata. Timestamp and byte values stay unformatted
/// so Swift can apply locale-aware presentation.
@interface PRInstanceWorld : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithIdentifier:(NSString *)identifier
                                        name:(NSString *)name
                                  folderName:(NSString *)folderName
                                    gameMode:(NSString *)gameMode
                                    iconKey:(nullable NSString *)iconKey
                          warningDescription:(nullable NSString *)warningDescription
                       lastPlayedUnixSeconds:(NSInteger)lastPlayedUnixSeconds
                                   sizeBytes:(uint64_t)sizeBytes
                                        seed:(nullable NSNumber *)seed
                                   isArchive:(BOOL)isArchive
                              canBeRenamed:(BOOL)canBeRenamed
                               canBeCopied:(BOOL)canBeCopied
                              canBeDeleted:(BOOL)canBeDeleted
                                canBeJoined:(BOOL)canBeJoined
                                  hasIcon:(BOOL)hasIcon NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly) NSString *folderName;
@property(nonatomic, copy, readonly) NSString *gameMode;
@property(nonatomic, copy, readonly, nullable) NSString *iconKey;
@property(nonatomic, copy, readonly, nullable) NSString *warningDescription;
@property(nonatomic, assign, readonly) NSInteger lastPlayedUnixSeconds;
@property(nonatomic, assign, readonly) uint64_t sizeBytes;
@property(nonatomic, strong, readonly, nullable) NSNumber *seed;
@property(nonatomic, assign, readonly) BOOL archive;
@property(nonatomic, assign, readonly) BOOL canBeRenamed;
@property(nonatomic, assign, readonly) BOOL canBeCopied;
@property(nonatomic, assign, readonly) BOOL canBeDeleted;
@property(nonatomic, assign, readonly) BOOL canBeJoined;
@property(nonatomic, assign, readonly) BOOL hasIcon;

@end

/// Immutable server row metadata with status and resource-download policy.
@interface PRInstanceServer : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithIdentifier:(NSString *)identifier
                                        name:(NSString *)name
                                     address:(NSString *)address
                              resourcePolicy:(PRInstanceServerResourcePolicy)resourcePolicy
                                      status:(PRInstanceServerStatus)status
                               onlinePlayers:(NSInteger)onlinePlayers
                               canBeEdited:(BOOL)canBeEdited
                              canBeDeleted:(BOOL)canBeDeleted
                                canBeJoined:(BOOL)canBeJoined NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly) NSString *address;
@property(nonatomic, assign, readonly) PRInstanceServerResourcePolicy resourcePolicy;
@property(nonatomic, assign, readonly) PRInstanceServerStatus status;
@property(nonatomic, assign, readonly) NSInteger onlinePlayers;
@property(nonatomic, assign, readonly) BOOL canBeEdited;
@property(nonatomic, assign, readonly) BOOL canBeDeleted;
@property(nonatomic, assign, readonly) BOOL canBeJoined;

@end

/// Immutable screenshot file metadata; image bytes remain a system action.
@interface PRInstanceScreenshot : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithIdentifier:(NSString *)identifier
                                    fileName:(NSString *)fileName
                                displayName:(NSString *)displayName
                       modifiedUnixSeconds:(NSInteger)modifiedUnixSeconds
                                   sizeBytes:(uint64_t)sizeBytes
                                    readable:(BOOL)readable
                                    writable:(BOOL)writable NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *fileName;
@property(nonatomic, copy, readonly) NSString *displayName;
@property(nonatomic, assign, readonly) NSInteger modifiedUnixSeconds;
@property(nonatomic, assign, readonly) uint64_t sizeBytes;
@property(nonatomic, assign, readonly) BOOL readable;
@property(nonatomic, assign, readonly) BOOL writable;

@end

/// Immutable current or historical log file metadata.
@interface PRInstanceLogFile : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithIdentifier:(NSString *)identifier
                                    fileName:(NSString *)fileName
                                displayName:(NSString *)displayName
                       modifiedUnixSeconds:(NSInteger)modifiedUnixSeconds
                                   sizeBytes:(uint64_t)sizeBytes
                                  compressed:(BOOL)compressed
                                     current:(BOOL)current
                                    readable:(BOOL)readable
                              canBeDeleted:(BOOL)canBeDeleted NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *fileName;
@property(nonatomic, copy, readonly) NSString *displayName;
@property(nonatomic, assign, readonly) NSInteger modifiedUnixSeconds;
@property(nonatomic, assign, readonly) uint64_t sizeBytes;
@property(nonatomic, assign, readonly) BOOL compressed;
@property(nonatomic, assign, readonly) BOOL current;
@property(nonatomic, assign, readonly) BOOL readable;
@property(nonatomic, assign, readonly) BOOL canBeDeleted;

@end

/// Bounded instance log content. Entries reuse the validated immutable line
/// DTO; the log identity remains separate from task identity.
@interface PRInstanceLogSnapshot : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithInstanceIdentifier:(NSString *)instanceIdentifier
                                       logIdentifier:(NSString *)logIdentifier
                                             entries:(NSArray<PRTaskLogEntry *> *)entries
                                  droppedEntryCount:(uint64_t)droppedEntryCount
                                       totalByteCount:(uint64_t)totalByteCount
                                           truncated:(BOOL)truncated NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *instanceIdentifier;
@property(nonatomic, copy, readonly) NSString *logIdentifier;
@property(nonatomic, copy, readonly) NSArray<PRTaskLogEntry *> *entries;
@property(nonatomic, assign, readonly) uint64_t droppedEntryCount;
@property(nonatomic, assign, readonly) uint64_t totalByteCount;
@property(nonatomic, assign, readonly) BOOL truncated;

@end

/// Foundation-only request for one M6-W5 list action.
@interface PRInstanceDetailMutationRequest : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithKind:(PRInstanceDetailKind)kind
                                action:(PRInstanceDetailAction)action
                       itemIdentifier:(NSString *)itemIdentifier
                            sourceURL:(nullable NSURL *)sourceURL
                           targetName:(NSString *)targetName
                                  name:(NSString *)name
                               address:(NSString *)address
                        resourcePolicy:(PRInstanceServerResourcePolicy)resourcePolicy
                             confirmed:(BOOL)confirmed
                              position:(NSInteger)position NS_DESIGNATED_INITIALIZER;

@property(nonatomic, assign, readonly) PRInstanceDetailKind kind;
@property(nonatomic, assign, readonly) PRInstanceDetailAction action;
@property(nonatomic, copy, readonly) NSString *itemIdentifier;
@property(nonatomic, copy, readonly, nullable) NSURL *sourceURL;
@property(nonatomic, copy, readonly) NSString *targetName;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly) NSString *address;
@property(nonatomic, assign, readonly) PRInstanceServerResourcePolicy resourcePolicy;
@property(nonatomic, assign, readonly) BOOL confirmed;
@property(nonatomic, assign, readonly) NSInteger position;

@end

/// Immutable outcome for a world/server/screenshot/log mutation request.
@interface PRInstanceDetailMutationResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithKind:(PRInstanceDetailKind)kind
                                action:(PRInstanceDetailAction)action
                              outcome:(PRInstanceDetailMutationOutcome)outcome
                    instanceIdentifier:(NSString *)instanceIdentifier
                         itemIdentifier:(NSString *)itemIdentifier
                        localizationKey:(nullable NSString *)localizationKey
                         diagnosticText:(nullable NSString *)diagnosticText
              partialChangesRolledBack:(BOOL)partialChangesRolledBack NS_DESIGNATED_INITIALIZER;

@property(nonatomic, assign, readonly) PRInstanceDetailKind kind;
@property(nonatomic, assign, readonly) PRInstanceDetailAction action;
@property(nonatomic, assign, readonly) PRInstanceDetailMutationOutcome outcome;
@property(nonatomic, copy, readonly) NSString *instanceIdentifier;
@property(nonatomic, copy, readonly) NSString *itemIdentifier;
@property(nonatomic, copy, readonly, nullable) NSString *localizationKey;
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readonly) BOOL partialChangesRolledBack;

@end

/// Immutable result for a fixture-safe launch or stop intent.
@interface PRInstanceCommandResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithKind:(PRInstanceCommandKind)kind
                           identifier:(NSString *)identifier
                              outcome:(PRInstanceCommandOutcome)outcome NS_DESIGNATED_INITIALIZER;

@property(nonatomic, assign, readonly) PRInstanceCommandKind kind;
@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, assign, readonly) PRInstanceCommandOutcome outcome;

@end

/// Immutable confirmed result for one notes mutation.
@interface PRInstanceNotesUpdateResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithIdentifier:(NSString *)identifier
                                      notes:(NSString *)notes
                                    outcome:(PRInstanceNotesUpdateOutcome)outcome NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *notes;
@property(nonatomic, assign, readonly) PRInstanceNotesUpdateOutcome outcome;

@end

typedef NS_ENUM(NSInteger, PRInstanceJoinTarget) {
    PRInstanceJoinTargetNone = 0,
    PRInstanceJoinTargetServer,
    PRInstanceJoinTargetWorld,
};

/// Immutable, non-secret instance settings for the native Form surface.
@interface PRInstanceSettings : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithIdentifier:(NSString *)identifier
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
                       customOpenALPath:(NSString *)customOpenALPath NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, assign, readonly) BOOL windowOverrideEnabled;
@property(nonatomic, assign, readonly) BOOL launchMaximized;
@property(nonatomic, assign, readonly) NSInteger windowWidth;
@property(nonatomic, assign, readonly) NSInteger windowHeight;
@property(nonatomic, assign, readonly) BOOL closeAfterLaunch;
@property(nonatomic, assign, readonly) BOOL quitAfterGameStop;
@property(nonatomic, assign, readonly) BOOL consoleOverrideEnabled;
@property(nonatomic, assign, readonly) BOOL showConsole;
@property(nonatomic, assign, readonly) BOOL showConsoleOnError;
@property(nonatomic, assign, readonly) BOOL autoCloseConsole;
@property(nonatomic, assign, readonly) BOOL globalDataPacksEnabled;
@property(nonatomic, copy, readonly) NSString *globalDataPacksPath;
@property(nonatomic, assign, readonly) BOOL gameTimeOverrideEnabled;
@property(nonatomic, assign, readonly) BOOL showGameTime;
@property(nonatomic, assign, readonly) BOOL recordGameTime;
@property(nonatomic, assign, readonly) BOOL countGameTime;
@property(nonatomic, assign, readonly) BOOL joinServerOnLaunch;
@property(nonatomic, assign, readonly) PRInstanceJoinTarget joinTarget;
@property(nonatomic, copy, readonly) NSString *joinServerAddress;
@property(nonatomic, copy, readonly) NSString *joinWorld;
@property(nonatomic, assign, readonly) BOOL overrideModDownloadLoaders;
@property(nonatomic, copy, readonly) NSArray<NSString *> *modDownloadLoaders;
@property(nonatomic, assign, readonly) BOOL javaLocationOverrideEnabled;
@property(nonatomic, copy, readonly) NSString *javaPath;
@property(nonatomic, assign, readonly) BOOL ignoreJavaCompatibility;
@property(nonatomic, assign, readonly) BOOL memoryOverrideEnabled;
@property(nonatomic, assign, readonly) NSInteger minMemoryMiB;
@property(nonatomic, assign, readonly) NSInteger maxMemoryMiB;
@property(nonatomic, assign, readonly) NSInteger permGenMiB;
@property(nonatomic, assign, readonly) BOOL lowMemoryWarning;
@property(nonatomic, assign, readonly) BOOL javaArgumentsOverrideEnabled;
@property(nonatomic, copy, readonly) NSString *jvmArguments;
@property(nonatomic, assign, readonly) BOOL commandOverrideEnabled;
@property(nonatomic, copy, readonly) NSString *preLaunchCommand;
@property(nonatomic, copy, readonly) NSString *wrapperCommand;
@property(nonatomic, copy, readonly) NSString *postExitCommand;
@property(nonatomic, assign, readonly) BOOL legacySettingsOverrideEnabled;
@property(nonatomic, assign, readonly) BOOL onlineFixes;
@property(nonatomic, assign, readonly) BOOL nativeWorkaroundsOverrideEnabled;
@property(nonatomic, assign, readonly) BOOL useNativeGLFW;
@property(nonatomic, copy, readonly) NSString *customGLFWPath;
@property(nonatomic, assign, readonly) BOOL useNativeOpenAL;
@property(nonatomic, copy, readonly) NSString *customOpenALPath;

@end

typedef NS_ENUM(NSInteger, PRInstanceSettingsUpdateOutcome) {
    PRInstanceSettingsUpdateOutcomeSucceeded = 0,
    PRInstanceSettingsUpdateOutcomeUnknownInstance,
    PRInstanceSettingsUpdateOutcomeRejected,
};

/// Immutable confirmed result for one instance settings mutation.
@interface PRInstanceSettingsUpdateResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithIdentifier:(NSString *)identifier
                                    settings:(nullable PRInstanceSettings *)settings
                                    outcome:(PRInstanceSettingsUpdateOutcome)outcome NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, strong, readonly, nullable) PRInstanceSettings *settings;
@property(nonatomic, assign, readonly) PRInstanceSettingsUpdateOutcome outcome;

@end

/// Immutable, non-secret global settings for the native Settings scene.
/// The directory URL is a scoped system-panel result; bookmark bytes and
/// their persistence remain inside the adapter and never enter this model.
@interface PRGlobalSettings : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithInstanceDirectoryURL:(NSURL *)instanceDirectoryURL
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
                                      logPrePostOutput:(BOOL)logPrePostOutput NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSURL *instanceDirectoryURL;
@property(nonatomic, copy, readonly) NSString *iconTheme;
@property(nonatomic, copy, readonly) NSString *applicationTheme;
@property(nonatomic, copy, readonly) NSString *backgroundCat;
@property(nonatomic, assign, readonly) NSInteger catOpacity;
@property(nonatomic, copy, readonly) NSString *catFit;
@property(nonatomic, copy, readonly) NSString *language;
@property(nonatomic, assign, readonly) BOOL useSystemLocale;
@property(nonatomic, assign, readonly) BOOL menuBarInsteadOfToolBar;
@property(nonatomic, assign, readonly) BOOL statusBarVisible;
@property(nonatomic, assign, readonly) BOOL toolbarsLocked;
@property(nonatomic, assign, readonly) NSInteger numberOfConcurrentTasks;
@property(nonatomic, assign, readonly) NSInteger numberOfConcurrentDownloads;
@property(nonatomic, assign, readonly) NSInteger numberOfManualRetries;
@property(nonatomic, assign, readonly) NSInteger requestTimeoutSeconds;
@property(nonatomic, copy, readonly) NSString *consoleFont;
@property(nonatomic, assign, readonly) NSInteger consoleFontSize;
@property(nonatomic, assign, readonly) NSInteger consoleMaxLines;
@property(nonatomic, assign, readonly) BOOL consoleOverflowStop;
@property(nonatomic, assign, readonly) BOOL showConsole;
@property(nonatomic, assign, readonly) BOOL autoCloseConsole;
@property(nonatomic, assign, readonly) BOOL showConsoleOnError;
@property(nonatomic, assign, readonly) BOOL logPrePostOutput;

@end

typedef NS_ENUM(NSInteger, PRGlobalSettingsUpdateOutcome) {
    PRGlobalSettingsUpdateOutcomeSucceeded = 0,
    PRGlobalSettingsUpdateOutcomeRejected,
};

/// Immutable confirmed result for one global settings mutation.
@interface PRGlobalSettingsUpdateResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithSettings:(nullable PRGlobalSettings *)settings
                                   outcome:(PRGlobalSettingsUpdateOutcome)outcome NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRGlobalSettings *settings;
@property(nonatomic, assign, readonly) PRGlobalSettingsUpdateOutcome outcome;

@end

typedef NS_ENUM(NSInteger, PRJavaInstallationValidity) {
    PRJavaInstallationValidityValid = 0,
    PRJavaInstallationValidityIncompatible,
    PRJavaInstallationValidityUnavailable,
};

/// Immutable Java discovery row. The executable path is display metadata only;
/// Swift never executes it or receives Java process output.
@interface PRJavaInstallation : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithIdentifier:(NSString *)identifier
                                     version:(NSString *)version
                                      vendor:(NSString *)vendor
                                architecture:(NSString *)architecture
                             executablePath:(NSString *)executablePath
                                   is64Bit:(BOOL)is64Bit
                                    managed:(BOOL)managed
                                   validity:(PRJavaInstallationValidity)validity
                             diagnosticText:(nullable NSString *)diagnosticText NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *version;
@property(nonatomic, copy, readonly) NSString *vendor;
@property(nonatomic, copy, readonly) NSString *architecture;
@property(nonatomic, copy, readonly) NSString *executablePath;
@property(nonatomic, assign, readonly) BOOL is64Bit;
@property(nonatomic, assign, readonly) BOOL managed;
@property(nonatomic, assign, readonly) PRJavaInstallationValidity validity;
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;

@end

typedef NS_ENUM(NSInteger, PRJavaDiscoveryOutcome) {
    PRJavaDiscoveryOutcomeSucceeded = 0,
    PRJavaDiscoveryOutcomeFailed,
    PRJavaDiscoveryOutcomeCancelled,
    PRJavaDiscoveryOutcomeRejected,
};

/// Immutable result for one discovery operation. Failure text is adapter-owned
/// and sanitized; raw stdout/stderr never crosses the bridge.
@interface PRJavaDiscoveryResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithInstallations:(NSArray<PRJavaInstallation *> *)installations
                                        outcome:(PRJavaDiscoveryOutcome)outcome
                                localizationKey:(NSString *)localizationKey
                                  diagnosticText:(nullable NSString *)diagnosticText
                                      retryable:(BOOL)retryable NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSArray<PRJavaInstallation *> *installations;
@property(nonatomic, assign, readonly) PRJavaDiscoveryOutcome outcome;
@property(nonatomic, copy, readonly) NSString *localizationKey;
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readonly) BOOL retryable;

@end

typedef NS_ENUM(NSInteger, PRJavaSelectionOutcome) {
    PRJavaSelectionOutcomeSucceeded = 0,
    PRJavaSelectionOutcomeUnknownInstallation,
    PRJavaSelectionOutcomeRejected,
};

/// Immutable confirmed Java selection result.
@interface PRJavaSelectionResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithInstallation:(nullable PRJavaInstallation *)installation
                                       outcome:(PRJavaSelectionOutcome)outcome
                               localizationKey:(NSString *)localizationKey
                                 diagnosticText:(nullable NSString *)diagnosticText NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRJavaInstallation *installation;
@property(nonatomic, assign, readonly) PRJavaSelectionOutcome outcome;
@property(nonatomic, copy, readonly) NSString *localizationKey;
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;

@end

typedef NS_ENUM(NSInteger, PRAccountType) {
    PRAccountTypeMicrosoft = 0,
    PRAccountTypeOffline,
};

typedef NS_ENUM(NSInteger, PRAccountState) {
    PRAccountStateUnchecked = 0,
    PRAccountStateOffline,
    PRAccountStateWorking,
    PRAccountStateOnline,
    PRAccountStateDisabled,
    PRAccountStateErrored,
    PRAccountStateExpired,
    PRAccountStateGone,
};

/// Immutable, non-secret account metadata. Provider-owned authentication
/// state, credentials, profile payloads, and persistence stay outside Swift.
@interface PRAccountSnapshot : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithIdentifier:(NSString *)identifier
                                 displayName:(NSString *)displayName
                                        type:(PRAccountType)type
                                       state:(PRAccountState)state
                               ownsMinecraft:(BOOL)ownsMinecraft
                                      isBusy:(BOOL)isBusy
                              canBeSelected:(BOOL)canBeSelected
                              diagnosticText:(nullable NSString *)diagnosticText NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *displayName;
@property(nonatomic, assign, readonly) PRAccountType type;
@property(nonatomic, assign, readonly) PRAccountState state;
@property(nonatomic, assign, readonly) BOOL ownsMinecraft;
@property(nonatomic, assign, readonly) BOOL isBusy;
@property(nonatomic, assign, readonly) BOOL canBeSelected;
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;

@end

typedef NS_ENUM(NSInteger, PRAccountSnapshotOutcome) {
    PRAccountSnapshotOutcomeSucceeded = 0,
    PRAccountSnapshotOutcomeFailed,
    PRAccountSnapshotOutcomeCancelled,
    PRAccountSnapshotOutcomeRejected,
};

/// Immutable result for one account snapshot load. The active identifier is
/// the legacy default account, not an authentication-task state.
@interface PRAccountSnapshotResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithAccounts:(NSArray<PRAccountSnapshot *> *)accounts
                    activeAccountIdentifier:(nullable NSString *)activeAccountIdentifier
                                   outcome:(PRAccountSnapshotOutcome)outcome
                           localizationKey:(NSString *)localizationKey
                             diagnosticText:(nullable NSString *)diagnosticText
                                 retryable:(BOOL)retryable NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSArray<PRAccountSnapshot *> *accounts;
@property(nonatomic, copy, readonly, nullable) NSString *activeAccountIdentifier;
@property(nonatomic, assign, readonly) PRAccountSnapshotOutcome outcome;
@property(nonatomic, copy, readonly) NSString *localizationKey;
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readonly) BOOL retryable;

@end

typedef NS_ENUM(NSInteger, PRAccountSelectionOutcome) {
    PRAccountSelectionOutcomeSucceeded = 0,
    PRAccountSelectionOutcomeUnknownAccount,
    PRAccountSelectionOutcomeRejected,
};

/// Immutable confirmed active-account selection. A successful nil account
/// clears the legacy default account.
@interface PRAccountSelectionResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithAccount:(nullable PRAccountSnapshot *)account
                                 outcome:(PRAccountSelectionOutcome)outcome
                          localizationKey:(NSString *)localizationKey
                            diagnosticText:(nullable NSString *)diagnosticText NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRAccountSnapshot *account;
@property(nonatomic, assign, readonly) PRAccountSelectionOutcome outcome;
@property(nonatomic, copy, readonly) NSString *localizationKey;
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;

@end

typedef NS_ENUM(NSInteger, PRAccountAuthenticationAction) {
    PRAccountAuthenticationActionLogin = 0,
    PRAccountAuthenticationActionRefresh,
};

typedef NS_ENUM(NSInteger, PRAccountAuthenticationPhase) {
    PRAccountAuthenticationPhasePreparing = 0,
    PRAccountAuthenticationPhaseAwaitingUser,
    PRAccountAuthenticationPhaseAuthenticating,
    PRAccountAuthenticationPhaseSucceeded,
    PRAccountAuthenticationPhaseFailed,
    PRAccountAuthenticationPhaseCancelled,
};

typedef NS_ENUM(NSInteger, PRAccountAuthenticationOutcome) {
    PRAccountAuthenticationOutcomeInProgress = 0,
    PRAccountAuthenticationOutcomeSucceeded,
    PRAccountAuthenticationOutcomeFailed,
    PRAccountAuthenticationOutcomeCancelled,
    PRAccountAuthenticationOutcomeRejected,
};

/// Immutable, non-secret authentication progress. Verification metadata is a
/// safe URL and instruction state only; user codes, authorization codes,
/// bearer tokens, refresh tokens, and profiles remain outside Swift.
@interface PRAccountAuthenticationProgress : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithAccountIdentifier:(NSString *)accountIdentifier
                                             action:(PRAccountAuthenticationAction)action
                                              phase:(PRAccountAuthenticationPhase)phase
                                            outcome:(PRAccountAuthenticationOutcome)outcome
                                      providerLabel:(NSString *)providerLabel
                                    verificationURL:(nullable NSString *)verificationURL
                                    localizationKey:(NSString *)localizationKey
                                      diagnosticText:(nullable NSString *)diagnosticText
                                   expiresInSeconds:(NSInteger)expiresInSeconds
                                         canCancel:(BOOL)canCancel
                                          retryable:(BOOL)retryable
                                 requiresUserAction:(BOOL)requiresUserAction NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *accountIdentifier;
@property(nonatomic, assign, readonly) PRAccountAuthenticationAction action;
@property(nonatomic, assign, readonly) PRAccountAuthenticationPhase phase;
@property(nonatomic, assign, readonly) PRAccountAuthenticationOutcome outcome;
@property(nonatomic, copy, readonly) NSString *providerLabel;
@property(nonatomic, copy, readonly, nullable) NSString *verificationURL;
@property(nonatomic, copy, readonly) NSString *localizationKey;
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readonly) NSInteger expiresInSeconds;
@property(nonatomic, assign, readonly) BOOL canCancel;
@property(nonatomic, assign, readonly) BOOL retryable;
@property(nonatomic, assign, readonly) BOOL requiresUserAction;
@property(nonatomic, assign, readonly, getter=isTerminal) BOOL terminal;

@end

/// Immutable confirmed authentication outcome carrying only non-secret account
/// metadata when successful.
@interface PRAccountAuthenticationResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithAccount:(nullable PRAccountSnapshot *)account
                                 outcome:(PRAccountAuthenticationOutcome)outcome
                          localizationKey:(NSString *)localizationKey
                            diagnosticText:(nullable NSString *)diagnosticText
                                retryable:(BOOL)retryable NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PRAccountSnapshot *account;
@property(nonatomic, assign, readonly) PRAccountAuthenticationOutcome outcome;
@property(nonatomic, copy, readonly) NSString *localizationKey;
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readonly) BOOL retryable;

@end

typedef NS_ENUM(NSInteger, PROfflineLaunchIdentityMode) {
    PROfflineLaunchIdentityModeOffline = 0,
    PROfflineLaunchIdentityModeDemo,
};

/// Immutable user-visible offline launch identity. Account identifiers are
/// fixture keys only; launch sessions, UUIDs, and credentials stay in the adapter.
@interface PROfflineLaunchIdentity : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithMode:(PROfflineLaunchIdentityMode)mode
                    accountIdentifier:(nullable NSString *)accountIdentifier
                                  name:(NSString *)name NS_DESIGNATED_INITIALIZER;

@property(nonatomic, assign, readonly) PROfflineLaunchIdentityMode mode;
@property(nonatomic, copy, readonly, nullable) NSString *accountIdentifier;
@property(nonatomic, copy, readonly) NSString *name;

@end

typedef NS_ENUM(NSInteger, PROfflineLaunchIdentityLoadOutcome) {
    PROfflineLaunchIdentityLoadOutcomeSucceeded = 0,
    PROfflineLaunchIdentityLoadOutcomeFailed,
    PROfflineLaunchIdentityLoadOutcomeCancelled,
    PROfflineLaunchIdentityLoadOutcomeRejected,
};

/// Immutable load result for a fixture-controlled offline identity.
@interface PROfflineLaunchIdentityLoadResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithIdentity:(nullable PROfflineLaunchIdentity *)identity
                                   outcome:(PROfflineLaunchIdentityLoadOutcome)outcome
                            localizationKey:(NSString *)localizationKey
                              diagnosticText:(nullable NSString *)diagnosticText
                                  retryable:(BOOL)retryable NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PROfflineLaunchIdentity *identity;
@property(nonatomic, assign, readonly) PROfflineLaunchIdentityLoadOutcome outcome;
@property(nonatomic, copy, readonly) NSString *localizationKey;
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readonly) BOOL retryable;

@end

typedef NS_ENUM(NSInteger, PROfflineLaunchIdentityUpdateOutcome) {
    PROfflineLaunchIdentityUpdateOutcomeSucceeded = 0,
    PROfflineLaunchIdentityUpdateOutcomeInvalidName,
    PROfflineLaunchIdentityUpdateOutcomeFailed,
    PROfflineLaunchIdentityUpdateOutcomeCancelled,
    PROfflineLaunchIdentityUpdateOutcomeRejected,
};

/// Immutable confirmed update result. The bridge validates the explicit
/// legacy 3–16 ASCII-name rule before invoking the adapter unless the user
/// explicitly enables the legacy invalid-name escape hatch.
@interface PROfflineLaunchIdentityUpdateResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithIdentity:(nullable PROfflineLaunchIdentity *)identity
                                   outcome:(PROfflineLaunchIdentityUpdateOutcome)outcome
                            localizationKey:(NSString *)localizationKey
                              diagnosticText:(nullable NSString *)diagnosticText
                                  retryable:(BOOL)retryable NS_DESIGNATED_INITIALIZER;

@property(nonatomic, strong, readonly, nullable) PROfflineLaunchIdentity *identity;
@property(nonatomic, assign, readonly) PROfflineLaunchIdentityUpdateOutcome outcome;
@property(nonatomic, copy, readonly) NSString *localizationKey;
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readonly) BOOL retryable;

@end

/// Immutable progress state for one task subtask.
@interface PRTaskSubtaskStatus : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithIdentifier:(NSString *)identifier
                                        name:(NSString *)name
                                       state:(PRTaskState)state
                                progressKind:(PRTaskProgressKind)progressKind
                            progressFraction:(double)progressFraction NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, assign, readonly) PRTaskState state;
@property(nonatomic, assign, readonly) PRTaskProgressKind progressKind;
@property(nonatomic, assign, readonly) double progressFraction;

@end

/// Immutable terminal metadata that stays separate from user-facing error rendering.
@interface PRTaskTerminalResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithOutcome:(PRTaskTerminalOutcome)outcome
                         localizationKey:(NSString *)localizationKey
                     substitutionValues:(NSDictionary<NSString *, NSString *> *)substitutionValues
                         diagnosticText:(nullable NSString *)diagnosticText
                partialChangesRolledBack:(BOOL)partialChangesRolledBack NS_DESIGNATED_INITIALIZER;

@property(nonatomic, assign, readonly) PRTaskTerminalOutcome outcome;
@property(nonatomic, copy, readonly) NSString *localizationKey;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *substitutionValues;
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readonly) BOOL partialChangesRolledBack;

@end

/// Immutable task state that carries progress, subtasks, and terminal metadata without exposing a launcher model.
@interface PRTaskStatus : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithIdentifier:(NSString *)identifier
                                       state:(PRTaskState)state
                                progressKind:(PRTaskProgressKind)progressKind
                            progressFraction:(double)progressFraction
                         cancellationAllowed:(BOOL)cancellationAllowed;
- (nullable instancetype)initWithIdentifier:(NSString *)identifier
                                       title:(nullable NSString *)title
                                       state:(PRTaskState)state
                                progressKind:(PRTaskProgressKind)progressKind
                            progressFraction:(double)progressFraction
                         cancellationAllowed:(BOOL)cancellationAllowed
                                   subtasks:(NSArray<PRTaskSubtaskStatus *> *)subtasks
                              terminalResult:(nullable PRTaskTerminalResult *)terminalResult NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, copy, readonly, nullable) NSString *title;
@property(nonatomic, assign, readonly) PRTaskState state;
@property(nonatomic, assign, readonly) PRTaskProgressKind progressKind;
@property(nonatomic, assign, readonly) double progressFraction;
@property(nonatomic, assign, readonly) BOOL cancellationAllowed;
@property(nonatomic, copy, readonly) NSArray<PRTaskSubtaskStatus *> *subtasks;
@property(nonatomic, strong, readonly, nullable) PRTaskTerminalResult *terminalResult;

@end

/// Immutable outcome for a cancellation request on a stable task identifier.
@interface PRTaskCancellationResult : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithIdentifier:(NSString *)identifier
                                     outcome:(PRTaskCancellationOutcome)outcome NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, assign, readonly) PRTaskCancellationOutcome outcome;

@end

/// One privacy-filtered, immutable log line. The facade guarantees that the
/// sequence is stable and that the text has already passed its byte bound.
@interface PRTaskLogEntry : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithSequence:(uint64_t)sequence
                                      text:(NSString *)text
                                 truncated:(BOOL)truncated NS_DESIGNATED_INITIALIZER;

@property(nonatomic, assign, readonly) uint64_t sequence;
@property(nonatomic, copy, readonly) NSString *text;
@property(nonatomic, assign, readonly) BOOL truncated;

@end

/// One bounded, privacy-filtered task log snapshot for native presentation.
@interface PRTaskLogSnapshot : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithTaskIdentifier:(NSString *)taskIdentifier
                                         entries:(NSArray<PRTaskLogEntry *> *)entries
                             droppedEntryCount:(uint64_t)droppedEntryCount
                                  totalByteCount:(uint64_t)totalByteCount
                                      truncated:(BOOL)truncated NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *taskIdentifier;
@property(nonatomic, copy, readonly) NSArray<PRTaskLogEntry *> *entries;
@property(nonatomic, assign, readonly) uint64_t droppedEntryCount;
@property(nonatomic, assign, readonly) uint64_t totalByteCount;
@property(nonatomic, assign, readonly) BOOL truncated;

@end

/// Immutable instance change data with an optional summary for removals.
@interface PRInstanceChange : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithKind:(PRInstanceChangeKind)kind
                           identifier:(NSString *)identifier
                              summary:(nullable PRInstanceSummary *)summary NS_DESIGNATED_INITIALIZER;

@property(nonatomic, assign, readonly) PRInstanceChangeKind kind;
@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, strong, readonly, nullable) PRInstanceSummary *summary;

@end

NS_ASSUME_NONNULL_END

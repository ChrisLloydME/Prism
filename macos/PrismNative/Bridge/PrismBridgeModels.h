#import <Foundation/Foundation.h>

#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

@class PRTaskLogEntry;

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

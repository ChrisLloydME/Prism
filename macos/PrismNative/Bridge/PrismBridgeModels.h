#import <Foundation/Foundation.h>

#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

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

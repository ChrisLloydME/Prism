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

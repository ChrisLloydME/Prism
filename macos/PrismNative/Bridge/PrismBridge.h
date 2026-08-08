#import <Foundation/Foundation.h>
#import "PrismBridgeErrors.h"
#import "PrismBridgeModels.h"

NS_ASSUME_NONNULL_BEGIN

/// Stable Objective-C surface between Swift and the existing C++ launcher core.
/// Qt and C++ types must not cross this boundary.
@interface PRApplicationIdentity : NSObject

/// The product identity is fixed so the native fork cannot drift into the
/// upstream application's bundle or data namespace.
+ (NSString *)requiredBundleIdentifier;
+ (NSString *)applicationName;

- (instancetype)init;
- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier
           applicationSupportBaseDirectory:(NSURL *)applicationSupportBaseDirectory NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *bundleIdentifier;
@property(nonatomic, copy, readonly) NSString *applicationName;
@property(nonatomic, copy, readonly) NSURL *applicationSupportDirectory;

@end

typedef NS_ENUM(NSInteger, PRBridgeLifecycleState) {
    PRBridgeLifecycleStateRunning = 0,
    PRBridgeLifecycleStateShuttingDown,
    PRBridgeLifecycleStateStopped,
};

typedef void (^PRBridgeLifecycleHandler)(void);
typedef void (^PRInstanceSummaryObservationHandler)(PRInstanceSummary *summary);
typedef void (^PRInstanceChangeObservationHandler)(PRInstanceChange *change);
typedef void (^PRTaskStatusObservationHandler)(PRTaskStatus *status);
typedef void (^PRTaskStatusCompletionHandler)(PRTaskStatus * _Nullable status,
                                               PRBridgeError * _Nullable error);
typedef void (^PRTaskLogCompletionHandler)(PRTaskLogSnapshot * _Nullable snapshot,
                                            PRBridgeError * _Nullable error);
typedef void (^PRTaskCancellationCompletionHandler)(PRTaskCancellationResult * _Nullable result,
                                                     PRBridgeError * _Nullable error);
typedef void (^PRInstanceSummariesCompletionHandler)(NSArray<PRInstanceSummary *> *summaries,
                                                      PRBridgeError * _Nullable error);
typedef void (^PRInstanceChangesCompletionHandler)(NSArray<PRInstanceChange *> *changes,
                                                    PRBridgeError * _Nullable error);
typedef void (^PRInstanceDetailsCompletionHandler)(PRInstanceDetails * _Nullable details,
                                                    PRBridgeError * _Nullable error);
typedef void (^PRInstanceComponentsCompletionHandler)(NSArray<PRInstanceComponent *> * _Nullable components,
                                                       PRBridgeError * _Nullable error);
typedef void (^PRInstanceCommandCompletionHandler)(PRInstanceCommandResult * _Nullable result,
                                                    PRBridgeError * _Nullable error);
typedef void (^PRInstanceNotesUpdateCompletionHandler)(PRInstanceNotesUpdateResult * _Nullable result,
                                                        PRBridgeError * _Nullable error);
typedef void (^PRInstanceSettingsCompletionHandler)(PRInstanceSettings * _Nullable settings,
                                                     PRBridgeError * _Nullable error);
typedef void (^PRInstanceSettingsUpdateCompletionHandler)(PRInstanceSettingsUpdateResult * _Nullable result,
                                                           PRBridgeError * _Nullable error);

/// Owns one bridge observation registration and cancels it when released.
@interface PRBridgeObservationToken : NSObject

- (instancetype)init NS_UNAVAILABLE;

@property(nonatomic, assign, readonly, getter=isCancelled) BOOL cancelled;

/// Returns YES only when this call transitions the token to cancelled.
- (BOOL)cancel;

@end

/// Objective-C++ composition root for the native facade lifecycle.
///
/// The root accepts an explicit file URL and owns cancellation and shutdown
/// callbacks until the first shutdown completes. C++ and Qt remain private to
/// the implementation file; Swift sees only Foundation values and handlers.
@interface PRPrismBridge : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithDataRootURL:(NSURL *)dataRootURL
                          cancellationHandler:(nullable PRBridgeLifecycleHandler)cancellationHandler
                             shutdownHandler:(nullable PRBridgeLifecycleHandler)shutdownHandler;

@property(nonatomic, copy, readonly) NSURL *dataRootURL;
@property(nonatomic, assign, readonly) PRBridgeLifecycleState lifecycleState;

/// Cancels pending work, releases lifecycle callbacks, and stops the root.
/// Repeated calls return NO and do not invoke callbacks again.
- (BOOL)shutdown;

/// Registers a Foundation callback. Releasing or cancelling the returned token
/// removes the callback; registration is rejected once shutdown begins.
- (nullable PRBridgeObservationToken *)observeInstanceSummariesWithHandler:(PRInstanceSummaryObservationHandler)handler;
- (nullable PRBridgeObservationToken *)observeInstanceChangesWithHandler:(PRInstanceChangeObservationHandler)handler;
- (nullable PRBridgeObservationToken *)observeTaskStatusWithHandler:(PRTaskStatusObservationHandler)handler;

/// Loads facade snapshots asynchronously. The completion runs on the main
/// actor and the returned token cancels delivery if it is released or cancelled
/// before the backend result is delivered.
- (nullable PRBridgeObservationToken *)loadInstanceSummariesWithCompletion:(PRInstanceSummariesCompletionHandler)completion;
- (nullable PRBridgeObservationToken *)loadInstanceChangesWithCompletion:(PRInstanceChangesCompletionHandler)completion;

/// Loads immutable metadata and notes for one stable instance identifier.
- (nullable PRBridgeObservationToken *)loadInstanceDetailsWithIdentifier:(NSString *)identifier
                                                                 completion:(PRInstanceDetailsCompletionHandler)completion;

/// Loads the ordered, immutable version/component list for one stable
/// instance identifier. The adapter preserves PackProfile order; no Qt model
/// or file ownership crosses the bridge.
- (nullable PRBridgeObservationToken *)loadInstanceComponentsWithIdentifier:(NSString *)identifier
                                                                   completion:(PRInstanceComponentsCompletionHandler)completion;

/// Loads one immutable task snapshot by stable identifier. Unknown tasks and
/// lifecycle failures are returned as stable bridge errors; the completion
/// runs on the main actor.
- (nullable PRBridgeObservationToken *)loadTaskStatusWithIdentifier:(NSString *)identifier
                                                          completion:(PRTaskStatusCompletionHandler)completion;

/// Loads one bounded, privacy-filtered task log snapshot. The completion
/// runs on the main actor and exposes only immutable Foundation values.
- (nullable PRBridgeObservationToken *)loadTaskLogWithIdentifier:(NSString *)identifier
                                                        completion:(PRTaskLogCompletionHandler)completion;

/// Requests cancellation through the injected facade port. The result is
/// idempotent and distinguishes requested, already-terminal, unknown-task,
/// and rejected outcomes; lifecycle and input failures use PRBridgeError.
- (nullable PRBridgeObservationToken *)cancelTaskWithIdentifier:(NSString *)identifier
                                                        completion:(PRTaskCancellationCompletionHandler)completion;

/// Sends a fixture-controlled command for one stable instance identifier. The
/// completion runs on the main actor with a Foundation result for success,
/// unknown-instance, or explicit backend rejection; invalid input and
/// lifecycle failures use PRBridgeError.
- (nullable PRBridgeObservationToken *)launchInstanceWithIdentifier:(NSString *)identifier
                                                           completion:(PRInstanceCommandCompletionHandler)completion;
- (nullable PRBridgeObservationToken *)stopInstanceWithIdentifier:(NSString *)identifier
                                                         completion:(PRInstanceCommandCompletionHandler)completion;

/// Persists notes through the injected facade port and returns the confirmed
/// value. The bridge never writes an instance file or owns a settings object.
- (nullable PRBridgeObservationToken *)updateInstanceNotesWithIdentifier:(NSString *)identifier
                                                                    notes:(NSString *)notes
                                                                completion:(PRInstanceNotesUpdateCompletionHandler)completion;

/// Loads immutable, non-secret instance settings for a standard native Form.
- (nullable PRBridgeObservationToken *)loadInstanceSettingsWithIdentifier:(NSString *)identifier
                                                                  completion:(PRInstanceSettingsCompletionHandler)completion;

/// Persists instance settings through the injected facade port and returns
/// the confirmed snapshot. Account selection and environment values are not
/// part of this contract.
- (nullable PRBridgeObservationToken *)updateInstanceSettingsWithIdentifier:(NSString *)identifier
                                                                    settings:(PRInstanceSettings *)settings
                                                                  completion:(PRInstanceSettingsUpdateCompletionHandler)completion;

@end

NS_ASSUME_NONNULL_END

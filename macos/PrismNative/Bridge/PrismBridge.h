#import <Foundation/Foundation.h>
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
typedef void (^PRTaskStatusObservationHandler)(PRTaskStatus *status);

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
                             shutdownHandler:(nullable PRBridgeLifecycleHandler)shutdownHandler
    NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSURL *dataRootURL;
@property(nonatomic, assign, readonly) PRBridgeLifecycleState lifecycleState;

/// Cancels pending work, releases lifecycle callbacks, and stops the root.
/// Repeated calls return NO and do not invoke callbacks again.
- (BOOL)shutdown;

/// Registers a Foundation callback. Releasing or cancelling the returned token
/// removes the callback; registration is rejected once shutdown begins.
- (nullable PRBridgeObservationToken *)observeInstanceSummariesWithHandler:(PRInstanceSummaryObservationHandler)handler;
- (nullable PRBridgeObservationToken *)observeTaskStatusWithHandler:(PRTaskStatusObservationHandler)handler;

@end

NS_ASSUME_NONNULL_END

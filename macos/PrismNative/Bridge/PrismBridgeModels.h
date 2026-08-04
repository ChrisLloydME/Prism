#import <Foundation/Foundation.h>

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

/// Immutable task state that carries progress without exposing a launcher model.
@interface PRTaskStatus : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithIdentifier:(NSString *)identifier
                                       state:(PRTaskState)state
                                progressKind:(PRTaskProgressKind)progressKind
                            progressFraction:(double)progressFraction
                         cancellationAllowed:(BOOL)cancellationAllowed NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *identifier;
@property(nonatomic, assign, readonly) PRTaskState state;
@property(nonatomic, assign, readonly) PRTaskProgressKind progressKind;
@property(nonatomic, assign, readonly) double progressFraction;
@property(nonatomic, assign, readonly) BOOL cancellationAllowed;

@end

NS_ASSUME_NONNULL_END

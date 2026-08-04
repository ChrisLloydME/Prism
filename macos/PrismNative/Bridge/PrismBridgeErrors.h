#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const PRBridgeErrorDomain;

typedef NS_ENUM(NSInteger, PRBridgeErrorCode) {
    PRBridgeErrorCodeUnknown = 1,
    PRBridgeErrorCodeInvalidInput = 2,
    PRBridgeErrorCodeDataUnavailable = 3,
    PRBridgeErrorCodeAuthenticationRequired = 4,
    PRBridgeErrorCodeOperationCancelled = 5,
    PRBridgeErrorCodePermissionDenied = 6,
    PRBridgeErrorCodeNetworkUnavailable = 7,
};

typedef NS_ENUM(NSInteger, PRBridgeErrorRecoveryKind) {
    PRBridgeErrorRecoveryKindNone = 0,
    PRBridgeErrorRecoveryKindRetry = 1,
    PRBridgeErrorRecoveryKindAuthenticate = 2,
    PRBridgeErrorRecoveryKindChooseFile = 3,
    PRBridgeErrorRecoveryKindRevealPath = 4,
    PRBridgeErrorRecoveryKindOpenSettings = 5,
};

FOUNDATION_EXPORT NSString *const PRBridgeErrorLocalizationKeyUserInfoKey;
FOUNDATION_EXPORT NSString *const PRBridgeErrorSubstitutionValuesUserInfoKey;
FOUNDATION_EXPORT NSString *const PRBridgeErrorDiagnosticTextUserInfoKey;
FOUNDATION_EXPORT NSString *const PRBridgeErrorRecoveryKindUserInfoKey;
FOUNDATION_EXPORT NSString *const PRBridgeErrorPartialChangesRolledBackUserInfoKey;

/// Immutable bridge error metadata. User-visible text is resolved from the
/// localization key; diagnostic text is optional and intended only for safe
/// logs or recovery diagnostics.
@interface PRBridgeError : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithCode:(PRBridgeErrorCode)code
                         localizationKey:(NSString *)localizationKey
                     substitutionValues:(NSDictionary<NSString *, NSString *> *)substitutionValues
                         diagnosticText:(nullable NSString *)diagnosticText
                            recoveryKind:(PRBridgeErrorRecoveryKind)recoveryKind
               partialChangesRolledBack:(BOOL)partialChangesRolledBack NS_DESIGNATED_INITIALIZER;

@property(nonatomic, copy, readonly) NSString *domain;
@property(nonatomic, assign, readonly) PRBridgeErrorCode code;
@property(nonatomic, copy, readonly) NSString *localizationKey;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *substitutionValues;
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;
@property(nonatomic, assign, readonly) PRBridgeErrorRecoveryKind recoveryKind;
@property(nonatomic, assign, readonly) BOOL partialChangesRolledBack;
@property(nonatomic, copy, readonly) NSError *foundationError;

@end

NS_ASSUME_NONNULL_END

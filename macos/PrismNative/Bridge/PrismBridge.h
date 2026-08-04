#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Stable Objective-C surface between Swift and the existing C++ launcher core.
/// Qt and C++ types must not cross this boundary.
@interface PRApplicationIdentity : NSObject

@property(nonatomic, copy, readonly) NSString *bundleIdentifier;
@property(nonatomic, copy, readonly) NSString *applicationName;
@property(nonatomic, copy, readonly) NSURL *applicationSupportDirectory;

@end

NS_ASSUME_NONNULL_END

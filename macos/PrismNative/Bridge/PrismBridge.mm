#import "PrismBridge.h"

namespace {
NSString *const kPrismApplicationName = @"Prism";
}

@implementation PRApplicationIdentity

- (NSString *)bundleIdentifier
{
    return NSBundle.mainBundle.bundleIdentifier ?: @"";
}

- (NSString *)applicationName
{
    return kPrismApplicationName;
}

- (NSURL *)applicationSupportDirectory
{
    NSURL *baseURL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
                                                            inDomain:NSUserDomainMask
                                                   appropriateForURL:nil
                                                              create:NO
                                                               error:nil];
    return [baseURL URLByAppendingPathComponent:kPrismApplicationName isDirectory:YES];
}

@end

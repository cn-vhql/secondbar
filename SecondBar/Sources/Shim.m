#import "Shim.h"
#import <dlfcn.h>
#import <objc/message.h>

static NSString *const SBErrorDomain = @"SecondBar.Hiding";

static NSError *SBError(NSString *reason) {
    return [NSError errorWithDomain:SBErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: reason}];
}

static NSString *const SBFrameworkPath = @"/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore";
static NSString *const SBConfigurationClass = @"MBAssessmentModeConfiguration";
static NSString *const SBAssertionClass = @"MBAssessmentModeAssertion";

static SEL SBConfigurationInit(void) { return @selector(initWithAllowedSystemItems:allowedBundleIdentifiers:); }
static SEL SBActivate(void) { return @selector(activateWithConfiguration:completionHandler:); }
static SEL SBInvalidate(void) { return @selector(invalidate); }

BOOL SBHidingIsAvailable(void) {
    if (!dlopen(SBFrameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL)) { return NO; }
    Class configuration = NSClassFromString(SBConfigurationClass);
    Class assertion = NSClassFromString(SBAssertionClass);
    return configuration && assertion
        && [configuration instancesRespondToSelector:SBConfigurationInit()]
        && [assertion instancesRespondToSelector:SBActivate()]
        && [assertion instancesRespondToSelector:SBInvalidate()];
}

void SBHidingActivate(NSArray<NSNumber *> *allowedSystemItems,
                      NSArray<NSString *> *allowedBundleIdentifiers,
                      void (^completion)(id _Nullable assertion, NSError * _Nullable error)) {
    void (^finish)(id, NSError *) = ^(id assertion, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(assertion, error); });
    };
    if (!SBHidingIsAvailable()) {
        finish(nil, SBError(@"MenuBarClientCore is unavailable on this macOS"));
        return;
    }
    @try {
        // Both lists must be NSArrays: the framework indexes into them.
        id configuration = ((id (*)(id, SEL, NSArray *, NSArray *))objc_msgSend)(
            [NSClassFromString(SBConfigurationClass) alloc], SBConfigurationInit(),
            [allowedSystemItems copy], [allowedBundleIdentifiers copy]);
        id assertion = [[NSClassFromString(SBAssertionClass) alloc] init];
        if (!configuration || !assertion) {
            finish(nil, SBError(@"Could not create the visibility configuration"));
            return;
        }
        ((void (*)(id, SEL, id, void (^)(NSError *)))objc_msgSend)(
            assertion, SBActivate(), configuration, ^(NSError *error) {
                finish(error ? nil : assertion, error);
            });
    } @catch (NSException *exception) {
        finish(nil, SBError([NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]));
    }
}

void SBHidingInvalidate(id assertion) {
    @try {
        if ([assertion respondsToSelector:SBInvalidate()]) {
            ((void (*)(id, SEL))objc_msgSend)(assertion, SBInvalidate());
        }
    } @catch (NSException *exception) {
        NSLog(@"SecondBar: invalidate raised %@: %@", exception.name, exception.reason);
    }
}

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Boundary to macOS 27's private MenuBarClientCore framework (the assessment-mode
// menu bar allow list). Resolved at runtime so an OS change degrades to
// "unavailable" instead of a launch failure.

// Whether the framework and every selector used below resolve.
BOOL SBHidingIsAvailable(void);

// Keeps only the given system items and apps visible; macOS hides every other
// status item and reflows the bar. Completion runs on the main queue with the
// assertion to hold (hiding lasts until it is invalidated or the process exits),
// or with an error.
void SBHidingActivate(NSArray<NSNumber *> *allowedSystemItems,
                      NSArray<NSString *> *allowedBundleIdentifiers,
                      void (^completion)(id _Nullable assertion, NSError * _Nullable error));

void SBHidingInvalidate(id assertion);

NS_ASSUME_NONNULL_END

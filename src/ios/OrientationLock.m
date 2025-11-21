#import <objc/runtime.h>
#import "MainViewController.h"

// Static flag to control orientation dynamically
static BOOL isRPSScreenActive = NO;

@implementation MainViewController (OrientationLock)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];

        SEL originalSelector = @selector(supportedInterfaceOrientations);
        SEL swizzledSelector = @selector(my_supportedInterfaceOrientations);

        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(self, swizzledSelector);

        method_exchangeImplementations(originalMethod, swizzledMethod);
    });
}

- (UIInterfaceOrientationMask)my_supportedInterfaceOrientations {
    // If RPS screen is active, force landscape only
    if (isRPSScreenActive) {
        return UIInterfaceOrientationMaskLandscapeLeft;
    }

    // Otherwise, respect the config.xml settings (portrait)
    return UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown;
}

// Public methods to control orientation state
+ (void)setRPSScreenActive:(BOOL)active {
    isRPSScreenActive = active;

    // Force orientation update
    if (@available(iOS 16.0, *)) {
        [UIViewController attemptRotationToDeviceOrientation];
    } else {
        [[UIDevice currentDevice] setValue:@(UIInterfaceOrientationUnknown) forKey:@"orientation"];
        [[UIDevice currentDevice] setValue:@(active ? UIInterfaceOrientationLandscapeLeft : UIInterfaceOrientationPortrait) forKey:@"orientation"];
    }
}

+ (BOOL)isRPSScreenActive {
    return isRPSScreenActive;
}

@end

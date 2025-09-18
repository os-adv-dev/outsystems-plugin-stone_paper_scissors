#import <objc/runtime.h>
#import "MainViewController.h"

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
    // 🔒 force only Landscape Left
    return UIInterfaceOrientationMaskLandscapeLeft;
}

@end
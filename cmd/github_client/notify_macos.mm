// Notifications posted by the app itself, so macOS shows them as from
// MoonBit GitHub Client with its icon rather than from Script Editor, as
// `osascript` notifications are. Only an app bundle signed with a valid
// certificate can use the UserNotifications framework; a process that is
// not a bundle gets 0 from gc_native_notify and falls back to osascript.

#ifdef __APPLE__
#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>

// Shows notifications while the app is in front too; macOS hides them by
// default for the frontmost app.
@interface GcNotificationDelegate : NSObject <UNUserNotificationCenterDelegate>
@end

@implementation GcNotificationDelegate
- (void)userNotificationCenter:(UNUserNotificationCenter*)center
       willPresentNotification:(UNNotification*)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
  completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList |
                    UNNotificationPresentationOptionSound);
}

- (void)userNotificationCenter:(UNUserNotificationCenter*)center
    didReceiveNotificationResponse:(UNNotificationResponse*)response
             withCompletionHandler:(void (^)(void))completionHandler {
  completionHandler();
}
@end

static UNUserNotificationCenter* gc_notification_center(void) {
  static UNUserNotificationCenter* center = nil;
  static GcNotificationDelegate* delegate = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    center = [UNUserNotificationCenter currentNotificationCenter];
    delegate = [[GcNotificationDelegate alloc] init];
    center.delegate = delegate;
  });
  return center;
}

// Whether the person allows notifications now. Asked on every post, since
// they can change it in System Settings while the app runs. The answer
// comes on another queue, so waiting here does not block it.
static UNAuthorizationStatus gc_authorization_status(UNUserNotificationCenter* center) {
  __block UNAuthorizationStatus status = UNAuthorizationStatusNotDetermined;
  dispatch_semaphore_t answered = dispatch_semaphore_create(0);
  [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* settings) {
    status = settings.authorizationStatus;
    dispatch_semaphore_signal(answered);
  }];
  dispatch_semaphore_wait(answered, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
#if !__has_feature(objc_arc)
  dispatch_release(answered);
#endif
  return status;
}

// Posts a notification. 1 when it was handed to macOS, 2 when the person
// turned notifications off for the app, and 0 when this process is not an
// app bundle, so the caller falls back to osascript.
extern "C" int gc_native_notify(const char* title, const char* subtitle, const char* body) {
  @autoreleasepool {
    if ([[NSBundle mainBundle] bundleIdentifier] == nil) return 0;
    UNUserNotificationCenter* center = gc_notification_center();
    UNAuthorizationStatus status = gc_authorization_status(center);
    if (status == UNAuthorizationStatusDenied) {
      NSLog(@"notification: turned off in System Settings");
      return 2;
    }
    if (status == UNAuthorizationStatusNotDetermined) {
      // The first notification asks the person; it shows once they allow.
      [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                            completionHandler:^(BOOL granted, NSError* error) {
                              NSLog(@"notification: allowed=%d%@", granted,
                                    error != nil ? [@" " stringByAppendingString:error.description] : @"");
                            }];
    }
    UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
    content.title = [NSString stringWithUTF8String:title];
    content.subtitle = [NSString stringWithUTF8String:subtitle];
    content.body = [NSString stringWithUTF8String:body];
    content.sound = [UNNotificationSound soundNamed:@"Glass"];
    UNNotificationRequest* request = [UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString]
                                                                          content:content
                                                                          trigger:nil];
    [center addNotificationRequest:request
             withCompletionHandler:^(NSError* error) {
               if (error != nil) {
                 NSLog(@"notification: macOS did not take it: %@", error);
               } else {
                 NSLog(@"notification: handed to macOS");
               }
             }];
#if !__has_feature(objc_arc)
    [content release];
#endif
    return 1;
  }
}
#else
extern "C" int gc_native_notify(const char*, const char*, const char*) { return 0; }
#endif

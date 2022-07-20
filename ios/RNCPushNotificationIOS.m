/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "RNCPushNotificationIOS.h"
#import "RCTConvert+Notification.h"
#import <React/RCTBridge.h>
#import <React/RCTConvert.h>
#import <React/RCTEventDispatcher.h>

NSString *const RCTRemoteNotificationReceived = @"RemoteNotificationReceived";

static NSString *const kLocalNotificationReceived = @"LocalNotificationReceived";
static NSString *const kRemoteNotificationsRegistered = @"RemoteNotificationsRegistered";
static NSString *const kRemoteNotificationRegistrationFailed = @"RemoteNotificationRegistrationFailed";

static NSString *const kErrorUnableToRequestPermissions = @"E_UNABLE_TO_REQUEST_PERMISSIONS";

#if !TARGET_OS_TV
@interface RNCPushNotificationIOS ()
@property (nonatomic, strong) NSMutableDictionary *remoteNotificationCallbacks;
@end


#else
@interface RNCPushNotificationIOS () <NativePushNotificationManagerIOS>
@end
#endif //TARGET_OS_TV

@implementation RNCPushNotificationIOS

RCT_EXPORT_MODULE()

- (dispatch_queue_t)methodQueue
{
  return dispatch_get_main_queue();
}

#if !TARGET_OS_TV
- (void)startObserving
{
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleLocalNotificationReceived:)
                                               name:kLocalNotificationReceived
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleRemoteNotificationReceived:)
                                               name:RCTRemoteNotificationReceived
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleRemoteNotificationsRegistered:)
                                               name:kRemoteNotificationsRegistered
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleRemoteNotificationRegistrationError:)
                                               name:kRemoteNotificationRegistrationFailed
                                             object:nil];
}

- (void)stopObserving
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSArray<NSString *> *)supportedEvents
{
  return @[@"localNotificationReceived",
           @"remoteNotificationReceived",
           @"remoteNotificationsRegistered",
           @"remoteNotificationRegistrationError"];
}

+ (void)didRegisterUserNotificationSettings:(__unused UIUserNotificationSettings *)notificationSettings
{
}

+ (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
  NSMutableString *hexString = [NSMutableString string];
  NSUInteger deviceTokenLength = deviceToken.length;
  const unsigned char *bytes = deviceToken.bytes;
  for (NSUInteger i = 0; i < deviceTokenLength; i++) {
    [hexString appendFormat:@"%02x", bytes[i]];
  }
  [[NSNotificationCenter defaultCenter] postNotificationName:kRemoteNotificationsRegistered
                                                      object:self
                                                    userInfo:@{@"deviceToken" : [hexString copy]}];
}

+ (void)didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
  [[NSNotificationCenter defaultCenter] postNotificationName:kRemoteNotificationRegistrationFailed
                                                      object:self
                                                    userInfo:@{@"error": error}];
}

+ (void)didReceiveRemoteNotification:(NSDictionary *)notification
{
  NSDictionary *userInfo = @{@"notification": notification};
  [[NSNotificationCenter defaultCenter] postNotificationName:RCTRemoteNotificationReceived
                                                      object:self
                                                    userInfo:userInfo];
}

+ (void)didReceiveRemoteNotification:(NSDictionary *)notification
              fetchCompletionHandler:(RNCRemoteNotificationCallback)completionHandler
{
  NSDictionary *userInfo = @{@"notification": notification, @"completionHandler": completionHandler};
  [[NSNotificationCenter defaultCenter] postNotificationName:RCTRemoteNotificationReceived
                                                      object:self
                                                    userInfo:userInfo];
}

+ (void)didReceiveLocalNotification:(UILocalNotification *)notification
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kLocalNotificationReceived
                                                      object:self
                                                    userInfo:[RCTConvert RCTFormatLocalNotification:notification]];
}

+ (void)didReceiveNotificationResponse:(UNNotificationResponse *)response
API_AVAILABLE(ios(10.0)) {
    _handleNotificationResponseReceived(response); // Custom Notification by Nyan
    [[NSNotificationCenter defaultCenter] postNotificationName:kLocalNotificationReceived
                                                      object:self
                                                    userInfo:[RCTConvert RCTFormatUNNotificationResponse:response]];
}

- (void)handleLocalNotificationReceived:(NSNotification *)notification
{
  [self sendEventWithName:@"localNotificationReceived" body:notification.userInfo];
}

- (void)handleRemoteNotificationReceived:(NSNotification *)notification
{
  NSMutableDictionary *remoteNotification = [NSMutableDictionary dictionaryWithDictionary:notification.userInfo[@"notification"]];
  RNCRemoteNotificationCallback completionHandler = notification.userInfo[@"completionHandler"];
  NSString *notificationId = [[NSUUID UUID] UUIDString];
  remoteNotification[@"notificationId"] = notificationId;
  remoteNotification[@"remote"] = @YES;
  if (completionHandler) {
    if (!self.remoteNotificationCallbacks) {
      // Lazy initialization
      self.remoteNotificationCallbacks = [NSMutableDictionary dictionary];
    }
    self.remoteNotificationCallbacks[notificationId] = completionHandler;
  }
  
  [self sendEventWithName:@"remoteNotificationReceived" body:remoteNotification];
}

- (void)handleRemoteNotificationsRegistered:(NSNotification *)notification
{
  [self sendEventWithName:@"remoteNotificationsRegistered" body:notification.userInfo];
}

- (void)handleRemoteNotificationRegistrationError:(NSNotification *)notification
{
  NSError *error = notification.userInfo[@"error"];
  NSDictionary *errorDetails = @{
    @"message": error.localizedDescription,
    @"code": @(error.code),
    @"details": error.userInfo,
  };
  [self sendEventWithName:@"remoteNotificationRegistrationError" body:errorDetails];
}

#pragma mark - Custom Notification by Nyan
/* begin History in File Storage */
// https://github.com/react-native-async-storage/async-storage/blob/master/ios/RNCAsyncStorage.m#L129
static NSString *const RCTStorageDirectory = @"RCTStorageDirectory_v1";
static NSString *const RCTManifestFileName = @"manifest.json";
static NSString *const historiesKey = @"histories";

static NSString *RCTCreateStorageDirectoryPath(NSString *storageDir)
{
    NSString *storageDirectoryPath = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    // We should use the "Application Support/[bundleID]" folder for persistent data storage that's hidden from users
    storageDirectoryPath = [storageDirectoryPath stringByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]];
    // Per Apple's docs, all app content in Application Support must be within a subdirectory of the app's bundle identifier
    storageDirectoryPath = [storageDirectoryPath stringByAppendingPathComponent:storageDir];
    return storageDirectoryPath;
}

static NSString *RCTGetStorageDirectory()
{
    static NSString *storageDirectory = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      storageDirectory = RCTCreateStorageDirectoryPath(RCTStorageDirectory);
    });
    return storageDirectory;
}

static NSString *RCTCreateManifestFilePath(NSString *storageDirectory)
{
    return [storageDirectory stringByAppendingPathComponent:RCTManifestFileName];
}

static NSString *RCTGetManifestFilePath()
{
    static NSString *manifestFilePath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      manifestFilePath = RCTCreateManifestFilePath(RCTStorageDirectory);
    });
    return manifestFilePath;
}

static void _addHistoryToFileStorage(NSDictionary *history) {
    if (!history) return;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *directoryPath = RCTGetStorageDirectory();
    BOOL isDir;
    BOOL storageDirectoryExists = [fileManager fileExistsAtPath:directoryPath isDirectory:&isDir] && isDir;
    if (!storageDirectoryExists) {
        NSError *_error;
        [fileManager createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:&_error];
        if (_error) {
            NSLog(@"Failed to create storage directory %@", _error);
            return;
        }
        NSLog(@"---Create folder success");
    }
    
    NSArray *historiesFromFile = _getHistoriesFromFileStorage();
    NSMutableArray *histories = [[NSMutableArray alloc]init];
    if (historiesFromFile) {
        histories = [historiesFromFile mutableCopy];
    }
    [histories addObject:history];
    NSDictionary *object = [NSDictionary dictionaryWithObject:histories forKey:historiesKey];

    NSError *error;
    NSString *filePath = RCTCreateStorageDirectoryPath(RCTGetManifestFilePath());
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:object];
    [data writeToFile:filePath options:NSDataWritingAtomic error:&error];
    if (error) {
        NSLog(@"Fail to add history %@", error);
        return;
    }
}

static inline NSArray* _getHistoriesFromFileStorage() {
    NSString *filePath = RCTCreateStorageDirectoryPath(RCTGetManifestFilePath());
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSData *archivedData = [NSData dataWithContentsOfFile:filePath];
        NSDictionary *object = (NSDictionary*) [NSKeyedUnarchiver unarchiveObjectWithData:archivedData];
        NSArray *histories = (NSArray*) [object objectForKey:historiesKey];
        return histories;
    }
    return nil;
}

static void _removeStorageDirectory()
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *directoryPath = RCTGetStorageDirectory();
    BOOL isDir;
    BOOL storageDirectoryExists = [fileManager fileExistsAtPath:directoryPath isDirectory:&isDir] && isDir;
    if (storageDirectoryExists) {
        NSError *error;
        [fileManager removeItemAtPath:directoryPath error:&error];
        if (error) {
            NSLog(@"Failed to delete storage directory %@", error);
        }
    }
}

RCT_EXPORT_METHOD(loadHistoriesFromFileStorage:(RCTResponseSenderBlock)callback)
{
    NSArray *histories = _getHistoriesFromFileStorage();
    callback(@[RCTNullIfNil(histories)]);
}

RCT_EXPORT_METHOD(removeHistoriesInFileStorage)
{
    _removeStorageDirectory();
}
/* end History in File Storage */

/* begin Notification actions & Details in User Defaults */
static NSString *const detailsDataKey = @"detailsData"; // only ios
static NSString *const focusActionId = @"id-action-focus"; // NotificationActionId.Focus
static NSString *const relaxActionId = @"id-action-relax"; // NotificationActionId.Relax
static NSString *const finishFocusId = @"id-notification-finish-focus"; // NotificationId.FinishFocus
static NSString *const finishShortBreakId = @"id-notification-finish-short-break"; // NotificationId.FinishShortBreak
static NSString *const finishLongBreakId = @"id-notification-finish-long-break"; // NotificationId.FinishLongBreak
static NSString *const statusFocusing = @"focusing"; // PomoStatus.Focusing
static NSString *const statusRelaxing = @"relaxing"; // PomoStatus.Relaxing
static NSString *const typeFocus = @"focus"; // PomoType.Focus
static NSString *const typeRelax = @"relax"; // PomoType.Relax

static NSString *const shortBreakTitle = @"SHORT BREAK";
static NSString *const shortBreakBody =@"Just relax, back to work after a cup of TEA! ☕";
static NSString *const longBreakTitle = @"LONG BREAK";
static NSString *const longBreakBody = @"Good job! Let's treat yourself a LONG RELAX! 😉";
static NSString *const focusAfterShortBreakTitle = @"TIME TO REFOCUS";
static NSString *const focusAfterShortBreakBody = @"You're invincible today! 👑";
static NSString *const focusAfterLongBreakTitle = @"KEEP IT GOING";
static NSString *const focusAfterLongBreakBody = @"Keep the spirit going!!! Let's start new a pomo! 🤓";
static NSString *const nextBreakMessage = @"Your next break is";
static NSString *const nextPomoMessage = @"Your next pomo is";

static void _handleNotificationResponseReceived(UNNotificationResponse *response) {
    if ([response.actionIdentifier isEqualToString:focusActionId] || [response.actionIdentifier isEqualToString:relaxActionId]) {
        NSDictionary *detailsFromUserDefaults = _getDetailsFromUserDefaults();
        NSMutableDictionary *userInfo = [response.notification.request.content.userInfo mutableCopy];
        NSMutableDictionary *details = [detailsFromUserDefaults ? detailsFromUserDefaults : [userInfo objectForKey:@"details"] mutableCopy];

        NSTimeInterval nowInMillis = [[NSDate date] timeIntervalSince1970] * 1000; // NSTimeInterval is double
        NSNumber *currentFireDate = [details objectForKey:@"fireDate"];
        BOOL isFocus = [response.actionIdentifier isEqualToString:focusActionId];

        // if don't have any pending notification
        if (!currentFireDate || (currentFireDate && currentFireDate.doubleValue <= nowInMillis)) {
            NSDictionary *history = [details objectForKey:@"history"];
            NSDictionary *pomo = [details objectForKey:@"pomo"];
            UNMutableNotificationContent *content = [response.notification.request.content mutableCopy];

            // 1. update details
            NSNumber *numOfSet = [pomo objectForKey:@"numOfSet"];
            NSNumber *currentIndex = [details objectForKey:@"currentIndex"];
            BOOL isLongBreak = numOfSet.intValue == currentIndex.intValue;

            NSNumber *focusTime = [pomo objectForKey:@"focusTime"];
            NSNumber *breakTime = [pomo objectForKey:isLongBreak ? @"longBreakTime" : @"shortBreakTime"];
            double timeInSeconds = [isFocus ? focusTime : breakTime doubleValue] * 60;
            NSNumber *startedAt = [NSNumber numberWithDouble:nowInMillis];
            NSNumber *fireDate = [NSNumber numberWithDouble:nowInMillis + timeInSeconds * 1000];

            [details setValue:isFocus ? statusFocusing : statusRelaxing forKey:@"status"];
            [details setValue:startedAt forKey:@"startedAt"];
            [details setValue:fireDate forKey:@"fireDate"];
            NSDictionary *newHistory = [[NSDictionary alloc] initWithObjectsAndKeys:[pomo objectForKey:@"name"],@"name", [pomo objectForKey:@"color"],@"color", isFocus ? typeFocus : typeRelax,@"type", startedAt,@"startedAt", fireDate,@"finishedAt",nil];
            [details setValue:newHistory forKey:@"history"];
            if (isFocus) {
                [details setValue:[NSNumber numberWithInt:isLongBreak ? 1 : currentIndex.intValue + 1] forKey:@"currentIndex"];
            }
            
            // 2. add Notification
            [userInfo setValue:details forKey:@"details"];
            content.userInfo = userInfo;
            NSString *unit = [isFocus ? breakTime : focusTime isEqualToNumber:[NSNumber numberWithDouble:1]] ? @"min" : @"mins";
            if (isFocus) {
                content.categoryIdentifier = finishFocusId;
                content.title = isLongBreak ? longBreakTitle : shortBreakTitle;
                content.body = [NSString stringWithFormat:@"%@\r\r%@ %@ %@", isLongBreak ? longBreakBody : shortBreakBody, nextBreakMessage, breakTime, unit];
            } else {
                content.categoryIdentifier = isLongBreak ? finishLongBreakId : finishShortBreakId;
                content.title = isLongBreak ? focusAfterLongBreakTitle : focusAfterShortBreakTitle;
                content.body = [NSString stringWithFormat:@"%@\r\r%@ %@ %@", isLongBreak ? focusAfterLongBreakBody : focusAfterShortBreakBody, nextPomoMessage, focusTime, unit];
            }
            
            UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:timeInSeconds repeats:FALSE];
            UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:content.categoryIdentifier content:content trigger:trigger];
            UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
            [center addNotificationRequest:request
                     withCompletionHandler:^(NSError* _Nullable error) {
                if (!error) {
                    // 3. store details, history
                    _setDetailsToUserDefaults(details);
                    _addHistoryToFileStorage(history);
                    }
                }
            ];
        }
    }
}

RCT_EXPORT_METHOD(loadDetailsFromUserDefaults:(RCTResponseSenderBlock)callback)
{
    _getHistoriesFromFileStorage();
    NSDictionary *details = _getDetailsFromUserDefaults();
    callback(@[RCTNullIfNil(details)]);
}

RCT_EXPORT_METHOD(storeDetailsToUserDefaults:(NSDictionary *)details)
{
    _setDetailsToUserDefaults(details);
}

static inline NSDictionary* _getDetailsFromUserDefaults() {
    NSData *archivedData = [[NSUserDefaults standardUserDefaults]
        dataForKey:detailsDataKey];
    NSDictionary *details = (NSDictionary*) [NSKeyedUnarchiver unarchiveObjectWithData:archivedData];
    return details;
}

static inline void _setDetailsToUserDefaults(NSDictionary *details)
{
    NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:details];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:archivedData forKey:detailsDataKey];
    [defaults synchronize];
}
/* end Notification actions & Details in User Defaults */

RCT_EXPORT_METHOD(onFinishRemoteNotification:(NSString *)notificationId fetchResult:(UIBackgroundFetchResult)result)
{
  [self.remoteNotificationCallbacks removeObjectForKey:notificationId];
}

/**
 * Update the application icon badge number on the home screen
 */
RCT_EXPORT_METHOD(setApplicationIconBadgeNumber:(NSInteger)number)
{
  RCTSharedApplication().applicationIconBadgeNumber = number;
}

/**
 * Get the current application icon badge number on the home screen
 */
RCT_EXPORT_METHOD(getApplicationIconBadgeNumber:(RCTResponseSenderBlock)callback)
{
  callback(@[@(RCTSharedApplication().applicationIconBadgeNumber)]);
}

RCT_EXPORT_METHOD(requestPermissions:(NSDictionary *)permissions
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  if (RCTRunningInAppExtension()) {
    reject(kErrorUnableToRequestPermissions, nil, RCTErrorWithMessage(@"Requesting push notifications is currently unavailable in an app extension"));
    return;
  }
    
  // Add a listener to make sure that startObserving has been called
  [self addListener:@"remoteNotificationsRegistered"];
  
  UNAuthorizationOptions types = UNAuthorizationOptionNone;
  if (permissions) {
    if ([RCTConvert BOOL:permissions[@"alert"]]) {
      types |= UNAuthorizationOptionAlert;
    }
    if ([RCTConvert BOOL:permissions[@"badge"]]) {
      types |= UNAuthorizationOptionBadge;
    }
    if ([RCTConvert BOOL:permissions[@"sound"]]) {
      types |= UNAuthorizationOptionSound;
    }
    if (@available(iOS 12, *)) {
        if ([RCTConvert BOOL:permissions[@"critical"]]) {
            types |= UNAuthorizationOptionCriticalAlert;
        }
    }
  } else {
    types = UNAuthorizationOptionAlert | UNAuthorizationOptionBadge | UNAuthorizationOptionSound;
  }
  
  [UNUserNotificationCenter.currentNotificationCenter
    requestAuthorizationWithOptions:types
    completionHandler:^(BOOL granted, NSError *_Nullable error) {

    if (error != NULL) {
      reject(@"-1", @"Error - Push authorization request failed.", error);
    } else {
      dispatch_async(dispatch_get_main_queue(), ^(void){
        [RCTSharedApplication() registerForRemoteNotifications];
      });
      [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
        resolve(RCTPromiseResolveValueForUNNotificationSettings(settings));
      }];
    }
  }];
}

RCT_EXPORT_METHOD(abandonPermissions)
{
  [RCTSharedApplication() unregisterForRemoteNotifications];
}

RCT_EXPORT_METHOD(checkPermissions:(RCTResponseSenderBlock)callback)
{
  if (RCTRunningInAppExtension()) {
    callback(@[RCTSettingsDictForUNNotificationSettings(NO, NO, NO, NO, NO, NO, UNAuthorizationStatusNotDetermined)]);
    return;
  }
  
  [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
    callback(@[RCTPromiseResolveValueForUNNotificationSettings(settings)]);
    }];
  }

static inline NSDictionary *RCTPromiseResolveValueForUNNotificationSettings(UNNotificationSettings* _Nonnull settings) {
  return RCTSettingsDictForUNNotificationSettings(settings.alertSetting == UNNotificationSettingEnabled,
                                                  settings.badgeSetting == UNNotificationSettingEnabled,
                                                  settings.soundSetting == UNNotificationSettingEnabled,
                                                  @available(iOS 12, *) && settings.criticalAlertSetting == UNNotificationSettingEnabled,
                                                  settings.lockScreenSetting == UNNotificationSettingEnabled,
                                                  settings.notificationCenterSetting == UNNotificationSettingEnabled,
                                                  settings.authorizationStatus);
  }

static inline NSDictionary *RCTSettingsDictForUNNotificationSettings(BOOL alert, BOOL badge, BOOL sound, BOOL critical, BOOL lockScreen, BOOL notificationCenter, UNAuthorizationStatus authorizationStatus) {
  return @{@"alert": @(alert), @"badge": @(badge), @"sound": @(sound), @"critical": @(critical), @"lockScreen": @(lockScreen), @"notificationCenter": @(notificationCenter), @"authorizationStatus": @(authorizationStatus)};
  }

/**
 * Method deprecated in iOS 10.0
 * TODO: This method will be removed in the next major version
 */
RCT_EXPORT_METHOD(presentLocalNotification:(UILocalNotification *)notification)
{
  [RCTSharedApplication() presentLocalNotificationNow:notification];
}

/**
 * Method deprecated in iOS 10.0
 * TODO: This method will be removed in the next major version
 */
RCT_EXPORT_METHOD(scheduleLocalNotification:(UILocalNotification *)notification)
{
  [RCTSharedApplication() scheduleLocalNotification:notification];
}

RCT_EXPORT_METHOD(addNotificationRequest:(UNNotificationRequest*)request)
{
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    NSString *imageUrl = request.content.userInfo[@"image"];
    NSMutableDictionary *fcmInfo = request.content.userInfo[@"fcm_options"];
    if(fcmInfo != nil && fcmInfo[@"image"] != nil) {
        imageUrl = fcmInfo[@"image"];
    }
    if(imageUrl != nil) {
        NSURL *attachmentURL = [NSURL URLWithString:imageUrl];
        [self loadAttachmentForUrl:attachmentURL completionHandler:^(UNNotificationAttachment *attachment) {
            if (attachment) {
                UNMutableNotificationContent *bestAttemptRequest = [request.content mutableCopy];
                [bestAttemptRequest setAttachments: [NSArray arrayWithObject:attachment]];
                UNNotificationRequest* notification = [UNNotificationRequest requestWithIdentifier:request.identifier content:bestAttemptRequest trigger:request.trigger];
                [center addNotificationRequest:notification
                            withCompletionHandler:^(NSError* _Nullable error) {
                    if (!error) {
                        NSLog(@"image notifier request success");
                        }
                    }
                ];
            }
        }];
    } else {
        [center addNotificationRequest:request
                 withCompletionHandler:^(NSError* _Nullable error) {
            if (!error) {
                NSLog(@"notifier request success");
                }
            }
        ];
    }
    
}

- (void)loadAttachmentForUrl:(NSURL *)attachmentURL
           completionHandler:(void (^)(UNNotificationAttachment *))completionHandler {
  __block UNNotificationAttachment *attachment = nil;

  NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];

  [[session
      downloadTaskWithURL:attachmentURL
        completionHandler:^(NSURL *temporaryFileLocation, NSURLResponse *response, NSError *error) {
          if (error != nil) {
            NSLog( @"Failed to download image given URL %@, error: %@\n", attachmentURL, error);
            completionHandler(attachment);
            return;
          }

          NSFileManager *fileManager = [NSFileManager defaultManager];
          NSString *fileExtension =
              [NSString stringWithFormat:@".%@", [response.suggestedFilename pathExtension]];
          NSURL *localURL = [NSURL
              fileURLWithPath:[temporaryFileLocation.path stringByAppendingString:fileExtension]];
          [fileManager moveItemAtURL:temporaryFileLocation toURL:localURL error:&error];
          if (error) {
            NSLog( @"Failed to move the image file to local location: %@, error: %@\n", localURL, error);
            completionHandler(attachment);
            return;
          }

          attachment = [UNNotificationAttachment attachmentWithIdentifier:@""
                                                                      URL:localURL
                                                                  options:nil
                                                                    error:&error];
          if (error) {
              NSLog(@"Failed to create attachment with URL %@, error: %@\n", localURL, error);
            completionHandler(attachment);
            return;
          }
          completionHandler(attachment);
        }] resume];
}

RCT_EXPORT_METHOD(setNotificationCategories:(NSArray*)categories)
{
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    NSMutableSet<UNNotificationCategory *>* categorySet = nil;
    
    if ([categories count] > 0) {
        categorySet = [NSMutableSet new];
        for(NSDictionary* category in categories){
            [categorySet addObject:[RCTConvert UNNotificationCategory:category]];
        }
    }
    [center setNotificationCategories:categorySet];
}

/**
 * Method not Available in iOS11+
 * TODO: This method will be removed in the next major version
 */
RCT_EXPORT_METHOD(cancelAllLocalNotifications)
{
  [RCTSharedApplication() cancelAllLocalNotifications];
}

RCT_EXPORT_METHOD(removeAllPendingNotificationRequests)
{
    if ([UNUserNotificationCenter class]) {
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        [center removeAllPendingNotificationRequests];
    }
}

RCT_EXPORT_METHOD(removePendingNotificationRequests:(NSArray<NSString *> *)identifiers)
{
    if ([UNUserNotificationCenter class]) {
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        [center removePendingNotificationRequestsWithIdentifiers:identifiers];
    }
}

/**
 * Method deprecated in iOS 10.0
 * TODO: This method will be removed in the next major version
 */
RCT_EXPORT_METHOD(cancelLocalNotifications:(NSDictionary<NSString *, id> *)userInfo)
{
  for (UILocalNotification *notification in RCTSharedApplication().scheduledLocalNotifications) {
    __block BOOL matchesAll = YES;
    NSDictionary<NSString *, id> *notificationInfo = notification.userInfo;
    // Note: we do this with a loop instead of just `isEqualToDictionary:`
    // because we only require that all specified userInfo values match the
    // notificationInfo values - notificationInfo may contain additional values
    // which we don't care about.
    [userInfo enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
      if (![notificationInfo[key] isEqual:obj]) {
        matchesAll = NO;
        *stop = YES;
      }
    }];
    if (matchesAll) {
      [RCTSharedApplication() cancelLocalNotification:notification];
    }
  }
}


RCT_EXPORT_METHOD(getInitialNotification:(RCTPromiseResolveBlock)resolve
                  reject:(__unused RCTPromiseRejectBlock)reject)
{
    NSMutableDictionary<NSString *, id> *initialNotification =
    [self.bridge.launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey] mutableCopy];
    UILocalNotification *initialLocalNotification =
    self.bridge.launchOptions[UIApplicationLaunchOptionsLocalNotificationKey];
  
    if (initialNotification) {
      initialNotification[@"userInteraction"] = [NSNumber numberWithInt:1];
      initialNotification[@"remote"] = @YES;
      resolve(initialNotification);
    } else if (initialLocalNotification) {
      resolve([RCTConvert RCTFormatLocalNotification:initialLocalNotification]);
    } else {
      resolve((id)kCFNull);
    }
}

/**
 * Method deprecated in iOS 10.0
 * TODO: This method will be removed in the next major version
 */
RCT_EXPORT_METHOD(getScheduledLocalNotifications:(RCTResponseSenderBlock)callback)
{
  NSArray<UILocalNotification *> *scheduledLocalNotifications = RCTSharedApplication().scheduledLocalNotifications;
  NSMutableArray<NSDictionary *> *formattedScheduledLocalNotifications = [NSMutableArray new];
  for (UILocalNotification *notification in scheduledLocalNotifications) {
      [formattedScheduledLocalNotifications addObject:[RCTConvert RCTFormatLocalNotification:notification]];
  }
  callback(@[formattedScheduledLocalNotifications]);
}

RCT_EXPORT_METHOD(getPendingNotificationRequests: (RCTResponseSenderBlock)callback)
{
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> *_Nonnull requests) {
      NSMutableArray<NSDictionary *> *formattedRequests = [NSMutableArray new];
      
      for (UNNotificationRequest *request in requests) {
          [formattedRequests addObject:[RCTConvert RCTFormatUNNotificationRequest:request]];
      }
      callback(@[formattedRequests]);
    }];
}

RCT_EXPORT_METHOD(removeAllDeliveredNotifications)
{
  if ([UNUserNotificationCenter class]) {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center removeAllDeliveredNotifications];
  }
}

RCT_EXPORT_METHOD(removeDeliveredNotifications:(NSArray<NSString *> *)identifiers)
{
  if ([UNUserNotificationCenter class]) {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center removeDeliveredNotificationsWithIdentifiers:identifiers];
  }
}

RCT_EXPORT_METHOD(getDeliveredNotifications:(RCTResponseSenderBlock)callback)
{
  if ([UNUserNotificationCenter class]) {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *_Nonnull notifications) {
      NSMutableArray<NSDictionary *> *formattedNotifications = [NSMutableArray new];
      
      for (UNNotification *notification in notifications) {
          [formattedNotifications addObject:[RCTConvert RCTFormatUNNotification:notification]];
      }
      callback(@[formattedNotifications]);
    }];
  }
}

#else //TARGET_OS_TV

RCT_EXPORT_METHOD(onFinishRemoteNotification:(NSString *)notificationId fetchResult:(NSString *)fetchResult)
{
  RCTLogError(@"Not implemented: %@", NSStringFromSelector(_cmd));
}

RCT_EXPORT_METHOD(setApplicationIconBadgeNumber:(double)number)
{
  RCTLogError(@"Not implemented: %@", NSStringFromSelector(_cmd));
}

RCT_EXPORT_METHOD(getApplicationIconBadgeNumber:(RCTResponseSenderBlock)callback)
{
  RCTLogError(@"Not implemented: %@", NSStringFromSelector(_cmd));
}

RCT_EXPORT_METHOD(requestPermissions:(JS::NativePushNotificationManagerIOS::SpecRequestPermissionsPermission &)permissions
                 resolve:(RCTPromiseResolveBlock)resolve
                 reject:(RCTPromiseRejectBlock)reject)
{
  RCTLogError(@"Not implemented: %@", NSStringFromSelector(_cmd));
}

RCT_EXPORT_METHOD(abandonPermissions)
{
  RCTLogError(@"Not implemented: %@", NSStringFromSelector(_cmd));
}

RCT_EXPORT_METHOD(checkPermissions:(RCTResponseSenderBlock)callback)
{
  RCTLogError(@"Not implemented: %@", NSStringFromSelector(_cmd));
}

RCT_EXPORT_METHOD(presentLocalNotification:(JS::NativePushNotificationManagerIOS::Notification &)notification)
{
  RCTLogError(@"Not implemented: %@", NSStringFromSelector(_cmd));
}

RCT_EXPORT_METHOD(scheduleLocalNotification:(JS::NativePushNotificationManagerIOS::Notification &)notification)
{
  RCTLogError(@"Not implemented: %@", NSStringFromSelector(_cmd));
}

RCT_EXPORT_METHOD(cancelAllLocalNotifications)
{
  RCTLogError(@"Not implemented: %@", NSStringFromSelector(_cmd));
}

RCT_EXPORT_METHOD(cancelLocalNotifications:(NSDictionary<NSString *, id> *)userInfo)
{
  RCTLogError(@"Not implemented: %@", NSStringFromSelector(_cmd));
}

RCT_EXPORT_METHOD(getInitialNotification:(RCTPromiseResolveBlock)resolve
                  reject:(__unused RCTPromiseRejectBlock)reject)
{
  RCTLogError(@"Not implemented: %@", NSStringFromSelector(_cmd));
}

RCT_EXPORT_METHOD(getScheduledLocalNotifications:(RCTResponseSenderBlock)callback)
{
  RCTLogError(@"Not implemented: %@", NSStringFromSelector(_cmd));
}

RCT_EXPORT_METHOD(removeAllDeliveredNotifications)
{
  RCTLogError(@"Not implemented: %@", NSStringFromSelector(_cmd));
}

RCT_EXPORT_METHOD(removeDeliveredNotifications:(NSArray<NSString *> *)identifiers)
{
  RCTLogError(@"Not implemented: %@", NSStringFromSelector(_cmd));
}

RCT_EXPORT_METHOD(getDeliveredNotifications:(RCTResponseSenderBlock)callback)
{
  RCTLogError(@"Not implemented: %@", NSStringFromSelector(_cmd));
}


- (NSArray<NSString *> *)supportedEvents
{
  return @[];
}

#endif //TARGET_OS_TV

@end

#import <AppKit/AppKit.h>
#import <UserNotifications/UserNotifications.h>

#include "macos_notifications.h"
#include "macos_achievement_images.h"
#include "desktop_settings.h"
#include "macos_localization.h"
#include <rex/cvar.h>
#include <rex/logging.h>
#include <rex/runtime.h>
#include <rex/system/kernel_state.h>
#include <rex/system/util/xdbf_utils.h>

// Resolve the same metadata/XDBF images used by the in-game achievement list.
NSData* AliceAchievementImage(const rex::system::AchievementInfo& info, rex::Runtime* runtime) {
  if (!runtime) return nil;
  auto metadata = [runtime](const std::filesystem::path& path) -> NSData* {
    if (auto file = runtime->FindMetadataPath(path)) {
      NSString* name = [NSString stringWithUTF8String:file->string().c_str()];
      if (NSData* data = [NSData dataWithContentsOfFile:name]) return data;
    }
    if (auto asset = runtime->FindEmbeddedMetadata(path)) {
      return [NSData dataWithBytes:asset->bytes.data() length:asset->bytes.size()];
    }
    return nil;
  };
  if (!info.icon_path.empty()) {
    if (NSData* data = metadata(info.icon_path)) return data;
  }
  if (info.image_id) {
    if (NSData* data = metadata(std::filesystem::path("icons") /
                               (std::to_string(info.image_id) + ".png"))) return data;
    if (runtime->kernel_state()) {
      auto db = runtime->kernel_state()->title_xdbf();
      if (db.is_valid()) {
        auto block = db.GetEntry(rex::system::util::XdbfSection::kImage, info.image_id);
        if (block) return [NSData dataWithBytes:block.buffer length:block.size];
      }
    }
  }
  return nil;
}

static UNNotificationAttachment* AchievementAttachment(
    const rex::system::AchievementInfo& info, rex::Runtime* runtime) {
  NSData* image = AliceAchievementImage(info, runtime);
  if (!image) return nil;
  NSBitmapImageRep* bitmap = [NSBitmapImageRep imageRepWithData:image];
  NSData* png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
  if (!png) return nil;
  // UserNotifications moves attachments into its own store. Supply a disposable
  // copy inside the project so the game's original image is never moved.
  NSURL* directory = [NSURL fileURLWithPath:[NSString stringWithUTF8String:
      alice::desktop::NotificationDirectory().string().c_str()] isDirectory:YES];
  NSError* error = nil;
  if (![NSFileManager.defaultManager createDirectoryAtURL:directory
      withIntermediateDirectories:YES attributes:nil error:&error]) {
    REXLOG_WARN("[notifications] attachment directory: {}", error.localizedDescription.UTF8String);
    return nil;
  }
  NSURL* file = [directory URLByAppendingPathComponent:
      [NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"png"]];
  if (![png writeToURL:file options:NSDataWritingAtomic error:&error]) {
    REXLOG_WARN("[notifications] attachment write: {}", error.localizedDescription.UTF8String);
    return nil;
  }
  UNNotificationAttachment* attachment = [UNNotificationAttachment
      attachmentWithIdentifier:@"achievement-icon" URL:file
      options:@{UNNotificationAttachmentOptionsThumbnailHiddenKey: @NO} error:&error];
  if (!attachment) {
    REXLOG_WARN("[notifications] attachment rejected: {}", error.localizedDescription.UTF8String);
    [NSFileManager.defaultManager removeItemAtURL:file error:nil];
  }
  return attachment;
}

REXCVAR_DEFINE_BOOL(alice_notification_test, false, "ALICE",
                    "Send a macOS notification without unlocking an achievement");

@interface AliceNotificationDelegate : NSObject <UNUserNotificationCenterDelegate>
@property(nonatomic) BOOL authorizationResolved;
@property(nonatomic) BOOL authorizationStarted;
@property(nonatomic, strong) NSMutableArray<UNNotificationRequest*>* pending;
@end

static void CleanUpAttachments(UNNotificationRequest* request) {
  for (UNNotificationAttachment* attachment in request.content.attachments) {
    // Only delete our disposable source files, never a URL in the system store.
    NSString* directory = [[NSString stringWithUTF8String:
        alice::desktop::NotificationDirectory().string().c_str()] stringByAppendingString:@"/"];
    if ([attachment.URL.path hasPrefix:directory]) {
      [NSFileManager.defaultManager removeItemAtURL:attachment.URL error:nil];
    }
  }
}

static void SubmitNotification(UNNotificationRequest* request) {
  UNUserNotificationCenter* center = UNUserNotificationCenter.currentNotificationCenter;
  [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* settings) {
    if (settings.authorizationStatus != UNAuthorizationStatusAuthorized &&
        settings.authorizationStatus != UNAuthorizationStatusProvisional) {
      REXLOG_WARN("[notifications] macOS notification permission is disabled");
      CleanUpAttachments(request);
      return;
    }
    [center addNotificationRequest:request withCompletionHandler:^(NSError* error) {
      if (error) {
        REXLOG_WARN("[notifications] delivery request failed: {}", error.localizedDescription.UTF8String);
      } else {
        REXLOG_INFO("[notifications] accepted by macOS: {}", request.identifier.UTF8String);
      }
      // The source must remain available until addNotificationRequest finishes.
      CleanUpAttachments(request);
    }];
  }];
}

@implementation AliceNotificationDelegate
- (void)userNotificationCenter:(UNUserNotificationCenter*)center
      willPresentNotification:(UNNotification*)notification
        withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completion {
  completion(UNNotificationPresentationOptionBanner |
             UNNotificationPresentationOptionList |
             UNNotificationPresentationOptionSound);
}
- (void)userNotificationCenter:(UNUserNotificationCenter*)center
       didReceiveNotificationResponse:(UNNotificationResponse*)response
                withCompletionHandler:(void (^)(void))completion {
  NSString* identifier = response.notification.request.identifier;
  BOOL defaultAction = [response.actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier];
  dispatch_async(dispatch_get_main_queue(), ^{
    alice::macos::HandleNotificationAction(identifier.UTF8String ?: "", defaultAction);
  });
  completion();
}
@end

// All delegate state is accessed on the main queue. Retain it because the
// notification center's delegate property is weak.
static AliceNotificationDelegate* notificationDelegate;

static void QueueNotification(UNNotificationRequest* request) {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!notificationDelegate) {
      REXLOG_WARN("[notifications] notification service is not initialized");
      CleanUpAttachments(request);
      return;
    }
    if (!notificationDelegate.authorizationResolved) {
      [notificationDelegate.pending addObject:request];
      return;
    }
    SubmitNotification(request);
  });
}

namespace alice::macos {
bool HandleNotificationAction(std::string_view identifier, bool defaultAction) {
  if (!defaultAction) return false;
  [NSApp activateIgnoringOtherApps:YES];
  constexpr std::string_view prefix = "alice.achievement.";
  if (!identifier.starts_with(prefix) || identifier.size() == prefix.size()) return false;
  alice::desktop::ShowAchievements();
  return true;
}

void PrepareNotificationHandling() {
  if (!NSThread.isMainThread) {
    dispatch_async(dispatch_get_main_queue(), ^{ PrepareNotificationHandling(); });
    return;
  }
  if (notificationDelegate) return;
  notificationDelegate = [AliceNotificationDelegate new];
  notificationDelegate.pending = [NSMutableArray new];
  UNUserNotificationCenter.currentNotificationCenter.delegate = notificationDelegate;
}

static rex::system::AchievementInfo NotificationAchievement(
    const rex::system::AchievementInfo& original, rex::Runtime* runtime) {
  auto info = original;
  if (!runtime || !runtime->kernel_state()) return info;
  auto db = runtime->kernel_state()->title_xdbf();
  if (!db.is_valid()) return info;
  const auto language = alice::desktop::UsesRussian() ?
      rex::system::XLanguage::kRussian : rex::system::XLanguage::kEnglish;
  for (const auto& entry : db.GetAchievements()) {
    if (entry.id != info.id) continue;
    auto translated = [&](uint16_t string_id, const std::string& fallback) {
      std::string text = db.GetStringTableEntry(language, string_id);
      if (text.empty()) text = db.GetStringTableEntry(rex::system::XLanguage::kEnglish, string_id);
      return text.empty() ? fallback : text;
    };
    info.label = translated(entry.label_id, info.label);
    info.description = translated(entry.description_id, info.description);
    break;
  }
  return info;
}

static UNMutableNotificationContent* AchievementContent(const rex::system::AchievementInfo& info) {
  UNMutableNotificationContent* content = [UNMutableNotificationContent new];
  content.title = AliceLocalized(@"Достижение получено");
  content.subtitle = [[NSString alloc] initWithBytes:info.label.data()
      length:info.label.size() encoding:NSUTF8StringEncoding] ?: @"Alice: Madness Returns";
  content.body = [[NSString alloc] initWithBytes:info.description.data()
      length:info.description.size() encoding:NSUTF8StringEncoding] ?: @"";
  content.sound = UNNotificationSound.defaultSound;
  content.threadIdentifier = @"alice-achievements";
  return content;
}

static UNMutableNotificationContent* UnavailableContent(bool legacy) {
  UNMutableNotificationContent* content = [UNMutableNotificationContent new];
  content.title = legacy ? AliceLocalized(@"Хорошая попытка!") : AliceLocalized(@"Функция не поддерживается");
  content.body = legacy ?
      AliceLocalized(@"American McGee's Alice для Xbox 360 невозможен для запуска. Разработка в этом направлении не ведётся") :
      AliceLocalized(@"Downloadable Content недоступен в версии для macOS.");
  content.sound = UNNotificationSound.defaultSound;
  content.threadIdentifier = @"alice-menu";
  return content;
}

void InitializeNotifications() {
  dispatch_async(dispatch_get_main_queue(), ^{
    PrepareNotificationHandling();
    if (notificationDelegate.authorizationStarted) return;
    notificationDelegate.authorizationStarted = YES;
    UNUserNotificationCenter* center = UNUserNotificationCenter.currentNotificationCenter;
    [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound
        completionHandler:^(BOOL granted, NSError* error) {
      if (error) {
        REXLOG_WARN("[notifications] authorization failed: {}", error.localizedDescription.UTF8String);
      }
      REXLOG_INFO("[notifications] permission {}", granted ? "granted" : "denied");
      dispatch_async(dispatch_get_main_queue(), ^{
        notificationDelegate.authorizationResolved = YES;
        NSArray<UNNotificationRequest*>* pending = [notificationDelegate.pending copy];
        [notificationDelegate.pending removeAllObjects];
        for (UNNotificationRequest* request in pending) SubmitNotification(request);
      });
    }];
  });
}

void NotifyAchievement(const rex::system::AchievementEvent& event, rex::Runtime* runtime, bool preview) {
  if (!alice::desktop::AchievementNotificationsEnabled()) return;
  @autoreleasepool {
    const auto info = NotificationAchievement(event.achievement, runtime);
    UNMutableNotificationContent* content = AchievementContent(info);
    if (UNNotificationAttachment* icon = AchievementAttachment(info, runtime)) {
      content.attachments = @[icon];
      REXLOG_INFO("[notifications] attached achievement icon: image {}", info.image_id);
    }
    REXLOG_INFO("[notifications] achievement banner: {} ({} G)", info.label, info.gamerscore);
    NSString* identifier = [NSString stringWithFormat:@"alice.achievement.%u", preview ? UINT32_MAX : info.id];
    UNNotificationRequest* request =
        [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:nil];
    QueueNotification(request);
  }
}

void NotifyLegacyAliceUnavailable() {
  @autoreleasepool {
    UNMutableNotificationContent* content = UnavailableContent(true);
    QueueNotification([UNNotificationRequest requestWithIdentifier:@"alice.legacy-unavailable"
        content:content trigger:nil]);
  }
}

void NotifyDownloadableContentUnavailable() {
  @autoreleasepool {
    UNMutableNotificationContent* content = UnavailableContent(false);
    QueueNotification([UNNotificationRequest requestWithIdentifier:@"alice.dlc-unavailable"
        content:content trigger:nil]);
  }
}

bool NotificationTestRequested() { return REXCVAR_GET(alice_notification_test); }

bool TestNotificationLocalization() {
  @autoreleasepool {
    const bool russian = alice::desktop::UsesRussian();
    rex::system::AchievementInfo info;
    info.label = alice::desktop::Localized("Проверка уведомлений");
    info.description = alice::desktop::Localized("Достижения Alice теперь отображаются через macOS.");
    auto achievement = AchievementContent(info);
    auto legacy = UnavailableContent(true);
    auto dlc = UnavailableContent(false);
    // Inspect the actual delivery content without posting test banners.
    return [achievement.title isEqual:russian ? @"Достижение получено" : @"Achievement unlocked"] &&
        [achievement.subtitle isEqual:russian ? @"Проверка уведомлений" : @"Notification test"] &&
        [achievement.body isEqual:russian ? @"Достижения Alice теперь отображаются через macOS." :
            @"Alice achievements now appear as macOS notifications."] &&
        [legacy.title isEqual:russian ? @"Хорошая попытка!" : @"Nice try!"] &&
        [legacy.body isEqual:russian ?
            @"American McGee's Alice для Xbox 360 невозможен для запуска. Разработка в этом направлении не ведётся" :
            @"American McGee's Alice for Xbox 360 cannot be launched. No development is planned in this direction."] &&
        [dlc.title isEqual:russian ? @"Функция не поддерживается" : @"Feature not supported"] &&
        [dlc.body isEqual:russian ? @"Downloadable Content недоступен в версии для macOS." :
            @"Downloadable Content is unavailable in the macOS version."];
  }
}
}

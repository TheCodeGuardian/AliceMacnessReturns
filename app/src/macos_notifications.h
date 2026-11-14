#pragma once
#include <rex/system/achievement_manager.h>
#include <string_view>
namespace rex { class Runtime; }

namespace alice::macos {
void PrepareNotificationHandling();
void InitializeNotifications();
bool HandleNotificationAction(std::string_view identifier, bool defaultAction);
void NotifyAchievement(const rex::system::AchievementEvent& event, rex::Runtime* runtime,
                       bool preview = false);
void NotifyLegacyAliceUnavailable();
void NotifyDownloadableContentUnavailable();
bool NotificationTestRequested();
bool TestNotificationLocalization();
}

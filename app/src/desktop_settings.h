#pragma once
#include <filesystem>
#include <string>
namespace rex { struct PathConfig; class Runtime; }
namespace rex::system { class AchievementManager; }
namespace alice::desktop {
struct Settings {
  std::filesystem::path game_directory;
  std::filesystem::path storage_directory;
  std::filesystem::path copy_user_data_from;
  bool fullscreen = false;
  bool vsync = true;
  bool mute = false;
  bool notifications = true;
};
Settings Defaults();
bool LoadSettings(Settings& settings, std::string& error);
bool SaveSettings(const Settings& settings, std::string& error);
bool ValidateSettings(const Settings& settings, std::string& error);
bool CopyUserData(const std::filesystem::path& from, const std::filesystem::path& to,
                  std::string& error);
std::filesystem::path SettingsFile();
const Settings& CurrentSettings();
void CommitSettings(const Settings& settings);
// Called before SDK logging, graphics or guest runtime initialization.
bool Prepare();
void ConfigurePaths(rex::PathConfig& paths);
std::string RuntimeDefaults();
std::filesystem::path NotificationDirectory();
std::filesystem::path ActiveStorageDirectory();
bool AchievementNotificationsEnabled();
void Attach(rex::system::AchievementManager& achievements, rex::Runtime* runtime);
void Detach();
void ShowSettings();
void ShowAchievements();
bool RunSelfTests(const std::filesystem::path& directory);
bool SelfTestsRequested();
bool ShowSetupWizard(Settings& settings, const std::string& reason);
void InstallMenus();
void RefreshMenus();
}

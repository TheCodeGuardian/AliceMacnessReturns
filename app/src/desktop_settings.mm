#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include "desktop_settings.h"
#include "macos_localization.h"
#include <rex/cvar.h>
#include <rex/rex_app.h>
#include <rex/runtime.h>
#include <atomic>
#include <fstream>

REXCVAR_DEFINE_STRING(alice_settings_file, "", "ALICE", "Location of macOS launcher settings")
    .lifecycle(rex::cvar::Lifecycle::kInitOnly);
REXCVAR_DEFINE_BOOL(alice_skip_setup, false, "ALICE", "Skip the setup wizard for automated tests")
    .lifecycle(rex::cvar::Lifecycle::kInitOnly);
REXCVAR_DEFINE_BOOL(alice_setup, false, "ALICE", "Show the setup wizard again")
    .lifecycle(rex::cvar::Lifecycle::kInitOnly);
REXCVAR_DEFINE_STRING(alice_desktop_test, "", "ALICE", "Run isolated desktop UI and settings tests")
    .lifecycle(rex::cvar::Lifecycle::kInitOnly);

namespace alice::desktop {
namespace {
Settings current;
std::filesystem::path active_storage;
std::atomic<bool> notifications{true};
NSString* String(const std::filesystem::path& path) {
  return [NSString stringWithUTF8String:path.string().c_str()];
}
std::filesystem::path SupportDirectory() {
  auto support = std::filesystem::path(NSHomeDirectory().UTF8String) /
      "Library/Application Support";
  // Keep existing settings/data discoverable; do not rename user directories.
  auto legacy = support / "Alice Madness Returns";
  std::error_code error;
  if (std::filesystem::exists(legacy / "settings.json", error)) return legacy;
  return support / "AliceMacnessReturns";
}
std::string Quote(const std::string& text) {
  std::string out = "\"";
  for (char c : text) {
    switch (c) {
      case '\\': out += "\\\\"; break;
      case '"': out += "\\\""; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default: out += c;
    }
  }
  return out + '"';
}
bool Within(const std::filesystem::path& child, const std::filesystem::path& parent) {
  auto c = std::filesystem::weakly_canonical(child);
  auto p = std::filesystem::weakly_canonical(parent);
  auto ci = c.begin();
  for (const auto& component : p) {
    if (ci == c.end() || *ci++ != component) return false;
  }
  return true;
}
}

std::filesystem::path SettingsFile() {
  auto explicit_path = REXCVAR_GET(alice_settings_file);
  return explicit_path.empty() ? SupportDirectory() / "settings.json" :
      std::filesystem::absolute(explicit_path).lexically_normal();
}

Settings Defaults() {
  Settings result;
  const auto explicit_game = rex::cvar::GetFlagByName("game_data_root");
  if (!explicit_game.empty()) result.game_directory = explicit_game;
#if ALICE_DEVELOPMENT_BUILD
  const std::filesystem::path project(ALICE_PROJECT_ROOT);
  if (result.game_directory.empty() && std::filesystem::is_regular_file(project / "assets/game_root/default.xex"))
    result.game_directory = project / "assets/game_root";
  if (!result.game_directory.empty()) {
    result.storage_directory = project / "build/game/state";
  }
#endif
  if (result.storage_directory.empty()) result.storage_directory = SupportDirectory() / "Data";
  return result;
}

bool LoadSettings(Settings& settings, std::string& error) {
  @autoreleasepool {
    NSError* e = nil;
    NSData* data = [NSData dataWithContentsOfFile:String(SettingsFile()) options:0 error:&e];
    if (!data) { error = Localized("Настройки ещё не сохранены или файл недоступен."); return false; }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&e];
    if (![json isKindOfClass:NSDictionary.class] || ![json[@"version"] isEqual:@1]) {
      error = Localized("Файл настроек повреждён или создан другой версией приложения."); return false;
    }
    for (NSString* key in @[@"game_directory", @"storage_directory"])
      if (![json[key] isKindOfClass:NSString.class]) {
        error = Localized("В настройках отсутствуют пути к папкам."); return false;
      }
    for (NSString* key in @[@"fullscreen", @"vsync", @"mute", @"notifications"])
      if (![json[key] isKindOfClass:NSNumber.class]) {
        error = Localized("В файле настроек неверно записаны переключатели."); return false;
      }
    Settings loaded;
    loaded.game_directory = [json[@"game_directory"] UTF8String];
    loaded.storage_directory = [json[@"storage_directory"] UTF8String];
    if ([json[@"copy_user_data_from"] isKindOfClass:NSString.class])
      loaded.copy_user_data_from = [json[@"copy_user_data_from"] UTF8String];
    loaded.fullscreen = [json[@"fullscreen"] boolValue];
    loaded.vsync = [json[@"vsync"] boolValue];
    loaded.mute = [json[@"mute"] boolValue];
    loaded.notifications = [json[@"notifications"] boolValue];
    settings = std::move(loaded);
    return true;
  }
}

bool ValidateSettings(const Settings& settings, std::string& error) {
  try {
    if (!settings.game_directory.is_absolute() || !settings.storage_directory.is_absolute() ||
        (!settings.copy_user_data_from.empty() && !settings.copy_user_data_from.is_absolute())) {
      error = Localized("Выберите полный путь к каждой папке."); return false;
    }
    auto executable = settings.game_directory / "default.xex";
    if (!std::filesystem::is_regular_file(executable)) executable = settings.game_directory / "Default.xex";
    std::ifstream file(executable, std::ios::binary);
    if (!file || !std::filesystem::is_directory(settings.game_directory / "AliceGame")) {
      error = Localized("Выберите папку извлечённой игры с default.xex и папкой AliceGame. ISO здесь не подходит.");
      return false;
    }
    CC_SHA256_CTX sha;
    CC_SHA256_Init(&sha);
    char buffer[65536];
    while (file) {
      file.read(buffer, sizeof(buffer));
      CC_SHA256_Update(&sha, buffer, static_cast<CC_LONG>(file.gcount()));
    }
    if (file.bad()) { error = Localized("Не удалось прочитать default.xex."); return false; }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &sha);
    std::string hex;
    const char* digits = "0123456789abcdef";
    for (auto b : digest) { hex += digits[b >> 4]; hex += digits[b & 15]; }
    if (hex != "cb03c935a7b42982cbe00adf65cb700e976156eb7273c8ff63d6c87d419dd808") {
      error = Localized("Эта версия игры не поддерживается. Нужен Xbox 360-релиз media 0B4C7F8F.");
      return false;
    }
    // Storage must be separate from the game and the signed app bundle.
    if (Within(settings.storage_directory, settings.game_directory) ||
        Within(settings.game_directory, settings.storage_directory) ||
        Within(settings.storage_directory, std::filesystem::path(NSBundle.mainBundle.bundlePath.UTF8String))) {
      error = Localized("Папка пользовательских данных должна находиться отдельно от игры и приложения.");
      return false;
    }
    return true;
  } catch (const std::exception& e) { error = e.what(); return false; }
}

bool SaveSettings(const Settings& settings, std::string& error) {
  @autoreleasepool {
    NSError* e = nil;
    NSFileManager* fm = NSFileManager.defaultManager;
    for (auto path : {settings.storage_directory, SettingsFile().parent_path()}) {
      if (![fm createDirectoryAtPath:String(path) withIntermediateDirectories:YES attributes:nil error:&e]) {
        error = e.localizedDescription.UTF8String; return false;
      }
    }
    // Check actual writes, including removable volumes and permissions.
    NSString* probe = [String(settings.storage_directory) stringByAppendingPathComponent:
        [@".alice-write-test-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    if (![[NSData data] writeToFile:probe options:NSDataWritingAtomic error:&e]) {
      error = e.localizedDescription.UTF8String; return false;
    }
    [fm removeItemAtPath:probe error:nil];
    NSDictionary* json = @{@"version": @1, @"game_directory": String(settings.game_directory),
        @"storage_directory": String(settings.storage_directory), @"fullscreen": @(settings.fullscreen),
        @"copy_user_data_from": String(settings.copy_user_data_from),
        @"vsync": @(settings.vsync), @"mute": @(settings.mute), @"notifications": @(settings.notifications)};
    NSData* data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:&e];
    if (!data || ![data writeToFile:String(SettingsFile()) options:NSDataWritingAtomic error:&e]) {
      error = e.localizedDescription.UTF8String; return false;
    }
    return true;
  }
}

bool CopyUserData(const std::filesystem::path& from, const std::filesystem::path& to,
                  std::string& error) {
  @autoreleasepool {
    try {
      if (from == to) return true;
      if (!std::filesystem::is_directory(from / "user")) {
        error = Localized("Исходные сохранения недоступны. Подключите диск со старой папкой данных или отключите копирование.");
        return false;
      }
      if (Within(to, from) || Within(from, to)) {
        error = Localized("Для копирования выберите отдельную папку, не вложенную в текущую."); return false;
      }
      if (std::filesystem::exists(to / "user")) {
        error = Localized("В новой папке уже есть сохранения. Отключите копирование, чтобы использовать их. Ничего не перезаписано.");
        return false;
      }
      std::filesystem::create_directories(to);
      auto staging = to / (std::string(".alice-import-") + NSUUID.UUID.UUIDString.UTF8String);
      NSFileManager* fm = NSFileManager.defaultManager;
      NSError* e = nil;
      if (![fm copyItemAtPath:String(from / "user") toPath:String(staging) error:&e] ||
          ![fm moveItemAtPath:String(staging) toPath:String(to / "user") error:&e]) {
        error = e.localizedDescription.UTF8String;
        [fm removeItemAtPath:String(staging) error:nil];
        return false;
      }
      return true;
    } catch (const std::exception& e) { error = e.what(); return false; }
  }
}

const Settings& CurrentSettings() { return current; }
void CommitSettings(const Settings& settings) {
  current = settings;
  notifications.store(settings.notifications);
}
bool AchievementNotificationsEnabled() { return notifications.load(); }
std::filesystem::path NotificationDirectory() { return active_storage / "notification-attachments"; }
std::filesystem::path ActiveStorageDirectory() { return active_storage; }
bool SelfTestsRequested() { return !REXCVAR_GET(alice_desktop_test).empty(); }

bool Prepare() {
  if (SelfTestsRequested()) return RunSelfTests(REXCVAR_GET(alice_desktop_test));
  Settings settings = Defaults();
  std::string reason;
  bool loaded = LoadSettings(settings, reason);
  if (!REXCVAR_GET(alice_skip_setup)) {
    bool valid = loaded && ValidateSettings(settings, reason);
    if (!valid || REXCVAR_GET(alice_setup)) {
      if (!ShowSetupWizard(settings, std::filesystem::exists(SettingsFile()) ? reason : std::string{})) return false;
    }
    while (!settings.copy_user_data_from.empty()) {
      if (CopyUserData(settings.copy_user_data_from, settings.storage_directory, reason)) {
        settings.copy_user_data_from.clear();
        if (SaveSettings(settings, reason)) break;
      }
      if (!ShowSetupWizard(settings, reason)) return false;
    }
  }
  CommitSettings(settings);
  active_storage = settings.storage_directory;
  InstallMenus();
  return true;
}

void ConfigurePaths(rex::PathConfig& paths) {
  if (REXCVAR_GET(game_data_root).empty()) paths.game_data_root = current.game_directory;
  if (REXCVAR_GET(user_data_root).empty()) paths.user_data_root = active_storage / "user";
  if (REXCVAR_GET(cache_root).empty()) paths.cache_root = active_storage / "cache";
  paths.config_path = active_storage / "alice.toml";
}

std::string RuntimeDefaults() {
  return "log_file = " + Quote((active_storage / "alice.log").string()) + "\n" +
      "vfs_path_index = " + Quote((active_storage / "cache/vfs_index_game_root.bin").string()) + "\n" +
      "fullscreen = " + (current.fullscreen ? "true\n" : "false\n") +
      "audio_mute = " + (current.mute ? "true\n" : "false\n") +
      "vulkan_allow_present_mode_immediate = " + (current.vsync ? "false\n" : "true\n") +
      "vulkan_allow_present_mode_mailbox = true\n";
}
}

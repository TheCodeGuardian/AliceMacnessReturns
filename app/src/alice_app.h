#pragma once
#include "macos_notifications.h"
#include "legacy_menu.h"
#include "desktop_settings.h"
#include "macos_localization.h"
#include <rex/ui/overlay/achievement_notification.h>
#include <rex/ui/keybinds.h>
#include <rex/rex_app.h>
#include <rex/runtime.h>
#include <rex/input/input_system.h>
#include <rex/input/device_assignment.h>

class AliceDesktopExit : public rex::ui::WindowedApp {
 public:
  AliceDesktopExit(rex::ui::WindowedAppContext& ctx, bool success)
      : WindowedApp(ctx, "alice"), success_(success) {}
  bool OnInitialize() override {
    app_context().RequestDeferredQuit();
    return success_;
  }
 private:
  bool success_;
};

class AliceApp : public rex::ReXApp {
 public:
  explicit AliceApp(rex::ui::WindowedAppContext& context)
      : rex::ReXApp(context, "alice", PPCImageConfig) {}
  static std::unique_ptr<rex::ui::WindowedApp> Create(rex::ui::WindowedAppContext& ctx) {
    // The SDL desktop entry point initializes Cocoa before calling the creator.
    // Complete setup before ReXApp constructs logging or the GPU/runtime.
    if (alice::desktop::SelfTestsRequested()) {
      bool success = alice::desktop::Prepare();
      return std::make_unique<AliceDesktopExit>(ctx, success);
    }
    alice::macos::PrepareNotificationHandling();
    if (!alice::desktop::Prepare()) {
      return std::make_unique<AliceDesktopExit>(ctx, true);
    }
    auto application = std::make_unique<AliceApp>(ctx);
    return application;
  }
  void OnConfigurePaths(rex::PathConfig& paths) override {
    alice::desktop::ConfigurePaths(paths);
    built_in_config_ = alice::desktop::RuntimeDefaults() +
        "gpu_plugin = \"xenos\"\n"
        "async_shader_compilation = false\n"
        "skip_depth_color_7e3_aliasing_transfers = true\n"
        "log_async = true\n";
  }
  void OnPostSetup() override {
    if (auto* input = dynamic_cast<rex::input::InputSystem*>(runtime()->input_system()))
      input->SetDeviceAssignment(std::make_unique<rex::input::SharedAssignment>());
    alice::desktop::Attach(achievements(), runtime());
    alice::macos::InitializeNotifications();
    alice::TestLegacyMenuHookIfRequested(runtime());
    notification_listener_ = achievements().RegisterNotificationCallback(
        [this](const rex::system::AchievementEvent& event) {
          alice::macos::NotifyAchievement(event, runtime());
        });
    if (alice::macos::NotificationTestRequested()) {
      rex::system::AchievementEvent test;
      test.achievement.label = alice::desktop::Localized("Проверка уведомлений");
      test.achievement.description = alice::desktop::Localized("Достижения Alice теперь отображаются через macOS.");
      for (const auto& info : achievements().ListAchievements()) {
        if (!achievements().IsUnlocked(info.id)) {
          test.achievement = info;
          break;
        }
      }
      // Preserve the Xbox ID for language lookup; delivery uses a preview ID.
      alice::macos::NotifyAchievement(test, runtime(), true);
    }
  }
  std::optional<rex::PathConfig> OnFinalizePaths(const rex::PathConfig& defaults,
      std::function<void(rex::PathConfig)> resume) override {
    window()->SetTitle("Alice: Madness Returns");
    alice::desktop::RefreshMenus();
    return defaults;
  }
  void OnShutdown() override {
    alice::desktop::Detach();
    if (notification_listener_) {
      achievements().UnregisterCallback(notification_listener_);
      notification_listener_ = 0;
    }
  }
  std::unique_ptr<rex::ui::AchievementNotificationDialog>
  CreateAchievementNotificationDialog() override { return nullptr; }

  std::string_view BuiltInConfig() const override {
    return built_in_config_;
  }
 protected:
  void OnKeyDown(rex::ui::KeyEvent& event) override {
    if (event.virtual_key() == rex::ui::VirtualKey::kF4) {
      alice::desktop::ShowSettings(); event.set_handled(true);
    } else if (event.virtual_key() == rex::ui::VirtualKey::kF7) {
      alice::desktop::ShowAchievements(); event.set_handled(true);
    } else rex::ui::ProcessKeyEvent(event);
  }
 private:
  std::string built_in_config_;
  rex::system::AchievementListenerHandle notification_listener_ = 0;
};

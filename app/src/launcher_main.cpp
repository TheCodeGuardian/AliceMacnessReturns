#include "desktop_settings.h"
#include "local_build.h"
#include <rex/ui/windowed_app.h>

class AliceLauncher final : public rex::ui::WindowedApp {
 public:
  AliceLauncher(rex::ui::WindowedAppContext& context, bool success)
      : WindowedApp(context, "alice"), success_(success) {}
  static std::unique_ptr<rex::ui::WindowedApp> Create(rex::ui::WindowedAppContext& context) {
    bool test = alice::desktop::SelfTestsRequested();
    bool success = alice::desktop::Prepare();
    if (success && !test) success = alice::desktop::BuildAndLaunchGame();
    return std::make_unique<AliceLauncher>(context, success);
  }
  bool OnInitialize() override {
    app_context().RequestDeferredQuit();
    return success_;
  }
 private:
  bool success_;
};
REX_DEFINE_APP(alice, AliceLauncher::Create)

#include "legacy_menu.h"
#include "macos_notifications.h"

#include <array>
#include <cstring>
#include <stdexcept>
#include <rex/cvar.h>
#include <rex/hook.h>
#include <rex/runtime.h>

REXCVAR_DEFINE_BOOL(alice_legacy_menu_test, false, "ALICE",
                   "Exercise the blocked Alice 1 menu action without launching another title");

namespace {
void AdvanceScriptFrame(PPCContext& ctx, uint8_t* base) {
  // No-argument UnrealScript exec: consume EX_EndFunctionParms exactly once.
  uint32_t code;
  std::memcpy(&code, base + ctx.r4.u32 + 24, sizeof(code));
  code = rex::byte_swap(rex::byte_swap(code) + uint32_t{1});
  std::memcpy(base + ctx.r4.u32 + 24, &code, sizeof(code));
}
}

// Media 0B4C7F8F: the native registration at 0x8304DE40 pairs the name
// intUAliceGameEngineexecLaunchAlice1 (0x821C2C68) with 0x82A8D9E0.
// Replace the UnrealScript exec entry BEFORE its virtual call (vtable +516).
// Hooking XamLoaderLaunchTitle would be too late: the game has torn down its
// engine by then, or failed loading game:\Alice1\fakk2.xex.
REX_HOOK_RAW(sub_82A8D9E0) {
  // Preserve the original exec wrapper's consumption of EX_EndFunctionParms.
  // r4 is FFrame*, Code is at +24; this native takes no script arguments.
  AdvanceScriptFrame(ctx, base);
  REXLOG_INFO("[legacy-menu] blocked Play American McGee's Alice; keeping the current game running");
  alice::macos::NotifyLegacyAliceUnavailable();
}

// Media 0B4C7F8F: sub_8304E220 registers this no-argument exec as
// intAAlicePlayerControllerexecDLCExitToStore at native table 0x83305920.
// Handle the menu action before the virtual call at vtable +1536, which
// otherwise enters the Xbox store/sign-in path.
REX_HOOK_RAW(sub_82AB2EF0) {
  AdvanceScriptFrame(ctx, base);
  REXLOG_INFO("[dlc-menu] blocked Downloadable Content; keeping the current game running");
  alice::macos::NotifyDownloadableContentUnavailable();
}

namespace alice {
void TestLegacyMenuHookIfRequested(rex::Runtime* runtime) {
  if (!REXCVAR_GET(alice_legacy_menu_test)) return;
  auto* memory = runtime->memory();
  const uint32_t frame = memory->SystemHeapAlloc(64);
  if (!frame) throw std::runtime_error("Legacy menu test: guest allocation failed");
  auto* base = runtime->virtual_membase();
  std::array<uint8_t, 64> expected;
  expected.fill(0xA5);
  // Code 0x123456FF must advance to 0x12345700 in big endian memory.
  expected[24] = 0x12; expected[25] = 0x34; expected[26] = 0x56; expected[27] = 0xFF;
  std::memcpy(base + frame, expected.data(), expected.size());
  PPCContext ctx{};
  ctx.r4.u64 = frame;
  ctx.r5.u64 = 0x12345678;
  ctx.lr = 0x87654320;
  const PPCContext before = ctx;
  // Null r3 deliberately makes the original virtual call invalid: success
  // demonstrates that the strong hook replaced the generated weak symbol.
  sub_82A8D9E0(ctx, base);
  expected[26] = 0x57; expected[27] = 0;
  const bool valid = std::memcmp(base + frame, expected.data(), expected.size()) == 0 &&
                     std::memcmp(&ctx, &before, sizeof(ctx)) == 0;
  memory->SystemHeapFree(frame);
  if (!valid) throw std::runtime_error("Legacy menu hook corrupted FFrame or PPC registers");
  REXLOG_INFO("[legacy-menu] test passed: VM advanced once, registers and frame canaries intact");
}
}

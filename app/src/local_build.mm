#import <AppKit/AppKit.h>
#include "local_build.h"
#include "desktop_settings.h"
#include "macos_localization.h"
#include <rex/cvar.h>
#include <cstdio>

REXCVAR_DEFINE_BOOL(alice_build_only, false, "ALICE", "Prepare the local game without launching it");

namespace {
NSString* L(NSString* ru, NSString* en) {
  return alice::desktop::UsesRussian() ? ru : en;
}
NSString* Path(const std::filesystem::path& path) {
  return [NSString stringWithUTF8String:path.string().c_str()];
}
NSString* Quote(NSString* value) {
  value = [value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
  value = [value stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
  value = [value stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
  value = [value stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
  value = [value stringByReplacingOccurrencesOfString:@"\t" withString:@"\\t"];
  return [NSString stringWithFormat:@"\"%@\"", value];
}
}

@interface AliceLocalBuilder : NSObject
@property NSWindow* window;
@property NSTextField* label;
@property NSTextView* output;
@property NSTask* task;
@property BOOL cancelled;
@property BOOL success;
@property NSString* failure;
@property NSString* logPath;
- (BOOL)run:(NSString*)executable arguments:(NSArray<NSString*>*)arguments directory:(NSString*)directory;
@end

@implementation AliceLocalBuilder
- (void)cancel:(id)sender {
  @synchronized(self) {
    self.cancelled = YES;
    if (self.task.running) [self.task terminate];
  }
}
- (BOOL)run:(NSString*)executable arguments:(NSArray<NSString*>*)arguments directory:(NSString*)directory {
  @autoreleasepool {
    NSFileHandle* log = [NSFileHandle fileHandleForWritingAtPath:self.logPath];
    [log seekToEndOfFile];
    NSString* command = [NSString stringWithFormat:@"\n%@ %@\n", executable, [arguments componentsJoinedByString:@" "]];
    [log writeData:[command dataUsingEncoding:NSUTF8StringEncoding]];
    NSTask* task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.arguments = arguments;
    task.currentDirectoryURL = [NSURL fileURLWithPath:directory];
    NSMutableDictionary* environment = [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"REX_MAX_JUMP_TABLE_ENTRIES"] = @"1024";
    environment[@"REX_REGISTER_SHARD_SPAN_BYTES"] = @"262144";
    environment[@"CLANG_MODULE_CACHE_PATH"] = [directory stringByAppendingPathComponent:@"module-cache"];
    task.environment = environment;
    task.standardOutput = log;
    task.standardError = log;
    NSError* error = nil;
    @synchronized(self) {
      if (self.cancelled) { [log closeFile]; return NO; }
      self.task = task;
      if (![task launchAndReturnError:&error]) self.failure = error.localizedDescription;
    }
    if (!error) [task waitUntilExit];
    self.task = nil;
    [log closeFile];
    if (error || task.terminationStatus != 0 || self.cancelled) {
      if (!self.failure) self.failure = [NSString stringWithFormat:@"%@ (exit %d)", executable.lastPathComponent, task.terminationStatus];
      return NO;
    }
    return YES;
  }
}
@end

namespace alice::desktop {
bool BuildAndLaunchGame() {
  @autoreleasepool {
    auto settings = CurrentSettings();
    std::string validation;
    if (!ValidateSettings(settings, validation)) {
      if (REXCVAR_GET(alice_build_only)) { std::fprintf(stderr, "%s\n", validation.c_str()); return false; }
      NSAlert* alert = [NSAlert new];
      alert.messageText = L(@"Не удалось подготовить игру", @"Unable to prepare the game");
      alert.informativeText = [NSString stringWithUTF8String:validation.c_str()];
      [alert runModal];
      return false;
    }
    NSFileManager* fm = NSFileManager.defaultManager;
    NSString* kit = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"BuildKit"];
    NSString* revision = [NSString stringWithContentsOfFile:[kit stringByAppendingPathComponent:@"revision.txt"] encoding:NSUTF8StringEncoding error:nil];
    if (!revision.length) {
      std::fprintf(stderr, "BuildKit/revision.txt is missing from the release app.\n");
      return false;
    }
    NSString* base = [Path(settings.storage_directory) stringByAppendingPathComponent:@"local-build"];
    NSString* work = [base stringByAppendingPathComponent:[revision stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
    NSString* source = [work stringByAppendingPathComponent:@"source/app"];
    NSString* build = [work stringByAppendingPathComponent:@"build"];
    NSString* app = [build stringByAppendingPathComponent:@"alice.app"];
    NSString* stamp = [work stringByAppendingPathComponent:@"complete.txt"];
    NSString* saved = [NSString stringWithContentsOfFile:stamp encoding:NSUTF8StringEncoding error:nil];
    BOOL ready = [saved isEqual:revision] && [fm isExecutableFileAtPath:[app stringByAppendingPathComponent:@"Contents/MacOS/alice"]];
    if (!ready) {
      AliceLocalBuilder* runner = [AliceLocalBuilder new];
      runner.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 370)
          styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
      runner.window.title = @"AliceMacnessReturns";
      runner.window.releasedWhenClosed = NO;
      runner.label = [NSTextField wrappingLabelWithString:L(@"Подготовка игры из ваших файлов. Первая сборка может занять несколько минут.", @"Preparing the game from your files. The first build may take several minutes.")];
      runner.label.frame = NSMakeRect(20, 312, 660, 40);
      [runner.window.contentView addSubview:runner.label];
      NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 65, 660, 235)];
      scroll.hasVerticalScroller = YES;
      runner.output = [[NSTextView alloc] initWithFrame:scroll.bounds];
      runner.output.editable = NO;
      runner.output.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
      scroll.documentView = runner.output;
      [runner.window.contentView addSubview:scroll];
      NSButton* cancel = [NSButton buttonWithTitle:L(@"Отмена", @"Cancel") target:runner action:@selector(cancel:)];
      cancel.frame = NSMakeRect(575, 18, 105, 32);
      [runner.window.contentView addSubview:cancel];
      [runner.window center];
      [runner.window makeKeyAndOrderFront:nil];
      [NSApp activateIgnoringOtherApps:YES];
      [fm createDirectoryAtPath:work withIntermediateDirectories:YES attributes:nil error:nil];
      runner.logPath = [work stringByAppendingPathComponent:@"build.log"];
      [@"AliceMacnessReturns local build\n" writeToFile:runner.logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
      NSTimer* timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer*) {
        NSFileHandle* file = [NSFileHandle fileHandleForReadingAtPath:runner.logPath];
        unsigned long long size = [file seekToEndOfFile];
        [file seekToFileOffset:size > 24000 ? size - 24000 : 0];
        NSString* text = [[NSString alloc] initWithData:[file readDataToEndOfFile] encoding:NSUTF8StringEncoding];
        [file closeFile];
        runner.output.string = text ?: @"";
        [runner.output scrollRangeToVisible:NSMakeRange(runner.output.string.length, 0)];
      }];
      [NSRunLoop.mainRunLoop addTimer:timer forMode:NSModalPanelRunLoopMode];
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
          NSError* error = nil;
          NSString* projectSource = [kit stringByAppendingPathComponent:@"project/app"];
          // An interrupted attempt retains its compiler cache. Copy updated host
          // sources without removing user files or touching the game directory.
          BOOL ok = [runner run:@"/usr/bin/ditto" arguments:@[projectSource, source] directory:work];
          NSString* game = Path(settings.game_directory);
          NSString* xex = [game stringByAppendingPathComponent:@"default.xex"];
          if (![fm fileExistsAtPath:xex]) xex = [game stringByAppendingPathComponent:@"Default.xex"];
          NSString* manifest = [NSString stringWithFormat:@"[project]\nname = \"alice\"\nsdk_version = \"0.10.0\"\ngame_root = %@\n\n[entrypoint]\nfile_path = %@\nout_directory_path = \"generated/default\"\nincludes = [\"overrides.toml\"]\n", Quote(game), Quote(xex)];
          if (ok) ok = [manifest writeToFile:[source stringByAppendingPathComponent:@"alice_manifest.toml"] atomically:YES encoding:NSUTF8StringEncoding error:&error];
          NSString* sdk = [kit stringByAppendingPathComponent:@"sdk"];
          NSString* cmake = [kit stringByAppendingPathComponent:@"tools/bin/cmake"];
          if (ok) ok = [runner run:@"/usr/bin/xcrun" arguments:@[@"--find", @"clang++"] directory:work];
          if (ok) ok = [runner run:[sdk stringByAppendingPathComponent:@"bin/rexglue"] arguments:@[@"codegen", @"alice_manifest.toml"] directory:source];
          if (ok) ok = [runner run:cmake arguments:@[@"-S", source, @"-B", build, @"-G", @"Ninja", @"-DCMAKE_BUILD_TYPE=Release", @"-DCMAKE_OSX_ARCHITECTURES=arm64", @"-DCMAKE_C_COMPILER=/usr/bin/clang", @"-DCMAKE_CXX_COMPILER=/usr/bin/clang++", @"-DCMAKE_OBJCXX_COMPILER=/usr/bin/clang++", [@"-DCMAKE_PREFIX_PATH=" stringByAppendingString:sdk], [@"-DCMAKE_MAKE_PROGRAM=" stringByAppendingString:[kit stringByAppendingPathComponent:@"tools/bin/ninja"]], @"-DALICE_DEVELOPMENT_BUILD=OFF", @"-DALICE_LAUNCHER_ONLY=OFF", @"-DREXGLUE_ENABLE_TRACY=OFF"] directory:work];
          if (ok) ok = [runner run:cmake arguments:@[@"--build", build, @"--target", @"alice", @"--parallel", @"3"] directory:work];
          if (ok) ok = [runner run:@"/usr/bin/codesign" arguments:@[@"--verify", @"--deep", @"--strict", app] directory:work];
          if (ok && !runner.cancelled) ok = [revision writeToFile:stamp atomically:YES encoding:NSUTF8StringEncoding error:&error];
          runner.success = ok && !runner.cancelled;
          if (error) runner.failure = error.localizedDescription;
          dispatch_async(dispatch_get_main_queue(), ^{ [NSApp stopModal]; });
        }
      });
      [NSApp runModalForWindow:runner.window];
      [timer invalidate];
      [runner.window orderOut:nil];
      if (!runner.success) {
        if (!runner.cancelled && !REXCVAR_GET(alice_build_only)) {
          NSAlert* alert = [NSAlert new];
          alert.messageText = L(@"Не удалось собрать игру", @"The game could not be built");
          alert.informativeText = [NSString stringWithFormat:@"%@\n\n%@\n\n%@", L(@"Нужны инструменты командной строки Xcode. Файлы игры сохранены. Подробности в журнале:", @"Xcode Command Line Tools are required. Your game files are preserved. See the build log:"), runner.logPath, runner.failure ?: @""];
          [alert runModal];
        }
        std::fprintf(stderr, "Local build failed. Log: %s\n", runner.logPath.UTF8String);
        return false;
      }
    }
    std::fprintf(stdout, "Local ARM64 game ready: %s%s\n", app.UTF8String, ready ? " (cached)" : "");
    if (REXCVAR_GET(alice_build_only)) return true;
    __block NSError* error = nil;
    __block BOOL finished = NO;
    __block NSRunningApplication* launched = nil;
    NSArray* arguments = @[[NSString stringWithFormat:@"--alice_settings_file=%@", Path(SettingsFile())]];
    NSWorkspaceOpenConfiguration* configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.arguments = arguments;
    [NSWorkspace.sharedWorkspace openApplicationAtURL:[NSURL fileURLWithPath:app]
        configuration:configuration completionHandler:^(NSRunningApplication* application, NSError* launchError) {
      dispatch_async(dispatch_get_main_queue(), ^{ launched = application; error = launchError; finished = YES; });
    }];
    while (!finished)
      [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    if (!launched) {
      NSAlert* alert = [NSAlert new];
      alert.messageText = L(@"Не удалось запустить игру", @"The game could not be launched");
      alert.informativeText = error.localizedDescription ?: app;
      [alert runModal];
      return false;
    }
    return true;
  }
}
}

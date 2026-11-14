#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include "desktop_settings.h"
#include "macos_localization.h"
#define L AliceLocalized
#include "macos_achievement_images.h"
#include "macos_notifications.h"
#include <rex/cvar.h>
#include <rex/logging.h>
#include <rex/runtime.h>
#include <rex/system/achievement_manager.h>
#include <algorithm>
#include <fstream>
#include <stdexcept>

REXCVAR_DEFINE_STRING(alice_desktop_capture, "", "ALICE", "Export the app's native views for UI verification");

using alice::desktop::Settings;

@interface AliceTextWindow : NSWindow
@end
@implementation AliceTextWindow
- (BOOL)performKeyEquivalent:(NSEvent*)event {
  // Preserve editing shortcuts after removing the visible Edit menu. Limit
  // this to a native text editor so game and application shortcuts stay intact.
  NSEventModifierFlags modifiers = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
  modifiers &= ~NSEventModifierFlagCapsLock;
  if (modifiers == NSEventModifierFlagCommand && [self.firstResponder isKindOfClass:NSTextView.class]) {
    NSDictionary* actions = @{@"x": @"cut:", @"c": @"copy:", @"v": @"paste:", @"a": @"selectAll:"};
    NSString* action = actions[event.charactersIgnoringModifiers.lowercaseString ?: @""];
    if (action && [NSApp sendAction:NSSelectorFromString(action) to:self.firstResponder from:self]) return YES;
  }
  return [super performKeyEquivalent:event];
}
@end

namespace {
NSString* Text(const std::string& value) {
  return [NSString stringWithUTF8String:value.c_str()] ?: @"";
}
NSTextField* Label(NSString* text, NSRect frame, CGFloat size = 13, BOOL secondary = NO) {
  NSTextField* label = [NSTextField wrappingLabelWithString:text];
  label.frame = frame;
  label.font = [NSFont systemFontOfSize:size];
  label.textColor = secondary ? NSColor.secondaryLabelColor : NSColor.labelColor;
  return label;
}
NSButton* Button(NSString* title, NSRect frame, id target, SEL action) {
  NSButton* button = [NSButton buttonWithTitle:title target:target action:action];
  button.bezelStyle = NSBezelStyleRounded;
  button.frame = frame;
  return button;
}
NSButton* Check(NSString* title, NSRect frame, BOOL value) {
  NSButton* button = [NSButton checkboxWithTitle:title target:nil action:nil];
  button.frame = frame;
  button.state = value ? NSControlStateValueOn : NSControlStateValueOff;
  return button;
}
NSWindow* Window(NSString* title, CGFloat width, CGFloat height, BOOL resize = NO) {
  NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
  if (resize) style |= NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable;
  NSWindow* window = [[AliceTextWindow alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
      styleMask:style backing:NSBackingStoreBuffered defer:NO];
  window.title = title;
  window.releasedWhenClosed = NO;
  [window center];
  return window;
}
}

@interface AlicePreferencesController : NSWindowController <NSWindowDelegate> {
 @public
  Settings original_;
  Settings result_;
}
@property BOOL wizard;
@property BOOL accepted;
@property NSInteger step;
@property(strong) NSArray<NSView*>* pages;
@property(strong) NSTextField* heading;
@property(strong) NSTextField* errorLabel;
@property(strong) NSTextField* gamePath;
@property(strong) NSTextField* storagePath;
@property(strong) NSButton* migrateSaves;
@property(strong) NSButton* fullscreen;
@property(strong) NSButton* vsync;
@property(strong) NSButton* mute;
@property(strong) NSButton* notifications;
@property(strong) NSButton* back;
@property(strong) NSButton* next;
- (instancetype)initWithSettings:(const Settings&)settings wizard:(BOOL)wizard reason:(NSString*)reason;
- (void)advance:(id)sender;
- (void)cancel:(id)sender;
@end

@implementation AlicePreferencesController
- (instancetype)initWithSettings:(const Settings&)settings wizard:(BOOL)wizard reason:(NSString*)reason {
  self = [super initWithWindow:Window(wizard ? L(@"Настройка Alice") : L(@"Настройки Alice"), 680, 570)];
  if (!self) return nil;
  original_ = result_ = settings;
  self.wizard = wizard;
  self.window.delegate = self;
  NSView* root = self.window.contentView;
  self.heading = Label(@"", NSMakeRect(28, 510, 624, 36), 25);
  [root addSubview:self.heading];
  NSMutableArray* pages = [NSMutableArray new];
  for (int i = 0; i < 3; ++i) {
    NSView* page = [[NSView alloc] initWithFrame:NSMakeRect(28, 130, 624, 365)];
    [root addSubview:page];
    [pages addObject:page];
  }
  self.pages = pages;
  NSView* welcome = pages[0];
  NSImageView* icon = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 225, 92, 92)];
  icon.image = NSApp.applicationIconImage;
  [welcome addSubview:icon];
  [welcome addSubview:Label(@"Alice: Madness Returns", NSMakeRect(112, 268, 500, 36), 23)];
  [welcome addSubview:Label(L(@"Версия для macOS · Apple Silicon"), NSMakeRect(112, 232, 500, 28), 14, YES)];
  [welcome addSubview:Label(L(@"Сначала выберите папку извлечённой игры Xbox 360 и место для сохранений, достижений и кэша."), NSMakeRect(0, 130, 612, 64), 16)];
  [welcome addSubview:Label(L(@"Файлы игры не входят в приложение. Нужна ваша копия совместимого релиза с default.xex и папкой AliceGame."), NSMakeRect(0, 60, 612, 58), 13, YES)];
  [welcome addSubview:Label(L(@"Эти параметры можно изменить позже: Alice: Madness Returns → Настройки… (⌘,)."), NSMakeRect(0, 8, 612, 40), 13, YES)];

  NSView* files = pages[1];
  [files addSubview:Label(L(@"Файлы игры"), NSMakeRect(0, 322, 600, 25), 15)];
  self.gamePath = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 280, 494, 28)];
  self.gamePath.stringValue = Text(settings.game_directory.string());
  self.gamePath.placeholderString = L(@"Папка с default.xex");
  self.gamePath.usesSingleLineMode = YES;
  self.gamePath.lineBreakMode = NSLineBreakByTruncatingMiddle;
  [(NSTextFieldCell*)self.gamePath.cell setScrollable:YES];
  [files addSubview:self.gamePath];
  [files addSubview:Button(L(@"Выбрать…"), NSMakeRect(502, 279, 122, 30), self, @selector(chooseGame:))];
  [files addSubview:Label(L(@"Используется существующая папка. Файлы игры не копируются."), NSMakeRect(0, 243, 610, 27), 12, YES)];
  [files addSubview:Label(L(@"Пользовательские данные"), NSMakeRect(0, 198, 610, 25), 15)];
  self.storagePath = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 156, 494, 28)];
  self.storagePath.stringValue = Text(settings.storage_directory.string());
  self.storagePath.usesSingleLineMode = YES;
  self.storagePath.lineBreakMode = NSLineBreakByTruncatingMiddle;
  [(NSTextFieldCell*)self.storagePath.cell setScrollable:YES];
  [files addSubview:self.storagePath];
  [files addSubview:Button(L(@"Выбрать…"), NSMakeRect(502, 155, 122, 30), self, @selector(chooseStorage:))];
  [files addSubview:Label(L(@"В этой папке будут сохранения, достижения, кэш и журнал игры."), NSMakeRect(0, 120, 610, 27), 12, YES)];
  self.migrateSaves = Check(L(@"Скопировать текущие сохранения и достижения при смене папки"), NSMakeRect(0, 69, 624, 28), YES);
  [files addSubview:self.migrateSaves];
  [files addSubview:Label(L(@"Исходные файлы останутся на месте. Существующие сохранения в новой папке не перезаписываются."), NSMakeRect(0, 15, 612, 45), 12, YES)];

  NSView* options = pages[2];
  self.fullscreen = Check(L(@"Запускать в полноэкранном режиме"), NSMakeRect(0, 298, 610, 28), settings.fullscreen);
  self.vsync = Check(L(@"Вертикальная синхронизация"), NSMakeRect(0, 246, 610, 28), settings.vsync);
  self.mute = Check(L(@"Выключить звук"), NSMakeRect(0, 194, 610, 28), settings.mute);
  self.notifications = Check(L(@"Системные уведомления о достижениях"), NSMakeRect(0, 142, 610, 28), settings.notifications);
  for (NSButton* control in @[self.fullscreen, self.vsync, self.mute, self.notifications]) [options addSubview:control];
  [options addSubview:Label(wizard ?
      L(@"Уведомления также должны быть разрешены в настройках macOS. Обзор достижений доступен через меню «Игра» и F7.") :
      L(@"Звук и уведомления изменятся сразу. Папки, полноэкранный запуск и синхронизация — после перезапуска игры."),
      NSMakeRect(0, 45, 612, 66), 13, YES)];
  NSTextField* configLocation = Label(L(@"Выбор папок сохраняется в настройках приложения."), NSMakeRect(0, 6, 612, 30), 12, YES);
  configLocation.toolTip = Text(alice::desktop::SettingsFile().string());
  [options addSubview:configLocation];

  self.errorLabel = Label(reason ?: @"", NSMakeRect(28, 70, 624, 54), 12);
  self.errorLabel.textColor = NSColor.systemRedColor;
  [root addSubview:self.errorLabel];
  NSButton* cancel = Button(wizard ? L(@"Отмена") : L(@"Закрыть"), NSMakeRect(28, 22, 110, 32), self, @selector(cancel:));
  cancel.keyEquivalent = @"\033";
  [root addSubview:cancel];
  self.back = Button(L(@"Назад"), NSMakeRect(390, 22, 110, 32), self, @selector(goBack:));
  self.next = Button(@"", NSMakeRect(508, 22, 144, 32), self, @selector(advance:));
  self.next.keyEquivalent = @"\r";
  [root addSubview:self.back]; [root addSubview:self.next];
  if (!wizard) {
    NSSegmentedControl* tabs = [NSSegmentedControl segmentedControlWithLabels:@[L(@"Папки"), L(@"Игра")]
        trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(changeTab:)];
    tabs.frame = NSMakeRect(425, 514, 227, 28);
    tabs.selectedSegment = 0;
    [root addSubview:tabs];
  }
  self.step = wizard ? 0 : 1;
  [self updatePage];
  return self;
}
- (void)updatePage {
  for (NSUInteger i = 0; i < self.pages.count; ++i) self.pages[i].hidden = i != self.step;
  self.heading.stringValue = self.wizard ? @[L(@"Добро пожаловать"), L(@"Папки игры"), L(@"Всё готово к запуску")][self.step] : L(@"Настройки");
  self.back.hidden = !self.wizard || self.step == 0;
  self.next.title = !self.wizard ? L(@"Сохранить") : self.step == 2 ? L(@"Начать игру") : L(@"Продолжить");
}
- (void)changeTab:(NSSegmentedControl*)sender { self.step = sender.selectedSegment + 1; [self updatePage]; }
- (void)goBack:(id)sender { if (self.step > 0) --self.step; [self updatePage]; }
- (void)choosePath:(NSTextField*)field title:(NSString*)title create:(BOOL)create {
  NSOpenPanel* panel = [NSOpenPanel openPanel];
  panel.title = title;
  panel.canChooseDirectories = YES;
  panel.canChooseFiles = NO;
  panel.canCreateDirectories = create;
  panel.allowsMultipleSelection = NO;
  panel.directoryURL = [NSURL fileURLWithPath:field.stringValue isDirectory:YES];
  if ([panel runModal] == NSModalResponseOK) field.stringValue = panel.URL.path;
}
- (void)chooseGame:(id)sender { [self choosePath:self.gamePath title:L(@"Папка извлечённой игры Xbox 360") create:NO]; }
- (void)chooseStorage:(id)sender { [self choosePath:self.storagePath title:L(@"Где хранить данные Alice") create:YES]; }
- (Settings)readSettings {
  Settings result;
  result.game_directory = self.gamePath.stringValue.stringByExpandingTildeInPath.UTF8String;
  result.storage_directory = self.storagePath.stringValue.stringByExpandingTildeInPath.UTF8String;
  result.fullscreen = self.fullscreen.state == NSControlStateValueOn;
  result.vsync = self.vsync.state == NSControlStateValueOn;
  result.mute = self.mute.state == NSControlStateValueOn;
  result.notifications = self.notifications.state == NSControlStateValueOn;
  auto source = original_.copy_user_data_from;
  if (source.empty()) source = alice::desktop::ActiveStorageDirectory();
  if (source.empty()) source = original_.storage_directory;
  if (self.migrateSaves.state == NSControlStateValueOn && source != result.storage_directory &&
      std::filesystem::exists(source / "user")) result.copy_user_data_from = source;
  return result;
}
- (void)advance:(id)sender {
  Settings settings = [self readSettings];
  std::string error;
  if (self.wizard && self.step == 0) { self.step = 1; [self updatePage]; return; }
  if (!alice::desktop::ValidateSettings(settings, error)) { self.errorLabel.stringValue = Text(error); return; }
  self.errorLabel.stringValue = @"";
  if (self.wizard && self.step == 1) { self.step = 2; [self updatePage]; return; }
  if (!alice::desktop::SaveSettings(settings, error)) { self.errorLabel.stringValue = Text(error); return; }
  result_ = settings;
  self.accepted = YES;
  if (self.wizard) [NSApp stopModalWithCode:NSModalResponseOK];
  else {
    alice::desktop::CommitSettings(settings);
    rex::cvar::SetFlagByName("audio_mute", settings.mute ? "true" : "false");
  }
  [self.window orderOut:nil];
}
- (void)cancel:(id)sender {
  if (self.wizard) [NSApp stopModalWithCode:NSModalResponseCancel];
  [self.window orderOut:nil];
}
- (BOOL)windowShouldClose:(NSWindow*)sender { [self cancel:nil]; return NO; }
@end

// Xbox 360 achievement flag 0x8 means its details may be shown before unlock.
// https://free60.org/System-Software/Formats/GPD/#flags
// Hidden rows are built without the secret strings or icon so search and
// accessibility cannot reveal them either.
static NSArray<NSDictionary*>* AchievementRows(rex::system::AchievementManager& manager,
                                               rex::Runtime* runtime) {
  auto catalog = manager.ListAchievements();
  std::sort(catalog.begin(), catalog.end(), [](const auto& a, const auto& b) { return a.id < b.id; });
  NSMutableArray* rows = [NSMutableArray new];
  for (const auto& info : catalog) {
    BOOL unlocked = manager.IsUnlocked(info.id);
    BOOL secret = !unlocked && !(info.flags & 8);
    NSString* title = secret ? L(@"Секретное достижение") : Text(info.label);
    NSString* description = secret ? L(@"Продолжайте игру, чтобы открыть это достижение.") :
        Text(unlocked ? info.description : info.unachieved_description);
    if (!secret && !description.length) description = Text(info.description);
    NSString* state = L(@"Закрыто");
    uint64_t time = manager.GetUnlockTime(info.id);
    if (unlocked && time >= 116444736000000000ULL) {
      NSDate* date = [NSDate dateWithTimeIntervalSince1970:
          double(time - 116444736000000000ULL) / 10000000.0];
      state = [L(@"Получено ") stringByAppendingString:[NSDateFormatter localizedStringFromDate:date
          dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle]];
    } else if (unlocked) state = L(@"Получено");
    NSImage* icon = nil;
    if (!secret) {
      NSData* data = AliceAchievementImage(info, runtime);
      if (data) icon = [[NSImage alloc] initWithData:data];
    }
    if (!icon) icon = [NSImage imageWithSystemSymbolName:unlocked ? @"checkmark.seal.fill" : @"lock.fill"
        accessibilityDescription:unlocked ? L(@"Получено") : L(@"Закрыто")];
    [rows addObject:@{@"title": title, @"description": description, @"state": state,
        @"unlocked": @(unlocked), @"score": @(info.gamerscore), @"icon": icon ?: [NSImage new]}];
  }
  return rows;
}

@interface AliceAchievementsController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@property(strong) NSArray<NSDictionary*>* rows;
@property(strong) NSArray<NSDictionary*>* filtered;
@property(strong) NSTextField* summary;
@property(strong) NSTextField* empty;
@property(strong) NSProgressIndicator* progress;
@property(strong) NSSearchField* search;
@property(strong) NSSegmentedControl* filter;
@property(strong) NSTableView* table;
- (void)updateRows:(NSArray<NSDictionary*>*)rows;
@end

@implementation AliceAchievementsController
- (instancetype)init {
  self = [super initWithWindow:Window(L(@"Достижения"), 760, 640, YES)];
  if (!self) return nil;
  self.window.minSize = NSMakeSize(680, 460);
  NSView* root = self.window.contentView;
  self.summary = Label(@"", NSMakeRect(24, 578, 712, 34), 22);
  self.summary.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
  [root addSubview:self.summary];
  self.progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(24, 554, 712, 12)];
  self.progress.indeterminate = NO;
  self.progress.minValue = 0; self.progress.maxValue = 1;
  self.progress.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
  [root addSubview:self.progress];
  self.filter = [NSSegmentedControl segmentedControlWithLabels:@[L(@"Все"), L(@"Получены"), L(@"Закрыты")]
      trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(filterChanged:)];
  self.filter.selectedSegment = 0;
  self.filter.frame = NSMakeRect(24, 502, 352, 30);
  self.filter.autoresizingMask = NSViewMinYMargin;
  [root addSubview:self.filter];
  self.search = [[NSSearchField alloc] initWithFrame:NSMakeRect(410, 502, 326, 30)];
  self.search.placeholderString = L(@"Поиск достижений");
  self.search.delegate = self;
  self.search.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
  [root addSubview:self.search];
  NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 16, 728, 470)];
  scroll.hasVerticalScroller = YES;
  scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.table = [[NSTableView alloc] initWithFrame:scroll.bounds];
  NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"achievement"];
  column.width = 700;
  column.resizingMask = NSTableColumnAutoresizingMask;
  [self.table addTableColumn:column];
  self.table.headerView = nil;
  self.table.rowHeight = 112;
  self.table.intercellSpacing = NSMakeSize(0, 4);
  self.table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
  self.table.dataSource = self; self.table.delegate = self;
  self.table.usesAlternatingRowBackgroundColors = YES;
  self.table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
  scroll.documentView = self.table;
  [root addSubview:scroll];
  self.empty = Label(@"", NSMakeRect(70, 240, 620, 80), 15, YES);
  self.empty.alignment = NSTextAlignmentCenter;
  self.empty.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
  [root addSubview:self.empty];
  self.rows = @[]; self.filtered = @[];
  return self;
}
- (void)updateRows:(NSArray<NSDictionary*>*)rows {
  self.rows = rows;
  NSUInteger unlocked = 0, earned = 0, total = 0;
  for (NSDictionary* row in rows) {
    total += [row[@"score"] unsignedIntegerValue];
    if ([row[@"unlocked"] boolValue]) { ++unlocked; earned += [row[@"score"] unsignedIntegerValue]; }
  }
  self.summary.stringValue = [NSString stringWithFormat:L(@"%lu из %lu · %lu / %lu G"),
      (unsigned long)unlocked, (unsigned long)rows.count, (unsigned long)earned, (unsigned long)total];
  self.progress.doubleValue = rows.count ? double(unlocked) / rows.count : 0;
  [self filterChanged:nil];
}
- (void)controlTextDidChange:(NSNotification*)notification { [self filterChanged:nil]; }
- (void)filterChanged:(id)sender {
  NSMutableArray* filtered = [NSMutableArray new];
  NSString* query = self.search.stringValue;
  for (NSDictionary* row in self.rows) {
    BOOL unlocked = [row[@"unlocked"] boolValue];
    if ((self.filter.selectedSegment == 1 && !unlocked) || (self.filter.selectedSegment == 2 && unlocked)) continue;
    if (query.length && ![row[@"title"] localizedCaseInsensitiveContainsString:query] &&
        ![row[@"description"] localizedCaseInsensitiveContainsString:query]) continue;
    [filtered addObject:row];
  }
  self.filtered = filtered;
  self.empty.stringValue = self.rows.count ? L(@"Нет достижений для выбранного фильтра.") : L(@"Список достижений появится после загрузки игры.");
  self.empty.hidden = filtered.count > 0;
  [self.table reloadData];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView { return self.filtered.count; }
- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)column row:(NSInteger)index {
  NSDictionary* row = self.filtered[index];
  NSTableCellView* cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, column.width, 112)];
  NSImageView* icon = [[NSImageView alloc] initWithFrame:NSMakeRect(12, 24, 64, 64)];
  icon.image = row[@"icon"];
  icon.imageScaling = NSImageScaleProportionallyUpOrDown;
  icon.alphaValue = [row[@"unlocked"] boolValue] ? 1 : 0.65;
  [cell addSubview:icon];
  NSTextField* title = Label(row[@"title"], NSMakeRect(92, 78, column.width - 182, 25), 15);
  title.font = [NSFont boldSystemFontOfSize:15];
  title.autoresizingMask = NSViewWidthSizable;
  [cell addSubview:title];
  NSTextField* score = Label([NSString stringWithFormat:@"%@ G", row[@"score"]], NSMakeRect(column.width - 82, 78, 64, 25), 13, YES);
  score.alignment = NSTextAlignmentRight;
  score.autoresizingMask = NSViewMinXMargin;
  [cell addSubview:score];
  NSTextField* description = Label(row[@"description"], NSMakeRect(92, 32, column.width - 110, 42), 13);
  description.autoresizingMask = NSViewWidthSizable;
  [cell addSubview:description];
  NSTextField* state = Label(row[@"state"], NSMakeRect(92, 6, column.width - 110, 23), 12, YES);
  state.autoresizingMask = NSViewWidthSizable;
  [cell addSubview:state];
  return cell;
}
@end

@interface AliceDesktopMenus : NSObject <NSMenuItemValidation>
- (void)settings:(id)sender;
- (void)achievements:(id)sender;
- (void)about:(id)sender;
- (void)project:(id)sender;
- (void)refreshMenus:(NSNotification*)notification;
@end

static NSURL* ProjectURL() {
  return [NSURL URLWithString:@"https://github.com/TheCodeGuardian/AliceMacnessReturns"];
}
static NSDictionary* AboutOptions() {
  NSString* description = L(@"Неофициальный порт Alice: Madness Returns для macOS на основе версии для Xbox 360 от TheCodeGuardian. Все права на игру и материалы принадлежат правообладателям.");
  NSMutableParagraphStyle* paragraph = [NSMutableParagraphStyle new];
  paragraph.alignment = NSTextAlignmentCenter;
  NSAttributedString* credits = [[NSAttributedString alloc] initWithString:description attributes:@{
      NSFontAttributeName: [NSFont systemFontOfSize:12],
      NSForegroundColorAttributeName: NSColor.labelColor,
      NSParagraphStyleAttributeName: paragraph}];
  return @{NSAboutPanelOptionApplicationName: @"AliceMacnessReturns",
      NSAboutPanelOptionApplicationVersion: NSBundle.mainBundle.infoDictionary[@"AliceDisplayVersion"] ?: @"0.1.a",
      NSAboutPanelOptionVersion: @"",
      NSAboutPanelOptionCredits: credits};
}
@implementation AliceDesktopMenus
- (void)settings:(id)sender { alice::desktop::ShowSettings(); }
- (void)achievements:(id)sender { alice::desktop::ShowAchievements(); }
- (void)about:(id)sender { [NSApp orderFrontStandardAboutPanelWithOptions:AboutOptions()]; }
- (void)project:(id)sender { [NSWorkspace.sharedWorkspace openURL:ProjectURL()]; }
- (BOOL)validateMenuItem:(NSMenuItem*)item { return NSApp.modalWindow == nil; }
- (void)refreshMenus:(NSNotification*)notification { alice::desktop::RefreshMenus(); }
@end

namespace {
AliceDesktopMenus* menuTarget;
AlicePreferencesController* preferences;
AliceAchievementsController* achievementWindow;
rex::system::AchievementManager* achievementManager;
rex::Runtime* activeRuntime;
uint64_t unlockListener;
bool achievementsPending = false;
bool desktopShuttingDown = false;
NSMutableArray<NSMenuItem*>* installedItems;
NSMenu* installedMainMenu;
bool installingMenus = false;
bool HasMenuAction(NSMenu* menu, SEL action) {
  for (NSMenuItem* item in menu.itemArray) {
    if (item.action == action && item.target == menuTarget) return true;
    if (item.submenu && HasMenuAction(item.submenu, action)) return true;
  }
  return false;
}
void RefreshAchievements() {
  if (achievementManager && achievementWindow)
    [achievementWindow updateRows:AchievementRows(*achievementManager, activeRuntime)];
}
NSArray* MenuSnapshot(NSMenu* menu) {
  NSMutableArray* result = [NSMutableArray new];
  for (NSMenuItem* item in menu.itemArray) {
    if (item.separatorItem) continue;
    [result addObject:@{@"title": item.title, @"shortcut": item.keyEquivalent,
        @"action": item.action ? NSStringFromSelector(item.action) : @"",
        @"items": item.submenu ? MenuSnapshot(item.submenu) : @[]}];
  }
  return result;
}
void ExportMenus(const std::filesystem::path& directory) {
  NSMutableArray* windows = [NSMutableArray new];
  for (NSWindow* window in NSApp.windows) [windows addObject:window.title];
  NSDictionary* snapshot = @{@"language": alice::desktop::UsesRussian() ? @"ru" : @"en",
      @"preferred_languages": NSLocale.preferredLanguages,
      @"bundle_localizations": NSBundle.mainBundle.preferredLocalizations,
      @"menus": MenuSnapshot(NSApp.mainMenu), @"windows": windows,
      @"about_name": AboutOptions()[NSAboutPanelOptionApplicationName],
      @"display_version": AboutOptions()[NSAboutPanelOptionApplicationVersion],
      @"about_description": [AboutOptions()[NSAboutPanelOptionCredits] string],
      @"project": ProjectURL().absoluteString};
  NSError* error = nil;
  NSData* data = [NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingPrettyPrinted error:&error];
  if (![data writeToFile:Text((directory / "menus.json").string()) options:NSDataWritingAtomic error:&error])
    throw std::runtime_error("Menu export failed");
}
void ExportView(NSWindow* window, const std::filesystem::path& file) {
  [window.contentView layoutSubtreeIfNeeded];
  [window displayIfNeeded];
  [CATransaction flush];
  // Modern AppKit controls commit their layer contents on the next UI turn.
  [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]];
  NSBitmapImageRep* bitmap = [window.contentView bitmapImageRepForCachingDisplayInRect:window.contentView.bounds];
  [window.contentView cacheDisplayInRect:window.contentView.bounds toBitmapImageRep:bitmap];
  NSData* png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
  NSError* error = nil;
  if (!png || ![png writeToFile:Text(file.string()) options:NSDataWritingAtomic error:&error])
    throw std::runtime_error("Native view export failed");
}
}

namespace alice::desktop {
bool ShowSetupWizard(Settings& settings, const std::string& reason) {
  InstallMenus();
  NSString* iconPath = [NSBundle.mainBundle pathForResource:@"alice" ofType:@"icns"];
  if (iconPath) NSApp.applicationIconImage = [[NSImage alloc] initWithContentsOfFile:iconPath];
  auto controller = [[AlicePreferencesController alloc] initWithSettings:settings wizard:YES reason:Text(reason)];
  [NSApp activateIgnoringOtherApps:YES];
  [NSApp runModalForWindow:controller.window];
  if (controller.accepted) settings = controller->result_;
  return controller.accepted;
}
void InstallMenus() {
  if (desktopShuttingDown || installingMenus) return;
  NSMenu* current = NSApp.mainMenu;
  if (menuTarget && installedMainMenu == current &&
      HasMenuAction(current, @selector(settings:)) &&
      HasMenuAction(current, @selector(achievements:)) &&
      HasMenuAction(current, @selector(project:))) return;
  installingMenus = true;
  struct InstallGuard { ~InstallGuard() { installingMenus = false; } } guard;
  if (!menuTarget) {
    menuTarget = [AliceDesktopMenus new];
    [NSNotificationCenter.defaultCenter addObserver:menuTarget selector:@selector(refreshMenus:)
        name:NSApplicationDidBecomeActiveNotification object:NSApp];
    [NSNotificationCenter.defaultCenter addObserver:menuTarget selector:@selector(refreshMenus:)
        name:NSWindowDidBecomeMainNotification object:nil];
  }
  for (NSMenuItem* item in installedItems) {
    if (item.submenu && item.submenu == NSApp.helpMenu) NSApp.helpMenu = nil;
    [item.menu removeItem:item];
  }
  installedItems = [NSMutableArray new];
  if (!NSApp.mainMenu) NSApp.mainMenu = [[NSMenu alloc] initWithTitle:@""];
  NSMenu* main = NSApp.mainMenu;
  if (!main.numberOfItems) {
    NSMenuItem* appItem = [[NSMenuItem alloc] initWithTitle:@"Alice: Madness Returns" action:nil keyEquivalent:@""];
    appItem.submenu = [[NSMenu alloc] initWithTitle:@"Alice: Madness Returns"];
    [appItem.submenu addItemWithTitle:L(@"О AliceMacnessReturns")
        action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appItem.submenu addItem:NSMenuItem.separatorItem];
    [appItem.submenu addItemWithTitle:L(@"Настройки…") action:nil keyEquivalent:@","];
    [appItem.submenu addItem:NSMenuItem.separatorItem];
    [appItem.submenu addItemWithTitle:L(@"Завершить Alice: Madness Returns") action:@selector(terminate:) keyEquivalent:@"q"];
    [main addItem:appItem];
  }
  NSMenuItem* appItem = [main itemAtIndex:0];
  appItem.title = @"Alice: Madness Returns";
  NSMenu* app = appItem.submenu;
  app.title = appItem.title;
  NSMenuItem* settings = nil;
  for (NSMenuItem* item in app.itemArray) {
    if ([item.keyEquivalent isEqual:@","]) settings = item;
    if (item.action == @selector(orderFrontStandardAboutPanel:) || item.action == @selector(about:)) {
      item.title = L(@"О AliceMacnessReturns");
      item.action = @selector(about:); item.target = menuTarget;
    } else if (item.action == @selector(hide:)) item.title = L(@"Скрыть Alice: Madness Returns");
    else if (item.action == @selector(hideOtherApplications:)) item.title = L(@"Скрыть остальные");
    else if (item.action == @selector(unhideAllApplications:)) item.title = L(@"Показать все");
    else if (item.action == @selector(terminate:)) item.title = L(@"Завершить Alice: Madness Returns");
    else if (item.submenu && item.submenu == NSApp.servicesMenu) {
      item.title = L(@"Службы"); item.submenu.title = item.title;
    }
  }
  // SDL supplies the standard Settings/Preferences slot with a nil action.
  // Reuse that exact item, including its normal position and Command-comma.
  if (!settings) {
    settings = [[NSMenuItem alloc] initWithTitle:L(@"Настройки…") action:nil keyEquivalent:@","];
    [app insertItem:settings atIndex:MIN(2, app.numberOfItems)];
  }
  settings.title = L(@"Настройки…");
  settings.action = @selector(settings:);
  settings.target = menuTarget;
  settings.keyEquivalentModifierMask = NSEventModifierFlagCommand;

  NSMenu* windows = NSApp.windowsMenu;
  for (NSMenuItem* item in main.itemArray) {
    if (windows && item.submenu == windows) { item.title = L(@"Окно"); windows.title = item.title; }
  }
  for (NSMenuItem* item in windows.itemArray) {
    if (item.action == @selector(performClose:)) item.title = L(@"Закрыть");
    else if (item.action == @selector(performMiniaturize:)) item.title = L(@"Свернуть");
    else if (item.action == @selector(performZoom:)) item.title = L(@"Развернуть");
    else if (item.action == @selector(toggleFullScreen:)) item.title = L(@"Полноэкранный режим");
    else if (item.action == @selector(arrangeInFront:)) item.title = L(@"На передний план");
  }
  // There is no Edit menu in the game. Native text windows handle their
  // clipboard shortcuts directly, without adding a menu to the game bar.
  for (NSMenuItem* item in [main.itemArray copy])
    if ([item.title isEqual:@"Edit"] || [item.title isEqual:@"Правка"]) [main removeItem:item];
  NSMenuItem* game = [[NSMenuItem alloc] initWithTitle:L(@"Игра") action:nil keyEquivalent:@""];
  game.submenu = [[NSMenu alloc] initWithTitle:game.title];
  NSMenuItem* achievements = [[NSMenuItem alloc] initWithTitle:L(@"Достижения") action:@selector(achievements:) keyEquivalent:@"a"];
  achievements.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
  achievements.target = menuTarget;
  [game.submenu addItem:achievements];
  NSInteger windowIndex = windows ? [main indexOfItemWithSubmenu:windows] : -1;
  [main insertItem:game atIndex:windowIndex >= 0 ? windowIndex : main.numberOfItems];
  [installedItems addObject:game];

  NSMenu* help = NSApp.helpMenu;
  if (!help) {
    NSMenuItem* helpItem = [[NSMenuItem alloc] initWithTitle:L(@"Справка") action:nil keyEquivalent:@""];
    helpItem.submenu = [[NSMenu alloc] initWithTitle:helpItem.title];
    [main addItem:helpItem]; [installedItems addObject:helpItem];
    help = helpItem.submenu; NSApp.helpMenu = help;
  } else {
    help.title = L(@"Справка");
    for (NSMenuItem* item in main.itemArray) if (item.submenu == help) item.title = help.title;
  }
  NSMenuItem* project = [[NSMenuItem alloc] initWithTitle:L(@"Проект на GitHub") action:@selector(project:) keyEquivalent:@""];
  project.target = menuTarget;
  [help addItem:project]; [installedItems addObject:project];

  // Publish a fresh root after filling it. Mutating SDL's already-published
  // root alone may leave the visible menu bar at its initial minimal layout.
  // Move items instead of copying them to preserve standard system item,
  // Services, Window and Help menu identities and their responder actions.
  NSMenu* published = [[NSMenu alloc] initWithTitle:main.title];
  for (NSMenuItem* item in [main.itemArray copy]) {
    [main removeItem:item];
    [published addItem:item];
  }
  installedMainMenu = published;
  NSApp.mainMenu = published;
  [published update];
}
void RefreshMenus() {
  if (installingMenus || desktopShuttingDown) return;
  installedMainMenu = nil;
  InstallMenus();
}
void ShowSettings() {
  if (preferences.window.visible) { [preferences.window makeKeyAndOrderFront:nil]; return; }
  preferences = [[AlicePreferencesController alloc] initWithSettings:CurrentSettings() wizard:NO reason:@""];
  [preferences showWindow:nil];
  [NSApp activateIgnoringOtherApps:YES];
}
void ShowAchievements() {
  if (desktopShuttingDown) return;
  if (!achievementManager) { achievementsPending = true; return; }
  achievementsPending = false;
  if (!achievementWindow) achievementWindow = [AliceAchievementsController new];
  RefreshAchievements();
  [achievementWindow showWindow:nil];
  [NSApp activateIgnoringOtherApps:YES];
}
void Attach(rex::system::AchievementManager& achievements, rex::Runtime* runtime) {
  desktopShuttingDown = false;
  achievementManager = &achievements;
  activeRuntime = runtime;
  unlockListener = achievements.RegisterUnlockCallback([](const rex::system::AchievementEvent&) {
    dispatch_async(dispatch_get_main_queue(), ^{ RefreshAchievements(); });
  });
  if (achievementsPending) ShowAchievements();
  if (!REXCVAR_GET(alice_desktop_capture).empty()) {
    std::filesystem::path directory(REXCVAR_GET(alice_desktop_capture));
    std::filesystem::create_directories(directory);
    ExportMenus(directory);
    ShowSettings();
    ExportView(preferences.window, directory / "settings.png");
    [preferences.window orderOut:nil];
    ShowAchievements();
    ExportView(achievementWindow.window, directory / "achievements.png");
    if (achievementWindow.rows.count > 14) {
      [achievementWindow.table scrollRowToVisible:14];
      ExportView(achievementWindow.window, directory / "achievements-public.png");
      [achievementWindow.table scrollRowToVisible:0];
    }
    REXLOG_INFO("[desktop] native views exported; {} Xbox achievements", achievementWindow.rows.count);
    [achievementWindow.window orderOut:nil];
  }
}
void Detach() {
  desktopShuttingDown = true;
  achievementsPending = false;
  if (achievementManager && unlockListener) achievementManager->UnregisterCallback(unlockListener);
  unlockListener = 0; achievementManager = nullptr; activeRuntime = nullptr;
  [preferences.window orderOut:nil]; preferences = nil;
  [achievementWindow.window orderOut:nil]; achievementWindow = nil;
  if (menuTarget) [NSNotificationCenter.defaultCenter removeObserver:menuTarget];
  for (NSMenuItem* item in installedItems) [item.menu removeItem:item];
  installedItems = nil; installedMainMenu = nil; menuTarget = nil;
}

bool RunSelfTests(const std::filesystem::path& directory) {
  try {
    auto require = [](bool valid, const char* message) {
      if (!valid) throw std::runtime_error(message);
    };
    std::filesystem::create_directories(directory);
    require(std::filesystem::is_empty(directory), "Test directory must be empty");
    auto config = directory / "настройки/settings.json";
    require(rex::cvar::SetFlagByName("alice_settings_file", config.string()), "Set isolated settings path");
    Settings settings = Defaults();
    settings.storage_directory = directory / "данные с пробелами";
    std::string error;
    require(ValidateSettings(settings, error), error.c_str());
    Settings invalid = settings;
    invalid.game_directory = directory;
    require(!ValidateSettings(invalid, error), "Missing XEX must be rejected");
    invalid = settings;
    invalid.storage_directory = settings.game_directory / "saves";
    require(!ValidateSettings(invalid, error), "Storage in game must be rejected");
    invalid = settings;
    invalid.game_directory = directory / "wrong-release";
    std::filesystem::create_directories(invalid.game_directory / "AliceGame");
    std::ofstream(invalid.game_directory / "default.xex") << "unsupported executable";
    require(!ValidateSettings(invalid, error), "Unsupported game release must be rejected");

    require(IsRussianLanguage("ru-RU") && IsRussianLanguage("ru_Cyrl_RU") &&
        !IsRussianLanguage("en-RU") && !IsRussianLanguage("fr-FR") && !IsRussianLanguage(""),
        "Only a Russian primary language enables Russian UI");
    require(alice::macos::TestNotificationLocalization(), "Notification content follows the system UI language");
    NSMenu* applicationMenu = [NSApp.mainMenu itemAtIndex:0].submenu;
    NSMenuItem* originalSettings = nil;
    NSInteger originalSettingsIndex = -1;
    for (NSMenuItem* item in applicationMenu.itemArray)
      if ([item.keyEquivalent isEqual:@","]) { originalSettings = item; originalSettingsIndex = [applicationMenu indexOfItem:item]; }
    InstallMenus();
    applicationMenu = [NSApp.mainMenu itemAtIndex:0].submenu;
    NSInteger settingsCount = 0;
    for (NSMenuItem* item in applicationMenu.itemArray) {
      if ([item.keyEquivalent isEqual:@","]) {
        ++settingsCount;
        require(item.action == @selector(settings:) && item.target == menuTarget,
            "The native Settings item must open our settings");
        if (originalSettings) require(item == originalSettings && [applicationMenu indexOfItem:item] == originalSettingsIndex,
            "Reuse the original macOS Settings item in place");
      }
    }
    require(settingsCount == 1, "Exactly one standard Settings item");
    require([NSApp.windowsMenu.title isEqual:L(@"Окно")], "Localize the standard Window menu");
    require([NSApp.helpMenu.title isEqual:L(@"Справка")] &&
        [NSApp.helpMenu itemWithTitle:L(@"Проект на GitHub")].action == @selector(project:), "GitHub Help command");
    require([ProjectURL().absoluteString isEqual:@"https://github.com/TheCodeGuardian/AliceMacnessReturns"], "Exact project URL");
    require([applicationMenu itemWithTitle:L(@"О AliceMacnessReturns")].action == @selector(about:) &&
        [AboutOptions()[NSAboutPanelOptionApplicationName] isEqual:@"AliceMacnessReturns"], "Standard About panel and project name");
    require([[NSApp.mainMenu itemAtIndex:0].title isEqual:@"Alice: Madness Returns"], "Application menu uses the game title");
    require([AboutOptions()[NSAboutPanelOptionApplicationVersion] isEqual:@"0.1.a"] &&
        [AboutOptions()[NSAboutPanelOptionVersion] isEqual:@""], "Display alpha version without numeric build suffix");
    require([NSApp.mainMenu indexOfItemWithTitle:@"Правка"] == -1 &&
        [NSApp.mainMenu indexOfItemWithTitle:@"Edit"] == -1, "No Edit menu in either language");
    require([NSApp.mainMenu itemWithTitle:L(@"Игра")].submenu.numberOfItems == 1 &&
        [[NSApp.mainMenu itemWithTitle:L(@"Игра")].submenu itemWithTitle:L(@"Достижения")] != nil,
        "Game menu uses the short Achievements title");
    require([L(@"Настройки…") isEqual:UsesRussian() ? @"Настройки…" : @"Settings…"], "Localized settings label");
    // Reproduce the minimal SDL bar from the reported screenshot, then send
    // the same activation notification used by the real application.
    NSMenu* previous = NSApp.mainMenu;
    NSMenu* minimal = [[NSMenu alloc] initWithTitle:@"SDL minimal menu"];
    for (NSMenuItem* item in [previous.itemArray copy]) {
      if (item.submenu == applicationMenu || item.submenu == NSApp.windowsMenu) {
        [previous removeItem:item];
        [minimal addItem:item];
      }
    }
    NSApp.mainMenu = minimal;
    [NSNotificationCenter.defaultCenter postNotificationName:NSApplicationDidBecomeActiveNotification object:NSApp];
    require(NSApp.mainMenu != minimal && HasMenuAction(NSApp.mainMenu, @selector(achievements:)) &&
        HasMenuAction(NSApp.mainMenu, @selector(project:)), "Activation republishes the full menu after an SDL reset");
    for (int i = 0; i < 4; ++i) RefreshMenus();
    require(NSApp.mainMenu.numberOfItems == 4 &&
        [NSApp.mainMenu itemWithTitle:L(@"Игра")] && [NSApp.mainMenu itemWithTitle:L(@"Справка")],
        "Repeated window activation must not duplicate or lose menus");
    ExportMenus(directory);
    // Drive the actual modal controller, including cancellation and all pages.
    auto cancelled = [[AlicePreferencesController alloc] initWithSettings:settings wizard:YES reason:@""];
    dispatch_async(dispatch_get_main_queue(), ^{ [cancelled cancel:nil]; });
    [NSApp runModalForWindow:cancelled.window];
    require(!cancelled.accepted && !std::filesystem::exists(config), "Cancel must not write configuration");
    auto wizard = [[AlicePreferencesController alloc] initWithSettings:settings wizard:YES reason:@""];
    dispatch_async(dispatch_get_main_queue(), ^{
      ExportView(wizard.window, directory / "wizard-welcome.png");
      [wizard advance:nil];
      ExportView(wizard.window, directory / "wizard-folders.png");
      [wizard advance:nil];
      ExportView(wizard.window, directory / "wizard-options.png");
      [wizard advance:nil];
      if (!wizard.accepted) [wizard cancel:nil];
    });
    [NSApp runModalForWindow:wizard.window];
    require(wizard.accepted, "Wizard must accept valid settings");
    Settings loaded;
    require(LoadSettings(loaded, error), "Reload settings");
    require(loaded.storage_directory == settings.storage_directory && loaded.game_directory == settings.game_directory,
        "Unicode paths must survive serialization");
    loaded.mute = true; loaded.notifications = false; loaded.vsync = false;
    require(SaveSettings(loaded, error), "Save toggles");
    require(LoadSettings(settings, error) && settings.mute && !settings.notifications && !settings.vsync,
        "Saved toggles must survive restart");
    NSData* before = [NSData dataWithContentsOfFile:Text(config.string())];
    invalid = settings;
    invalid.storage_directory = directory / "not-a-directory";
    std::ofstream(invalid.storage_directory) << "keep this file";
    require(!SaveSettings(invalid, error), "Unwritable storage must be rejected");
    require([before isEqual:[NSData dataWithContentsOfFile:Text(config.string())]], "Failed save must preserve config");
    std::ofstream(config) << "{broken-json";
    require(!LoadSettings(loaded, error), "Corrupt config must be rejected");
    require(SaveSettings(settings, error), "Restore fixture config");
    CommitSettings(settings);
    require(!AchievementNotificationsEnabled(), "Live notification preference");

    auto source = directory / "old";
    auto destination = directory / "new";
    std::filesystem::create_directories(source / "user/achievements");
    std::ofstream(source / "user/save.dat") << "original save";
    std::ofstream(source / "user/achievements/unlocks.toml") << "achievement fixture";
    require(CopyUserData(source, destination, error), "Copy saves and achievements");
    require(std::filesystem::exists(source / "user/save.dat") &&
        std::filesystem::exists(destination / "user/achievements/unlocks.toml"), "Copy must preserve source");
    require(!CopyUserData(source, destination, error), "Existing destination must never be overwritten");
    require(!CopyUserData(source, source / "nested", error), "Nested copy must be rejected");
    require(!CopyUserData(directory / "missing-disk", destination, error), "Missing source must not silently start an empty profile");

    rex::system::AchievementManager manager;
    manager.SetUnlockSavePath(directory / "fixture-unlocks.toml");
    manager.RegisterAchievement({.id=1, .label="Обычное достижение", .description="Условие выполнено",
        .unachieved_description="Обычное условие", .gamerscore=10, .flags=8});
    manager.RegisterAchievement({.id=2, .label="SECRET TITLE", .description="SECRET DESCRIPTION",
        .unachieved_description="SECRET LOCKED TEXT", .gamerscore=20, .flags=0});
    auto rows = AchievementRows(manager, nullptr);
    require([rows[1][@"title"] isEqual:L(@"Секретное достижение")], "Secret title must stay hidden");
    require([rows[1][@"description"] rangeOfString:@"SECRET"].location == NSNotFound, "Secret description leak");
    manager.UnlockAchievement(1);
    // Detach before the fixture manager is destroyed, including assertion
    // failures; the outer catch must never unregister against dead storage.
    struct AttachmentGuard { ~AttachmentGuard() { Detach(); } } attachmentGuard;
    require(!alice::macos::HandleNotificationAction("alice.dlc-unavailable", true), "DLC notification must not open achievements");
    require(!alice::macos::HandleNotificationAction("alice.achievement.1", false), "Dismissing must not open achievements");
    require(achievementWindow == nil, "No achievement window before click");
    require(alice::macos::HandleNotificationAction("alice.achievement.1", true) && achievementWindow == nil,
        "Achievement click waits for runtime attachment");
    Attach(manager, nullptr);
    require(achievementWindow.window.visible && [achievementWindow.window.title isEqual:L(@"Достижения")],
        "Deferred click opens the achievements window with a short title");
    [achievementWindow.window orderOut:nil];
    require(!alice::macos::HandleNotificationAction("alice.achievement.1", false) && !achievementWindow.window.visible,
        "Dismiss must leave the achievements window closed");
    require(alice::macos::HandleNotificationAction("alice.achievement.1", true) && achievementWindow.window.visible,
        "Click opens achievements in the live application");
    require(achievementWindow.rows.count == 2 && achievementWindow.progress.doubleValue == 0.5,
        "Real manager unlock count");
    achievementWindow.search.stringValue = @"SECRET TITLE";
    [achievementWindow filterChanged:nil];
    require(achievementWindow.filtered.count == 0, "Search must not disclose secrets");
    achievementWindow.search.stringValue = @"";
    achievementWindow.filter.selectedSegment = 1;
    [achievementWindow filterChanged:nil];
    require(achievementWindow.filtered.count == 1, "Unlocked filter");
    achievementWindow.filter.selectedSegment = 0;
    [achievementWindow filterChanged:nil];
    ExportView(achievementWindow.window, directory / "achievements-fixture.png");
    manager.UnlockAchievement(2);
    RefreshAchievements();
    require([achievementWindow.rows[1][@"title"] isEqual:@"SECRET TITLE"], "Unlock must reveal Xbox achievement");
    rex::system::AchievementManager reopened;
    reopened.SetUnlockSavePath(directory / "fixture-unlocks.toml");
    reopened.LoadUnlockState();
    require(reopened.IsUnlocked(1) && reopened.IsUnlocked(2), "Unlocks survive manager restart");
    ShowSettings();
    ExportView(preferences.window, directory / "settings.png");
    [preferences.window makeFirstResponder:preferences.gamePath];
    NSEvent* selectAll = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:preferences.window.windowNumber
        context:nil characters:@"a" charactersIgnoringModifiers:@"a" isARepeat:NO keyCode:0];
    require([preferences.window performKeyEquivalent:selectAll] &&
        [(NSTextView*)preferences.window.firstResponder selectedRange].length == preferences.gamePath.stringValue.length,
        "Text editing shortcuts work without an Edit menu");
    preferences.mute.state = NSControlStateValueOff;
    preferences.notifications.state = NSControlStateValueOn;
    [preferences.next performClick:nil];
    require(preferences.accepted && AchievementNotificationsEnabled() &&
        rex::cvar::GetFlagByName("audio_mute") == "false", "Settings must apply live mute and notifications");
    // Validate and export again after native windows, modal loops and AppKit
    // menu validation have run, rather than relying on the initial labels.
    for (NSMenuItem* item in NSApp.mainMenu.itemArray) [item.submenu update];
    require([NSApp.windowsMenu.title isEqual:UsesRussian() ? @"Окно" : @"Window"],
        "Window menu retains the process language after AppKit validation");
    ExportMenus(directory);
    Detach();
    REXLOG_INFO("[desktop-test] passed: wizard, cancellation, persistence, safe copying, Xbox unlocks and secrets");
    return true;
  } catch (const std::exception& error) {
    Detach();
    REXLOG_ERROR("[desktop-test] failed: {}", error.what());
    return false;
  }
}
}

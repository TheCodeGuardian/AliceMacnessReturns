#include "macos_localization.h"

namespace alice::desktop {
bool IsRussianLanguage(std::string_view language) {
  NSString* identifier = [[NSString alloc] initWithBytes:language.data() length:language.size()
      encoding:NSUTF8StringEncoding];
  if (!identifier.length) return false;
  NSString* code = [NSLocale componentsFromLocaleIdentifier:identifier][NSLocaleLanguageCode];
  return code && [code caseInsensitiveCompare:@"ru"] == NSOrderedSame;
}
bool UsesRussian() {
  static const bool russian = [] {
    NSString* primary = NSLocale.preferredLanguages.firstObject ?: @"en";
    return IsRussianLanguage(primary.UTF8String);
  }();
  return russian;
}
std::string Localized(std::string_view russian) {
  NSString* key = [[NSString alloc] initWithBytes:russian.data() length:russian.size()
      encoding:NSUTF8StringEncoding];
  return AliceLocalized(key).UTF8String;
}
}
NSString* AliceLocalized(NSString* russian) {
  if (alice::desktop::UsesRussian()) return russian;
  static NSBundle* english = [NSBundle bundleWithPath:
      [NSBundle.mainBundle pathForResource:@"en" ofType:@"lproj"]];
  return [english localizedStringForKey:russian value:russian table:@"Localizable"];
}

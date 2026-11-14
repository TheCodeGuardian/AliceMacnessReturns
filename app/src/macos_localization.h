#pragma once
#include <string>
#include <string_view>
namespace alice::desktop {
bool UsesRussian();
bool IsRussianLanguage(std::string_view language);
std::string Localized(std::string_view russian);
}
#ifdef __OBJC__
#import <Foundation/Foundation.h>
NSString* AliceLocalized(NSString* russian);
#endif

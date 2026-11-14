#pragma once
#import <Foundation/Foundation.h>
#include <rex/system/achievement_store.h>
namespace rex { class Runtime; }
NSData* AliceAchievementImage(const rex::system::AchievementInfo& info, rex::Runtime* runtime);

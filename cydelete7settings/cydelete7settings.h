//
//  cydelete7settings.h
//  cydelete7settings
//
//  Created by Ryan Burke on 03.01.2014.
//  Copyright (c) 2014 Ryan Burke. All rights reserved.
//
#include "Preferences/PSSpecifier.h"
#include "Preferences/PSListController.h"

static CFNotificationCenterRef darwinNotifyCenter;

@interface UIDevice (wc)
- (BOOL)isWildcat;
@end

@interface cydelete7settingsListController : PSListController

- (id)specifiers;
- (void)ryanDonate:(id)arg;
- (void)dustinDonate:(id)arg;
- (void)viewSource:(id)arg;
- (void)setPreferenceValue:(id)value specifier:(id)specifier;

@end

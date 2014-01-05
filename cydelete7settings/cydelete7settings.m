//
//  cydelete7settings.m
//  cydelete7settings
//
//  Created by Ryan Burke on 03.01.2014.
//  Copyright (c) 2014 Ryan Burke. All rights reserved.
//

#import "cydelete7settings.h"

@implementation cydelete7settingsListController

-(id)init {
    self = [super init];
    if(self) {
        darwinNotifyCenter = CFNotificationCenterGetDarwinNotifyCenter();
    }
    return self;
}


- (id)specifiers {
	if (_specifiers == nil) {
		_specifiers = [self loadSpecifiersFromPlistName:@"cydelete7settings" target:self];
        [self localizedSpecifiersWithSpecifiers:_specifiers];
	}
	return _specifiers;
}

- (id)navigationTitle {
	return [[self bundle] localizedStringForKey:[super title] value:[super title] table:nil];
}

- (id)localizedSpecifiersWithSpecifiers:(NSArray *)specifiers {
    
    NSLog(@"localizedSpecifiersWithSpecifiers");
	for(PSSpecifier *curSpec in specifiers) {
		NSString *name = [curSpec name];
		if(name) {
			[curSpec setName:[[self bundle] localizedStringForKey:name value:name table:nil]];
		}
		NSString *footerText = [curSpec propertyForKey:@"footerText"];
		if(footerText)
			[curSpec setProperty:[[self bundle] localizedStringForKey:footerText value:footerText table:nil] forKey:@"footerText"];
		id titleDict = [curSpec titleDictionary];
		if(titleDict) {
			NSMutableDictionary *newTitles = [[NSMutableDictionary alloc] init];
			for(NSString *key in titleDict) {
				NSString *value = [titleDict objectForKey:key];
				[newTitles setObject:[[self bundle] localizedStringForKey:value value:value table:nil] forKey: key];
			}
			[curSpec setTitleDictionary:newTitles];
		}
	}
	return specifiers;
}

- (void)ryanDonate:(id)arg {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=4VBFWEFBUF56N"]];
}


- (void)dustinDonate:(id)arg {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=4275311"]];
}

- (void)viewSource:(id)arg {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/ryanb93/CyDelete7"]];
}


- (void)setPreferenceValue:(id)value specifier:(id)specifier {
	[super setPreferenceValue:value specifier:specifier];
	// Post a notification.
	NSString *notification = [specifier propertyForKey:@"postNotification"];
	if(notification)
		CFNotificationCenterPostNotification(darwinNotifyCenter, (__bridge CFStringRef)notification, NULL, NULL, true);
}

@end

//
//  CyDeleteListController.mm
//
//  Created by Ryan Burke on 03.01.2014.
//  Copyright (c) 2014 Ryan Burke. All rights reserved.
//
#include <UIKit/UIApplication.h>
#include <Preferences/PSSpecifier.h>
#include <Preferences/PSListController.h>

@interface CyDeleteListController : PSListController

- (id)specifiers;
- (void)donate:(id)arg;
- (void)viewSource:(id)arg;

@end

@implementation CyDeleteListController

- (id)specifiers {
	if (_specifiers == nil) {
		_specifiers = [[self loadSpecifiersFromPlistName:@"CyDelete" target:self] retain];
        [self localizedSpecifiersWithSpecifiers:_specifiers];
	}
	return _specifiers;
}

- (id)navigationTitle {
	return [[self bundle] localizedStringForKey:[super title] value:[super title] table:nil];
}

- (id)localized:(NSString *)key{
    return [[self bundle] localizedStringForKey:key value:key table:nil];
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

- (void)donate:(id)arg {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=4VBFWEFBUF56N"]];  
}

- (void)viewSource:(id)arg {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/ryanb93/CyDelete"]];
}


@end

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

- (void)donate2:(id)arg {
    UIAlertController* alert=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ palxex",[self localized:@"DONATE"]] message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[self localized:@"BITCOIN"] style:UIAlertActionStyleDefault handler:^(UIAlertAction* _Nonnull action)
        {
            NSURL *targetURL = [NSURL URLWithString:@"bitcoin:1EXrR9YSEEXtFSYWjNnwrhyRhc4DoQHhzC"];
            if([[UIApplication sharedApplication] canOpenURL:targetURL])
                [[UIApplication sharedApplication] openURL:targetURL];
            else{
                [[UIPasteboard generalPasteboard] setString:@"1EXrR9YSEEXtFSYWjNnwrhyRhc4DoQHhzC"];
                UIAlertController* alert=[UIAlertController alertControllerWithTitle:@"" message:@"BTC address 1EXrR9YSEEXtFSYWjNnwrhyRhc4DoQHhzC; have been copied in your pasteboard" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OKay" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController: alert animated:YES completion:nil];
            }
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:[self localized:@"ALIPAY"] style:UIAlertActionStyleDefault handler:^(UIAlertAction* _Nonnull action)
        {
            NSURL *targetURL = [NSURL URLWithString:@"alipayqr://platformapi/startapp?saId=10000007&qrcode=https%3A%2F%2Fqr.alipay.com%2Faex04760kwfblpiaho9mg00"];
            if([[UIApplication sharedApplication] canOpenURL:targetURL])
                [[UIApplication sharedApplication] openURL:targetURL];
            else
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://qr.alipay.com/aex04760kwfblpiaho9mg00"]];
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:[self localized:@"PAYPAL"] style:UIAlertActionStyleDefault handler:^(UIAlertAction* _Nonnull action)
        {[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://www.paypal.com/cgi-bin/webscr?cmd=_xclick&business=W25D7EKNG9JNQ&lc=C2&item_name=Donation&button_subtype=services"]];
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:[self localized:@"CANCEL"] style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController: alert animated:YES completion:nil];
}

- (void)viewSource:(id)arg {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/ryanb93/CyDelete"]];
}


@end

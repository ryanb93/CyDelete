//
//  CyDelete.xm
//  CyDelete
//
//  Created by Ryan Burke on 02.01.2014.
//  Copyright (c) 2014 Ryan Burke. All rights reserved.
//
//  Modified by Pal Lockheart on 12.04.2016.
//  Copyright (c) 2016 Pal Lockheart. All rights reserved.
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <substrate.h>

#import <SpringBoard/SpringBoard.h>
#import <SpringBoard/SBApplication.h>
#import <SpringBoard/SBIcon.h>
#import <SpringBoard/SBIconView.h>
#import <SpringBoard/SBApplicationIcon.h>
#import <SpringBoard/SBIconController.h>
#import <SpringBoard/SBIconModel.h>
#import <SpringBoard/SBApplicationController.h>
#import <mach/mach_host.h>
#import <dirent.h>
#import <spawn.h>

__attribute__((unused)) static NSMutableString *outputForShellCommand(NSString *cmd);
static void removeBundleFromMIList(NSString *bundle);
static NSBundle *cyDelBundle = nil;
static NSMutableDictionary *iconPackagesDict;
static NSOperationQueue *uninstallQueue;

#define SBLocalizedString(key) [[NSBundle mainBundle] localizedStringForKey:key value:@"None" table:@"SpringBoard"]
#define CDLocalizedString(key) [cyDelBundle localizedStringForKey:key value:key table:nil]

#ifndef kCFCoreFoundationVersionNumber_iOS_8_0
#define kCFCoreFoundationVersionNumber_iOS_8_0 1129.15
#endif

@interface CDUninstallOperation : NSOperation {
	BOOL _executing;
	BOOL _finished;
}
@end

@interface CDUninstallDpkgOperation : CDUninstallOperation<UIAlertViewDelegate> {
	NSString *_package;
}
@property (nonatomic, retain) NSString *package;
- (id)initWithPackage:(NSString *)package;
@end

//Loads the application translation bundle and stores it locally. 
static void initTranslation() {
    cyDelBundle = [NSBundle bundleWithPath:@"/Library/Application Support/CyDelete/CyDelete.bundle"];
}

static bool getCFBool(CFStringRef key, bool defaultValue) {
	//Sync the latest version of the preferences.
	bool synced = CFPreferencesAppSynchronize(CFSTR("com.ryanburke.cydelete"));
	//If the sync failed, lets just default to protecting Cydia for safety.
	if(!synced) return defaultValue;
	//Create a boolean object to hold the success value from next function.
	Boolean success;
	//Get the value of the key from the preferences.
	bool result = CFPreferencesGetAppBooleanValue(key, CFSTR("com.ryanburke.cydelete"), &success);
	//If the enabled key existed and we got the value okay.
	if(success) {
		//Return the value of the key.
		return result;
	}
	//If for some reason we couldn't get the value lets just default to protecting Cydia for safety.
	return defaultValue;
}

static bool getProtectCydia() {
	return getCFBool(CFSTR("CDProtectCydia"), true);
}

static bool getProtectPangu() {
	return getCFBool(CFSTR("CDProtectPangu"), true);
}

static bool getEnabled() {
	return getCFBool(CFSTR("enabled"), true);
}


// Thanks _BigBoss_!
__attribute__((unused)) static int getFreeMemory() {
	vm_size_t pageSize;
	host_page_size(mach_host_self(), &pageSize);
	struct vm_statistics vmStats;
	mach_msg_type_number_t infoCount = sizeof(vmStats);
	host_statistics(mach_host_self(), HOST_VM_INFO, (host_info_t)&vmStats, &infoCount);
	int availMem = vmStats.free_count + vmStats.inactive_count;
	return (availMem * pageSize) / 1024 / 1024;
}

__attribute__((unused)) static NSMutableString *outputForShellCommand(NSString *cmd) {
	FILE *fp;
	char buf[1024];
	NSMutableString* finalRet;

	fp = popen([cmd UTF8String], "r");
	if (fp == NULL) {
		return nil;
	}

	fgets(buf, 1024, fp);
	finalRet = [NSMutableString stringWithUTF8String:buf];

	if(pclose(fp) != 0) {
		return nil;
	}

	return finalRet;
}


#define fexists(n) access(n, F_OK)

static char *owner(const char *_bundle, const char *_title, const char *_path) {
	char bundle[1024], title[1024];
	static char pkgname[256];
	int pathlen = strlen(_path);

	snprintf(bundle, 1024, "/var/lib/dpkg/info/%s.list", _bundle);
	snprintf(title, 1024, "/var/lib/dpkg/info/%s.list", _title);
	if(fexists(bundle) == 0) {
		strcpy(pkgname, _bundle);
		return pkgname;
	} else if(fexists(title) == 0) {
		strcpy(pkgname, _title);
		return pkgname;
	}

	DIR *d = opendir("/var/lib/dpkg/info");
	if(!d) return NULL;
	struct dirent *ent;
	while((ent = readdir(d)) != NULL) {
		int namelen = strlen(ent->d_name);
		if(strcmp(ent->d_name + namelen - 5, ".list") != 0) continue;
		char curpath[1024];
		snprintf(curpath, 1024, "/var/lib/dpkg/info/%s", ent->d_name);
		FILE *fp = fopen(curpath, "r");
		char curfn[1024];
		while(fgets(curfn, 1024, fp) != NULL) {
			if(strncmp(_path, curfn, pathlen) == 0) {
				strncpy(pkgname, ent->d_name, namelen - 5);
				pkgname[namelen - 5] = '\0';
				fclose(fp);
				closedir(d);
				return pkgname;
			}
		}
		fclose(fp);
	}
	closedir(d);
	return NULL;
}

static id ownerForSBApplication(SBApplication *application) {
	NSString *bundle = [application bundleIdentifier];
	NSString *title = [application displayName];
	NSString *plistPath = [NSString stringWithFormat:@"%@/Info.plist", [application path]];
	char *pkgNameC = owner([bundle UTF8String], [title UTF8String], [plistPath UTF8String]);
	id package = pkgNameC ? [NSString stringWithUTF8String:pkgNameC] : [NSNull null];
	return package;
}

static BOOL isOfficialUninstallable(SBApplication *application) {
	return [application isSystemApplication] 
		|| [application isInternalApplication]
		|| [application isWebApplication]
		|| [[application path] hasPrefix:@"/private/var/mobile/Containers/Bundle/Application"]      //iOS 9.1.x-
		|| [[application path] hasPrefix:@"/private/var/containers/Bundle/Application"];            //iOS 9.2.x+
}

@implementation CDUninstallOperation
- (id)init {
	if((self = [super init]) != nil) {
		_executing = NO;
		_finished = NO;
	}
	return self;
}

- (BOOL)isConcurrent { return YES; }
- (BOOL)isExecuting { return _executing; }
- (BOOL)isFinished { return _finished; }

- (void)start {
	if([self isCancelled]) {
		[self willChangeValueForKey:@"isFinished"];
		_finished = YES;
		[self didChangeValueForKey:@"isFinished"];
		return;
	}
	[self willChangeValueForKey:@"isExecuting"];
	[NSThread detachNewThreadSelector:@selector(main) toTarget:self withObject:nil];
	_executing = YES;
	[self didChangeValueForKey:@"isExecuting"];
}

- (void)completeOperation {
	[self willChangeValueForKey:@"isFinished"];
	[self willChangeValueForKey:@"isExecuting"];
	_executing = NO;
	_finished = YES;
	[self didChangeValueForKey:@"isExecuting"];
	[self didChangeValueForKey:@"isFinished"];
}

- (void)main {
}
@end

@implementation CDUninstallDpkgOperation
	
	//String to store the package name.
	@synthesize package = _package;
	
	- (id)initWithPackage:(NSString *)package {
		if((self = [super init]) != nil) {
			self.package = package;
		}
		return self;
	}

	- (void)displayError {
		NSString *body = [NSString stringWithFormat:CDLocalizedString(@"PACKAGE_UNINSTALL_ERROR_BODY"), _package];
		UIAlertView *delView = [[UIAlertView alloc] initWithTitle:CDLocalizedString(@"PACKAGE_UNINSTALL_ERROR_TITLE") message:body delegate:nil cancelButtonTitle:@"Okay" otherButtonTitles:nil];
		[delView show]; 
	}

	-(void)displayRespring {
		NSString *body = [NSString stringWithFormat:CDLocalizedString(@"PACKAGE_FINISH_BODY"), _package, @"respring"];
		UIAlertView *respring = [[UIAlertView alloc] initWithTitle:CDLocalizedString(@"PACKAGE_FINISH_RESTART") message:body delegate:self cancelButtonTitle:@"Okay" otherButtonTitles:nil];
		respring.tag = 100;
		[respring show];
	}

	- (void)main {
		NSString *command = [NSString stringWithFormat:@"/usr/libexec/cydelete/setuid /usr/libexec/cydelete/uninstall_dpkg.sh %@", _package];
		NSString *output = outputForShellCommand(command);
		if(!output) [self performSelectorOnMainThread:@selector(displayError) withObject:nil waitUntilDone:NO];
		[self completeOperation];
		//Horrible code - need a way to detect if an application needs a respring after uninstall. ("apt-cache depends pkgname" contains mobilesubstrate?)
		if([_package isEqualToString:@"libactivator"]) {
			[self performSelectorOnMainThread:@selector(displayRespring) withObject:nil waitUntilDone:NO];
		}
	}

	-(void) alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex{
	    if (alertView.tag == 100) {
	    	[(SpringBoard *)[UIApplication sharedApplication] _relaunchSpringBoardNow];
	    }
	}

@end

static void removeBundleFromMIList(NSString *bundle) {
	NSString *path = [NSString stringWithFormat:@"%@/Library/Caches/com.apple.mobile.installation.plist", NSHomeDirectory()];
	NSMutableDictionary *cache = [[NSMutableDictionary alloc] initWithContentsOfFile:path];
	[[cache objectForKey:@"System"] removeObjectForKey:bundle];
	[cache writeToFile:path atomically:YES];
}

%hook SBApplicationController

-(void)uninstallApplication:(SBApplication *)application {
	//If the application is not a system app or web app.
	if(![application isSystemApplication] || [[application path] isEqualToString:@"/Applications/Web.app"]) {
		%orig;
	}
	else {

		//Get the package details for the bundle ID.
		id package = nil;

		if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_8_0) {
			package = [iconPackagesDict objectForKey:[application bundleIdentifier]];
		}
		else {
			package = [iconPackagesDict objectForKey:[application displayName]];
		}

		// We were called with an application that doesn't have an entry in the packages list.
		if(!package) package = ownerForSBApplication(application);
		// We still don't have an entry (or a NSNull). We should probably bail out.
		if(!package) return;
		//If the package equals null then we can assume it is not installed via Cydia.
		if(package == [NSNull null]) {
			//Show the user an error message warning them that we didn't remove the application.
			NSString *nonCydiaText = [NSString stringWithFormat:CDLocalizedString(@"PACKAGE_NOT_CYDIA_BODY"), package];
			UIAlertView *nonCydiaAlert = [[UIAlertView alloc] initWithTitle:CDLocalizedString(@"PACKAGE_NOT_CYDIA_TITLE") 
			                                                        message:nonCydiaText 
			                                                       delegate:nil 
			                                              cancelButtonTitle:@"Okay" 
			                                              otherButtonTitles:nil];
			[nonCydiaAlert show];
		}
		else {
			//Add the package to the Uninstall operation queue.
			[uninstallQueue addOperation:[[CDUninstallDpkgOperation alloc] initWithPackage:package]];
			removeBundleFromMIList([application bundleIdentifier]);
		}
	}
}
%end

static BOOL cydelete_IOSVersionAbove92() {
	return kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_9_2;
}

static BOOL cydelete_allowsUninstall(SBIcon *arg) {
	//Get the bundle ID for this application.
	NSString *bundle = nil;
	if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_8_0) {
		bundle = [[arg application] bundleIdentifier];
	}
	else {
		bundle = [[arg application] displayName];
	}
	//If the application is an Apple application.
	bool isApple = ([bundle hasPrefix:@"com.apple."] && ![bundle hasPrefix:@"com.apple.samplecode."]);
	//If the application is Cydia and user has protected it.
	bool isCydia = ([bundle isEqualToString:@"com.saurik.Cydia"] && getProtectCydia());
	//If the application is Cydia and user has protected it.
	bool isPangu = ([bundle isEqualToString:@"io.pangu.nvwastone"] && getProtectPangu());
	//If any of these match then we don't want to allow uninstall.
	if(isApple || isCydia || isPangu || !getEnabled() || getFreeMemory() < 20 ) {
		return NO;
	}
	return YES;
}

static void uninstallClickedForIcon(SBIcon *self) {
	//Get the application for this icon.
	SBApplication *app = [self application];
	
	//Get the bundle identifer for this application.
	NSString *bundle = nil;
	if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_8_0) {
		bundle = [app bundleIdentifier];
	}
	else {
		bundle = [app displayName];
	}

	//If iconPackagesDict does not contain this current application's bundle ID.
	if(![[iconPackagesDict allKeys] containsObject:bundle]) {
		//Get the owner of the application.
		id pkgName = ownerForSBApplication(app);
		//At this point, an app store app would be pkgname null.
		[iconPackagesDict setObject:pkgName forKey:bundle];
	}
}

static BOOL _forceCydia;
@interface SBApplicationIcon(CyDelete) 
@property (nonatomic) BOOL forceCydia;
@end


@interface LSApplicationWorkspace : NSObject
+ (id) defaultWorkspace;
- (BOOL) unregisterApplication:(id)application;
- (BOOL) registerApplicationDictionary:(id)application;
@end

%hook SBIconController
	- (_Bool)iconViewDisplaysCloseBox:(id)arg1{
		if([arg1 class] != %c(SBIconView) && [arg1 class] != %c(SBActivatorIcon)) {
			return %orig(arg1);
		}
		SBIconView *iconView = arg1;
		SBIcon *icon = [iconView icon];
		return cydelete_allowsUninstall(icon);
	}
	- (void)iconCloseBoxTapped:(id)_i {
		%log;
		SBIconView *iconView = _i;
		SBIcon *icon = [iconView icon];
		SBApplicationIcon *appicon = (SBApplicationIcon *)icon;
		SBApplication *app = [icon application];
		id pkgName = ownerForSBApplication(app);
		if(pkgName != [NSNull null]) {
			uninstallClickedForIcon(icon);
		}
		if(cydelete_IOSVersionAbove92() && [[iconPackagesDict allKeys] containsObject:[app bundleIdentifier]]) {
			//new mechanism: iOS 9.2 above will not automatically trigger uninstall, we've to call it manually
			BOOL contains = NO;
			for(CDUninstallDpkgOperation *operation in [uninstallQueue operations]){
				if([operation.package isEqualToString:[app bundleIdentifier]]){
					contains = YES;
					break;
				}
			}
			if(contains) {
				UIAlertController* alert=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ IS uninstalling",[app displayName]] message:@"Please WAIT A SEC" preferredStyle:UIAlertControllerStyleAlert];  
				[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]]; 
				[self presentViewController: alert animated:YES completion:nil];  
			}else{
				appicon.forceCydia = YES;
				UIAlertController* alert=[UIAlertController alertControllerWithTitle:[appicon uninstallAlertTitle] message:[appicon uninstallAlertBody] preferredStyle:UIAlertControllerStyleAlert];  
				[alert addAction:[UIAlertAction actionWithTitle:[appicon uninstallAlertCancelTitle] style:UIAlertActionStyleDefault handler:nil]]; 
				[alert addAction:[UIAlertAction actionWithTitle:[appicon uninstallAlertConfirmTitle] style:UIAlertActionStyleCancel handler:^(UIAlertAction* _Nonnull action)  
				{
				    Class $LSApplicationWorkspace = objc_getClass("LSApplicationWorkspace");
				    [[$LSApplicationWorkspace defaultWorkspace] unregisterApplication:[NSURL fileURLWithPath:[app path]]];
				    Class $SBApplicationController = objc_getClass("SBApplicationController");
				    [[$SBApplicationController sharedInstance] uninstallApplication:app];
				}]];  
				appicon.forceCydia = NO;
				[self presentViewController: alert animated:YES completion:nil];  
			}
		}else{
			%orig;
		}
	}
%end

%hook SBApplicationIcon
	%new
	- (BOOL)forceCydia{
		return _forceCydia;
	}
	%new
	- (void)setForceCydia:(BOOL)force{
		_forceCydia = force;
	}

	//iOS 7/8/9.0-9.1 compatible code
	-(BOOL)allowsCloseBox {
		if([self class] != %c(SBApplicationIcon) && [self class] != %c(SBActivatorIcon)) {
			return %orig;
		}
		return cydelete_allowsUninstall(self);
	}
	-(BOOL)allowsUninstall {
		if([self class] != %c(SBApplicationIcon) && [self class] != %c(SBActivatorIcon)) {
			return %orig;
		}
		return cydelete_allowsUninstall(self);
	}
	-(void)closeBoxClicked:(id)event {
		if([self class] != %c(SBApplicationIcon) && [self class] != %c(SBActivatorIcon)) {
			%orig;
			return;
		}
		uninstallClickedForIcon(self);
		%orig;
	}
	-(void)uninstallClicked:(id)event {
		if([self class] != %c(SBApplicationIcon) && [self class] != %c(SBActivatorIcon)) {
			%orig;
			return;
		}
		uninstallClickedForIcon(self);
		%orig;
	}

	-(NSString *)uninstallAlertTitle {
		%log;
		if(!_forceCydia && isOfficialUninstallable([self application]))
			return %orig;
		return [NSString stringWithFormat:cydelete_IOSVersionAbove92() ? SBLocalizedString(@"UNINSTALL_ICON_TITLE_DELETE_WITH_NAME") : SBLocalizedString(@"UNINSTALL_ICON_TITLE"),
						[[self application] displayName]];
	}

	-(NSString *)uninstallAlertBody {
		%log;
		if(!_forceCydia && isOfficialUninstallable([self application]))
			return %orig;

		NSString *bundle = nil;

		if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_8_0) {
			bundle = [[self application] bundleIdentifier];
		}
		else {
			bundle = [[self application] displayName];
		}

		id package = [iconPackagesDict objectForKey:bundle];	

		NSString *body;
		if(package == [NSNull null]) {
			body = [NSString stringWithFormat:SBLocalizedString(@"DELETE_WIDGET_BODY"),
							[[self application] displayName]];
		}
		else {
			NSString *localString = CDLocalizedString(@"PACKAGE_DELETE_BODY");
			body = [NSString stringWithFormat:localString, [[self application] displayName], package];
		}
		return body;
	}

	-(NSString *)uninstallAlertConfirmTitle {
		%log;
		if(!_forceCydia && isOfficialUninstallable([self application]))
			return %orig;
		return cydelete_IOSVersionAbove92() ? SBLocalizedString(@"UNINSTALL_ICON_BUTTON_DELETE") : SBLocalizedString(@"UNINSTALL_ICON_CONFIRM");
	}

	-(NSString *)uninstallAlertCancelTitle {
		%log;
		if(!_forceCydia && isOfficialUninstallable([self application]))
			return %orig;
		return cydelete_IOSVersionAbove92() ? SBLocalizedString(@"UNINSTALL_ICON_BUTTON_CANCEL") : SBLocalizedString(@"UNINSTALL_ICON_CANCEL");
	}
%end

%ctor {
	%init;
	initTranslation();
	iconPackagesDict = [[NSMutableDictionary alloc] init];
	uninstallQueue = [[NSOperationQueue alloc] init];
	[uninstallQueue setMaxConcurrentOperationCount:1];
}
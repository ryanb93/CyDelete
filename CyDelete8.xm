//
//  CyDelete7.xm
//  CyDelete7
//
//  Created by Ryan Burke on 02.01.2014.
//  Copyright (c) 2014 Ryan Burke. All rights reserved.
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <substrate.h>

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

@interface CDUninstallOperation : NSOperation {
	BOOL _executing;
	BOOL _finished;
}
@end

@interface CDUninstallDpkgOperation : CDUninstallOperation {
	NSString *_package;
}

@property (nonatomic, retain) NSString *package;
- (id)initWithPackage:(NSString *)package;
@end

static void initTranslation() {
    cyDelBundle = [NSBundle bundleWithPath:@"/Library/MobileSubstrate/DynamicLibraries/CyDelete8.bundle"];
}

static bool getProtectCydia() {
	//Sync the latest version of the preferences.
	bool synced = CFPreferencesAppSynchronize(CFSTR("com.ryanburke.cydelete8"));
	//If the sync failed, lets just default to protecting Cydia for safety.
	if(!synced) return true;
	//Create a boolean object to hold the success value from next function.
	Boolean success;
	//Get the value of the "CDProtectCydia" key from the preferences.
	bool result = CFPreferencesGetAppBooleanValue(CFSTR("CDProtectCydia"), CFSTR("com.ryanburke.cydelete8"), &success);
	//If the enabled key existed and we got the value okay.
	if(success) {
		//Return the value of the key.
		return result;
	}
	//If for some reason we couldn't get the value lets just default to protecting Cydia for safety.
	return true;
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

	- (bool)runCMD
	{
		//Path to the setuid appliaction that gets us root permissions.
	    const char *setuid = "/usr/libexec/cydelete/setuid";
	    //Path to our uninstall script that we want to run as root.
		char commandChar[] = "/usr/libexec/cydelete/uninstall_dpkg.sh";

		//Horrible method to convert NSString to Char array.
		char packageChar [strlen([_package UTF8String]) + 1];
		strcpy(packageChar, [_package UTF8String]);

		//Char literal array containing shell script path and package name.
	    char *argv[] = {commandChar, packageChar, NULL};

	    //Create a pid_t object to hold reference to spawned process.
	    pid_t pid;

	    //Spawn a new process using posix_spawn as System() is depricated on iOS 8.
	    int status = posix_spawn(&pid, setuid, NULL, NULL, argv, NULL);

	    //Status 0 indicates successful spawn. Not that apt-get was success though.
	    if (status == 0) {
	        if (waitpid(pid, &status, 0) != -1) {
	        	//Return a success.
	            return true;
	        }
	    }
	    //Return failure.
	    return false;
	}

	- (void)displayError {
		NSString *body = [NSString stringWithFormat:CDLocalizedString(@"PACKAGE_UNINSTALL_ERROR_BODY"), _package];
		UIAlertView *delView = [[UIAlertView alloc] initWithTitle:CDLocalizedString(@"PACKAGE_UNINSTALL_ERROR_TITLE") message:body delegate:nil cancelButtonTitle:@"Okay" otherButtonTitles:nil];
		[delView show];
	}

	- (void)main {
		bool output = [self runCMD];
		if(output) {
			removeBundleFromMIList(_package);
		} 
		else {
			[self performSelectorOnMainThread:@selector(displayError) withObject:nil waitUntilDone:NO];
		}

		[self completeOperation];
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
	if(![application isSystemApplication] || [[application path] isEqualToString:@"/Applications/Web.app"]) {
		%orig;
		return;
	}

	id package = [iconPackagesDict objectForKey:[application bundleIdentifier]];
	
	// We were called with an application that doesn't have an entry in the packages list.
	if(!package) package = ownerForSBApplication(application);

	// We still don't have an entry (or a NSNull). We should probably bail out.
	if(!package) return;
	
	[uninstallQueue addOperation:[[CDUninstallDpkgOperation alloc] initWithPackage:package]];

}
%end

@interface SBApplicationIcon (CyDelete)
	-(BOOL)cydelete_allowsUninstall;
	-(void)cydelete_uninstallClicked;
@end

static void uninstallClickedForIcon(SBIcon *self) {
	if(![[iconPackagesDict allKeys] containsObject:[[self application] bundleIdentifier]]) {
		SBApplication *app = [self application];
		id _pkgName = ownerForSBApplication(app);
		//At this point, an app store app would be pkgname null.
		[iconPackagesDict setObject:_pkgName forKey:[[self application] bundleIdentifier]];
	}
}

%hook SBIconController
	- (void)iconCloseBoxTapped:(id)_i {
		SBIconView *iconView = _i;
		SBIcon *icon = [iconView icon];
		SBApplication *app = [icon application];
		id pkgName = ownerForSBApplication(app);
		if(pkgName != [NSNull null]) {
			uninstallClickedForIcon(icon);
		}
		%orig;
	}
%end

%hook SBApplicationIcon

	%new(c@:)
	-(BOOL)cydelete_allowsUninstall {

		NSString *bundle = [[self application] bundleIdentifier];
		bool isApple = ([bundle hasPrefix:@"com.apple."] && ![bundle hasPrefix:@"com.apple.samplecode."]);
		bool isCydia = ([bundle isEqualToString:@"com.saurik.Cydia"] && getProtectCydia());

		if(isApple || isCydia || getFreeMemory() < 20 ) {
			return NO;
		}
		
		return YES;
	}

	-(BOOL)allowsCloseBox {
		if([self class] != %c(SBApplicationIcon)) {
			return %orig;
		}
		return [self cydelete_allowsUninstall];
	}

	-(BOOL)allowsUninstall {
		if([self class] != %c(SBApplicationIcon)) {
			return %orig;
		}
		return [self cydelete_allowsUninstall];
	}

	-(void)closeBoxClicked:(id)event {
		if([self class] != %c(SBApplicationIcon)) {
			%orig;
			return;
		}
		uninstallClickedForIcon(self);
		%orig;
	}

	-(void)uninstallClicked:(id)event {
		if([self class] != %c(SBApplicationIcon)) {
			%orig;
			return;
		}
		uninstallClickedForIcon(self);
		%orig;
	}

	-(NSString *)uninstallAlertTitle {
		return [NSString stringWithFormat:SBLocalizedString(@"UNINSTALL_ICON_TITLE"),
						[[self application] displayName]];
	}

	-(NSString *)uninstallAlertBody {
		id package = [iconPackagesDict objectForKey:[[self application] bundleIdentifier]];	
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
		return SBLocalizedString(@"UNINSTALL_ICON_CONFIRM");
	}

	-(NSString *)uninstallAlertCancelTitle {
		return SBLocalizedString(@"UNINSTALL_ICON_CANCEL");
	}
%end

%ctor {
	%init;
	initTranslation();
	iconPackagesDict = [[NSMutableDictionary alloc] init];
	uninstallQueue = [[NSOperationQueue alloc] init];
	[uninstallQueue setMaxConcurrentOperationCount:1];
}

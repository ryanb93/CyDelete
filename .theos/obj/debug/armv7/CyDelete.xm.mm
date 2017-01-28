#line 1 "CyDelete.xm"







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


static void initTranslation() {
    cyDelBundle = [NSBundle bundleWithPath:@"/Library/Application Support/CyDelete/CyDelete.bundle"];
}

static bool getCFBool(CFStringRef key, bool defaultValue) {
	
	bool synced = CFPreferencesAppSynchronize(CFSTR("com.ryanburke.cydelete"));
	
	if(!synced) return defaultValue;
	
	Boolean success;
	
	bool result = CFPreferencesGetAppBooleanValue(key, CFSTR("com.ryanburke.cydelete"), &success);
	
	if(success) {
		
		return result;
	}
	
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


#include <substrate.h>
#if defined(__clang__)
#if __has_feature(objc_arc)
#define _LOGOS_SELF_TYPE_NORMAL __unsafe_unretained
#define _LOGOS_SELF_TYPE_INIT __attribute__((ns_consumed))
#define _LOGOS_SELF_CONST const
#define _LOGOS_RETURN_RETAINED __attribute__((ns_returns_retained))
#else
#define _LOGOS_SELF_TYPE_NORMAL
#define _LOGOS_SELF_TYPE_INIT
#define _LOGOS_SELF_CONST
#define _LOGOS_RETURN_RETAINED
#endif
#else
#define _LOGOS_SELF_TYPE_NORMAL
#define _LOGOS_SELF_TYPE_INIT
#define _LOGOS_SELF_CONST
#define _LOGOS_RETURN_RETAINED
#endif

@class SBActivatorIcon; @class SBApplicationIcon; @class SBIconController; @class SBApplicationController; 
static void (*_logos_orig$_ungrouped$SBApplicationController$uninstallApplication$)(_LOGOS_SELF_TYPE_NORMAL SBApplicationController* _LOGOS_SELF_CONST, SEL, SBApplication *); static void _logos_method$_ungrouped$SBApplicationController$uninstallApplication$(_LOGOS_SELF_TYPE_NORMAL SBApplicationController* _LOGOS_SELF_CONST, SEL, SBApplication *); static void (*_logos_orig$_ungrouped$SBIconController$iconCloseBoxTapped$)(_LOGOS_SELF_TYPE_NORMAL SBIconController* _LOGOS_SELF_CONST, SEL, id); static void _logos_method$_ungrouped$SBIconController$iconCloseBoxTapped$(_LOGOS_SELF_TYPE_NORMAL SBIconController* _LOGOS_SELF_CONST, SEL, id); static BOOL _logos_method$_ungrouped$SBApplicationIcon$cydelete_allowsUninstall(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST, SEL); static BOOL (*_logos_orig$_ungrouped$SBApplicationIcon$allowsCloseBox)(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST, SEL); static BOOL _logos_method$_ungrouped$SBApplicationIcon$allowsCloseBox(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST, SEL); static BOOL (*_logos_orig$_ungrouped$SBApplicationIcon$allowsUninstall)(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST, SEL); static BOOL _logos_method$_ungrouped$SBApplicationIcon$allowsUninstall(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST, SEL); static void (*_logos_orig$_ungrouped$SBApplicationIcon$closeBoxClicked$)(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST, SEL, id); static void _logos_method$_ungrouped$SBApplicationIcon$closeBoxClicked$(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST, SEL, id); static void (*_logos_orig$_ungrouped$SBApplicationIcon$uninstallClicked$)(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST, SEL, id); static void _logos_method$_ungrouped$SBApplicationIcon$uninstallClicked$(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST, SEL, id); static NSString * (*_logos_orig$_ungrouped$SBApplicationIcon$uninstallAlertTitle)(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST, SEL); static NSString * _logos_method$_ungrouped$SBApplicationIcon$uninstallAlertTitle(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST, SEL); static NSString * (*_logos_orig$_ungrouped$SBApplicationIcon$uninstallAlertBody)(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST, SEL); static NSString * _logos_method$_ungrouped$SBApplicationIcon$uninstallAlertBody(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST, SEL); static NSString * (*_logos_orig$_ungrouped$SBApplicationIcon$uninstallAlertConfirmTitle)(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST, SEL); static NSString * _logos_method$_ungrouped$SBApplicationIcon$uninstallAlertConfirmTitle(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST, SEL); static NSString * (*_logos_orig$_ungrouped$SBApplicationIcon$uninstallAlertCancelTitle)(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST, SEL); static NSString * _logos_method$_ungrouped$SBApplicationIcon$uninstallAlertCancelTitle(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST, SEL); 
static __inline__ __attribute__((always_inline)) __attribute__((unused)) Class _logos_static_class_lookup$SBApplicationIcon(void) { static Class _klass; if(!_klass) { _klass = objc_getClass("SBApplicationIcon"); } return _klass; }static __inline__ __attribute__((always_inline)) __attribute__((unused)) Class _logos_static_class_lookup$SBActivatorIcon(void) { static Class _klass; if(!_klass) { _klass = objc_getClass("SBActivatorIcon"); } return _klass; }
#line 258 "CyDelete.xm"


static void _logos_method$_ungrouped$SBApplicationController$uninstallApplication$(_LOGOS_SELF_TYPE_NORMAL SBApplicationController* _LOGOS_SELF_CONST __unused self, SEL __unused _cmd, SBApplication * application) {
	
	if(![application isSystemApplication] || [[application path] isEqualToString:@"/Applications/Web.app"]) {
		_logos_orig$_ungrouped$SBApplicationController$uninstallApplication$(self, _cmd, application);
	}
	else {

		
		id package = nil;

		if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_8_0) {
			package = [iconPackagesDict objectForKey:[application bundleIdentifier]];
		}
		else {
			package = [iconPackagesDict objectForKey:[application displayName]];
		}

		
		if(!package) package = ownerForSBApplication(application);
		
		if(!package) return;
		
		if(package == [NSNull null]) {
			
			NSString *nonCydiaText = [NSString stringWithFormat:CDLocalizedString(@"PACKAGE_NOT_CYDIA_BODY"), package];
			UIAlertView *nonCydiaAlert = [[UIAlertView alloc] initWithTitle:CDLocalizedString(@"PACKAGE_NOT_CYDIA_TITLE") 
														message:nonCydiaText 
														delegate:nil 
														cancelButtonTitle:@"Okay" 
														otherButtonTitles:nil];
			[nonCydiaAlert show];
		}
		else {
			
			[uninstallQueue addOperation:[[CDUninstallDpkgOperation alloc] initWithPackage:package]];
			removeBundleFromMIList([application bundleIdentifier]);
		}
	}
}


@interface SBApplicationIcon (CyDelete)
	-(BOOL)cydelete_allowsUninstall;
	-(void)cydelete_uninstallClicked;
@end

static void uninstallClickedForIcon(SBIcon *self) {
	
	SBApplication *app = [self application];
	
	
	NSString *bundle = nil;
	if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_8_0) {
		bundle = [app bundleIdentifier];
	}
	else {
		bundle = [app displayName];
	}

	
	if(![[iconPackagesDict allKeys] containsObject:bundle]) {
		
		id pkgName = ownerForSBApplication(app);
		
		[iconPackagesDict setObject:pkgName forKey:bundle];
	}
}


	static void _logos_method$_ungrouped$SBIconController$iconCloseBoxTapped$(_LOGOS_SELF_TYPE_NORMAL SBIconController* _LOGOS_SELF_CONST __unused self, SEL __unused _cmd, id _i) {
		HBLogDebug(@"-[<SBIconController: %p> iconCloseBoxTapped:%@]", self, _i);
		SBIconView *iconView = _i;
		SBIcon *icon = [iconView icon];
		SBApplication *app = [icon application];
		id pkgName = ownerForSBApplication(app);
		if(pkgName != [NSNull null]) {
			uninstallClickedForIcon(icon);
		}
		_logos_orig$_ungrouped$SBIconController$iconCloseBoxTapped$(self, _cmd, _i);
	}




	
	static BOOL _logos_method$_ungrouped$SBApplicationIcon$cydelete_allowsUninstall(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST __unused self, SEL __unused _cmd) {
		
		NSString *bundle = nil;
		if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_8_0) {
			bundle = [[self application] bundleIdentifier];
		}
		else {
			bundle = [[self application] displayName];
		}
		
		bool isApple = ([bundle hasPrefix:@"com.apple."] && ![bundle hasPrefix:@"com.apple.samplecode."]);
		
		bool isCydia = ([bundle isEqualToString:@"com.saurik.Cydia"] && getProtectCydia());
		
		bool isPangu = ([bundle isEqualToString:@"io.pangu.loader"] && getProtectPangu());
		
		if(isApple || isCydia || isPangu || !getEnabled() || getFreeMemory() < 20 ) {
			return NO;
		}
		return YES;
	}

	static BOOL _logos_method$_ungrouped$SBApplicationIcon$allowsCloseBox(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST __unused self, SEL __unused _cmd) {
		if([self class] != _logos_static_class_lookup$SBApplicationIcon() && [self class] != _logos_static_class_lookup$SBActivatorIcon()) {
			return _logos_orig$_ungrouped$SBApplicationIcon$allowsCloseBox(self, _cmd);
		}
		return [self cydelete_allowsUninstall];
	}

	static BOOL _logos_method$_ungrouped$SBApplicationIcon$allowsUninstall(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST __unused self, SEL __unused _cmd) {
		if([self class] != _logos_static_class_lookup$SBApplicationIcon() && [self class] != _logos_static_class_lookup$SBActivatorIcon()) {
			return _logos_orig$_ungrouped$SBApplicationIcon$allowsUninstall(self, _cmd);
		}
		return [self cydelete_allowsUninstall];
	}

	static void _logos_method$_ungrouped$SBApplicationIcon$closeBoxClicked$(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST __unused self, SEL __unused _cmd, id event) {
		if([self class] != _logos_static_class_lookup$SBApplicationIcon() && [self class] != _logos_static_class_lookup$SBActivatorIcon()) {
			_logos_orig$_ungrouped$SBApplicationIcon$closeBoxClicked$(self, _cmd, event);
			return;
		}
		uninstallClickedForIcon(self);
		_logos_orig$_ungrouped$SBApplicationIcon$closeBoxClicked$(self, _cmd, event);
	}

	static void _logos_method$_ungrouped$SBApplicationIcon$uninstallClicked$(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST __unused self, SEL __unused _cmd, id event) {
		if([self class] != _logos_static_class_lookup$SBApplicationIcon() && [self class] != _logos_static_class_lookup$SBActivatorIcon()) {
			_logos_orig$_ungrouped$SBApplicationIcon$uninstallClicked$(self, _cmd, event);
			return;
		}
		uninstallClickedForIcon(self);
		_logos_orig$_ungrouped$SBApplicationIcon$uninstallClicked$(self, _cmd, event);
	}

	static NSString * _logos_method$_ungrouped$SBApplicationIcon$uninstallAlertTitle(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST __unused self, SEL __unused _cmd) {
		return [NSString stringWithFormat:SBLocalizedString(@"UNINSTALL_ICON_TITLE"),
						[[self application] displayName]];
	}

	static NSString * _logos_method$_ungrouped$SBApplicationIcon$uninstallAlertBody(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST __unused self, SEL __unused _cmd) {

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

	static NSString * _logos_method$_ungrouped$SBApplicationIcon$uninstallAlertConfirmTitle(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST __unused self, SEL __unused _cmd) {
		return SBLocalizedString(@"UNINSTALL_ICON_CONFIRM");
	}

	static NSString * _logos_method$_ungrouped$SBApplicationIcon$uninstallAlertCancelTitle(_LOGOS_SELF_TYPE_NORMAL SBApplicationIcon* _LOGOS_SELF_CONST __unused self, SEL __unused _cmd) {
		return SBLocalizedString(@"UNINSTALL_ICON_CANCEL");
	}


static __attribute__((constructor)) void _logosLocalCtor_3c714889(int __unused argc, char __unused **argv, char __unused **envp) {
	{Class _logos_class$_ungrouped$SBApplicationController = objc_getClass("SBApplicationController"); if (_logos_class$_ungrouped$SBApplicationController) {MSHookMessageEx(_logos_class$_ungrouped$SBApplicationController, @selector(uninstallApplication:), (IMP)&_logos_method$_ungrouped$SBApplicationController$uninstallApplication$, (IMP*)&_logos_orig$_ungrouped$SBApplicationController$uninstallApplication$);} else {HBLogError(@"logos: nil class %s", "SBApplicationController");}Class _logos_class$_ungrouped$SBIconController = objc_getClass("SBIconController"); if (_logos_class$_ungrouped$SBIconController) {MSHookMessageEx(_logos_class$_ungrouped$SBIconController, @selector(iconCloseBoxTapped:), (IMP)&_logos_method$_ungrouped$SBIconController$iconCloseBoxTapped$, (IMP*)&_logos_orig$_ungrouped$SBIconController$iconCloseBoxTapped$);} else {HBLogError(@"logos: nil class %s", "SBIconController");}Class _logos_class$_ungrouped$SBApplicationIcon = objc_getClass("SBApplicationIcon"); { const char *_typeEncoding = "c@:"; class_addMethod(_logos_class$_ungrouped$SBApplicationIcon, @selector(cydelete_allowsUninstall), (IMP)&_logos_method$_ungrouped$SBApplicationIcon$cydelete_allowsUninstall, _typeEncoding); }if (_logos_class$_ungrouped$SBApplicationIcon) {MSHookMessageEx(_logos_class$_ungrouped$SBApplicationIcon, @selector(allowsCloseBox), (IMP)&_logos_method$_ungrouped$SBApplicationIcon$allowsCloseBox, (IMP*)&_logos_orig$_ungrouped$SBApplicationIcon$allowsCloseBox);} else {HBLogError(@"logos: nil class %s", "SBApplicationIcon");}if (_logos_class$_ungrouped$SBApplicationIcon) {MSHookMessageEx(_logos_class$_ungrouped$SBApplicationIcon, @selector(allowsUninstall), (IMP)&_logos_method$_ungrouped$SBApplicationIcon$allowsUninstall, (IMP*)&_logos_orig$_ungrouped$SBApplicationIcon$allowsUninstall);} else {HBLogError(@"logos: nil class %s", "SBApplicationIcon");}if (_logos_class$_ungrouped$SBApplicationIcon) {MSHookMessageEx(_logos_class$_ungrouped$SBApplicationIcon, @selector(closeBoxClicked:), (IMP)&_logos_method$_ungrouped$SBApplicationIcon$closeBoxClicked$, (IMP*)&_logos_orig$_ungrouped$SBApplicationIcon$closeBoxClicked$);} else {HBLogError(@"logos: nil class %s", "SBApplicationIcon");}if (_logos_class$_ungrouped$SBApplicationIcon) {MSHookMessageEx(_logos_class$_ungrouped$SBApplicationIcon, @selector(uninstallClicked:), (IMP)&_logos_method$_ungrouped$SBApplicationIcon$uninstallClicked$, (IMP*)&_logos_orig$_ungrouped$SBApplicationIcon$uninstallClicked$);} else {HBLogError(@"logos: nil class %s", "SBApplicationIcon");}if (_logos_class$_ungrouped$SBApplicationIcon) {MSHookMessageEx(_logos_class$_ungrouped$SBApplicationIcon, @selector(uninstallAlertTitle), (IMP)&_logos_method$_ungrouped$SBApplicationIcon$uninstallAlertTitle, (IMP*)&_logos_orig$_ungrouped$SBApplicationIcon$uninstallAlertTitle);} else {HBLogError(@"logos: nil class %s", "SBApplicationIcon");}if (_logos_class$_ungrouped$SBApplicationIcon) {MSHookMessageEx(_logos_class$_ungrouped$SBApplicationIcon, @selector(uninstallAlertBody), (IMP)&_logos_method$_ungrouped$SBApplicationIcon$uninstallAlertBody, (IMP*)&_logos_orig$_ungrouped$SBApplicationIcon$uninstallAlertBody);} else {HBLogError(@"logos: nil class %s", "SBApplicationIcon");}if (_logos_class$_ungrouped$SBApplicationIcon) {MSHookMessageEx(_logos_class$_ungrouped$SBApplicationIcon, @selector(uninstallAlertConfirmTitle), (IMP)&_logos_method$_ungrouped$SBApplicationIcon$uninstallAlertConfirmTitle, (IMP*)&_logos_orig$_ungrouped$SBApplicationIcon$uninstallAlertConfirmTitle);} else {HBLogError(@"logos: nil class %s", "SBApplicationIcon");}if (_logos_class$_ungrouped$SBApplicationIcon) {MSHookMessageEx(_logos_class$_ungrouped$SBApplicationIcon, @selector(uninstallAlertCancelTitle), (IMP)&_logos_method$_ungrouped$SBApplicationIcon$uninstallAlertCancelTitle, (IMP*)&_logos_orig$_ungrouped$SBApplicationIcon$uninstallAlertCancelTitle);} else {HBLogError(@"logos: nil class %s", "SBApplicationIcon");}}
	initTranslation();
	iconPackagesDict = [[NSMutableDictionary alloc] init];
	uninstallQueue = [[NSOperationQueue alloc] init];
	[uninstallQueue setMaxConcurrentOperationCount:1];
}

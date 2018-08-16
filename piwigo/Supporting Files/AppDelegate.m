//
//  AppDelegate.m
//  piwigo
//
//  Created by Spencer Baker on 1/14/15.
//  Copyright (c) 2015 bakercrew. All rights reserved.
//

#import <Photos/Photos.h>

#import "AppDelegate.h"
#import "LoginNavigationController.h"
#import "LoginViewController_iPhone.h"
#import "LoginViewController_iPad.h"

#import "Model.h"
#import "SessionService.h"
#import "KeychainAccess.h"
#import "SAMKeychain.h"
#import "AFNetworkActivityIndicatorManager.h"
#import "CategoriesData.h"
#import "PhotosFetch.h"
#import "AlbumImagesViewController.h"

//#ifndef DEBUG_NOCACHE
//#define DEBUG_NOCACHE
//#endif

NSString * const kPiwigoNotificationPaletteChanged = @"kPiwigoNotificationPaletteChanged";
NSString * const kPiwigoError404EncounteredNotification = @"kPiwigoError404EncounteredNotification";

@interface AppDelegate ()

@property (nonatomic, strong) LoginViewController *loginVC;

@end

@implementation AppDelegate

+ (void)initialize {
    
}


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	
    // Override point for customization after application launch.

    // Cache settings
#if defined(DEBUG_NOCACHE)
    // set it to 0 to clear cache
    NSURLCache *URLCache = [[NSURLCache alloc] initWithMemoryCapacity:0
                                                       diskCapacity:0
                                                           diskPath:nil];
    [NSURLCache setSharedURLCache:URLCache];
    // set it back to default value
	URLCache = [[NSURLCache alloc]
                            initWithMemoryCapacity:[Model sharedInstance].memoryCache * 1024*1024
								      diskCapacity:[Model sharedInstance].diskCache * 1024*1024
                                          diskPath:nil];
	[NSURLCache setSharedURLCache:URLCache];
#else
    NSURLCache *URLCache = [[NSURLCache alloc]
                            initWithMemoryCapacity:[Model sharedInstance].memoryCache * 1024*1024
                            diskCapacity:[Model sharedInstance].diskCache * 1024*1024
                            diskPath:nil];
    [NSURLCache setSharedURLCache:URLCache];
#endif

    // Login ?
    NSString *user, *password;
    NSString *server = [Model sharedInstance].serverName;
    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlock];
    
    // Look for credentials if server address provided
    if (server.length > 0)
    {
        // Known acounts for that server?
        NSArray *accounts = [SAMKeychain accountsForService:server];
        if ((accounts == nil) || ([accounts count] <= 0))
        {
            // No credentials available for that server. And with the old methods?
            user = [KeychainAccess getLoginUser];
            password = [KeychainAccess getLoginPassword];
            
            // Store credentials with new method if found
            if (user.length > 0) {
                [Model sharedInstance].username = user;
                [[Model sharedInstance] saveToDisk];
                [SAMKeychain setPassword:password forService:server account:user];
            }
        } else {
            // Credentials available
            user = [Model sharedInstance].username;
            if (user.length > 0) {
                password = [SAMKeychain passwordForService:server account:user];
            }
        }
    }
    
    if(server.length > 0 || (user.length > 0 && password.length > 0))
	{
        [self.loginVC launchLogin];
	}
	
    // No login
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	[self.window makeKeyAndVisible];
	[self loadLoginView];
	
    // Enable network activity indicator
	[AFNetworkActivityIndicatorManager sharedManager].enabled = YES;
    
    // Enable network reachability monitoring
    [[AFNetworkReachabilityManager sharedManager] startMonitoring];
    	
	return YES;
}

-(void)loadNavigation
{
    AlbumImagesViewController *albums = [[AlbumImagesViewController alloc] initWithAlbumId:[Model sharedInstance].defaultCategory inCache:NO];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:albums];
    [self.loginVC removeFromParentViewController];
	self.loginVC = nil;
    
    // Observe the UIScreenBrightnessDidChangeNotification.
    // When that notification is posted, the method screenBrightnessChanged will be called.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(screenBrightnessChanged:) name:UIScreenBrightnessDidChangeNotification object:nil];

    // Observe the PiwigoError404EncounteredNotification.
    // When that notification is posted, the app checks the login.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkSessionStatusAndTryRelogin) name:kPiwigoError404EncounteredNotification object:nil];
    
    // Set network reachability status change block
    [[AFNetworkReachabilityManager sharedManager] setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
//#if defined(DEBUG)
//        NSLog(@"!!!!!! Network Reachability Changed!");
//        NSLog(@"       hadOpenedSession=%@, usesCommunityPluginV29=%@, hasAdminRights=%@",
//              ([Model sharedInstance].hadOpenedSession ? @"YES" : @"NO"),
//              ([Model sharedInstance].usesCommunityPluginV29 ? @"YES" : @"NO"),
//              ([Model sharedInstance].hasAdminRights ? @"YES" : @"NO"));
//#endif

        if ([AFNetworkReachabilityManager sharedManager].reachable) {
            // Connection changed but again reachable — Login again?
            [self checkSessionStatusAndTryRelogin];
        }
    }];
}

-(void)checkSessionStatusAndTryRelogin
{
    BOOL hadOpenedSession = [Model sharedInstance].hadOpenedSession;
    NSString *server = [Model sharedInstance].serverName;
    NSString *user = [KeychainAccess getLoginUser];
    
    if(hadOpenedSession && (server.length > 0) && (user.length > 0))
    {
//#if defined(DEBUG)
//                NSLog(@"       Connection changed but again reachable — Login again?");
//#endif
        [self.loginVC checkSessionStatusAndTryRelogin];
    }
}

// Called when the screen brightness has changed or when user changed settings
-(void)screenBrightnessChanged:(NSNotification *)note
{
//    NSLog(@"Screen Brightness: %f",[[UIScreen mainScreen] brightness]);
    if (![Model sharedInstance].isDarkPaletteModeActive) {
        // Static light palette mode chosen
        if (![Model sharedInstance].isDarkPaletteActive) {
            // Already showing light palette
            return;
        } else {
            // Switch to light palette
            [Model sharedInstance].isDarkPaletteActive = NO;
            [UITextField appearance].keyboardAppearance = UIKeyboardAppearanceLight;
        }
    } else {
        // Dark palette mode chosen
        if (![Model sharedInstance].switchPaletteAutomatically) {
            // Static dark palette chosen
            if ([Model sharedInstance].isDarkPaletteActive) {
                // Already showing dark palette
                return;
            } else {
                // Switch to dark palette
                [Model sharedInstance].isDarkPaletteActive = YES;
                [UITextField appearance].keyboardAppearance = UIKeyboardAppearanceDark;
            }
        } else {
            // Dynamic dark palette chosen
            NSInteger currentBrightness = lroundf([[UIScreen mainScreen] brightness] * 100.0);
            if ([Model sharedInstance].isDarkPaletteActive) {
                // Dark palette displayed
                if (currentBrightness > [Model sharedInstance].switchPaletteThreshold) {
                    // Screen brightness > thereshold, switch to light palette
                    [Model sharedInstance].isDarkPaletteActive = NO;
                    [UITextField appearance].keyboardAppearance = UIKeyboardAppearanceLight;
                } else {
                    // Keep dark palette
                    return;
                }
            } else {
                // Light palette displayed
                if (currentBrightness < [Model sharedInstance].switchPaletteThreshold) {
                    // Screen brightness < threshold, switch to dark palette
                    [Model sharedInstance].isDarkPaletteActive = YES;
                    [UITextField appearance].keyboardAppearance = UIKeyboardAppearanceDark;
                } else {
                    // Keep light palette
                    return;
                }
            }
        }
    }
    
    // Store modified settings
    [[Model sharedInstance] saveToDisk];

    // Notify palette change
    [[NSNotificationCenter defaultCenter] postNotificationName:kPiwigoNotificationPaletteChanged object:nil];
}

-(void)loadLoginView
{
	LoginNavigationController *nav = [[LoginNavigationController alloc] initWithRootViewController:self.loginVC];
	[nav setNavigationBarHidden:YES];
	self.window.rootViewController = nav;
}

-(LoginViewController*)loginVC
{
	if(_loginVC) return _loginVC;
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        _loginVC = [LoginViewController_iPhone new];
    } else {
        _loginVC = [LoginViewController_iPad new];
    }
	return _loginVC;
}

- (void)applicationWillResignActive:(UIApplication *)application {
	// Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
	// Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
	// Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
	// If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
	// Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.

    // Should we reopen the session ?
    BOOL hadOpenedSession = [Model sharedInstance].hadOpenedSession;
    NSString *server = [Model sharedInstance].serverName;
    NSString *user = [Model sharedInstance].username;
    if(hadOpenedSession && (server.length > 0) && (user.length > 0))
    {
        // Let's see…
        [self.loginVC checkSessionStatusAndTryRelogin];
    }
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
	// Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.

    // Check access to photos — Required as system does not always ask
    if([PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusNotDetermined) {
        // Request authorization to access photos
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            // Nothing to do…
        }];
    }
    else if(([PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusDenied) ||
            ([PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusRestricted)) {
        // Inform user that he denied or restricted access to photos
        UIAlertController* alert = [UIAlertController
                alertControllerWithTitle:NSLocalizedString(@"localAlbums_photosNotAuthorized_title", @"No Access")
                message:NSLocalizedString(@"localAlbums_photosNotAuthorized_msg", @"tell user to change settings, how")
                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction* dismissAction = [UIAlertAction
                actionWithTitle:NSLocalizedString(@"alertDismissButton", @"Dismiss")
                style:UIAlertActionStyleCancel
                handler:^(UIAlertAction * action) {}];
        
        [alert addAction:dismissAction];
        [self.loginVC presentViewController:alert animated:YES completion:nil];
    }
    
    // Piwigo Mobile will play audio even if the Silent switch set to silent or when the screen locks.
    // Furthermore, it will interrupt any other current audio sessions (no mixing)
    if (@available(iOS 9, *)) {
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        NSArray<NSString *> *availableCategories = [audioSession availableCategories];
        if ([availableCategories containsObject:AVAudioSessionCategoryPlayback]) {
            [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
        }
    }

    // Should we change the theme ?
    [self screenBrightnessChanged:nil];    
}

- (void)applicationWillTerminate:(UIApplication *)application {
	// Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.

    // Cancel tasks and close sessions
    [[Model sharedInstance].sessionManager invalidateSessionCancelingTasks:YES];
    [[Model sharedInstance].imagesSessionManager invalidateSessionCancelingTasks:YES];

    // Disable network activity indicator
    [AFNetworkActivityIndicatorManager sharedManager].enabled = NO;
    
    // Disable network reachability monitoring
    [[AFNetworkReachabilityManager sharedManager] stopMonitoring];
}

@end

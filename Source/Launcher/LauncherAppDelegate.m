/*
 * Author: Landon Fuller <landonf@plausiblelabs.com>
 *
 * Copyright (c) 2010 Plausible Labs Cooperative, Inc.
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */

#import "LauncherAppDelegate.h"
#import "LauncherSimClient.h"

/* Resource subdirectory for the embedded application */
#define APP_DIR @"EmbeddedApp"

/* Full application-relative path to the embeddedapp dir */
#define FULL_APP_DIR @"Contents/Resources/" APP_DIR

@implementation LauncherAppDelegate

- (void) applicationDidFinishLaunching: (NSNotification *) aNotification {
    NSError *error;

    /* Display a fatal configuration error modaly */
    void (^ConfigError)(NSString *) = ^(NSString *text) {
        NSAlert *alert = [NSAlert alertWithMessageText: @"The launcher has not been correctly configured." 
                                         defaultButton: @"Quit"
                                       alternateButton: nil 
                                           otherButton: nil
                             informativeTextWithFormat: text];
        [alert runModal];
        [[NSApplication sharedApplication] terminate: self];
    };

    /* Find the embedded application dir */
    NSString *appContainer = [[NSBundle mainBundle] pathForResource: APP_DIR ofType: nil];
    if (appContainer == nil) {
        ConfigError(@"Missing the " FULL_APP_DIR " directory.");
        return;
    }

    /* Scan for applications */
    NSArray *appPaths = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: appContainer error: &error];
    if (appPaths == nil) {
        ConfigError(FULL_APP_DIR " could not be read.");
        return;
    } else if ([appPaths count] == 0) {
        ConfigError(@"No applications found in " FULL_APP_DIR ".");
        return;
    } else if ([appPaths count] > 1) {
        ConfigError(@"More than one application found in " FULL_APP_DIR ".");
        return;
    }

    /* Load the app meta-data */
    NSString *appPath = [appContainer stringByAppendingPathComponent: [appPaths objectAtIndex: 0]];
    _app = [[PLSimulatorApplication alloc] initWithPath: appPath error: &error];
    if (_app == nil) {
        [[NSAlert alertWithError: error] runModal];
        [[NSApplication sharedApplication] terminate: self];
        return;
    }
    
    /* if the app supports both iPhone and iPad, first check info.plist to see if a default device family
       was written in by the bundler.  If not, then prompt for whether to run as iPhone or iPad */
    if ([_app.deviceFamilies count] > 1 ) {
        NSDictionary *infoPlist = [[NSBundle mainBundle] infoDictionary];
        id obj = [infoPlist objectForKey:@"PLDefaultUIDeviceFamily"];
        if(obj != nil && [obj respondsToSelector:@selector(intValue)]) {
            _preferredDeviceFamily = [PLSimulatorDeviceFamily deviceFamilyForDeviceCode:[obj intValue]];
        }
        
        /* no device family found in info.plist, prompt the user which one to use */
        if( _preferredDeviceFamily == nil ) {
            NSString *infoFmt = NSLocalizedString(@"This app can run on either iPhone or iPad.  Select a device to use.", 
                                                  @"Device Selection for universal apps");
            
            NSAlert *alert = [NSAlert alertWithMessageText: NSLocalizedString(@"Select device to use.", @"Select device to use")
                                             defaultButton: NSLocalizedString(@"Use iPhone", @"iPhone button")
                                           alternateButton: NSLocalizedString(@"Use iPad", @"iPad button")
                                               otherButton: nil
                                 informativeTextWithFormat: infoFmt, _app.canonicalSDKName];
            NSInteger ret = [alert runModal];
            if(NSAlertDefaultReturn == ret ) {
                _preferredDeviceFamily = [PLSimulatorDeviceFamily iphoneFamily];
            } else {
                _preferredDeviceFamily = [PLSimulatorDeviceFamily ipadFamily];
            }            
        }
    }    

    /* Find the matching platform SDKs. We don't care about version, but do care about the SDK the 
     * app was built with and the device families it requires/supports */
    _discovery = [[PLSimulatorDiscovery alloc] initWithMinimumVersion: nil
                                                     canonicalSDKName: _app.canonicalSDKName
                                                       deviceFamilies: _app.deviceFamilies];
    _discovery.delegate = self;
    [_discovery startQuery];
    
}

// from PLSimulatorDiscoveryDelegate protocol
- (void) simulatorDiscovery: (PLSimulatorDiscovery *) discovery didFindMatchingSimulatorPlatforms: (NSArray *) platforms {
    /* No platforms found */
    if ([platforms count] == 0) {
        NSString *infoFmt = NSLocalizedString(@"The iPhone SDK required by the application could not be found. Please install the %@ SDK and try again.", 
                                              @"App SDK not found");
    
        NSAlert *alert = [NSAlert alertWithMessageText: NSLocalizedString(@"Required iPhone SDK not found.", @"SDK not found")
                                         defaultButton: NSLocalizedString(@"Quit", @"Quit button")
                                       alternateButton: nil
                                           otherButton: nil
                             informativeTextWithFormat: infoFmt, _app.canonicalSDKName];
        [alert runModal];
        [[NSApplication sharedApplication] terminate: self];
        return;
    }

    /* Launch with the discovery-preferred platform */
    LauncherSimClient *client = [[LauncherSimClient alloc] initWithPlatform: [platforms objectAtIndex: 0] app: _app preferredDeviceFamily:_preferredDeviceFamily];
    [client launch];
}

@end

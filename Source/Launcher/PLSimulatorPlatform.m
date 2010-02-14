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

#import "PLSimulatorPlatform.h"

#import "PLSimulator.h"

/* Relative path to the set of platform sub-SDKs */
#define PLATFORM_SUBSDK_PATH @"Developer/SDKs/"

/**
 * Manages a Simulator Platform SDK, allows querying of the bundled PLSimulatorSDK meta-data.
 *
 * @par Thread Safety
 * Immutable and thread-safe. May be used from any thread.
 */
@implementation PLSimulatorPlatform

@synthesize path = _path;
@synthesize sdks = _sdks;

/**
 * Initialize with the provided simulator platform SDK path.
 *
 * @param path Simulator platform SDK path (eg, /Developer/Platforms/iPhoneSimulator.platform)
 * @param error If an error occurs, upon return contains an NSError object that describes the problem.
 *
 * @return Returns an initialized PLSimulatorPlatform instance, or nil if the simulator meta-data can not
 * be parsed or the path appears to not be a valid platform SDK.
 */
- (id) initWithPath: (NSString *) path error: (NSError **) outError {
    if ((self = [super init]) == nil) {
        // Shouldn't happen
        plsimulator_populate_nserror(outError, PLSimulatorErrorUnknown, @"Unexpected error", nil);
        return nil;
    }
    
    _path = path;

    /* Verify that the path exists */
    NSFileManager *fm = [NSFileManager new];
    BOOL isDir;
    if (![fm fileExistsAtPath: _path isDirectory: &isDir] || isDir == NO) {
        NSString *desc = NSLocalizedString(@"The provided Platform SDK path does exist or is not a directory.",
                                           @"Missing/non-directory SDK path");
        plsimulator_populate_nserror(outError, PLSimulatorErrorInvalidSDK, desc, nil);
        return nil;
    }


    /* Load all SDKs */
    NSError *error;
    NSString *sdkDir = [_path stringByAppendingPathComponent: PLATFORM_SUBSDK_PATH];
    NSArray *sdkPaths = [fm contentsOfDirectoryAtPath: sdkDir error: &error];
    
    if (sdkPaths == nil) {
        NSString *desc = NSLocalizedString(@"The provided Platform SDK does not contain any SDKs",
                                           @"Missing/non-directory SDK sub-path");
        plsimulator_populate_nserror(outError, PLSimulatorErrorInvalidSDK, desc, error);
        return nil;
    }

    /* Iterate and load the SDK subdirectories */
    NSMutableArray *sdks = [NSMutableArray arrayWithCapacity: [sdkPaths count]];
    _sdks = sdks;

    for (NSString *sdkPath in sdkPaths) {
        NSString *absolutePath = [sdkDir stringByAppendingPathComponent: sdkPath];

        PLSimulatorSDK *sdk = [[PLSimulatorSDK alloc] initWithPath: absolutePath error: &error];

        /* Simply skip unparsable SDKs */
        if (sdk == nil) {
            NSLog(@"Skipping bad SDK %@: %@", absolutePath, error);
            continue;
        }

        [sdks addObject: sdk];
    }

    return self;
}


@end

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

#import "PLSimulatorDiscovery.h"

@implementation NSArray (Reverse)

- (NSArray *)reversedArray {
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:[self count]];
    NSEnumerator *enumerator = [self reverseObjectEnumerator];
    for (id element in enumerator) {
        [array addObject:element];
    }
    return array;
}

@end

@interface PLSimulatorDiscovery (PrivateMethods)
- (void) queryFinished: (NSNotification *) notification;
@end

/**
 * Implements automatic discovery of local Simulator Platform SDKs.
 *
 * @par Thread Safety
 * Mutable and may not be shared across threads.
 */
@implementation PLSimulatorDiscovery

@synthesize delegate = _delegate;

/**
 * Initialize a new query with the requested minumum simulator SDK version.
 *
 * @param version The required minumum simulator SDK version (3.0, 3.1.2, 3.2, etc). May be nil, in which
 * case no matching will be done on the version.
 * @param sdkName Specify a canonical name for an SDK that must be included with the platform SDK (iphonesimulator3.1, etc).
 * If nil, no verification of the canonical name will be done on SDKs contained in the platform SDK. 
 * @param deviceFamilies The set of requested PLSimulatorDeviceFamily types. Platform SDKs that match any of these device
 * families will be returned.
 */
- (id) initWithMinimumVersion: (NSString *) version 
             canonicalSDKName: (NSString *) canonicalSDKName
               deviceFamilies: (NSSet *) deviceFamilies 
{
    if ((self = [super init]) == nil)
        return nil;

    _version = [version copy];
    _canonicalSDKName = canonicalSDKName;
    _deviceFamilies = deviceFamilies;
    _query = [NSMetadataQuery new];

    /* Set up a query for all iPhoneSimulator platform directories. We use kMDItemDisplayName rather than
     * the more correct kMDItemFSName for performance reasons -- */
    NSArray *predicates = [NSArray arrayWithObjects:
                           [NSPredicate predicateWithFormat: @"kMDItemDisplayName == 'iPhoneSimulator.platform'"],
                           [NSPredicate predicateWithFormat: @"kMDItemContentTypeTree == 'public.directory'"],
                           nil];
    [_query setPredicate: [NSCompoundPredicate andPredicateWithSubpredicates: predicates]];

    /* We want to search the root volume for the developer tools. */
    NSURL *root = [NSURL fileURLWithPath: @"/" isDirectory: YES];
    [_query setSearchScopes: [NSArray arrayWithObject: root]];

    /* Configure result listening */
    NSNotificationCenter *nf = [NSNotificationCenter defaultCenter];
    [nf addObserver: self 
           selector: @selector(queryFinished:)
               name: NSMetadataQueryDidFinishGatheringNotification 
             object: _query];

    [_query setDelegate: self];

    return self;
}

/**
 * Start the query. A query can't be started if one is already running.
 */
- (void) startQuery {
    assert(_running == NO);
    _running = YES;

    [_query startQuery];
}

@end

/**
 * @internal
 */
@implementation PLSimulatorDiscovery (PrivateMethods)

/**
 * Comparison function. Compared two platforms by the latest version of their sub-SDKs.
 * Used to determine which platform is likely the most stable, as most users will only
 * have two SDKs installed -- the current, and a beta SDK.
 */
static NSInteger platform_compare_by_version (id obj1, id obj2, void *context) {
    PLSimulatorPlatform *platform1 = obj1;
    PLSimulatorPlatform *platform2 = obj2;
    
    /* Fetch the highest SDK version for each platform */
    NSString *(^Version)(PLSimulatorPlatform *) = ^(PLSimulatorPlatform *p) {
        NSString *last = nil;
        for (PLSimulatorSDK *sdk in p.sdks) {
            if (last == nil || rpm_vercomp([sdk.version UTF8String], [last UTF8String]) > 0)
                last = sdk.version;
        }

        return last;
    };
    
    NSString *ver1 = Version(platform1);
    NSString *ver2 = Version(platform2);

    /* Neither should be nil as we shouldn't be called on Platform SDKs that do not
     * contain sub-SDKs, but if that occurs, provide a reasonable answer */
    if (ver1 == nil && ver2 == nil)
        return NSOrderedSame;
    else if (ver1 == nil)
        return NSOrderedAscending;
    else if (ver2 == nil)
        return NSOrderedDescending;

    int res = rpm_vercomp([ver1 UTF8String], [ver2 UTF8String]);

    if (res > 0)
        return NSOrderedDescending;
    if (res < 0)
        return NSOrderedAscending;
    else
        return NSOrderedSame;
}

- (void)processQueryItemForPath:(NSString *)path overMin:(NSMutableArray *)overMin platformSDKs:(NSMutableArray *)platformSDKs {
    PLSimulatorPlatform *platform;
    NSError *error;    
    platform = [[PLSimulatorPlatform alloc] initWithPath: path error: &error];
    if (platform == nil) {
        NSLog(@"Skipping platform discovery result '%@', failed to load platform SDK meta-data: %@", path, error);
        return;
    }
    
    /* Check the minimum version and device families */
    BOOL hasMinVersion = NO;
    BOOL hasDeviceFamily = NO;
    BOOL hasExpectedSDK = NO;
    
    /* Skip filters that are not required */
    if (_version == nil)
        hasMinVersion = YES;
    
    if (_canonicalSDKName == nil)
        hasExpectedSDK = YES;
    
    for (PLSimulatorSDK *sdk in platform.sdks) {
        /* If greater than or equal to the minimum version, this platform SDK meets the requirements */
        if (_version != nil && rpm_vercomp([sdk.version UTF8String], [_version UTF8String]) >= 0)
            hasMinVersion = YES;
        
        /* Also check for the canonical SDK name */
        if (_canonicalSDKName != nil && [_canonicalSDKName isEqualToString: sdk.canonicalName])
            hasExpectedSDK = YES;
        
        /* If any our requested families are included, this platform SDK meets the requirements. */
        for (NSString *family in _deviceFamilies) {
            if ([sdk.deviceFamilies containsObject: family]) {
                hasDeviceFamily = YES;
                continue;
            }
        }
    }
    
    if (hasMinVersion && hasDeviceFamily) {
        [overMin addObject:platform];
    }
    
    if (!hasMinVersion || !hasDeviceFamily || !hasExpectedSDK)
        return;
    
    [platformSDKs addObject: platform];
}

- (void)processQueryResult:(NSMetadataItem *)item overMin:(NSMutableArray *)overMin platformSDKs:(NSMutableArray *)platformSDKs {
    NSString *path;
    path = [[item valueForAttribute: (NSString *) kMDItemPath] stringByResolvingSymlinksInPath];
    [self processQueryItemForPath:path overMin:overMin platformSDKs:platformSDKs];
}

// NSMetadataQueryDidFinishGatheringNotification
- (void) queryFinished: (NSNotification *) note {
    /* Received the full spotlight query result set. No longer running */
    _running = NO;

    /* Convert the items into PLSimulatorPlatform instances, filtering out results that don't match the minimum version
     * and supported device families. */
    NSArray *results = [_query results];
    NSMutableArray *platformSDKs = [NSMutableArray arrayWithCapacity: [results count]];
	NSMutableArray *overMin = [NSMutableArray arrayWithCapacity: [results count]];

    for (NSMetadataItem *item in results) {
        [self processQueryResult:item overMin:overMin platformSDKs:platformSDKs];
    }
	
    // if we didn't find anything by the standard search, then try and look for SDKs installed inside Xcode's app bundle in Applications.
    // this will be the norm in Xcode 4.3
    if ([platformSDKs count] == 0 && [overMin count] == 0) {
        [self processQueryItemForPath:@"/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform" overMin:overMin platformSDKs:platformSDKs];
    }
	
	
	NSArray *sorted = nil;
	
	// if there's no SDK that's an exact version match, use any that are over the min version.
	// in that case, sort to use the newest possible version
	if ([platformSDKs count] == 0 && [overMin count] > 0) {
		NSMutableArray *a = [NSMutableArray arrayWithCapacity:[overMin count]];

		NSEnumerator *enumerator = [[overMin sortedArrayUsingFunction: platform_compare_by_version context: nil] reverseObjectEnumerator];
		for (id element in enumerator) {
			[a addObject:element];
		}
		sorted = a;
	} else {
		/* Sort by version, try to choose the most stable SDK of the available set. */
		sorted = [platformSDKs sortedArrayUsingFunction: platform_compare_by_version context: nil];
    }
	
    /* Inform the delegate */
    [_delegate simulatorDiscovery: self didFindMatchingSimulatorPlatforms: sorted];
}

@end
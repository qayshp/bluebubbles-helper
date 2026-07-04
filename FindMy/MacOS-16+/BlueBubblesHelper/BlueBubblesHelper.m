//
//  BlueBubblesHelper.m
//  BlueBubblesHelper
//
//  Created by Tanay Neotia on 5/3/26.
//  Copyright © 2026 BlueBubbleMessaging. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <os/log.h>

#import "BlueBubblesHelper.h"
#import "FMLHandle.h"
#import "FMLLocation.h"
#import "FMLSession.h"
#import "Logging.h"
#import "NetworkController.h"

@interface BlueBubblesHelper ()
- (FindMyLocateSession *)findMyLocateSession;
- (void)handleFindMyFriendsRefreshWithTransaction:(NSString *)transaction;
- (NSDictionary *)serializeFMLFriend:(id)friend handle:(id)handle location:(id)location;
- (NSDictionary *)serializeFMLHandle:(id)handle;
- (NSDictionary *)serializeFMLLocation:(id)location handle:(id)handle;
@end

@implementation BlueBubblesHelper

static os_log_t logger;
static NetworkController *networkController;
static FindMyLocateSession *findMyLocateSession;

+ (instancetype)sharedInstance {
    static BlueBubblesHelper *plugin = nil;
    @synchronized(self) {
        if (!plugin) {
            plugin = [[self alloc] init];
            logger = os_log_create("BlueBubblesHelper", "findmy-helper");
        }
    }
    return plugin;
}

+ (void)load {
    [BlueBubblesHelper sharedInstance];

    NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    os_log(logger, "%{public}@ loaded into %{public}@ on macOS %ld.%ld.%ld", [self className], bundleIdentifier, (long)version.majorVersion, (long)version.minorVersion, (long)version.patchVersion);

    if (![bundleIdentifier isEqualToString:@"com.apple.findmy"]) {
        os_log_error(logger, "Injected into non-Find My process %{public}@, aborting.", bundleIdentifier);
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        os_log(logger, "Injected into Find My. Connecting to BlueBubbles Server...");
        networkController = [NetworkController sharedInstance];
        [networkController connect];
    });
}

- (void)handleServerEvent:(NSString *)event data:(NSDictionary *)data transactionId:(NSString *)transaction {
    if ([event isEqualToString:@"refresh-findmy-friends"]) {
        [self handleFindMyFriendsRefreshWithTransaction:transaction];
        return;
    }

    DLog("BLUEBUBBLESHELPER: Find My action not implemented: %{public}@", event);
    if (transaction != nil) {
        [[NetworkController sharedInstance] sendMessage:@{
            @"transactionId": transaction,
            @"error": [NSString stringWithFormat:@"Find My action not implemented: %@", event ?: @"<nil>"],
        }];
    }
}

- (id)objectValueFromObject:(id)object selector:(SEL)selector {
    if (object == nil || ![object respondsToSelector:selector]) {
        return nil;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [object performSelector:selector];
#pragma clang diagnostic pop
}

- (FindMyLocateSession *)findMyLocateSession {
    if (findMyLocateSession != nil) {
        return findMyLocateSession;
    }

    Class sessionClass = NSClassFromString(@"FindMyLocateSession");
    if (sessionClass == nil) {
        NSError *loadError = nil;
        NSBundle *wrapperBundle = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/FindMyLocateObjCWrapper.framework"];
        if (![wrapperBundle loadAndReturnError:&loadError]) {
            DLog("BLUEBUBBLESHELPER: Failed to load FindMyLocateObjCWrapper.framework: %@", loadError);
        }
        sessionClass = NSClassFromString(@"FindMyLocateSession");
    }

    if (sessionClass == nil) {
        DLog("BLUEBUBBLESHELPER: FindMyLocateSession class is unavailable");
        return nil;
    }

    findMyLocateSession = [[sessionClass alloc] init];

    if ([findMyLocateSession respondsToSelector:@selector(startUpdatingFriendsWithInitialUpdates:completion:)]) {
        [findMyLocateSession startUpdatingFriendsWithInitialUpdates:YES completion:^{
            DLog("BLUEBUBBLESHELPER: FindMyLocateSession started updating friends");
        }];
    }

    if ([findMyLocateSession respondsToSelector:@selector(startMonitoringActiveLocationSharingDeviceChangeWithCompletion:)]) {
        [findMyLocateSession startMonitoringActiveLocationSharingDeviceChangeWithCompletion:^{
            DLog("BLUEBUBBLESHELPER: FindMyLocateSession started active device monitoring");
        }];
    }

    return findMyLocateSession;
}

- (id)handleForFMLFriend:(id)friend {
    if (friend == nil) {
        return nil;
    }
    if ([friend isKindOfClass:NSClassFromString(@"FMLHandle")]) {
        return friend;
    }
    return [self objectValueFromObject:friend selector:@selector(handle)];
}

- (NSString *)identifierForFMLHandle:(id)handle {
    id identifier = [self objectValueFromObject:handle selector:@selector(identifier)];
    if ([identifier isKindOfClass:[NSString class]]) {
        return identifier;
    }

    id comparisonIdentifier = [self objectValueFromObject:handle selector:@selector(comparisonIdentifier)];
    if ([comparisonIdentifier isKindOfClass:[NSString class]]) {
        return comparisonIdentifier;
    }

    return handle == nil ? nil : [handle description];
}

- (NSDictionary *)serializeFMLHandle:(id)handle {
    return @{
        @"identifier": [self identifierForFMLHandle:handle] ?: [NSNull null],
        @"description": handle == nil ? [NSNull null] : [handle description],
    };
}

- (NSDictionary *)serializeFMLLocation:(id)location handle:(id)handle {
    if (location == nil) {
        return @{
            @"handle": [self identifierForFMLHandle:handle] ?: [NSNull null],
            @"location": [NSNull null],
        };
    }

    FMLLocation *fmlLocation = (FMLLocation *)location;
    double latitude = [fmlLocation respondsToSelector:@selector(latitude)] ? [fmlLocation latitude] : 0;
    double longitude = [fmlLocation respondsToSelector:@selector(longitude)] ? [fmlLocation longitude] : 0;
    double timestamp = [fmlLocation respondsToSelector:@selector(timestamp)] ? [fmlLocation timestamp] : 0;
    long long locationType = [fmlLocation respondsToSelector:@selector(locationType)] ? [fmlLocation locationType] : 0;
    id address = [self objectValueFromObject:fmlLocation selector:@selector(address)];
    NSString *coarseAddressLabel = [self objectValueFromObject:fmlLocation selector:@selector(coarseAddressLabel)];
    NSArray *labels = [self objectValueFromObject:fmlLocation selector:@selector(labels)];

    return @{
        @"handle": [self identifierForFMLHandle:handle] ?: [NSNull null],
        @"coordinates": @[@(latitude), @(longitude)],
        @"long_address": address == nil ? [NSNull null] : [address description],
        @"short_address": coarseAddressLabel ?: [NSNull null],
        @"subtitle": coarseAddressLabel ?: [NSNull null],
        @"title": labels ?: [NSNull null],
        @"last_updated": timestamp > 0 ? @(round(timestamp) * 1000) : [NSNull null],
        @"is_locating_in_progress": @NO,
        @"status": (locationType == 0) ? @"legacy" : (locationType == 2) ? @"live" : @"shallow",
        @"location_type": @(locationType),
        @"horizontal_accuracy": [fmlLocation respondsToSelector:@selector(horizontalAccuracy)] ? @([fmlLocation horizontalAccuracy]) : [NSNull null],
        @"vertical_accuracy": [fmlLocation respondsToSelector:@selector(verticalAccuracy)] ? @([fmlLocation verticalAccuracy]) : [NSNull null],
        @"speed": [fmlLocation respondsToSelector:@selector(speed)] ? @([fmlLocation speed]) : [NSNull null],
        @"altitude": [fmlLocation respondsToSelector:@selector(altitude)] ? @([fmlLocation altitude]) : [NSNull null],
    };
}

- (NSDictionary *)serializeFMLFriend:(id)friend handle:(id)handle location:(id)location {
    NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithDictionary:[self serializeFMLLocation:location handle:handle]];
    [result setValue:[self serializeFMLHandle:handle] forKey:@"findmy_handle"];
    [result setValue:friend == nil ? [NSNull null] : [friend description] forKey:@"friend"];
    return [result copy];
}

- (NSArray *)cachedFindMyFriendsForSession:(FindMyLocateSession *)session {
    NSArray *friends = nil;

    if ([session respondsToSelector:@selector(cachedFriendsSharingLocationWithMe)]) {
        friends = [self objectValueFromObject:session selector:@selector(cachedFriendsSharingLocationWithMe)];
    }
    if (friends == nil && [session respondsToSelector:@selector(cachedFriendsSharingLocationsWithMe)]) {
        friends = [self objectValueFromObject:session selector:@selector(cachedFriendsSharingLocationsWithMe)];
    }

    return [friends isKindOfClass:[NSArray class]] ? friends : @[];
}

- (void)sendFindMyFriends:(NSArray *)friends session:(FindMyLocateSession *)session transaction:(NSString *)transaction {
    if (friends.count == 0) {
        [[NetworkController sharedInstance] sendMessage:@{@"transactionId": transaction ?: [NSNull null], @"locations": @[]}];
        return;
    }

    NSMutableArray *locations = [[NSMutableArray alloc] init];
    dispatch_group_t refreshGroup = dispatch_group_create();

    for (id friend in friends) {
        id handle = [self handleForFMLFriend:friend];
        if (handle == nil) {
            @synchronized (locations) {
                [locations addObject:[self serializeFMLFriend:friend handle:nil location:nil]];
            }
            continue;
        }

        dispatch_group_enter(refreshGroup);
        void (^finishRefresh)(void) = ^{
            id location = nil;
            if ([session respondsToSelector:@selector(cachedLocationForHandle:includeAddress:)]) {
                location = [session cachedLocationForHandle:handle includeAddress:YES];
            } else if ([session respondsToSelector:@selector(cachedLocationForHandle:)]) {
                location = [session cachedLocationForHandle:handle];
            }

            @synchronized (locations) {
                [locations addObject:[self serializeFMLFriend:friend handle:handle location:location]];
            }
            dispatch_group_leave(refreshGroup);
        };

        if ([session respondsToSelector:@selector(startRefreshingLocationForHandles:priority:isFromGroup:reverseGeocode:completion:)]) {
            [session startRefreshingLocationForHandles:@[handle] priority:1000 isFromGroup:NO reverseGeocode:YES completion:finishRefresh];
        } else if ([session respondsToSelector:@selector(startRefreshingLocationForHandles:priority:isFromGroup:completion:)]) {
            [session startRefreshingLocationForHandles:@[handle] priority:1000 isFromGroup:NO completion:finishRefresh];
        } else {
            finishRefresh();
        }
    }

    __block BOOL didSendResponse = NO;
    void (^sendResponse)(void) = ^{
        @synchronized (locations) {
            if (didSendResponse) {
                return;
            }
            didSendResponse = YES;
            [[NetworkController sharedInstance] sendMessage:@{
                @"transactionId": transaction ?: [NSNull null],
                @"locations": locations,
            }];
        }
    };

    dispatch_group_notify(refreshGroup, dispatch_get_main_queue(), ^{
        sendResponse();
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DLog("BLUEBUBBLESHELPER: Find My refresh timeout fired with %lu locations", (unsigned long)[locations count]);
        sendResponse();
    });
}

- (void)handleFindMyFriendsRefreshWithTransaction:(NSString *)transaction {
    FindMyLocateSession *session = [self findMyLocateSession];
    if (session == nil) {
        [[NetworkController sharedInstance] sendMessage:@{
            @"transactionId": transaction ?: [NSNull null],
            @"error": @"FindMyLocateSession is unavailable",
        }];
        return;
    }

    if ([session respondsToSelector:@selector(getFriendsSharingLocationsWithMeWithCompletion:)]) {
        [session getFriendsSharingLocationsWithMeWithCompletion:^(NSArray *friends) {
            NSArray *friendList = [friends isKindOfClass:[NSArray class]] ? friends : [self cachedFindMyFriendsForSession:session];
            [self sendFindMyFriends:friendList session:session transaction:transaction];
        }];
    } else {
        [self sendFindMyFriends:[self cachedFindMyFriendsForSession:session] session:session transaction:transaction];
    }
}

@end

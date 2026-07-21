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
#import "FMLSession.h"
#import "FindMyFriendPayload.h"
#import "Logging.h"
#import "NetworkController.h"

@interface BlueBubblesHelper ()
- (FindMyLocateSession *)findMyLocateSession;
- (void)handleFindMyFriendsRefreshWithTransaction:(NSString *)transaction;
- (id)cachedLocationForHandle:(id)handle session:(FindMyLocateSession *)session;
- (void)sendFindMyFriends:(NSArray *)friends
                  session:(FindMyLocateSession *)session
              transaction:(NSString *)transaction
       friendListTimedOut:(BOOL)friendListTimedOut;
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

    if (event == nil || [event rangeOfString:@"findmy" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        DLog("BLUEBUBBLESHELPER: Ignoring unrelated Private API action: %{public}@", event);
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
    return [self objectValueFromObject:friend selector:NSSelectorFromString(@"handle")];
}

- (id)cachedLocationForHandle:(id)handle session:(FindMyLocateSession *)session {
    if ([session respondsToSelector:@selector(cachedLocationForHandle:includeAddress:)]) {
        return [session cachedLocationForHandle:handle includeAddress:YES];
    }
    if ([session respondsToSelector:@selector(cachedLocationForHandle:)]) {
        return [session cachedLocationForHandle:handle];
    }

    return nil;
}

- (NSArray *)cachedFindMyFriendsForSession:(FindMyLocateSession *)session {
    NSArray *friends = nil;

    SEL singularFriendsSelector = NSSelectorFromString(@"cachedFriendsSharingLocationWithMe");
    if ([session respondsToSelector:singularFriendsSelector]) {
        friends = [self objectValueFromObject:session selector:singularFriendsSelector];
    }
    if (friends == nil && [session respondsToSelector:@selector(cachedFriendsSharingLocationsWithMe)]) {
        friends = [self objectValueFromObject:session selector:@selector(cachedFriendsSharingLocationsWithMe)];
    }

    return [friends isKindOfClass:[NSArray class]] ? friends : @[];
}

- (void)sendFindMyFriends:(NSArray *)friends
                  session:(FindMyLocateSession *)session
              transaction:(NSString *)transaction
       friendListTimedOut:(BOOL)friendListTimedOut {
    NSMutableDictionary<NSString *, NSDictionary *> *locationsByHandle = [[NSMutableDictionary alloc] init];
    NSMutableSet<NSString *> *pendingHandles = [[NSMutableSet alloc] init];
    dispatch_group_t refreshGroup = dispatch_group_create();
    __block NSUInteger skippedFriends = 0;

    for (id friend in friends) {
        id handle = [self handleForFMLFriend:friend];
        NSString *identifier = [FindMyFriendPayload identifierForHandle:handle];
        if (identifier == nil) {
            skippedFriends += 1;
            continue;
        }

        NSDictionary *cachedPayload = [FindMyFriendPayload
            locationPayloadForLocation:[self cachedLocationForHandle:handle session:session]
                                 handle:handle];
        if (cachedPayload == nil) {
            skippedFriends += 1;
            continue;
        }

        __block BOOL shouldRefresh = NO;
        @synchronized (pendingHandles) {
            if (locationsByHandle[identifier] == nil) {
                locationsByHandle[identifier] = cachedPayload;
                [pendingHandles addObject:identifier];
                shouldRefresh = YES;
            }
        }
        if (!shouldRefresh) {
            continue;
        }

        dispatch_group_enter(refreshGroup);
        __block BOOL didFinishRefresh = NO;
        void (^finishRefresh)(void) = ^{
            @synchronized (pendingHandles) {
                if (didFinishRefresh) {
                    return;
                }
                didFinishRefresh = YES;

                NSDictionary *payload = [FindMyFriendPayload
                    locationPayloadForLocation:[self cachedLocationForHandle:handle session:session]
                                         handle:handle];
                if (payload != nil) {
                    locationsByHandle[identifier] = payload;
                }
                [pendingHandles removeObject:identifier];
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
        NSDictionary *response = nil;
        @synchronized (pendingHandles) {
            if (didSendResponse) {
                return;
            }
            didSendResponse = YES;
            response = [FindMyFriendPayload responseForTransaction:transaction
                                                  locationsByHandle:locationsByHandle
                                                     pendingHandles:pendingHandles
                                                 friendListTimedOut:friendListTimedOut
                                                     skippedFriends:skippedFriends];
        }
        [[NetworkController sharedInstance] sendMessage:response];
    };

    dispatch_group_notify(refreshGroup, dispatch_get_main_queue(), ^{
        sendResponse();
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DLog("BLUEBUBBLESHELPER: Find My refresh timeout fired with %lu pending handle(s)", (unsigned long)pendingHandles.count);
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

    __block BOOL didReceiveFriendList = NO;
    void (^useFriendList)(NSArray *, BOOL) = ^(NSArray *friends, BOOL timedOut) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (didReceiveFriendList) {
                return;
            }
            didReceiveFriendList = YES;

            NSArray *friendList = [friends isKindOfClass:[NSArray class]]
                ? friends : [self cachedFindMyFriendsForSession:session];
            [self sendFindMyFriends:friendList
                            session:session
                        transaction:transaction
                 friendListTimedOut:timedOut];
        });
    };

    if (![session respondsToSelector:@selector(getFriendsSharingLocationsWithMeWithCompletion:)]) {
        useFriendList([self cachedFindMyFriendsForSession:session], NO);
        return;
    }

    [session getFriendsSharingLocationsWithMeWithCompletion:^(NSArray *friends) {
        useFriendList(friends, NO);
    }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (didReceiveFriendList) {
            return;
        }
        DLog("BLUEBUBBLESHELPER: Find My friend-list request timed out; using cached friends");
        useFriendList([self cachedFindMyFriendsForSession:session], YES);
    });
}

@end

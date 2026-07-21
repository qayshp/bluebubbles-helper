#import "FindMyFriendsHelper.h"

#import <os/log.h>

#import "FindMyLocateSession.h"
#import "FindMyFriendPayload.h"
#import "ServerConnection.h"

static const NSTimeInterval BBConnectionDelaySeconds = 5.0;
static const NSTimeInterval BBFriendListTimeoutSeconds = 5.0;
static const NSTimeInterval BBLocationRefreshTimeoutSeconds = 8.0;
static const long long BBLocationRefreshPriority = 1000;

@interface FindMyFriendsHelper ()
- (nullable id)valueForSelector:(SEL)selector onObject:(nullable id)object;
- (nullable FindMyLocateSession *)locateSession;
- (nullable id)locationHandleForFriend:(nullable id)friendRecord;
- (nullable id)cachedLocationForHandle:(id)locationHandle session:(FindMyLocateSession *)session;
- (NSArray *)cachedFriendsForSession:(FindMyLocateSession *)session;
- (void)refreshAndSendLocationsForFriends:(NSArray *)friendRecords
                                  session:(FindMyLocateSession *)session
                    transactionIdentifier:(nullable NSString *)transactionIdentifier
                       friendListTimedOut:(BOOL)friendListTimedOut;
- (void)handleFriendsRefreshForTransactionIdentifier:(nullable NSString *)transactionIdentifier;
- (void)sendError:(NSString *)errorMessage transactionIdentifier:(nullable NSString *)transactionIdentifier;
@end

@implementation FindMyFriendsHelper

static os_log_t helperLog;
static FindMyLocateSession *activeLocateSession;

+ (instancetype)sharedInstance {
    static FindMyFriendsHelper *sharedHelper = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedHelper = [[self alloc] init];
        helperLog = os_log_create("BlueBubblesFindMyHelper", "friends-helper");
    });
    return sharedHelper;
}

+ (void)load {
    [FindMyFriendsHelper sharedInstance];

    NSString *hostBundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    if (![hostBundleIdentifier isEqualToString:@"com.apple.findmy"]) {
        os_log_error(helperLog, "Refusing injection into %{public}@", hostBundleIdentifier);
        return;
    }

    NSOperatingSystemVersion operatingSystemVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
    os_log(
        helperLog,
        "Loaded on macOS %ld.%ld.%ld",
        (long)operatingSystemVersion.majorVersion,
        (long)operatingSystemVersion.minorVersion,
        (long)operatingSystemVersion.patchVersion
    );

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(BBConnectionDelaySeconds * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{
            [[ServerConnection sharedInstance] connect];
        }
    );
}

- (void)handleServerAction:(nullable NSString *)action
     transactionIdentifier:(nullable NSString *)transactionIdentifier {
    if ([action isEqualToString:@"refresh-findmy-friends"]) {
        [self handleFriendsRefreshForTransactionIdentifier:transactionIdentifier];
        return;
    }

    if (action == nil) {
        os_log(helperLog, "Ignoring Private API action without a name");
        return;
    }

    NSRange findMyMarker = [action rangeOfString:@"findmy" options:NSCaseInsensitiveSearch];
    if (findMyMarker.location == NSNotFound) {
        os_log(helperLog, "Ignoring unrelated Private API action: %{public}@", action);
        return;
    }

    NSString *errorMessage = [NSString stringWithFormat:@"Find My action not implemented: %@", action];
    [self sendError:errorMessage transactionIdentifier:transactionIdentifier];
}

- (void)sendError:(NSString *)errorMessage transactionIdentifier:(nullable NSString *)transactionIdentifier {
    os_log_error(helperLog, "%{public}@", errorMessage);
    if (transactionIdentifier == nil) {
        return;
    }
    [[ServerConnection sharedInstance] sendMessage:@{
        @"transactionId": transactionIdentifier,
        @"error": errorMessage,
    }];
}

- (nullable id)valueForSelector:(SEL)selector onObject:(nullable id)object {
    if (object == nil || ![object respondsToSelector:selector]) {
        return nil;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [object performSelector:selector];
#pragma clang diagnostic pop
}

- (nullable FindMyLocateSession *)locateSession {
    if (activeLocateSession != nil) {
        return activeLocateSession;
    }

    Class locateSessionClass = NSClassFromString(@"FindMyLocateSession");
    if (locateSessionClass == nil) {
        NSError *frameworkLoadError = nil;
        NSBundle *wrapperFramework = [NSBundle
            bundleWithPath:@"/System/Library/PrivateFrameworks/FindMyLocateObjCWrapper.framework"];
        if (![wrapperFramework loadAndReturnError:&frameworkLoadError]) {
            os_log_error(helperLog, "Unable to load FindMyLocateObjCWrapper: %{public}@", frameworkLoadError);
        }
        locateSessionClass = NSClassFromString(@"FindMyLocateSession");
    }

    if (locateSessionClass == nil) {
        os_log_error(helperLog, "FindMyLocateSession is unavailable");
        return nil;
    }

    activeLocateSession = [[locateSessionClass alloc] init];

    if ([activeLocateSession respondsToSelector:@selector(startUpdatingFriendsWithInitialUpdates:completion:)]) {
        [activeLocateSession startUpdatingFriendsWithInitialUpdates:YES completion:^{
            os_log(helperLog, "Find My friend updates started");
        }];
    }

    if ([activeLocateSession respondsToSelector:@selector(startMonitoringActiveLocationSharingDeviceChangeWithCompletion:)]) {
        [activeLocateSession startMonitoringActiveLocationSharingDeviceChangeWithCompletion:^{
            os_log(helperLog, "Find My active-device monitoring started");
        }];
    }

    return activeLocateSession;
}

- (nullable id)locationHandleForFriend:(nullable id)friendRecord {
    if (friendRecord == nil) {
        return nil;
    }
    if ([friendRecord isKindOfClass:NSClassFromString(@"FMLHandle")]) {
        return friendRecord;
    }
    return [self valueForSelector:NSSelectorFromString(@"handle") onObject:friendRecord];
}

- (nullable id)cachedLocationForHandle:(id)locationHandle session:(FindMyLocateSession *)session {
    if ([session respondsToSelector:@selector(cachedLocationForHandle:includeAddress:)]) {
        return [session cachedLocationForHandle:locationHandle includeAddress:YES];
    }
    if ([session respondsToSelector:@selector(cachedLocationForHandle:)]) {
        return [session cachedLocationForHandle:locationHandle];
    }
    return nil;
}

- (NSArray *)cachedFriendsForSession:(FindMyLocateSession *)session {
    NSArray *cachedFriends = nil;
    SEL singularLocationSelector = NSSelectorFromString(@"cachedFriendsSharingLocationWithMe");
    if ([session respondsToSelector:singularLocationSelector]) {
        cachedFriends = [self valueForSelector:singularLocationSelector onObject:session];
    }
    if (cachedFriends == nil && [session respondsToSelector:@selector(cachedFriendsSharingLocationsWithMe)]) {
        cachedFriends = [self valueForSelector:@selector(cachedFriendsSharingLocationsWithMe) onObject:session];
    }
    return [cachedFriends isKindOfClass:[NSArray class]] ? cachedFriends : @[];
}

- (void)refreshAndSendLocationsForFriends:(NSArray *)friendRecords
                                  session:(FindMyLocateSession *)session
                    transactionIdentifier:(nullable NSString *)transactionIdentifier
                       friendListTimedOut:(BOOL)friendListTimedOut {
    NSMutableDictionary<NSString *, NSDictionary *> *locationsByFriendIdentifier = [[NSMutableDictionary alloc] init];
    NSMutableSet<NSString *> *pendingFriendIdentifiers = [[NSMutableSet alloc] init];
    NSMutableArray<void (^)(void)> *completeLocationRefreshBlocks = [[NSMutableArray alloc] init];
    dispatch_group_t locationRefreshGroup = dispatch_group_create();
    __block NSUInteger unidentifiedFriendCount = 0;

    for (id friendRecord in friendRecords) {
        id locationHandle = [self locationHandleForFriend:friendRecord];
        NSString *friendIdentifier = [FindMyFriendPayload identifierForHandle:locationHandle];
        if (friendIdentifier == nil) {
            unidentifiedFriendCount += 1;
            continue;
        }

        NSDictionary *cachedLocationPayload = [FindMyFriendPayload
            locationPayloadForLocation:[self cachedLocationForHandle:locationHandle session:session]
                                 handle:locationHandle];
        if (cachedLocationPayload == nil) {
            unidentifiedFriendCount += 1;
            continue;
        }

        __block BOOL shouldRefreshLocation = NO;
        @synchronized (pendingFriendIdentifiers) {
            if (locationsByFriendIdentifier[friendIdentifier] == nil) {
                locationsByFriendIdentifier[friendIdentifier] = cachedLocationPayload;
                [pendingFriendIdentifiers addObject:friendIdentifier];
                shouldRefreshLocation = YES;
            }
        }
        if (!shouldRefreshLocation) {
            continue;
        }

        dispatch_group_enter(locationRefreshGroup);
        __block BOOL locationRefreshCompleted = NO;
        void (^completeLocationRefresh)(void) = ^{
            @synchronized (pendingFriendIdentifiers) {
                if (locationRefreshCompleted) {
                    return;
                }
                locationRefreshCompleted = YES;

                NSDictionary *refreshedLocationPayload = [FindMyFriendPayload
                    locationPayloadForLocation:[self cachedLocationForHandle:locationHandle session:session]
                                         handle:locationHandle];
                if (refreshedLocationPayload != nil) {
                    locationsByFriendIdentifier[friendIdentifier] = refreshedLocationPayload;
                }
                [pendingFriendIdentifiers removeObject:friendIdentifier];
            }
            dispatch_group_leave(locationRefreshGroup);
        };
        [completeLocationRefreshBlocks addObject:completeLocationRefresh];

        if ([session respondsToSelector:@selector(startRefreshingLocationForHandles:priority:isFromGroup:reverseGeocode:completion:)]) {
            [session startRefreshingLocationForHandles:@[locationHandle]
                                              priority:BBLocationRefreshPriority
                                           isFromGroup:NO
                                        reverseGeocode:YES
                                            completion:completeLocationRefresh];
        } else if ([session respondsToSelector:@selector(startRefreshingLocationForHandles:priority:isFromGroup:completion:)]) {
            [session startRefreshingLocationForHandles:@[locationHandle]
                                              priority:BBLocationRefreshPriority
                                           isFromGroup:NO
                                            completion:completeLocationRefresh];
        } else {
            completeLocationRefresh();
        }
    }

    __block BOOL responseSent = NO;
    void (^sendResponseOnce)(void) = ^{
        NSDictionary *response = nil;
        @synchronized (pendingFriendIdentifiers) {
            if (responseSent) {
                return;
            }
            responseSent = YES;
            response = [FindMyFriendPayload
                responseForTransactionIdentifier:transactionIdentifier
                     locationsByFriendIdentifier:locationsByFriendIdentifier
                        pendingFriendIdentifiers:pendingFriendIdentifiers
                              friendListTimedOut:friendListTimedOut
                       unidentifiedFriendCount:unidentifiedFriendCount];
        }
        [[ServerConnection sharedInstance] sendMessage:response];
    };

    dispatch_group_notify(locationRefreshGroup, dispatch_get_main_queue(), sendResponseOnce);

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(BBLocationRefreshTimeoutSeconds * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{
            NSUInteger pendingFriendCount = 0;
            @synchronized (pendingFriendIdentifiers) {
                pendingFriendCount = pendingFriendIdentifiers.count;
            }
            os_log(helperLog, "Friend location deadline reached with %lu pending", (unsigned long)pendingFriendCount);
            sendResponseOnce();
            for (void (^completeLocationRefresh)(void) in completeLocationRefreshBlocks) {
                completeLocationRefresh();
            }
        }
    );
}

- (void)handleFriendsRefreshForTransactionIdentifier:(nullable NSString *)transactionIdentifier {
    FindMyLocateSession *session = [self locateSession];
    if (session == nil) {
        [self sendError:@"FindMyLocateSession is unavailable" transactionIdentifier:transactionIdentifier];
        return;
    }

    __block BOOL friendListResolved = NO;
    void (^resolveFriendListOnce)(NSArray *, BOOL) = ^(NSArray *requestedFriends, BOOL timedOut) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (friendListResolved) {
                return;
            }
            friendListResolved = YES;

            NSArray *friendRecords = [requestedFriends isKindOfClass:[NSArray class]]
                ? requestedFriends : [self cachedFriendsForSession:session];
            [self refreshAndSendLocationsForFriends:friendRecords
                                            session:session
                              transactionIdentifier:transactionIdentifier
                                 friendListTimedOut:timedOut];
        });
    };

    if (![session respondsToSelector:@selector(getFriendsSharingLocationsWithMeWithCompletion:)]) {
        resolveFriendListOnce([self cachedFriendsForSession:session], NO);
        return;
    }

    [session getFriendsSharingLocationsWithMeWithCompletion:^(NSArray *requestedFriends) {
        resolveFriendListOnce(requestedFriends, NO);
    }];

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(BBFriendListTimeoutSeconds * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{
            if (friendListResolved) {
                return;
            }
            os_log(helperLog, "Friend list deadline reached; using cached friends");
            resolveFriendListOnce([self cachedFriendsForSession:session], YES);
        }
    );
}

@end

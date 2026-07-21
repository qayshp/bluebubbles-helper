#import <Foundation/Foundation.h>

#import "FindMyFriendPayload.h"

@interface BBMockHandle : NSObject
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *comparisonIdentifier;
@end

@implementation BBMockHandle
@end

@interface BBMockLocation : NSObject
@property(nonatomic) double altitude;
@property(nonatomic, copy) NSString *coarseAddressLabel;
@property(nonatomic) double horizontalAccuracy;
@property(nonatomic, copy) NSArray *labels;
@property(nonatomic) double latitude;
@property(nonatomic) long long locationType;
@property(nonatomic) double longitude;
@property(nonatomic) double speed;
@property(nonatomic) double timestamp;
@property(nonatomic) double verticalAccuracy;
@end

@implementation BBMockLocation
@end

static void BBAssert(BOOL condition, NSString *message) {
    if (condition) {
        return;
    }

    NSLog(@"FAIL: %@", message);
    exit(1);
}

static BBMockHandle *BBHandle(NSString *identifier) {
    BBMockHandle *handle = [[BBMockHandle alloc] init];
    handle.identifier = identifier;
    return handle;
}

int main(void) {
    @autoreleasepool {
        BBAssert([FindMyFriendPayload identifierForHandle:nil] == nil, @"nil handles must not gain an identity");

        BBMockHandle *comparisonHandle = [[BBMockHandle alloc] init];
        comparisonHandle.comparisonIdentifier = @"comparison-id";
        BBAssert([[FindMyFriendPayload identifierForHandle:comparisonHandle] isEqualToString:@"comparison-id"],
                 @"comparisonIdentifier must be the explicit fallback");

        BBMockHandle *alice = BBHandle(@"alice@example.com");
        NSDictionary *missingLocation = [FindMyFriendPayload locationPayloadForLocation:nil handle:alice];
        BBAssert([missingLocation[@"coordinates"] isEqual:[NSNull null]], @"missing coordinates must stay null");
        BBAssert([missingLocation[@"handle"] isEqualToString:@"alice@example.com"], @"handle must be stable");
        BBAssert(missingLocation[@"description"] == nil && missingLocation[@"friend"] == nil,
                 @"opaque private descriptions must not be exported");

        BBMockLocation *liveLocation = [[BBMockLocation alloc] init];
        liveLocation.latitude = 47.61;
        liveLocation.longitude = -122.33;
        liveLocation.timestamp = 1234.567;
        liveLocation.locationType = 2;
        liveLocation.coarseAddressLabel = @"Seattle, WA";
        liveLocation.labels = @[@42, @"Alice"];
        liveLocation.horizontalAccuracy = 6.5;
        liveLocation.verticalAccuracy = 9.0;
        liveLocation.speed = 1.25;
        liveLocation.altitude = 32.0;

        NSDictionary *livePayload = [FindMyFriendPayload locationPayloadForLocation:liveLocation handle:alice];
        BBAssert([livePayload[@"coordinates"] isEqual:@[@47.61, @-122.33]], @"coordinates must be preserved");
        BBAssert([livePayload[@"title"] isEqualToString:@"Alice"], @"the first string label must become the title");
        BBAssert([livePayload[@"long_address"] isEqualToString:@"Seattle, WA"], @"address must use an explicit string field");
        BBAssert([livePayload[@"last_updated"] isEqual:@1234567], @"timestamps must be converted to milliseconds");
        BBAssert([livePayload[@"status"] isEqualToString:@"live"], @"location type 2 must map to live");

        NSDictionary *locationsByHandle = @{
            @"bob@example.com": [FindMyFriendPayload locationPayloadForLocation:nil handle:BBHandle(@"bob@example.com")],
            @"alice@example.com": livePayload,
        };
        NSDictionary *complete = [FindMyFriendPayload responseForTransaction:@"transaction"
                                                            locationsByHandle:locationsByHandle
                                                               pendingHandles:[NSSet set]
                                                           friendListTimedOut:NO
                                                               skippedFriends:1];
        NSArray *completeLocations = complete[@"locations"];
        BBAssert([complete[@"partial"] isEqual:@NO], @"completed refreshes must not be partial");
        BBAssert([completeLocations[0][@"handle"] isEqualToString:@"alice@example.com"],
                 @"responses must be sorted by stable handle");
        BBAssert([complete[@"skippedFriends"] isEqual:@1], @"skipped friend count must be retained");

        NSSet *pending = [NSSet setWithObjects:@"bob@example.com", @"alice@example.com", nil];
        NSDictionary *partial = [FindMyFriendPayload responseForTransaction:@"transaction"
                                                           locationsByHandle:locationsByHandle
                                                              pendingHandles:pending
                                                          friendListTimedOut:YES
                                                              skippedFriends:0];
        BBAssert([partial[@"partial"] isEqual:@YES], @"timeouts must be explicit");
        BBAssert([partial[@"friendListTimedOut"] isEqual:@YES], @"friend-list timeout must be explicit");
        BBAssert([partial[@"timedOutHandles"] isEqual:@[@"alice@example.com", @"bob@example.com"]],
                 @"timed-out handles must be deterministic");

        NSLog(@"PASS: FindMyFriendPayloadTests");
    }

    return 0;
}

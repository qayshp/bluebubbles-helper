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

static BBMockHandle *BBHandleWithIdentifier(NSString *identifier) {
    BBMockHandle *findMyHandle = [[BBMockHandle alloc] init];
    findMyHandle.identifier = identifier;
    return findMyHandle;
}

int main(void) {
    @autoreleasepool {
        BBAssert([FindMyFriendPayload identifierForHandle:nil] == nil, @"nil handles must not gain an identity");

        BBMockHandle *comparisonHandle = [[BBMockHandle alloc] init];
        comparisonHandle.comparisonIdentifier = @"comparison-id";
        BBAssert([[FindMyFriendPayload identifierForHandle:comparisonHandle] isEqualToString:@"comparison-id"],
                 @"comparisonIdentifier must be the explicit fallback");

        BBMockHandle *aliceHandle = BBHandleWithIdentifier(@"alice@example.com");
        NSDictionary *missingLocationPayload = [FindMyFriendPayload locationPayloadForLocation:nil handle:aliceHandle];
        BBAssert([missingLocationPayload[@"coordinates"] isEqual:[NSNull null]], @"missing coordinates must stay null");
        BBAssert([missingLocationPayload[@"handle"] isEqualToString:@"alice@example.com"], @"handle must be stable");
        BBAssert(missingLocationPayload[@"description"] == nil && missingLocationPayload[@"friend"] == nil,
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

        NSDictionary *liveLocationPayload = [FindMyFriendPayload locationPayloadForLocation:liveLocation handle:aliceHandle];
        BBAssert([liveLocationPayload[@"coordinates"] isEqual:@[@47.61, @-122.33]], @"coordinates must be preserved");
        BBAssert([liveLocationPayload[@"title"] isEqualToString:@"Alice"], @"the first string label must become the title");
        BBAssert([liveLocationPayload[@"long_address"] isEqualToString:@"Seattle, WA"], @"address must use an explicit string field");
        BBAssert([liveLocationPayload[@"last_updated"] isEqual:@1234567], @"timestamps must be converted to milliseconds");
        BBAssert([liveLocationPayload[@"status"] isEqualToString:@"live"], @"location type 2 must map to live");

        NSDictionary *locationsByFriendIdentifier = @{
            @"bob@example.com": [FindMyFriendPayload
                locationPayloadForLocation:nil
                                     handle:BBHandleWithIdentifier(@"bob@example.com")],
            @"alice@example.com": liveLocationPayload,
        };
        NSDictionary *completeResponse = [FindMyFriendPayload
            responseForTransactionIdentifier:@"transaction"
                 locationsByFriendIdentifier:locationsByFriendIdentifier
                    pendingFriendIdentifiers:[NSSet set]
                          friendListTimedOut:NO
                   unidentifiedFriendCount:1];
        NSArray *completeLocations = completeResponse[@"locations"];
        BBAssert([completeResponse[@"partial"] isEqual:@NO], @"completed refreshes must not be partial");
        BBAssert([completeLocations[0][@"handle"] isEqualToString:@"alice@example.com"],
                 @"responses must be sorted by stable handle");
        BBAssert([completeResponse[@"skippedFriends"] isEqual:@1], @"skipped friend count must be retained");

        NSSet *pendingFriendIdentifiers = [NSSet setWithObjects:@"bob@example.com", @"alice@example.com", nil];
        NSDictionary *partialResponse = [FindMyFriendPayload
            responseForTransactionIdentifier:@"transaction"
                 locationsByFriendIdentifier:locationsByFriendIdentifier
                    pendingFriendIdentifiers:pendingFriendIdentifiers
                          friendListTimedOut:YES
                   unidentifiedFriendCount:0];
        BBAssert([partialResponse[@"partial"] isEqual:@YES], @"timeouts must be explicit");
        BBAssert([partialResponse[@"friendListTimedOut"] isEqual:@YES], @"friend-list timeout must be explicit");
        BBAssert([partialResponse[@"timedOutHandles"] isEqual:@[@"alice@example.com", @"bob@example.com"]],
                 @"timed-out handles must be deterministic");

        NSLog(@"PASS: FindMyFriendPayloadTests");
    }

    return 0;
}

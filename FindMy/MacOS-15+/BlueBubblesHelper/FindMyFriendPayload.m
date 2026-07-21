#import "FindMyFriendPayload.h"

#import <math.h>

@protocol BBFindMyHandleLike <NSObject>
- (id)identifier;
- (id)comparisonIdentifier;
@end

@protocol BBFindMyLocationLike <NSObject>
- (double)altitude;
- (id)coarseAddressLabel;
- (double)horizontalAccuracy;
- (id)labels;
- (double)latitude;
- (long long)locationType;
- (double)longitude;
- (double)speed;
- (double)timestamp;
- (double)verticalAccuracy;
@end

@implementation FindMyFriendPayload

+ (nullable id)objectValueFromObject:(nullable id)object selector:(SEL)selector {
    if (object == nil || ![object respondsToSelector:selector]) {
        return nil;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [object performSelector:selector];
#pragma clang diagnostic pop
}

+ (nullable NSString *)nonEmptyString:(nullable id)value {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }

    NSString *string = (NSString *)value;
    return string.length > 0 ? string : nil;
}

+ (nullable NSString *)firstLabel:(nullable id)value {
    if (![value isKindOfClass:[NSArray class]]) {
        return nil;
    }

    for (id label in (NSArray *)value) {
        NSString *string = [self nonEmptyString:label];
        if (string != nil) {
            return string;
        }
    }

    return nil;
}

+ (id)finiteNumberOrNull:(double)value {
    return isfinite(value) ? @(value) : [NSNull null];
}

+ (nullable NSString *)identifierForHandle:(nullable id)handle {
    NSString *identifier = [self nonEmptyString:[self objectValueFromObject:handle selector:@selector(identifier)]];
    if (identifier != nil) {
        return identifier;
    }

    return [self nonEmptyString:[self objectValueFromObject:handle selector:@selector(comparisonIdentifier)]];
}

+ (nullable NSDictionary *)locationPayloadForLocation:(nullable id)location handle:(nullable id)handle {
    NSString *identifier = [self identifierForHandle:handle];
    if (identifier == nil) {
        return nil;
    }

    if (location == nil) {
        return @{
            @"handle": identifier,
            @"coordinates": [NSNull null],
            @"long_address": [NSNull null],
            @"short_address": [NSNull null],
            @"subtitle": [NSNull null],
            @"title": [NSNull null],
            @"last_updated": [NSNull null],
            @"is_locating_in_progress": @NO,
            @"status": @"legacy",
            @"location_type": [NSNull null],
            @"horizontal_accuracy": [NSNull null],
            @"vertical_accuracy": [NSNull null],
            @"speed": [NSNull null],
            @"altitude": [NSNull null],
        };
    }

    id<BBFindMyLocationLike> typedLocation = (id<BBFindMyLocationLike>)location;
    BOOL hasCoordinates = [typedLocation respondsToSelector:@selector(latitude)] &&
        [typedLocation respondsToSelector:@selector(longitude)];
    id coordinates = [NSNull null];
    if (hasCoordinates) {
        double latitude = [typedLocation latitude];
        double longitude = [typedLocation longitude];
        if (isfinite(latitude) && isfinite(longitude)) {
            coordinates = @[@(latitude), @(longitude)];
        }
    }

    double timestamp = [typedLocation respondsToSelector:@selector(timestamp)] ? [typedLocation timestamp] : 0;
    BOOL hasLocationType = [typedLocation respondsToSelector:@selector(locationType)];
    long long locationType = hasLocationType ? [typedLocation locationType] : 0;
    NSString *status = locationType == 2 ? @"live" : locationType == 0 ? @"legacy" : @"shallow";
    NSString *address = [self nonEmptyString:[self objectValueFromObject:typedLocation selector:@selector(coarseAddressLabel)]];
    NSString *title = [self firstLabel:[self objectValueFromObject:typedLocation selector:@selector(labels)]];

    return @{
        @"handle": identifier,
        @"coordinates": coordinates,
        @"long_address": address ?: [NSNull null],
        @"short_address": address ?: [NSNull null],
        @"subtitle": address ?: [NSNull null],
        @"title": title ?: [NSNull null],
        @"last_updated": timestamp > 0 && isfinite(timestamp) ? @(llround(timestamp * 1000.0)) : [NSNull null],
        @"is_locating_in_progress": @NO,
        @"status": status,
        @"location_type": hasLocationType ? @(locationType) : [NSNull null],
        @"horizontal_accuracy": [typedLocation respondsToSelector:@selector(horizontalAccuracy)]
            ? [self finiteNumberOrNull:[typedLocation horizontalAccuracy]] : [NSNull null],
        @"vertical_accuracy": [typedLocation respondsToSelector:@selector(verticalAccuracy)]
            ? [self finiteNumberOrNull:[typedLocation verticalAccuracy]] : [NSNull null],
        @"speed": [typedLocation respondsToSelector:@selector(speed)]
            ? [self finiteNumberOrNull:[typedLocation speed]] : [NSNull null],
        @"altitude": [typedLocation respondsToSelector:@selector(altitude)]
            ? [self finiteNumberOrNull:[typedLocation altitude]] : [NSNull null],
    };
}

+ (NSDictionary *)responseForTransaction:(nullable NSString *)transaction
                        locationsByHandle:(NSDictionary<NSString *, NSDictionary *> *)locationsByHandle
                           pendingHandles:(NSSet<NSString *> *)pendingHandles
                       friendListTimedOut:(BOOL)friendListTimedOut
                           skippedFriends:(NSUInteger)skippedFriends {
    NSArray<NSString *> *sortedHandles = [[locationsByHandle allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NSDictionary *> *locations = [[NSMutableArray alloc] initWithCapacity:sortedHandles.count];
    for (NSString *handle in sortedHandles) {
        NSDictionary *location = locationsByHandle[handle];
        if (location != nil) {
            [locations addObject:location];
        }
    }

    NSArray<NSString *> *timedOutHandles = [[pendingHandles allObjects] sortedArrayUsingSelector:@selector(compare:)];
    BOOL partial = friendListTimedOut || timedOutHandles.count > 0;

    return @{
        @"transactionId": transaction ?: [NSNull null],
        @"locations": locations,
        @"partial": @(partial),
        @"friendListTimedOut": @(friendListTimedOut),
        @"timedOutHandles": timedOutHandles,
        @"skippedFriends": @(skippedFriends),
    };
}

@end

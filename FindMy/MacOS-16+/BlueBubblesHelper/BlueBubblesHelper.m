//
//  BlueBubblesHelper.m
//  BlueBubblesHelper
//
//  Created by Tanay Neotia on 5/3/26.
//  Copyright © 2026 BlueBubbleMessaging. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <CoreLocation/CoreLocation.h>
#import <os/log.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "BlueBubblesHelper.h"
#import "FMLHandle.h"
#import "FMLLocation.h"
#import "FMLSession.h"
#import "Logging.h"
#import "NetworkController.h"

@interface BlueBubblesHelper ()
- (FindMyLocateSession *)findMyLocateSession;
- (void)handleFindMyFriendsRefreshWithTransaction:(NSString *)transaction;
- (void)handleFindMyDevicesRefreshWithTransaction:(NSString *)transaction;
- (void)handleFindMyItemsRefreshWithTransaction:(NSString *)transaction;
- (void)handleFindMySearchPartyDebugWithTransaction:(NSString *)transaction;
- (void)handleFindMySearchPartyBeaconProbeStartWithTransaction:(NSString *)transaction;
- (void)handleFindMySearchPartyBeaconProbeStatusWithTransaction:(NSString *)transaction;
- (void)handleFindMySearchPartyLocationProbeStartWithTransaction:(NSString *)transaction;
- (void)handleFindMySearchPartyLocationProbeStartWithTransaction:(NSString *)transaction focusedStep:(NSUInteger)focusedStep;
- (void)handleFindMySearchPartyDelegatedCheckpointWithTransaction:(NSString *)transaction checkpoint:(NSString *)checkpoint;
- (void)handleFindMySearchPartyLocationProbeStatusWithTransaction:(NSString *)transaction;
- (void)handleFindMySearchPartyLocationProbeCompactStatusWithTransaction:(NSString *)transaction;
- (void)appendFindMySearchPartyLocationProbeCompletionForProbeId:(NSString *)probeId selectorName:(NSString *)selectorName result:(id)result;
- (void)appendFindMySearchPartyLocationProbePassiveEventWithSelectorName:(NSString *)selectorName phase:(NSString *)phase context:(id)context result:(id)result source:(id)source;
- (NSDictionary *)serializeFMLFriend:(id)friend handle:(id)handle location:(id)location;
- (NSDictionary *)serializeFMLDevice:(id)device;
- (NSDictionary *)serializeOwnerBeacon:(id)beacon;
- (NSDictionary *)serializeFMLHandle:(id)handle;
- (NSDictionary *)serializeFMLLocation:(id)location handle:(id)handle;
- (NSDictionary *)findMyObjectGraphDiagnostics;
- (NSDictionary *)findMySessionObjectDiagnostics;
- (void)captureFindMyDataSource:(id)dataSource tableView:(id)tableView;
- (void)captureFindMyInterestingObject:(id)object source:(NSString *)source selector:(SEL)selector;
- (void)captureFindMyInterestingSetterObject:(id)object value:(id)value selector:(SEL)selector;
- (void)captureFindMySearchPartyAccessorResult:(id)result source:(id)source selector:(SEL)selector;
- (void)captureFindMySearchPartyLocationInvocationForTarget:(id)target selector:(SEL)selector context:(id)context result:(id)result phase:(NSString *)phase;
- (NSDictionary *)capturedFindMyDataSourceDiagnostics;
- (NSDictionary *)capturedFindMyPassiveDiagnostics;
- (NSDictionary *)compactFindMyRefreshDiagnostics:(NSDictionary *)diagnostics;
- (NSDictionary *)findMySearchPartyDebugSnapshot;
- (NSDictionary *)findMySearchPartyBeaconProbeStatus;
- (NSDictionary *)findMySearchPartyLocationProbeStatus;
- (NSDictionary *)findMySearchPartyLocationProbeCompactStatus;
- (NSDictionary *)searchPartyLastOnlineInfoSummaryForBeacons:(NSArray *)beacons context:(id)context;
- (NSDictionary *)searchPartyFetchContextDiagnosticsForContext:(id)context;
- (NSDictionary *)searchPartyLocationInfoAccessorValuesForObject:(id)object;
- (NSDictionary *)searchPartyLocationInfoIvarValuesForObject:(id)object;
- (NSArray *)searchPartyLocationBearingChildSnapshotsForValue:(id)value;
- (NSDictionary *)searchPartyIdentifierCandidateMapForBeacon:(id)beacon;
- (NSDictionary *)searchPartyResultDeepDiagnosticsForObject:(id)object;
- (NSDictionary *)directFindMyFieldsForObject:(id)object;
- (NSArray *)findMyListRowsForDataSourceTerm:(NSString *)dataSourceTerm type:(NSString *)type;
- (NSDictionary *)activeFindMyListDiagnosticsForDataSourceTerm:(NSString *)dataSourceTerm type:(NSString *)type;
- (BOOL)selectFindMySegmentIndex:(NSInteger)index;
- (void)installFindMySwizzles;
- (NSDictionary *)findMySwizzleDiagnostics;
- (NSDictionary *)compactRuntimeDiagnosticsForClassNames:(NSArray<NSString *> *)classNames matchingTerms:(NSArray<NSString *> *)terms methodLimit:(NSUInteger)methodLimit ivarLimit:(NSUInteger)ivarLimit;
- (NSDictionary *)compactSearchPartyLocationProbeResultForSelector:(NSString *)selectorName result:(id)result;
- (NSDictionary *)compactRelatedSearchPartyObject:(id)object matchingTerms:(NSArray<NSString *> *)terms;
- (BOOL)setSafeIvarObjectValue:(id)value ivarName:(NSString *)ivarName object:(id)object;
- (BOOL)setSafeIvarRangeValue:(NSRange)value ivarName:(NSString *)ivarName object:(id)object;
@end

@implementation BlueBubblesHelper

static os_log_t logger;
static NetworkController *networkController;
static FindMyLocateSession *findMyLocateSession;
static id findMyOwnerSession;
static NSMutableDictionary<NSString *, NSValue *> *findMyOriginalImps;
static NSMutableArray<NSDictionary *> *findMySwizzleEvents;
static NSMutableArray<NSString *> *findMySwizzledSelectors;
static NSMutableDictionary<NSString *, NSDictionary *> *findMyCapturedDataSourceSnapshots;
static NSMutableArray<NSDictionary *> *findMyCapturedObjectSnapshots;
static NSMutableArray<NSDictionary *> *findMySearchPartyAccessorSnapshots;
static NSMutableDictionary<NSString *, id> *findMyCapturedObjectsByIdentifier;
static NSMutableDictionary *findMySearchPartyBeaconProbe;
static NSMutableDictionary *findMySearchPartyLocationProbe;
static NSUInteger findMySearchPartyLocationProbeStepIndex;
static id findMyCapturedSearchPartyLocationFetch;
static id findMyCapturedSearchPartyLocationContext;
static id findMyCapturedDevicesDataSource;
static id findMyCapturedItemsDataSource;
static BOOL findMySwizzlesInstalled;
extern void *BlueBubblesFindMySwiftProbe(void);
extern void *BlueBubblesFindMyStartFMIPManager(void *ownerSession);

static NSString *BBFindMySwizzleKey(Class class, SEL selector) {
    return [NSString stringWithFormat:@"%@:%@", NSStringFromClass(class), NSStringFromSelector(selector)];
}

static void BBFindMyRecordSwizzleEvent(NSDictionary *event) {
    @synchronized ([BlueBubblesHelper class]) {
        if (findMySwizzleEvents == nil) {
            findMySwizzleEvents = [[NSMutableArray alloc] init];
        }
        NSMutableDictionary *mutableEvent = [[NSMutableDictionary alloc] initWithDictionary:event ?: @{}];
        mutableEvent[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
        [findMySwizzleEvents addObject:[mutableEvent copy]];
        if (findMySwizzleEvents.count > 24) {
            [findMySwizzleEvents removeObjectsInRange:NSMakeRange(0, findMySwizzleEvents.count - 24)];
        }
    }
}

struct BBFindMyBlockDescriptor {
    unsigned long int reserved;
    unsigned long int size;
};

struct BBFindMyBlockLiteral {
    void *isa;
    int flags;
    int reserved;
    void *invoke;
    struct BBFindMyBlockDescriptor *descriptor;
};

static NSString *BBFindMyBlockSignature(id block) {
    if (block == nil) {
        return nil;
    }

    const int blockHasCopyDispose = (1 << 25);
    const int blockHasSignature = (1 << 30);
    struct BBFindMyBlockLiteral *literal = (__bridge struct BBFindMyBlockLiteral *)block;
    if ((literal->flags & blockHasSignature) == 0 || literal->descriptor == NULL) {
        return nil;
    }

    void *descriptorCursor = literal->descriptor;
    descriptorCursor = (void *)((uintptr_t)descriptorCursor + (sizeof(unsigned long int) * 2));
    if ((literal->flags & blockHasCopyDispose) != 0) {
        descriptorCursor = (void *)((uintptr_t)descriptorCursor + (sizeof(void *) * 2));
    }

    const char *signature = (*(const char **)descriptorCursor);
    if (signature == NULL) {
        return nil;
    }
    return [NSString stringWithUTF8String:signature];
}

static NSDictionary *BBFindMySetterValueMetadata(id value) {
    if (value == nil) {
        return @{};
    }

    NSString *className = NSStringFromClass([value class]) ?: @"<nil>";
    NSMutableDictionary *metadata = [@{
        @"value_class": className,
        @"value_id": [NSString stringWithFormat:@"%p", value],
    } mutableCopy];

    if ([className containsString:@"Block"]) {
        metadata[@"value_is_block"] = @YES;
        NSString *signature = BBFindMyBlockSignature(value);
        metadata[@"block_signature"] = signature ?: @"<unavailable>";
    }

    return [metadata copy];
}

static NSInteger BBFindMyTableViewNumberOfRows(id self, SEL _cmd, id tableView, NSInteger section) {
    NSInteger rowCount = 0;
    NSString *key = BBFindMySwizzleKey([self class], _cmd);
    NSValue *originalValue = nil;
    @synchronized ([BlueBubblesHelper class]) {
        originalValue = findMyOriginalImps[key];
    }
    if (originalValue != nil) {
        NSInteger (*original)(id, SEL, id, NSInteger) = (NSInteger (*)(id, SEL, id, NSInteger))[originalValue pointerValue];
        rowCount = original(self, _cmd, tableView, section);
    }

    BBFindMyRecordSwizzleEvent(@{
        @"event": @"tableView:numberOfRowsInSection:",
        @"data_source_class": NSStringFromClass([self class]) ?: @"<nil>",
        @"table_class": tableView == nil ? @"<nil>" : NSStringFromClass([tableView class]),
        @"section": @(section),
        @"rows": @(rowCount),
    });
    return rowCount;
}

static id BBFindMyTableViewCellForRow(id self, SEL _cmd, id tableView, id indexPath) {
    id cell = nil;
    NSString *key = BBFindMySwizzleKey([self class], _cmd);
    NSValue *originalValue = nil;
    @synchronized ([BlueBubblesHelper class]) {
        originalValue = findMyOriginalImps[key];
    }
    if (originalValue != nil) {
        id (*original)(id, SEL, id, id) = (id (*)(id, SEL, id, id))[originalValue pointerValue];
        cell = original(self, _cmd, tableView, indexPath);
    }

    NSNumber *section = nil;
    NSNumber *row = nil;
    if ([indexPath respondsToSelector:@selector(section)]) {
        NSInteger (*sectionGetter)(id, SEL) = (NSInteger (*)(id, SEL))objc_msgSend;
        section = @(sectionGetter(indexPath, @selector(section)));
    }
    if ([indexPath respondsToSelector:@selector(row)]) {
        NSInteger (*rowGetter)(id, SEL) = (NSInteger (*)(id, SEL))objc_msgSend;
        row = @(rowGetter(indexPath, @selector(row)));
    }

    BBFindMyRecordSwizzleEvent(@{
        @"event": @"tableView:cellForRowAtIndexPath:",
        @"data_source_class": NSStringFromClass([self class]) ?: @"<nil>",
        @"table_class": tableView == nil ? @"<nil>" : NSStringFromClass([tableView class]),
        @"cell_class": cell == nil ? @"<nil>" : NSStringFromClass([cell class]),
        @"section": section ?: [NSNull null],
        @"row": row ?: [NSNull null],
    });
    return cell;
}

static void BBFindMyTableViewSetDataSource(id self, SEL _cmd, id dataSource) {
    NSString *key = BBFindMySwizzleKey([self class], _cmd);
    NSValue *originalValue = nil;
    @synchronized ([BlueBubblesHelper class]) {
        originalValue = findMyOriginalImps[key];
    }
    if (originalValue != nil) {
        void (*original)(id, SEL, id) = (void (*)(id, SEL, id))[originalValue pointerValue];
        original(self, _cmd, dataSource);
    }

    BBFindMyRecordSwizzleEvent(@{
        @"event": @"setDataSource:",
        @"table_class": NSStringFromClass([self class]) ?: @"<nil>",
        @"data_source_class": dataSource == nil ? @"<nil>" : NSStringFromClass([dataSource class]),
    });

    if (dataSource != nil) {
        [[BlueBubblesHelper sharedInstance] captureFindMyDataSource:dataSource tableView:self];
    }
}

static id BBFindMyInterestingInit(id self, SEL _cmd) {
    id initialized = self;
    NSString *key = BBFindMySwizzleKey([self class], _cmd);
    NSValue *originalValue = nil;
    @synchronized ([BlueBubblesHelper class]) {
        originalValue = findMyOriginalImps[key];
    }
    if (originalValue != nil) {
        id (*original)(id, SEL) = (id (*)(id, SEL))[originalValue pointerValue];
        initialized = original(self, _cmd);
    }

    if (initialized != nil) {
        [[BlueBubblesHelper sharedInstance] captureFindMyInterestingObject:initialized source:@"init" selector:_cmd];
    }
    return initialized;
}

static void BBFindMyInterestingObjectSetter(id self, SEL _cmd, id value) {
    NSString *key = BBFindMySwizzleKey([self class], _cmd);
    NSValue *originalValue = nil;
    @synchronized ([BlueBubblesHelper class]) {
        originalValue = findMyOriginalImps[key];
    }
    if (originalValue != nil) {
        void (*original)(id, SEL, id) = (void (*)(id, SEL, id))[originalValue pointerValue];
        original(self, _cmd, value);
    }

    [[BlueBubblesHelper sharedInstance] captureFindMyInterestingSetterObject:self value:value selector:_cmd];
}

static void BBFindMyLocationUpdateBlockSetter(id self, SEL _cmd, id value) {
    id valueForOriginal = value;
    NSString *signature = BBFindMyBlockSignature(value);
    BOOL isLocationResultBlock = signature != nil && [signature rangeOfString:@"SPLocationFetchResult"].location != NSNotFound;
    BOOL isDeviceEventResultBlock = signature != nil && [signature rangeOfString:@"SPDeviceEventFetchResult"].location != NSNotFound;
    if (value != nil && (isLocationResultBlock || isDeviceEventResultBlock)) {
        void (^originalBlock)(id) = [value copy];
        valueForOriginal = [^(id result) {
            [[BlueBubblesHelper sharedInstance] captureFindMySearchPartyLocationInvocationForTarget:self
                                                                                           selector:_cmd
                                                                                            context:nil
                                                                                             result:result
                                                                                              phase:@"locationUpdateBlock"];
            [[BlueBubblesHelper sharedInstance] captureFindMySearchPartyAccessorResult:result source:self selector:_cmd];
            if ([result respondsToSelector:NSSelectorFromString(@"locationsByBeaconIdentifier")]) {
                id locations = [[BlueBubblesHelper sharedInstance] safeObjectValueFromObject:result selectorName:@"locationsByBeaconIdentifier"];
                [[BlueBubblesHelper sharedInstance] captureFindMySearchPartyAccessorResult:locations source:result selector:NSSelectorFromString(@"locationsByBeaconIdentifier")];
            }
            if ([result respondsToSelector:NSSelectorFromString(@"beaconEventByBeaconIdentifier")]) {
                id events = [[BlueBubblesHelper sharedInstance] safeObjectValueFromObject:result selectorName:@"beaconEventByBeaconIdentifier"];
                [[BlueBubblesHelper sharedInstance] captureFindMySearchPartyAccessorResult:events source:result selector:NSSelectorFromString(@"beaconEventByBeaconIdentifier")];
            }
            if (originalBlock != nil) {
                originalBlock(result);
            }
        } copy];
    }

    NSString *key = BBFindMySwizzleKey([self class], _cmd);
    NSValue *originalValue = nil;
    @synchronized ([BlueBubblesHelper class]) {
        originalValue = findMyOriginalImps[key];
    }
    if (originalValue != nil) {
        void (*original)(id, SEL, id) = (void (*)(id, SEL, id))[originalValue pointerValue];
        original(self, _cmd, valueForOriginal);
    }

    [[BlueBubblesHelper sharedInstance] captureFindMyInterestingSetterObject:self value:value selector:_cmd];
}

static void BBFindMyLocationFetchContextCompletion(id self, SEL _cmd, id context, id completion) {
    [[BlueBubblesHelper sharedInstance] captureFindMySearchPartyLocationInvocationForTarget:self
                                                                                   selector:_cmd
                                                                                    context:context
                                                                                     result:nil
                                                                                      phase:@"before"];

    id completionForOriginal = completion;
    NSString *signature = BBFindMyBlockSignature(completion);
    if (completion != nil && (signature == nil || [signature rangeOfString:@"SPLocationFetchResult"].location != NSNotFound || [signature rangeOfString:@"@"].location != NSNotFound)) {
        void (^originalCompletion)(id) = [completion copy];
        completionForOriginal = [^(id result) {
            [[BlueBubblesHelper sharedInstance] captureFindMySearchPartyLocationInvocationForTarget:self
                                                                                           selector:_cmd
                                                                                            context:context
                                                                                             result:result
                                                                                              phase:@"completion"];
            if ([result respondsToSelector:NSSelectorFromString(@"locationsByBeaconIdentifier")]) {
                id locations = [[BlueBubblesHelper sharedInstance] safeObjectValueFromObject:result selectorName:@"locationsByBeaconIdentifier"];
                [[BlueBubblesHelper sharedInstance] captureFindMySearchPartyAccessorResult:locations
                                                                                    source:result
                                                                                  selector:NSSelectorFromString(@"locationsByBeaconIdentifier")];
            }
            if (originalCompletion != nil) {
                originalCompletion(result);
            }
        } copy];
    }

    NSString *key = BBFindMySwizzleKey([self class], _cmd);
    NSValue *originalValue = nil;
    @synchronized ([BlueBubblesHelper class]) {
        originalValue = findMyOriginalImps[key];
    }
    if (originalValue != nil) {
        void (*original)(id, SEL, id, id) = (void (*)(id, SEL, id, id))[originalValue pointerValue];
        original(self, _cmd, context, completionForOriginal);
    }
}

static void BBFindMySearchPartyLocationObjectArgument(id self, SEL _cmd, id value) {
    NSString *selectorName = NSStringFromSelector(_cmd);
    if ([selectorName isEqualToString:@"setLastContext:"]) {
        [[BlueBubblesHelper sharedInstance] captureFindMySearchPartyLocationInvocationForTarget:self
                                                                                       selector:_cmd
                                                                                        context:value
                                                                                         result:nil
                                                                                          phase:@"setter"];
    } else if ([selectorName isEqualToString:@"receivedUpdatedLocation:"]) {
        [[BlueBubblesHelper sharedInstance] captureFindMySearchPartyLocationInvocationForTarget:self
                                                                                       selector:_cmd
                                                                                        context:nil
                                                                                         result:value
                                                                                          phase:@"receivedUpdatedLocation"];
        [[BlueBubblesHelper sharedInstance] captureFindMySearchPartyAccessorResult:value source:self selector:_cmd];
        if ([value respondsToSelector:NSSelectorFromString(@"locationsByBeaconIdentifier")]) {
            id locations = [[BlueBubblesHelper sharedInstance] safeObjectValueFromObject:value selectorName:@"locationsByBeaconIdentifier"];
            [[BlueBubblesHelper sharedInstance] captureFindMySearchPartyAccessorResult:locations
                                                                                source:value
                                                                              selector:NSSelectorFromString(@"locationsByBeaconIdentifier")];
        }
    } else if ([selectorName isEqualToString:@"receivedUpdatedDeviceEvents:"]) {
        [[BlueBubblesHelper sharedInstance] captureFindMySearchPartyLocationInvocationForTarget:self
                                                                                       selector:_cmd
                                                                                        context:nil
                                                                                         result:value
                                                                                          phase:@"receivedUpdatedDeviceEvents"];
        [[BlueBubblesHelper sharedInstance] captureFindMySearchPartyAccessorResult:value source:self selector:_cmd];
        if ([value respondsToSelector:NSSelectorFromString(@"beaconEventByBeaconIdentifier")]) {
            id events = [[BlueBubblesHelper sharedInstance] safeObjectValueFromObject:value selectorName:@"beaconEventByBeaconIdentifier"];
            [[BlueBubblesHelper sharedInstance] captureFindMySearchPartyAccessorResult:events
                                                                                source:value
                                                                              selector:NSSelectorFromString(@"beaconEventByBeaconIdentifier")];
        }
    } else {
        [[BlueBubblesHelper sharedInstance] captureFindMySearchPartyAccessorResult:value source:self selector:_cmd];
        if ([value respondsToSelector:NSSelectorFromString(@"locationsByBeaconIdentifier")]) {
            id locations = [[BlueBubblesHelper sharedInstance] safeObjectValueFromObject:value selectorName:@"locationsByBeaconIdentifier"];
            [[BlueBubblesHelper sharedInstance] captureFindMySearchPartyAccessorResult:locations
                                                                                source:value
                                                                              selector:NSSelectorFromString(@"locationsByBeaconIdentifier")];
        }
        if ([value respondsToSelector:NSSelectorFromString(@"beaconEventByBeaconIdentifier")]) {
            id events = [[BlueBubblesHelper sharedInstance] safeObjectValueFromObject:value selectorName:@"beaconEventByBeaconIdentifier"];
            [[BlueBubblesHelper sharedInstance] captureFindMySearchPartyAccessorResult:events
                                                                                source:value
                                                                              selector:NSSelectorFromString(@"beaconEventByBeaconIdentifier")];
        }
    }

    NSString *key = BBFindMySwizzleKey([self class], _cmd);
    NSValue *originalValue = nil;
    @synchronized ([BlueBubblesHelper class]) {
        originalValue = findMyOriginalImps[key];
    }
    if (originalValue != nil) {
        void (*original)(id, SEL, id) = (void (*)(id, SEL, id))[originalValue pointerValue];
        original(self, _cmd, value);
    }
}

static id BBFindMySearchPartyResultAccessor(id self, SEL _cmd) {
    id result = nil;
    NSString *key = BBFindMySwizzleKey([self class], _cmd);
    NSValue *originalValue = nil;
    @synchronized ([BlueBubblesHelper class]) {
        originalValue = findMyOriginalImps[key];
    }
    if (originalValue != nil) {
        id (*original)(id, SEL) = (id (*)(id, SEL))[originalValue pointerValue];
        result = original(self, _cmd);
    }

    [[BlueBubblesHelper sharedInstance] captureFindMySearchPartyAccessorResult:result source:self selector:_cmd];
    return result;
}

static void BBFindMySearchPartyResultSetter(id self, SEL _cmd, id value) {
    [[BlueBubblesHelper sharedInstance] captureFindMySearchPartyAccessorResult:value source:self selector:_cmd];

    NSString *key = BBFindMySwizzleKey([self class], _cmd);
    NSValue *originalValue = nil;
    @synchronized ([BlueBubblesHelper class]) {
        originalValue = findMyOriginalImps[key];
    }
    if (originalValue != nil) {
        void (*original)(id, SEL, id) = (void (*)(id, SEL, id))[originalValue pointerValue];
        original(self, _cmd, value);
    }
}

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

    [[BlueBubblesHelper sharedInstance] installFindMySwizzles];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        os_log(logger, "Injected into Find My. Connecting to BlueBubbles Server...");
        [[BlueBubblesHelper sharedInstance] installFindMySwizzles];
        networkController = [NetworkController sharedInstance];
        [networkController connect];
    });
}

- (void)handleServerEvent:(NSString *)event data:(NSDictionary *)data transactionId:(NSString *)transaction {
    if ([event isEqualToString:@"refresh-findmy-friends"]) {
        [self handleFindMyFriendsRefreshWithTransaction:transaction];
        return;
    }

    if ([event isEqualToString:@"refresh-findmy-devices"]) {
        [self handleFindMyDevicesRefreshWithTransaction:transaction];
        return;
    }

    if ([event isEqualToString:@"refresh-findmy-items"]) {
        [self handleFindMyItemsRefreshWithTransaction:transaction];
        return;
    }

    if ([event isEqualToString:@"debug-findmy-searchparty"]) {
        [self handleFindMySearchPartyDebugWithTransaction:transaction];
        return;
    }

    if ([event isEqualToString:@"debug-findmy-searchparty-beacons-start"]) {
        [self handleFindMySearchPartyBeaconProbeStartWithTransaction:transaction];
        return;
    }

    if ([event isEqualToString:@"debug-findmy-searchparty-beacons"]) {
        [self handleFindMySearchPartyBeaconProbeStatusWithTransaction:transaction];
        return;
    }

    if ([event isEqualToString:@"debug-findmy-searchparty-locations-start"]) {
        [self handleFindMySearchPartyLocationProbeStartWithTransaction:transaction];
        return;
    }

    if ([event isEqualToString:@"debug-findmy-searchparty-locations-latest-single"]) {
        [self handleFindMySearchPartyLocationProbeStartWithTransaction:transaction focusedStep:1];
        return;
    }

    if ([event isEqualToString:@"debug-findmy-searchparty-locations-source-subset"]) {
        [self handleFindMySearchPartyLocationProbeStartWithTransaction:transaction focusedStep:4];
        return;
    }

    if ([event isEqualToString:@"debug-findmy-searchparty-locations-proxy-context"]) {
        [self handleFindMySearchPartyLocationProbeStartWithTransaction:transaction focusedStep:3];
        return;
    }

    if ([event isEqualToString:@"debug-findmy-searchparty-locations-live-request"]) {
        [self handleFindMySearchPartyLocationProbeStartWithTransaction:transaction focusedStep:5];
        return;
    }

    if ([event isEqualToString:@"debug-findmy-searchparty-locations-resolve-identifiers"]) {
        [self handleFindMySearchPartyLocationProbeStartWithTransaction:transaction focusedStep:6];
        return;
    }

    if ([event isEqualToString:@"debug-findmy-searchparty-locations-resolve-context-uuid"]) {
        [self handleFindMySearchPartyLocationProbeStartWithTransaction:transaction focusedStep:7];
        return;
    }

    if ([event isEqualToString:@"debug-findmy-searchparty-locations-resolve-stable-identifier"]) {
        [self handleFindMySearchPartyLocationProbeStartWithTransaction:transaction focusedStep:8];
        return;
    }

    if ([event isEqualToString:@"debug-findmy-searchparty-locations-resolved-beacon-location"]) {
        [self handleFindMySearchPartyLocationProbeStartWithTransaction:transaction focusedStep:9];
        return;
    }

    if ([event isEqualToString:@"debug-findmy-searchparty-locations-context-single-identifier"]) {
        [self handleFindMySearchPartyLocationProbeStartWithTransaction:transaction focusedStep:10];
        return;
    }

    if ([event isEqualToString:@"debug-findmy-searchparty-locations-last-online-identifiers"]) {
        [self handleFindMySearchPartyLocationProbeStartWithTransaction:transaction focusedStep:16];
        return;
    }

    if ([event isEqualToString:@"debug-findmy-searchparty-locations-callback-watch"]) {
        [self handleFindMySearchPartyLocationProbeStartWithTransaction:transaction focusedStep:11];
        return;
    }

    if ([event isEqualToString:@"debug-findmy-searchparty-locations-callback-watch-full-context"]) {
        [self handleFindMySearchPartyLocationProbeStartWithTransaction:transaction focusedStep:12];
        return;
    }

    if ([event isEqualToString:@"debug-findmy-searchparty-locations-device-event-watch"]) {
        [self handleFindMySearchPartyLocationProbeStartWithTransaction:transaction focusedStep:13];
        return;
    }

    if ([event isEqualToString:@"debug-findmy-searchparty-locations-delegated-context"]) {
        [self handleFindMySearchPartyLocationProbeStartWithTransaction:transaction focusedStep:14];
        return;
    }

    if ([event isEqualToString:@"debug-findmy-searchparty-locations-delegated-watch"]) {
        [self handleFindMySearchPartyLocationProbeStartWithTransaction:transaction focusedStep:15];
        return;
    }

    NSString *delegatedCheckpointPrefix = @"debug-findmy-searchparty-locations-delegated-checkpoint-";
    if ([event hasPrefix:delegatedCheckpointPrefix]) {
        NSString *checkpoint = [event substringFromIndex:delegatedCheckpointPrefix.length];
        [self handleFindMySearchPartyDelegatedCheckpointWithTransaction:transaction checkpoint:checkpoint];
        return;
    }

    if ([event isEqualToString:@"debug-findmy-searchparty-locations"]) {
        [self handleFindMySearchPartyLocationProbeStatusWithTransaction:transaction];
        return;
    }

    if ([event isEqualToString:@"debug-findmy-searchparty-locations-compact"]) {
        [self handleFindMySearchPartyLocationProbeCompactStatusWithTransaction:transaction];
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

- (id)safeObjectValueFromObject:(id)object selectorName:(NSString *)selectorName {
    if (object == nil || selectorName.length == 0) {
        return nil;
    }

    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) {
        return nil;
    }

    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (signature == nil || signature.numberOfArguments != 2) {
        return nil;
    }

    const char *returnType = signature.methodReturnType;
    if (returnType == NULL || returnType[0] != '@') {
        return nil;
    }

    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        return [object performSelector:selector];
#pragma clang diagnostic pop
    } @catch (NSException *exception) {
        return nil;
    }
}

- (id)safeJSONValueFromObject:(id)object zeroArgumentSelectorName:(NSString *)selectorName {
    if (object == nil || selectorName.length == 0) {
        return nil;
    }

    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) {
        return nil;
    }

    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (signature == nil || signature.numberOfArguments != 2) {
        return nil;
    }

    const char *returnType = signature.methodReturnType;
    if (returnType == NULL || strcmp(returnType, @encode(void)) == 0) {
        return nil;
    }

    @try {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        [invocation setTarget:object];
        [invocation setSelector:selector];
        [invocation invoke];

        if (returnType[0] == '@') {
            __unsafe_unretained id value = nil;
            [invocation getReturnValue:&value];
            if (value == nil || value == [NSNull null]) {
                return nil;
            }
            NSDictionary *location = [self serializeLocationObject:value];
            if (location != (NSDictionary *)[NSNull null]) {
                return @{@"location": location, @"class": [self classNameForObject:value]};
            }
            NSString *stringValue = [self stringValueForFindMyValue:value];
            if (stringValue.length > 0) {
                return stringValue;
            }
            return [self summaryForValue:value];
        }

        if (strcmp(returnType, @encode(BOOL)) == 0 || strcmp(returnType, @encode(bool)) == 0) {
            BOOL value = NO;
            [invocation getReturnValue:&value];
            return @(value);
        }
        if (strcmp(returnType, @encode(double)) == 0) {
            double value = 0;
            [invocation getReturnValue:&value];
            return @(value);
        }
        if (strcmp(returnType, @encode(float)) == 0 || strcmp(returnType, @encode(CGFloat)) == 0) {
            CGFloat value = 0;
            [invocation getReturnValue:&value];
            return @(value);
        }
        if (strcmp(returnType, @encode(NSInteger)) == 0) {
            NSInteger value = 0;
            [invocation getReturnValue:&value];
            return @(value);
        }
        if (strcmp(returnType, @encode(NSUInteger)) == 0) {
            NSUInteger value = 0;
            [invocation getReturnValue:&value];
            return @(value);
        }
        if (strcmp(returnType, @encode(int)) == 0) {
            int value = 0;
            [invocation getReturnValue:&value];
            return @(value);
        }
        if (strcmp(returnType, @encode(long long)) == 0) {
            long long value = 0;
            [invocation getReturnValue:&value];
            return @(value);
        }
        if (strcmp(returnType, @encode(unsigned long long)) == 0) {
            unsigned long long value = 0;
            [invocation getReturnValue:&value];
            return @(value);
        }
        if (strcmp(returnType, @encode(CLLocationCoordinate2D)) == 0) {
            CLLocationCoordinate2D coordinate;
            [invocation getReturnValue:&coordinate];
            if (CLLocationCoordinate2DIsValid(coordinate)) {
                return @{
                    @"latitude": @(coordinate.latitude),
                    @"longitude": @(coordinate.longitude),
                };
            }
        }
    } @catch (NSException *exception) {
        return nil;
    }

    return nil;
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

- (id)findMyOwnerSession {
    if (findMyOwnerSession != nil) {
        return findMyOwnerSession;
    }

    Class ownerSessionClass = NSClassFromString(@"SPOwnerSession");
    if (ownerSessionClass == nil) {
        NSError *loadError = nil;
        NSBundle *ownerBundle = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/SPOwner.framework"];
        if (![ownerBundle loadAndReturnError:&loadError]) {
            DLog("BLUEBUBBLESHELPER: Failed to load SPOwner.framework: %@", loadError);
        }
        ownerSessionClass = NSClassFromString(@"SPOwnerSession");
    }

    if (ownerSessionClass == nil) {
        DLog("BLUEBUBBLESHELPER: SPOwnerSession class is unavailable");
        return nil;
    }

    findMyOwnerSession = [[ownerSessionClass alloc] init];
    if ([findMyOwnerSession respondsToSelector:@selector(startRefreshing)]) {
        [self objectValueFromObject:findMyOwnerSession selector:@selector(startRefreshing)];
    }

    return findMyOwnerSession;
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

- (NSArray *)selectorNamesForClass:(Class)class includeClassMethods:(BOOL)includeClassMethods {
    if (class == nil) {
        return @[];
    }

    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(includeClassMethods ? object_getClass(class) : class, &methodCount);
    NSMutableArray *selectorNames = [[NSMutableArray alloc] init];
    for (unsigned int i = 0; i < methodCount; i++) {
        SEL selector = method_getName(methods[i]);
        if (selector != nil) {
            [selectorNames addObject:NSStringFromSelector(selector)];
        }
    }
    free(methods);
    return [selectorNames sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (NSDictionary *)runtimeDiagnosticsForClassNames:(NSArray<NSString *> *)classNames {
    NSMutableDictionary *diagnostics = [[NSMutableDictionary alloc] init];
    for (NSString *className in classNames) {
        Class class = NSClassFromString(className);
        if (class == nil) {
            diagnostics[className] = @{@"available": @NO};
            continue;
        }

        NSMutableArray *ivars = [[NSMutableArray alloc] init];
        unsigned int ivarCount = 0;
        Ivar *ivarList = class_copyIvarList(class, &ivarCount);
        for (unsigned int i = 0; i < ivarCount; i++) {
            Ivar ivar = ivarList[i];
            const char *name = ivar_getName(ivar);
            const char *type = ivar_getTypeEncoding(ivar);
            [ivars addObject:@{
                @"name": name == NULL ? @"<nil>" : [NSString stringWithUTF8String:name],
                @"type": type == NULL ? @"<nil>" : [NSString stringWithUTF8String:type],
            }];
        }
        free(ivarList);

        diagnostics[className] = @{
            @"available": @YES,
            @"class_methods": [self selectorNamesForClass:class includeClassMethods:YES],
            @"instance_methods": [self selectorNamesForClass:class includeClassMethods:NO],
            @"ivars": ivars,
        };
    }
    return [diagnostics copy];
}

- (NSArray *)compactSelectorDiagnosticsForClass:(Class)class includeClassMethods:(BOOL)includeClassMethods matchingTerms:(NSArray<NSString *> *)terms limit:(NSUInteger)limit {
    if (class == nil || limit == 0) {
        return @[];
    }

    NSMutableArray *matches = [[NSMutableArray alloc] init];
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(includeClassMethods ? object_getClass(class) : class, &methodCount);
    for (unsigned int i = 0; i < methodCount && matches.count < limit; i++) {
        SEL selector = method_getName(methods[i]);
        NSString *selectorName = selector == nil ? nil : NSStringFromSelector(selector);
        if (selectorName.length == 0) {
            continue;
        }

        BOOL matched = terms.count == 0;
        for (NSString *term in terms) {
            if ([selectorName rangeOfString:term options:NSCaseInsensitiveSearch].location != NSNotFound) {
                matched = YES;
                break;
            }
        }
        if (!matched) {
            continue;
        }

        [matches addObject:@{
            @"selector": selectorName,
            @"type_encoding": [NSString stringWithUTF8String:method_getTypeEncoding(methods[i]) ?: ""] ?: @"",
        }];
    }
    free(methods);
    return [matches copy];
}

- (NSDictionary *)compactRuntimeDiagnosticsForClassNames:(NSArray<NSString *> *)classNames matchingTerms:(NSArray<NSString *> *)terms methodLimit:(NSUInteger)methodLimit ivarLimit:(NSUInteger)ivarLimit {
    NSMutableDictionary *diagnostics = [[NSMutableDictionary alloc] init];
    for (NSString *className in classNames) {
        Class class = NSClassFromString(className);
        if (class == nil) {
            diagnostics[className] = @{@"available": @NO};
            continue;
        }

        NSMutableArray *ivars = [[NSMutableArray alloc] init];
        unsigned int ivarCount = 0;
        Ivar *ivarList = class_copyIvarList(class, &ivarCount);
        for (unsigned int i = 0; i < ivarCount && ivars.count < ivarLimit; i++) {
            Ivar ivar = ivarList[i];
            const char *name = ivar_getName(ivar);
            const char *type = ivar_getTypeEncoding(ivar);
            [ivars addObject:@{
                @"name": name == NULL ? @"<nil>" : [NSString stringWithUTF8String:name],
                @"type": type == NULL ? @"<nil>" : [NSString stringWithUTF8String:type],
            }];
        }
        free(ivarList);

        diagnostics[className] = @{
            @"available": @YES,
            @"matched_class_methods": [self compactSelectorDiagnosticsForClass:class includeClassMethods:YES matchingTerms:terms limit:methodLimit],
            @"matched_instance_methods": [self compactSelectorDiagnosticsForClass:class includeClassMethods:NO matchingTerms:terms limit:methodLimit],
            @"ivar_count": @(ivarCount),
            @"ivars": ivars,
        };
    }
    return [diagnostics copy];
}

- (BOOL)swizzleInstanceMethodForClass:(Class)class selector:(SEL)selector replacement:(IMP)replacement {
    if (class == nil || selector == nil || replacement == nil) {
        return NO;
    }

    Method method = class_getInstanceMethod(class, selector);
    if (method == nil) {
        return NO;
    }

    NSString *key = BBFindMySwizzleKey(class, selector);
    @synchronized ([BlueBubblesHelper class]) {
        if (findMyOriginalImps[key] != nil) {
            return YES;
        }

        if (findMyOriginalImps == nil) {
            findMyOriginalImps = [[NSMutableDictionary alloc] init];
        }
        if (findMySwizzledSelectors == nil) {
            findMySwizzledSelectors = [[NSMutableArray alloc] init];
        }

        IMP original = method_getImplementation(method);
        findMyOriginalImps[key] = [NSValue valueWithPointer:original];
        method_setImplementation(method, replacement);
        [findMySwizzledSelectors addObject:key];
    }
    return YES;
}

- (BOOL)installSetDataSourceOverrideForClass:(Class)class {
    if (class == nil) {
        return NO;
    }

    SEL selector = @selector(setDataSource:);
    Method method = class_getInstanceMethod(class, selector);
    if (method == nil) {
        return NO;
    }

    NSString *key = BBFindMySwizzleKey(class, selector);
    @synchronized ([BlueBubblesHelper class]) {
        if (findMyOriginalImps[key] != nil) {
            return YES;
        }

        if (findMyOriginalImps == nil) {
            findMyOriginalImps = [[NSMutableDictionary alloc] init];
        }
        if (findMySwizzledSelectors == nil) {
            findMySwizzledSelectors = [[NSMutableArray alloc] init];
        }

        IMP original = method_getImplementation(method);
        const char *types = method_getTypeEncoding(method);
        if (!class_addMethod(class, selector, (IMP)BBFindMyTableViewSetDataSource, types)) {
            return NO;
        }
        findMyOriginalImps[key] = [NSValue valueWithPointer:original];
        [findMySwizzledSelectors addObject:key];
    }
    return YES;
}

- (void)installFindMySwizzles {
    @synchronized ([BlueBubblesHelper class]) {
        findMySwizzlesInstalled = YES;
        if (findMyOriginalImps == nil) {
            findMyOriginalImps = [[NSMutableDictionary alloc] init];
        }
        if (findMySwizzleEvents == nil) {
            findMySwizzleEvents = [[NSMutableArray alloc] init];
        }
        if (findMySwizzledSelectors == nil) {
            findMySwizzledSelectors = [[NSMutableArray alloc] init];
        }
    }

    NSArray *dataSourceClassNames = @[
        @"FindMy.FMPeopleListDataSource",
        @"FMPeopleListDataSource",
        @"FindMy.FMDevicesListDataSource",
        @"FMDevicesListDataSource",
        @"_TtC6FindMy23FMDevicesListDataSource",
        @"FindMy.FMItemsListDataSource",
        @"FMItemsListDataSource",
        @"_TtC6FindMy21FMItemsListDataSource",
    ];

    for (NSString *className in dataSourceClassNames) {
        Class class = NSClassFromString(className);
        if (class == nil) {
            continue;
        }
        [self swizzleInstanceMethodForClass:class
                                   selector:@selector(tableView:numberOfRowsInSection:)
                                replacement:(IMP)BBFindMyTableViewNumberOfRows];
        [self swizzleInstanceMethodForClass:class
                                   selector:@selector(tableView:cellForRowAtIndexPath:)
                                replacement:(IMP)BBFindMyTableViewCellForRow];
    }

    for (NSString *className in @[@"FindMy.FMTableView", @"FMTableView", @"_TtC6FindMy11FMTableView"]) {
        [self installSetDataSourceOverrideForClass:NSClassFromString(className)];
    }

    NSArray *interestingClassNames = @[
        @"SPOwnerSession",
        @"FindMy.FMDevicesProvider",
        @"_TtC6FindMy17FMDevicesProvider",
        @"FindMy.FMDevicesActionController",
        @"FindMy.FMItemsListDataSource",
        @"_TtC6FindMy21FMItemsListDataSource",
        @"FindMyUICore.ItemsProvider",
        @"FindMyUICore.ItemsLocationsProvider",
        @"FindMyUICore.Repository",
        @"FindMyUICore.SessionLive",
        @"SPOwnerSessionLocationFetch",
    ];
    for (NSString *className in interestingClassNames) {
        [self swizzleInstanceMethodForClass:NSClassFromString(className)
                                   selector:@selector(init)
                                replacement:(IMP)BBFindMyInterestingInit];
    }

    Class ownerSessionClass = NSClassFromString(@"SPOwnerSession");
    for (NSString *selectorName in @[
        @"setBeaconAddedBlock:",
        @"setBeaconRemovedBlock:",
        @"setBeaconsChangedBlock:",
        @"setClientObservedBeacons:",
        @"setDelegatedLocationUpdateBlock:",
        @"setDeviceEventUpdateBlock:",
        @"setLatestLocationsUpdatedBlock:",
        @"setLocationCache:",
        @"setLocationSources:",
        @"setLocationUpdateBlock:",
        @"setMaintainedBeaconsChangedBlock:",
        @"setMaintainedUnknownBeaconsChangedBlock:",
        @"setOwnerSessionStateUpdatedBlock:",
        @"setTagSeparationBeaconsChangedBlock:",
    ]) {
        IMP replacement = ([selectorName isEqualToString:@"setLocationUpdateBlock:"] ||
                           [selectorName isEqualToString:@"setLatestLocationsUpdatedBlock:"] ||
                           [selectorName isEqualToString:@"setDelegatedLocationUpdateBlock:"] ||
                           [selectorName isEqualToString:@"setDeviceEventUpdateBlock:"])
            ? (IMP)BBFindMyLocationUpdateBlockSetter
            : (IMP)BBFindMyInterestingObjectSetter;
        [self swizzleInstanceMethodForClass:ownerSessionClass
                                   selector:NSSelectorFromString(selectorName)
                                replacement:replacement];
    }
    for (NSString *selectorName in @[
        @"subscribeAndFetchLocationForContext:completion:",
        @"locationForContext:completion:",
    ]) {
        [self swizzleInstanceMethodForClass:ownerSessionClass
                                   selector:NSSelectorFromString(selectorName)
                                replacement:(IMP)BBFindMyLocationFetchContextCompletion];
    }

    Class ownerSessionLocationFetchClass = NSClassFromString(@"SPOwnerSessionLocationFetch");
    for (NSString *selectorName in @[
        @"setLastContext:",
        @"setLocationUpdates:",
        @"setLocationUpdateBlock:",
        @"setDeviceEventUpdates:",
        @"setDeviceEventUpdateBlock:",
        @"setLocationFetchSessionInvalidationBlock:",
        @"setProxy:",
        @"setSession:",
    ]) {
        IMP replacement = (IMP)BBFindMyInterestingObjectSetter;
        if ([selectorName isEqualToString:@"setLocationUpdates:"] ||
            [selectorName isEqualToString:@"setLocationUpdateBlock:"] ||
            [selectorName isEqualToString:@"setDeviceEventUpdates:"] ||
            [selectorName isEqualToString:@"setDeviceEventUpdateBlock:"]) {
            replacement = (IMP)BBFindMyLocationUpdateBlockSetter;
        } else if ([selectorName isEqualToString:@"setLastContext:"]) {
            replacement = (IMP)BBFindMySearchPartyLocationObjectArgument;
        }
        [self swizzleInstanceMethodForClass:ownerSessionLocationFetchClass
                                   selector:NSSelectorFromString(selectorName)
                                replacement:replacement];
    }
    [self swizzleInstanceMethodForClass:ownerSessionLocationFetchClass
                               selector:NSSelectorFromString(@"receivedUpdatedLocation:")
                            replacement:(IMP)BBFindMySearchPartyLocationObjectArgument];
    [self swizzleInstanceMethodForClass:ownerSessionLocationFetchClass
                               selector:NSSelectorFromString(@"receivedUpdatedDeviceEvents:")
                            replacement:(IMP)BBFindMySearchPartyLocationObjectArgument];
    for (NSString *selectorName in @[
        @"subscribeAndFetchLocationForContext:completion:",
        @"locationForContext:completion:",
    ]) {
        [self swizzleInstanceMethodForClass:ownerSessionLocationFetchClass
                                   selector:NSSelectorFromString(selectorName)
                                replacement:(IMP)BBFindMyLocationFetchContextCompletion];
    }

    NSDictionary<NSString *, NSArray<NSString *> *> *searchPartyResultAccessors = @{
        @"SPLocationFetchResult": @[@"locationsByBeaconIdentifier"],
        @"SPDeviceEventFetchResult": @[@"beaconEventByBeaconIdentifier"],
    };
    for (NSString *className in searchPartyResultAccessors) {
        for (NSString *selectorName in searchPartyResultAccessors[className]) {
            [self swizzleInstanceMethodForClass:NSClassFromString(className)
                                       selector:NSSelectorFromString(selectorName)
                                    replacement:(IMP)BBFindMySearchPartyResultAccessor];
        }
    }
    NSDictionary<NSString *, NSArray<NSString *> *> *searchPartyResultSetters = @{
        @"SPLocationFetchResult": @[@"setLocationsByBeaconIdentifier:"],
        @"SPDeviceEventFetchResult": @[@"setBeaconEventByBeaconIdentifier:"],
    };
    for (NSString *className in searchPartyResultSetters) {
        for (NSString *selectorName in searchPartyResultSetters[className]) {
            [self swizzleInstanceMethodForClass:NSClassFromString(className)
                                       selector:NSSelectorFromString(selectorName)
                                    replacement:(IMP)BBFindMySearchPartyResultSetter];
        }
    }
    Class simpleBeaconInterfaceClass = NSClassFromString(@"SPBeaconManagerSimpleBeaconUpdateInterface");
    [self swizzleInstanceMethodForClass:simpleBeaconInterfaceClass
                               selector:NSSelectorFromString(@"simpleBeacons")
                            replacement:(IMP)BBFindMySearchPartyResultAccessor];
    [self swizzleInstanceMethodForClass:simpleBeaconInterfaceClass
                               selector:NSSelectorFromString(@"receivedSimpleBeaconUpdates:")
                            replacement:(IMP)BBFindMySearchPartyLocationObjectArgument];
    [self swizzleInstanceMethodForClass:simpleBeaconInterfaceClass
                               selector:NSSelectorFromString(@"receivedSimpleBeaconRemovals:")
                            replacement:(IMP)BBFindMySearchPartyLocationObjectArgument];
    [self swizzleInstanceMethodForClass:simpleBeaconInterfaceClass
                               selector:NSSelectorFromString(@"startUpdatingSimpleBeaconsWithContext:completion:")
                            replacement:(IMP)BBFindMyLocationFetchContextCompletion];
}

- (NSDictionary *)findMySwizzleDiagnostics {
    @synchronized ([BlueBubblesHelper class]) {
        NSArray *events = [findMySwizzleEvents copy] ?: @[];
        NSUInteger start = events.count > 12 ? events.count - 12 : 0;
        NSArray *recentEvents = events.count > 0 ? [events subarrayWithRange:NSMakeRange(start, events.count - start)] : @[];
        return @{
            @"installed": @(findMySwizzlesInstalled),
            @"swizzled_selectors": [findMySwizzledSelectors copy] ?: @[],
            @"event_count": @(events.count),
            @"events": recentEvents,
        };
    }
}

- (NSArray *)findMyProviderSelectorMatchesForObject:(id)object {
    if (object == nil) {
        return @[];
    }

    NSArray *terms = @[@"device", @"item", @"beacon", @"location", @"session", @"provider", @"manager", @"repository", @"refresh"];
    NSMutableArray *methodNames = [[NSMutableArray alloc] init];
    Class methodClass = [object class];
    NSUInteger methodDepth = 0;
    while (methodClass != nil && methodDepth < 4 && methodNames.count < 80) {
        unsigned int methodCount = 0;
        Method *methodList = class_copyMethodList(methodClass, &methodCount);
        for (unsigned int i = 0; i < methodCount && methodNames.count < 80; i++) {
            NSString *methodName = NSStringFromSelector(method_getName(methodList[i]));
            for (NSString *term in terms) {
                if ([methodName rangeOfString:term options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    [methodNames addObject:methodName];
                    break;
                }
            }
        }
        free(methodList);
        methodClass = class_getSuperclass(methodClass);
        methodDepth++;
    }
    return methodNames;
}

- (NSArray *)findMyDirectIvarClassSnapshotForObject:(id)object {
    if (object == nil) {
        return @[];
    }

    NSMutableArray *ivars = [[NSMutableArray alloc] init];
    Class ivarClass = [object class];
    NSUInteger ivarClassDepth = 0;
    while (ivarClass != nil && ivarClassDepth < 4 && ivars.count < 80) {
        unsigned int ivarCount = 0;
        Ivar *ivarList = class_copyIvarList(ivarClass, &ivarCount);
        for (unsigned int i = 0; i < ivarCount && ivars.count < 80; i++) {
            Ivar ivar = ivarList[i];
            const char *type = ivar_getTypeEncoding(ivar);
            if (type == NULL || type[0] != '@') {
                continue;
            }

            id value = nil;
            @try {
                value = object_getIvar(object, ivar);
            } @catch (NSException *exception) {
                value = nil;
            }

            [ivars addObject:@{
                @"name": [NSString stringWithUTF8String:ivar_getName(ivar)] ?: @"<nil>",
                @"type": [NSString stringWithUTF8String:type] ?: @"<nil>",
                @"class": [self classNameForObject:value],
                @"summary": [self summaryForValue:value],
            }];
        }
        free(ivarList);
        ivarClass = class_getSuperclass(ivarClass);
        ivarClassDepth++;
    }
    return [ivars copy];
}

- (NSDictionary *)findMyProviderIvarSnapshotForObject:(id)object maxDepth:(NSUInteger)maxDepth {
    NSArray *terms = @[
        @"Session", @"Provider", @"Manager", @"Repository", @"SPOwner",
        @"FMIP", @"Beacon", @"Device", @"Item", @"Location", @"DataSource"
    ];

    NSMutableArray *queue = [[NSMutableArray alloc] initWithObjects:@{@"object": object ?: [NSNull null], @"path": @"root", @"depth": @0}, nil];
    NSMutableSet *seen = [[NSMutableSet alloc] init];
    NSMutableArray *matches = [[NSMutableArray alloc] init];
    NSUInteger scanned = 0;

    while (queue.count > 0 && scanned < 120 && matches.count < 60) {
        NSDictionary *entry = queue[0];
        [queue removeObjectAtIndex:0];

        id current = entry[@"object"];
        if (current == nil || current == [NSNull null]) {
            continue;
        }

        NSValue *identity = [NSValue valueWithNonretainedObject:current];
        if ([seen containsObject:identity]) {
            continue;
        }
        [seen addObject:identity];
        scanned++;

        NSString *path = entry[@"path"] ?: @"root";
        NSUInteger depth = [entry[@"depth"] unsignedIntegerValue];
        NSString *className = [self classNameForObject:current];
        BOOL interesting = [self className:className matchesAnyTerm:terms];
        NSMutableDictionary *ivars = [[NSMutableDictionary alloc] init];
        NSMutableArray *nextObjects = [[NSMutableArray alloc] init];

        Class ivarClass = [current class];
        NSUInteger ivarClassDepth = 0;
        while (ivarClass != nil && ivarClassDepth < 5 && ivars.count < 80) {
            unsigned int ivarCount = 0;
            Ivar *ivarList = class_copyIvarList(ivarClass, &ivarCount);
            for (unsigned int i = 0; i < ivarCount && ivars.count < 80; i++) {
                Ivar ivar = ivarList[i];
                const char *type = ivar_getTypeEncoding(ivar);
                if (type == NULL || type[0] != '@') {
                    continue;
                }

                id value = nil;
                @try {
                    value = object_getIvar(current, ivar);
                } @catch (NSException *exception) {
                    value = nil;
                }
                if (value == nil) {
                    continue;
                }

                NSString *ivarName = [NSString stringWithUTF8String:ivar_getName(ivar)];
                NSString *valueClass = [self classNameForObject:value];
                if ([self className:ivarName matchesAnyTerm:terms] || [self className:valueClass matchesAnyTerm:terms]) {
                    ivars[ivarName] = [self summaryForValue:value];
                    interesting = YES;
                    if (depth < maxDepth) {
                        [nextObjects addObject:@{
                            @"object": value,
                            @"path": [NSString stringWithFormat:@"%@->%@", path, ivarName],
                            @"depth": @(depth + 1),
                        }];
                    }
                }
            }
            free(ivarList);
            ivarClass = class_getSuperclass(ivarClass);
            ivarClassDepth++;
        }

        if (interesting || ivars.count > 0) {
            NSMutableDictionary *match = [[NSMutableDictionary alloc] initWithDictionary:@{
                @"path": path,
                @"class": className ?: @"<nil>",
                @"methods": [self findMyProviderSelectorMatchesForObject:current],
            }];
            if (ivars.count > 0) {
                match[@"ivars"] = ivars;
            }
            [matches addObject:[match copy]];
        }

        [queue addObjectsFromArray:nextObjects];
    }

    return @{
        @"scanned": @(scanned),
        @"matches": matches,
    };
}

- (void)captureFindMyDataSource:(id)dataSource tableView:(id)tableView {
    NSString *className = [self classNameForObject:dataSource];
    NSString *type = nil;
    if ([className rangeOfString:@"FMDevicesListDataSource" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        type = @"devices";
        findMyCapturedDevicesDataSource = dataSource;
    } else if ([className rangeOfString:@"FMItemsListDataSource" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        type = @"items";
        findMyCapturedItemsDataSource = dataSource;
    } else {
        return;
    }

    id retainedDataSource = dataSource;
    id retainedTableView = tableView;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        id retainedDelegate = [self safeValueForKey:@"delegate" object:retainedTableView];
        NSDictionary *snapshot = @{
            @"type": type,
            @"timestamp": @([[NSDate date] timeIntervalSince1970]),
            @"data_source_class": [self classNameForObject:retainedDataSource],
            @"table_view_class": [self classNameForObject:retainedTableView],
            @"delegate_class": [self classNameForObject:retainedDelegate],
            @"data_source_methods": [self findMyProviderSelectorMatchesForObject:retainedDataSource],
            @"table_view_methods": [self findMyProviderSelectorMatchesForObject:retainedTableView],
            @"data_source_ivars": [self findMyDirectIvarClassSnapshotForObject:retainedDataSource],
        };
        @synchronized ([BlueBubblesHelper class]) {
            if (findMyCapturedDataSourceSnapshots == nil) {
                findMyCapturedDataSourceSnapshots = [[NSMutableDictionary alloc] init];
            }
            findMyCapturedDataSourceSnapshots[type] = snapshot;
        }
    });
}

- (NSDictionary *)capturedFindMyDataSourceDiagnostics {
    @synchronized ([BlueBubblesHelper class]) {
        return [findMyCapturedDataSourceSnapshots copy] ?: @{};
    }
}

- (NSDictionary *)findMyPassiveSnapshotForObject:(id)object source:(NSString *)source selector:(SEL)selector {
    if (object == nil) {
        return @{};
    }

    NSString *objectIdentifier = [NSString stringWithFormat:@"%p", object];
    return @{
        @"source": source ?: @"<nil>",
        @"selector": selector == nil ? @"<nil>" : NSStringFromSelector(selector),
        @"class": [self classNameForObject:object],
        @"object_id": objectIdentifier,
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
    };
}

- (void)captureFindMyInterestingObject:(id)object source:(NSString *)source selector:(SEL)selector {
    NSDictionary *snapshot = [self findMyPassiveSnapshotForObject:object source:source selector:selector];
    if (snapshot.count == 0) {
        return;
    }

    DLog("BLUEBUBBLESHELPER: Passive Find My capture source=%{public}@ selector=%{public}@ class=%{public}@ object=%{public}@",
         snapshot[@"source"], snapshot[@"selector"], snapshot[@"class"], snapshot[@"object_id"]);

    @synchronized ([BlueBubblesHelper class]) {
        if (findMyCapturedObjectSnapshots == nil) {
            findMyCapturedObjectSnapshots = [[NSMutableArray alloc] init];
        }
        if (findMyCapturedObjectsByIdentifier == nil) {
            findMyCapturedObjectsByIdentifier = [[NSMutableDictionary alloc] init];
        }
        NSString *objectIdentifier = snapshot[@"object_id"];
        if ([objectIdentifier isKindOfClass:[NSString class]]) {
            findMyCapturedObjectsByIdentifier[objectIdentifier] = object;
            if (findMyCapturedObjectsByIdentifier.count > 80) {
                [findMyCapturedObjectsByIdentifier removeObjectForKey:findMyCapturedObjectsByIdentifier.allKeys.firstObject];
            }
        }
        [findMyCapturedObjectSnapshots addObject:snapshot];
        if (findMyCapturedObjectSnapshots.count > 60) {
            [findMyCapturedObjectSnapshots removeObjectsInRange:NSMakeRange(0, findMyCapturedObjectSnapshots.count - 60)];
        }
    }
}

- (void)captureFindMyInterestingSetterObject:(id)object value:(id)value selector:(SEL)selector {
    NSMutableDictionary *snapshot = [[self findMyPassiveSnapshotForObject:object source:@"setter" selector:selector] mutableCopy];
    if (snapshot.count == 0) {
        return;
    }

    NSDictionary *valueMetadata = BBFindMySetterValueMetadata(value);
    if (valueMetadata.count > 0) {
        snapshot[@"value"] = valueMetadata;
    }

    DLog("BLUEBUBBLESHELPER: Passive Find My setter capture selector=%{public}@ class=%{public}@ object=%{public}@ value=%{public}@",
         snapshot[@"selector"], snapshot[@"class"], snapshot[@"object_id"], valueMetadata.description ?: @"<nil>");

    @synchronized ([BlueBubblesHelper class]) {
        if (findMyCapturedObjectSnapshots == nil) {
            findMyCapturedObjectSnapshots = [[NSMutableArray alloc] init];
        }
        if (findMyCapturedObjectsByIdentifier == nil) {
            findMyCapturedObjectsByIdentifier = [[NSMutableDictionary alloc] init];
        }
        NSString *objectIdentifier = snapshot[@"object_id"];
        if ([objectIdentifier isKindOfClass:[NSString class]]) {
            findMyCapturedObjectsByIdentifier[objectIdentifier] = object;
            if (findMyCapturedObjectsByIdentifier.count > 80) {
                [findMyCapturedObjectsByIdentifier removeObjectForKey:findMyCapturedObjectsByIdentifier.allKeys.firstObject];
            }
        }
        [findMyCapturedObjectSnapshots addObject:[snapshot copy]];
        if (findMyCapturedObjectSnapshots.count > 60) {
            [findMyCapturedObjectSnapshots removeObjectsInRange:NSMakeRange(0, findMyCapturedObjectSnapshots.count - 60)];
        }
    }
}

- (NSArray *)compactEntriesForSearchPartyAccessorResult:(id)result {
    if (![result isKindOfClass:[NSDictionary class]]) {
        return @[];
    }

    NSDictionary *dictionary = (NSDictionary *)result;
    NSMutableArray *entries = [[NSMutableArray alloc] init];
    for (id key in dictionary.allKeys) {
        if (entries.count >= 8) {
            break;
        }

        id value = dictionary[key];
        NSMutableDictionary *entry = [[NSMutableDictionary alloc] initWithDictionary:@{
            @"key": [key description] ?: @"<nil>",
            @"key_class": [self classNameForObject:key],
            @"value_class": [self classNameForObject:value],
        }];

        NSString *valueDescription = [value description];
        if (valueDescription.length > 0) {
            entry[@"value_description"] = valueDescription.length > 220 ? [valueDescription substringToIndex:220] : valueDescription;
        }

        [entries addObject:[entry copy]];
    }
    return entries;
}

- (void)captureFindMySearchPartyAccessorResult:(id)result source:(id)source selector:(SEL)selector {
    NSMutableDictionary *snapshot = [[NSMutableDictionary alloc] initWithDictionary:@{
        @"selector": selector == nil ? @"<nil>" : NSStringFromSelector(selector),
        @"source_class": [self classNameForObject:source],
        @"source_id": source == nil ? @"<nil>" : [NSString stringWithFormat:@"%p", source],
        @"result_class": [self classNameForObject:result],
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
    }];

    if ([result isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = (NSDictionary *)result;
        snapshot[@"result_count"] = @(dictionary.count);
        snapshot[@"entries"] = [self compactEntriesForSearchPartyAccessorResult:dictionary];
    } else if ([result isKindOfClass:[NSArray class]]) {
        NSArray *array = (NSArray *)result;
        snapshot[@"result_count"] = @(array.count);
        snapshot[@"result_summary"] = [self summaryForValue:array];
        snapshot[@"beacon_summaries"] = [self compactBeaconSummariesForBeacons:array];
    } else if ([result isKindOfClass:[NSSet class]]) {
        NSSet *set = (NSSet *)result;
        snapshot[@"result_count"] = @(set.count);
        snapshot[@"result_summary"] = [self summaryForValue:set];
        snapshot[@"beacon_summaries"] = [self compactBeaconSummariesForBeacons:[set allObjects]];
    } else if (result != nil) {
        snapshot[@"result_summary"] = [self summaryForValue:result];
        if ([self isSearchPartyResultObject:result] || [self className:[self classNameForObject:result] matchesAnyTerm:@[@"SPLocationFetchContext"]]) {
            snapshot[@"compact_result"] = [self compactSearchPartyLocationProbeResultForSelector:snapshot[@"selector"] result:result];
        } else {
            NSDictionary *fields = [self directFindMyFieldsForObject:result];
            if (fields.count > 0) {
                snapshot[@"fields"] = fields;
            }
        }
        NSString *description = [result description];
        if (description.length > 0) {
            snapshot[@"result_description"] = description.length > 220 ? [description substringToIndex:220] : description;
        }
    }

    DLog("BLUEBUBBLESHELPER: SearchParty accessor selector=%{public}@ source=%{public}@ result=%{public}@ count=%{public}@",
         snapshot[@"selector"], snapshot[@"source_class"], snapshot[@"result_class"], snapshot[@"result_count"] ?: @"<nil>");

    @synchronized ([BlueBubblesHelper class]) {
        if (findMySearchPartyAccessorSnapshots == nil) {
            findMySearchPartyAccessorSnapshots = [[NSMutableArray alloc] init];
        }
        [findMySearchPartyAccessorSnapshots addObject:[snapshot copy]];
        if (findMySearchPartyAccessorSnapshots.count > 80) {
            [findMySearchPartyAccessorSnapshots removeObjectsInRange:NSMakeRange(0, findMySearchPartyAccessorSnapshots.count - 80)];
        }
    }
}

- (void)captureFindMySearchPartyLocationInvocationForTarget:(id)target selector:(SEL)selector context:(id)context result:(id)result phase:(NSString *)phase {
    NSMutableDictionary *snapshot = [[NSMutableDictionary alloc] initWithDictionary:@{
        @"selector": selector == nil ? @"<nil>" : NSStringFromSelector(selector),
        @"source_class": [self classNameForObject:target],
        @"source_id": target == nil ? @"<nil>" : [NSString stringWithFormat:@"%p", target],
        @"phase": phase ?: @"<nil>",
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
    }];

    if (context != nil) {
        snapshot[@"context"] = [self compactSearchPartyLocationProbeResultForSelector:@"SPLocationFetchContext" result:context];
    }
    if (result != nil) {
        snapshot[@"result"] = [self compactSearchPartyLocationProbeResultForSelector:@"SPLocationFetchResult" result:result];
    }
    NSString *selectorName = NSStringFromSelector(selector);
    BOOL isDelegatedSelector = [selectorName rangeOfString:@"delegated" options:NSCaseInsensitiveSearch].location != NSNotFound;
    BOOL shouldAppendPassiveEvent = [phase rangeOfString:@"receivedUpdated" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                                    [phase rangeOfString:@"Block" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                                    isDelegatedSelector;
    if (shouldAppendPassiveEvent && result != nil) {
        [self appendFindMySearchPartyLocationProbePassiveEventWithSelectorName:snapshot[@"selector"]
                                                                         phase:phase
                                                                       context:context
                                                                        result:result
                                                                        source:target];
    } else if (shouldAppendPassiveEvent && isDelegatedSelector && context != nil) {
        [self appendFindMySearchPartyLocationProbePassiveEventWithSelectorName:snapshot[@"selector"]
                                                                         phase:phase
                                                                       context:context
                                                                        result:nil
                                                                        source:target];
    }

    DLog("BLUEBUBBLESHELPER: SearchParty location invocation selector=%{public}@ source=%{public}@ phase=%{public}@ context=%{public}@ result=%{public}@",
         snapshot[@"selector"], snapshot[@"source_class"], snapshot[@"phase"], snapshot[@"context"] ?: @"<nil>", snapshot[@"result"] ?: @"<nil>");

    @synchronized ([BlueBubblesHelper class]) {
        if ([NSStringFromClass([target class]) isEqualToString:@"SPOwnerSessionLocationFetch"]) {
            findMyCapturedSearchPartyLocationFetch = target;
        }
        if ([NSStringFromClass([context class]) isEqualToString:@"SPLocationFetchContext"]) {
            findMyCapturedSearchPartyLocationContext = context;
        }
        if (findMySearchPartyAccessorSnapshots == nil) {
            findMySearchPartyAccessorSnapshots = [[NSMutableArray alloc] init];
        }
        [findMySearchPartyAccessorSnapshots addObject:[snapshot copy]];
        if (findMySearchPartyAccessorSnapshots.count > 60) {
            [findMySearchPartyAccessorSnapshots removeObjectsInRange:NSMakeRange(0, findMySearchPartyAccessorSnapshots.count - 60)];
        }
    }
}

- (NSDictionary *)capturedFindMyPassiveDiagnostics {
    @synchronized ([BlueBubblesHelper class]) {
        NSArray *snapshots = [findMyCapturedObjectSnapshots copy] ?: @[];
        NSUInteger start = snapshots.count > 20 ? snapshots.count - 20 : 0;
        NSArray *recent = snapshots.count > 0 ? [snapshots subarrayWithRange:NSMakeRange(start, snapshots.count - start)] : @[];
        NSArray *accessorSnapshots = [findMySearchPartyAccessorSnapshots copy] ?: @[];
        NSUInteger accessorStart = accessorSnapshots.count > 24 ? accessorSnapshots.count - 24 : 0;
        NSArray *recentAccessors = accessorSnapshots.count > 0 ? [accessorSnapshots subarrayWithRange:NSMakeRange(accessorStart, accessorSnapshots.count - accessorStart)] : @[];
        return @{
            @"snapshot_count": @(snapshots.count),
            @"snapshots": recent,
            @"searchparty_accessor_count": @(accessorSnapshots.count),
            @"searchparty_accessors": recentAccessors,
        };
    }
}

- (NSDictionary *)compactFindMyActiveListDiagnostics:(NSDictionary *)diagnostics {
    if (![diagnostics isKindOfClass:[NSDictionary class]]) {
        return @{};
    }

    NSMutableDictionary *compact = [[NSMutableDictionary alloc] init];
    for (NSString *key in @[@"found", @"type", @"requested_data_source_term", @"data_source_class", @"table_view_class", @"delegate_class", @"visible_cell_count", @"active_scan_count"]) {
        id value = diagnostics[key];
        if (value != nil) {
            compact[key] = value;
        }
    }
    return [compact copy];
}

- (NSDictionary *)compactFindMySwizzleDiagnostics:(NSDictionary *)diagnostics {
    if (![diagnostics isKindOfClass:[NSDictionary class]]) {
        return @{};
    }

    NSArray *events = [diagnostics[@"events"] isKindOfClass:[NSArray class]] ? diagnostics[@"events"] : @[];
    NSUInteger start = events.count > 8 ? events.count - 8 : 0;
    NSArray *recentEvents = events.count > 0 ? [events subarrayWithRange:NSMakeRange(start, events.count - start)] : @[];
    NSArray *selectors = [diagnostics[@"swizzled_selectors"] isKindOfClass:[NSArray class]] ? diagnostics[@"swizzled_selectors"] : @[];

    return @{
        @"installed": diagnostics[@"installed"] ?: @NO,
        @"event_count": diagnostics[@"event_count"] ?: @(events.count),
        @"events": recentEvents,
        @"swizzled_selector_count": @(selectors.count),
    };
}

- (NSDictionary *)compactFindMyRefreshDiagnostics:(NSDictionary *)diagnostics {
    if (![diagnostics isKindOfClass:[NSDictionary class]]) {
        return @{};
    }

    NSMutableDictionary *compact = [[NSMutableDictionary alloc] init];
    for (NSString *key in @[@"selected_devices_segment", @"selected_items_segment", @"ui_device_count", @"ui_item_count", @"owner_beacon_count", @"owner_beacon_timeout"]) {
        id value = diagnostics[key];
        if (value != nil) {
            compact[key] = value;
        }
    }

    NSDictionary *passiveCaptures = diagnostics[@"passive_captures"];
    if ([passiveCaptures isKindOfClass:[NSDictionary class]]) {
        compact[@"passive_captures"] = passiveCaptures;
    }

    NSDictionary *swizzle = diagnostics[@"swizzle"];
    if ([swizzle isKindOfClass:[NSDictionary class]]) {
        compact[@"swizzle"] = [self compactFindMySwizzleDiagnostics:swizzle];
    }

    NSDictionary *activeDevicesList = diagnostics[@"active_devices_list"];
    if ([activeDevicesList isKindOfClass:[NSDictionary class]]) {
        compact[@"active_devices_list"] = [self compactFindMyActiveListDiagnostics:activeDevicesList];
    }

    NSDictionary *activeItemsList = diagnostics[@"active_items_list"];
    if ([activeItemsList isKindOfClass:[NSDictionary class]]) {
        compact[@"active_items_list"] = [self compactFindMyActiveListDiagnostics:activeItemsList];
    }

    NSDictionary *swiftProbe = diagnostics[@"swift_probe"];
    if ([swiftProbe isKindOfClass:[NSDictionary class]]) {
        compact[@"swift_probe"] = swiftProbe;
    }

    return [compact copy];
}

- (NSArray *)capturedSearchPartyOwnerSessions {
    NSMutableArray *sessions = [[NSMutableArray alloc] init];
    @synchronized ([BlueBubblesHelper class]) {
        for (NSString *identifier in findMyCapturedObjectsByIdentifier) {
            id object = findMyCapturedObjectsByIdentifier[identifier];
            if ([[self classNameForObject:object] isEqualToString:@"SPOwnerSession"]) {
                [sessions addObject:@{
                    @"object_id": identifier ?: @"<nil>",
                    @"object": object,
                }];
                if (sessions.count >= 6) {
                    break;
                }
            }
        }
    }
    return [sessions copy];
}

- (NSDictionary *)searchPartySummaryForSession:(id)session objectIdentifier:(NSString *)objectIdentifier {
    NSArray *accessors = @[
        @"allBeacons",
        @"allBeaconsCache",
        @"locationCache",
        @"locationSources",
        @"clientObservedBeacons",
        @"batteryStatusCache",
        @"ownerSessionState",
        @"beaconsChangedBlock",
        @"locationUpdateBlock",
        @"deviceEventUpdateBlock",
        @"latestLocationsUpdatedBlock",
        @"maintainedBeaconsChangedBlock",
        @"maintainedUnknownBeaconsChangedBlock",
        @"tagSeparationBeaconsChangedBlock",
    ];

    NSMutableDictionary *values = [[NSMutableDictionary alloc] init];
    NSMutableArray *availableAccessors = [[NSMutableArray alloc] init];
    for (NSString *accessor in accessors) {
        SEL selector = NSSelectorFromString(accessor);
        if (![session respondsToSelector:selector]) {
            continue;
        }

        [availableAccessors addObject:accessor];
        id value = [self safeObjectValueFromObject:session selectorName:accessor];
        if (value != nil) {
            NSMutableDictionary *summary = [[self summaryForValue:value] mutableCopy];
            if ([value isKindOfClass:[NSDictionary class]]) {
                summary[@"entries"] = [self compactEntriesForSearchPartyAccessorResult:value];
            }
            values[accessor] = [summary copy];
        } else {
            values[accessor] = @{@"class": @"<nil>"};
        }
    }

    return @{
        @"class": [self classNameForObject:session],
        @"object_id": objectIdentifier ?: @"<nil>",
        @"available_accessors": availableAccessors,
        @"values": values,
    };
}

- (NSDictionary *)findMySearchPartyDebugSnapshot {
    [self installFindMySwizzles];

    NSArray *capturedSessions = [self capturedSearchPartyOwnerSessions];
    NSMutableArray *sessionSnapshots = [[NSMutableArray alloc] init];
    for (NSDictionary *entry in capturedSessions) {
        id session = entry[@"object"];
        if (session == nil || session == [NSNull null]) {
            continue;
        }
        [sessionSnapshots addObject:[self searchPartySummaryForSession:session objectIdentifier:entry[@"object_id"]]];
    }

    NSUInteger capturedObjectCount = 0;
    @synchronized ([BlueBubblesHelper class]) {
        capturedObjectCount = findMyCapturedObjectsByIdentifier.count;
    }

    return @{
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
        @"swizzle": [self compactFindMySwizzleDiagnostics:[self findMySwizzleDiagnostics]],
        @"passive_captures": [self capturedFindMyPassiveDiagnostics],
        @"captured_object_count": @(capturedObjectCount),
        @"captured_owner_session_count": @(capturedSessions.count),
        @"captured_owner_sessions": sessionSnapshots,
    };
}

- (void)handleFindMySearchPartyDebugWithTransaction:(NSString *)transaction {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleFindMySearchPartyDebugWithTransaction:transaction];
        });
        return;
    }

    [[NetworkController sharedInstance] sendMessage:@{
        @"transactionId": transaction ?: [NSNull null],
        @"searchparty": [self findMySearchPartyDebugSnapshot],
    }];
}

- (NSArray *)compactBeaconSummariesForBeacons:(NSArray *)beacons {
    NSMutableArray *summaries = [[NSMutableArray alloc] init];
    for (id beacon in beacons ?: @[]) {
        if (summaries.count >= 80) {
            break;
        }

        NSMutableDictionary *summary = [[NSMutableDictionary alloc] initWithDictionary:[self summaryForValue:beacon]];
        NSString *description = [beacon description];
        if (description.length > 0) {
            summary[@"description"] = description.length > 240 ? [description substringToIndex:240] : description;
        }
        NSDictionary *fields = [self directFindMyFieldsForObject:beacon];
        if (fields.count > 0) {
            summary[@"fields"] = fields;
        }
        [summaries addObject:[summary copy]];
    }
    return [summaries copy];
}

- (NSDictionary *)findMySearchPartyBeaconProbeStatus {
    @synchronized ([BlueBubblesHelper class]) {
        return [findMySearchPartyBeaconProbe copy] ?: @{
            @"status": @"not_started",
        };
    }
}

- (void)storeFindMySearchPartyBeaconProbe:(NSDictionary *)probe {
    @synchronized ([BlueBubblesHelper class]) {
        findMySearchPartyBeaconProbe = [[NSMutableDictionary alloc] initWithDictionary:probe ?: @{}];
    }
}

- (void)handleFindMySearchPartyBeaconProbeStartWithTransaction:(NSString *)transaction {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleFindMySearchPartyBeaconProbeStartWithTransaction:transaction];
        });
        return;
    }

    [self installFindMySwizzles];
    NSArray *capturedSessions = [self capturedSearchPartyOwnerSessions];
    id targetSession = nil;
    NSString *targetSessionIdentifier = nil;
    for (NSDictionary *entry in capturedSessions) {
        id session = entry[@"object"];
        if (session != nil && session != [NSNull null] && [session respondsToSelector:NSSelectorFromString(@"allBeaconsWithCompletion:")]) {
            targetSession = session;
            targetSessionIdentifier = entry[@"object_id"];
            break;
        }
    }

    NSString *probeId = [[NSUUID UUID] UUIDString];
    NSMutableDictionary *startedProbe = [[NSMutableDictionary alloc] initWithDictionary:@{
        @"probe_id": probeId,
        @"status": targetSession == nil ? @"unavailable" : @"started",
        @"started_at": @([[NSDate date] timeIntervalSince1970]),
        @"captured_owner_session_count": @(capturedSessions.count),
        @"session_id": targetSessionIdentifier ?: [NSNull null],
    }];

    if (targetSession == nil) {
        startedProbe[@"error"] = @"No captured SPOwnerSession responds to allBeaconsWithCompletion:";
        [self storeFindMySearchPartyBeaconProbe:startedProbe];
        [[NetworkController sharedInstance] sendMessage:@{
            @"transactionId": transaction ?: [NSNull null],
            @"beacon_probe": [self findMySearchPartyBeaconProbeStatus],
        }];
        return;
    }

    [self storeFindMySearchPartyBeaconProbe:startedProbe];

    void (^completion)(id) = ^(id beaconsResult) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray *beacons = @[];
            if ([beaconsResult isKindOfClass:[NSArray class]]) {
                beacons = beaconsResult;
            } else if ([beaconsResult isKindOfClass:[NSSet class]]) {
                beacons = [(NSSet *)beaconsResult allObjects];
            }
            NSMutableArray *serialized = [[NSMutableArray alloc] init];
            for (id beacon in beacons) {
                if (serialized.count >= 80) {
                    break;
                }
                [serialized addObject:[self serializeOwnerBeacon:beacon]];
            }

            NSMutableDictionary *completedProbe = [[NSMutableDictionary alloc] initWithDictionary:@{
                @"probe_id": probeId,
                @"status": @"completed",
                @"started_at": startedProbe[@"started_at"] ?: @0,
                @"completed_at": @([[NSDate date] timeIntervalSince1970]),
                @"session_id": targetSessionIdentifier ?: [NSNull null],
                @"result_class": [self classNameForObject:beaconsResult],
                @"result_summary": [self summaryForValue:beaconsResult],
                @"beacon_count": @(beacons.count),
                @"serialized_count": @(serialized.count),
                @"beacon_summaries": [self compactBeaconSummariesForBeacons:beacons],
                @"beacons": serialized,
            }];
            [self storeFindMySearchPartyBeaconProbe:completedProbe];
        });
    };

    SEL selector = NSSelectorFromString(@"allBeaconsWithCompletion:");
    @try {
        NSMethodSignature *signature = [targetSession methodSignatureForSelector:selector];
        if (signature == nil || signature.numberOfArguments != 3) {
            startedProbe[@"status"] = @"failed";
            startedProbe[@"error"] = @"Unexpected allBeaconsWithCompletion: method signature";
            [self storeFindMySearchPartyBeaconProbe:startedProbe];
        } else {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:targetSession];
            [invocation setSelector:selector];
            [invocation setArgument:&completion atIndex:2];
            [invocation retainArguments];
            [invocation invoke];
        }
    } @catch (NSException *exception) {
        startedProbe[@"status"] = @"failed";
        startedProbe[@"error"] = exception.reason ?: exception.description ?: @"Exception invoking allBeaconsWithCompletion:";
        [self storeFindMySearchPartyBeaconProbe:startedProbe];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @synchronized ([BlueBubblesHelper class]) {
            NSString *currentProbeId = findMySearchPartyBeaconProbe[@"probe_id"];
            NSString *currentStatus = findMySearchPartyBeaconProbe[@"status"];
            if ([currentProbeId isEqualToString:probeId] && [currentStatus isEqualToString:@"started"]) {
                findMySearchPartyBeaconProbe[@"status"] = @"timed_out";
                findMySearchPartyBeaconProbe[@"timed_out_at"] = @([[NSDate date] timeIntervalSince1970]);
            }
        }
    });

    [[NetworkController sharedInstance] sendMessage:@{
        @"transactionId": transaction ?: [NSNull null],
        @"beacon_probe": [self findMySearchPartyBeaconProbeStatus],
    }];
}

- (void)handleFindMySearchPartyBeaconProbeStatusWithTransaction:(NSString *)transaction {
    [[NetworkController sharedInstance] sendMessage:@{
        @"transactionId": transaction ?: [NSNull null],
        @"beacon_probe": [self findMySearchPartyBeaconProbeStatus],
    }];
}

- (BOOL)selectorNameMatchesSearchPartyLocationProbe:(NSString *)selectorName {
    if (selectorName.length == 0) {
        return NO;
    }

    NSArray *terms = @[@"location", @"Location", @"locations", @"Locations", @"beacon", @"Beacon"];
    for (NSString *term in terms) {
        if ([selectorName rangeOfString:term options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

- (NSArray *)searchPartyLocationMethodDiagnosticsForObject:(id)object {
    if (object == nil || object == [NSNull null]) {
        return @[];
    }

    NSMutableArray *methods = [[NSMutableArray alloc] init];
    NSMutableSet *seen = [[NSMutableSet alloc] init];
    Class methodClass = [object class];
    NSUInteger methodDepth = 0;
    while (methodClass != nil && methodDepth < 5 && methods.count < 140) {
        unsigned int methodCount = 0;
        Method *methodList = class_copyMethodList(methodClass, &methodCount);
        for (unsigned int i = 0; i < methodCount && methods.count < 140; i++) {
            SEL selector = method_getName(methodList[i]);
            NSString *selectorName = NSStringFromSelector(selector);
            if (![self selectorNameMatchesSearchPartyLocationProbe:selectorName] || [seen containsObject:selectorName]) {
                continue;
            }
            [seen addObject:selectorName];

            NSMethodSignature *signature = [object methodSignatureForSelector:selector];
            NSMutableDictionary *entry = [[NSMutableDictionary alloc] initWithDictionary:@{
                @"selector": selectorName ?: @"<nil>",
                @"declaring_class": NSStringFromClass(methodClass) ?: @"<nil>",
                @"type_encoding": [NSString stringWithUTF8String:method_getTypeEncoding(methodList[i]) ?: ""] ?: @"",
            }];
            if (signature != nil) {
                const char *returnType = signature.methodReturnType;
                entry[@"argument_count"] = @(signature.numberOfArguments);
                entry[@"return_type"] = returnType == NULL ? @"<nil>" : [NSString stringWithUTF8String:returnType];
            }
            [methods addObject:[entry copy]];
        }
        free(methodList);
        methodClass = class_getSuperclass(methodClass);
        methodDepth++;
    }
    return [methods copy];
}

- (NSArray *)compactLocationDictionaryEntries:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return @[];
    }

    NSMutableArray *entries = [[NSMutableArray alloc] init];
    for (id key in dictionary.allKeys) {
        if (entries.count >= 40) {
            break;
        }

        id value = dictionary[key];
        NSMutableDictionary *entry = [[NSMutableDictionary alloc] initWithDictionary:@{
            @"key": [key description] ?: @"<nil>",
            @"key_class": [self classNameForObject:key],
            @"value_class": [self classNameForObject:value],
            @"value_summary": [self summaryForValue:value],
        }];
        NSDictionary *location = [self serializeLocationObject:value];
        if (location != (NSDictionary *)[NSNull null]) {
            entry[@"location"] = location;
        }
        NSDictionary *fields = [self directFindMyFieldsForObject:value];
        if (fields.count > 0) {
            entry[@"fields"] = fields;
        }
        NSString *description = [value description];
        if (description.length > 0) {
            entry[@"value_description"] = description.length > 220 ? [description substringToIndex:220] : description;
        }
        [entries addObject:[entry copy]];
    }
    return [entries copy];
}

- (BOOL)isSearchPartyResultObject:(id)object {
    NSString *className = [self classNameForObject:object];
    return [className isEqualToString:@"SPLocationFetchResult"] ||
           [className isEqualToString:@"SPDeviceEventFetchResult"];
}

- (BOOL)selectorNameMatchesSearchPartyResultDeepDiagnostics:(NSString *)selectorName {
    if (selectorName.length == 0 ||
        [selectorName hasPrefix:@"set"] ||
        [selectorName rangeOfString:@":"].location != NSNotFound) {
        return NO;
    }
    NSArray *ignoredTerms = @[@"accessibility", @"Accessibility", @"ITK_", @"vk_", @"VN", @"_ax", @"focusGroup"];
    for (NSString *term in ignoredTerms) {
        if ([selectorName rangeOfString:term options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return NO;
        }
    }

    NSArray *terms = @[
        @"location", @"locations", @"Location", @"Locations",
        @"beacon", @"beacons", @"Beacon", @"Beacons",
        @"device", @"devices", @"Device", @"Devices",
        @"event", @"events", @"Event", @"Events",
        @"cache", @"cached", @"Cache", @"Cached",
        @"result", @"results", @"Result", @"Results"
    ];
    for (NSString *term in terms) {
        if ([selectorName rangeOfString:term options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

- (NSDictionary *)searchPartyResultDeepDiagnosticsForObject:(id)object {
    if (![self isSearchPartyResultObject:object]) {
        return @{};
    }

    NSMutableDictionary *diagnostics = [[NSMutableDictionary alloc] initWithDictionary:@{
        @"class": [self classNameForObject:object],
    }];

    NSArray *candidateKeys = @[
        @"locationsByBeaconIdentifier", @"locationByBeaconIdentifier", @"locationsByIdentifier",
        @"locations", @"location", @"locationCache", @"cachedLocation", @"cache",
        @"beaconLocations", @"beaconLocation", @"beaconEvents", @"beaconEventByBeaconIdentifier",
        @"results", @"result", @"devices", @"deviceEvents", @"events", @"items", @"beacons"
    ];
    NSMutableDictionary *keyValues = [[NSMutableDictionary alloc] init];
    for (NSString *key in candidateKeys) {
        id value = [self safeValueForKey:key object:object];
        if (value == nil || value == [NSNull null]) {
            continue;
        }

        NSMutableDictionary *valueEntry = [[NSMutableDictionary alloc] initWithDictionary:@{
            @"summary": [self summaryForValue:value],
        }];
        NSDictionary *location = [self serializeLocationObject:value];
        if (location != (NSDictionary *)[NSNull null]) {
            valueEntry[@"location"] = location;
        }
        if ([value isKindOfClass:[NSDictionary class]]) {
            valueEntry[@"entries"] = [self compactLocationDictionaryEntries:value];
        } else if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSSet class]]) {
            valueEntry[@"children"] = [self compactBeaconSummariesForBeacons:[self objectChildrenForValue:value]];
        } else {
            NSDictionary *fields = [self directFindMyFieldsForObject:value];
            if (fields.count > 0) {
                valueEntry[@"fields"] = fields;
            }
        }
        NSString *description = [value description];
        if (description.length > 0) {
            valueEntry[@"description"] = description.length > 240 ? [description substringToIndex:240] : description;
        }
        keyValues[key] = [valueEntry copy];
    }
    if (keyValues.count > 0) {
        diagnostics[@"candidate_key_values"] = keyValues;
    }

    NSMutableDictionary *accessorValues = [[NSMutableDictionary alloc] init];
    NSMutableArray *methodDiagnostics = [[NSMutableArray alloc] init];
    NSMutableSet *seenSelectors = [[NSMutableSet alloc] initWithArray:candidateKeys];
    Class methodClass = [object class];
    NSUInteger methodDepth = 0;
    while (methodClass != nil && methodDepth < 5 && methodDiagnostics.count < 120) {
        unsigned int methodCount = 0;
        Method *methodList = class_copyMethodList(methodClass, &methodCount);
        for (unsigned int i = 0; i < methodCount && methodDiagnostics.count < 120; i++) {
            Method method = methodList[i];
            SEL selector = method_getName(method);
            NSString *selectorName = NSStringFromSelector(selector);
            if ([seenSelectors containsObject:selectorName] ||
                ![self selectorNameMatchesSearchPartyResultDeepDiagnostics:selectorName]) {
                continue;
            }
            [seenSelectors addObject:selectorName];

            NSMethodSignature *signature = [object methodSignatureForSelector:selector];
            NSMutableDictionary *methodEntry = [[NSMutableDictionary alloc] initWithDictionary:@{
                @"selector": selectorName ?: @"<nil>",
                @"declaring_class": NSStringFromClass(methodClass) ?: @"<nil>",
                @"type_encoding": [NSString stringWithUTF8String:method_getTypeEncoding(method) ?: ""] ?: @"",
            }];
            if (signature != nil) {
                const char *returnType = signature.methodReturnType;
                methodEntry[@"argument_count"] = @(signature.numberOfArguments);
                methodEntry[@"return_type"] = returnType == NULL ? @"<nil>" : [NSString stringWithUTF8String:returnType];
                if (signature.numberOfArguments == 2 && returnType != NULL && returnType[0] == '@' && accessorValues.count < 40) {
                    id value = [self safeObjectValueFromObject:object selectorName:selectorName];
                    if (value != nil && value != [NSNull null]) {
                        NSMutableDictionary *valueEntry = [[NSMutableDictionary alloc] initWithDictionary:@{
                            @"summary": [self summaryForValue:value],
                        }];
                        NSDictionary *location = [self serializeLocationObject:value];
                        if (location != (NSDictionary *)[NSNull null]) {
                            valueEntry[@"location"] = location;
                        }
                        if ([value isKindOfClass:[NSDictionary class]]) {
                            valueEntry[@"entries"] = [self compactLocationDictionaryEntries:value];
                        } else {
                            NSDictionary *fields = [self directFindMyFieldsForObject:value];
                            if (fields.count > 0) {
                                valueEntry[@"fields"] = fields;
                            }
                        }
                        accessorValues[selectorName] = [valueEntry copy];
                    }
                }
            }
            [methodDiagnostics addObject:[methodEntry copy]];
        }
        free(methodList);
        methodClass = class_getSuperclass(methodClass);
        methodDepth++;
    }
    if (methodDiagnostics.count > 0) {
        diagnostics[@"methods"] = methodDiagnostics;
    }
    if (accessorValues.count > 0) {
        diagnostics[@"accessor_values"] = accessorValues;
    }

    NSArray *ivars = [self findMyDirectIvarClassSnapshotForObject:object];
    if (ivars.count > 0) {
        diagnostics[@"ivars"] = ivars;
    }

    return [diagnostics copy];
}

- (NSDictionary *)searchPartyLocationProbeResultForSelector:(NSString *)selectorName result:(id)result {
    NSMutableDictionary *entry = [[NSMutableDictionary alloc] initWithDictionary:@{
        @"selector": selectorName ?: @"<nil>",
        @"result_class": [self classNameForObject:result],
        @"result_summary": [self summaryForValue:result],
    }];

    NSDictionary *location = [self serializeLocationObject:result];
    if (location != (NSDictionary *)[NSNull null]) {
        entry[@"location"] = location;
    }
    if ([result isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = (NSDictionary *)result;
        entry[@"result_count"] = @(dictionary.count);
        entry[@"entries"] = [self compactLocationDictionaryEntries:dictionary];
    }
    id simpleBeacons = [self safeObjectValueFromObject:result selectorName:@"simpleBeacons"];
    NSArray *simpleBeaconChildren = [self objectChildrenForValue:simpleBeacons];
    if (simpleBeaconChildren.count > 0) {
        entry[@"simple_beacon_count"] = @(simpleBeaconChildren.count);
        entry[@"simple_beacons"] = [self compactBeaconSummariesForBeacons:simpleBeaconChildren];
    }
    NSDictionary *fields = [self directFindMyFieldsForObject:result];
    if (fields.count > 0) {
        entry[@"fields"] = fields;
    }
    NSDictionary *deepResultDiagnostics = [self searchPartyResultDeepDiagnosticsForObject:result];
    if (deepResultDiagnostics.count > 0) {
        entry[@"deep_result_diagnostics"] = deepResultDiagnostics;
    }
    NSString *className = [self classNameForObject:result];
    if ([self className:className matchesAnyTerm:@[@"Location", @"Fetch", @"SPOwner", @"Beacon"]]) {
        NSArray *methods = [self searchPartyLocationMethodDiagnosticsForObject:result];
        if (methods.count > 0) {
            entry[@"methods"] = methods;
        }
        NSArray *ivars = [self findMyDirectIvarClassSnapshotForObject:result];
        if (ivars.count > 0) {
            entry[@"ivars"] = ivars;
        }
    }
    NSString *description = [result description];
    if (description.length > 0) {
        entry[@"result_description"] = description.length > 300 ? [description substringToIndex:300] : description;
    }
    return [entry copy];
}

- (NSDictionary *)compactSearchPartyLocationProbeResultForSelector:(NSString *)selectorName result:(id)result {
    NSMutableDictionary *entry = [[NSMutableDictionary alloc] initWithDictionary:@{
        @"selector": selectorName ?: @"<nil>",
        @"result_class": [self classNameForObject:result],
        @"result_summary": [self summaryForValue:result],
    }];

    NSDictionary *location = [self serializeLocationObject:result];
    if (location != (NSDictionary *)[NSNull null]) {
        entry[@"location"] = location;
    }

    id locationsByBeaconIdentifier = [self safeObjectValueFromObject:result selectorName:@"locationsByBeaconIdentifier"];
    if ([locationsByBeaconIdentifier isKindOfClass:[NSDictionary class]]) {
        NSDictionary *locations = (NSDictionary *)locationsByBeaconIdentifier;
        entry[@"locations_by_beacon_identifier_count"] = @(locations.count);
        entry[@"locations_by_beacon_identifier_entries"] = [self compactLocationDictionaryEntries:locations];
    }

    id beaconEventByBeaconIdentifier = [self safeObjectValueFromObject:result selectorName:@"beaconEventByBeaconIdentifier"];
    if ([beaconEventByBeaconIdentifier isKindOfClass:[NSDictionary class]]) {
        NSDictionary *events = (NSDictionary *)beaconEventByBeaconIdentifier;
        entry[@"beacon_event_by_beacon_identifier_count"] = @(events.count);
        entry[@"beacon_event_by_beacon_identifier_entries"] = [self compactLocationDictionaryEntries:events];
    }

    id searchIdentifiers = [self safeObjectValueFromObject:result selectorName:@"searchIdentifiers"];
    NSUInteger searchIdentifierCount = [self objectChildrenForValue:searchIdentifiers].count;
    if (searchIdentifierCount > 0) {
        entry[@"search_identifier_count"] = @(searchIdentifierCount);
    }

    id searchLocationSources = [self safeObjectValueFromObject:result selectorName:@"searchLocationSources"];
    NSUInteger searchLocationSourceCount = [self objectChildrenForValue:searchLocationSources].count;
    if (searchLocationSourceCount > 0) {
        entry[@"search_location_source_count"] = @(searchLocationSourceCount);
    }

    id lastOnlineLocationInfo = [self safeObjectValueFromObject:result selectorName:@"lastOnlineLocationInfo"];
    if ([lastOnlineLocationInfo isKindOfClass:[NSDictionary class]]) {
        entry[@"last_online_location_info_count"] = @([(NSDictionary *)lastOnlineLocationInfo count]);
    }
    if ([[self classNameForObject:result] isEqualToString:@"SPLocationFetchContext"]) {
        entry[@"context_detail"] = [self searchPartyFetchContextDiagnosticsForContext:result];
    }
    if ([[self classNameForObject:result] isEqualToString:@"SPLocationFetchResult"]) {
        NSDictionary *deepResultDiagnostics = [self searchPartyResultDeepDiagnosticsForObject:result];
        if (deepResultDiagnostics.count > 0) {
            entry[@"result_detail"] = deepResultDiagnostics;
        }
    }

    NSMutableDictionary *relatedObjects = [[NSMutableDictionary alloc] init];
    for (NSString *relatedSelector in @[@"proxy", @"_proxy", @"session", @"connection", @"serviceDescription", @"locationFetch", @"simpleBeaconUpdateInterface", @"context"]) {
        id relatedObject = [self safeObjectValueFromObject:result selectorName:relatedSelector];
        if (relatedObject != nil && relatedObject != [NSNull null]) {
            relatedObjects[relatedSelector] = [self compactRelatedSearchPartyObject:relatedObject matchingTerms:@[
                @"proxy", @"session", @"connection", @"service", @"location", @"beacon",
                @"device", @"event", @"cache", @"fetch", @"xpc", @"received", @"updated"
            ]];
        }
    }
    if (relatedObjects.count > 0) {
        entry[@"related_objects"] = relatedObjects;
    }

    NSDictionary *fields = [self directFindMyFieldsForObject:result];
    if (fields.count > 0) {
        entry[@"fields"] = fields;
    }

    NSString *description = [result description];
    if (description.length > 0) {
        entry[@"result_description"] = description.length > 180 ? [description substringToIndex:180] : description;
    }
    return [entry copy];
}

- (NSDictionary *)compactRelatedSearchPartyObject:(id)object matchingTerms:(NSArray<NSString *> *)terms {
    if (object == nil || object == [NSNull null]) {
        return @{@"class": @"<nil>"};
    }

    NSString *objectClassName = [self classNameForObject:object];
    NSMutableDictionary *summary = [[NSMutableDictionary alloc] initWithDictionary:@{
        @"class": objectClassName ?: @"<nil>",
        @"summary": [self summaryForValue:object],
        @"object_id": [NSString stringWithFormat:@"%p", object],
    }];

    NSString *description = [object description];
    if (description.length > 0) {
        summary[@"description"] = description.length > 180 ? [description substringToIndex:180] : description;
    }

    Class objectClass = [object class];
    NSArray *matchedMethods = [self compactSelectorDiagnosticsForClass:objectClass includeClassMethods:NO matchingTerms:terms limit:60];
    if (matchedMethods.count > 0) {
        summary[@"matched_instance_methods"] = matchedMethods;
    }

    NSMutableArray *ivars = [[NSMutableArray alloc] init];
    unsigned int ivarCount = 0;
    Ivar *ivarList = class_copyIvarList(objectClass, &ivarCount);
    for (unsigned int i = 0; i < ivarCount && ivars.count < 8; i++) {
        Ivar ivar = ivarList[i];
        const char *name = ivar_getName(ivar);
        const char *type = ivar_getTypeEncoding(ivar);
        [ivars addObject:@{
            @"name": name == NULL ? @"<nil>" : [NSString stringWithUTF8String:name],
            @"type": type == NULL ? @"<nil>" : [NSString stringWithUTF8String:type],
        }];
    }
    free(ivarList);
    summary[@"ivar_count"] = @(ivarCount);
    if (ivars.count > 0) {
        summary[@"ivars"] = ivars;
    }

    return [summary copy];
}

- (NSDictionary *)findMySearchPartyLocationProbeStatus {
    @synchronized ([BlueBubblesHelper class]) {
        return [findMySearchPartyLocationProbe copy] ?: @{
            @"status": @"not_started",
        };
    }
}

- (NSArray *)compactSearchPartyLocationProbeEntries:(NSArray *)entries limit:(NSUInteger)limit {
    if (![entries isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSUInteger start = entries.count > limit ? entries.count - limit : 0;
    NSMutableArray *compactEntries = [[NSMutableArray alloc] init];
    for (NSUInteger index = start; index < entries.count; index++) {
        id rawEntry = entries[index];
        if (![rawEntry isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        NSDictionary *entry = (NSDictionary *)rawEntry;
        NSMutableDictionary *compactEntry = [[NSMutableDictionary alloc] init];
        for (NSString *key in @[@"selector", @"phase", @"timestamp", @"source_class", @"result_class"]) {
            id value = entry[key];
            if (value != nil && value != [NSNull null]) {
                compactEntry[key] = value;
            }
        }

        NSDictionary *result = [entry[@"result"] isKindOfClass:[NSDictionary class]] ? entry[@"result"] : entry;
        for (NSString *key in @[@"locations_by_beacon_identifier_count", @"beacon_event_by_beacon_identifier_count", @"result_class"]) {
            id value = result[key];
            if (value != nil && value != [NSNull null] && compactEntry[key] == nil) {
                compactEntry[key] = value;
            }
        }
        id location = result[@"location"];
        if (location != nil && location != [NSNull null]) {
            compactEntry[@"location"] = location;
        }
        id locationEntries = result[@"locations_by_beacon_identifier_entries"];
        if ([locationEntries isKindOfClass:[NSArray class]] && [(NSArray *)locationEntries count] > 0) {
            compactEntry[@"locations_by_beacon_identifier_entries"] = locationEntries;
        }
        id eventEntries = result[@"beacon_event_by_beacon_identifier_entries"];
        if ([eventEntries isKindOfClass:[NSArray class]] && [(NSArray *)eventEntries count] > 0) {
            compactEntry[@"beacon_event_by_beacon_identifier_entries"] = eventEntries;
        }
        NSDictionary *resultDetail = [result[@"result_detail"] isKindOfClass:[NSDictionary class]] ? result[@"result_detail"] : nil;
        if (resultDetail != nil) {
            NSDictionary *candidateKeyValues = [resultDetail[@"candidate_key_values"] isKindOfClass:[NSDictionary class]] ? resultDetail[@"candidate_key_values"] : @{};
            NSDictionary *accessorValues = [resultDetail[@"accessor_values"] isKindOfClass:[NSDictionary class]] ? resultDetail[@"accessor_values"] : @{};
            NSArray *methods = [resultDetail[@"methods"] isKindOfClass:[NSArray class]] ? resultDetail[@"methods"] : @[];
            NSArray *ivars = [resultDetail[@"ivars"] isKindOfClass:[NSArray class]] ? resultDetail[@"ivars"] : @[];
            compactEntry[@"result_detail_summary"] = @{
                @"candidate_key_names": [[candidateKeyValues allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)],
                @"accessor_names": [[accessorValues allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)],
                @"method_count": @(methods.count),
                @"ivars": ivars.count > 12 ? [ivars subarrayWithRange:NSMakeRange(0, 12)] : ivars,
            };
        }

        [compactEntries addObject:compactEntry];
    }
    return [compactEntries copy];
}

- (NSDictionary *)findMySearchPartyLocationProbeCompactStatus {
    @synchronized ([BlueBubblesHelper class]) {
        if (findMySearchPartyLocationProbe == nil) {
            return @{
                @"status": @"not_started",
            };
        }

        NSMutableDictionary *compact = [[NSMutableDictionary alloc] init];
        for (NSString *key in @[
            @"probe_id",
            @"status",
            @"started_at",
            @"completed_at",
            @"focused_probe_step",
            @"dedicated_probe",
            @"pending_completion_count",
            @"captured_owner_session_count",
            @"beacon_result_class",
            @"beacon_result_summary",
            @"context_search_identifier_count",
            @"context_search_location_source_count",
            @"passive_location_event_count",
            @"last_passive_location_event_at",
            @"callback_watch_method_availability",
            @"callback_watch_context",
            @"single_identifier_context_method_availability",
            @"last_online_context_method_availability",
            @"delegated_context_method_availability",
            @"callback_watch_note",
            @"delegated_context_note",
            @"single_identifier_context_assignment",
            @"last_online_context_assignment",
            @"controlled_context_assignment",
        ]) {
            id value = findMySearchPartyLocationProbe[key];
            if (value != nil && value != [NSNull null]) {
                compact[key] = value;
            }
        }

        compact[@"completion_results"] = [self compactSearchPartyLocationProbeEntries:findMySearchPartyLocationProbe[@"completion_results"] limit:12];
        compact[@"passive_location_events"] = [self compactSearchPartyLocationProbeEntries:findMySearchPartyLocationProbe[@"passive_location_events"] limit:20];

        return [compact copy];
    }
}

- (void)storeFindMySearchPartyLocationProbe:(NSDictionary *)probe {
    @synchronized ([BlueBubblesHelper class]) {
        findMySearchPartyLocationProbe = [[NSMutableDictionary alloc] initWithDictionary:probe ?: @{}];
    }
}

- (void)appendFindMySearchPartyLocationProbeCompletionForProbeId:(NSString *)probeId selectorName:(NSString *)selectorName result:(id)result {
    @synchronized ([BlueBubblesHelper class]) {
        if (![findMySearchPartyLocationProbe[@"probe_id"] isEqualToString:probeId]) {
            return;
        }

        NSMutableArray *completionResults = nil;
        id existingResults = findMySearchPartyLocationProbe[@"completion_results"];
        if ([existingResults isKindOfClass:[NSArray class]]) {
            completionResults = [[NSMutableArray alloc] initWithArray:existingResults];
        } else {
            completionResults = [[NSMutableArray alloc] init];
        }

        [completionResults addObject:[self compactSearchPartyLocationProbeResultForSelector:selectorName result:result]];
        findMySearchPartyLocationProbe[@"completion_results"] = completionResults;

        NSInteger pending = [findMySearchPartyLocationProbe[@"pending_completion_count"] integerValue];
        pending = MAX(0, pending - 1);
        findMySearchPartyLocationProbe[@"pending_completion_count"] = @(pending);
        if (pending == 0) {
            findMySearchPartyLocationProbe[@"status"] = @"completed";
            findMySearchPartyLocationProbe[@"completed_at"] = @([[NSDate date] timeIntervalSince1970]);
        }
    }
}

- (void)appendFindMySearchPartyLocationProbePassiveEventWithSelectorName:(NSString *)selectorName phase:(NSString *)phase context:(id)context result:(id)result source:(id)source {
    @synchronized ([BlueBubblesHelper class]) {
        if (findMySearchPartyLocationProbe == nil || [findMySearchPartyLocationProbe[@"status"] isEqualToString:@"not_started"]) {
            return;
        }

        NSMutableArray *passiveEvents = nil;
        id existingEvents = findMySearchPartyLocationProbe[@"passive_location_events"];
        if ([existingEvents isKindOfClass:[NSArray class]]) {
            passiveEvents = [[NSMutableArray alloc] initWithArray:existingEvents];
        } else {
            passiveEvents = [[NSMutableArray alloc] init];
        }

        NSMutableDictionary *event = [[NSMutableDictionary alloc] initWithDictionary:@{
            @"selector": selectorName ?: @"<nil>",
            @"phase": phase ?: @"<nil>",
            @"timestamp": @([[NSDate date] timeIntervalSince1970]),
            @"source_class": [self classNameForObject:source],
            @"source_id": source == nil ? @"<nil>" : [NSString stringWithFormat:@"%p", source],
            @"result_class": [self classNameForObject:result],
        }];
        if (context != nil) {
            event[@"context"] = [self compactSearchPartyLocationProbeResultForSelector:@"SPLocationFetchContext" result:context];
        }
        if (result != nil) {
            event[@"result"] = [self compactSearchPartyLocationProbeResultForSelector:selectorName result:result];
        }

        [passiveEvents addObject:event];
        if (passiveEvents.count > 40) {
            [passiveEvents removeObjectsInRange:NSMakeRange(0, passiveEvents.count - 40)];
        }
        findMySearchPartyLocationProbe[@"passive_location_events"] = passiveEvents;
        findMySearchPartyLocationProbe[@"passive_location_event_count"] = @(passiveEvents.count);
        findMySearchPartyLocationProbe[@"last_passive_location_event_at"] = event[@"timestamp"];
    }
}

- (NSString *)normalizedSearchPartyIdentifierString:(id)value {
    if (value == nil || value == [NSNull null]) {
        return nil;
    }
    NSString *stringValue = nil;
    if ([value isKindOfClass:[NSUUID class]]) {
        stringValue = [(NSUUID *)value UUIDString];
    } else {
        stringValue = [value description];
    }
    if (stringValue.length == 0) {
        return nil;
    }
    return [[stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
}

- (NSArray *)searchPartyIdentifierCandidatesForBeacon:(id)beacon {
    NSMutableArray *candidates = [[NSMutableArray alloc] init];
    NSDictionary *candidateMap = [self searchPartyIdentifierCandidateMapForBeacon:beacon];
    for (NSString *key in @[@"identifier", @"ownerBeaconIdentifier", @"stableIdentifier", @"uuid", @"beaconUUID", @"accessoryIdentifier", @"productUUID", @"correlationIdentifier"]) {
        NSString *normalized = candidateMap[key];
        if (normalized.length > 0 && ![candidates containsObject:normalized]) {
            [candidates addObject:normalized];
        }
    }
    return [candidates copy];
}

- (NSDictionary *)searchPartyIdentifierCandidateMapForBeacon:(id)beacon {
    NSMutableDictionary *candidateMap = [[NSMutableDictionary alloc] init];
    for (NSString *key in @[
        @"identifier", @"ownerBeaconIdentifier", @"stableIdentifier", @"uuid",
        @"beaconUUID", @"accessoryIdentifier", @"productUUID", @"correlationIdentifier"
    ]) {
        id value = [self directFindMyCandidateValueFromObject:beacon key:key];
        NSString *normalized = [self normalizedSearchPartyIdentifierString:value];
        if (normalized.length > 0) {
            candidateMap[key] = normalized;
        }
    }
    return [candidateMap copy];
}

- (NSDictionary *)searchPartyLocationInfoAccessorValuesForObject:(id)object {
    if (object == nil || object == [NSNull null]) {
        return @{};
    }

    NSMutableArray *selectorNames = [[NSMutableArray alloc] initWithArray:@[
        @"location",
        @"clLocation",
        @"lastLocation",
        @"latestLocation",
        @"crowdSourcedLocation",
        @"coordinate",
        @"latitude",
        @"longitude",
        @"horizontalAccuracy",
        @"verticalAccuracy",
        @"altitude",
        @"timestamp",
        @"timeStamp",
        @"date",
        @"locationFinished",
        @"locationError",
        @"locationSource",
        @"locationType",
        @"isLocationAvailable",
        @"isOldLocation",
        @"oldLocation",
        @"lastOnlineDate",
        @"lastOnlineTime",
    ]];

    for (NSDictionary *method in [self searchPartyLocationMethodDiagnosticsForObject:object]) {
        NSString *selectorName = method[@"selector"];
        NSNumber *argumentCount = method[@"argument_count"];
        if (selectorName.length > 0 &&
            [argumentCount unsignedIntegerValue] == 2 &&
            ![selectorNames containsObject:selectorName] &&
            selectorNames.count < 80) {
            [selectorNames addObject:selectorName];
        }
    }

    NSMutableDictionary *values = [[NSMutableDictionary alloc] init];
    for (NSString *selectorName in selectorNames) {
        id value = [self safeJSONValueFromObject:object zeroArgumentSelectorName:selectorName];
        if (value != nil && value != [NSNull null]) {
            values[selectorName] = value;
        }
    }

    return [values copy];
}

- (NSDictionary *)searchPartyLocationInfoIvarValuesForObject:(id)object {
    if (object == nil || object == [NSNull null]) {
        return @{};
    }

    NSMutableDictionary *values = [[NSMutableDictionary alloc] init];
    Class ivarClass = [object class];
    NSUInteger ivarClassDepth = 0;
    while (ivarClass != nil && ivarClassDepth < 5 && values.count < 80) {
        unsigned int ivarCount = 0;
        Ivar *ivarList = class_copyIvarList(ivarClass, &ivarCount);
        for (unsigned int i = 0; i < ivarCount && values.count < 80; i++) {
            Ivar ivar = ivarList[i];
            const char *type = ivar_getTypeEncoding(ivar);
            const char *name = ivar_getName(ivar);
            if (type == NULL || name == NULL) {
                continue;
            }
            NSString *ivarName = [NSString stringWithUTF8String:name];

            @try {
                if (type[0] == '@') {
                    id value = object_getIvar(object, ivar);
                    if (value == nil || value == [NSNull null]) {
                        continue;
                    }
                    NSDictionary *location = [self serializeLocationObject:value];
                    if (location != (NSDictionary *)[NSNull null]) {
                        values[ivarName] = @{@"location": location, @"class": [self classNameForObject:value]};
                    } else if ([self className:ivarName matchesAnyTerm:@[@"location"]] ||
                               [self className:[self classNameForObject:value] matchesAnyTerm:@[@"Location"]]) {
                        NSArray *children = [self searchPartyLocationBearingChildSnapshotsForValue:value];
                        if (children.count > 0) {
                            values[ivarName] = @{
                                @"class": [self classNameForObject:value],
                                @"summary": [self summaryForValue:value],
                                @"children": children,
                            };
                        } else {
                            NSString *stringValue = [self stringValueForFindMyValue:value];
                            values[ivarName] = stringValue ?: [self summaryForValue:value];
                        }
                    } else {
                        NSString *stringValue = [self stringValueForFindMyValue:value];
                        values[ivarName] = stringValue ?: [self summaryForValue:value];
                    }
                } else if (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0) {
                    ptrdiff_t offset = ivar_getOffset(ivar);
                    BOOL value = *(BOOL *)((uint8_t *)(__bridge void *)object + offset);
                    values[ivarName] = @(value);
                } else if (strcmp(type, @encode(double)) == 0) {
                    ptrdiff_t offset = ivar_getOffset(ivar);
                    double value = *(double *)((uint8_t *)(__bridge void *)object + offset);
                    values[ivarName] = @(value);
                } else if (strcmp(type, @encode(float)) == 0) {
                    ptrdiff_t offset = ivar_getOffset(ivar);
                    float value = *(float *)((uint8_t *)(__bridge void *)object + offset);
                    values[ivarName] = @(value);
                } else if (strcmp(type, @encode(NSInteger)) == 0) {
                    ptrdiff_t offset = ivar_getOffset(ivar);
                    NSInteger value = *(NSInteger *)((uint8_t *)(__bridge void *)object + offset);
                    values[ivarName] = @(value);
                } else if (strcmp(type, @encode(NSUInteger)) == 0) {
                    ptrdiff_t offset = ivar_getOffset(ivar);
                    NSUInteger value = *(NSUInteger *)((uint8_t *)(__bridge void *)object + offset);
                    values[ivarName] = @(value);
                } else if (strcmp(type, @encode(int)) == 0) {
                    ptrdiff_t offset = ivar_getOffset(ivar);
                    int value = *(int *)((uint8_t *)(__bridge void *)object + offset);
                    values[ivarName] = @(value);
                } else if (strcmp(type, @encode(long long)) == 0) {
                    ptrdiff_t offset = ivar_getOffset(ivar);
                    long long value = *(long long *)((uint8_t *)(__bridge void *)object + offset);
                    values[ivarName] = @(value);
                } else if (strcmp(type, @encode(unsigned long long)) == 0) {
                    ptrdiff_t offset = ivar_getOffset(ivar);
                    unsigned long long value = *(unsigned long long *)((uint8_t *)(__bridge void *)object + offset);
                    values[ivarName] = @(value);
                }
            } @catch (NSException *exception) {
            }
        }
        free(ivarList);
        ivarClass = class_getSuperclass(ivarClass);
        ivarClassDepth++;
    }

    return [values copy];
}

- (NSDictionary *)searchPartyFetchContextDiagnosticsForContext:(id)context {
    if (context == nil || context == [NSNull null]) {
        return @{};
    }

    NSMutableDictionary *detail = [[NSMutableDictionary alloc] initWithDictionary:@{
        @"context_class": [self classNameForObject:context],
        @"context_id": [NSString stringWithFormat:@"%p", context],
        @"context_summary": [self summaryForValue:context],
    }];

    NSArray *arraySelectors = @[
        @"searchIdentifiers",
        @"searchTypes",
        @"searchPriority",
        @"searchLocationSources",
    ];
    for (NSString *selectorName in arraySelectors) {
        id value = [self safeObjectValueFromObject:context selectorName:selectorName];
        NSArray *children = [self objectChildrenForValue:value];
        NSMutableArray *sample = [[NSMutableArray alloc] init];
        for (id child in children) {
            if (sample.count >= 12) {
                break;
            }
            NSMutableDictionary *entry = [[NSMutableDictionary alloc] initWithDictionary:@{
                @"class": [self classNameForObject:child],
                @"summary": [self summaryForValue:child],
            }];
            NSString *stringValue = [self stringValueForFindMyValue:child] ?: [child description];
            if (stringValue.length > 0) {
                entry[@"value"] = stringValue.length > 240 ? [stringValue substringToIndex:240] : stringValue;
            }
            [sample addObject:[entry copy]];
        }
        detail[[NSString stringWithFormat:@"%@_class", selectorName]] = [self classNameForObject:value];
        detail[[NSString stringWithFormat:@"%@_summary", selectorName]] = [self summaryForValue:value];
        detail[[NSString stringWithFormat:@"%@_count", selectorName]] = @(children.count);
        detail[[NSString stringWithFormat:@"%@_sample", selectorName]] = sample;
    }

    for (NSString *selectorName in @[@"cachePolicy", @"bundleIdentifier"]) {
        id value = [self safeObjectValueFromObject:context selectorName:selectorName];
        if (value != nil && value != [NSNull null]) {
            detail[selectorName] = @{
                @"class": [self classNameForObject:value],
                @"summary": [self summaryForValue:value],
                @"value": [self stringValueForFindMyValue:value] ?: [value description] ?: @"<nil>",
            };
        }
    }

    for (NSString *selectorName in @[@"subscribe", @"reportDeviceEvents"]) {
        id value = [self safeJSONValueFromObject:context zeroArgumentSelectorName:selectorName];
        if (value != nil && value != [NSNull null]) {
            detail[selectorName] = value;
        }
    }

    SEL primaryIndexRangeSelector = NSSelectorFromString(@"primaryIndexRange");
    if ([context respondsToSelector:primaryIndexRangeSelector]) {
        NSMethodSignature *signature = [context methodSignatureForSelector:primaryIndexRangeSelector];
        const char *returnType = signature == nil ? NULL : signature.methodReturnType;
        if (returnType != NULL && strstr(returnType, "NSRange") != NULL) {
            @try {
                NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                [invocation setTarget:context];
                [invocation setSelector:primaryIndexRangeSelector];
                [invocation invoke];
                NSRange range = NSMakeRange(0, 0);
                [invocation getReturnValue:&range];
                detail[@"primaryIndexRange"] = @{
                    @"location": @(range.location),
                    @"length": @(range.length),
                };
            } @catch (NSException *exception) {
            }
        }
    }

    id lastOnlineInfo = [self safeObjectValueFromObject:context selectorName:@"lastOnlineLocationInfo"];
    detail[@"lastOnlineLocationInfo_class"] = [self classNameForObject:lastOnlineInfo];
    detail[@"lastOnlineLocationInfo_summary"] = [self summaryForValue:lastOnlineInfo];
    if ([lastOnlineInfo isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = (NSDictionary *)lastOnlineInfo;
        NSMutableArray *entries = [[NSMutableArray alloc] init];
        for (id key in dictionary.allKeys) {
            if (entries.count >= 5) {
                break;
            }
            id value = dictionary[key];
            NSMutableDictionary *entry = [[NSMutableDictionary alloc] initWithDictionary:@{
                @"key_class": [self classNameForObject:key],
                @"key": [self normalizedSearchPartyIdentifierString:key] ?: [key description] ?: @"<nil>",
                @"value_class": [self classNameForObject:value],
                @"value_summary": [self summaryForValue:value],
            }];
            NSString *description = [value description];
            if (description.length > 0) {
                entry[@"value_description"] = description.length > 240 ? [description substringToIndex:240] : description;
            }
            NSDictionary *accessors = [self searchPartyLocationInfoAccessorValuesForObject:value];
            if (accessors.count > 0) {
                entry[@"accessors"] = accessors;
            }
            NSDictionary *ivars = [self searchPartyLocationInfoIvarValuesForObject:value];
            if (ivars.count > 0) {
                entry[@"ivars"] = ivars;
            }
            NSDictionary *location = [self serializeLocationObject:value];
            if (location != (NSDictionary *)[NSNull null]) {
                entry[@"location"] = location;
            }
            [entries addObject:[entry copy]];
        }
        detail[@"lastOnlineLocationInfo_count"] = @(dictionary.count);
        detail[@"lastOnlineLocationInfo_entries_sample"] = entries;
    }

    return [detail copy];
}

- (NSDictionary *)searchPartyLastOnlineInfoSummaryForBeacons:(NSArray *)beacons context:(id)context {
    id lastOnlineInfo = [self safeObjectValueFromObject:context selectorName:@"lastOnlineLocationInfo"];
    id searchTypes = [self safeObjectValueFromObject:context selectorName:@"searchTypes"];
    id searchLocationSources = [self safeObjectValueFromObject:context selectorName:@"searchLocationSources"];

    NSMutableDictionary *summary = [[NSMutableDictionary alloc] initWithDictionary:@{
        @"context_class": [self classNameForObject:context],
        @"last_online_class": [self classNameForObject:lastOnlineInfo],
        @"last_online_summary": [self summaryForValue:lastOnlineInfo],
        @"search_types_summary": [self summaryForValue:searchTypes],
        @"search_location_sources_summary": [self summaryForValue:searchLocationSources],
    }];

    if (![lastOnlineInfo isKindOfClass:[NSDictionary class]]) {
        return [summary copy];
    }

    NSDictionary *lastOnlineDictionary = (NSDictionary *)lastOnlineInfo;
    NSMutableDictionary *lastOnlineByKey = [[NSMutableDictionary alloc] init];
    for (id key in lastOnlineDictionary.allKeys) {
        NSString *normalized = [self normalizedSearchPartyIdentifierString:key];
        if (normalized.length > 0) {
            lastOnlineByKey[normalized] = lastOnlineDictionary[key];
        }
    }

    NSMutableArray *matches = [[NSMutableArray alloc] init];
    NSMutableArray *unmatchedNamedBeacons = [[NSMutableArray alloc] init];
    for (id beacon in beacons ?: @[]) {
        NSString *name = [[self firstObjectValueFromObject:beacon
                                                      keys:@[@"name", @"displayName", @"accessoryName"]
                                                 selectors:@[@"name", @"displayName", @"accessoryName"]] description];
        NSArray *candidateIdentifiers = [self searchPartyIdentifierCandidatesForBeacon:beacon];
        id matchedKey = nil;
        id matchedValue = nil;
        for (NSString *candidate in candidateIdentifiers) {
            id value = lastOnlineByKey[candidate];
            if (value != nil) {
                matchedKey = candidate;
                matchedValue = value;
                break;
            }
        }

        if (matchedValue == nil) {
            if (name.length > 0 && unmatchedNamedBeacons.count < 20) {
                [unmatchedNamedBeacons addObject:@{
                    @"name": name,
                    @"identifier_candidates": candidateIdentifiers ?: @[],
                }];
            }
            continue;
        }

        NSMutableDictionary *match = [[NSMutableDictionary alloc] initWithDictionary:@{
            @"name": name.length > 0 ? name : @"<nil>",
            @"matched_key": matchedKey ?: @"<nil>",
            @"identifier_candidates": candidateIdentifiers ?: @[],
            @"beacon_class": [self classNameForObject:beacon] ?: @"<nil>",
            @"beacon_summary": [self summaryForValue:beacon],
            @"beacon_serialized": [self serializeOwnerBeacon:beacon],
            @"last_online_class": [self classNameForObject:matchedValue],
            @"last_online_summary": [self summaryForValue:matchedValue],
            @"last_online_detail": [self searchPartyLocationProbeResultForSelector:@"SPLastOnlineLocationInfo" result:matchedValue],
        }];

        NSDictionary *beaconLocation = [self serializeLocationObject:beacon];
        if (beaconLocation != (NSDictionary *)[NSNull null]) {
            match[@"beacon_location"] = beaconLocation;
        }
        NSDictionary *beaconFields = [self directFindMyFieldsForObject:beacon];
        if (beaconFields.count > 0) {
            match[@"beacon_fields"] = beaconFields;
        }
        NSDictionary *beaconAccessors = [self searchPartyLocationInfoAccessorValuesForObject:beacon];
        if (beaconAccessors.count > 0) {
            match[@"beacon_accessors"] = beaconAccessors;
        }
        NSDictionary *beaconIvars = [self searchPartyLocationInfoIvarValuesForObject:beacon];
        if (beaconIvars.count > 0) {
            match[@"beacon_ivars"] = beaconIvars;
        }
        NSDictionary *location = [self serializeLocationObject:matchedValue];
        if (location != (NSDictionary *)[NSNull null]) {
            match[@"location"] = location;
        }
        NSDictionary *fields = [self directFindMyFieldsForObject:matchedValue];
        if (fields.count > 0) {
            match[@"fields"] = fields;
        }
        NSDictionary *accessorValues = [self searchPartyLocationInfoAccessorValuesForObject:matchedValue];
        if (accessorValues.count > 0) {
            match[@"last_online_accessors"] = accessorValues;
        }
        NSDictionary *ivarValues = [self searchPartyLocationInfoIvarValuesForObject:matchedValue];
        if (ivarValues.count > 0) {
            match[@"last_online_ivars"] = ivarValues;
        }
        NSString *description = [matchedValue description];
        if (description.length > 0) {
            match[@"last_online_description"] = description.length > 240 ? [description substringToIndex:240] : description;
        }
        [matches addObject:[match copy]];
        if (matches.count >= 40) {
            break;
        }
    }

    summary[@"matched_beacon_count"] = @(matches.count);
    summary[@"matches"] = [matches copy];
    summary[@"unmatched_named_beacons_sample"] = [unmatchedNamedBeacons copy];
    return [summary copy];
}

- (void)handleFindMySearchPartyLocationProbeStartWithTransaction:(NSString *)transaction {
    [self handleFindMySearchPartyLocationProbeStartWithTransaction:transaction focusedStep:0];
}

- (void)handleFindMySearchPartyDelegatedCheckpointWithTransaction:(NSString *)transaction checkpoint:(NSString *)checkpoint {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleFindMySearchPartyDelegatedCheckpointWithTransaction:transaction checkpoint:checkpoint];
        });
        return;
    }

    NSArray *capturedSessions = [self capturedSearchPartyOwnerSessions];
    id targetSession = nil;
    NSString *targetSessionIdentifier = nil;
    for (NSDictionary *entry in capturedSessions) {
        id session = entry[@"object"];
        if (session != nil && session != [NSNull null]) {
            targetSession = session;
            targetSessionIdentifier = entry[@"object_id"];
            break;
        }
    }

    NSString *probeId = [[NSUUID UUID] UUIDString];
    NSMutableDictionary *probe = [[NSMutableDictionary alloc] initWithDictionary:@{
        @"probe_id": probeId,
        @"status": targetSession == nil ? @"unavailable" : @"started",
        @"started_at": @([[NSDate date] timeIntervalSince1970]),
        @"delegated_checkpoint": checkpoint ?: @"<nil>",
        @"captured_owner_session_count": @(capturedSessions.count),
        @"session_id": targetSessionIdentifier ?: [NSNull null],
        @"note": @"Checkpoint delegated probe bypasses shared location probe setup. Each route call performs exactly one small operation.",
    }];
    [self storeFindMySearchPartyLocationProbe:probe];

    if (targetSession == nil) {
        probe[@"error"] = @"No captured SPOwnerSession is available";
        probe[@"status"] = @"completed";
        probe[@"completed_at"] = @([[NSDate date] timeIntervalSince1970]);
        [self storeFindMySearchPartyLocationProbe:probe];
        [[NetworkController sharedInstance] sendMessage:@{
            @"transactionId": transaction ?: [NSNull null],
            @"location_probe": [self findMySearchPartyLocationProbeStatus],
        }];
        return;
    }

    DLog("BLUEBUBBLESHELPER: Delegated checkpoint starting: %{public}@", checkpoint ?: @"<nil>");

    NSArray *delegatedSelectors = @[
        @"delegatedLocationForContext:completion:",
        @"subscribeDelegatedLocationUpdatesForContext:completion:",
    ];
    void (^appendResponds)(NSMutableDictionary *, NSString *, id) = ^(NSMutableDictionary *target, NSString *prefix, id object) {
        NSMutableDictionary *values = [[NSMutableDictionary alloc] init];
        for (NSString *selectorName in delegatedSelectors) {
            SEL selector = NSSelectorFromString(selectorName);
            values[selectorName] = @([object respondsToSelector:selector]);
        }
        target[prefix] = values;
    };
    void (^appendSignatures)(NSMutableDictionary *, NSString *, id) = ^(NSMutableDictionary *target, NSString *prefix, id object) {
        NSMutableDictionary *values = [[NSMutableDictionary alloc] init];
        for (NSString *selectorName in delegatedSelectors) {
            SEL selector = NSSelectorFromString(selectorName);
            NSMethodSignature *signature = [object methodSignatureForSelector:selector];
            values[selectorName] = signature == nil ? @"<nil>" : [NSString stringWithFormat:@"args=%lu return=%s", (unsigned long)signature.numberOfArguments, signature.methodReturnType];
        }
        target[prefix] = values;
    };

    if ([checkpoint isEqualToString:@"session"]) {
        probe[@"session_class"] = [self classNameForObject:targetSession] ?: @"<nil>";
    } else if ([checkpoint isEqualToString:@"location-fetch"]) {
        id locationFetch = [self safeObjectValueFromObject:targetSession selectorName:@"locationFetch"];
        probe[@"location_fetch_class"] = [self classNameForObject:locationFetch] ?: @"<nil>";
        probe[@"location_fetch_id"] = locationFetch == nil ? @"<nil>" : [NSString stringWithFormat:@"%p", locationFetch];
    } else if ([checkpoint isEqualToString:@"proxy"]) {
        id ownerProxy = [self safeObjectValueFromObject:targetSession selectorName:@"proxy"] ?: [self safeObjectValueFromObject:targetSession selectorName:@"_proxy"];
        probe[@"proxy_class"] = [self classNameForObject:ownerProxy] ?: @"<nil>";
        probe[@"proxy_id"] = ownerProxy == nil ? @"<nil>" : [NSString stringWithFormat:@"%p", ownerProxy];
    } else if ([checkpoint isEqualToString:@"responds-owner"]) {
        appendResponds(probe, @"owner_responds", targetSession);
    } else if ([checkpoint isEqualToString:@"responds-location-fetch"]) {
        id locationFetch = [self safeObjectValueFromObject:targetSession selectorName:@"locationFetch"];
        probe[@"location_fetch_class"] = [self classNameForObject:locationFetch] ?: @"<nil>";
        appendResponds(probe, @"location_fetch_responds", locationFetch);
    } else if ([checkpoint isEqualToString:@"responds-proxy"]) {
        id ownerProxy = [self safeObjectValueFromObject:targetSession selectorName:@"proxy"] ?: [self safeObjectValueFromObject:targetSession selectorName:@"_proxy"];
        probe[@"proxy_class"] = [self classNameForObject:ownerProxy] ?: @"<nil>";
        appendResponds(probe, @"proxy_responds", ownerProxy);
    } else if ([checkpoint isEqualToString:@"signature-owner"]) {
        appendSignatures(probe, @"owner_signatures", targetSession);
    } else if ([checkpoint isEqualToString:@"signature-location-fetch"]) {
        id locationFetch = [self safeObjectValueFromObject:targetSession selectorName:@"locationFetch"];
        probe[@"location_fetch_class"] = [self classNameForObject:locationFetch] ?: @"<nil>";
        appendSignatures(probe, @"location_fetch_signatures", locationFetch);
    } else if ([checkpoint isEqualToString:@"signature-proxy"]) {
        id ownerProxy = [self safeObjectValueFromObject:targetSession selectorName:@"proxy"] ?: [self safeObjectValueFromObject:targetSession selectorName:@"_proxy"];
        probe[@"proxy_class"] = [self classNameForObject:ownerProxy] ?: @"<nil>";
        appendSignatures(probe, @"proxy_signatures", ownerProxy);
    } else if ([checkpoint isEqualToString:@"captured-context"]) {
        id capturedContext = nil;
        @synchronized ([BlueBubblesHelper class]) {
            capturedContext = findMyCapturedSearchPartyLocationContext;
        }
        probe[@"captured_context_class"] = [self classNameForObject:capturedContext] ?: @"<nil>";
        probe[@"captured_context_id"] = capturedContext == nil ? @"<nil>" : [NSString stringWithFormat:@"%p", capturedContext];
        probe[@"captured_context_summary"] = [self summaryForValue:capturedContext];
    } else if ([checkpoint isEqualToString:@"captured-context-detail"]) {
        id capturedContext = nil;
        @synchronized ([BlueBubblesHelper class]) {
            capturedContext = findMyCapturedSearchPartyLocationContext;
        }
        probe[@"captured_context_class"] = [self classNameForObject:capturedContext] ?: @"<nil>";
        probe[@"captured_context_detail"] = [self searchPartyFetchContextDiagnosticsForContext:capturedContext];
    } else if ([checkpoint isEqualToString:@"owner-last-context"]) {
        id ownerLastContext = [self safeObjectValueFromObject:targetSession selectorName:@"lastContext"];
        probe[@"owner_last_context_class"] = [self classNameForObject:ownerLastContext] ?: @"<nil>";
        probe[@"owner_last_context_id"] = ownerLastContext == nil ? @"<nil>" : [NSString stringWithFormat:@"%p", ownerLastContext];
        probe[@"owner_last_context_summary"] = [self summaryForValue:ownerLastContext];
    } else if ([checkpoint isEqualToString:@"location-fetch-last-context"]) {
        id locationFetch = [self safeObjectValueFromObject:targetSession selectorName:@"locationFetch"];
        id locationFetchLastContext = [self safeObjectValueFromObject:locationFetch selectorName:@"lastContext"];
        probe[@"location_fetch_class"] = [self classNameForObject:locationFetch] ?: @"<nil>";
        probe[@"location_fetch_last_context_class"] = [self classNameForObject:locationFetchLastContext] ?: @"<nil>";
        probe[@"location_fetch_last_context_id"] = locationFetchLastContext == nil ? @"<nil>" : [NSString stringWithFormat:@"%p", locationFetchLastContext];
        probe[@"location_fetch_last_context_detail"] = [self searchPartyFetchContextDiagnosticsForContext:locationFetchLastContext];
    } else if ([checkpoint isEqualToString:@"beacon-last-online-correlation"]) {
        id capturedContext = nil;
        @synchronized ([BlueBubblesHelper class]) {
            capturedContext = findMyCapturedSearchPartyLocationContext;
        }
        id cachedBeacons = [self safeObjectValueFromObject:targetSession selectorName:@"allBeacons"] ?: [self safeObjectValueFromObject:targetSession selectorName:@"allBeaconsCache"];
        NSArray *beacons = [self objectChildrenForValue:cachedBeacons];
        id lastOnlineInfo = [self safeObjectValueFromObject:capturedContext selectorName:@"lastOnlineLocationInfo"];
        NSMutableArray *lastOnlineKeys = [[NSMutableArray alloc] init];
        if ([lastOnlineInfo isKindOfClass:[NSDictionary class]]) {
            for (id key in [(NSDictionary *)lastOnlineInfo allKeys]) {
                NSString *normalized = [self normalizedSearchPartyIdentifierString:key];
                if (normalized.length > 0) {
                    [lastOnlineKeys addObject:normalized];
                }
            }
            [lastOnlineKeys sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        }
        probe[@"captured_context_class"] = [self classNameForObject:capturedContext] ?: @"<nil>";
        probe[@"beacon_cache_class"] = [self classNameForObject:cachedBeacons] ?: @"<nil>";
        probe[@"beacon_cache_summary"] = [self summaryForValue:cachedBeacons];
        probe[@"beacon_count"] = @(beacons.count);
        probe[@"last_online_info_class"] = [self classNameForObject:lastOnlineInfo] ?: @"<nil>";
        probe[@"last_online_key_count"] = @(lastOnlineKeys.count);
        probe[@"last_online_keys"] = [lastOnlineKeys copy];
        probe[@"beacon_last_online_correlation"] = [self searchPartyLastOnlineInfoSummaryForBeacons:beacons context:capturedContext];
        probe[@"beacon_summaries_sample"] = [self compactBeaconSummariesForBeacons:beacons];
    } else if ([checkpoint isEqualToString:@"owner-location-graph"]) {
        id cachedBeacons = [self safeObjectValueFromObject:targetSession selectorName:@"allBeacons"] ?: [self safeObjectValueFromObject:targetSession selectorName:@"allBeaconsCache"];
        NSArray *beacons = [self objectChildrenForValue:cachedBeacons];
        NSMutableArray *samples = [[NSMutableArray alloc] init];
        for (id beacon in beacons) {
            if (samples.count >= 24) {
                break;
            }
            id safeLocations = [self safeObjectValueFromObject:beacon selectorName:@"safeLocations"] ?: [self safeValueForKey:@"safeLocations" object:beacon];
            NSArray *safeLocationSnapshots = [self searchPartyLocationBearingChildSnapshotsForValue:safeLocations];
            if (safeLocationSnapshots.count == 0) {
                continue;
            }
            NSString *name = [[self firstObjectValueFromObject:beacon
                                                          keys:@[@"name", @"displayName", @"accessoryName"]
                                                     selectors:@[@"name", @"displayName", @"accessoryName"]] description];
            [samples addObject:@{
                @"name": name.length > 0 ? name : @"<nil>",
                @"identifier_candidates": [self searchPartyIdentifierCandidatesForBeacon:beacon] ?: @[],
                @"safe_locations_class": [self classNameForObject:safeLocations] ?: @"<nil>",
                @"safe_locations_summary": [self summaryForValue:safeLocations],
                @"safe_locations": safeLocationSnapshots,
            }];
        }
        probe[@"owner_location_graph"] = @{
            @"mode": @"cached_beacon_safe_location_sample",
            @"beacon_cache_class": [self classNameForObject:cachedBeacons] ?: @"<nil>",
            @"beacon_count": @(beacons.count),
            @"safe_location_sample_count": @(samples.count),
            @"safe_location_samples": samples,
            @"note": @"The original recursive owner-location graph scan timed out. This checkpoint is intentionally shallow and only samples cached SPBeacon.safeLocations without touching proxy/XPC paths.",
        };
    } else {
        probe[@"error"] = [NSString stringWithFormat:@"Unknown delegated checkpoint: %@", checkpoint ?: @"<nil>"];
    }

    probe[@"status"] = @"completed";
    probe[@"pending_completion_count"] = @0;
    probe[@"completed_at"] = @([[NSDate date] timeIntervalSince1970]);
    [self storeFindMySearchPartyLocationProbe:probe];
    [[NetworkController sharedInstance] sendMessage:@{
        @"transactionId": transaction ?: [NSNull null],
        @"location_probe": [self findMySearchPartyLocationProbeStatus],
    }];
}

- (void)handleFindMySearchPartyLocationProbeStartWithTransaction:(NSString *)transaction focusedStep:(NSUInteger)requestedFocusedStep {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleFindMySearchPartyLocationProbeStartWithTransaction:transaction focusedStep:requestedFocusedStep];
        });
        return;
    }

    [self installFindMySwizzles];

    NSArray *capturedSessions = [self capturedSearchPartyOwnerSessions];
    id targetSession = nil;
    NSString *targetSessionIdentifier = nil;
    for (NSDictionary *entry in capturedSessions) {
        id session = entry[@"object"];
        if (session != nil && session != [NSNull null]) {
            targetSession = session;
            targetSessionIdentifier = entry[@"object_id"];
            break;
        }
    }

    NSString *probeId = [[NSUUID UUID] UUIDString];
    NSMutableDictionary *startedProbe = [[NSMutableDictionary alloc] initWithDictionary:@{
        @"probe_id": probeId,
        @"status": targetSession == nil ? @"unavailable" : @"started",
        @"started_at": @([[NSDate date] timeIntervalSince1970]),
        @"captured_owner_session_count": @(capturedSessions.count),
        @"session_id": targetSessionIdentifier ?: [NSNull null],
    }];

    if (targetSession == nil) {
        startedProbe[@"error"] = @"No captured SPOwnerSession is available";
        [self storeFindMySearchPartyLocationProbe:startedProbe];
        [[NetworkController sharedInstance] sendMessage:@{
            @"transactionId": transaction ?: [NSNull null],
            @"location_probe": [self findMySearchPartyLocationProbeStatus],
        }];
        return;
    }

    if (requestedFocusedStep == 15) {
        startedProbe[@"dedicated_probe"] = @YES;
        startedProbe[@"focused_probe_step"] = @15;
        startedProbe[@"status"] = @"completed";
        startedProbe[@"pending_completion_count"] = @0;
        startedProbe[@"called_start_refreshing"] = @NO;
        startedProbe[@"completed_at"] = @([[NSDate date] timeIntervalSince1970]);
        startedProbe[@"delegated_watch_note"] = @"Minimal delegated inspection only: confirms a captured SPOwnerSession is available without startRefreshing, method-surface enumeration, selector swizzling, proxy inspection, or delegated invocation. The fuller delegated-watch setup crashed Find My before probe state could be stored.";
        [self storeFindMySearchPartyLocationProbe:startedProbe];
        [[NetworkController sharedInstance] sendMessage:@{
            @"transactionId": transaction ?: [NSNull null],
            @"location_probe": [self findMySearchPartyLocationProbeStatus],
        }];
        return;
    }

    if (requestedFocusedStep != 15 && [targetSession respondsToSelector:NSSelectorFromString(@"startRefreshing")]) {
        [self objectValueFromObject:targetSession selector:NSSelectorFromString(@"startRefreshing")];
        startedProbe[@"called_start_refreshing"] = @YES;
    } else if (requestedFocusedStep == 15) {
        startedProbe[@"called_start_refreshing"] = @NO;
        startedProbe[@"start_refreshing_note"] = @"Skipped for delegated-watch inspection because the route should not trigger SearchParty refresh behavior before storing diagnostics.";
    }

    NSUInteger focusedProbeStep = 0;
    if (requestedFocusedStep >= 1 && requestedFocusedStep <= 16) {
        focusedProbeStep = requestedFocusedStep;
        startedProbe[@"dedicated_probe"] = @YES;
    } else {
        @synchronized ([BlueBubblesHelper class]) {
            NSUInteger focusedProbeSteps[] = {4, 3, 1, 2};
            focusedProbeStep = focusedProbeSteps[findMySearchPartyLocationProbeStepIndex % 4];
            findMySearchPartyLocationProbeStepIndex += 1;
        }
        startedProbe[@"dedicated_probe"] = @NO;
    }

    NSString *focusedProbeSelector = @"SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.singleIdentifier";
    if (focusedProbeStep == 2) {
        focusedProbeSelector = @"SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.exactContextArguments";
    } else if (focusedProbeStep == 3) {
        focusedProbeSelector = @"SPOwnerSessionLocationFetch.controlledContext";
    } else if (focusedProbeStep == 4) {
        focusedProbeSelector = @"SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.sourceSubsets";
    } else if (focusedProbeStep == 5) {
        focusedProbeSelector = @"SPOwnerSessionXPCProtocol.requestLiveLocationForUUID.identifierVariants";
    } else if (focusedProbeStep == 6) {
        focusedProbeSelector = @"SPOwnerSessionXPCProtocol.identifierResolution";
    } else if (focusedProbeStep == 7) {
        focusedProbeSelector = @"SPOwnerSessionXPCProtocol.beaconForUUID.contextIdentifier";
    } else if (focusedProbeStep == 8) {
        focusedProbeSelector = @"SPOwnerSessionXPCProtocol.beaconForIdentifier.stableIdentifier";
    } else if (focusedProbeStep == 9) {
        focusedProbeSelector = @"SPOwnerSessionXPCProtocol.beaconForUUID.resolvedBeaconLocation";
    } else if (focusedProbeStep == 10) {
        focusedProbeSelector = @"SPOwnerSessionLocationFetch.contextSingleIdentifier";
    } else if (focusedProbeStep == 11) {
        focusedProbeSelector = @"SPOwnerSessionLocationFetch.singleIdentifierCallbackWatch";
    } else if (focusedProbeStep == 12) {
        focusedProbeSelector = @"SPOwnerSessionLocationFetch.fullContextCallbackWatch";
    } else if (focusedProbeStep == 13) {
        focusedProbeSelector = @"SPOwnerSessionLocationFetch.deviceEventCallbackWatch";
    } else if (focusedProbeStep == 14) {
        focusedProbeSelector = @"SPOwnerSessionXPCProtocol.delegatedLocationForContext";
    } else if (focusedProbeStep == 15) {
        focusedProbeSelector = @"SPOwnerSessionXPCProtocol.delegatedLocationPassiveWatch";
    } else if (focusedProbeStep == 16) {
        focusedProbeSelector = @"SPOwnerSessionLocationFetch.lastOnlineIdentifiers";
    }

    NSArray *methods = [self searchPartyLocationMethodDiagnosticsForObject:targetSession];
    startedProbe[@"method_count"] = @(methods.count);
    startedProbe[@"lower_layer_classes_checked"] = @[
        @"SPLocationFetchContext",
        @"SPLocationFetchResult",
        @"SPOwnerSessionLocationFetch",
        @"SPDeviceEventFetchResult",
        @"FMXPCSession",
        @"SPBeaconManagerSimpleBeaconUpdateInterface",
        @"SPSimpleBeaconContext",
        @"FindMyLocateSession",
        @"FMFSession",
    ];

    NSMutableArray *accessorResults = [[NSMutableArray alloc] init];
    NSMutableArray *candidateCompletionSelectors = [[NSMutableArray alloc] init];
    for (NSDictionary *method in methods) {
        NSString *selectorName = method[@"selector"];
        NSNumber *argumentCount = method[@"argument_count"];
        NSString *returnType = method[@"return_type"];
        if (selectorName.length == 0) {
            continue;
        }
        SEL selector = NSSelectorFromString(selectorName);
        if ([argumentCount unsignedIntegerValue] == 2 && [returnType hasPrefix:@"@"] && accessorResults.count < 40) {
            id result = [self safeObjectValueFromObject:targetSession selectorName:selectorName];
            [accessorResults addObject:[self compactSearchPartyLocationProbeResultForSelector:selectorName result:result]];
        } else if ([selectorName rangeOfString:@"completion" options:NSCaseInsensitiveSearch].location != NSNotFound &&
                   [selectorName rangeOfString:@"location" options:NSCaseInsensitiveSearch].location != NSNotFound &&
                   candidateCompletionSelectors.count < 40 &&
                   [targetSession respondsToSelector:selector]) {
            [candidateCompletionSelectors addObject:selectorName];
        }
    }

    startedProbe[@"accessor_results"] = accessorResults;
    startedProbe[@"candidate_completion_selectors"] = candidateCompletionSelectors;
    startedProbe[@"focused_probe_step"] = @(focusedProbeStep);
    startedProbe[@"invoked_location_selectors"] = @[
        @"SPOwnerSession.locationsForBeacons:completion:",
        @"SPBeaconManagerSimpleBeaconUpdateInterface.startUpdatingSimpleBeaconsWithContext:completion:",
        focusedProbeSelector,
    ];
    startedProbe[@"pending_completion_count"] = focusedProbeStep == 15 ? @0 : (focusedProbeStep == 16 ? @6 : ((focusedProbeStep == 9 || focusedProbeStep == 10) ? @5 : ((focusedProbeStep == 11 || focusedProbeStep == 12 || focusedProbeStep == 13) ? @3 : ((focusedProbeStep == 5 || focusedProbeStep == 6) ? @6 : (focusedProbeStep == 3 ? @5 : (focusedProbeStep == 4 ? @6 : @3))))));
    [self storeFindMySearchPartyLocationProbe:startedProbe];

    id capturedLocationFetch = nil;
    id capturedLocationContext = nil;
    @synchronized ([BlueBubblesHelper class]) {
        capturedLocationFetch = findMyCapturedSearchPartyLocationFetch;
        capturedLocationContext = findMyCapturedSearchPartyLocationContext;
    }
    if (capturedLocationFetch != nil) {
        startedProbe[@"captured_location_fetch_summary"] = [self compactSearchPartyLocationProbeResultForSelector:@"SPOwnerSessionLocationFetch" result:capturedLocationFetch];
    }
    if (capturedLocationContext != nil) {
        startedProbe[@"captured_location_context_summary"] = [self compactSearchPartyLocationProbeResultForSelector:@"SPLocationFetchContext" result:capturedLocationContext];
    }

    if (focusedProbeStep == 15) {
        id ownerProxy = [self safeObjectValueFromObject:targetSession selectorName:@"proxy"] ?: [self safeObjectValueFromObject:targetSession selectorName:@"_proxy"];
        id locationFetch = capturedLocationFetch ?: [self safeObjectValueFromObject:targetSession selectorName:@"locationFetch"];
        NSMutableDictionary *delegatedWatchAvailability = [[NSMutableDictionary alloc] init];
        NSMutableDictionary *delegatedWatchSignatures = [[NSMutableDictionary alloc] init];

        for (NSString *selectorName in @[
            @"delegatedLocationForContext:completion:",
            @"subscribeDelegatedLocationUpdatesForContext:completion:",
        ]) {
            SEL selector = NSSelectorFromString(selectorName);
            delegatedWatchAvailability[[NSString stringWithFormat:@"ownerSession.%@", selectorName]] = @([targetSession respondsToSelector:selector]);
            delegatedWatchAvailability[[NSString stringWithFormat:@"locationFetch.%@", selectorName]] = @([locationFetch respondsToSelector:selector]);
            delegatedWatchAvailability[[NSString stringWithFormat:@"ownerProxy.%@", selectorName]] = @([ownerProxy respondsToSelector:selector]);

            NSMethodSignature *ownerSignature = [targetSession methodSignatureForSelector:selector];
            NSMethodSignature *locationFetchSignature = [locationFetch methodSignatureForSelector:selector];
            NSMethodSignature *proxySignature = [ownerProxy methodSignatureForSelector:selector];
            delegatedWatchSignatures[[NSString stringWithFormat:@"ownerSession.%@", selectorName]] = ownerSignature == nil ? @"<nil>" : [NSString stringWithFormat:@"args=%lu return=%s", (unsigned long)ownerSignature.numberOfArguments, ownerSignature.methodReturnType];
            delegatedWatchSignatures[[NSString stringWithFormat:@"locationFetch.%@", selectorName]] = locationFetchSignature == nil ? @"<nil>" : [NSString stringWithFormat:@"args=%lu return=%s", (unsigned long)locationFetchSignature.numberOfArguments, locationFetchSignature.methodReturnType];
            delegatedWatchSignatures[[NSString stringWithFormat:@"ownerProxy.%@", selectorName]] = proxySignature == nil ? @"<nil>" : [NSString stringWithFormat:@"args=%lu return=%s", (unsigned long)proxySignature.numberOfArguments, proxySignature.methodReturnType];
        }

        startedProbe[@"delegated_watch_method_availability"] = delegatedWatchAvailability;
        startedProbe[@"delegated_watch_method_signatures"] = delegatedWatchSignatures;
        startedProbe[@"delegated_watch_proxy_class"] = [self classNameForObject:ownerProxy] ?: @"<nil>";
        startedProbe[@"delegated_watch_location_fetch_class"] = [self classNameForObject:locationFetch] ?: @"<nil>";
        startedProbe[@"delegated_watch_note"] = @"Non-mutating delegated inspection: records delegated-location availability/signatures and calls startRefreshing, but does not swizzle or invoke delegatedLocationForContext:completion:. Swizzling delegated selectors crashed Find My before probe state could be stored.";
        startedProbe[@"status"] = @"observing";
        [self storeFindMySearchPartyLocationProbe:startedProbe];
        [[NetworkController sharedInstance] sendMessage:@{
            @"transactionId": transaction ?: [NSNull null],
            @"location_probe": [self findMySearchPartyLocationProbeStatus],
        }];
        return;
    }

    [self storeFindMySearchPartyLocationProbe:startedProbe];

    if (![targetSession respondsToSelector:NSSelectorFromString(@"allBeaconsWithCompletion:")] ||
        (![targetSession respondsToSelector:NSSelectorFromString(@"subscribeAndFetchLocationForContext:completion:")] &&
         ![capturedLocationFetch respondsToSelector:NSSelectorFromString(@"subscribeAndFetchLocationForContext:completion:")] &&
         ![[self safeObjectValueFromObject:targetSession selectorName:@"locationFetch"] respondsToSelector:NSSelectorFromString(@"subscribeAndFetchLocationForContext:completion:")])) {
        startedProbe[@"status"] = @"completed";
        startedProbe[@"completed_at"] = @([[NSDate date] timeIntervalSince1970]);
        startedProbe[@"pending_completion_count"] = @0;
        startedProbe[@"error"] = @"SPOwnerSession does not respond to allBeaconsWithCompletion: and subscribeAndFetchLocationForContext:completion:";
        [self storeFindMySearchPartyLocationProbe:startedProbe];
    } else {
        void (^appendProbeCompletion)(NSString *, id) = ^(NSString *selectorName, id result) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendFindMySearchPartyLocationProbeCompletionForProbeId:probeId
                                                                  selectorName:selectorName
                                                                        result:result];
            });
        };

        void (^locationForContextCompletion)(id) = ^(id result) {
            appendProbeCompletion(@"SPOwnerSessionLocationFetch.locationForContext:completion:", result);
        };

        void (^subscribeLocationsCompletion)(id) = ^(id result) {
            appendProbeCompletion(@"SPOwnerSessionLocationFetch.subscribeAndFetchLocationForContext:completion:", result);
        };

        void (^locationsForBeaconsCompletion)(id) = ^(id result) {
            appendProbeCompletion(@"SPOwnerSession.locationsForBeacons:completion:", result);
        };

        void (^simpleBeaconsCompletion)(id) = ^(id result) {
            appendProbeCompletion(@"SPBeaconManagerSimpleBeaconUpdateInterface.startUpdatingSimpleBeaconsWithContext:completion:", result);
        };

        void (^latestLocationsCompletion)(id) = ^(id result) {
            appendProbeCompletion(@"SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers:fetchLimit:sources:completion:", result);
        };

        void (^beaconsCompletion)(id) = ^(id beaconsResult) {
            dispatch_async(dispatch_get_main_queue(), ^{
                @synchronized ([BlueBubblesHelper class]) {
                    if (![findMySearchPartyLocationProbe[@"probe_id"] isEqualToString:probeId]) {
                        return;
                    }
                    if (findMySearchPartyLocationProbe[@"beacon_result_class"] != nil) {
                        return;
                    }
                    findMySearchPartyLocationProbe[@"beacon_result_class"] = [self classNameForObject:beaconsResult];
                    findMySearchPartyLocationProbe[@"beacon_result_summary"] = [self summaryForValue:beaconsResult];
                }

                NSArray *beacons = @[];
                if ([beaconsResult isKindOfClass:[NSArray class]]) {
                    beacons = beaconsResult;
                } else if ([beaconsResult isKindOfClass:[NSSet class]]) {
                    beacons = [(NSSet *)beaconsResult allObjects];
                }

                NSMutableSet *searchIdentifiers = [[NSMutableSet alloc] init];
                NSMutableSet *searchLocationSources = [[NSMutableSet alloc] init];
                for (id beacon in beacons) {
                    id identifier = [self directFindMyCandidateValueFromObject:beacon key:@"identifier"];
                    if (identifier != nil && identifier != [NSNull null]) {
                        [searchIdentifiers addObject:identifier];
                    }
                    id locationProviders = [self directFindMyCandidateValueFromObject:beacon key:@"locationProviders"];
                    if ([locationProviders isKindOfClass:[NSSet class]]) {
                        [searchLocationSources unionSet:locationProviders];
                    } else if ([locationProviders isKindOfClass:[NSArray class]]) {
                        [searchLocationSources addObjectsFromArray:locationProviders];
                    } else if (locationProviders != nil && locationProviders != [NSNull null]) {
                        [searchLocationSources addObject:locationProviders];
                    }
                }

                id locationFetch = capturedLocationFetch ?: [self safeObjectValueFromObject:targetSession selectorName:@"locationFetch"];
                id realLastContext = capturedLocationContext ?: [self safeObjectValueFromObject:locationFetch selectorName:@"lastContext"] ?: [self safeObjectValueFromObject:targetSession selectorName:@"lastContext"];
                id realSearchIdentifiers = [self safeObjectValueFromObject:realLastContext selectorName:@"searchIdentifiers"];
                id realSearchTypes = [self safeObjectValueFromObject:realLastContext selectorName:@"searchTypes"];
                id realSearchLocationSources = [self safeObjectValueFromObject:realLastContext selectorName:@"searchLocationSources"];
                id realLastOnlineInfo = [self safeObjectValueFromObject:realLastContext selectorName:@"lastOnlineLocationInfo"];
                NSDictionary *lastOnlineSummary = [self searchPartyLastOnlineInfoSummaryForBeacons:beacons context:realLastContext];

                NSArray *identifierArray = [searchIdentifiers allObjects];
                NSArray *realIdentifierArray = [self objectChildrenForValue:realSearchIdentifiers];
                id generatedSearchLocationSources = realSearchLocationSources ?: [searchLocationSources allObjects];
                NSArray *sourceArray = [self objectChildrenForValue:generatedSearchLocationSources];
                NSMutableArray *liveRequestCandidates = [[NSMutableArray alloc] init];
                NSMutableArray *identifierResolutionCandidates = [[NSMutableArray alloc] init];
                NSMutableArray *contextIdentifierUUIDCandidates = [[NSMutableArray alloc] init];
                NSMutableSet *seenLiveRequestIdentifiers = [[NSMutableSet alloc] init];
                NSMutableSet *seenResolutionIdentifiers = [[NSMutableSet alloc] init];
                NSMutableSet *seenContextIdentifierUUIDs = [[NSMutableSet alloc] init];
                for (id candidateIdentifier in realIdentifierArray) {
                    if (contextIdentifierUUIDCandidates.count >= 3) {
                        break;
                    }
                    NSUUID *uuidValue = nil;
                    if ([candidateIdentifier isKindOfClass:[NSUUID class]]) {
                        uuidValue = candidateIdentifier;
                    } else if ([candidateIdentifier isKindOfClass:[NSString class]]) {
                        uuidValue = [[NSUUID alloc] initWithUUIDString:candidateIdentifier];
                    }
                    NSString *normalizedUUID = [uuidValue UUIDString];
                    if (uuidValue == nil || normalizedUUID.length == 0 || [seenContextIdentifierUUIDs containsObject:normalizedUUID]) {
                        continue;
                    }
                    [seenContextIdentifierUUIDs addObject:normalizedUUID];
                    [contextIdentifierUUIDCandidates addObject:@{
                        @"variant": @"realSearchIdentifiers",
                        @"identifier": normalizedUUID,
                        @"name": @"<context>",
                        @"request_value": uuidValue,
                        @"request_value_class": [self classNameForObject:uuidValue],
                    }];
                }
                if (contextIdentifierUUIDCandidates.count == 0) {
                    for (id candidateIdentifier in identifierArray) {
                        if (contextIdentifierUUIDCandidates.count >= 3) {
                            break;
                        }
                        NSUUID *uuidValue = nil;
                        if ([candidateIdentifier isKindOfClass:[NSUUID class]]) {
                            uuidValue = candidateIdentifier;
                        } else if ([candidateIdentifier isKindOfClass:[NSString class]]) {
                            uuidValue = [[NSUUID alloc] initWithUUIDString:candidateIdentifier];
                        }
                        NSString *normalizedUUID = [uuidValue UUIDString];
                        if (uuidValue == nil || normalizedUUID.length == 0 || [seenContextIdentifierUUIDs containsObject:normalizedUUID]) {
                            continue;
                        }
                        [seenContextIdentifierUUIDs addObject:normalizedUUID];
                        [contextIdentifierUUIDCandidates addObject:@{
                            @"variant": @"generatedSearchIdentifiers",
                            @"identifier": normalizedUUID,
                            @"name": @"<generated>",
                            @"request_value": uuidValue,
                            @"request_value_class": [self classNameForObject:uuidValue],
                        }];
                    }
                }
                for (id beacon in beacons) {
                    if (liveRequestCandidates.count >= 4 && identifierResolutionCandidates.count >= 6) {
                        break;
                    }
                    NSString *name = [[self firstObjectValueFromObject:beacon
                                                                  keys:@[@"name", @"displayName", @"accessoryName"]
                                                             selectors:@[@"name", @"displayName", @"accessoryName"]] description];
                    NSDictionary *candidateMap = [self searchPartyIdentifierCandidateMapForBeacon:beacon];
                    for (NSString *variantKey in @[@"identifier", @"ownerBeaconIdentifier", @"stableIdentifier", @"uuid", @"beaconUUID", @"accessoryIdentifier", @"productUUID", @"correlationIdentifier"]) {
                        if (liveRequestCandidates.count >= 4 && identifierResolutionCandidates.count >= 6) {
                            break;
                        }
                        NSString *normalized = candidateMap[variantKey];
                        if (normalized.length == 0) {
                            continue;
                        }
                        id rawValue = [self directFindMyCandidateValueFromObject:beacon key:variantKey];
                        id requestValue = rawValue;
                        if (![requestValue isKindOfClass:[NSUUID class]]) {
                            NSUUID *uuidValue = [[NSUUID alloc] initWithUUIDString:normalized];
                            requestValue = uuidValue ?: rawValue ?: normalized;
                        }
                        if (requestValue == nil || requestValue == [NSNull null]) {
                            continue;
                        }
                        NSDictionary *candidate = @{
                            @"variant": variantKey,
                            @"identifier": normalized,
                            @"name": name.length > 0 ? name : @"<nil>",
                            @"request_value": requestValue,
                            @"request_value_class": [self classNameForObject:requestValue],
                        };
                        if (liveRequestCandidates.count < 4 && ![seenLiveRequestIdentifiers containsObject:normalized]) {
                            [seenLiveRequestIdentifiers addObject:normalized];
                            [liveRequestCandidates addObject:candidate];
                        }
                        BOOL isStringIdentifier = [requestValue isKindOfClass:[NSString class]];
                        BOOL isUUIDIdentifier = [requestValue isKindOfClass:[NSUUID class]];
                        BOOL usefulResolutionVariant = [variantKey isEqualToString:@"stableIdentifier"] ||
                                                       [variantKey isEqualToString:@"identifier"] ||
                                                       [variantKey isEqualToString:@"productUUID"] ||
                                                       [variantKey isEqualToString:@"ownerBeaconIdentifier"] ||
                                                       [variantKey isEqualToString:@"beaconUUID"];
                        if (identifierResolutionCandidates.count < 6 &&
                            usefulResolutionVariant &&
                            (isStringIdentifier || isUUIDIdentifier) &&
                            ![seenResolutionIdentifiers containsObject:[NSString stringWithFormat:@"%@:%@", variantKey, normalized]]) {
                            [seenResolutionIdentifiers addObject:[NSString stringWithFormat:@"%@:%@", variantKey, normalized]];
                            [identifierResolutionCandidates addObject:candidate];
                        }
                    }
                }

                Class contextClass = NSClassFromString(@"SPLocationFetchContext");
                id context = contextClass == nil ? nil : [[contextClass alloc] init];
                [self setSafeValue:@"com.apple.findmy" forKey:@"bundleIdentifier" object:context];
                [self setSafeValue:realLastContext == nil ? @0 : @"foregroundRefresh" forKey:@"cachePolicy" object:context];
                [self setSafeValue:@YES forKey:@"subscribe" object:context];
                [self setSafeValue:@YES forKey:@"reportDeviceEvents" object:context];
                if (identifierArray.count > 0) {
                    [self setSafeValue:identifierArray forKey:@"searchIdentifiers" object:context];
                }
                if (realSearchTypes != nil && realSearchTypes != [NSNull null]) {
                    [self setSafeValue:realSearchTypes forKey:@"searchTypes" object:context];
                }
                if (realSearchLocationSources != nil && realSearchLocationSources != [NSNull null]) {
                    [self setSafeValue:realSearchLocationSources forKey:@"searchLocationSources" object:context];
                } else if (searchLocationSources.count > 0) {
                    [self setSafeValue:[searchLocationSources allObjects] forKey:@"searchLocationSources" object:context];
                }
                if (realLastOnlineInfo != nil && realLastOnlineInfo != [NSNull null]) {
                    [self setSafeValue:realLastOnlineInfo forKey:@"lastOnlineLocationInfo" object:context];
                }
                id contextSearchIdentifiersAfterKVC = [self safeObjectValueFromObject:context selectorName:@"searchIdentifiers"];
                id contextSearchLocationSourcesAfterKVC = [self safeObjectValueFromObject:context selectorName:@"searchLocationSources"];
                NSMutableDictionary *controlledContextAssignment = [[NSMutableDictionary alloc] initWithDictionary:@{
                    @"identifier_array_class": [self classNameForObject:identifierArray],
                    @"identifier_array_count": @(identifierArray.count),
                    @"source_argument_class": [self classNameForObject:generatedSearchLocationSources],
                    @"source_count": @(sourceArray.count),
                    @"search_identifiers_after_kvc_count": @([[self objectChildrenForValue:contextSearchIdentifiersAfterKVC] count]),
                    @"search_location_sources_after_kvc_count": @([[self objectChildrenForValue:contextSearchLocationSourcesAfterKVC] count]),
                }];
                if ([[self objectChildrenForValue:contextSearchIdentifiersAfterKVC] count] == 0 && identifierArray.count > 0) {
                    controlledContextAssignment[@"search_identifiers_ivar_write"] = @([self setSafeIvarObjectValue:identifierArray ivarName:@"_searchIdentifiers" object:context]);
                }
                if ([[self objectChildrenForValue:contextSearchLocationSourcesAfterKVC] count] == 0 && generatedSearchLocationSources != nil && generatedSearchLocationSources != [NSNull null]) {
                    controlledContextAssignment[@"search_location_sources_ivar_write"] = @([self setSafeIvarObjectValue:generatedSearchLocationSources ivarName:@"_searchLocationSources" object:context]);
                }
                if (identifierArray.count > 0) {
                    controlledContextAssignment[@"primary_index_range_ivar_write"] = @([self setSafeIvarRangeValue:NSMakeRange(0, identifierArray.count) ivarName:@"_primaryIndexRange" object:context]);
                }
                controlledContextAssignment[@"search_identifiers_final_count"] = @([[self objectChildrenForValue:[self safeObjectValueFromObject:context selectorName:@"searchIdentifiers"]] count]);
                controlledContextAssignment[@"search_location_sources_final_count"] = @([[self objectChildrenForValue:[self safeObjectValueFromObject:context selectorName:@"searchLocationSources"]] count]);

                id singleIdentifierContext = contextClass == nil ? nil : [[contextClass alloc] init];
                NSDictionary *singleIdentifierCandidate = contextIdentifierUUIDCandidates.count > 0 ? contextIdentifierUUIDCandidates[0] : nil;
                id singleIdentifierValue = singleIdentifierCandidate[@"request_value"];
                NSArray *singleIdentifierArray = singleIdentifierValue == nil ? @[] : @[singleIdentifierValue];
                [self setSafeValue:@"com.apple.findmy" forKey:@"bundleIdentifier" object:singleIdentifierContext];
                [self setSafeValue:realLastContext == nil ? @0 : @"foregroundRefresh" forKey:@"cachePolicy" object:singleIdentifierContext];
                [self setSafeValue:@YES forKey:@"subscribe" object:singleIdentifierContext];
                [self setSafeValue:@YES forKey:@"reportDeviceEvents" object:singleIdentifierContext];
                if (singleIdentifierArray.count > 0) {
                    [self setSafeValue:singleIdentifierArray forKey:@"searchIdentifiers" object:singleIdentifierContext];
                }
                if (realSearchTypes != nil && realSearchTypes != [NSNull null]) {
                    [self setSafeValue:realSearchTypes forKey:@"searchTypes" object:singleIdentifierContext];
                }
                if (realSearchLocationSources != nil && realSearchLocationSources != [NSNull null]) {
                    [self setSafeValue:realSearchLocationSources forKey:@"searchLocationSources" object:singleIdentifierContext];
                } else if (searchLocationSources.count > 0) {
                    [self setSafeValue:[searchLocationSources allObjects] forKey:@"searchLocationSources" object:singleIdentifierContext];
                }
                if (realLastOnlineInfo != nil && realLastOnlineInfo != [NSNull null]) {
                    [self setSafeValue:realLastOnlineInfo forKey:@"lastOnlineLocationInfo" object:singleIdentifierContext];
                }
                id singleContextIdentifiersAfterKVC = [self safeObjectValueFromObject:singleIdentifierContext selectorName:@"searchIdentifiers"];
                id singleContextSourcesAfterKVC = [self safeObjectValueFromObject:singleIdentifierContext selectorName:@"searchLocationSources"];
                NSMutableDictionary *singleIdentifierContextAssignment = [[NSMutableDictionary alloc] initWithDictionary:@{
                    @"argument": singleIdentifierCandidate == nil ? [NSNull null] : @{
                        @"variant": singleIdentifierCandidate[@"variant"] ?: @"<nil>",
                        @"identifier": singleIdentifierCandidate[@"identifier"] ?: @"<nil>",
                        @"name": singleIdentifierCandidate[@"name"] ?: @"<nil>",
                        @"request_value_class": singleIdentifierCandidate[@"request_value_class"] ?: @"<nil>",
                    },
                    @"search_identifiers_after_kvc_count": @([[self objectChildrenForValue:singleContextIdentifiersAfterKVC] count]),
                    @"search_location_sources_after_kvc_count": @([[self objectChildrenForValue:singleContextSourcesAfterKVC] count]),
                }];
                if ([[self objectChildrenForValue:singleContextIdentifiersAfterKVC] count] == 0 && singleIdentifierArray.count > 0) {
                    singleIdentifierContextAssignment[@"search_identifiers_ivar_write"] = @([self setSafeIvarObjectValue:singleIdentifierArray ivarName:@"_searchIdentifiers" object:singleIdentifierContext]);
                }
                if ([[self objectChildrenForValue:singleContextSourcesAfterKVC] count] == 0 && generatedSearchLocationSources != nil && generatedSearchLocationSources != [NSNull null]) {
                    singleIdentifierContextAssignment[@"search_location_sources_ivar_write"] = @([self setSafeIvarObjectValue:generatedSearchLocationSources ivarName:@"_searchLocationSources" object:singleIdentifierContext]);
                }
                if (singleIdentifierArray.count > 0) {
                    singleIdentifierContextAssignment[@"primary_index_range_ivar_write"] = @([self setSafeIvarRangeValue:NSMakeRange(0, singleIdentifierArray.count) ivarName:@"_primaryIndexRange" object:singleIdentifierContext]);
                }
                singleIdentifierContextAssignment[@"search_identifiers_final_count"] = @([[self objectChildrenForValue:[self safeObjectValueFromObject:singleIdentifierContext selectorName:@"searchIdentifiers"]] count]);
                singleIdentifierContextAssignment[@"search_location_sources_final_count"] = @([[self objectChildrenForValue:[self safeObjectValueFromObject:singleIdentifierContext selectorName:@"searchLocationSources"]] count]);

                NSMutableArray *lastOnlineIdentifierValues = [[NSMutableArray alloc] init];
                NSMutableArray *lastOnlineIdentifierStrings = [[NSMutableArray alloc] init];
                NSMutableSet *seenLastOnlineIdentifiers = [[NSMutableSet alloc] init];
                NSString *preferredLastOnlineIdentifier = @"243A7F6E-B4ED-481F-A2E0-54EF9AD6EDB6";
                NSMutableArray *lastOnlineKeys = [[NSMutableArray alloc] init];
                if ([realLastOnlineInfo isKindOfClass:[NSDictionary class]]) {
                    [lastOnlineKeys addObjectsFromArray:[(NSDictionary *)realLastOnlineInfo allKeys]];
                }
                [lastOnlineKeys sortUsingComparator:^NSComparisonResult(id a, id b) {
                    NSString *aString = [self normalizedSearchPartyIdentifierString:a] ?: [a description];
                    NSString *bString = [self normalizedSearchPartyIdentifierString:b] ?: [b description];
                    if ([aString isEqualToString:preferredLastOnlineIdentifier]) {
                        return NSOrderedAscending;
                    }
                    if ([bString isEqualToString:preferredLastOnlineIdentifier]) {
                        return NSOrderedDescending;
                    }
                    return [aString localizedCaseInsensitiveCompare:bString];
                }];
                for (id key in lastOnlineKeys) {
                    if (lastOnlineIdentifierValues.count >= 10) {
                        break;
                    }
                    NSUUID *uuidValue = nil;
                    if ([key isKindOfClass:[NSUUID class]]) {
                        uuidValue = key;
                    } else {
                        uuidValue = [[NSUUID alloc] initWithUUIDString:[key description]];
                    }
                    NSString *normalized = [uuidValue UUIDString];
                    if (uuidValue == nil || normalized.length == 0 || [seenLastOnlineIdentifiers containsObject:normalized]) {
                        continue;
                    }
                    [seenLastOnlineIdentifiers addObject:normalized];
                    [lastOnlineIdentifierValues addObject:uuidValue];
                    [lastOnlineIdentifierStrings addObject:normalized];
                }

                id lastOnlineContext = contextClass == nil ? nil : [[contextClass alloc] init];
                [self setSafeValue:@"com.apple.findmy" forKey:@"bundleIdentifier" object:lastOnlineContext];
                [self setSafeValue:realLastContext == nil ? @0 : @"foregroundRefresh" forKey:@"cachePolicy" object:lastOnlineContext];
                [self setSafeValue:@YES forKey:@"subscribe" object:lastOnlineContext];
                [self setSafeValue:@YES forKey:@"reportDeviceEvents" object:lastOnlineContext];
                if (lastOnlineIdentifierValues.count > 0) {
                    [self setSafeValue:lastOnlineIdentifierValues forKey:@"searchIdentifiers" object:lastOnlineContext];
                }
                if (realSearchTypes != nil && realSearchTypes != [NSNull null]) {
                    [self setSafeValue:realSearchTypes forKey:@"searchTypes" object:lastOnlineContext];
                }
                if (realSearchLocationSources != nil && realSearchLocationSources != [NSNull null]) {
                    [self setSafeValue:realSearchLocationSources forKey:@"searchLocationSources" object:lastOnlineContext];
                } else if (searchLocationSources.count > 0) {
                    [self setSafeValue:[searchLocationSources allObjects] forKey:@"searchLocationSources" object:lastOnlineContext];
                }
                if (realLastOnlineInfo != nil && realLastOnlineInfo != [NSNull null]) {
                    [self setSafeValue:realLastOnlineInfo forKey:@"lastOnlineLocationInfo" object:lastOnlineContext];
                }
                id lastOnlineContextIdentifiersAfterKVC = [self safeObjectValueFromObject:lastOnlineContext selectorName:@"searchIdentifiers"];
                id lastOnlineContextSourcesAfterKVC = [self safeObjectValueFromObject:lastOnlineContext selectorName:@"searchLocationSources"];
                NSMutableDictionary *lastOnlineContextAssignment = [[NSMutableDictionary alloc] initWithDictionary:@{
                    @"preferred_identifier": preferredLastOnlineIdentifier,
                    @"identifier_strings": [lastOnlineIdentifierStrings copy],
                    @"search_identifiers_after_kvc_count": @([[self objectChildrenForValue:lastOnlineContextIdentifiersAfterKVC] count]),
                    @"search_location_sources_after_kvc_count": @([[self objectChildrenForValue:lastOnlineContextSourcesAfterKVC] count]),
                }];
                if ([[self objectChildrenForValue:lastOnlineContextIdentifiersAfterKVC] count] == 0 && lastOnlineIdentifierValues.count > 0) {
                    lastOnlineContextAssignment[@"search_identifiers_ivar_write"] = @([self setSafeIvarObjectValue:lastOnlineIdentifierValues ivarName:@"_searchIdentifiers" object:lastOnlineContext]);
                }
                if ([[self objectChildrenForValue:lastOnlineContextSourcesAfterKVC] count] == 0 && generatedSearchLocationSources != nil && generatedSearchLocationSources != [NSNull null]) {
                    lastOnlineContextAssignment[@"search_location_sources_ivar_write"] = @([self setSafeIvarObjectValue:generatedSearchLocationSources ivarName:@"_searchLocationSources" object:lastOnlineContext]);
                }
                if (lastOnlineIdentifierValues.count > 0) {
                    lastOnlineContextAssignment[@"primary_index_range_ivar_write"] = @([self setSafeIvarRangeValue:NSMakeRange(0, lastOnlineIdentifierValues.count) ivarName:@"_primaryIndexRange" object:lastOnlineContext]);
                }
                lastOnlineContextAssignment[@"search_identifiers_final_count"] = @([[self objectChildrenForValue:[self safeObjectValueFromObject:lastOnlineContext selectorName:@"searchIdentifiers"]] count]);
                lastOnlineContextAssignment[@"search_location_sources_final_count"] = @([[self objectChildrenForValue:[self safeObjectValueFromObject:lastOnlineContext selectorName:@"searchLocationSources"]] count]);

                @synchronized ([BlueBubblesHelper class]) {
                    findMySearchPartyLocationProbe[@"real_last_context_summary"] = [self compactSearchPartyLocationProbeResultForSelector:@"SPLocationFetchContext.lastContext" result:realLastContext];
                    findMySearchPartyLocationProbe[@"real_last_online_info"] = lastOnlineSummary;
                    findMySearchPartyLocationProbe[@"context_summary"] = [self compactSearchPartyLocationProbeResultForSelector:@"SPLocationFetchContext" result:context];
                    findMySearchPartyLocationProbe[@"single_identifier_context_summary"] = [self compactSearchPartyLocationProbeResultForSelector:@"SPLocationFetchContext.singleIdentifier" result:singleIdentifierContext];
                    findMySearchPartyLocationProbe[@"last_online_context_summary"] = [self compactSearchPartyLocationProbeResultForSelector:@"SPLocationFetchContext.lastOnlineIdentifiers" result:lastOnlineContext];
                    findMySearchPartyLocationProbe[@"context_search_identifier_count"] = @(searchIdentifiers.count);
                    findMySearchPartyLocationProbe[@"context_search_location_source_count"] = realSearchLocationSources != nil ? @([[self objectChildrenForValue:realSearchLocationSources] count]) : @(searchLocationSources.count);
                    findMySearchPartyLocationProbe[@"context_report_device_events"] = @YES;
                    findMySearchPartyLocationProbe[@"controlled_context_assignment"] = controlledContextAssignment;
                    findMySearchPartyLocationProbe[@"single_identifier_context_assignment"] = singleIdentifierContextAssignment;
                    findMySearchPartyLocationProbe[@"last_online_context_assignment"] = lastOnlineContextAssignment;
                }

                id invocationTarget = locationFetch ?: targetSession;
                @try {
                    SEL locationsForBeaconsSelector = NSSelectorFromString(@"locationsForBeacons:completion:");
                    NSMethodSignature *locationsForBeaconsSignature = [targetSession methodSignatureForSelector:locationsForBeaconsSelector];
                    if (locationsForBeaconsSignature != nil && locationsForBeaconsSignature.numberOfArguments == 4) {
                        NSInvocation *locationsForBeaconsInvocation = [NSInvocation invocationWithMethodSignature:locationsForBeaconsSignature];
                        [locationsForBeaconsInvocation setTarget:targetSession];
                        [locationsForBeaconsInvocation setSelector:locationsForBeaconsSelector];
                        [locationsForBeaconsInvocation setArgument:&beacons atIndex:2];
                        [locationsForBeaconsInvocation setArgument:&locationsForBeaconsCompletion atIndex:3];
                        [locationsForBeaconsInvocation retainArguments];
                        [locationsForBeaconsInvocation invoke];
                    } else {
                        [self appendFindMySearchPartyLocationProbeCompletionForProbeId:probeId
                                                                          selectorName:@"SPOwnerSession.locationsForBeacons:completion:"
                                                                                result:nil];
                    }

                    id simpleBeaconInterface = [self safeObjectValueFromObject:targetSession selectorName:@"simpleBeaconUpdateInterface"];
                    id simpleBeaconContext = [self safeValueForKey:@"context" object:simpleBeaconInterface] ?: [self safeObjectValueFromObject:simpleBeaconInterface selectorName:@"context"];
                    SEL startSimpleBeaconsSelector = NSSelectorFromString(@"startUpdatingSimpleBeaconsWithContext:completion:");
                    NSMethodSignature *startSimpleBeaconsSignature = [simpleBeaconInterface methodSignatureForSelector:startSimpleBeaconsSelector];
                    @synchronized ([BlueBubblesHelper class]) {
                        findMySearchPartyLocationProbe[@"simple_beacon_interface_summary"] = [self compactSearchPartyLocationProbeResultForSelector:@"SPBeaconManagerSimpleBeaconUpdateInterface" result:simpleBeaconInterface];
                        findMySearchPartyLocationProbe[@"simple_beacon_context_summary"] = [self compactSearchPartyLocationProbeResultForSelector:@"SPSimpleBeaconContext" result:simpleBeaconContext];
                    }
                    if (simpleBeaconInterface != nil &&
                        simpleBeaconContext != nil &&
                        startSimpleBeaconsSignature != nil &&
                        startSimpleBeaconsSignature.numberOfArguments == 4) {
                        NSInvocation *simpleBeaconsInvocation = [NSInvocation invocationWithMethodSignature:startSimpleBeaconsSignature];
                        [simpleBeaconsInvocation setTarget:simpleBeaconInterface];
                        [simpleBeaconsInvocation setSelector:startSimpleBeaconsSelector];
                        [simpleBeaconsInvocation setArgument:&simpleBeaconContext atIndex:2];
                        [simpleBeaconsInvocation setArgument:&simpleBeaconsCompletion atIndex:3];
                        [simpleBeaconsInvocation retainArguments];
                        [simpleBeaconsInvocation invoke];
                    } else {
                        [self appendFindMySearchPartyLocationProbeCompletionForProbeId:probeId
                                                                          selectorName:@"SPBeaconManagerSimpleBeaconUpdateInterface.startUpdatingSimpleBeaconsWithContext:completion:"
                                                                                result:nil];
                    }

                    id ownerProxy = [self safeObjectValueFromObject:locationFetch selectorName:@"proxy"] ?: [self safeObjectValueFromObject:targetSession selectorName:@"proxy"];
                    SEL latestLocationsSelector = NSSelectorFromString(@"latestLocationsForIdentifiers:fetchLimit:sources:completion:");
                    NSMethodSignature *latestLocationsSignature = [ownerProxy methodSignatureForSelector:latestLocationsSelector];
                    if (ownerProxy != nil &&
                        latestLocationsSignature != nil &&
                        latestLocationsSignature.numberOfArguments == 6 &&
                        searchIdentifiers.count > 0) {
                        id generatedFetchLimit = @(identifierArray.count);
                        @synchronized ([BlueBubblesHelper class]) {
                            findMySearchPartyLocationProbe[@"latest_locations_proxy_summary"] = [self compactRelatedSearchPartyObject:ownerProxy matchingTerms:@[
                                @"location", @"locations", @"beacon", @"device", @"event", @"fetch", @"source"
                            ]];
                            findMySearchPartyLocationProbe[@"latest_locations_identifier_count"] = @(identifierArray.count);
                            findMySearchPartyLocationProbe[@"latest_locations_source_count"] = @(sourceArray.count);
                            findMySearchPartyLocationProbe[@"latest_locations_argument_classes"] = @{
                                @"generated_identifiers_class": [self classNameForObject:identifierArray],
                                @"generated_identifier_element_class": identifierArray.count > 0 ? [self classNameForObject:identifierArray[0]] : @"<nil>",
                                @"generated_identifier_set_class": [self classNameForObject:searchIdentifiers],
                                @"real_search_identifiers_class": [self classNameForObject:realSearchIdentifiers],
                                @"real_search_identifiers_count": @([[self objectChildrenForValue:realSearchIdentifiers] count]),
                                @"sources_argument_class": [self classNameForObject:generatedSearchLocationSources],
                                @"source_element_class": sourceArray.count > 0 ? [self classNameForObject:sourceArray[0]] : @"<nil>",
                                @"real_search_location_sources_class": [self classNameForObject:realSearchLocationSources],
                                @"fetch_limit_class": [self classNameForObject:generatedFetchLimit],
                            };
                        }

                        id firstIdentifier = identifierArray.count > 0 ? identifierArray[0] : nil;
                        if (focusedProbeStep == 1 && firstIdentifier != nil) {
                            NSArray *singleIdentifierArray = @[firstIdentifier];
                            id singleFetchLimit = @1;
                            void (^singleIdentifierCompletion)(id) = ^(id result) {
                                appendProbeCompletion(@"SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.singleIdentifier", result);
                            };
                            NSInvocation *singleIdentifierInvocation = [NSInvocation invocationWithMethodSignature:latestLocationsSignature];
                            [singleIdentifierInvocation setTarget:ownerProxy];
                            [singleIdentifierInvocation setSelector:latestLocationsSelector];
                            [singleIdentifierInvocation setArgument:&singleIdentifierArray atIndex:2];
                            [singleIdentifierInvocation setArgument:&singleFetchLimit atIndex:3];
                            [singleIdentifierInvocation setArgument:&generatedSearchLocationSources atIndex:4];
                            [singleIdentifierInvocation setArgument:&singleIdentifierCompletion atIndex:5];
                            [singleIdentifierInvocation retainArguments];
                            [singleIdentifierInvocation invoke];
                        } else if (focusedProbeStep == 1) {
                            appendProbeCompletion(@"SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.singleIdentifier", nil);
                        }

                        if (focusedProbeStep == 2) {
                            id exactIdentifiers = [[self objectChildrenForValue:realSearchIdentifiers] count] > 0 ? realSearchIdentifiers : searchIdentifiers;
                            id exactFetchLimit = @([[self objectChildrenForValue:exactIdentifiers] count]);
                            void (^exactContextArgumentsCompletion)(id) = ^(id result) {
                                appendProbeCompletion(@"SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.exactContextArguments", result);
                            };
                            NSInvocation *exactContextArgumentsInvocation = [NSInvocation invocationWithMethodSignature:latestLocationsSignature];
                            [exactContextArgumentsInvocation setTarget:ownerProxy];
                            [exactContextArgumentsInvocation setSelector:latestLocationsSelector];
                            [exactContextArgumentsInvocation setArgument:&exactIdentifiers atIndex:2];
                            [exactContextArgumentsInvocation setArgument:&exactFetchLimit atIndex:3];
                            [exactContextArgumentsInvocation setArgument:&generatedSearchLocationSources atIndex:4];
                            [exactContextArgumentsInvocation setArgument:&exactContextArgumentsCompletion atIndex:5];
                            [exactContextArgumentsInvocation retainArguments];
                            [exactContextArgumentsInvocation invoke];
                        }

                        if (focusedProbeStep == 4) {
                            NSUInteger sourceSubsetLimit = 4;
                            for (NSUInteger sourceIndex = 0; sourceIndex < sourceSubsetLimit; sourceIndex++) {
                                NSString *selectorLabel = [NSString stringWithFormat:@"SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.sourceSubset.%lu", (unsigned long)sourceIndex];
                                if (firstIdentifier == nil || sourceIndex >= sourceArray.count) {
                                    appendProbeCompletion(selectorLabel, nil);
                                    continue;
                                }

                                NSArray *singleIdentifierArray = @[firstIdentifier];
                                id singleFetchLimit = @1;
                                id sourceObject = sourceArray[sourceIndex];
                                NSArray *singleSourceArray = @[sourceObject];
                                void (^sourceSubsetCompletion)(id) = ^(id result) {
                                    appendProbeCompletion(selectorLabel, result);
                                };
                                NSInvocation *sourceSubsetInvocation = [NSInvocation invocationWithMethodSignature:latestLocationsSignature];
                                [sourceSubsetInvocation setTarget:ownerProxy];
                                [sourceSubsetInvocation setSelector:latestLocationsSelector];
                                [sourceSubsetInvocation setArgument:&singleIdentifierArray atIndex:2];
                                [sourceSubsetInvocation setArgument:&singleFetchLimit atIndex:3];
                                [sourceSubsetInvocation setArgument:&singleSourceArray atIndex:4];
                                [sourceSubsetInvocation setArgument:&sourceSubsetCompletion atIndex:5];
                                [sourceSubsetInvocation retainArguments];
                                [sourceSubsetInvocation invoke];
                                @synchronized ([BlueBubblesHelper class]) {
                                    NSMutableArray *sourceSubsetArguments = nil;
                                    id existingArguments = findMySearchPartyLocationProbe[@"latest_locations_source_subset_arguments"];
                                    if ([existingArguments isKindOfClass:[NSArray class]]) {
                                        sourceSubsetArguments = [[NSMutableArray alloc] initWithArray:existingArguments];
                                    } else {
                                        sourceSubsetArguments = [[NSMutableArray alloc] init];
                                    }
                                    [sourceSubsetArguments addObject:@{
                                        @"selector": selectorLabel,
                                        @"source_class": [self classNameForObject:sourceObject],
                                        @"source_summary": [self summaryForValue:sourceObject],
                                    }];
                                    findMySearchPartyLocationProbe[@"latest_locations_source_subset_arguments"] = sourceSubsetArguments;
                                }
                            }
                        }

                    } else {
                        if (focusedProbeStep == 1) {
                            appendProbeCompletion(@"SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.singleIdentifier", nil);
                        } else if (focusedProbeStep == 2) {
                            appendProbeCompletion(@"SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.exactContextArguments", nil);
                        } else if (focusedProbeStep == 4) {
                            for (NSUInteger sourceIndex = 0; sourceIndex < 4; sourceIndex++) {
                                appendProbeCompletion([NSString stringWithFormat:@"SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.sourceSubset.%lu", (unsigned long)sourceIndex], nil);
                            }
                        }
                    }

                    if (focusedProbeStep == 3) {
                        id controlledContextTarget = locationFetch ?: [self safeObjectValueFromObject:targetSession selectorName:@"locationFetch"];
                        SEL locationForContextSelector = NSSelectorFromString(@"locationForContext:completion:");
                        NSMethodSignature *locationForContextSignature = [controlledContextTarget methodSignatureForSelector:locationForContextSelector];
                        if (controlledContextTarget != nil &&
                            locationForContextSignature != nil &&
                            locationForContextSignature.numberOfArguments == 4) {
                            void (^controlledLocationForContextCompletion)(id) = ^(id result) {
                                appendProbeCompletion(@"SPOwnerSessionLocationFetch.locationForContext:completion:.controlledContext", result);
                            };
                            NSInvocation *controlledLocationForContextInvocation = [NSInvocation invocationWithMethodSignature:locationForContextSignature];
                            [controlledLocationForContextInvocation setTarget:controlledContextTarget];
                            [controlledLocationForContextInvocation setSelector:locationForContextSelector];
                            [controlledLocationForContextInvocation setArgument:&context atIndex:2];
                            [controlledLocationForContextInvocation setArgument:&controlledLocationForContextCompletion atIndex:3];
                            [controlledLocationForContextInvocation retainArguments];
                            [controlledLocationForContextInvocation invoke];
                        } else {
                            appendProbeCompletion(@"SPOwnerSessionLocationFetch.locationForContext:completion:.controlledContext", nil);
                        }

                        SEL subscribeForContextSelector = NSSelectorFromString(@"subscribeAndFetchLocationForContext:completion:");
                        NSMethodSignature *subscribeForContextSignature = [controlledContextTarget methodSignatureForSelector:subscribeForContextSelector];
                        if (controlledContextTarget != nil &&
                            subscribeForContextSignature != nil &&
                            subscribeForContextSignature.numberOfArguments == 4) {
                            void (^controlledSubscribeForContextCompletion)(id) = ^(id result) {
                                appendProbeCompletion(@"SPOwnerSessionLocationFetch.subscribeAndFetchLocationForContext:completion:.controlledContext", result);
                            };
                            NSInvocation *controlledSubscribeForContextInvocation = [NSInvocation invocationWithMethodSignature:subscribeForContextSignature];
                            [controlledSubscribeForContextInvocation setTarget:controlledContextTarget];
                            [controlledSubscribeForContextInvocation setSelector:subscribeForContextSelector];
                            [controlledSubscribeForContextInvocation setArgument:&context atIndex:2];
                            [controlledSubscribeForContextInvocation setArgument:&controlledSubscribeForContextCompletion atIndex:3];
                            [controlledSubscribeForContextInvocation retainArguments];
                            [controlledSubscribeForContextInvocation invoke];
                        } else {
                            appendProbeCompletion(@"SPOwnerSessionLocationFetch.subscribeAndFetchLocationForContext:completion:.controlledContext", nil);
                        }

                        SEL proxyLocationForContextSelector = NSSelectorFromString(@"locationForContext:completion:");
                        NSMethodSignature *proxyLocationForContextSignature = [ownerProxy methodSignatureForSelector:proxyLocationForContextSelector];
                        if (ownerProxy != nil &&
                            proxyLocationForContextSignature != nil &&
                            proxyLocationForContextSignature.numberOfArguments == 4) {
                            void (^proxyLocationForContextCompletion)(id) = ^(id result) {
                                appendProbeCompletion(@"SPOwnerSessionXPCProtocol.locationForContext:completion:", result);
                            };
                            NSInvocation *proxyLocationForContextInvocation = [NSInvocation invocationWithMethodSignature:proxyLocationForContextSignature];
                            [proxyLocationForContextInvocation setTarget:ownerProxy];
                            [proxyLocationForContextInvocation setSelector:proxyLocationForContextSelector];
                            [proxyLocationForContextInvocation setArgument:&context atIndex:2];
                            [proxyLocationForContextInvocation setArgument:&proxyLocationForContextCompletion atIndex:3];
                            [proxyLocationForContextInvocation retainArguments];
                            [proxyLocationForContextInvocation invoke];
                        } else {
                            appendProbeCompletion(@"SPOwnerSessionXPCProtocol.locationForContext:completion:", nil);
                        }
                    }

                    if (focusedProbeStep == 10) {
                        id singleContextTarget = locationFetch ?: [self safeObjectValueFromObject:targetSession selectorName:@"locationFetch"];
                        SEL locationForContextSelector = NSSelectorFromString(@"locationForContext:completion:");
                        NSMethodSignature *locationForContextSignature = [singleContextTarget methodSignatureForSelector:locationForContextSelector];
                        SEL subscribeForContextSelector = NSSelectorFromString(@"subscribeAndFetchLocationForContext:completion:");
                        NSMethodSignature *subscribeForContextSignature = [singleContextTarget methodSignatureForSelector:subscribeForContextSelector];
                        SEL proxyLocationForContextSelector = NSSelectorFromString(@"locationForContext:completion:");
                        NSMethodSignature *proxyLocationForContextSignature = [ownerProxy methodSignatureForSelector:proxyLocationForContextSelector];

                        @synchronized ([BlueBubblesHelper class]) {
                            findMySearchPartyLocationProbe[@"single_identifier_context_method_availability"] = @{
                                @"locationFetch.locationForContext": @(singleContextTarget != nil && locationForContextSignature != nil && locationForContextSignature.numberOfArguments == 4),
                                @"locationFetch.subscribeAndFetchLocationForContext": @(singleContextTarget != nil && subscribeForContextSignature != nil && subscribeForContextSignature.numberOfArguments == 4),
                                @"proxy.locationForContext": @(ownerProxy != nil && proxyLocationForContextSignature != nil && proxyLocationForContextSignature.numberOfArguments == 4),
                            };
                        }

                        if (singleContextTarget != nil &&
                            singleIdentifierContext != nil &&
                            locationForContextSignature != nil &&
                            locationForContextSignature.numberOfArguments == 4) {
                            void (^singleLocationForContextCompletion)(id) = ^(id result) {
                                appendProbeCompletion(@"SPOwnerSessionLocationFetch.locationForContext:completion:.singleIdentifierContext", result);
                            };
                            NSInvocation *singleLocationForContextInvocation = [NSInvocation invocationWithMethodSignature:locationForContextSignature];
                            [singleLocationForContextInvocation setTarget:singleContextTarget];
                            [singleLocationForContextInvocation setSelector:locationForContextSelector];
                            [singleLocationForContextInvocation setArgument:&singleIdentifierContext atIndex:2];
                            [singleLocationForContextInvocation setArgument:&singleLocationForContextCompletion atIndex:3];
                            [singleLocationForContextInvocation retainArguments];
                            [singleLocationForContextInvocation invoke];
                        } else {
                            appendProbeCompletion(@"SPOwnerSessionLocationFetch.locationForContext:completion:.singleIdentifierContext", nil);
                        }

                        if (singleContextTarget != nil &&
                            singleIdentifierContext != nil &&
                            subscribeForContextSignature != nil &&
                            subscribeForContextSignature.numberOfArguments == 4) {
                            void (^singleSubscribeForContextCompletion)(id) = ^(id result) {
                                appendProbeCompletion(@"SPOwnerSessionLocationFetch.subscribeAndFetchLocationForContext:completion:.singleIdentifierContext", result);
                            };
                            NSInvocation *singleSubscribeForContextInvocation = [NSInvocation invocationWithMethodSignature:subscribeForContextSignature];
                            [singleSubscribeForContextInvocation setTarget:singleContextTarget];
                            [singleSubscribeForContextInvocation setSelector:subscribeForContextSelector];
                            [singleSubscribeForContextInvocation setArgument:&singleIdentifierContext atIndex:2];
                            [singleSubscribeForContextInvocation setArgument:&singleSubscribeForContextCompletion atIndex:3];
                            [singleSubscribeForContextInvocation retainArguments];
                            [singleSubscribeForContextInvocation invoke];
                        } else {
                            appendProbeCompletion(@"SPOwnerSessionLocationFetch.subscribeAndFetchLocationForContext:completion:.singleIdentifierContext", nil);
                        }

                        if (ownerProxy != nil &&
                            singleIdentifierContext != nil &&
                            proxyLocationForContextSignature != nil &&
                            proxyLocationForContextSignature.numberOfArguments == 4) {
                            void (^singleProxyLocationForContextCompletion)(id) = ^(id result) {
                                appendProbeCompletion(@"SPOwnerSessionXPCProtocol.locationForContext:completion:.singleIdentifierContext", result);
                            };
                            NSInvocation *singleProxyLocationForContextInvocation = [NSInvocation invocationWithMethodSignature:proxyLocationForContextSignature];
                            [singleProxyLocationForContextInvocation setTarget:ownerProxy];
                            [singleProxyLocationForContextInvocation setSelector:proxyLocationForContextSelector];
                            [singleProxyLocationForContextInvocation setArgument:&singleIdentifierContext atIndex:2];
                            [singleProxyLocationForContextInvocation setArgument:&singleProxyLocationForContextCompletion atIndex:3];
                            [singleProxyLocationForContextInvocation retainArguments];
                            [singleProxyLocationForContextInvocation invoke];
                        } else {
                            appendProbeCompletion(@"SPOwnerSessionXPCProtocol.locationForContext:completion:.singleIdentifierContext", nil);
                        }
                    }

                    if (focusedProbeStep == 16) {
                        id lastOnlineContextTarget = locationFetch ?: [self safeObjectValueFromObject:targetSession selectorName:@"locationFetch"];
                        SEL locationForContextSelector = NSSelectorFromString(@"locationForContext:completion:");
                        NSMethodSignature *locationForContextSignature = [lastOnlineContextTarget methodSignatureForSelector:locationForContextSelector];
                        SEL subscribeForContextSelector = NSSelectorFromString(@"subscribeAndFetchLocationForContext:completion:");
                        NSMethodSignature *subscribeForContextSignature = [lastOnlineContextTarget methodSignatureForSelector:subscribeForContextSelector];
                        SEL proxyLocationForContextSelector = NSSelectorFromString(@"locationForContext:completion:");
                        NSMethodSignature *proxyLocationForContextSignature = [ownerProxy methodSignatureForSelector:proxyLocationForContextSelector];

                        @synchronized ([BlueBubblesHelper class]) {
                            findMySearchPartyLocationProbe[@"last_online_context_method_availability"] = @{
                                @"latestLocationsForIdentifiers": @(ownerProxy != nil && latestLocationsSignature != nil && latestLocationsSignature.numberOfArguments == 6),
                                @"locationFetch.locationForContext": @(lastOnlineContextTarget != nil && locationForContextSignature != nil && locationForContextSignature.numberOfArguments == 4),
                                @"locationFetch.subscribeAndFetchLocationForContext": @(lastOnlineContextTarget != nil && subscribeForContextSignature != nil && subscribeForContextSignature.numberOfArguments == 4),
                                @"proxy.locationForContext": @(ownerProxy != nil && proxyLocationForContextSignature != nil && proxyLocationForContextSignature.numberOfArguments == 4),
                            };
                        }

                        if (ownerProxy != nil &&
                            latestLocationsSignature != nil &&
                            latestLocationsSignature.numberOfArguments == 6 &&
                            lastOnlineIdentifierValues.count > 0) {
                            NSArray *lastOnlineIdentifierArgument = [lastOnlineIdentifierValues copy];
                            id lastOnlineFetchLimit = @(lastOnlineIdentifierArgument.count);
                            void (^lastOnlineLatestCompletion)(id) = ^(id result) {
                                appendProbeCompletion(@"SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.lastOnlineIdentifiers", result);
                            };
                            NSInvocation *lastOnlineLatestInvocation = [NSInvocation invocationWithMethodSignature:latestLocationsSignature];
                            [lastOnlineLatestInvocation setTarget:ownerProxy];
                            [lastOnlineLatestInvocation setSelector:latestLocationsSelector];
                            [lastOnlineLatestInvocation setArgument:&lastOnlineIdentifierArgument atIndex:2];
                            [lastOnlineLatestInvocation setArgument:&lastOnlineFetchLimit atIndex:3];
                            [lastOnlineLatestInvocation setArgument:&generatedSearchLocationSources atIndex:4];
                            [lastOnlineLatestInvocation setArgument:&lastOnlineLatestCompletion atIndex:5];
                            [lastOnlineLatestInvocation retainArguments];
                            [lastOnlineLatestInvocation invoke];
                        } else {
                            appendProbeCompletion(@"SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.lastOnlineIdentifiers", nil);
                        }

                        if (lastOnlineContextTarget != nil &&
                            lastOnlineContext != nil &&
                            locationForContextSignature != nil &&
                            locationForContextSignature.numberOfArguments == 4) {
                            void (^lastOnlineLocationForContextCompletion)(id) = ^(id result) {
                                appendProbeCompletion(@"SPOwnerSessionLocationFetch.locationForContext:completion:.lastOnlineIdentifiers", result);
                            };
                            NSInvocation *lastOnlineLocationForContextInvocation = [NSInvocation invocationWithMethodSignature:locationForContextSignature];
                            [lastOnlineLocationForContextInvocation setTarget:lastOnlineContextTarget];
                            [lastOnlineLocationForContextInvocation setSelector:locationForContextSelector];
                            [lastOnlineLocationForContextInvocation setArgument:&lastOnlineContext atIndex:2];
                            [lastOnlineLocationForContextInvocation setArgument:&lastOnlineLocationForContextCompletion atIndex:3];
                            [lastOnlineLocationForContextInvocation retainArguments];
                            [lastOnlineLocationForContextInvocation invoke];
                        } else {
                            appendProbeCompletion(@"SPOwnerSessionLocationFetch.locationForContext:completion:.lastOnlineIdentifiers", nil);
                        }

                        if (lastOnlineContextTarget != nil &&
                            lastOnlineContext != nil &&
                            subscribeForContextSignature != nil &&
                            subscribeForContextSignature.numberOfArguments == 4) {
                            void (^lastOnlineSubscribeForContextCompletion)(id) = ^(id result) {
                                appendProbeCompletion(@"SPOwnerSessionLocationFetch.subscribeAndFetchLocationForContext:completion:.lastOnlineIdentifiers", result);
                            };
                            NSInvocation *lastOnlineSubscribeForContextInvocation = [NSInvocation invocationWithMethodSignature:subscribeForContextSignature];
                            [lastOnlineSubscribeForContextInvocation setTarget:lastOnlineContextTarget];
                            [lastOnlineSubscribeForContextInvocation setSelector:subscribeForContextSelector];
                            [lastOnlineSubscribeForContextInvocation setArgument:&lastOnlineContext atIndex:2];
                            [lastOnlineSubscribeForContextInvocation setArgument:&lastOnlineSubscribeForContextCompletion atIndex:3];
                            [lastOnlineSubscribeForContextInvocation retainArguments];
                            [lastOnlineSubscribeForContextInvocation invoke];
                        } else {
                            appendProbeCompletion(@"SPOwnerSessionLocationFetch.subscribeAndFetchLocationForContext:completion:.lastOnlineIdentifiers", nil);
                        }

                        if (ownerProxy != nil &&
                            lastOnlineContext != nil &&
                            proxyLocationForContextSignature != nil &&
                            proxyLocationForContextSignature.numberOfArguments == 4) {
                            void (^lastOnlineProxyLocationForContextCompletion)(id) = ^(id result) {
                                appendProbeCompletion(@"SPOwnerSessionXPCProtocol.locationForContext:completion:.lastOnlineIdentifiers", result);
                            };
                            NSInvocation *lastOnlineProxyLocationForContextInvocation = [NSInvocation invocationWithMethodSignature:proxyLocationForContextSignature];
                            [lastOnlineProxyLocationForContextInvocation setTarget:ownerProxy];
                            [lastOnlineProxyLocationForContextInvocation setSelector:proxyLocationForContextSelector];
                            [lastOnlineProxyLocationForContextInvocation setArgument:&lastOnlineContext atIndex:2];
                            [lastOnlineProxyLocationForContextInvocation setArgument:&lastOnlineProxyLocationForContextCompletion atIndex:3];
                            [lastOnlineProxyLocationForContextInvocation retainArguments];
                            [lastOnlineProxyLocationForContextInvocation invoke];
                        } else {
                            appendProbeCompletion(@"SPOwnerSessionXPCProtocol.locationForContext:completion:.lastOnlineIdentifiers", nil);
                        }
                    }

                    if (focusedProbeStep == 11) {
                        id singleContextTarget = locationFetch ?: [self safeObjectValueFromObject:targetSession selectorName:@"locationFetch"];
                        SEL subscribeForContextSelector = NSSelectorFromString(@"subscribeAndFetchLocationForContext:completion:");
                        NSMethodSignature *subscribeForContextSignature = [singleContextTarget methodSignatureForSelector:subscribeForContextSelector];

                        @synchronized ([BlueBubblesHelper class]) {
                            findMySearchPartyLocationProbe[@"callback_watch_method_availability"] = @{
                                @"locationFetch.subscribeAndFetchLocationForContext": @(singleContextTarget != nil && subscribeForContextSignature != nil && subscribeForContextSignature.numberOfArguments == 4),
                            };
                            findMySearchPartyLocationProbe[@"callback_watch_note"] = @"Poll this probe after the subscription completion to inspect passive_location_events from setLocationUpdateBlock:, setLatestLocationsUpdatedBlock:, and receivedUpdatedLocation:.";
                        }

                        if (singleContextTarget != nil &&
                            singleIdentifierContext != nil &&
                            subscribeForContextSignature != nil &&
                            subscribeForContextSignature.numberOfArguments == 4) {
                            void (^callbackWatchSubscribeCompletion)(id) = ^(id result) {
                                appendProbeCompletion(@"SPOwnerSessionLocationFetch.subscribeAndFetchLocationForContext:completion:.callbackWatch", result);
                            };
                            NSInvocation *callbackWatchInvocation = [NSInvocation invocationWithMethodSignature:subscribeForContextSignature];
                            [callbackWatchInvocation setTarget:singleContextTarget];
                            [callbackWatchInvocation setSelector:subscribeForContextSelector];
                            [callbackWatchInvocation setArgument:&singleIdentifierContext atIndex:2];
                            [callbackWatchInvocation setArgument:&callbackWatchSubscribeCompletion atIndex:3];
                            [callbackWatchInvocation retainArguments];
                            [callbackWatchInvocation invoke];
                        } else {
                            appendProbeCompletion(@"SPOwnerSessionLocationFetch.subscribeAndFetchLocationForContext:completion:.callbackWatch", nil);
                        }
                    }

                    if (focusedProbeStep == 12) {
                        id fullContextTarget = locationFetch ?: [self safeObjectValueFromObject:targetSession selectorName:@"locationFetch"];
                        SEL subscribeForContextSelector = NSSelectorFromString(@"subscribeAndFetchLocationForContext:completion:");
                        NSMethodSignature *subscribeForContextSignature = [fullContextTarget methodSignatureForSelector:subscribeForContextSelector];

                        @synchronized ([BlueBubblesHelper class]) {
                            findMySearchPartyLocationProbe[@"callback_watch_method_availability"] = @{
                                @"locationFetch.subscribeAndFetchLocationForContext": @(fullContextTarget != nil && subscribeForContextSignature != nil && subscribeForContextSignature.numberOfArguments == 4),
                            };
                            findMySearchPartyLocationProbe[@"callback_watch_context"] = @"full";
                            findMySearchPartyLocationProbe[@"callback_watch_note"] = @"Full-context callback watch uses the generated context with all collected searchIdentifiers and searchLocationSources, then polls compact passive_location_events.";
                        }

                        if (fullContextTarget != nil &&
                            context != nil &&
                            subscribeForContextSignature != nil &&
                            subscribeForContextSignature.numberOfArguments == 4) {
                            void (^fullContextSubscribeCompletion)(id) = ^(id result) {
                                appendProbeCompletion(@"SPOwnerSessionLocationFetch.subscribeAndFetchLocationForContext:completion:.fullContextCallbackWatch", result);
                            };
                            NSInvocation *fullContextWatchInvocation = [NSInvocation invocationWithMethodSignature:subscribeForContextSignature];
                            [fullContextWatchInvocation setTarget:fullContextTarget];
                            [fullContextWatchInvocation setSelector:subscribeForContextSelector];
                            [fullContextWatchInvocation setArgument:&context atIndex:2];
                            [fullContextWatchInvocation setArgument:&fullContextSubscribeCompletion atIndex:3];
                            [fullContextWatchInvocation retainArguments];
                            [fullContextWatchInvocation invoke];
                        } else {
                            appendProbeCompletion(@"SPOwnerSessionLocationFetch.subscribeAndFetchLocationForContext:completion:.fullContextCallbackWatch", nil);
                        }
                    }

                    if (focusedProbeStep == 13) {
                        id deviceEventTarget = locationFetch ?: [self safeObjectValueFromObject:targetSession selectorName:@"locationFetch"];
                        SEL subscribeForContextSelector = NSSelectorFromString(@"subscribeAndFetchLocationForContext:completion:");
                        NSMethodSignature *subscribeForContextSignature = [deviceEventTarget methodSignatureForSelector:subscribeForContextSelector];

                        @synchronized ([BlueBubblesHelper class]) {
                            findMySearchPartyLocationProbe[@"callback_watch_method_availability"] = @{
                                @"locationFetch.subscribeAndFetchLocationForContext": @(deviceEventTarget != nil && subscribeForContextSignature != nil && subscribeForContextSignature.numberOfArguments == 4),
                            };
                            findMySearchPartyLocationProbe[@"callback_watch_context"] = @"deviceEventsFull";
                            findMySearchPartyLocationProbe[@"callback_watch_note"] = @"Device-event callback watch uses the full generated context with reportDeviceEvents enabled and captures receivedUpdatedDeviceEvents: into passive_location_events.";
                        }

                        if (deviceEventTarget != nil &&
                            context != nil &&
                            subscribeForContextSignature != nil &&
                            subscribeForContextSignature.numberOfArguments == 4) {
                            void (^deviceEventSubscribeCompletion)(id) = ^(id result) {
                                appendProbeCompletion(@"SPOwnerSessionLocationFetch.subscribeAndFetchLocationForContext:completion:.deviceEventCallbackWatch", result);
                            };
                            NSInvocation *deviceEventWatchInvocation = [NSInvocation invocationWithMethodSignature:subscribeForContextSignature];
                            [deviceEventWatchInvocation setTarget:deviceEventTarget];
                            [deviceEventWatchInvocation setSelector:subscribeForContextSelector];
                            [deviceEventWatchInvocation setArgument:&context atIndex:2];
                            [deviceEventWatchInvocation setArgument:&deviceEventSubscribeCompletion atIndex:3];
                            [deviceEventWatchInvocation retainArguments];
                            [deviceEventWatchInvocation invoke];
                        } else {
                            appendProbeCompletion(@"SPOwnerSessionLocationFetch.subscribeAndFetchLocationForContext:completion:.deviceEventCallbackWatch", nil);
                        }
                    }

                    if (focusedProbeStep == 14) {
                        SEL delegatedLocationSelector = NSSelectorFromString(@"delegatedLocationForContext:completion:");
                        id ownerProxy = [self safeObjectValueFromObject:targetSession selectorName:@"proxy"] ?: [self safeObjectValueFromObject:targetSession selectorName:@"_proxy"];
                        id delegatedLocationTarget = [targetSession respondsToSelector:delegatedLocationSelector] ? targetSession : ownerProxy;
                        NSMethodSignature *delegatedLocationSignature = [delegatedLocationTarget methodSignatureForSelector:delegatedLocationSelector];

                        @synchronized ([BlueBubblesHelper class]) {
                            findMySearchPartyLocationProbe[@"delegated_context_method_availability"] = @{
                                @"ownerSession.delegatedLocationForContext": @([targetSession respondsToSelector:delegatedLocationSelector]),
                                @"ownerProxy.delegatedLocationForContext": @(ownerProxy != nil && [ownerProxy respondsToSelector:delegatedLocationSelector]),
                                @"selectedTargetClass": [self classNameForObject:delegatedLocationTarget] ?: @"<nil>",
                            };
                            findMySearchPartyLocationProbe[@"delegated_context_note"] = @"Delegated-context probe uses the full generated SPLocationFetchContext and calls delegatedLocationForContext:completion: on SPOwnerSession or its XPC proxy.";
                        }

                        if (delegatedLocationTarget != nil &&
                            context != nil &&
                            delegatedLocationSignature != nil &&
                            delegatedLocationSignature.numberOfArguments == 4) {
                            void (^delegatedLocationCompletion)(id) = ^(id result) {
                                appendProbeCompletion(@"SPOwnerSessionXPCProtocol.delegatedLocationForContext:completion:", result);
                            };
                            NSInvocation *delegatedLocationInvocation = [NSInvocation invocationWithMethodSignature:delegatedLocationSignature];
                            [delegatedLocationInvocation setTarget:delegatedLocationTarget];
                            [delegatedLocationInvocation setSelector:delegatedLocationSelector];
                            [delegatedLocationInvocation setArgument:&context atIndex:2];
                            [delegatedLocationInvocation setArgument:&delegatedLocationCompletion atIndex:3];
                            [delegatedLocationInvocation retainArguments];
                            [delegatedLocationInvocation invoke];
                        } else {
                            appendProbeCompletion(@"SPOwnerSessionXPCProtocol.delegatedLocationForContext:completion:", nil);
                        }
                    }

                    if (focusedProbeStep == 5) {
                        SEL requestLiveLocationSelector = NSSelectorFromString(@"requestLiveLocationForUUID:completion:");
                        NSMethodSignature *requestLiveLocationSignature = [ownerProxy methodSignatureForSelector:requestLiveLocationSelector];
                        @synchronized ([BlueBubblesHelper class]) {
                            NSMutableArray *arguments = [[NSMutableArray alloc] init];
                            for (NSDictionary *candidate in liveRequestCandidates) {
                                [arguments addObject:@{
                                    @"variant": candidate[@"variant"] ?: @"<nil>",
                                    @"identifier": candidate[@"identifier"] ?: @"<nil>",
                                    @"name": candidate[@"name"] ?: @"<nil>",
                                    @"request_value_class": candidate[@"request_value_class"] ?: @"<nil>",
                                }];
                            }
                            findMySearchPartyLocationProbe[@"live_request_arguments"] = arguments;
                        }

                        if (ownerProxy != nil &&
                            requestLiveLocationSignature != nil &&
                            requestLiveLocationSignature.numberOfArguments == 4 &&
                            liveRequestCandidates.count > 0) {
                            for (NSUInteger candidateIndex = 0; candidateIndex < 4; candidateIndex++) {
                                NSString *selectorLabel = [NSString stringWithFormat:@"SPOwnerSessionXPCProtocol.requestLiveLocationForUUID.variant.%lu", (unsigned long)candidateIndex];
                                if (candidateIndex >= liveRequestCandidates.count) {
                                    appendProbeCompletion(selectorLabel, nil);
                                    continue;
                                }
                                NSDictionary *candidate = liveRequestCandidates[candidateIndex];
                                id requestValue = candidate[@"request_value"];
                                void (^liveRequestCompletion)(id) = ^(id result) {
                                    appendProbeCompletion(selectorLabel, result);
                                };
                                NSInvocation *liveRequestInvocation = [NSInvocation invocationWithMethodSignature:requestLiveLocationSignature];
                                [liveRequestInvocation setTarget:ownerProxy];
                                [liveRequestInvocation setSelector:requestLiveLocationSelector];
                                [liveRequestInvocation setArgument:&requestValue atIndex:2];
                                [liveRequestInvocation setArgument:&liveRequestCompletion atIndex:3];
                                [liveRequestInvocation retainArguments];
                                [liveRequestInvocation invoke];
                            }
                        } else {
                            for (NSUInteger candidateIndex = 0; candidateIndex < 4; candidateIndex++) {
                                appendProbeCompletion([NSString stringWithFormat:@"SPOwnerSessionXPCProtocol.requestLiveLocationForUUID.variant.%lu", (unsigned long)candidateIndex], nil);
                            }
                        }
                    }

                    if (focusedProbeStep == 6) {
                        SEL beaconForIdentifierSelector = NSSelectorFromString(@"beaconForIdentifier:completion:");
                        SEL beaconForUUIDSelector = NSSelectorFromString(@"beaconForUUID:completion:");
                        SEL beaconGroupsForUUIDsSelector = NSSelectorFromString(@"beaconGroupsForUUIDs:completion:");
                        NSMethodSignature *beaconForIdentifierSignature = [ownerProxy methodSignatureForSelector:beaconForIdentifierSelector];
                        NSMethodSignature *beaconForUUIDSignature = [ownerProxy methodSignatureForSelector:beaconForUUIDSelector];
                        NSMethodSignature *beaconGroupsForUUIDsSignature = [ownerProxy methodSignatureForSelector:beaconGroupsForUUIDsSelector];

                        NSMutableArray *stringCandidates = [[NSMutableArray alloc] init];
                        NSMutableArray *uuidCandidates = [[NSMutableArray alloc] init];
                        for (NSDictionary *candidate in identifierResolutionCandidates) {
                            id requestValue = candidate[@"request_value"];
                            if ([requestValue isKindOfClass:[NSString class]] && stringCandidates.count < 2) {
                                [stringCandidates addObject:candidate];
                            } else if ([requestValue isKindOfClass:[NSUUID class]] && uuidCandidates.count < 3) {
                                [uuidCandidates addObject:candidate];
                            }
                        }

                        @synchronized ([BlueBubblesHelper class]) {
                            NSMutableArray *arguments = [[NSMutableArray alloc] init];
                            for (NSDictionary *candidate in identifierResolutionCandidates) {
                                if (arguments.count >= 6) {
                                    break;
                                }
                                [arguments addObject:@{
                                    @"variant": candidate[@"variant"] ?: @"<nil>",
                                    @"identifier": candidate[@"identifier"] ?: @"<nil>",
                                    @"name": candidate[@"name"] ?: @"<nil>",
                                    @"request_value_class": candidate[@"request_value_class"] ?: @"<nil>",
                                }];
                            }
                            findMySearchPartyLocationProbe[@"identifier_resolution_arguments"] = arguments;
                            findMySearchPartyLocationProbe[@"identifier_resolution_method_availability"] = @{
                                @"beaconForIdentifier": @(ownerProxy != nil && beaconForIdentifierSignature != nil && beaconForIdentifierSignature.numberOfArguments == 4),
                                @"beaconForUUID": @(ownerProxy != nil && beaconForUUIDSignature != nil && beaconForUUIDSignature.numberOfArguments == 4),
                                @"beaconGroupsForUUIDs": @(ownerProxy != nil && beaconGroupsForUUIDsSignature != nil && beaconGroupsForUUIDsSignature.numberOfArguments == 4),
                            };
                        }

                        NSUInteger focusedCompletionIndex = 0;
                        BOOL canCallBeaconForIdentifier = ownerProxy != nil && beaconForIdentifierSignature != nil && beaconForIdentifierSignature.numberOfArguments == 4;
                        for (NSUInteger i = 0; i < 1; i++) {
                            NSString *selectorLabel = [NSString stringWithFormat:@"SPOwnerSessionXPCProtocol.beaconForIdentifier.variant.%lu", (unsigned long)i];
                            if (!canCallBeaconForIdentifier || i >= stringCandidates.count) {
                                appendProbeCompletion(selectorLabel, nil);
                                focusedCompletionIndex += 1;
                                continue;
                            }
                            NSDictionary *candidate = stringCandidates[i];
                            id requestValue = candidate[@"request_value"];
                            void (^resolutionCompletion)(id) = ^(id result) {
                                appendProbeCompletion(selectorLabel, result);
                            };
                            NSInvocation *resolutionInvocation = [NSInvocation invocationWithMethodSignature:beaconForIdentifierSignature];
                            [resolutionInvocation setTarget:ownerProxy];
                            [resolutionInvocation setSelector:beaconForIdentifierSelector];
                            [resolutionInvocation setArgument:&requestValue atIndex:2];
                            [resolutionInvocation setArgument:&resolutionCompletion atIndex:3];
                            [resolutionInvocation retainArguments];
                            [resolutionInvocation invoke];
                            focusedCompletionIndex += 1;
                        }

                        BOOL canCallBeaconForUUID = ownerProxy != nil && beaconForUUIDSignature != nil && beaconForUUIDSignature.numberOfArguments == 4;
                        for (NSUInteger i = 0; i < 2; i++) {
                            NSString *selectorLabel = [NSString stringWithFormat:@"SPOwnerSessionXPCProtocol.beaconForUUID.variant.%lu", (unsigned long)i];
                            if (!canCallBeaconForUUID || i >= uuidCandidates.count) {
                                appendProbeCompletion(selectorLabel, nil);
                                focusedCompletionIndex += 1;
                                continue;
                            }
                            NSDictionary *candidate = uuidCandidates[i];
                            id requestValue = candidate[@"request_value"];
                            void (^resolutionCompletion)(id) = ^(id result) {
                                appendProbeCompletion(selectorLabel, result);
                            };
                            NSInvocation *resolutionInvocation = [NSInvocation invocationWithMethodSignature:beaconForUUIDSignature];
                            [resolutionInvocation setTarget:ownerProxy];
                            [resolutionInvocation setSelector:beaconForUUIDSelector];
                            [resolutionInvocation setArgument:&requestValue atIndex:2];
                            [resolutionInvocation setArgument:&resolutionCompletion atIndex:3];
                            [resolutionInvocation retainArguments];
                            [resolutionInvocation invoke];
                            focusedCompletionIndex += 1;
                        }

                        BOOL canCallBeaconGroupsForUUIDs = ownerProxy != nil && beaconGroupsForUUIDsSignature != nil && beaconGroupsForUUIDsSignature.numberOfArguments == 4;
                        NSString *groupsSelectorLabel = @"SPOwnerSessionXPCProtocol.beaconGroupsForUUIDs.sample";
                        if (canCallBeaconGroupsForUUIDs && uuidCandidates.count > 0) {
                            NSMutableArray *uuidValues = [[NSMutableArray alloc] init];
                            for (NSDictionary *candidate in uuidCandidates) {
                                id requestValue = candidate[@"request_value"];
                                if ([requestValue isKindOfClass:[NSUUID class]] && uuidValues.count < 3) {
                                    [uuidValues addObject:requestValue];
                                }
                            }
                            NSArray *uuidArray = [uuidValues copy];
                            void (^groupsCompletion)(id) = ^(id result) {
                                appendProbeCompletion(groupsSelectorLabel, result);
                            };
                            NSInvocation *groupsInvocation = [NSInvocation invocationWithMethodSignature:beaconGroupsForUUIDsSignature];
                            [groupsInvocation setTarget:ownerProxy];
                            [groupsInvocation setSelector:beaconGroupsForUUIDsSelector];
                            [groupsInvocation setArgument:&uuidArray atIndex:2];
                            [groupsInvocation setArgument:&groupsCompletion atIndex:3];
                            [groupsInvocation retainArguments];
                            [groupsInvocation invoke];
                        } else {
                            appendProbeCompletion(groupsSelectorLabel, nil);
                        }
                        focusedCompletionIndex += 1;

                        while (focusedCompletionIndex < 4) {
                            appendProbeCompletion([NSString stringWithFormat:@"SPOwnerSessionXPCProtocol.identifierResolution.unused.%lu", (unsigned long)focusedCompletionIndex], nil);
                            focusedCompletionIndex += 1;
                        }
                    }

                    if (focusedProbeStep == 7) {
                        SEL beaconForUUIDSelector = NSSelectorFromString(@"beaconForUUID:completion:");
                        NSMethodSignature *beaconForUUIDSignature = [ownerProxy methodSignatureForSelector:beaconForUUIDSelector];
                        NSDictionary *candidate = contextIdentifierUUIDCandidates.count > 0 ? contextIdentifierUUIDCandidates[0] : nil;
                        @synchronized ([BlueBubblesHelper class]) {
                            findMySearchPartyLocationProbe[@"single_identifier_resolution_method_availability"] = @{
                                @"beaconForUUID": @(ownerProxy != nil && beaconForUUIDSignature != nil && beaconForUUIDSignature.numberOfArguments == 4),
                            };
                            findMySearchPartyLocationProbe[@"single_identifier_resolution_argument"] = candidate == nil ? [NSNull null] : @{
                                @"variant": candidate[@"variant"] ?: @"<nil>",
                                @"identifier": candidate[@"identifier"] ?: @"<nil>",
                                @"name": candidate[@"name"] ?: @"<nil>",
                                @"request_value_class": candidate[@"request_value_class"] ?: @"<nil>",
                            };
                        }
                        NSString *selectorLabel = @"SPOwnerSessionXPCProtocol.beaconForUUID.contextIdentifier.single";
                        if (ownerProxy != nil &&
                            beaconForUUIDSignature != nil &&
                            beaconForUUIDSignature.numberOfArguments == 4 &&
                            candidate != nil) {
                            id requestValue = candidate[@"request_value"];
                            void (^resolutionCompletion)(id) = ^(id result) {
                                appendProbeCompletion(selectorLabel, result);
                            };
                            NSInvocation *resolutionInvocation = [NSInvocation invocationWithMethodSignature:beaconForUUIDSignature];
                            [resolutionInvocation setTarget:ownerProxy];
                            [resolutionInvocation setSelector:beaconForUUIDSelector];
                            [resolutionInvocation setArgument:&requestValue atIndex:2];
                            [resolutionInvocation setArgument:&resolutionCompletion atIndex:3];
                            [resolutionInvocation retainArguments];
                            [resolutionInvocation invoke];
                        } else {
                            appendProbeCompletion(selectorLabel, nil);
                        }
                    }

                    if (focusedProbeStep == 8) {
                        SEL beaconForIdentifierSelector = NSSelectorFromString(@"beaconForIdentifier:completion:");
                        NSMethodSignature *beaconForIdentifierSignature = [ownerProxy methodSignatureForSelector:beaconForIdentifierSelector];
                        NSDictionary *candidate = nil;
                        for (NSDictionary *candidateEntry in identifierResolutionCandidates) {
                            id requestValue = candidateEntry[@"request_value"];
                            if ([requestValue isKindOfClass:[NSString class]]) {
                                candidate = candidateEntry;
                                break;
                            }
                        }
                        @synchronized ([BlueBubblesHelper class]) {
                            findMySearchPartyLocationProbe[@"single_identifier_resolution_method_availability"] = @{
                                @"beaconForIdentifier": @(ownerProxy != nil && beaconForIdentifierSignature != nil && beaconForIdentifierSignature.numberOfArguments == 4),
                            };
                            findMySearchPartyLocationProbe[@"single_identifier_resolution_argument"] = candidate == nil ? [NSNull null] : @{
                                @"variant": candidate[@"variant"] ?: @"<nil>",
                                @"identifier": candidate[@"identifier"] ?: @"<nil>",
                                @"name": candidate[@"name"] ?: @"<nil>",
                                @"request_value_class": candidate[@"request_value_class"] ?: @"<nil>",
                            };
                        }
                        NSString *selectorLabel = @"SPOwnerSessionXPCProtocol.beaconForIdentifier.stableIdentifier.single";
                        if (ownerProxy != nil &&
                            beaconForIdentifierSignature != nil &&
                            beaconForIdentifierSignature.numberOfArguments == 4 &&
                            candidate != nil) {
                            id requestValue = candidate[@"request_value"];
                            void (^resolutionCompletion)(id) = ^(id result) {
                                appendProbeCompletion(selectorLabel, result);
                            };
                            NSInvocation *resolutionInvocation = [NSInvocation invocationWithMethodSignature:beaconForIdentifierSignature];
                            [resolutionInvocation setTarget:ownerProxy];
                            [resolutionInvocation setSelector:beaconForIdentifierSelector];
                            [resolutionInvocation setArgument:&requestValue atIndex:2];
                            [resolutionInvocation setArgument:&resolutionCompletion atIndex:3];
                            [resolutionInvocation retainArguments];
                            [resolutionInvocation invoke];
                        } else {
                            appendProbeCompletion(selectorLabel, nil);
                        }
                    }

                    if (focusedProbeStep == 9) {
                        SEL beaconForUUIDSelector = NSSelectorFromString(@"beaconForUUID:completion:");
                        NSMethodSignature *beaconForUUIDSignature = [ownerProxy methodSignatureForSelector:beaconForUUIDSelector];
                        NSDictionary *candidate = contextIdentifierUUIDCandidates.count > 0 ? contextIdentifierUUIDCandidates[0] : nil;
                        @synchronized ([BlueBubblesHelper class]) {
                            findMySearchPartyLocationProbe[@"resolved_beacon_location_method_availability"] = @{
                                @"beaconForUUID": @(ownerProxy != nil && beaconForUUIDSignature != nil && beaconForUUIDSignature.numberOfArguments == 4),
                                @"locationsForBeacons": @(targetSession != nil && locationsForBeaconsSignature != nil && locationsForBeaconsSignature.numberOfArguments == 4),
                                @"latestLocationsForIdentifiers": @(ownerProxy != nil && latestLocationsSignature != nil && latestLocationsSignature.numberOfArguments == 6),
                            };
                            findMySearchPartyLocationProbe[@"resolved_beacon_location_argument"] = candidate == nil ? [NSNull null] : @{
                                @"variant": candidate[@"variant"] ?: @"<nil>",
                                @"identifier": candidate[@"identifier"] ?: @"<nil>",
                                @"name": candidate[@"name"] ?: @"<nil>",
                                @"request_value_class": candidate[@"request_value_class"] ?: @"<nil>",
                            };
                        }
                        NSString *selectorLabel = @"SPOwnerSessionXPCProtocol.beaconForUUID.resolvedBeaconLocation";
                        if (ownerProxy != nil &&
                            beaconForUUIDSignature != nil &&
                            beaconForUUIDSignature.numberOfArguments == 4 &&
                            candidate != nil) {
                            id requestValue = candidate[@"request_value"];
                            void (^resolutionCompletion)(id) = ^(id result) {
                                appendProbeCompletion(selectorLabel, result);
                                if (result == nil || result == [NSNull null]) {
                                    appendProbeCompletion(@"SPOwnerSession.locationsForBeacons:completion:.resolvedBeacon", nil);
                                    appendProbeCompletion(@"SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.resolvedBeaconIdentifier", nil);
                                    return;
                                }

                                if (targetSession != nil &&
                                    locationsForBeaconsSignature != nil &&
                                    locationsForBeaconsSignature.numberOfArguments == 4) {
                                    NSArray *resolvedBeacons = @[result];
                                    void (^resolvedLocationsCompletion)(id) = ^(id locationsResult) {
                                        appendProbeCompletion(@"SPOwnerSession.locationsForBeacons:completion:.resolvedBeacon", locationsResult);
                                    };
                                    NSInvocation *resolvedLocationsInvocation = [NSInvocation invocationWithMethodSignature:locationsForBeaconsSignature];
                                    [resolvedLocationsInvocation setTarget:targetSession];
                                    [resolvedLocationsInvocation setSelector:locationsForBeaconsSelector];
                                    [resolvedLocationsInvocation setArgument:&resolvedBeacons atIndex:2];
                                    [resolvedLocationsInvocation setArgument:&resolvedLocationsCompletion atIndex:3];
                                    [resolvedLocationsInvocation retainArguments];
                                    [resolvedLocationsInvocation invoke];
                                } else {
                                    appendProbeCompletion(@"SPOwnerSession.locationsForBeacons:completion:.resolvedBeacon", nil);
                                }

                                id resolvedIdentifier = [self directFindMyCandidateValueFromObject:result key:@"identifier"];
                                if (ownerProxy != nil &&
                                    latestLocationsSignature != nil &&
                                    latestLocationsSignature.numberOfArguments == 6 &&
                                    resolvedIdentifier != nil &&
                                    resolvedIdentifier != [NSNull null]) {
                                    NSArray *resolvedIdentifierArray = @[resolvedIdentifier];
                                    id resolvedFetchLimit = @1;
                                    void (^resolvedLatestCompletion)(id) = ^(id latestResult) {
                                        appendProbeCompletion(@"SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.resolvedBeaconIdentifier", latestResult);
                                    };
                                    NSInvocation *resolvedLatestInvocation = [NSInvocation invocationWithMethodSignature:latestLocationsSignature];
                                    [resolvedLatestInvocation setTarget:ownerProxy];
                                    [resolvedLatestInvocation setSelector:latestLocationsSelector];
                                    [resolvedLatestInvocation setArgument:&resolvedIdentifierArray atIndex:2];
                                    [resolvedLatestInvocation setArgument:&resolvedFetchLimit atIndex:3];
                                    [resolvedLatestInvocation setArgument:&generatedSearchLocationSources atIndex:4];
                                    [resolvedLatestInvocation setArgument:&resolvedLatestCompletion atIndex:5];
                                    [resolvedLatestInvocation retainArguments];
                                    [resolvedLatestInvocation invoke];
                                } else {
                                    appendProbeCompletion(@"SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.resolvedBeaconIdentifier", nil);
                                }
                            };
                            NSInvocation *resolutionInvocation = [NSInvocation invocationWithMethodSignature:beaconForUUIDSignature];
                            [resolutionInvocation setTarget:ownerProxy];
                            [resolutionInvocation setSelector:beaconForUUIDSelector];
                            [resolutionInvocation setArgument:&requestValue atIndex:2];
                            [resolutionInvocation setArgument:&resolutionCompletion atIndex:3];
                            [resolutionInvocation retainArguments];
                            [resolutionInvocation invoke];
                        } else {
                            appendProbeCompletion(selectorLabel, nil);
                            appendProbeCompletion(@"SPOwnerSession.locationsForBeacons:completion:.resolvedBeacon", nil);
                            appendProbeCompletion(@"SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.resolvedBeaconIdentifier", nil);
                        }
                    }
                } @catch (NSException *exception) {
                    @synchronized ([BlueBubblesHelper class]) {
                        findMySearchPartyLocationProbe[@"status"] = @"failed";
                        findMySearchPartyLocationProbe[@"error"] = exception.reason ?: exception.description ?: @"Exception invoking SearchParty location fetch methods";
                    }
                }
            });
        };

        @try {
            SEL beaconsSelector = NSSelectorFromString(@"allBeaconsWithCompletion:");
            NSMethodSignature *beaconsSignature = [targetSession methodSignatureForSelector:beaconsSelector];
            if (beaconsSignature == nil || beaconsSignature.numberOfArguments != 3) {
                startedProbe[@"status"] = @"failed";
                startedProbe[@"pending_completion_count"] = @0;
                startedProbe[@"error"] = @"Unexpected allBeaconsWithCompletion: method signature";
                [self storeFindMySearchPartyLocationProbe:startedProbe];
            } else {
                NSInvocation *beaconsInvocation = [NSInvocation invocationWithMethodSignature:beaconsSignature];
                [beaconsInvocation setTarget:targetSession];
                [beaconsInvocation setSelector:beaconsSelector];
                [beaconsInvocation setArgument:&beaconsCompletion atIndex:2];
                [beaconsInvocation retainArguments];
                [beaconsInvocation invoke];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    @synchronized ([BlueBubblesHelper class]) {
                        if (![findMySearchPartyLocationProbe[@"probe_id"] isEqualToString:probeId] ||
                            findMySearchPartyLocationProbe[@"beacon_result_class"] != nil) {
                            return;
                        }
                    }
                    id cachedBeacons = [self safeObjectValueFromObject:targetSession selectorName:@"allBeacons"] ?: [self safeObjectValueFromObject:targetSession selectorName:@"allBeaconsCache"];
                    if (cachedBeacons != nil && cachedBeacons != [NSNull null]) {
                        beaconsCompletion(cachedBeacons);
                    }
                });
            }
        } @catch (NSException *exception) {
            startedProbe[@"status"] = @"failed";
            startedProbe[@"pending_completion_count"] = @0;
            startedProbe[@"error"] = exception.reason ?: exception.description ?: @"Exception invoking allBeaconsWithCompletion:";
            [self storeFindMySearchPartyLocationProbe:startedProbe];
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @synchronized ([BlueBubblesHelper class]) {
                NSString *currentProbeId = findMySearchPartyLocationProbe[@"probe_id"];
                NSString *currentStatus = findMySearchPartyLocationProbe[@"status"];
                if ([currentProbeId isEqualToString:probeId] && [currentStatus isEqualToString:@"started"]) {
                    findMySearchPartyLocationProbe[@"status"] = @"timed_out";
                    findMySearchPartyLocationProbe[@"timed_out_at"] = @([[NSDate date] timeIntervalSince1970]);
                }
            }
        });
    }

    [[NetworkController sharedInstance] sendMessage:@{
        @"transactionId": transaction ?: [NSNull null],
        @"location_probe": [self findMySearchPartyLocationProbeStatus],
    }];
}

- (void)handleFindMySearchPartyLocationProbeStatusWithTransaction:(NSString *)transaction {
    [[NetworkController sharedInstance] sendMessage:@{
        @"transactionId": transaction ?: [NSNull null],
        @"location_probe": [self findMySearchPartyLocationProbeStatus],
    }];
}

- (void)handleFindMySearchPartyLocationProbeCompactStatusWithTransaction:(NSString *)transaction {
    [[NetworkController sharedInstance] sendMessage:@{
        @"transactionId": transaction ?: [NSNull null],
        @"location_probe": [self findMySearchPartyLocationProbeCompactStatus],
    }];
}

- (NSArray *)runtimeClassNamesMatchingTerms:(NSArray<NSString *> *)terms limit:(NSUInteger)limit {
    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) {
        return @[];
    }

    Class *classes = (__unsafe_unretained Class *)calloc((size_t)classCount, sizeof(Class));
    objc_getClassList(classes, classCount);

    NSMutableArray *matches = [[NSMutableArray alloc] init];
    for (int i = 0; i < classCount; i++) {
        NSString *className = NSStringFromClass(classes[i]);
        for (NSString *term in terms) {
            if ([className rangeOfString:term options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [matches addObject:className];
                break;
            }
        }
        if (matches.count >= limit) {
            break;
        }
    }

    free(classes);
    return [matches sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (BOOL)boolValueFromObject:(id)object selector:(SEL)selector {
    if (object == nil || ![object respondsToSelector:selector]) {
        return NO;
    }

    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (signature == nil) {
        return NO;
    }

    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:object];
    [invocation setSelector:selector];
    [invocation invoke];

    BOOL value = NO;
    [invocation getReturnValue:&value];
    return value;
}

- (NSString *)classNameForObject:(id)object {
    return object == nil ? @"<nil>" : NSStringFromClass([object class]);
}

- (BOOL)className:(NSString *)className matchesAnyTerm:(NSArray<NSString *> *)terms {
    for (NSString *term in terms) {
        if ([className rangeOfString:term options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

- (id)safeValueForKey:(NSString *)key object:(id)object {
    if (object == nil || key == nil) {
        return nil;
    }

    @try {
        return [object valueForKey:key];
    } @catch (NSException *exception) {
        return nil;
    }
}

- (void)setSafeValue:(id)value forKey:(NSString *)key object:(id)object {
    if (object == nil || key == nil || value == nil) {
        return;
    }

    @try {
        [object setValue:value forKey:key];
    } @catch (NSException *exception) {
    }
}

- (BOOL)setSafeIvarObjectValue:(id)value ivarName:(NSString *)ivarName object:(id)object {
    if (object == nil || value == nil || ivarName.length == 0) {
        return NO;
    }

    @try {
        Ivar ivar = class_getInstanceVariable([object class], [ivarName UTF8String]);
        if (ivar == NULL) {
            return NO;
        }
        object_setIvar(object, ivar, value);
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
}

- (BOOL)setSafeIvarRangeValue:(NSRange)value ivarName:(NSString *)ivarName object:(id)object {
    if (object == nil || ivarName.length == 0) {
        return NO;
    }

    @try {
        Ivar ivar = class_getInstanceVariable([object class], [ivarName UTF8String]);
        if (ivar == NULL) {
            return NO;
        }
        ptrdiff_t offset = ivar_getOffset(ivar);
        NSRange *slot = (NSRange *)((uint8_t *)(__bridge void *)object + offset);
        *slot = value;
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
}

- (NSDictionary *)summaryForValue:(id)value {
    if (value == nil) {
        return @{@"class": @"<nil>"};
    }

    NSMutableDictionary *summary = [[NSMutableDictionary alloc] initWithDictionary:@{
        @"class": [self classNameForObject:value],
    }];

    if ([value isKindOfClass:[NSArray class]]) {
        NSArray *array = (NSArray *)value;
        NSMutableArray *elementClasses = [[NSMutableArray alloc] init];
        NSUInteger limit = MIN(array.count, 10);
        for (NSUInteger i = 0; i < limit; i++) {
            [elementClasses addObject:[self classNameForObject:array[i]]];
        }
        summary[@"count"] = @(array.count);
        summary[@"element_classes"] = elementClasses;
    } else if ([value isKindOfClass:[NSSet class]]) {
        NSSet *set = (NSSet *)value;
        NSMutableArray *elementClasses = [[NSMutableArray alloc] init];
        NSUInteger index = 0;
        for (id element in set) {
            if (index >= 10) {
                break;
            }
            [elementClasses addObject:[self classNameForObject:element]];
            index++;
        }
        summary[@"count"] = @(set.count);
        summary[@"element_classes"] = elementClasses;
    } else if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = (NSDictionary *)value;
        NSMutableArray *keys = [[NSMutableArray alloc] init];
        for (id key in [dictionary allKeys]) {
            if (keys.count >= 10) {
                break;
            }
            [keys addObject:[key description] ?: @"<nil>"];
        }
        summary[@"count"] = @(dictionary.count);
        summary[@"keys"] = keys;
    } else if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSDate class]]) {
        summary[@"value"] = [value description];
    }

    return [summary copy];
}

- (NSArray *)objectChildrenForValue:(id)value {
    if (value == nil || value == [NSNull null]) {
        return @[];
    }

    if ([value isKindOfClass:[NSArray class]]) {
        return value;
    }

    if ([value isKindOfClass:[NSSet class]]) {
        return [(NSSet *)value allObjects];
    }

    if ([value isKindOfClass:[NSDictionary class]]) {
        return [(NSDictionary *)value allValues];
    }

    if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSDate class]]) {
        return @[];
    }

    return @[value];
}

- (NSArray *)searchPartyLocationBearingChildSnapshotsForValue:(id)value {
    NSArray *children = [self objectChildrenForValue:value];
    if (children.count == 0) {
        return @[];
    }

    NSMutableArray *snapshots = [[NSMutableArray alloc] init];
    for (id child in children) {
        if (snapshots.count >= 8) {
            break;
        }

        NSMutableDictionary *snapshot = [[NSMutableDictionary alloc] initWithDictionary:@{
            @"class": [self classNameForObject:child],
            @"summary": [self summaryForValue:child],
        }];

        NSString *description = [child description];
        if (description.length > 0) {
            snapshot[@"description"] = description.length > 240 ? [description substringToIndex:240] : description;
        }

        NSDictionary *location = [self serializeLocationObject:child];
        if (location != (NSDictionary *)[NSNull null]) {
            snapshot[@"location"] = location;
        }

        NSDictionary *fields = [self directFindMyFieldsForObject:child];
        if (fields.count > 0) {
            snapshot[@"fields"] = fields;
        }

        [snapshots addObject:[snapshot copy]];
    }

    return [snapshots copy];
}

- (NSDictionary *)inspectObject:(id)object {
    NSArray *keys = @[
        @"devices", @"items", @"allDevices", @"allItems", @"device", @"item",
        @"currentDevice", @"selectedDevice", @"devicesProvider", @"itemsProvider",
        @"deviceProvider", @"itemProvider", @"locationProvider", @"fmipManager",
        @"manager", @"provider", @"dataSource", @"delegate", @"representedObject",
        @"contentViewController", @"children", @"viewControllers",
        @"windowControllers", @"rootViewController",
        @"childViewControllers", @"presentedViewController", @"selectedViewController",
        @"navigationController", @"tabBarController", @"splitViewController",
        @"window", @"keyWindow"
    ];

    NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithDictionary:@{
        @"class": [self classNameForObject:object],
    }];

    NSMutableDictionary *kvcValues = [[NSMutableDictionary alloc] init];
    for (NSString *key in keys) {
        id value = [self safeValueForKey:key object:object];
        if (value != nil) {
            kvcValues[key] = [self summaryForValue:value];
        }
    }
    if (kvcValues.count > 0) {
        result[@"kvc"] = kvcValues;
    }

    NSMutableDictionary *ivars = [[NSMutableDictionary alloc] init];
    Class class = [object class];
    NSUInteger classDepth = 0;
    while (class != nil && classDepth < 6) {
        unsigned int ivarCount = 0;
        Ivar *ivarList = class_copyIvarList(class, &ivarCount);
        for (unsigned int i = 0; i < ivarCount; i++) {
            Ivar ivar = ivarList[i];
            const char *type = ivar_getTypeEncoding(ivar);
            if (type == NULL || type[0] != '@') {
                continue;
            }

            id value = nil;
            @try {
                value = object_getIvar(object, ivar);
            } @catch (NSException *exception) {
                value = nil;
            }

            if (value != nil) {
                NSString *name = [NSString stringWithUTF8String:ivar_getName(ivar)];
                ivars[name] = [self summaryForValue:value];
            }
        }
        free(ivarList);
        class = class_getSuperclass(class);
        classDepth++;
    }
    if (ivars.count > 0) {
        result[@"ivars"] = ivars;
    }

    return [result copy];
}

- (NSDictionary *)findMyObjectGraphDiagnostics {
    NSArray *terms = @[
        @"FindMy.", @"FindMyUICore.", @"FindMyAppCore.", @"FMIPCore.",
        @"FMDevice", @"FMItem", @"FMIP", @"FMPeople", @"FMLocation",
        @"FMDevices", @"FMItems", @"FMListViewController",
        @"FMPeopleListDataSource", @"FMDevicesListDataSource",
        @"FMItemsListDataSource", @"FMSegmentedControl",
        @"Repository", @"SessionLive", @"C6FindMy"
    ];
    NSMutableArray *roots = [[NSMutableArray alloc] init];
    if (NSApp != nil) {
        [roots addObject:NSApp];
        if (NSApp.delegate != nil) {
            [roots addObject:NSApp.delegate];
        }
        [roots addObjectsFromArray:NSApp.windows ?: @[]];
    }

    Class uiApplicationClass = NSClassFromString(@"UIApplication");
    SEL sharedApplicationSelector = NSSelectorFromString(@"sharedApplication");
    if (uiApplicationClass != nil && [uiApplicationClass respondsToSelector:sharedApplicationSelector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id uiApplication = [uiApplicationClass performSelector:sharedApplicationSelector];
#pragma clang diagnostic pop
        if (uiApplication != nil) {
            [roots addObject:uiApplication];
            id appDelegate = [self safeValueForKey:@"delegate" object:uiApplication];
            if (appDelegate != nil) {
                [roots addObject:appDelegate];
            }
            id windows = [self safeValueForKey:@"windows" object:uiApplication];
            for (id window in [self objectChildrenForValue:windows]) {
                [roots addObject:window];
            }
        }
    }

    NSMutableArray *queue = [[NSMutableArray alloc] init];
    for (id root in roots) {
        [queue addObject:@{@"object": root, @"path": [self classNameForObject:root], @"depth": @0}];
    }

    NSMutableSet *seen = [[NSMutableSet alloc] init];
    NSMutableArray *matches = [[NSMutableArray alloc] init];
    NSUInteger scanned = 0;

    while (queue.count > 0 && scanned < 1200 && matches.count < 180) {
        NSDictionary *entry = queue[0];
        [queue removeObjectAtIndex:0];

        id object = entry[@"object"];
        if (object == nil || object == [NSNull null]) {
            continue;
        }

        NSValue *identity = [NSValue valueWithNonretainedObject:object];
        if ([seen containsObject:identity]) {
            continue;
        }
        [seen addObject:identity];
        scanned++;

        NSString *path = entry[@"path"];
        NSUInteger depth = [entry[@"depth"] unsignedIntegerValue];
        NSString *className = [self classNameForObject:object];
        BOOL interesting = [self className:className matchesAnyTerm:terms];
        NSDictionary *inspection = [self inspectObject:object];

        if (!interesting) {
            for (NSDictionary *summary in [inspection[@"kvc"] allValues]) {
                if ([self className:summary[@"class"] ?: @"" matchesAnyTerm:terms]) {
                    interesting = YES;
                    break;
                }
            }
        }
        if (!interesting) {
            for (NSDictionary *summary in [inspection[@"ivars"] allValues]) {
                if ([self className:summary[@"class"] ?: @"" matchesAnyTerm:terms]) {
                    interesting = YES;
                    break;
                }
            }
        }

        if (interesting) {
            NSMutableDictionary *match = [[NSMutableDictionary alloc] initWithDictionary:inspection];
            match[@"path"] = path ?: className;
            [matches addObject:match];
        }

        if ([object isKindOfClass:NSClassFromString(@"UITableView")]) {
            for (NSString *key in @[@"dataSource", @"delegate"]) {
                id related = [self safeValueForKey:key object:object];
                if (related != nil && [self className:[self classNameForObject:related] matchesAnyTerm:terms]) {
                    NSMutableDictionary *relatedMatch = [[NSMutableDictionary alloc] initWithDictionary:[self inspectObject:related]];
                    relatedMatch[@"path"] = [NSString stringWithFormat:@"%@.%@", path, key];
                    [matches addObject:relatedMatch];
                }
            }
        }

        if (depth >= 8) {
            continue;
        }

        NSMutableArray *childValues = [[NSMutableArray alloc] init];
        NSDictionary *kvc = inspection[@"kvc"];
        for (NSString *key in kvc) {
            id value = [self safeValueForKey:key object:object];
            for (id child in [self objectChildrenForValue:value]) {
                [childValues addObject:@{@"object": child, @"path": [NSString stringWithFormat:@"%@.%@", path, key], @"depth": @(depth + 1)}];
            }
        }

        Class ivarClass = [object class];
        NSUInteger ivarClassDepth = 0;
        while (ivarClass != nil && ivarClassDepth < 6) {
            unsigned int ivarCount = 0;
            Ivar *ivarList = class_copyIvarList(ivarClass, &ivarCount);
            for (unsigned int i = 0; i < ivarCount; i++) {
                Ivar ivar = ivarList[i];
                const char *type = ivar_getTypeEncoding(ivar);
                if (type == NULL || type[0] != '@') {
                    continue;
                }

                id value = nil;
                @try {
                    value = object_getIvar(object, ivar);
                } @catch (NSException *exception) {
                    value = nil;
                }

                NSString *ivarName = [NSString stringWithUTF8String:ivar_getName(ivar)];
                for (id child in [self objectChildrenForValue:value]) {
                    [childValues addObject:@{@"object": child, @"path": [NSString stringWithFormat:@"%@->%@", path, ivarName], @"depth": @(depth + 1)}];
                }
            }
            free(ivarList);
            ivarClass = class_getSuperclass(ivarClass);
            ivarClassDepth++;
        }

        [queue addObjectsFromArray:childValues];
    }

    NSMutableArray *rootClasses = [[NSMutableArray alloc] init];
    for (id root in roots) {
        [rootClasses addObject:[self classNameForObject:root]];
    }

    return @{
        @"root_count": @(roots.count),
        @"root_classes": rootClasses,
        @"scanned": @(scanned),
        @"matches": matches,
    };
}

- (NSDictionary *)findMySessionObjectDiagnostics {
    NSArray *terms = @[
        @"Session", @"Provider", @"Manager", @"Repository", @"SPOwner",
        @"FMIP", @"Beacon", @"Device", @"Item"
    ];
    NSArray *interestingSelectors = @[
        @"devices", @"items", @"itemGroups", @"allBeacons", @"allBeaconsCache",
        @"allBeaconsWithCompletion:", @"startRefreshing", @"refresh",
        @"locationProvider", @"devicesProvider", @"itemsProvider",
        @"fmipManager", @"ownerSession", @"session", @"repository"
    ];

    NSMutableArray *queue = [[NSMutableArray alloc] init];
    for (NSString *term in @[@"FMDevicesListDataSource", @"FMItemsListDataSource"]) {
        NSDictionary *active = [self activeFindMyTableViewForDataSourceTerm:term];
        id tableView = active[@"tableView"];
        id dataSource = active[@"dataSource"];
        id delegate = [self safeValueForKey:@"delegate" object:tableView];
        for (NSDictionary *root in @[
            @{@"object": tableView ?: [NSNull null], @"path": [NSString stringWithFormat:@"%@.tableView", term], @"depth": @0},
            @{@"object": dataSource ?: [NSNull null], @"path": [NSString stringWithFormat:@"%@.dataSource", term], @"depth": @0},
            @{@"object": delegate ?: [NSNull null], @"path": [NSString stringWithFormat:@"%@.delegate", term], @"depth": @0},
        ]) {
            if (root[@"object"] != [NSNull null]) {
                [queue addObject:root];
            }
        }
    }

    NSMutableSet *seen = [[NSMutableSet alloc] init];
    NSMutableArray *matches = [[NSMutableArray alloc] init];
    NSUInteger scanned = 0;

    while (queue.count > 0 && scanned < 160 && matches.count < 80) {
        NSDictionary *entry = queue[0];
        [queue removeObjectAtIndex:0];

        id object = entry[@"object"];
        if (object == nil || object == [NSNull null]) {
            continue;
        }

        NSValue *identity = [NSValue valueWithNonretainedObject:object];
        if ([seen containsObject:identity]) {
            continue;
        }
        [seen addObject:identity];
        scanned++;

        NSString *path = entry[@"path"];
        NSUInteger depth = [entry[@"depth"] unsignedIntegerValue];
        NSString *className = [self classNameForObject:object];
        BOOL interesting = [self className:className matchesAnyTerm:terms];

        NSMutableArray *respondsTo = [[NSMutableArray alloc] init];
        for (NSString *selectorName in interestingSelectors) {
            if ([object respondsToSelector:NSSelectorFromString(selectorName)]) {
                [respondsTo addObject:selectorName];
                interesting = YES;
            }
        }

        NSMutableDictionary *matchingIvars = [[NSMutableDictionary alloc] init];
        NSMutableArray *nextObjects = [[NSMutableArray alloc] init];
        Class ivarScanClass = [object class];
        NSUInteger ivarScanDepth = 0;
        while (ivarScanClass != nil && ivarScanDepth < 5) {
            unsigned int ivarCount = 0;
            Ivar *ivarList = class_copyIvarList(ivarScanClass, &ivarCount);
            for (unsigned int i = 0; i < ivarCount; i++) {
                Ivar ivar = ivarList[i];
                const char *type = ivar_getTypeEncoding(ivar);
                if (type == NULL || type[0] != '@') {
                    continue;
                }

                id value = nil;
                @try {
                    value = object_getIvar(object, ivar);
                } @catch (NSException *exception) {
                    value = nil;
                }

                if (value == nil) {
                    continue;
                }
                NSString *ivarName = [NSString stringWithUTF8String:ivar_getName(ivar)];
                NSString *valueClass = [self classNameForObject:value];
                if ([self className:ivarName matchesAnyTerm:terms] || [self className:valueClass matchesAnyTerm:terms]) {
                    matchingIvars[ivarName] = [self summaryForValue:value];
                    [nextObjects addObject:@{@"object": value, @"path": [NSString stringWithFormat:@"%@->%@", path, ivarName], @"depth": @(depth + 1)}];
                    interesting = YES;
                }
            }
            free(ivarList);
            ivarScanClass = class_getSuperclass(ivarScanClass);
            ivarScanDepth++;
        }

        if (interesting) {
            NSMutableDictionary *match = [[NSMutableDictionary alloc] initWithDictionary:@{
                @"class": className ?: @"<nil>",
                @"path": path ?: className ?: @"<nil>",
                @"responds_to": respondsTo,
            }];
            if (matchingIvars.count > 0) {
                match[@"ivars"] = matchingIvars;
            }

            NSMutableArray *methodNames = [[NSMutableArray alloc] init];
            Class methodClass = [object class];
            NSUInteger methodDepth = 0;
            while (methodClass != nil && methodDepth < 4 && methodNames.count < 60) {
                unsigned int methodCount = 0;
                Method *methodList = class_copyMethodList(methodClass, &methodCount);
                for (unsigned int i = 0; i < methodCount && methodNames.count < 60; i++) {
                    NSString *methodName = NSStringFromSelector(method_getName(methodList[i]));
                    if ([self className:methodName matchesAnyTerm:terms] ||
                        [methodName rangeOfString:@"refresh" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                        [methodName rangeOfString:@"location" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                        [methodNames addObject:methodName];
                    }
                }
                free(methodList);
                methodClass = class_getSuperclass(methodClass);
                methodDepth++;
            }
            if (methodNames.count > 0) {
                match[@"methods"] = methodNames;
            }
            [matches addObject:[match copy]];
        }

        if (depth >= 2) {
            continue;
        }

        [queue addObjectsFromArray:nextObjects];
    }

    return @{
        @"scanned": @(scanned),
        @"matches": matches,
    };
}

- (NSArray *)findMyRootObjects {
    NSMutableArray *roots = [[NSMutableArray alloc] init];
    if (NSApp != nil) {
        [roots addObject:NSApp];
        if (NSApp.delegate != nil) {
            [roots addObject:NSApp.delegate];
        }
        [roots addObjectsFromArray:NSApp.windows ?: @[]];
    }

    Class uiApplicationClass = NSClassFromString(@"UIApplication");
    SEL sharedApplicationSelector = NSSelectorFromString(@"sharedApplication");
    if (uiApplicationClass != nil && [uiApplicationClass respondsToSelector:sharedApplicationSelector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id uiApplication = [uiApplicationClass performSelector:sharedApplicationSelector];
#pragma clang diagnostic pop
        if (uiApplication != nil) {
            [roots addObject:uiApplication];
            id appDelegate = [self safeValueForKey:@"delegate" object:uiApplication];
            if (appDelegate != nil) {
                [roots addObject:appDelegate];
            }
            id windows = [self safeValueForKey:@"windows" object:uiApplication];
            for (id window in [self objectChildrenForValue:windows]) {
                [roots addObject:window];
            }
        }
    }
    return [roots copy];
}

- (NSDictionary *)activeFindMyTableViewForDataSourceTerm:(NSString *)dataSourceTerm {
    NSMutableArray *queue = [[NSMutableArray alloc] init];
    for (id root in [self findMyRootObjects]) {
        [queue addObject:@{@"object": root, @"depth": @0}];
    }

    NSMutableSet *seen = [[NSMutableSet alloc] init];
    NSUInteger scanned = 0;
    while (queue.count > 0 && scanned < 1800) {
        NSDictionary *entry = queue[0];
        [queue removeObjectAtIndex:0];

        id object = entry[@"object"];
        if (object == nil || object == [NSNull null]) {
            continue;
        }

        NSValue *identity = [NSValue valueWithNonretainedObject:object];
        if ([seen containsObject:identity]) {
            continue;
        }
        [seen addObject:identity];
        scanned++;

        NSString *className = [self classNameForObject:object];
        if ([className rangeOfString:@"FMTableView" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [object isKindOfClass:NSClassFromString(@"UITableView")]) {
            id dataSource = [self safeValueForKey:@"dataSource" object:object];
            NSString *dataSourceClass = [self classNameForObject:dataSource];
            if ([dataSourceClass rangeOfString:dataSourceTerm options:NSCaseInsensitiveSearch].location != NSNotFound) {
                return @{
                    @"tableView": object,
                    @"dataSource": dataSource,
                    @"scanned": @(scanned),
                };
            }
        }

        NSUInteger depth = [entry[@"depth"] unsignedIntegerValue];
        if (depth >= 8) {
            continue;
        }

        NSDictionary *inspection = [self inspectObject:object];
        for (NSString *key in inspection[@"kvc"]) {
            id value = [self safeValueForKey:key object:object];
            for (id child in [self objectChildrenForValue:value]) {
                [queue addObject:@{@"object": child, @"depth": @(depth + 1)}];
            }
        }

        Class ivarClass = [object class];
        NSUInteger ivarClassDepth = 0;
        while (ivarClass != nil && ivarClassDepth < 6) {
            unsigned int ivarCount = 0;
            Ivar *ivarList = class_copyIvarList(ivarClass, &ivarCount);
            for (unsigned int i = 0; i < ivarCount; i++) {
                Ivar ivar = ivarList[i];
                const char *type = ivar_getTypeEncoding(ivar);
                if (type == NULL || type[0] != '@') {
                    continue;
                }

                id value = nil;
                @try {
                    value = object_getIvar(object, ivar);
                } @catch (NSException *exception) {
                    value = nil;
                }

                for (id child in [self objectChildrenForValue:value]) {
                    [queue addObject:@{@"object": child, @"depth": @(depth + 1)}];
                }
            }
            free(ivarList);
            ivarClass = class_getSuperclass(ivarClass);
            ivarClassDepth++;
        }
    }

    return nil;
}

- (NSArray *)textValuesInObject:(id)object maxDepth:(NSUInteger)maxDepth {
    if (object == nil || object == [NSNull null]) {
        return @[];
    }

    NSMutableArray *texts = [[NSMutableArray alloc] init];
    NSMutableArray *queue = [[NSMutableArray alloc] initWithObjects:@{@"object": object, @"depth": @0}, nil];
    NSMutableSet *seen = [[NSMutableSet alloc] init];

    while (queue.count > 0 && texts.count < 24) {
        NSDictionary *entry = queue[0];
        [queue removeObjectAtIndex:0];

        id current = entry[@"object"];
        if (current == nil || current == [NSNull null]) {
            continue;
        }

        NSValue *identity = [NSValue valueWithNonretainedObject:current];
        if ([seen containsObject:identity]) {
            continue;
        }
        [seen addObject:identity];

        for (NSString *selectorName in @[@"text", @"stringValue", @"title", @"subtitle", @"accessibilityLabel", @"accessibilityValue"]) {
            SEL selector = NSSelectorFromString(selectorName);
            if ([current respondsToSelector:selector]) {
                id value = [self objectValueFromObject:current selector:selector];
                if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0 && ![texts containsObject:value]) {
                    [texts addObject:value];
                }
            }
        }

        NSUInteger depth = [entry[@"depth"] unsignedIntegerValue];
        if (depth >= maxDepth) {
            continue;
        }

        for (NSString *childKey in @[@"subviews", @"contentView", @"accessibilityElements", @"arrangedSubviews"]) {
            id children = [self safeValueForKey:childKey object:current];
            for (id child in [self objectChildrenForValue:children]) {
                [queue addObject:@{@"object": child, @"depth": @(depth + 1)}];
            }
        }

    }

    return [texts copy];
}

- (NSString *)stringValueForFindMyValue:(id)value {
    if (value == nil || value == [NSNull null]) {
        return nil;
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value length] > 0 ? value : nil;
    }
    if ([value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSDate class]]) {
        return [value description];
    }
    return nil;
}

- (NSDictionary *)directFindMyFieldsForObject:(id)object {
    if (object == nil || object == [NSNull null]) {
        return @{};
    }
    if ([object isKindOfClass:[NSArray class]] || [object isKindOfClass:[NSSet class]] || [object isKindOfClass:[NSDictionary class]]) {
        return @{};
    }

    NSArray *keys = @[
        @"identifier", @"id", @"stableIdentifier", @"accessoryIdentifier", @"beaconIdentifier",
        @"uuid", @"beaconUUID", @"serialNumber", @"productIdentifier", @"name", @"displayName",
        @"title", @"subtitle", @"deviceName", @"accessoryName", @"modelName", @"modelDisplayName",
        @"deviceModel", @"rawDeviceModel", @"batteryStatus", @"batteryLevel", @"role", @"location",
        @"lastLocation", @"latestLocation", @"crowdSourcedLocation"
    ];

    NSMutableDictionary *fields = [[NSMutableDictionary alloc] init];
    for (NSString *key in keys) {
        id value = [self safeValueForKey:key object:object];
        if (value == nil || value == [NSNull null]) {
            continue;
        }

        if ([key rangeOfString:@"location" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            NSDictionary *serializedLocation = [self serializeLocationObject:value];
            if (serializedLocation != (NSDictionary *)[NSNull null]) {
                fields[key] = serializedLocation;
            } else {
                fields[key] = [self summaryForValue:value];
            }
            continue;
        }

        NSString *stringValue = [self stringValueForFindMyValue:value];
        fields[key] = stringValue ?: [self summaryForValue:value];
    }

    return [fields copy];
}

- (id)directFindMyCandidateValueFromObject:(id)object key:(NSString *)key {
    id value = [self safeValueForKey:key object:object];
    if (value != nil && value != [NSNull null]) {
        return value;
    }

    SEL selector = NSSelectorFromString(key);
    if (selector != nil && [object respondsToSelector:selector]) {
        return [self objectValueFromObject:object selector:selector];
    }

    return nil;
}

- (NSArray *)directFindMyIvarCandidatesForObject:(id)object {
    if (object == nil || object == [NSNull null]) {
        return @[];
    }

    NSArray *terms = @[
        @"FMDevice", @"FMItem", @"CellViewModel", @"FMIP", @"SPBeacon",
        @"Device", @"Item", @"Beacon", @"Location"
    ];
    NSMutableArray *candidates = [[NSMutableArray alloc] init];
    Class class = [object class];
    NSUInteger classDepth = 0;
    while (class != nil && classDepth < 4 && candidates.count < 16) {
        unsigned int ivarCount = 0;
        Ivar *ivarList = class_copyIvarList(class, &ivarCount);
        for (unsigned int i = 0; i < ivarCount && candidates.count < 16; i++) {
            Ivar ivar = ivarList[i];
            const char *type = ivar_getTypeEncoding(ivar);
            if (type == NULL || type[0] != '@') {
                continue;
            }

            id value = nil;
            @try {
                value = object_getIvar(object, ivar);
            } @catch (NSException *exception) {
                value = nil;
            }
            if (value == nil || value == [NSNull null]) {
                continue;
            }

            NSString *name = [NSString stringWithUTF8String:ivar_getName(ivar)] ?: @"<ivar>";
            NSString *valueClass = [self classNameForObject:value];
            BOOL interesting = [self className:name matchesAnyTerm:terms] || [self className:valueClass matchesAnyTerm:terms];
            if (!interesting) {
                continue;
            }

            [candidates addObject:@{
                @"source": [NSString stringWithFormat:@"ivar:%@", name],
                @"object": value,
            }];
        }
        free(ivarList);
        class = class_getSuperclass(class);
        classDepth++;
    }

    return [candidates copy];
}

- (NSDictionary *)findMyModelDetailsForCell:(id)cell dataSource:(id)dataSource {
    NSMutableArray *candidates = [[NSMutableArray alloc] init];
    [candidates addObject:@{@"source": @"cell", @"object": cell}];
    if (dataSource != nil) {
        [candidates addObject:@{@"source": @"dataSource", @"object": dataSource}];
    }

    for (NSString *key in @[
        @"viewModel", @"cellViewModel", @"model", @"device", @"item", @"beacon",
        @"representedObject", @"contentConfiguration", @"configuration"
    ]) {
        id value = [self directFindMyCandidateValueFromObject:cell key:key];
        if (value != nil && value != [NSNull null]) {
            [candidates addObject:@{@"source": key, @"object": value}];
        }
    }

    [candidates addObjectsFromArray:[self directFindMyIvarCandidatesForObject:cell]];

    NSMutableArray *details = [[NSMutableArray alloc] init];
    NSMutableSet *seen = [[NSMutableSet alloc] init];
    for (NSDictionary *candidate in candidates) {
        id object = candidate[@"object"];
        if (object == nil || object == [NSNull null]) {
            continue;
        }
        NSValue *identity = [NSValue valueWithNonretainedObject:object];
        if ([seen containsObject:identity]) {
            continue;
        }
        [seen addObject:identity];

        NSMutableDictionary *detail = [[NSMutableDictionary alloc] initWithDictionary:@{
            @"source": candidate[@"source"] ?: @"<unknown>",
            @"class": [self classNameForObject:object],
            @"summary": [self summaryForValue:object],
        }];

        NSDictionary *fields = [self directFindMyFieldsForObject:object];
        if (fields.count > 0) {
            detail[@"fields"] = fields;
        }

        NSArray *texts = [self textValuesInObject:object maxDepth:2];
        if (texts.count > 0) {
            detail[@"texts"] = texts;
        }

        if ([[self classNameForObject:object] rangeOfString:@"CellViewModel" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            detail[@"selectors"] = [[self selectorNamesForClass:[object class] includeClassMethods:NO] subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)40, [[self selectorNamesForClass:[object class] includeClassMethods:NO] count]))];
        }

        [details addObject:[detail copy]];
        if (details.count >= 12) {
            break;
        }
    }

    return @{@"candidates": [details copy]};
}

- (NSDictionary *)serializeFindMyListCell:(id)cell
                               dataSource:(id)dataSource
                                  section:(NSInteger)section
                                     row:(NSInteger)row
                                     type:(NSString *)type {
    NSArray *texts = [self textValuesInObject:cell maxDepth:4];
    NSDictionary *modelDetails = [self findMyModelDetailsForCell:cell dataSource:dataSource];
    NSString *name = texts.count > 0 ? texts[0] : [NSString stringWithFormat:@"%@ %ld-%ld", type, (long)section, (long)row];
    NSString *identifier = [NSString stringWithFormat:@"%@:%ld:%ld", type, (long)section, (long)row];

    for (NSDictionary *candidate in modelDetails[@"candidates"] ?: @[]) {
        NSDictionary *fields = candidate[@"fields"];
        if (![fields isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        for (NSString *nameKey in @[@"name", @"displayName", @"title", @"deviceName", @"accessoryName", @"modelDisplayName"]) {
            NSString *candidateName = [self stringValueForFindMyValue:fields[nameKey]];
            if (candidateName.length > 0) {
                name = candidateName;
                break;
            }
        }
        for (NSString *identifierKey in @[@"identifier", @"id", @"stableIdentifier", @"accessoryIdentifier", @"beaconIdentifier", @"uuid", @"beaconUUID", @"serialNumber"]) {
            NSString *candidateIdentifier = [self stringValueForFindMyValue:fields[identifierKey]];
            if (candidateIdentifier.length > 0) {
                identifier = candidateIdentifier;
                break;
            }
        }
    }

    NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithDictionary:@{
        @"id": identifier,
        @"identifier": identifier,
        @"name": name ?: [NSNull null],
        @"deviceDisplayName": name ?: [NSNull null],
        @"deviceModel": type,
        @"rawDeviceModel": type,
        @"modelDisplayName": [type isEqualToString:@"item"] ? @"Find My Item" : @"Find My Device",
        @"batteryStatus": @"Unknown",
        @"audioChannels": @[],
        @"locationEnabled": @YES,
        @"isConsideredAccessory": @([type isEqualToString:@"item"]),
        @"locationCapable": @YES,
        @"fmlyShare": @NO,
        @"thisDevice": @NO,
        @"isMac": @NO,
        @"lostModeEnabled": @NO,
        @"deviceClass": type,
        @"prsId": @"owner",
        @"findmy_ui": @{
            @"section": @(section),
            @"row": @(row),
            @"cellClass": [self classNameForObject:cell],
            @"dataSourceClass": [self classNameForObject:dataSource],
            @"texts": texts ?: @[],
            @"modelDetails": modelDetails,
        },
    }];

    for (NSDictionary *candidate in modelDetails[@"candidates"] ?: @[]) {
        NSDictionary *fields = candidate[@"fields"];
        if (![fields isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        for (NSString *locationKey in @[@"location", @"lastLocation", @"latestLocation", @"crowdSourcedLocation"]) {
            id location = fields[locationKey];
            if ([location isKindOfClass:[NSDictionary class]] && location[@"latitude"] != nil && location[@"longitude"] != nil) {
                result[@"location"] = location;
                break;
            }
        }
        if (result[@"location"] != nil) {
            break;
        }
    }

    if ([type isEqualToString:@"item"]) {
        result[@"findmy_item"] = result[@"findmy_ui"];
    } else {
        result[@"findmy_device"] = result[@"findmy_ui"];
    }

    return [result copy];
}

- (NSArray *)findMyListRowsForDataSourceTerm:(NSString *)dataSourceTerm type:(NSString *)type {
    NSDictionary *active = [self activeFindMyTableViewForDataSourceTerm:dataSourceTerm];
    id tableView = active[@"tableView"];
    id dataSource = active[@"dataSource"];
    if (tableView == nil || dataSource == nil) {
        return @[];
    }

    SEL visibleCellsSelector = @selector(visibleCells);
    if (![tableView respondsToSelector:visibleCellsSelector]) {
        return @[];
    }

    id (*visibleCells)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    NSArray *cells = nil;
    @try {
        id visible = visibleCells(tableView, visibleCellsSelector);
        if ([visible isKindOfClass:[NSArray class]]) {
            cells = visible;
        }
    } @catch (NSException *exception) {
        cells = nil;
    }

    NSMutableArray *rows = [[NSMutableArray alloc] init];
    NSInteger row = 0;
    for (id cell in cells ?: @[]) {
        if (rows.count >= 80) {
            break;
        }
        if (cell != nil) {
            [rows addObject:[self serializeFindMyListCell:cell dataSource:dataSource section:0 row:row type:type]];
        }
        row++;
    }

    return [rows copy];
}

- (NSDictionary *)activeFindMyListDiagnosticsForDataSourceTerm:(NSString *)dataSourceTerm type:(NSString *)type {
    NSDictionary *active = [self activeFindMyTableViewForDataSourceTerm:dataSourceTerm];
    id tableView = active[@"tableView"];
    id dataSource = active[@"dataSource"];
    id delegate = [self safeValueForKey:@"delegate" object:tableView];

    NSMutableDictionary *diagnostics = [[NSMutableDictionary alloc] initWithDictionary:@{
        @"requested_data_source_term": dataSourceTerm ?: @"<nil>",
        @"type": type ?: @"<nil>",
        @"found": @(tableView != nil && dataSource != nil),
        @"active_scan_count": active[@"scanned"] ?: @0,
        @"table_view_class": [self classNameForObject:tableView],
        @"data_source_class": [self classNameForObject:dataSource],
        @"delegate_class": [self classNameForObject:delegate],
    }];

    SEL visibleCellsSelector = @selector(visibleCells);
    if (tableView != nil && [tableView respondsToSelector:visibleCellsSelector]) {
        id (*visibleCells)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        NSArray *cells = nil;
        @try {
            id visible = visibleCells(tableView, visibleCellsSelector);
            if ([visible isKindOfClass:[NSArray class]]) {
                cells = visible;
            }
        } @catch (NSException *exception) {
            cells = nil;
        }

        NSMutableArray *cellDiagnostics = [[NSMutableArray alloc] init];
        NSUInteger row = 0;
        for (id cell in cells ?: @[]) {
            if (cellDiagnostics.count >= 20) {
                break;
            }
            [cellDiagnostics addObject:@{
                @"row": @(row),
                @"class": [self classNameForObject:cell],
                @"summary": [self summaryForValue:cell],
            }];
            row++;
        }
        diagnostics[@"visible_cell_count"] = @(cells.count);
        diagnostics[@"visible_cells"] = cellDiagnostics;
    }

    return [diagnostics copy];
}

- (BOOL)selectFindMySegmentIndex:(NSInteger)index {
    NSArray *sectionSelectors = @[
        NSStringFromSelector(NSSelectorFromString(@"showPeople")),
        NSStringFromSelector(NSSelectorFromString(@"showDevices")),
        NSStringFromSelector(NSSelectorFromString(@"showItems")),
    ];
    if (index >= 0 && index < (NSInteger)sectionSelectors.count) {
        SEL sectionSelector = NSSelectorFromString(sectionSelectors[(NSUInteger)index]);
        Class uiApplicationClass = NSClassFromString(@"UIApplication");
        SEL sharedApplicationSelector = NSSelectorFromString(@"sharedApplication");
        SEL sendActionSelector = NSSelectorFromString(@"sendAction:to:from:forEvent:");
        if (uiApplicationClass != nil && [uiApplicationClass respondsToSelector:sharedApplicationSelector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id uiApplication = [uiApplicationClass performSelector:sharedApplicationSelector];
#pragma clang diagnostic pop
            if (uiApplication != nil && [uiApplication respondsToSelector:sendActionSelector]) {
                BOOL (*sendAction)(id, SEL, SEL, id, id, id) = (BOOL (*)(id, SEL, SEL, id, id, id))objc_msgSend;
                BOOL didSendAction = sendAction(uiApplication, sendActionSelector, sectionSelector, nil, nil, nil);
                if (didSendAction) {
                    DLog("BLUEBUBBLESHELPER: Sent Find My section action %@ through UIApplication", NSStringFromSelector(sectionSelector));
                    return YES;
                }
            }
        }

        CGKeyCode keyCode = 0;
        if (index == 0) {
            keyCode = 18;
        } else if (index == 1) {
            keyCode = 19;
        } else if (index == 2) {
            keyCode = 20;
        }
        if (keyCode != 0) {
            [[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
            CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
            CGEventRef keyDown = CGEventCreateKeyboardEvent(source, keyCode, true);
            CGEventRef keyUp = CGEventCreateKeyboardEvent(source, keyCode, false);
            if (keyDown != NULL && keyUp != NULL) {
                CGEventSetFlags(keyDown, kCGEventFlagMaskCommand);
                CGEventSetFlags(keyUp, kCGEventFlagMaskCommand);
                CGEventPost(kCGHIDEventTap, keyDown);
                usleep(120000);
                CGEventPost(kCGHIDEventTap, keyUp);
                DLog("BLUEBUBBLESHELPER: Posted Find My command key for %@", NSStringFromSelector(sectionSelector));
                CFRelease(keyDown);
                CFRelease(keyUp);
                if (source != NULL) {
                    CFRelease(source);
                }
                return YES;
            }
            if (keyDown != NULL) {
                CFRelease(keyDown);
            }
            if (keyUp != NULL) {
                CFRelease(keyUp);
            }
            if (source != NULL) {
                CFRelease(source);
            }
        }

        NSMutableArray *selectorQueue = [[NSMutableArray alloc] init];
        for (id root in [self findMyRootObjects]) {
            [selectorQueue addObject:@{@"object": root, @"depth": @0}];
        }

        NSMutableSet *selectorSeen = [[NSMutableSet alloc] init];
        NSUInteger selectorScanned = 0;
        while (selectorQueue.count > 0 && selectorScanned < 1600) {
            NSDictionary *entry = selectorQueue[0];
            [selectorQueue removeObjectAtIndex:0];

            id object = entry[@"object"];
            if (object == nil || object == [NSNull null]) {
                continue;
            }

            NSValue *identity = [NSValue valueWithNonretainedObject:object];
            if ([selectorSeen containsObject:identity]) {
                continue;
            }
            [selectorSeen addObject:identity];
            selectorScanned++;

            if ([object respondsToSelector:sectionSelector]) {
                DLog("BLUEBUBBLESHELPER: Invoking Find My section selector %@ on %@", NSStringFromSelector(sectionSelector), [self classNameForObject:object]);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [object performSelector:sectionSelector];
#pragma clang diagnostic pop
                return YES;
            }

            NSUInteger depth = [entry[@"depth"] unsignedIntegerValue];
            if (depth >= 8) {
                continue;
            }

            NSDictionary *inspection = [self inspectObject:object];
            for (NSString *key in inspection[@"kvc"]) {
                id value = [self safeValueForKey:key object:object];
                for (id child in [self objectChildrenForValue:value]) {
                    [selectorQueue addObject:@{@"object": child, @"depth": @(depth + 1)}];
                }
            }

            Class ivarClass = [object class];
            NSUInteger ivarClassDepth = 0;
            while (ivarClass != nil && ivarClassDepth < 6) {
                unsigned int ivarCount = 0;
                Ivar *ivarList = class_copyIvarList(ivarClass, &ivarCount);
                for (unsigned int i = 0; i < ivarCount; i++) {
                    Ivar ivar = ivarList[i];
                    const char *type = ivar_getTypeEncoding(ivar);
                    if (type == NULL || type[0] != '@') {
                        continue;
                    }

                    id value = nil;
                    @try {
                        value = object_getIvar(object, ivar);
                    } @catch (NSException *exception) {
                        value = nil;
                    }

                    for (id child in [self objectChildrenForValue:value]) {
                        [selectorQueue addObject:@{@"object": child, @"depth": @(depth + 1)}];
                    }
                }
                free(ivarList);
                ivarClass = class_getSuperclass(ivarClass);
                ivarClassDepth++;
            }
        }
    }

    NSMutableArray *queue = [[NSMutableArray alloc] init];
    for (id root in [self findMyRootObjects]) {
        [queue addObject:@{@"object": root, @"depth": @0}];
    }

    NSMutableSet *seen = [[NSMutableSet alloc] init];
    NSUInteger scanned = 0;
    while (queue.count > 0 && scanned < 1200) {
        NSDictionary *entry = queue[0];
        [queue removeObjectAtIndex:0];

        id object = entry[@"object"];
        if (object == nil || object == [NSNull null]) {
            continue;
        }

        NSValue *identity = [NSValue valueWithNonretainedObject:object];
        if ([seen containsObject:identity]) {
            continue;
        }
        [seen addObject:identity];
        scanned++;

        NSString *className = [self classNameForObject:object];
        if ([className rangeOfString:@"SegmentedControl" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            SEL setSelectedSegmentIndex = NSSelectorFromString(@"setSelectedSegmentIndex:");
            if ([object respondsToSelector:setSelectedSegmentIndex]) {
                NSMethodSignature *signature = [object methodSignatureForSelector:setSelectedSegmentIndex];
                NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
                [invocation setTarget:object];
                [invocation setSelector:setSelectedSegmentIndex];
                [invocation setArgument:&index atIndex:2];
                [invocation invoke];

                SEL sendActions = NSSelectorFromString(@"sendActionsForControlEvents:");
                if ([object respondsToSelector:sendActions]) {
                    NSUInteger valueChangedEvent = 1 << 12;
                    NSMethodSignature *actionSignature = [object methodSignatureForSelector:sendActions];
                    NSInvocation *actionInvocation = [NSInvocation invocationWithMethodSignature:actionSignature];
                    [actionInvocation setTarget:object];
                    [actionInvocation setSelector:sendActions];
                    [actionInvocation setArgument:&valueChangedEvent atIndex:2];
                    [actionInvocation invoke];
                }
                return YES;
            }
        }

        NSUInteger depth = [entry[@"depth"] unsignedIntegerValue];
        if (depth >= 8) {
            continue;
        }

        NSDictionary *inspection = [self inspectObject:object];
        for (NSString *key in inspection[@"kvc"]) {
            id value = [self safeValueForKey:key object:object];
            for (id child in [self objectChildrenForValue:value]) {
                [queue addObject:@{@"object": child, @"depth": @(depth + 1)}];
            }
        }

        Class ivarClass = [object class];
        NSUInteger ivarClassDepth = 0;
        while (ivarClass != nil && ivarClassDepth < 6) {
            unsigned int ivarCount = 0;
            Ivar *ivarList = class_copyIvarList(ivarClass, &ivarCount);
            for (unsigned int i = 0; i < ivarCount; i++) {
                Ivar ivar = ivarList[i];
                const char *type = ivar_getTypeEncoding(ivar);
                if (type == NULL || type[0] != '@') {
                    continue;
                }

                id value = nil;
                @try {
                    value = object_getIvar(object, ivar);
                } @catch (NSException *exception) {
                    value = nil;
                }

                for (id child in [self objectChildrenForValue:value]) {
                    [queue addObject:@{@"object": child, @"depth": @(depth + 1)}];
                }
            }
            free(ivarList);
            ivarClass = class_getSuperclass(ivarClass);
            ivarClassDepth++;
        }
    }
    return NO;
}

- (NSDictionary *)serializeFMLDevice:(id)device {
    if (device == nil) {
        return @{};
    }

    NSString *identifier = [self objectValueFromObject:device selector:@selector(identifier)];
    NSString *deviceName = [self objectValueFromObject:device selector:@selector(deviceName)];
    NSString *idsDeviceId = [self objectValueFromObject:device selector:@selector(idsDeviceId)];

    return @{
        @"id": identifier ?: idsDeviceId ?: [device description],
        @"name": deviceName ?: [device description],
        @"deviceDisplayName": deviceName ?: [NSNull null],
        @"deviceModel": @"FMLDevice",
        @"rawDeviceModel": @"FMLDevice",
        @"modelDisplayName": @"Find My Device",
        @"batteryStatus": @"Unknown",
        @"audioChannels": @[],
        @"locationEnabled": @YES,
        @"isConsideredAccessory": @NO,
        @"locationCapable": @YES,
        @"fmlyShare": @NO,
        @"thisDevice": @([self boolValueFromObject:device selector:@selector(isThisDevice)]),
        @"isMac": @NO,
        @"lostModeEnabled": @NO,
        @"deviceClass": @"FMLDevice",
        @"prsId": @"owner",
        @"findmy_device": @{
            @"identifier": identifier ?: [NSNull null],
            @"idsDeviceId": idsDeviceId ?: [NSNull null],
            @"deviceName": deviceName ?: [NSNull null],
            @"description": [device description] ?: [NSNull null],
            @"isActive": [device respondsToSelector:@selector(isActive)] ? @([self boolValueFromObject:device selector:@selector(isActive)]) : [NSNull null],
            @"isThisDevice": [device respondsToSelector:@selector(isThisDevice)] ? @([self boolValueFromObject:device selector:@selector(isThisDevice)]) : [NSNull null],
            @"isCompanion": [device respondsToSelector:@selector(isCompanion)] ? @([self boolValueFromObject:device selector:@selector(isCompanion)]) : [NSNull null],
            @"isAutoMeCapable": [device respondsToSelector:@selector(isAutoMeCapable)] ? @([self boolValueFromObject:device selector:@selector(isAutoMeCapable)]) : [NSNull null],
        },
    };
}

- (id)firstObjectValueFromObject:(id)object keys:(NSArray<NSString *> *)keys selectors:(NSArray<NSString *> *)selectors {
    for (NSString *key in keys) {
        id value = [self safeValueForKey:key object:object];
        if (value != nil && value != [NSNull null]) {
            return value;
        }
    }

    for (NSString *selectorName in selectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([object respondsToSelector:selector]) {
            id value = [self objectValueFromObject:object selector:selector];
            if (value != nil && value != [NSNull null]) {
                return value;
            }
        }
    }

    return nil;
}

- (NSDictionary *)serializeLocationObject:(id)location {
    if (location == nil || location == [NSNull null]) {
        return (NSDictionary *)[NSNull null];
    }

    id nestedLocation = [self firstObjectValueFromObject:location keys:@[@"location", @"clLocation"] selectors:@[@"location", @"clLocation"]];
    if (nestedLocation != nil && nestedLocation != location) {
        location = nestedLocation;
    }

    CLLocationDegrees latitude = 0;
    CLLocationDegrees longitude = 0;
    BOOL hasCoordinate = NO;
    if ([location respondsToSelector:@selector(coordinate)]) {
        CLLocationCoordinate2D (*coordinateGetter)(id, SEL) = (CLLocationCoordinate2D (*)(id, SEL))objc_msgSend;
        CLLocationCoordinate2D coordinate = coordinateGetter(location, @selector(coordinate));
        latitude = coordinate.latitude;
        longitude = coordinate.longitude;
        hasCoordinate = CLLocationCoordinate2DIsValid(coordinate);
    } else {
        id latitudeValue = [self firstObjectValueFromObject:location keys:@[@"latitude"] selectors:@[@"latitude"]];
        id longitudeValue = [self firstObjectValueFromObject:location keys:@[@"longitude"] selectors:@[@"longitude"]];
        if ([latitudeValue respondsToSelector:@selector(doubleValue)] && [longitudeValue respondsToSelector:@selector(doubleValue)]) {
            latitude = [latitudeValue doubleValue];
            longitude = [longitudeValue doubleValue];
            hasCoordinate = YES;
        }
    }

    if (!hasCoordinate) {
        return (NSDictionary *)[NSNull null];
    }

    NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithDictionary:@{
        @"latitude": @(latitude),
        @"longitude": @(longitude),
    }];

    id horizontalAccuracy = [self firstObjectValueFromObject:location keys:@[@"horizontalAccuracy"] selectors:@[@"horizontalAccuracy"]];
    if ([horizontalAccuracy respondsToSelector:@selector(doubleValue)]) {
        result[@"horizontalAccuracy"] = @([horizontalAccuracy doubleValue]);
    }

    id timestamp = [self firstObjectValueFromObject:location keys:@[@"timestamp", @"timeStamp", @"date"] selectors:@[@"timestamp", @"timeStamp", @"date"]];
    if ([timestamp isKindOfClass:[NSDate class]]) {
        result[@"timeStamp"] = @([(NSDate *)timestamp timeIntervalSince1970] * 1000);
    } else if ([timestamp respondsToSelector:@selector(doubleValue)]) {
        result[@"timeStamp"] = @([timestamp doubleValue] * 1000);
    }

    return [result copy];
}

- (NSDictionary *)serializeOwnerBeacon:(id)beacon {
    NSString *identifier = [[self firstObjectValueFromObject:beacon
                                                       keys:@[@"identifier", @"uuid", @"beaconUUID", @"accessoryIdentifier"]
                                                  selectors:@[@"identifier", @"uuid", @"beaconUUID", @"accessoryIdentifier"]] description];
    NSString *name = [[self firstObjectValueFromObject:beacon
                                                  keys:@[@"name", @"displayName", @"accessoryName"]
                                             selectors:@[@"name", @"displayName", @"accessoryName"]] description];
    id serialNumber = [self firstObjectValueFromObject:beacon keys:@[@"serialNumber"] selectors:@[@"serialNumber"]];
    id productIdentifier = [self firstObjectValueFromObject:beacon keys:@[@"productIdentifier"] selectors:@[@"productIdentifier"]];
    id batteryStatus = [self firstObjectValueFromObject:beacon keys:@[@"batteryStatus"] selectors:@[@"batteryStatus"]];
    id role = [self firstObjectValueFromObject:beacon keys:@[@"role"] selectors:@[@"role"]];
    id location = [self firstObjectValueFromObject:beacon
                                              keys:@[@"location", @"lastLocation", @"latestLocation"]
                                         selectors:@[@"location", @"lastLocation", @"latestLocation"]];

    NSDictionary *serializedLocation = [self serializeLocationObject:location];
    NSString *deviceName = name.length > 0 ? name : (identifier ?: [beacon description]);

    NSMutableDictionary *device = [[NSMutableDictionary alloc] initWithDictionary:@{
        @"id": identifier ?: [beacon description],
        @"identifier": identifier ?: [NSNull null],
        @"name": deviceName ?: [NSNull null],
        @"deviceDisplayName": [NSNull null],
        @"deviceModel": @"beacon",
        @"rawDeviceModel": @"beacon",
        @"modelDisplayName": @"Find My Item",
        @"batteryStatus": batteryStatus == nil ? @"Unknown" : [batteryStatus description],
        @"audioChannels": @[],
        @"locationEnabled": @YES,
        @"isConsideredAccessory": @YES,
        @"locationCapable": @YES,
        @"fmlyShare": @NO,
        @"thisDevice": @NO,
        @"isMac": @NO,
        @"lostModeEnabled": @NO,
        @"deviceClass": @"beacon",
        @"prsId": @"owner",
        @"findmy_beacon": @{
            @"class": [self classNameForObject:beacon],
            @"description": [beacon description] ?: [NSNull null],
            @"serialNumber": serialNumber ?: [NSNull null],
            @"productIdentifier": productIdentifier ?: [NSNull null],
            @"role": role == nil ? [NSNull null] : [role description],
        },
    }];

    if (serializedLocation != (NSDictionary *)[NSNull null]) {
        device[@"location"] = serializedLocation;
        device[@"crowdSourcedLocation"] = serializedLocation;
    }

    if (serialNumber != nil) {
        device[@"serialNumber"] = [serialNumber description];
    }
    if (productIdentifier != nil) {
        device[@"productIdentifier"] = [productIdentifier description];
    }

    return [device copy];
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

- (void)handleFindMyDevicesRefreshWithTransaction:(NSString *)transaction {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleFindMyDevicesRefreshWithTransaction:transaction];
        });
        return;
    }

    FindMyLocateSession *session = [self findMyLocateSession];
    NSMutableArray *devices = [[NSMutableArray alloc] init];
    [self installFindMySwizzles];
    BOOL didSelectDevicesSegment = [self selectFindMySegmentIndex:1];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSDictionary *diagnostics = [self runtimeDiagnosticsForClassNames:@[
            @"FMDevicesProvider",
            @"FindMy.FMDevicesProvider",
            @"_TtC6FindMy17FMDevicesProvider",
            @"FMDevicesListDataSource",
            @"FindMy.FMDevicesListDataSource",
            @"_TtC6FindMy23FMDevicesListDataSource",
            @"FMItemsListDataSource",
            @"FindMy.FMItemsListDataSource",
            @"_TtC6FindMy21FMItemsListDataSource",
            @"FMLocationProvider",
            @"FindMy.FMLocationProvider",
            @"FMDeviceDetailDataSource",
            @"FindMy.FMDeviceDetailDataSource",
            @"FMItemDetailDataSource",
            @"FindMy.FMItemDetailDataSource",
            @"FMPeopleProvider",
            @"FindMy.FMPeopleProvider",
            @"FMPeopleListDataSource",
            @"FindMy.FMPeopleListDataSource",
            @"FMSegmentedControl",
            @"FindMy.FMSegmentedControl",
            @"SPOwnerSession",
            @"SPOwner.SwiftBootstrapManager",
        ]];
        NSMutableDictionary *mutableDiagnostics = [[NSMutableDictionary alloc] initWithDictionary:diagnostics];
        mutableDiagnostics[@"selected_devices_segment"] = @(didSelectDevicesSegment);
        void *swiftProbePointer = BlueBubblesFindMySwiftProbe();
        if (swiftProbePointer != NULL) {
            NSDictionary *swiftProbe = CFBridgingRelease(swiftProbePointer);
            if ([swiftProbe isKindOfClass:[NSDictionary class]]) {
                mutableDiagnostics[@"swift_probe"] = swiftProbe;
            }
        }
        mutableDiagnostics[@"runtime_class_matches"] = [self runtimeClassNamesMatchingTerms:@[
            @"FMDevice",
            @"FMItem",
            @"FMLocationProvider",
            @"FMDevicesProvider",
            @"FMItemsList",
            @"FindMy",
            @"SPOwner",
            @"Beacon",
        ] limit:200];
        mutableDiagnostics[@"swizzle"] = [self findMySwizzleDiagnostics];
        mutableDiagnostics[@"captured_data_sources"] = [self capturedFindMyDataSourceDiagnostics];
        mutableDiagnostics[@"passive_captures"] = [self capturedFindMyPassiveDiagnostics];
        mutableDiagnostics[@"active_devices_list"] = [self activeFindMyListDiagnosticsForDataSourceTerm:@"FMDevicesListDataSource" type:@"device"];
        mutableDiagnostics[@"active_items_list"] = [self activeFindMyListDiagnosticsForDataSourceTerm:@"FMItemsListDataSource" type:@"item"];
        NSArray *uiDevices = [self findMyListRowsForDataSourceTerm:@"FMDevicesListDataSource" type:@"device"];
        mutableDiagnostics[@"ui_device_count"] = @(uiDevices.count);
        [devices addObjectsFromArray:uiDevices];

        __block BOOL didSendResponse = NO;
        void (^sendResponse)(void) = ^{
            @synchronized (devices) {
                if (didSendResponse) {
                    return;
                }
                didSendResponse = YES;
                [[NetworkController sharedInstance] sendMessage:@{
                    @"transactionId": transaction ?: [NSNull null],
                    @"devices": devices,
                    @"diagnostics": [self compactFindMyRefreshDiagnostics:mutableDiagnostics],
                }];
            }
        };

        if (devices.count > 0) {
            sendResponse();
            return;
        }

        id ownerSession = [self findMyOwnerSession];
        if (ownerSession != nil && [ownerSession respondsToSelector:@selector(allBeaconsWithCompletion:)]) {
            void (^completion)(NSArray *) = ^(NSArray *beacons) {
                NSArray *beaconList = [beacons isKindOfClass:[NSArray class]] ? beacons : @[];
                @synchronized (devices) {
                    mutableDiagnostics[@"owner_beacon_count"] = @(beaconList.count);
                    NSMutableArray *beaconClasses = [[NSMutableArray alloc] init];
                    for (id beacon in beaconList) {
                        [beaconClasses addObject:[self classNameForObject:beacon]];
                        [devices addObject:[self serializeOwnerBeacon:beacon]];
                    }
                    mutableDiagnostics[@"owner_beacon_classes"] = beaconClasses;
                }
                sendResponse();
            };
            NSMethodSignature *signature = [ownerSession methodSignatureForSelector:@selector(allBeaconsWithCompletion:)];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:ownerSession];
            [invocation setSelector:@selector(allBeaconsWithCompletion:)];
            [invocation setArgument:&completion atIndex:2];
            [invocation invoke];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                mutableDiagnostics[@"owner_beacon_timeout"] = @YES;
                sendResponse();
            });
            return;
        }

        if (session != nil && [session respondsToSelector:@selector(getActiveLocationSharingDeviceWithCompletion:)]) {
            [session getActiveLocationSharingDeviceWithCompletion:^(id device) {
                if (device != nil) {
                    [devices addObject:[self serializeFMLDevice:device]];
                }
                sendResponse();
            }];
            return;
        }

        sendResponse();
    });
}

- (void)handleFindMyItemsRefreshWithTransaction:(NSString *)transaction {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleFindMyItemsRefreshWithTransaction:transaction];
        });
        return;
    }

    NSMutableArray *items = [[NSMutableArray alloc] init];
    [self installFindMySwizzles];
    BOOL didSelectItemsSegment = [self selectFindMySegmentIndex:2];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSDictionary *diagnostics = [self runtimeDiagnosticsForClassNames:@[
            @"FMItemsListDataSource",
            @"FindMy.FMItemsListDataSource",
            @"_TtC6FindMy21FMItemsListDataSource",
            @"FMItemDetailDataSource",
            @"FindMy.FMItemDetailDataSource",
            @"SPOwnerSession",
            @"SPOwner.SwiftBootstrapManager",
        ]];
        NSMutableDictionary *mutableDiagnostics = [[NSMutableDictionary alloc] initWithDictionary:diagnostics];
        mutableDiagnostics[@"selected_items_segment"] = @(didSelectItemsSegment);
        mutableDiagnostics[@"runtime_class_matches"] = [self runtimeClassNamesMatchingTerms:@[
            @"FMItem",
            @"FMItemsList",
            @"SPOwner",
            @"Beacon",
        ] limit:200];
        mutableDiagnostics[@"swizzle"] = [self findMySwizzleDiagnostics];
        mutableDiagnostics[@"captured_data_sources"] = [self capturedFindMyDataSourceDiagnostics];
        mutableDiagnostics[@"passive_captures"] = [self capturedFindMyPassiveDiagnostics];
        mutableDiagnostics[@"active_items_list"] = [self activeFindMyListDiagnosticsForDataSourceTerm:@"FMItemsListDataSource" type:@"item"];
        NSArray *uiItems = [self findMyListRowsForDataSourceTerm:@"FMItemsListDataSource" type:@"item"];
        mutableDiagnostics[@"ui_item_count"] = @(uiItems.count);
        [items addObjectsFromArray:uiItems];

        __block BOOL didSendResponse = NO;
        void (^sendResponse)(void) = ^{
            @synchronized (items) {
                if (didSendResponse) {
                    return;
                }
                didSendResponse = YES;
                [[NetworkController sharedInstance] sendMessage:@{
                    @"transactionId": transaction ?: [NSNull null],
                    @"items": items,
                    @"diagnostics": [self compactFindMyRefreshDiagnostics:mutableDiagnostics],
                }];
            }
        };

        if (items.count > 0) {
            sendResponse();
            return;
        }

        id ownerSession = [self findMyOwnerSession];
        if (ownerSession != nil && [ownerSession respondsToSelector:@selector(allBeaconsWithCompletion:)]) {
            void (^completion)(NSArray *) = ^(NSArray *beacons) {
                NSArray *beaconList = [beacons isKindOfClass:[NSArray class]] ? beacons : @[];
                @synchronized (items) {
                    mutableDiagnostics[@"owner_beacon_count"] = @(beaconList.count);
                    NSMutableArray *beaconClasses = [[NSMutableArray alloc] init];
                    for (id beacon in beaconList) {
                        [beaconClasses addObject:[self classNameForObject:beacon]];
                        [items addObject:[self serializeOwnerBeacon:beacon]];
                    }
                    mutableDiagnostics[@"owner_beacon_classes"] = beaconClasses;
                }
                sendResponse();
            };
            NSMethodSignature *signature = [ownerSession methodSignatureForSelector:@selector(allBeaconsWithCompletion:)];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:ownerSession];
            [invocation setSelector:@selector(allBeaconsWithCompletion:)];
            [invocation setArgument:&completion atIndex:2];
            [invocation invoke];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                mutableDiagnostics[@"owner_beacon_timeout"] = @YES;
                sendResponse();
            });
            return;
        }

        mutableDiagnostics[@"owner_session_available"] = @(ownerSession != nil);
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

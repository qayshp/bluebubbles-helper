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
- (NSDictionary *)capturedFindMyDataSourceDiagnostics;
- (NSDictionary *)capturedFindMyPassiveDiagnostics;
- (NSDictionary *)compactFindMyRefreshDiagnostics:(NSDictionary *)diagnostics;
- (NSArray *)findMyListRowsForDataSourceTerm:(NSString *)dataSourceTerm type:(NSString *)type;
- (NSDictionary *)activeFindMyListDiagnosticsForDataSourceTerm:(NSString *)dataSourceTerm type:(NSString *)type;
- (BOOL)selectFindMySegmentIndex:(NSInteger)index;
- (void)installFindMySwizzles;
- (NSDictionary *)findMySwizzleDiagnostics;
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
static NSMutableDictionary<NSString *, id> *findMyCapturedObjectsByIdentifier;
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

        diagnostics[className] = @{
            @"available": @YES,
            @"class_methods": [self selectorNamesForClass:class includeClassMethods:YES],
            @"instance_methods": [self selectorNamesForClass:class includeClassMethods:NO],
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
        [self swizzleInstanceMethodForClass:ownerSessionClass
                                   selector:NSSelectorFromString(selectorName)
                                replacement:(IMP)BBFindMyInterestingObjectSetter];
    }
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

- (NSDictionary *)capturedFindMyPassiveDiagnostics {
    @synchronized ([BlueBubblesHelper class]) {
        NSArray *snapshots = [findMyCapturedObjectSnapshots copy] ?: @[];
        NSUInteger start = snapshots.count > 20 ? snapshots.count - 20 : 0;
        NSArray *recent = snapshots.count > 0 ? [snapshots subarrayWithRange:NSMakeRange(start, snapshots.count - start)] : @[];
        return @{
            @"snapshot_count": @(snapshots.count),
            @"snapshots": recent,
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

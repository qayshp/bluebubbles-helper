#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FindMyFriendPayload : NSObject

+ (nullable NSString *)identifierForHandle:(nullable id)handle;

+ (nullable NSDictionary *)locationPayloadForLocation:(nullable id)location
                                                handle:(nullable id)handle;

+ (NSDictionary *)responseForTransaction:(nullable NSString *)transaction
                        locationsByHandle:(NSDictionary<NSString *, NSDictionary *> *)locationsByHandle
                           pendingHandles:(NSSet<NSString *> *)pendingHandles
                       friendListTimedOut:(BOOL)friendListTimedOut
                           skippedFriends:(NSUInteger)skippedFriends;

@end

NS_ASSUME_NONNULL_END

#import "ServerConnection.h"

#import <os/log.h>
#import <unistd.h>

#import "FindMyFriendsHelper.h"

static const uint16_t BBPrivateApiBasePort = 45670;
static const uint16_t BBMaximumPort = UINT16_MAX;
static const uid_t BBFirstUserIdentifier = 501;
static const NSTimeInterval BBReconnectDelaySeconds = 5.0;

@interface ServerConnection ()
@property(nonatomic, strong, nullable) GCDAsyncSocket *socket;
@property(nonatomic) BOOL reconnectScheduled;
- (nullable NSDictionary *)decodeMessageData:(NSData *)messageData;
- (uint16_t)serverPort;
- (void)readNextMessage;
- (void)scheduleReconnect;
@end

@implementation ServerConnection

static os_log_t connectionLog;

+ (instancetype)sharedInstance {
    static ServerConnection *sharedConnection = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedConnection = [[self alloc] init];
        connectionLog = os_log_create("BlueBubblesFindMyHelper", "server-connection");
    });
    return sharedConnection;
}

- (uint16_t)serverPort {
    uid_t userIdentifier = getuid();
    NSUInteger userOffset = userIdentifier > BBFirstUserIdentifier ? userIdentifier - BBFirstUserIdentifier : 0;
    return (uint16_t)MIN((NSUInteger)BBPrivateApiBasePort + userOffset, (NSUInteger)BBMaximumPort);
}

- (void)connect {
    if (self.socket != nil && !self.socket.isDisconnected) {
        return;
    }

    self.reconnectScheduled = NO;
    self.socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];

    NSError *connectionError = nil;
    uint16_t port = [self serverPort];
    os_log(connectionLog, "Connecting to BlueBubbles Server on port %{public}hu", port);
    if (![self.socket connectToHost:@"localhost" onPort:port error:&connectionError]) {
        os_log_error(connectionLog, "Unable to connect to BlueBubbles Server: %{public}@", connectionError);
        self.socket = nil;
        [self scheduleReconnect];
        return;
    }

    [self readNextMessage];
}

- (void)sendMessage:(NSDictionary *)message {
    NSError *serializationError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:message options:0 error:&serializationError];
    if (jsonData == nil) {
        os_log_error(connectionLog, "Unable to serialize server message: %{public}@", serializationError);
        return;
    }

    NSMutableData *framedMessage = [jsonData mutableCopy];
    [framedMessage appendData:[GCDAsyncSocket LFData]];
    [self.socket writeData:framedMessage withTimeout:-1 tag:1];
}

- (nullable NSDictionary *)decodeMessageData:(NSData *)messageData {
    NSError *decodingError = nil;
    id decodedMessage = [NSJSONSerialization JSONObjectWithData:messageData options:0 error:&decodingError];
    if (![decodedMessage isKindOfClass:[NSDictionary class]]) {
        os_log_error(connectionLog, "Unable to decode server message: %{public}@", decodingError);
        return nil;
    }
    return decodedMessage;
}

- (void)readNextMessage {
    [self.socket readDataToData:[GCDAsyncSocket LFData] withTimeout:-1 tag:1];
}

- (void)scheduleReconnect {
    if (self.reconnectScheduled) {
        return;
    }

    self.reconnectScheduled = YES;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(BBReconnectDelaySeconds * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{
            self.reconnectScheduled = NO;
            [self connect];
        }
    );
}

- (void)socket:(GCDAsyncSocket *)socket didConnectToHost:(NSString *)host port:(uint16_t)port {
    self.reconnectScheduled = NO;
    os_log(connectionLog, "Connected to BlueBubbles Server on port %{public}hu", port);
    [self sendMessage:@{
        @"event": @"ping",
        @"message": @"Find My Friends helper connected",
        @"process": [[NSBundle mainBundle] bundleIdentifier],
    }];
}

- (void)socket:(GCDAsyncSocket *)socket didReadData:(NSData *)messageData withTag:(long)tag {
    [self readNextMessage];

    NSDictionary *serverMessage = [self decodeMessageData:messageData];
    if (serverMessage == nil) {
        return;
    }

    NSString *action = [serverMessage[@"action"] isKindOfClass:[NSString class]] ? serverMessage[@"action"] : nil;
    NSString *transactionIdentifier = [serverMessage[@"transactionId"] isKindOfClass:[NSString class]]
        ? serverMessage[@"transactionId"] : nil;

    [[FindMyFriendsHelper sharedInstance] handleServerAction:action
                                      transactionIdentifier:transactionIdentifier];
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)socket withError:(nullable NSError *)error {
    if (socket != self.socket) {
        return;
    }

    self.socket = nil;
    if (error != nil) {
        os_log_error(connectionLog, "Disconnected from BlueBubbles Server: %{public}@", error);
    } else {
        os_log(connectionLog, "Disconnected from BlueBubbles Server");
    }
    [self scheduleReconnect];
}

@end

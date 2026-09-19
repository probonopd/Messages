/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MSGWebSocketState) {
	MSGWebSocketStateDisconnected = 0,
	MSGWebSocketStateConnecting = 1,
	MSGWebSocketStateOpen = 2,
	MSGWebSocketStateClosing = 3,
};

@class MSGWebSocketTransport;

@protocol MSGWebSocketTransportDelegate <NSObject>

@optional
- (void)webSocketDidOpen:(MSGWebSocketTransport *)transport;
- (void)webSocket:(MSGWebSocketTransport *)transport didReceiveData:(NSData *)data isText:(BOOL)isText;
- (void)webSocket:(MSGWebSocketTransport *)transport didFailWithError:(NSError *)error;
- (void)webSocketDidClose:(MSGWebSocketTransport *)transport;

@end

@interface MSGWebSocketTransport : NSObject

@property (nonatomic, assign) id<MSGWebSocketTransportDelegate> delegate;
@property (nonatomic, readonly) MSGWebSocketState state;

- (void)connectToURL:(NSURL *)url;
- (void)sendData:(NSData *)data isText:(BOOL)isText;
- (void)close;

@end
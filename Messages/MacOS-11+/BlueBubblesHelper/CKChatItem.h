//
//  CKChatItem.h
//  BlueBubblesHelper DyLib
//
//  Created by Tanay Neotia on 5/20/26.
//  Copyright © 2026 BlueBubbleMessaging. All rights reserved.
//


// Headers generated with ktool v2.0.0
// https://github.com/cxnder/ktool | pip3 install k2l
// Platform: IOS | Minimum OS: 16.5.0 | SDK: 16.5.0


#ifndef CKCHATITEM_H
#define CKCHATITEM_H


@interface CKChatItem : NSObject 

+(id)chatItemWithIMChatItem:(id)arg0 balloonMaxWidth:(CGFloat)arg1;
+(id)chatItemWithIMChatItem:(id)arg0 balloonMaxWidth:(CGFloat)arg1 fullMaxWidth:(CGFloat)arg2 transcriptTraitCollection:(id)arg3 overlayLayout:(BOOL)arg4 ;

@end


#endif

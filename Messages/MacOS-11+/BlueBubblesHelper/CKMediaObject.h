//
//  CKMediaObject.h
//  BlueBubblesHelper DyLib
//
//  Created by Tanay Neotia on 5/2/26.
//  Copyright © 2026 BlueBubbleMessaging. All rights reserved.
//


// Headers generated with ktool v2.0.0
// https://github.com/cxnder/ktool | pip3 install k2l
// Platform: IOS | Minimum OS: 16.5.0 | SDK: 16.5.0


#ifndef CKMEDIAOBJECT_H
#define CKMEDIAOBJECT_H

@class NSString, NSURL, NSData, NSDate, NSDictionary, UITraitCollection;
@protocol QLPreviewItem, OS_dispatch_group, CKFileTransfer;


@interface CKMediaObject : NSObject

@property (readonly, copy, nonatomic) NSString *transferGUID;

@end


#endif

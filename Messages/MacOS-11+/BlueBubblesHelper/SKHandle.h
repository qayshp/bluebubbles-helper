//
//  SKHandle.h
//  BlueBubblesHelper DyLib
//
//  Created by Tanay Neotia on 5/15/26.
//  Copyright © 2026 BlueBubbleMessaging. All rights reserved.
//


// Headers generated with ktool v2.0.0
// https://github.com/cxnder/ktool | pip3 install k2l
// Platform: IOS | Minimum OS: 16.5.0 | SDK: 16.5.0


#ifndef SKHANDLE_H
#define SKHANDLE_H

@class NSString;
@protocol NSSecureCoding, NSCopying;


@interface SKHandle : NSObject 



@property (readonly, nonatomic) NSString *handleString; // ivar: _handleString


+(BOOL)supportsSecureCoding;
-(BOOL)isEqual:(id)arg0 ;
-(BOOL)isExactlyEqualToHandle:(id)arg0 ;
-(NSUInteger)hash;
-(id)copyWithZone:(struct _NSZone *)arg0 ;
-(id)description;
-(id)initWithCoder:(id)arg0 ;
-(id)initWithString:(id)arg0 ;
-(id)initWithString:(id)arg0 mergeID:(id)arg1 ;
-(void)encodeWithCoder:(id)arg0 ;


@end


#endif

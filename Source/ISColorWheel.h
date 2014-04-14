/*
 By: Justin Meiners
 
 Copyright (c) 2013 Inline Studios
 Licensed under the MIT license: http://www.opensource.org/licenses/mit-license.php
*/

#import <UIKit/UIKit.h>

@class ISColorWheel;

@protocol ISColorWheelDelegate <NSObject>

@required
- (void)colorWheelDidChangeColor:(ISColorWheel*)colorWheel;

@end


@interface ISColorWheel : UIView

@property (nonatomic, weak) IBOutlet id <ISColorWheelDelegate> delegate;

@property (nonatomic, assign) int clampRGBAmount;
@property (nonatomic, assign) int clampRGBMargin;

@property (nonatomic, assign) CGFloat hueCount;
@property (nonatomic, assign) CGFloat hueOffset;

@property (nonatomic, assign) CGFloat saturationCount;
@property (nonatomic, assign) CGFloat saturationMinimum;
@property (nonatomic, assign) CGFloat saturationMaximum;

@property (nonatomic, assign) CGFloat brightness;
@property (nonatomic, assign) BOOL lockBrightness;

@property (nonatomic, assign) BOOL swapSaturationAndBrightness;

@property (nonatomic, strong) UIView* knobView;
@property (nonatomic, assign) CGSize knobSize;
@property (nonatomic, assign) CGFloat knobBorderWidth;
@property (nonatomic, strong) UIColor* knobBorderColor;
@property (nonatomic, assign) BOOL knobShowsCurrentColor;

@property (nonatomic, assign) CGFloat borderWidth;
@property (nonatomic, strong) UIColor* borderColor;

@property (nonatomic, assign) BOOL continuous;

@property (nonatomic, strong) UIColor* currentColor;

- (void)updateImage;
- (void)setTouchPoint:(CGPoint)point;

@end

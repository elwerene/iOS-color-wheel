/*
 By: Justin Meiners
 
 Copyright (c) 2013 Inline Studios
 Licensed under the MIT license: http://www.opensource.org/licenses/mit-license.php
 */

#import "ISColorWheel.h"

#define M_DOUBLE_PI         6.28318530717959

typedef struct
{
    unsigned char r;
    unsigned char g;
    unsigned char b;
    
} ISColorWheelPixelRGB;

static CGFloat ISColorWheel_PointDistance (CGPoint p1, CGPoint p2)
{
    return sqrtf((p1.x - p2.x) * (p1.x - p2.x) + (p1.y - p2.y) * (p1.y - p2.y));
}


static ISColorWheelPixelRGB ISColorWheel_HSBToRGB (CGFloat h, CGFloat s, CGFloat v)
{
    h *= 6.0f;
    int i = floorf(h);
    CGFloat f = h - (CGFloat)i;
    CGFloat p = v *  (1.0f - s);
    CGFloat q = v * (1.0f - s * f);
    CGFloat t = v * (1.0f - s * (1.0f - f));
    
    CGFloat r;
    CGFloat g;
    CGFloat b;
    
    switch (i)
    {
        case 0:
            r = v;
            g = t;
            b = p;
            break;
        case 1:
            r = q;
            g = v;
            b = p;
            break;
        case 2:
            r = p;
            g = v;
            b = t;
            break;
        case 3:
            r = p;
            g = q;
            b = v;
            break;
        case 4:
            r = t;
            g = p;
            b = v;
            break;
        default:        // case 5:
            r = v;
            g = p;
            b = q;
            break;
    }
    
    ISColorWheelPixelRGB pixel;
    pixel.r = r * 255.0f;
    pixel.g = g * 255.0f;
    pixel.b = b * 255.0f;
    
    return pixel;
}

@interface ISColorKnobView : UIView

@property (nonatomic, assign) CGFloat borderWidth;
@property (nonatomic, strong) UIColor* borderColor;
@property (nonatomic, strong) UIColor* fillColor;

@end

@implementation ISColorKnobView

- (id)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame]))
    {
        self.backgroundColor = [UIColor clearColor];
        self.borderColor = [UIColor blackColor];
        self.fillColor = [UIColor clearColor];
        self.borderWidth = 2.0;
    }
    return self;
}

- (void)drawRect:(CGRect)rect
{
    CGRect ellipseRect = CGRectInset(self.bounds, _borderWidth, _borderWidth);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, _fillColor.CGColor);
    CGContextAddEllipseInRect(ctx, ellipseRect);
    CGContextFillPath(ctx);
    CGContextSetLineWidth(ctx, _borderWidth);
    CGContextSetStrokeColorWithColor(ctx, _borderColor.CGColor);
    CGContextAddEllipseInRect(ctx, ellipseRect);
    CGContextStrokePath(ctx);
}

-(void)setBorderColor:(UIColor *)borderColor
{
    if (![_borderColor isEqual:borderColor]) {
        _borderColor = borderColor;
        [self setNeedsDisplay];
    }
}

-(void)setBorderWidth:(CGFloat)borderWidth
{
    if (_borderWidth != borderWidth) {
        _borderWidth = borderWidth;
        [self setNeedsDisplay];
    }
}

-(void)setFillColor:(UIColor *)fillColor
{
    if (![_fillColor isEqual:fillColor]) {
        _fillColor = fillColor;
        [self setNeedsDisplay];
    }
}


@end


@interface ISColorWheel ()
{
    ISColorWheelPixelRGB* _imageData;
}

@property (nonatomic, assign) NSInteger imageDataLength;
@property (nonatomic, assign) CGImageRef radialImage;
@property (nonatomic, assign) CGFloat radius;
@property (nonatomic, assign) CGFloat diameter;
@property (nonatomic, assign) CGPoint touchPoint;
@property (nonatomic, assign) CGPoint wheelCenter;
@property (nonatomic, assign) CGPoint imageCenter;

- (ISColorWheelPixelRGB)colorAtPoint:(CGPoint)point forDisplay:(BOOL)forDisplay;
- (CGPoint)viewToImageSpace:(CGPoint)point;
- (void)updateKnob;

- (void)initialize;

- (ISColorKnobView *)colorKnobView;

@end

@implementation ISColorWheel
@synthesize currentColor=_currentColor;

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self initialize];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self initialize];
    }
    return self;
}

- (void)initialize
{
    _radialImage = NULL;
    _imageData = NULL;
    
    _borderColor = [UIColor blackColor];
    _borderWidth = 2.0f;
    
    _imageDataLength = 0;
    
    _hueCount = 0.0;
    _hueOffset = 0.0;
    _saturationCount = 0.0;
    _saturationMinimum = 0.0;
    _saturationMaximum = 1.0;
    
    _clampRGBAmount = 0;
    _clampRGBMargin = 0;
    
    _brightness = 1.0;
    
    _swapSaturationAndBrightness = NO;
    
    _knobSize = CGSizeMake(32.0f, 32.0f);
    
    [self updateWheelCenter];
    _touchPoint = _wheelCenter;
    
    ISColorKnobView* knob = [[ISColorKnobView alloc] init];
    self.knobView = knob;
    self.backgroundColor = [UIColor clearColor];
    
    _continuous = false;
}

- (void)dealloc
{
    if (_radialImage)
    {
        CGImageRelease(_radialImage);
    }
    
    if (_imageData)
    {
        free(_imageData);
    }
}

NS_INLINE unsigned char RoundClamp(unsigned char value, int rounding, int margin)
{
    int offset = value % rounding;
    int base = value - offset;
    int result;
    int halfRounding = rounding/2;
    if (offset < margin) {
        result = base + round(((CGFloat)offset/(CGFloat)margin) * halfRounding);
    } else if ((rounding - offset) < margin) {
        result = base + rounding - round(((CGFloat)(rounding - offset)/(CGFloat)margin) * halfRounding);
    } else {
        result = base + halfRounding;
    }
    if (result < 0) {
        result = 0;
    } else if (result > 255) {
        result = 255;
    }
    return result;
}

- (ISColorWheelPixelRGB)colorAtPoint:(CGPoint)point forDisplay:(BOOL)forDisplay
{
    CGFloat angle = atan2(point.x - _imageCenter.x, point.y - _imageCenter.y) + M_PI;
    CGFloat dist = ISColorWheel_PointDistance(point, _imageCenter);
    
    CGFloat hue = angle / M_DOUBLE_PI;
    
    if (_hueCount > 0.0) {
        hue = round(hue * _hueCount) / _hueCount;
    }
    
    if (_hueOffset != 0.0) {
        hue += _hueOffset;
        if (hue > 1.0) {
            double intPart;
            hue = modf(hue, &intPart);
        }
    }
    
    hue = MIN(hue, 1.0f - .0000001f);
    hue = MAX(hue, 0.0f);
    
    CGFloat sat = dist / (_radius);
    
    sat = MIN(sat, 1.0);
    sat = MAX(sat, 0.0);
    
    CGFloat brightness;
    if (_swapSaturationAndBrightness) {
        brightness = sat;
        sat = _brightness;
    } else {
        brightness = _brightness;
    }
    
    if (_saturationCount > 0.0) {
        if (_saturationCount <= 1.0) {
            sat = 1.0f;
        } else {
            sat = round(sat * _saturationCount - 0.5) / (_saturationCount - 1.0);
        }
    }
    
    sat = MIN(sat, 1.0);
    sat = MAX(sat, 0.0);
    
    if (_saturationMinimum > 0.0 || _saturationMaximum < 1.0) {
        CGFloat satMin = MAX(0.0, _saturationMinimum);
        sat = sat * (MIN(1.0f, _saturationMaximum) - satMin) + satMin;
    }
    
    ISColorWheelPixelRGB rgb = ISColorWheel_HSBToRGB(hue, sat, brightness);
    
    if (_clampRGBAmount > 1) {
        int margin = 0;
        if (forDisplay) margin = _clampRGBMargin;
        rgb.r = RoundClamp(rgb.r, _clampRGBAmount, margin);
        rgb.g = RoundClamp(rgb.g, _clampRGBAmount, margin);
        rgb.b = RoundClamp(rgb.b, _clampRGBAmount, margin);
    }
    
    return rgb;
}

- (CGPoint)viewToImageSpace:(CGPoint)point
{
    CGFloat height = CGRectGetHeight(self.bounds);
    
    point.y = height - point.y;
        
    CGPoint min = CGPointMake(_wheelCenter.x - _radius, _wheelCenter.y - _radius);
    
    point.x = point.x - min.x;
    point.y = point.y - min.y;
    
    return point;
}

- (void)updateKnob
{
    if (!self.knobView)
    {
        return;
    }
    
    if (isnan(_touchPoint.x) || isnan(_touchPoint.y)) return;
    
    self.knobView.bounds = CGRectMake(0, 0, self.knobSize.width, self.knobSize.height);
    self.knobView.center = _touchPoint;
    ISColorKnobView *colorKnobView = self.colorKnobView;
    if (colorKnobView != nil) {
        if (_knobShowsCurrentColor) {
            colorKnobView.fillColor = self.currentColor;
        } else {
            colorKnobView.fillColor = [UIColor clearColor];
        }
    }
}

- (void)willMoveToSuperview:(UIView *)newSuperview
{
    if (newSuperview != nil) {
        self.currentColor = _currentColor;
    }
}

- (void)updateImage
{
    if (CGRectGetWidth(self.bounds) == 0 || CGRectGetHeight(self.bounds) == 0)
    {
        return;
    }
    
    if (_radialImage)
    {
        CGImageRelease(_radialImage);
        _radialImage = nil;
    }
    
    int width = _diameter;
    int height = _diameter;
    
    int dataLength = sizeof(ISColorWheelPixelRGB) * width * height;
    
    if (dataLength != _imageDataLength)
    {
        if (_imageData)
        {
            free(_imageData);
        }
        _imageData = malloc(dataLength);
        
        _imageDataLength = dataLength;
    }
    
    for (int y = 0; y < height; y++)
    {
        for (int x = 0; x < width; x++)
        {
            _imageData[x + y * width] = [self colorAtPoint:CGPointMake(x, y) forDisplay:YES];
        }
    }
    
    CGBitmapInfo bitInfo = kCGBitmapByteOrderDefault;
    
	CGDataProviderRef ref = CGDataProviderCreateWithData(NULL, _imageData, dataLength, NULL);
	CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
    
	_radialImage = CGImageCreate(width,
                                 height,
                                 8,
                                 24,
                                 width * 3,
                                 colorspace,
                                 bitInfo,
                                 ref,
                                 NULL,
                                 true,
                                 kCGRenderingIntentDefault);
    
    CGColorSpaceRelease(colorspace);
    CGDataProviderRelease(ref);
    
    [self setNeedsDisplay];
}

- (UIColor*)currentColor
{
    if (self.superview != nil && _radius > 0.0f) {
        ISColorWheelPixelRGB pixel = [self colorAtPoint:[self viewToImageSpace:_touchPoint] forDisplay:NO];
        _currentColor = [UIColor colorWithRed:pixel.r / 255.0f green:pixel.g / 255.0f blue:pixel.b / 255.0f alpha:1.0];
    }
    return _currentColor;
}

- (void)setCurrentColor:(UIColor*)color
{
    _currentColor = color;
    
    if (color == nil || self.superview == nil || _radius <= 0.0f) return;
    
    CGFloat hue = 0.0;
    CGFloat saturation = 0.0;
    CGFloat brightness = 1.0;
    CGFloat alpha = 1.0;
    
    CGColorSpaceModel colorSpaceModel = CGColorSpaceGetModel(CGColorGetColorSpace(color.CGColor));
    
    if (colorSpaceModel == kCGColorSpaceModelRGB) {
        [color getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];
    } else if (colorSpaceModel == kCGColorSpaceModelMonochrome) {
        const CGFloat *c = CGColorGetComponents(color.CGColor);
        saturation = 0.0;
        brightness = c[0];
        alpha = c[1];
    }
    
    /*/
    NSLog(@"hue = %f",hue);
    NSLog(@"saturation = %f",saturation);
    NSLog(@"brightness = %f",brightness);
    //*/
    
    if (_swapSaturationAndBrightness) {
        CGFloat swap = saturation;
        saturation = brightness;
        brightness = swap;
    }
    
    if (!_lockBrightness) {
        _brightness = brightness;
    }
    
    if (_hueOffset != 0.0) {
        
        hue = hue - _hueOffset + 1.0;
        if (hue > 1.0) {
            double intPart;
            hue = modf(hue, &intPart);
        }
    }
    
    CGFloat angle = (hue * M_DOUBLE_PI) + M_PI_2;
    CGFloat dist = saturation * _radius;
        
    CGPoint point;
    point.x = _wheelCenter.x + (cosf(angle) * dist);
    point.y = _wheelCenter.y + (sinf(angle) * dist);
    
    [self setTouchPoint: point];
    [self updateImage];
    [self updateKnob];
}

- (void)setKnobView:(UIView *)knobView
{
    if (_knobView != knobView) {
        if (_knobView) {
            [_knobView removeFromSuperview];
        }
        
        _knobView = knobView;
        
        if (_knobView) {
            [self addSubview:_knobView];
        }
    }
    [self updateKnob];
}

- (ISColorKnobView *)colorKnobView
{
    if ([_knobView isKindOfClass:[ISColorKnobView class]]) {
        return (ISColorKnobView *)_knobView;
    } else {
        return nil;
    }
}

-(void)setKnobBorderColor:(UIColor *)knobBorderColor
{
    _knobBorderColor = knobBorderColor;
    if ([_knobView isKindOfClass:[ISColorKnobView class]]) {
        [(ISColorKnobView *)_knobView setBorderColor:knobBorderColor];
    }
}

-(void)setKnobBorderWidth:(CGFloat)knobBorderWidth
{
    _knobBorderWidth = knobBorderWidth;
    if ([_knobView isKindOfClass:[ISColorKnobView class]]) {
        [(ISColorKnobView *)_knobView setBorderWidth:knobBorderWidth];
    }
}

-(void)setBorderColor:(UIColor *)borderColor
{
    if (_borderColor != borderColor && ![borderColor isEqual:_borderColor]) {
        _borderColor = borderColor;
        [self setNeedsLayout];
    }
}

-(void)setBorderWidth:(CGFloat)borderWidth
{
    if (_borderWidth != borderWidth) {
        _borderWidth = borderWidth;
        [self setNeedsLayout];
    }
}

-(void)setHueOffset:(CGFloat)hueOffset
{
    hueOffset = MIN(1.0f, MAX(0.0f, hueOffset));
    if (_hueOffset != hueOffset) {
        _hueOffset = hueOffset;
        [self setNeedsLayout];
    }
}

- (void)drawRect:(CGRect)rect
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    CGContextSaveGState (ctx);
    
    CGFloat borderWidth = MAX(0.0f, self.borderWidth);
    CGFloat halfBorderWidth = borderWidth/2.0f;
    
    CGRect wheelRect = CGRectMake(_wheelCenter.x - _radius, _wheelCenter.y - _radius, _diameter, _diameter);
    CGRect borderRect = CGRectInset(wheelRect, -halfBorderWidth, -halfBorderWidth);
    
    if (borderWidth > 0.0f && self.borderColor != nil) {
        CGContextSetLineWidth(ctx, borderWidth);
        CGContextSetStrokeColorWithColor(ctx, [self.borderColor CGColor]);
        CGContextAddEllipseInRect(ctx, borderRect);
        CGContextStrokePath(ctx);
    }
    
    CGContextAddEllipseInRect(ctx, wheelRect);
    CGContextClip(ctx);
    
    if (_radialImage)
    {
        CGContextDrawImage(ctx, wheelRect, _radialImage);
    }

    CGContextRestoreGState (ctx);
}

-(void)updateWheelCenter
{
    CGSize boundsSize = self.bounds.size;
    _wheelCenter = CGPointMake(round(boundsSize.width/2.0f), round(boundsSize.height/2.0f));
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    _radius = floor(MIN(CGRectGetWidth(bounds), CGRectGetHeight(bounds)) / 2.0);
    _radius -= MAX(0.0f, self.borderWidth);
    _diameter = _radius * 2.0f;
    _imageCenter = CGPointMake(_radius, _radius);
    [self updateWheelCenter];
    [self updateImage];
    self.currentColor = _currentColor;
    [self updateKnob];
}

-(void)notifyDelegateOfColorChange
{
    if ([self.delegate respondsToSelector:@selector(colorWheelDidChangeColor:)]) {
        [self.delegate colorWheelDidChangeColor:self];
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self setTouchPoint:[[touches anyObject] locationInView:self]];
    
    [self notifyDelegateOfColorChange];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self setTouchPoint:[[touches anyObject] locationInView:self]];
    
    if (self.continuous)
    {
        [self notifyDelegateOfColorChange];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self notifyDelegateOfColorChange];
}

- (void)setTouchPoint:(CGPoint)point
{
    // Check if the touch is outside the wheel
    if (ISColorWheel_PointDistance(_wheelCenter, point) < _radius) {
        _touchPoint = point;
        
    } else {
        // If so we need to create a drection vector and calculate the constrained point
        CGPoint vec = CGPointMake(point.x - _wheelCenter.x, point.y - _wheelCenter.y);
        
        CGFloat extents = sqrtf((vec.x * vec.x) + (vec.y * vec.y));
        
        vec.x /= extents;
        vec.y /= extents;
        
        _touchPoint = CGPointMake(_wheelCenter.x + vec.x * _radius, _wheelCenter.y + vec.y * _radius);
    }
    
    [self updateKnob];
}

@end

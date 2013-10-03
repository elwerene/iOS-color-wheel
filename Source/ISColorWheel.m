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

static float ISColorWheel_PointDistance (CGPoint p1, CGPoint p2)
{
    return sqrtf((p1.x - p2.x) * (p1.x - p2.x) + (p1.y - p2.y) * (p1.y - p2.y));
}


static ISColorWheelPixelRGB ISColorWheel_HSBToRGB (float h, float s, float v)
{
    h *= 6.0f;
    int i = floorf(h);
    float f = h - (float)i;
    float p = v *  (1.0f - s);
    float q = v * (1.0f - s * f);
    float t = v * (1.0f - s * (1.0f - f));
    
    float r;
    float g;
    float b;
    
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

@end

@implementation ISColorKnobView

- (id)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame]))
    {
        self.backgroundColor = [UIColor clearColor];
        self.borderColor = [UIColor blackColor];
        self.borderWidth = 2.0;
    }
    return self;
}

- (void)drawRect:(CGRect)rect
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(ctx, _borderWidth);
    CGContextSetStrokeColorWithColor(ctx, _borderColor.CGColor);
    CGContextAddEllipseInRect(ctx, CGRectInset(self.bounds, _borderWidth, _borderWidth));
    CGContextStrokePath(ctx);
}

-(void)setBorderColor:(UIColor *)borderColor
{
    _borderColor = borderColor;
    [self setNeedsDisplay];
}

-(void)setBorderWidth:(CGFloat)borderWidth
{
    _borderWidth = borderWidth;
    [self setNeedsDisplay];
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

- (ISColorWheelPixelRGB)colorAtPoint:(CGPoint)point;
- (CGPoint)viewToImageSpace:(CGPoint)point;
- (void)updateKnob;

@end

@implementation ISColorWheel

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
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
        
        _knobSize = CGSizeMake(20, 20);
        
        [self updateWheelCenter];
        _touchPoint = _wheelCenter;
                
        ISColorKnobView* knob = [[ISColorKnobView alloc] init];
        self.knobView = knob;
        self.backgroundColor = [UIColor clearColor];
        
        _continuous = false;
    }
    return self;
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
        result = base + round(((float)offset/(float)margin) * halfRounding);
    } else if ((rounding - offset) < margin) {
        result = base + rounding - round(((float)(rounding - offset)/(float)margin) * halfRounding);
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

- (ISColorWheelPixelRGB)colorAtPoint:(CGPoint)point
{
    CGPoint center = _wheelCenter;
    
    float angle = atan2(point.x - center.x, point.y - center.y) + M_PI;
    float dist = ISColorWheel_PointDistance(point, center);
    
    float hue = angle / M_DOUBLE_PI;
    
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
    
    float sat = dist / (_radius);
    
    sat = MIN(sat, 1.0);
    sat = MAX(sat, 0.0);
    
    float brightness;
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
        float satMin = MAX(0.0, _saturationMinimum);
        sat = sat * (MIN(1.0f, _saturationMaximum) - satMin) + satMin;
    }
    
    ISColorWheelPixelRGB rgb = ISColorWheel_HSBToRGB(hue, sat, brightness);
    
    if (_clampRGBAmount > 1) {
        rgb.r = RoundClamp(rgb.r, _clampRGBAmount, _clampRGBMargin);
        rgb.g = RoundClamp(rgb.g, _clampRGBAmount, _clampRGBMargin);
        rgb.b = RoundClamp(rgb.b, _clampRGBAmount, _clampRGBMargin);
    }
    
    return rgb;
}

- (CGPoint)viewToImageSpace:(CGPoint)point
{
    float height = CGRectGetHeight(self.bounds);
    
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
    
    self.knobView.bounds = CGRectMake(0, 0, self.knobSize.width, self.knobSize.height);
    self.knobView.center = _touchPoint;
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
            _imageData[x + y * width] = [self colorAtPoint:CGPointMake(x, y)];
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
    ISColorWheelPixelRGB pixel = [self colorAtPoint:[self viewToImageSpace:_touchPoint]];
    return [UIColor colorWithRed:pixel.r / 255.0f green:pixel.g / 255.0f blue:pixel.b / 255.0f alpha:1.0];
}

- (void)setCurrentColor:(UIColor*)color
{
    if (color == nil) return;
    
    float hue = 0.0;
    float saturation = 0.0;
    float brightness = 1.0;
    float alpha = 1.0;
    
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
    
    self.brightness = brightness;
    
    CGPoint center = _wheelCenter;
    
    if (_hueOffset != 0.0) {
        
        hue = hue - _hueOffset + 1.0;
        if (hue > 1.0) {
            double intPart;
            hue = modf(hue, &intPart);
        }
    }
    
    float angle = (hue * M_DOUBLE_PI) + M_PI_2;
    float dist = saturation * _radius;
        
    CGPoint point;
    point.x = center.x + (cosf(angle) * dist);
    point.y = center.y + (sinf(angle) * dist);
    
    [self setTouchPoint: point];
    [self updateImage];
}

- (void)setKnobView:(UIView *)knobView
{
    if (_knobView)
    {
        [_knobView removeFromSuperview];
    }
    
    _knobView = knobView;
    
    if (_knobView)
    {
        [self addSubview:_knobView];
    }
    
    [self updateKnob];
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

-(void)setHueOffset:(float)hueOffset
{
    hueOffset = MIN(1.0f, MAX(0.0f, hueOffset));
    if (_hueOffset != hueOffset) {
        _hueOffset = hueOffset;
        [self setNeedsLayout];
    }
}

- (void)drawRect:(CGRect)rect
{
    CGPoint center = _wheelCenter;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    CGContextSaveGState (ctx);
    
    CGFloat borderWidth = MAX(0.0f, self.borderWidth);
    CGFloat halfBorderWidth = borderWidth/2.0f;
    
    CGRect wheelRect = CGRectMake(center.x - _radius, center.y - _radius, _diameter, _diameter);
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
    [self updateWheelCenter];
    [self updateImage];
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
    CGPoint center = _wheelCenter;
    
    // Check if the touch is outside the wheel
    if (ISColorWheel_PointDistance(center, point) < _radius) {
        _touchPoint = point;
        
    } else {
        // If so we need to create a drection vector and calculate the constrained point
        CGPoint vec = CGPointMake(point.x - center.x, point.y - center.y);
        
        float extents = sqrtf((vec.x * vec.x) + (vec.y * vec.y));
        
        vec.x /= extents;
        vec.y /= extents;
        
        _touchPoint = CGPointMake(center.x + vec.x * _radius, center.y + vec.y * _radius);
    }
    
    [self updateKnob];
}

@end

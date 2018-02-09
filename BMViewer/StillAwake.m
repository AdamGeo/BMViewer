//
//  StillAwake.m
//  BMViewer
//
//  Created by Adam Geoghegan on 4/2/18.
//

#import "StillAwake.h"

@implementation StillAwake

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.layer = [[CALayer alloc] init];
        self.wantsLayer = YES;
    }
    return self;
}

- (void)drawRect:(NSRect)rect {
    [[NSColor clearColor] set];
    NSRectFill(rect);
//    [super drawRect:dirtyRect];
}

- (BOOL)wantsUpdateLayer
{
    return YES;
}

- (void)updateLayer
{
    self.layer.backgroundColor = self.backgroundColor.CGColor;
}

- (void)setBackgroundColor:(NSColor *)backgroundColor
{
    _backgroundColor = backgroundColor;
    [self setNeedsDisplay:YES];
}
@end

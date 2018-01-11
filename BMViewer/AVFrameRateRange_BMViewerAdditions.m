#import "AVFrameRateRange_BMViewerAdditions.h"

@implementation AVFrameRateRange (BMViewerAdditions)

- (NSString *)localizedName
{
	if ([self minFrameRate] != [self maxFrameRate]) {
		NSString *formatString = NSLocalizedString(@"FPS: %0.2f-%0.2f", @"FPS when minFrameRate != maxFrameRate");
		return [NSString stringWithFormat:formatString, [self minFrameRate], [self maxFrameRate]];
	}
	NSString *formatString = NSLocalizedString(@"FPS: %0.2f", @"FPS when minFrameRate == maxFrameRate");
	return [NSString stringWithFormat:formatString, [self minFrameRate]];
}

@end

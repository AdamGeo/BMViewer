//
//  tipImage.m
//  BMViewer
//
//  Created by Adam Geoghegan on 19/1/18.
//

#import "tipImage.h"

@implementation tipImage {
    NSString *info;
    NSString *infoDescription;
}

- (void)mouseDown:(NSEvent *)theEvent
{
    NSInteger clickCount = [theEvent clickCount];
    if (clickCount == 1) {
        NSHelpManager *helpManager = [NSHelpManager sharedHelpManager];
        infoDescription = [infoDescription stringByReplacingOccurrencesOfString:@"\\n" withString:@"\n"];
        [helpManager setContextHelp:[[NSAttributedString alloc] initWithString:infoDescription] forObject:self];
        [helpManager showContextHelpForObject:self locationHint:[NSEvent mouseLocation]];
        [helpManager removeContextHelpForObject:self];
    }
}

@end

//
//  PDFGenerator.m
//
//  Created by Joel Arnott.
//

#import "PDFGenerator.h"

/***************************************************************************************************
 * UIPdfPrintPageRenderer
 */

@interface UIPdfPrintPageRenderer : UIPrintPageRenderer
@end

@implementation UIPdfPrintPageRenderer

/***************************************************************************************************
 * UIPrintPageRenderer
 */

- (id)init
{
    if ((self = [super init])) {
        self.footerHeight = 30;
    }
    return self;
}

- (CGRect)paperRect
{
    return UIGraphicsGetPDFContextBounds();
}

- (CGRect)printableRect
{
    return CGRectInset([self paperRect], 20, 20);
}

- (void)drawFooterForPageAtIndex:(NSInteger)pageIndex inRect:(CGRect)footerRect
{
    // Get our footer font
    UIFont *font = [UIFont systemFontOfSize:6];
    
    // Get page number string
    NSString *num = [NSString stringWithFormat:@"Page %d of %d", (int)pageIndex+1, (int)self.numberOfPages];
    
    // Draw it
    CGFloat numX = footerRect.origin.x + footerRect.size.width/2 - [num sizeWithFont:font].width/2;
    CGFloat numY = footerRect.origin.y;
    [num drawAtPoint:CGPointMake(numX, numY) withFont:font];
    
    // Get produced by string
    NSString *madeBy = @"Report produced by Unit Planner";

    // Draw it
    [madeBy drawAtPoint:CGPointMake(footerRect.origin.x + 20, footerRect.origin.y) withFont:font];
    
    // Get date
    NSDateFormatter *fmtr = [[NSDateFormatter alloc] init];
    fmtr.dateStyle = NSDateFormatterLongStyle;
    fmtr.timeStyle = NSDateFormatterShortStyle;
    NSString *dateString = [fmtr stringFromDate:[NSDate date]];
    
    // Draw it
    CGFloat dX = footerRect.origin.x + footerRect.size.width - 20 - [dateString sizeWithFont:font].width;
    CGFloat dY = footerRect.origin.y;
    [dateString drawAtPoint:CGPointMake(dX, dY) withFont:font];
}

@end

/***************************************************************************************************
 * PDFGenerator
 */

@implementation PDFGenerator

+ (NSData *)pdfDataForHtml:(NSString *)html
{
    NSMutableData *pdfData = [NSMutableData data];
    
    // Build renderer
    UIPrintPageRenderer *renderer = [[UIPdfPrintPageRenderer alloc] init];
    
    // Filter HTML to hide all sections
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(div\\.Section([0-9]+) \\{)"
                                                                           options:0
                                                                             error:nil];
    NSUInteger numSections = [regex numberOfMatchesInString:html options:0 range:NSMakeRange(0, [html length])];
    NSString *newHtml = [regex stringByReplacingMatchesInString:html
                                                        options:0
                                                          range:NSMakeRange(0, [html length])
                                                   withTemplate:@"$1 display: none;"];
    
    // Start building the PDF
    UIGraphicsBeginPDFContextToData(pdfData, CGRectMake(0.0, 0.0,  11.69f * 72, 8.27f * 72), nil);

    // Add HTML formatters to renderer for each section
    for (int i = 1; i <= numSections; i++) {
        // Filter HTML to show only this section
        NSString *secHtml = [newHtml stringByReplacingOccurrencesOfString:[NSString stringWithFormat:
                                                                           @"div.Section%d { display: none;", i]
                                                               withString:[NSString stringWithFormat:
                                                                           @"div.Section%d {", i]];
        // Add HTML formatter to renderer
        UIMarkupTextPrintFormatter *fmtr = [[UIMarkupTextPrintFormatter alloc] initWithMarkupText:secHtml];
        fmtr.contentInsets = UIEdgeInsetsZero;
        [renderer addPrintFormatter:fmtr startingAtPageAtIndex:[renderer numberOfPages]];
    }
    
    // Render!
    for (int i = 0; i < [renderer numberOfPages]; i++) {
        UIGraphicsBeginPDFPage();
        [renderer drawPageAtIndex:i inRect:UIGraphicsGetPDFContextBounds()];
    }
    
    // Finished
    UIGraphicsEndPDFContext();

    return pdfData;
}

@end

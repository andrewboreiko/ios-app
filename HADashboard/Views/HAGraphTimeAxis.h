#import <Foundation/Foundation.h>

@interface HAGraphTimeAxis : NSObject
+ (NSArray<NSNumber *> *)hourlyTicksFrom:(NSTimeInterval)start
                                    to:(NSTimeInterval)end
                                 width:(double)width
                            labelWidth:(double)labelWidth
                              timeZone:(NSTimeZone *)timeZone;
+ (NSArray<NSDictionary *> *)bucketTicksForSeries:(NSArray<NSDictionary *> *)series
                                            from:(NSTimeInterval)start
                                              to:(NSTimeInterval)end
                                           width:(double)width
                                      labelWidth:(double)labelWidth;
@end

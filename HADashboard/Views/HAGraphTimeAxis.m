#import "HAGraphTimeAxis.h"
#import <math.h>

@implementation HAGraphTimeAxis
+ (NSArray<NSNumber *> *)hourlyTicksFrom:(NSTimeInterval)start
                                    to:(NSTimeInterval)end
                                 width:(double)width
                            labelWidth:(double)labelWidth
                              timeZone:(NSTimeZone *)timeZone {
    double span = end - start;
    if (!isfinite(start) || !isfinite(end) || !isfinite(width) || !isfinite(labelWidth) ||
        span <= 0 || span > 48 * 3600 || width <= 0 || labelWidth < 0 || width < labelWidth) return @[];
    double minimumHours = span / width * (labelWidth + 8) / 3600;
    NSInteger step = 24;
    for (NSNumber *candidate in @[@1, @2, @3, @4, @6, @12, @24]) {
        if (candidate.integerValue >= minimumHours) { step = candidate.integerValue; break; }
    }
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = timeZone ?: [NSTimeZone localTimeZone];
    NSDate *midnight = [calendar startOfDayForDate:[NSDate dateWithTimeIntervalSince1970:start]];
    NSTimeInterval cursor = midnight.timeIntervalSince1970;
    NSMutableArray *ticks = [NSMutableArray array];
    NSTimeInterval previous = -HUGE_VAL;
    // Absolute-hour iteration preserves both hours when the local clock moves back.
    for (; cursor <= end; cursor += 3600) {
        if (cursor < start) continue;
        NSDateComponents *parts = [calendar components:NSCalendarUnitHour | NSCalendarUnitMinute
                                             fromDate:[NSDate dateWithTimeIntervalSince1970:cursor]];
        if (parts.minute || parts.hour % step) continue;
        double spacing = (cursor - previous) / span * width;
        if (spacing < labelWidth + 8) continue;
        [ticks addObject:@(cursor)];
        previous = cursor;
    }
    return ticks;
}
+ (NSArray<NSDictionary *> *)bucketTicksForSeries:(NSArray<NSDictionary *> *)series
                                            from:(NSTimeInterval)start
                                              to:(NSTimeInterval)end
                                           width:(double)width
                                      labelWidth:(double)labelWidth {
    double span = end - start;
    if (!isfinite(start) || !isfinite(end) || !isfinite(width) || !isfinite(labelWidth) ||
        span <= 0 || width < labelWidth || width <= 0 || labelWidth < 0) return @[];
    NSMutableDictionary *buckets = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in series) {
        for (NSDictionary *point in entry[@"points"]) {
            if (![point[@"start"] isKindOfClass:[NSNumber class]] || ![point[@"end"] isKindOfClass:[NSNumber class]]) continue;
            double bucketStart = [point[@"start"] doubleValue], bucketEnd = [point[@"end"] doubleValue];
            if (!isfinite(bucketStart) || !isfinite(bucketEnd) || bucketEnd <= bucketStart) continue;
            double center = (bucketStart + bucketEnd) / 2;
            if (center < start || center > end) continue;
            // A bar describes the interval starting at its label, centered under the whole group.
            buckets[@(bucketStart)] = @{@"timestamp": @(center), @"labelTimestamp": @(bucketStart)};
        }
    }
    NSArray *keys = [[buckets allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *ticks = [NSMutableArray array];
    double previous = -HUGE_VAL;
    for (NSNumber *key in keys) {
        NSDictionary *tick = buckets[key];
        double center = [tick[@"timestamp"] doubleValue];
        if ((center - previous) / span * width < labelWidth + 8) continue;
        [ticks addObject:tick];
        previous = center;
    }
    return ticks;
}
@end

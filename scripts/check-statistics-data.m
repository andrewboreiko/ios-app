#import <Foundation/Foundation.h>
#import "HAStatisticsData.h"
#import "HAGraphTimeAxis.h"
#import <math.h>

static NSUInteger checks;
static void require(BOOL condition, NSString *message) {
    checks++;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        require(argc == 2, @"Pass the statistics fixture path");
        NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        NSDictionary *fixture = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        NSArray *rows = fixture[@"sensor.resetting_energy"];
        NSArray *points = [HAStatisticsData pointsFromRows:rows statistic:@"change"];
        require(points.count == 4, @"Null buckets must remain gaps");
        require(fabs([points[0][@"value"] doubleValue] - 0.46) < 1e-9, @"Use recorder change, not state or sum");
        require(fabs([points[1][@"value"] doubleValue] - 0.02) < 1e-9, @"Daily reset must not become negative consumption");
        require([points[2][@"value"] doubleValue] == 0, @"Zero consumption is valid data");
        require([points[2][@"start"] doubleValue] - [points[1][@"start"] doubleValue] == 7200, @"Do not compact missing buckets");
        require([points[0][@"start"] doubleValue] == 1794614400, @"Convert websocket milliseconds to seconds");
        require([HAStatisticsData pointsFromRows:(id)[NSNull null] statistic:@"change"].count == 0, @"Absent entity is empty");
        NSArray *invalid = @[@{@"start": @1, @"end": @2, @"change": @YES},
                             @{@"start": @2, @"end": @1, @"change": @4},
                             @{@"start": @1, @"end": @2, @"change": @"4"},
                             @{@"start": @1, @"end": @2, @"change": @(NAN)}, [NSNull null]];
        require([HAStatisticsData pointsFromRows:invalid statistic:@"change"].count == 0, @"Malformed rows are not fabricated as zero");
        NSArray *dst = @[@{@"start": @1792882800000, @"end": @1792972800000, @"change": @2}];
        NSDictionary *dstPoint = [HAStatisticsData pointsFromRows:dst statistic:@"change"].firstObject;
        require([dstPoint[@"end"] doubleValue] - [dstPoint[@"start"] doubleValue] == 90000, @"Preserve HA's 25-hour DST bucket");
        NSDictionary *options = [HAStatisticsData optionsFromProperties:@{@"days_to_show": @7, @"period": @"day", @"stat_types": @[@"change"], @"chart_type": @"bar"}];
        NSDictionary *command = [HAStatisticsData commandForEntityIds:@[@"sensor.resetting_energy"] options:options now:[NSDate dateWithTimeIntervalSince1970:1794628800]];
        require([command[@"type"] isEqual:@"recorder/statistics_during_period"], @"Use Recorder instead of raw history");
        require([command[@"start_time"] isEqual:@"2026-11-07T03:00:00Z"], @"Match HA's seven-day window plus first hour");
        require([command[@"period"] isEqual:@"day"] && [command[@"types"] isEqual:@[@"change"]], @"Request the configured aggregation");
        for (NSDictionary *props in @[@{@"days_to_show": @0}, @{@"days_to_show": @"7"}, @{@"days_to_show": @(NAN)}, @{@"period": @"bad"}, @{@"stat_types": @[@"bad"]}, @{@"chart_type": @"pie"}, @{@"days_to_show": @366, @"period": @"5minute"}]) {
            require([HAStatisticsData optionsFromProperties:props] == nil, @"Reject invalid or oversized statistics queries");
        }
        NSDictionary *defaults = [HAStatisticsData optionsFromProperties:@{}];
        require([defaults[@"days_to_show"] isEqual:@30] && [defaults[@"chart_type"] isEqual:@"line"], @"Statistics defaults differ from history defaults");
        require([[HAStatisticsData optionsFromProperties:@{@"stat_types": @"change"}][@"stat_types"] isEqual:@[@"change"]], @"Accept HA's string stat_types shorthand");
        NSTimeZone *utc = [NSTimeZone timeZoneForSecondsFromGMT:0];
        NSTimeInterval dayStart = 1794700800;
        NSArray *wideTicks = [HAGraphTimeAxis hourlyTicksFrom:dayStart to:dayStart + 25 * 3600 width:1000 labelWidth:25 timeZone:utc];
        require(wideTicks.count == 26, @"A wide 25-hour graph labels every hour");
        require([wideTicks[1] doubleValue] - [wideTicks[0] doubleValue] == 3600, @"Wide scale uses hourly ticks");
        NSArray *narrowTicks = [HAGraphTimeAxis hourlyTicksFrom:dayStart to:dayStart + 25 * 3600 width:600 labelWidth:25 timeZone:utc];
        require(narrowTicks.count == 13, @"A narrower graph labels every two hours");
        require([narrowTicks[1] doubleValue] - [narrowTicks[0] doubleValue] == 7200, @"Narrow scale uses two-hour ticks");
        NSArray *partial = [HAGraphTimeAxis hourlyTicksFrom:dayStart + 17 * 60 to:dayStart + 4 * 3600 + 41 * 60 width:600 labelWidth:25 timeZone:utc];
        require(partial.count == 4 && [partial[0] doubleValue] == dayStart + 3600, @"Ticks align to whole hours rather than fractional endpoints");
        NSArray *nepal = [HAGraphTimeAxis hourlyTicksFrom:dayStart to:dayStart + 4 * 3600 width:600 labelWidth:25 timeZone:[NSTimeZone timeZoneWithName:@"Asia/Kathmandu"]];
        require(fmod([nepal[0] doubleValue], 3600) == 900, @"Align hours in a timezone with a 45-minute offset");
        NSTimeZone *kyiv = [NSTimeZone timeZoneWithName:@"Europe/Kyiv"];
        NSDateFormatter *dateParser = [[NSDateFormatter alloc] init];
        dateParser.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        dateParser.dateFormat = @"yyyy-MM-dd HH:mm";
        dateParser.timeZone = kyiv;
        for (NSString *day in @[@"2026-03-29 00:00", @"2026-10-25 00:00"]) {
            NSDate *start = [dateParser dateFromString:day];
            NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
            calendar.timeZone = kyiv;
            NSDate *end = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:start options:0];
            NSArray *ticks = [HAGraphTimeAxis hourlyTicksFrom:start.timeIntervalSince1970 to:end.timeIntervalSince1970 width:2000 labelWidth:25 timeZone:kyiv];
            require(ticks.count == (NSUInteger)([end timeIntervalSinceDate:start] / 3600) + 1, @"DST days retain their real 23 or 25 hours");
            BOOL aligned = YES, increasing = YES;
            double previous = -HUGE_VAL;
            for (NSNumber *tick in ticks) {
                NSDateComponents *parts = [calendar components:NSCalendarUnitMinute fromDate:[NSDate dateWithTimeIntervalSince1970:tick.doubleValue]];
                aligned &= parts.minute == 0;
                increasing &= tick.doubleValue > previous;
                previous = tick.doubleValue;
            }
            require(aligned && increasing, @"DST tick timestamps stay aligned and strictly increasing");
        }
        for (NSArray *inputs in @[@[@0, @0, @500], @[@2, @1, @500], @[@0, @86400, @0], @[@0, @86400, @20], @[@0, @172801, @500], @[@0, @(NAN), @500]]) {
            require([HAGraphTimeAxis hourlyTicksFrom:[inputs[0] doubleValue] to:[inputs[1] doubleValue] width:[inputs[2] doubleValue] labelWidth:25 timeZone:utc].count == 0, @"Invalid or too-small axis ranges produce no ticks");
        }
        NSMutableArray *hourBuckets = [NSMutableArray array];
        for (NSUInteger i = 0; i < 25; i++) {
            double start = dayStart + i * 3600;
            [hourBuckets addObject:@{@"start": @(start), @"end": @(start + 3600)}];
        }
        NSArray *hourSeries = @[@{@"points": hourBuckets}, @{@"points": hourBuckets}];
        NSArray *barTicks = [HAGraphTimeAxis bucketTicksForSeries:hourSeries from:dayStart to:dayStart + 25 * 3600 width:1000 labelWidth:25];
        require(barTicks.count == 25, @"Each hourly group has one label, not one per entity or an extra ending hour");
        require([barTicks[0][@"labelTimestamp"] doubleValue] == dayStart, @"Hourly label describes the bucket start");
        require([barTicks[0][@"timestamp"] doubleValue] == dayStart + 1800, @"Hourly label sits under the middle of the three bars");
        require([barTicks.lastObject[@"labelTimestamp"] doubleValue] == dayStart + 24 * 3600, @"No phantom hour after the last bucket");
        NSArray *thinBarTicks = [HAGraphTimeAxis bucketTicksForSeries:hourSeries from:dayStart to:dayStart + 25 * 3600 width:600 labelWidth:25];
        require(thinBarTicks.count == 13, @"Hourly groups still adapt to two-hour spacing");
        NSMutableArray *dailyBuckets = [NSMutableArray array];
        NSDate *firstDay = [dateParser dateFromString:@"2026-11-08 00:00"];
        for (NSUInteger i = 0; i < 8; i++) {
            double start = firstDay.timeIntervalSince1970 + i * 86400;
            [dailyBuckets addObject:@{@"start": @(start), @"end": @(start + 86400)}];
        }
        NSArray *dailyTicks = [HAGraphTimeAxis bucketTicksForSeries:@[@{@"points": dailyBuckets}] from:firstDay.timeIntervalSince1970 to:firstDay.timeIntervalSince1970 + 8 * 86400 width:1000 labelWidth:25];
        require(dailyTicks.count == 8, @"Every recorded day has a date, not four arbitrary times");
        BOOL dailyAligned = YES;
        for (NSUInteger i = 0; i < dailyTicks.count; i++) {
            double start = [dailyBuckets[i][@"start"] doubleValue];
            dailyAligned &= [dailyTicks[i][@"labelTimestamp"] doubleValue] == start;
            dailyAligned &= [dailyTicks[i][@"timestamp"] doubleValue] == start + 43200;
        }
        require(dailyAligned, @"Daily dates describe midnight and are centered under their own group");
        NSArray *dstBarTicks = [HAGraphTimeAxis bucketTicksForSeries:@[@{@"points": @[dstPoint]}] from:[dstPoint[@"start"] doubleValue] to:[dstPoint[@"end"] doubleValue] width:500 labelWidth:25];
        require(dstBarTicks.count == 1 && [dstBarTicks[0][@"timestamp"] doubleValue] - [dstPoint[@"start"] doubleValue] == 45000, @"A 25-hour day uses its actual center, not an assumed 12 hours");
        require([dstBarTicks[0][@"labelTimestamp"] isEqual:dstPoint[@"start"]], @"DST does not change the date represented by the bar");
        require([HAGraphTimeAxis bucketTicksForSeries:@[] from:0 to:86400 width:500 labelWidth:25].count == 0, @"No dates are invented for an empty response");
        NSArray *gapSeries = @[@{@"points": @[hourBuckets[0], hourBuckets[2]]}];
        NSArray *gapTicks = [HAGraphTimeAxis bucketTicksForSeries:gapSeries from:dayStart to:dayStart + 3 * 3600 width:500 labelWidth:25];
        require(gapTicks.count == 2 && [gapTicks[1][@"labelTimestamp"] doubleValue] == dayStart + 7200, @"Missing data does not shift later labels");
        NSDate *peakHour = [dateParser dateFromString:@"2026-11-14 21:00"];
        double peakStart = peakHour.timeIntervalSince1970;
        NSArray *peakRows = @[@{@"start": @(peakStart * 1000), @"end": @((peakStart + 3600) * 1000), @"change": @0.96}];
        NSDictionary *peakPoint = [HAStatisticsData pointsFromRows:peakRows statistic:@"change"].firstObject;
        require([peakPoint[@"timestamp"] doubleValue] == peakStart, @"HA's 0.96 kWh peak at 21:00 must not move to 21:30");
        require([peakPoint[@"value"] isEqual:@0.96], @"Time alignment must not alter consumption");
        NSArray *peakBarTicks = [HAGraphTimeAxis bucketTicksForSeries:@[@{@"points": @[peakPoint]}] from:peakStart to:peakStart + 3600 width:500 labelWidth:25];
        require([peakBarTicks[0][@"timestamp"] doubleValue] == peakStart + 1800, @"The same interval still centers its bar group");
        require([peakBarTicks[0][@"labelTimestamp"] doubleValue] == peakStart, @"Bar label retains the 21:00 start");
        require([dstPoint[@"timestamp"] isEqual:dstPoint[@"start"]], @"Daily line points must not shift by half a DST day");
        fprintf(stdout, "%lu statistics data checks passed\n", (unsigned long)checks);
    }
    return 0;
}

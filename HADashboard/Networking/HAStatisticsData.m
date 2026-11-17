#import "HAStatisticsData.h"
#import <math.h>

@implementation HAStatisticsData

+ (NSDictionary *)optionsFromProperties:(NSDictionary *)properties {
    id rawDays = properties[@"days_to_show"] ?: @30;
    if (![rawDays isKindOfClass:[NSNumber class]]) return nil;
    double days = [rawDays doubleValue];
    if (!isfinite(days) || days <= 0 || days > 366) return nil;
    NSString *period = properties[@"period"] ?: @"auto";
    if (![period isKindOfClass:[NSString class]]) return nil;
    if ([period isEqual:@"auto"]) period = @"hour";
    NSDictionary *durations = @{@"5minute": @300, @"hour": @3600, @"day": @86400,
                               @"week": @604800, @"month": @2419200, @"year": @31536000};
    NSNumber *duration = durations[period];
    if (!duration || (days * 86400 + 3600) / duration.doubleValue > 5000) return nil;
    id types = properties[@"stat_types"] ?: @[@"change", @"state", @"sum", @"min", @"max", @"mean"];
    if ([types isKindOfClass:[NSString class]]) types = @[types];
    if (![types isKindOfClass:[NSArray class]] || [types count] == 0) return nil;
    NSSet *allowed = [NSSet setWithArray:@[@"change", @"state", @"sum", @"min", @"max", @"mean"]];
    for (id type in types) if (![allowed containsObject:type]) return nil;
    NSString *chart = properties[@"chart_type"] ?: @"line";
    if (![@[@"bar", @"line"] containsObject:chart]) return nil;
    return @{@"days_to_show": @(days), @"period": period,
             @"stat_types": [[NSOrderedSet orderedSetWithArray:types] array], @"chart_type": chart};
}

+ (NSDictionary *)commandForEntityIds:(NSArray<NSString *> *)entityIds
                             options:(NSDictionary *)options
                                 now:(NSDate *)now {
    if (!entityIds.count || !options || !now) return nil;
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    // HA's statistics card includes one extra hour for the first aggregated bucket.
    NSDate *start = [now dateByAddingTimeInterval:-([options[@"days_to_show"] doubleValue] * 86400 + 3600)];
    return @{@"type": @"recorder/statistics_during_period", @"statistic_ids": entityIds,
             @"start_time": [formatter stringFromDate:start], @"end_time": [formatter stringFromDate:now],
             @"period": options[@"period"], @"types": options[@"stat_types"]};
}

+ (NSArray<NSDictionary *> *)pointsFromRows:(NSArray *)rows statistic:(NSString *)statistic {
    if (![rows isKindOfClass:[NSArray class]]) return @[];
    NSMutableDictionary *byStart = [NSMutableDictionary dictionary];
    for (id row in rows) {
        if (![row isKindOfClass:[NSDictionary class]]) continue;
        id value = row[statistic], start = row[@"start"], end = row[@"end"];
        if (![value isKindOfClass:[NSNumber class]] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() ||
            ![start isKindOfClass:[NSNumber class]] || ![end isKindOfClass:[NSNumber class]]) continue;
        double v = [value doubleValue], s = [start doubleValue] / 1000, e = [end doubleValue] / 1000;
        if (!isfinite(v) || !isfinite(s) || !isfinite(e) || e <= s) continue;
        // Recorder supplies reset-aware change; never subtract raw sensor states here.
        // Recorder timestamps lines at interval start; bars use start/end to find their center.
        byStart[@(s)] = @{@"value": @(v), @"start": @(s), @"end": @(e), @"timestamp": @(s)};
    }
    NSArray *keys = [[byStart allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *points = [NSMutableArray arrayWithCapacity:keys.count];
    for (NSNumber *key in keys) [points addObject:byStart[key]];
    return points;
}
@end

#import <Foundation/Foundation.h>

@interface HAStatisticsData : NSObject
+ (NSDictionary *)optionsFromProperties:(NSDictionary *)properties;
+ (NSDictionary *)commandForEntityIds:(NSArray<NSString *> *)entityIds
                             options:(NSDictionary *)options
                                 now:(NSDate *)now;
+ (NSArray<NSDictionary *> *)pointsFromRows:(NSArray *)rows statistic:(NSString *)statistic;
@end

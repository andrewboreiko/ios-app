#import <XCTest/XCTest.h>
#import "HALovelaceParser.h"
#import "HADashboardConfig.h"
#import "HAGraphView.h"
#import "HAGraphCardCell.h"
#import "HAConnectionManager.h"
#import "HAStatisticsData.h"
#import <objc/runtime.h>

static void HACollectLineVertices(void *info, const CGPathElement *element) {
    if (element->type == kCGPathElementMoveToPoint || element->type == kCGPathElementAddLineToPoint) {
        [(__bridge NSMutableArray *)info addObject:[NSValue valueWithCGPoint:element->points[0]]];
    }
}

static NSMutableArray *statisticsCommands;
@interface HAConnectionManager (StatisticsTestTransport)
- (void)statisticsTestSendCommand:(NSDictionary *)command completion:(void (^)(id, NSError *))completion;
@end
@implementation HAConnectionManager (StatisticsTestTransport)
- (void)statisticsTestSendCommand:(NSDictionary *)command completion:(void (^)(id, NSError *))completion {
    [statisticsCommands addObject:@{@"command": command, @"completion": [completion copy]}];
}
@end

@interface HAStatisticsGraphTests : XCTestCase
@end
@implementation HAStatisticsGraphTests
- (void)testStatisticsConfigurationSurvivesSectionParsing {
    NSDictionary *card = @{@"type": @"statistics-graph", @"days_to_show": @7, @"period": @"day",
                           @"chart_type": @"bar", @"stat_types": @[@"change"],
                           @"entities": @[@{@"entity": @"sensor.energy", @"name": @"Fridge", @"color": @"amber"}]};
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:@{
        @"views": @[@{@"type": @"sections", @"sections": @[@{@"type": @"grid", @"cards": @[card]}]}]
    }];
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:2];
    NSDictionary *props = config.items.firstObject.entitiesSection.customProperties;
    XCTAssertEqualObjects(props[@"statistics"], @YES);
    for (NSString *key in @[@"days_to_show", @"period", @"chart_type", @"stat_types"]) XCTAssertEqualObjects(props[key], card[key]);
    XCTAssertEqualObjects(props[@"entityConfigs"][0][@"color"], @"amber");
}
- (void)testSingleNonzeroBucketRendersAndAllZeroSeriesKeepsAxes {
    HAGraphView *graph = [[HAGraphView alloc] initWithFrame:CGRectMake(0, 0, 500, 180)];
    graph.statisticsMode = YES;
    graph.barChart = YES;
    graph.showAxisLabels = YES;
    [graph setValue:@YES forKey:@"lightweight"];
    graph.dataSeries = @[@{@"points": @[@{@"start": @1000, @"end": @4600, @"timestamp": @2800, @"value": @0.46}],
                           @"color": [UIColor redColor], @"unit": @"kWh", @"label": @"Boiler"}];
    CAShapeLayer *layer = [[graph valueForKey:@"lineLayers"] firstObject];
    XCTAssertNotNil((__bridge id)layer.path);
    CGRect bounds = CGPathGetBoundingBox(layer.path);
    XCTAssertGreaterThan(bounds.size.height, 0);
    XCTAssertGreaterThan([[graph valueForKey:@"timeAxisLabels"] count], 0U);
    graph.dataSeries = @[@{@"points": @[@{@"start": @1000, @"end": @4600, @"timestamp": @2800, @"value": @0}],
                           @"unit": @"kWh", @"label": @"Idle"}];
    XCTAssertGreaterThan([[graph valueForKey:@"valueAxisLabels"] count], 0U);
}
- (void)testHourlyLabelsAdaptOnResizeWithoutOverlapping {
    HAGraphView *graph = [[HAGraphView alloc] initWithFrame:CGRectMake(0, 0, 1024, 180)];
    graph.statisticsMode = YES;
    graph.barChart = YES;
    graph.showAxisLabels = YES;
    [graph setValue:@YES forKey:@"lightweight"];
    NSMutableArray *points = [NSMutableArray array];
    for (NSUInteger hour = 0; hour < 25; hour++) {
        double start = 1794700800 + hour * 3600;
        [points addObject:@{@"start": @(start), @"end": @(start + 3600), @"timestamp": @(start + 1800), @"value": @1}];
    }
    graph.dataSeries = @[@{@"points": points, @"label": @"Energy", @"unit": @"kWh"}];
    NSArray *labels = [graph valueForKey:@"timeAxisLabels"];
    NSUInteger wideCount = labels.count;
    XCTAssertEqual(wideCount, 25U);
    UILabel *firstLabel = labels.firstObject;
    CGFloat expectedCenter = 35 + (graph.bounds.size.width - 35) / 50;
    XCTAssertEqualWithAccuracy(CGRectGetMidX(firstLabel.frame), expectedCenter, 0.1);
    for (UILabel *label in labels) XCTAssertTrue([label.text containsString:@":00"]);
    graph.frame = CGRectMake(0, 0, 600, 180);
    [graph setNeedsLayout];
    [graph layoutIfNeeded];
    labels = [graph valueForKey:@"timeAxisLabels"];
    XCTAssertGreaterThan(labels.count, 10U);
    XCTAssertLessThan(labels.count, wideCount);
    CGFloat end = -CGFLOAT_MAX;
    for (UILabel *label in labels) {
        XCTAssertGreaterThanOrEqual(CGRectGetMinX(label.frame), end + 6);
        XCTAssertGreaterThanOrEqual(CGRectGetMinX(label.frame), 0);
        XCTAssertLessThanOrEqual(CGRectGetMaxX(label.frame), graph.bounds.size.width);
        end = CGRectGetMaxX(label.frame);
    }
}
- (void)testWeeklyGraphLabelsEachDayAtItsGroupCenter {
    HAGraphView *graph = [[HAGraphView alloc] initWithFrame:CGRectMake(0, 0, 1024, 180)];
    graph.statisticsMode = YES;
    graph.barChart = YES;
    graph.showAxisLabels = YES;
    [graph setValue:@YES forKey:@"lightweight"];
    NSMutableArray *points = [NSMutableArray array];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"dd/MM";
    for (NSUInteger day = 0; day < 8; day++) {
        double start = 1794088800 + day * 86400;
        [points addObject:@{@"start": @(start), @"end": @(start + 86400), @"timestamp": @(start + 43200), @"value": @1}];
    }
    graph.dataSeries = @[@{@"points": points, @"label": @"Energy", @"unit": @"kWh"}];
    NSArray *labels = [graph valueForKey:@"timeAxisLabels"];
    XCTAssertEqual(labels.count, 8U);
    for (NSUInteger i = 0; i < labels.count; i++) {
        UILabel *label = labels[i];
        NSString *date = [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:[points[i][@"start"] doubleValue]]];
        XCTAssertEqualObjects(label.text, date);
        XCTAssertFalse([label.text containsString:@":"]);
        CGFloat expectedCenter = 35 + (i + 0.5) / 8 * (graph.bounds.size.width - 35);
        XCTAssertEqualWithAccuracy(CGRectGetMidX(label.frame), expectedCenter, 0.1);
    }
}
- (void)testLinePeakAlignsWithItsHourAndUsesZeroBaseline {
    HAGraphView *graph = [[HAGraphView alloc] initWithFrame:CGRectMake(0, 0, 1024, 180)];
    graph.statisticsMode = YES;
    graph.showAxisLabels = YES;
    [graph setValue:@YES forKey:@"lightweight"];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm";
    double start = [[formatter dateFromString:@"2026-11-14 20:00"] timeIntervalSince1970];
    NSMutableArray *rows = [NSMutableArray array];
    NSArray *values = @[@0, @0.96, @0.31, @0.74, @0];
    for (NSUInteger i = 0; i < values.count; i++) {
        [rows addObject:@{@"start": @((start + i * 3600) * 1000), @"end": @((start + (i + 1) * 3600) * 1000), @"change": values[i]}];
    }
    NSArray *points = [HAStatisticsData pointsFromRows:rows statistic:@"change"];
    graph.dataSeries = @[@{@"points": points, @"label": @"Boiler", @"unit": @"kWh"}];
    CAShapeLayer *line = [[graph valueForKey:@"lineLayers"] firstObject];
    NSMutableArray *vertices = [NSMutableArray array];
    CGPathApply(line.path, (__bridge void *)vertices, HACollectLineVertices);
    XCTAssertEqual(vertices.count, values.count);
    CGPoint peak = [vertices[1] CGPointValue];
    CGFloat expectedX = 35 + 0.25 * (graph.bounds.size.width - 35);
    XCTAssertEqualWithAccuracy(peak.x, expectedX, 0.1);
    BOOL found = NO;
    for (UILabel *label in [graph valueForKey:@"timeAxisLabels"]) {
        if (![label.text isEqual:@"21:00"]) continue;
        found = YES;
        XCTAssertEqualWithAccuracy(CGRectGetMidX(label.frame), peak.x, 0.1);
    }
    XCTAssertTrue(found);
    XCTAssertEqualObjects([[graph valueForKey:@"axisGroups"] firstObject][@"yMin"], @0);
}
- (void)testReusedCellRejectsOldResponseAndShowsZeroConsumption {
    Method live = class_getInstanceMethod([HAConnectionManager class], @selector(sendCommand:completion:));
    Method fake = class_getInstanceMethod([HAConnectionManager class], @selector(statisticsTestSendCommand:completion:));
    statisticsCommands = [NSMutableArray array];
    method_exchangeImplementations(live, fake);
    @try {
        HADashboardConfigSection *section = [[HADashboardConfigSection alloc] init];
        section.entityIds = @[@"sensor.energy"];
        section.customProperties = @{@"statistics": @YES, @"days_to_show": @1, @"period": @"hour",
                                     @"stat_types": @[@"change"], @"chart_type": @"bar"};
        HAGraphCardCell *cell = [[HAGraphCardCell alloc] initWithFrame:CGRectMake(0, 0, 500, 240)];
        [cell configureWithSection:section entities:@{}];
        [cell beginLoading];
        void (^firstMetadata)(id, NSError *) = statisticsCommands[0][@"completion"];
        firstMetadata(@[@{@"statistic_id": @"sensor.energy", @"unit_of_measurement": @"kWh"}], nil);
        XCTAssertEqualObjects(statisticsCommands[1][@"command"][@"period"], @"hour");
        void (^oldStatistics)(id, NSError *) = statisticsCommands[1][@"completion"];
        [cell prepareForReuse];
        section.customProperties = @{@"statistics": @YES, @"days_to_show": @7, @"period": @"day",
                                     @"stat_types": @[@"change"], @"chart_type": @"bar"};
        [cell configureWithSection:section entities:@{}];
        [cell beginLoading];
        oldStatistics(@{@"sensor.energy": @[@{@"start": @1000000, @"end": @4600000, @"change": @999}]}, nil);
        HAGraphView *graph = [cell valueForKey:@"graphView"];
        XCTAssertEqual(graph.dataSeries.count, 0U);
        void (^nextMetadata)(id, NSError *) = statisticsCommands[2][@"completion"];
        nextMetadata(@[@{@"statistic_id": @"sensor.energy", @"unit_of_measurement": @"kWh"}], nil);
        XCTAssertEqualObjects(statisticsCommands[3][@"command"][@"period"], @"day");
        void (^nextStatistics)(id, NSError *) = statisticsCommands[3][@"completion"];
        nextStatistics(@{@"sensor.energy": @[@{@"start": @1000000, @"end": @87400000, @"change": @0}]}, nil);
        XCTAssertEqual(graph.dataSeries.count, 1U);
        XCTAssertEqualObjects(graph.dataSeries[0][@"points"][0][@"value"], @0);
        XCTAssertEqualObjects(graph.dataSeries[0][@"unit"], @"kWh");
        XCTAssertNil([[cell valueForKey:@"valueLabel"] text]);
        [cell beginLoading];
        XCTAssertEqual(statisticsCommands.count, 4U);
        [cell cancelLoading];
    } @finally {
        method_exchangeImplementations(live, fake);
        statisticsCommands = nil;
    }
}
@end

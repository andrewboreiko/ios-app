#import <XCTest/XCTest.h>
#import <AVFoundation/AVFoundation.h>
#import "HACameraEntityCell.h"
#import "HADashboardViewController.h"
#import "HADashboardConfig.h"
#import "HALovelaceParser.h"
#import "HAEntity.h"
#import "HAPanelLayout.h"

@interface HACameraEntityCell (FitModeTestAccess)
@property (nonatomic, strong) UIImageView *snapshotView;
@property (nonatomic, strong) AVPlayerLayer *hlsPlayerLayer;
- (void)playHLSURL:(NSURL *)url;
@end

@interface HADashboardViewController (FitModeTestAccess)
- (CGFloat)heightForItemAtIndexPath:(NSIndexPath *)indexPath itemWidth:(CGFloat)itemWidth;
@end

@interface HACameraFitModeTests : XCTestCase
@end

@implementation HACameraFitModeTests

- (HADashboardConfigItem *)itemForCard:(NSDictionary *)card {
    HALovelaceDashboard *dashboard = [HALovelaceParser parseDashboardFromDictionary:@{
        @"views": @[@{@"title": @"Camera", @"cards": @[card]}]
    }];
    HADashboardConfig *config = [HALovelaceParser dashboardConfigFromView:dashboard.views.firstObject columns:1];
    return config.items.firstObject;
}

- (HAEntity *)camera {
    return [[HAEntity alloc] initWithDictionary:@{
        @"entity_id": @"camera.test", @"state": @"idle", @"attributes": @{}
    }];
}

- (HADashboardConfigItem *)itemWithMode:(id)mode {
    NSMutableDictionary *card = [@{@"type": @"picture-entity", @"entity": @"camera.test"} mutableCopy];
    if (mode) card[@"fit_mode"] = mode;
    return [self itemForCard:card];
}

- (void)testParserRetainsSupportedModesAndIgnoresInvalidValues {
    for (NSString *mode in @[@"contain", @"cover"]) {
        XCTAssertEqualObjects([self itemWithMode:mode].customProperties[@"fit_mode"], mode);
    }
    for (id value in @[@"stretch", @42, [NSNull null]]) {
        XCTAssertNil([self itemWithMode:value].customProperties[@"fit_mode"]);
    }
    XCTAssertNil([self itemWithMode:nil].customProperties[@"fit_mode"]);
}

- (void)testSnapshotModeChangesWhenSameCellIsReconfigured {
    HACameraEntityCell *cell = [[HACameraEntityCell alloc] initWithFrame:CGRectMake(0, 0, 500, 300)];
    HAEntity *camera = [self camera];
    [cell configureWithEntity:camera configItem:[self itemWithMode:@"contain"]];
    XCTAssertEqual(cell.snapshotView.contentMode, UIViewContentModeScaleAspectFit);
    [cell prepareForReuse];
    [cell configureWithEntity:camera configItem:[self itemWithMode:@"cover"]];
    XCTAssertEqual(cell.snapshotView.contentMode, UIViewContentModeScaleAspectFill);
    [cell configureWithEntity:camera configItem:[self itemWithMode:@"contain"]];
    [cell configureWithEntity:camera configItem:[self itemWithMode:nil]];
    XCTAssertEqual(cell.snapshotView.contentMode, UIViewContentModeScaleAspectFill);
    [cell stopRefresh];
}

- (void)testActiveHLSLayerChangesGravityWithoutReplacement {
    HACameraEntityCell *cell = [[HACameraEntityCell alloc] initWithFrame:CGRectMake(0, 0, 500, 300)];
    HAEntity *camera = [self camera];
    [cell configureWithEntity:camera configItem:[self itemWithMode:@"cover"]];
    AVPlayerLayer *layer = [AVPlayerLayer layer];
    cell.hlsPlayerLayer = layer;
    [cell configureWithEntity:camera configItem:[self itemWithMode:@"contain"]];
    XCTAssertEqual(cell.hlsPlayerLayer, layer);
    XCTAssertEqualObjects(layer.videoGravity, AVLayerVideoGravityResizeAspect);
    [cell configureWithEntity:camera configItem:[self itemWithMode:@"cover"]];
    XCTAssertEqualObjects(layer.videoGravity, AVLayerVideoGravityResizeAspectFill);
    [cell stopRefresh];
}

- (void)testNewHLSLayerUsesConfiguredContainMode {
    HACameraEntityCell *cell = [[HACameraEntityCell alloc] initWithFrame:CGRectMake(0, 0, 500, 300)];
    [cell configureWithEntity:[self camera] configItem:[self itemWithMode:@"contain"]];
    [cell playHLSURL:[NSURL URLWithString:@"http://127.0.0.1:9/test.m3u8"]];
    XCTAssertEqualObjects(cell.hlsPlayerLayer.videoGravity, AVLayerVideoGravityResizeAspect);
    [cell stopRefresh];
}

- (void)testAutomaticPanelContainHeightMatchesViewport {
    HADashboardViewController *controller = [[HADashboardViewController alloc] init];
    UICollectionView *collection = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 0, 1024, 600)
                                                    collectionViewLayout:[[HAPanelLayout alloc] init]];
    HADashboardConfigSection *section = [[HADashboardConfigSection alloc] init];
    section.items = @[[self itemWithMode:@"contain"]];
    HADashboardConfig *config = [[HADashboardConfig alloc] init];
    config.sections = @[section];
    [controller setValue:collection forKey:@"collectionView"];
    [controller setValue:config forKey:@"dashboardConfig"];
    XCTAssertEqual([controller heightForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]
                                            itemWidth:1024], 600);
}

@end

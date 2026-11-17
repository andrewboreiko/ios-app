# Local HA Dashboard fork for iPad

Status: 2026-11-18. Origin: https://github.com/andrewboreiko/ios-app . Upstream: https://github.com/ha-dashboard/ios-app . Upstream base: 28e6937, branch ipad-compatibility. Changes are organized into thematic commits. The user authorized publishing this branch on 2026-11-18; no PR has been created. This project is separate from the alert maps.

## Setup and device verification

- User device: iPad mini 1, armv7, iOS 9.3.6, jailbreak and AppSync Unified.
- Xcode 27.2 (27B52), XcodeGen 2.46.0. No simulator runtimes are installed. Global xcode-select was unchanged; builds use DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer.
- iOS 9 linking uses SDK 15.2 from Xcode 13.2.1: upstream release xcode13-sdk-stubs-v1, archive SHA256 7b89a8882d60246b0ba53ed4a61363a0cbcad648e5b36874940bf4ee400c2dfc. Extracted into ignored build/toolchains/iPhoneOS.sdk.
- Ignored .env contains only BUNDLE_ID=com.andrewboreiko.hadashboard.dev and XCODE13_SDK_PATH. Compilation needs no HA token.
- The user manually installed baseline 351 and confirmed launch/connection. They then installed 351.1 and confirmed the complete uncropped camera frame on iPad. Confirmed YAML: panel, camera.doorbell_fluent, fit_mode: contain, show_name/show_state: false, without dimensions.height.
- The test app is HA Dashboard Dev with a separate Bundle ID; the original app remains separate. iPad installation, HA changes and publication require explicit permission. Do not open a browser without separate permission.

## Local implementation

### Camera — 351.1, confirmed by the user

The parser preserves contain/cover. The snapshot/MJPEG UIImageView and HLS layer use AspectFit/ResizeAspect for contain. An active layer changes mode without restarting. Missing/unknown fit_mode keeps cover. A contain panel without explicit height/rows uses the viewport height. Fullscreen mode and explicit sizes remain unchanged.

### Statistics — 351.2, iPad verification pending

- statistics-graph is distinguished from history-graph. The parser passes days_to_show, period, stat_types, chart_type, entity names and colors.
- recorder/get_statistics_metadata and recorder/statistics_during_period use the existing authenticated WebSocket connection. Units come from Recorder metadata. Change is used directly, without subtracting raw state/sum; daily sensor resets do not become negative consumption.
- Grouped bars use HA's actual start/end boundaries, including DST. Rendering includes a zero baseline, axes on armv7, a legend and independent scaling by unit. The current sensor state is not displayed as period consumption.
- Supported: bar/line, change/state/sum/min/max/mean, 5minute/hour/day/week/month/year. Missing period/auto uses hour, matching HA's default request; the default window is 30 days. Queries are limited to 366 days and approximately 5000 buckets per sensor.
- Refresh occurs once a minute while the card is visible. There is a 20-second UI timeout, response identity checks after reconfiguration, and error/empty/partially missing data messages. Gaps are not fabricated as zero; real zero values remain valid.
- Automatic statistics card height is 240 pt. Long press does not open the previous raw-history detail; a dedicated interactive statistics detail is not implemented. Options such as logarithmic_scale, energy_date_selection, min/max_y_axis and unit conversion were not implemented.
- Read-only MCP confirmed change in kWh for all five sensors in the user's YAML: refrigerator/reolink daily, boiler daily, refrigerator/reolink summation_delivered. HA has the data; HA configuration was unchanged. This does not verify the new iPad renderer.

## Validation

- 22 Foundation checks actually executed on Mac: resets, null, zero, gaps, milliseconds, a 25-hour DST bucket, request options and rejection of invalid/oversized queries. Fixture: HADashboardTests/Fixtures/statistics-hourly.json.
- HACameraFitModeTests and HAStatisticsGraphTests passed syntax compilation. They cover parser, reuse, HLS, panel, single/zero bars, armv7 axes and a late response after changing period. XCTest was not executed: no simulator runtimes are installed.
- Final native armv7 and arm64 compilation/linking passed; minimum iOS 9.0 and ARM-mode entry were verified. The new Objective-C module was registered manually in xcodeproj; upstream snapshot resources were preserved.
- IPA checks: ZIP CRC, required resources, codesign, architectures and minimum iOS passed in the packager. 351.2 has not been installed or tested on iPad.

## Reproducing the build

```sh
HADASHBOARD_SLICES_ONLY=YES bash scripts/build.sh device
HADASHBOARD_BUILD_NUMBER=351.6 python3 scripts/package-appsync.py
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun clang -fobjc-arc -framework Foundation -I HADashboard/Networking -I HADashboard/Views scripts/check-statistics-data.m HADashboard/Networking/HAStatisticsData.m HADashboard/Views/HAGraphTimeAxis.m -o /tmp/ha-statistics-data-check
/tmp/ha-statistics-data-check HADashboardTests/Fixtures/statistics-hourly.json
```

scripts/package-appsync.py builds an unsigned resource template, replaces its executable with the universal iOS 9 binary, prepares LaunchScreen/icons/Info.plist and signs ad-hoc for AppSync. It refuses binaries older than Objective-C sources/headers. It does not change secrets, HA or iPad. Previous IPA builds 351 and 351.1 are preserved.

Current artifact: build/appsync/HA-Dashboard-Dev-1.3.1-351.6-appsync.ipa.
SHA256: 00f295b2619f6fc6905c24b49f0cb9350e6413ee6c8f2fb3d7858977c54ea8ad.
Manifest: build/appsync/build-manifest.json; records appSourcesSha256, Bundle ID and deviceTested=false.
Logs: /tmp/ha-dashboard-statistics-build.log and /tmp/ha-dashboard-statistics-package.log.

## Next step

The user manually upgrades HA Dashboard Dev through USB/AppSync and checks Charts with the existing YAML: hourly change bars over 24 hours and daily change bars over 7 days, comparing colors and values with standard HA. Check returning to the tab and that camera contain still works. Update the 351.2 status after actual device verification. No fallback PNG chart generator has been created; if needed, it will be another separate project.

## Adaptive time axis — 351.3, 2026-11-15

- Hourly statistics over ranges up to 48 hours use ticks aligned to whole local hours. Wide graphs label every hour, narrower graphs every two hours; very narrow graphs use larger intervals to avoid overlap. Density uses the actual plot width and measured label width and is recalculated on resize.
- HH:mm also applies to the usual 25-hour query range for a one-day card. Edge labels are skipped if clamping them to the view bounds would overlap a neighbor. Weekly, daily and ordinary history graphs are unchanged.
- Foundation-only HAGraphTimeAxis generates ticks in the local timezone. 38 local checks actually passed: the previous 22 plus hourly/two-hour density, fractional endpoints, a timezone with a 45-minute offset, Kyiv spring/autumn DST and invalid sizes/ranges.
- HAStatisticsGraphTests now checks label density and non-overlap after resizing. XCTest syntax compilation passed; XCTest was not executed because no simulator runtime is installed.
- armv7/arm64 compilation and linking for iOS 9 passed. IPA 351.3 passed packager validation; it has not been installed on iPad. Logs: /tmp/ha-dashboard-axis-build.log and /tmp/ha-dashboard-axis-package.log.
- Next step: manually upgrade HA Dashboard Dev to 351.3, open Charts and check denser labels and adaptive density when the graph becomes narrower. HA configuration and the web card were unchanged.

## Exact bar interval labels — 351.4, 2026-11-15

The user's photos show a defect in the previous renderer: the weekly axis contained four arbitrary timestamps, such as 10/11 16:00, while hourly ticks sat on group boundaries. This is an axis alignment defect; the photos do not establish a discrepancy in the consumption values themselves.

- Statistics bar labels now use the actual Recorder interval start, while their X coordinate uses the midpoint of start/end, under the entire group of devices. There is no extra hour after the final group.
- Hourly format is HH:mm; daily/longer format is dd/MM. At sufficient width, the weekly graph labels every recorded day. Narrow graphs thin labels according to actual spacing without shifting the date/hour represented.
- Shared intervals across sensors do not duplicate ticks; gaps do not shift later dates. A 25-hour day's center uses its actual boundaries, while its label retains the starting date.
- 49 Foundation checks actually passed. XCTest now checks the exact hourly group center and eight daily date labels; syntax compilation passed, but simulator execution was not performed because no runtime is installed.
- armv7/arm64 compilation/linking for iOS 9 passed; IPA 351.4 passed packager validation. The new version has not been verified on iPad. Logs: /tmp/ha-dashboard-bucket-axis-build.log and /tmp/ha-dashboard-bucket-axis-package.log.
- Next step: manually upgrade Dev to 351.4, check the date under every daily group and the hour under each hourly group's center. If heights/values themselves differ from HA, compare the identical Recorder time interval rather than drawing conclusions from axis labels alone.

## Line statistics without the half-hour shift — 351.5, 2026-11-15

The user replaced chart_type: line-stack with line; the current Dev does not support line-stack. Comparison photos showed the boiler's 0.96 kWh peak at 21:00 in HA, but between 21:00 and 22:00 on iPad. Our normalization incorrectly assigned the interval midpoint as timestamp.

- Normalized statistics points now use Recorder start as timestamp. The value for 21:00–22:00 is therefore plotted at 21:00, matching the HA example. The change value is unchanged.
- Bar rendering and group labels continue to use start/end and their midpoint independently of the line timestamp. Daily groups and adaptive density remain intact.
- Nonnegative line statistics use a zero Y baseline instead of negative padding. Negative data and history graphs retain their previous scaling behavior.
- 54 Foundation checks actually passed, including the 0.96 kWh point at 21:00, value preservation, independent bar centering and DST. XCTest now checks the peak's geometric alignment with 21:00 and the zero baseline; syntax compilation passed. XCTest was not executed because no simulator runtime is installed.
- armv7/arm64 compilation/linking for iOS 9 passed; IPA 351.5 passed packager checks. It has not been verified on iPad. Logs: /tmp/ha-dashboard-line-time-build.log and /tmp/ha-dashboard-line-time-package.log.
- Next: manually upgrade Dev to 351.5, retain chart_type: line, check that the November 14 21:00 peak aligns with the 21:00 label, and recheck weekly bars. HA and the Dashboard were unchanged.

## iPad tab icons — 351.6, 2026-11-16

- The top iPad view picker displays the Dashboard view.icon instead of its text title. It uses the existing MDI renderer at 20 pt, with template images and the segment's system selection tint.
- Missing or unknown icons fall back to the view title. The title is also assigned as the image accessibilityLabel; on-device VoiceOver behavior has not been verified. iPhone text tabs are unchanged.
- Native armv7/arm64 compilation and linking for iOS 9 passed. home, cctv, shield-alert, power-plug and chart-areaspline were verified in the bundled MDI map. The packager validated IPA 351.6 resources, ZIP, signature, architectures and minimum iOS. Visual iPad verification is pending.
- Logs: /tmp/ha-dashboard-tab-icons-build.log and /tmp/ha-dashboard-tab-icons-package.log. HA/Dashboard, GitHub and the device were unchanged.
- Next step: manually upgrade HA Dashboard Dev to 351.6, check all tab icons, selection tint and switching. If a tab still shows text, check its YAML icon. This build retains the graph changes from 351.5.

## Local commit organization — 2026-11-17

Five commits separate AppSync packaging, camera containment, Recorder statistics with aligned axes, iPad tab icons, and English setup documentation. Shared parser/controller/project changes are split by feature so each commit includes its own dependencies and test registrations. IPA files, build output, .env and SDK stubs are ignored and excluded.

Pre-commit verification: 54 Foundation checks passed; the Xcode project plist is valid; packaging script syntax is valid; current application source hashes match validated IPA 351.6. XCTest execution remains unverified because no simulator runtime is installed. The user's photo after 351.5 shows the hourly peak aligned at 21:00; iPad tab icons still require device verification.

Review with `git log --oneline 28e6937..HEAD`. Next step: verify 351.6 tab icons on iPad. The user authorized pushing this branch on 2026-11-18; opening a PR or merging is outside that request.

import XCTest
@testable import FANcyCore

final class CurveProfileTests: XCTestCase {

    private let presets: [CurveProfile] = [.silent, .balanced, .performance, .gaming]

    func testOnlyCustomHasNoPresetCurve() {
        for profile in CurveProfile.allCases {
            XCTAssertEqual(profile.curve == nil, profile == .custom, "\(profile)")
        }
    }

    func testEveryPresetStaysWithinZeroToHundredPercent() {
        for profile in presets {
            for point in profile.curve!.points {
                XCTAssertTrue((0...100).contains(point.pct), "\(profile): \(point.pct)%")
            }
        }
    }

    func testPresetsNeverSlowFansDownAsTemperatureRises() {
        for profile in presets {
            let sorted = profile.curve!.points.sorted { $0.temp < $1.temp }
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                XCTAssertLessThanOrEqual(a.pct, b.pct,
                    "\(profile) drops between \(a.temp)°C and \(b.temp)°C")
            }
        }
    }

    func testPresetsAreOrderedQuietToAggressive() {
        // At every temperature a quieter profile asks for no more airflow than
        // a louder one — otherwise the names in the menu would lie.
        for temp in stride(from: 30.0, through: 95.0, by: 5) {
            let pcts = presets.map { $0.curve!.interpolate(temp: temp) }
            for (quieter, louder) in zip(pcts, pcts.dropFirst()) {
                XCTAssertLessThanOrEqual(quieter, louder, "at \(temp)°C: \(pcts)")
            }
        }
    }

    func testEveryProfileHasLabelAndIcon() {
        for profile in CurveProfile.allCases {
            XCTAssertFalse(profile.label.isEmpty, "\(profile)")
            XCTAssertFalse(profile.icon.isEmpty, "\(profile)")
        }
    }
}

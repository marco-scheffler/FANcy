import XCTest
@testable import FANcyCore

final class FanCurveTests: XCTestCase {

    private let curve = FanCurve(points: [(30, 0), (50, 20), (70, 60), (90, 100)])

    // MARK: - Interpolation

    func testBelowFirstPointClampsToFirstPercentage() {
        XCTAssertEqual(curve.interpolate(temp: 10), 0)
    }

    func testAboveLastPointClampsToLastPercentage() {
        XCTAssertEqual(curve.interpolate(temp: 105), 100)
    }

    func testExactPointReturnsItsPercentage() {
        XCTAssertEqual(curve.interpolate(temp: 70), 60)
    }

    func testBetweenPointsInterpolatesLinearly() {
        // Halfway between (50, 20) and (70, 60).
        XCTAssertEqual(curve.interpolate(temp: 60), 40, accuracy: 0.0001)
    }

    func testUnsortedPointsGiveSameResultAsSorted() {
        // The curve editor can leave points in any order after a drag.
        let shuffled = FanCurve(points: [(70, 60), (30, 0), (90, 100), (50, 20)])
        for temp in stride(from: 20.0, through: 100.0, by: 2.5) {
            XCTAssertEqual(shuffled.interpolate(temp: temp), curve.interpolate(temp: temp),
                           accuracy: 0.0001, "at \(temp)°C")
        }
    }

    func testEmptyCurveReturnsZero() {
        XCTAssertEqual(FanCurve(points: []).interpolate(temp: 60), 0)
    }

    // MARK: - RPM conversion

    func testPercentageMapsOntoFanRange() {
        XCTAssertEqual(FanCurve.pctToRPM(0, min: 2000, max: 6000), 2000)
        XCTAssertEqual(FanCurve.pctToRPM(100, min: 2000, max: 6000), 6000)
        XCTAssertEqual(FanCurve.pctToRPM(25, min: 2000, max: 6000), 3000)
    }

    // MARK: - Deadband

    func testSmallChangesStayInsideDeadband() {
        XCTAssertFalse(FanCurve.needsUpdate(targetRPM: 3000, lastRPM: 3000))
        XCTAssertFalse(FanCurve.needsUpdate(targetRPM: 3050, lastRPM: 3000))
        XCTAssertFalse(FanCurve.needsUpdate(targetRPM: 2950, lastRPM: 3000))
    }

    func testChangesBeyondDeadbandTriggerUpdate() {
        XCTAssertTrue(FanCurve.needsUpdate(targetRPM: 3051, lastRPM: 3000))
        XCTAssertTrue(FanCurve.needsUpdate(targetRPM: 2949, lastRPM: 3000))
    }

    func testFirstApplicationAfterActivationAlwaysWrites() {
        // AppState resets the last applied RPM to 0 when a curve is activated,
        // so even the slowest target must be written.
        let slowest = FanCurve.pctToRPM(0, min: 2317, max: 7826)
        XCTAssertTrue(FanCurve.needsUpdate(targetRPM: slowest, lastRPM: 0))
    }

    // MARK: - Persistence format

    func testCodableRoundTripPreservesCurve() throws {
        let data = try JSONEncoder().encode(curve)
        let decoded = try JSONDecoder().decode(FanCurve.self, from: data)
        XCTAssertEqual(decoded, curve)
    }

    func testEqualityToleratesFloatingPointNoise() {
        let nudged = FanCurve(points: [(30.001, 0), (50, 20), (70, 60), (90, 100.004)])
        XCTAssertEqual(nudged, curve)

        let different = FanCurve(points: [(30, 0), (50, 25), (70, 60), (90, 100)])
        XCTAssertNotEqual(different, curve)
    }
}

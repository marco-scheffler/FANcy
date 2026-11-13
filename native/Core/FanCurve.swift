import Foundation

/// A temperature->fan% mapping curve with linear interpolation.
struct FanCurve: Codable, Equatable {
    var points: [(temp: Double, pct: Double)]

    // MARK: - Preset profiles

    static let `default` = FanCurve(points: [
        (30, 0), (45, 5), (60, 30), (75, 65), (90, 100),
    ])

    static let silent = FanCurve(points: [
        (30, 0), (50, 0), (65, 15), (80, 40), (95, 70),
    ])

    static let balanced = FanCurve(points: [
        (30, 0), (45, 5), (60, 30), (75, 65), (90, 100),
    ])

    static let performance = FanCurve(points: [
        (30, 10), (45, 25), (55, 50), (70, 80), (85, 100),
    ])

    static let gaming = FanCurve(points: [
        (30, 20), (40, 40), (50, 60), (65, 85), (80, 100),
    ])

    // Codable support for tuple array
    enum CodingKeys: String, CodingKey { case points }
    struct Point: Codable { var temp: Double; var pct: Double }

    init(points: [(temp: Double, pct: Double)]) {
        self.points = points
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let pts = try c.decode([Point].self, forKey: .points)
        self.points = pts.map { ($0.temp, $0.pct) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(points.map { Point(temp: $0.temp, pct: $0.pct) }, forKey: .points)
    }

    static func == (lhs: FanCurve, rhs: FanCurve) -> Bool {
        guard lhs.points.count == rhs.points.count else { return false }
        for (a, b) in zip(lhs.points, rhs.points) {
            if abs(a.temp - b.temp) > 0.01 || abs(a.pct - b.pct) > 0.01 { return false }
        }
        return true
    }

    /// Linear interpolation. Returns fan % for a given temperature.
    func interpolate(temp: Double) -> Double {
        let sorted = points.sorted { $0.temp < $1.temp }
        guard let first = sorted.first, let last = sorted.last else { return 0 }
        if temp <= first.temp { return first.pct }
        if temp >= last.temp { return last.pct }
        for i in 0..<(sorted.count - 1) {
            if sorted[i].temp <= temp && temp <= sorted[i + 1].temp {
                let t = (temp - sorted[i].temp) / (sorted[i + 1].temp - sorted[i].temp)
                return sorted[i].pct + t * (sorted[i + 1].pct - sorted[i].pct)
            }
        }
        return last.pct
    }

    /// Convert fan % to RPM.
    static func pctToRPM(_ pct: Double, min: Double, max: Double) -> Double {
        min + (pct / 100.0) * (max - min)
    }

    /// Minimum change in target RPM before the curve rewrites the fans. Keeps
    /// them from hunting audibly on every small temperature wiggle.
    static let deadbandRPM: Double = 50

    /// Whether a newly computed curve target differs enough from the last
    /// applied one to be worth writing to the fans.
    static func needsUpdate(targetRPM: Double, lastRPM: Double) -> Bool {
        abs(targetRPM - lastRPM) > deadbandRPM
    }

    // MARK: - Persistence

    private static var appDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("FANcy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var fileURL: URL { appDir.appendingPathComponent("fan_curve.json") }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.fileURL)
        }
    }

    static func load() -> FanCurve {
        guard let data = try? Data(contentsOf: fileURL),
              let curve = try? JSONDecoder().decode(FanCurve.self, from: data)
        else { return .default }
        return curve
    }
}

// MARK: - Profile

enum CurveProfile: String, CaseIterable, Identifiable {
    case silent, balanced, performance, gaming, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .silent: return L10n.silent
        case .balanced: return L10n.balanced
        case .performance: return L10n.performance
        case .gaming: return L10n.gaming
        case .custom: return L10n.custom
        }
    }

    var icon: String {
        switch self {
        case .silent: return "moon.fill"
        case .balanced: return "equal.circle.fill"
        case .performance: return "bolt.fill"
        case .gaming: return "gamecontroller.fill"
        case .custom: return "slider.horizontal.3"
        }
    }

    var curve: FanCurve? {
        switch self {
        case .silent: return .silent
        case .balanced: return .balanced
        case .performance: return .performance
        case .gaming: return .gaming
        case .custom: return nil
        }
    }
}

import Foundation
import XCTest

/// Checks the Sparkle setup the app ships with. Mistakes here don't crash
/// anything — they silently stop every installed copy from ever updating.
final class UpdateConfigurationTests: XCTestCase {

    private static let sparkleNS = "http://www.andymatuschak.org/xml-namespaces/sparkle"

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // FANcyCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root

    private func infoPlist() throws -> [String: Any] {
        let url = Self.repoRoot.appendingPathComponent("native/Resources/Info.plist")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    private func appBuildNumber() throws -> Int {
        let raw = try XCTUnwrap(try infoPlist()["CFBundleVersion"] as? String)
        return try XCTUnwrap(Int(raw), "CFBundleVersion '\(raw)' isn't a plain integer — Sparkle compares it numerically")
    }

    // MARK: - Info.plist

    func testFeedURLPointsAtTheCommittedAppcast() throws {
        let raw = try XCTUnwrap(try infoPlist()["SUFeedURL"] as? String)
        let url = try XCTUnwrap(URL(string: raw))
        XCTAssertEqual(url.scheme, "https", "Sparkle refuses plain-http feeds")
        XCTAssertEqual(url.host, "raw.githubusercontent.com")
        XCTAssertEqual(url.path, "/marco-scheffler/FANcy/main/appcast.xml")
    }

    func testPublicKeyIsAnEd25519Key() throws {
        let key = try XCTUnwrap(try infoPlist()["SUPublicEDKey"] as? String)
        let bytes = try XCTUnwrap(Data(base64Encoded: key), "SUPublicEDKey isn't base64")
        XCTAssertEqual(bytes.count, 32, "an Ed25519 public key is 32 bytes")
    }

    func testBuildNumberIsNumeric() throws {
        _ = try appBuildNumber()
    }

    // MARK: - appcast.xml

    func testAppcastEntriesAreCompleteOrderedAndUnique() throws {
        let url = Self.repoRoot.appendingPathComponent("appcast.xml")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("no appcast.xml yet")
        }
        let doc = try XMLDocument(contentsOf: url)
        let channel = try XCTUnwrap(doc.rootElement()?.elements(forName: "channel").first)
        let items = channel.elements(forName: "item")
        XCTAssertFalse(items.isEmpty, "appcast has no releases")

        var builds: [Int] = []
        for item in items {
            let build = try XCTUnwrap(
                item.elements(forLocalName: "version", uri: Self.sparkleNS).first?.stringValue.flatMap(Int.init),
                "an item has no numeric sparkle:version")
            builds.append(build)

            let enclosure = try XCTUnwrap(item.elements(forName: "enclosure").first, "build \(build): no enclosure")
            let download = enclosure.attribute(forName: "url")?.stringValue ?? ""
            XCTAssertTrue(download.hasPrefix("https://github.com/marco-scheffler/FANcy/releases/download/"),
                          "build \(build): unexpected download URL \(download)")
            let signature = enclosure.attribute(forLocalName: "edSignature", uri: Self.sparkleNS)?.stringValue ?? ""
            XCTAssertEqual(Data(base64Encoded: signature)?.count, 64,
                           "build \(build): missing or malformed EdDSA signature")
        }

        XCTAssertEqual(Set(builds).count, builds.count, "duplicate build numbers: \(builds)")
        XCTAssertEqual(builds, builds.sorted(by: >), "items must be newest first: \(builds)")
        XCTAssertGreaterThanOrEqual(try appBuildNumber(), builds.max() ?? 0,
            "the app in the repo is older than the newest published build")
    }
}

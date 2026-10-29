@testable import PackageClaimKit
import Foundation
import XCTest

final class RegistryTests: XCTestCase {
    let pypi = """
    {"info": {"name": "requests", "version": "2.34.2", "yanked": false},
     "releases": {"0.0.1": [], "0.2.0": [{"upload_time_iso_8601": "2011-02-14T03:27:40.848427Z"}],
                  "2.34.2": [{"upload_time_iso_8601": "2026-07-01T10:00:00.000000Z"}, {"size": 1}]}}
    """
    let npm = """
    {"name": "request", "dist-tags": {"latest": "2.88.2"}, "time": {"created": "2011-01-22T00:36:12.640Z"},
     "versions": {"2.88.0": {}, "2.88.2": {"deprecated": "request has been deprecated"}}}
    """
    let crates = """
    {"crate": {"name": "serde", "created_at": "2014-12-05T20:20:39.487502Z", "max_version": "1.0.229"},
     "versions": [{"num": "1.0.229", "yanked": false}, {"num": "1.0.0", "yanked": true}, {"yanked": false}]}
    """

    func testParsesThePyPIDocument() {
        let found = RegistryParser.parse(Data(pypi.utf8), in: .pypi)
        XCTAssertEqual(found?.name, "requests")
        XCTAssertEqual(found?.latestVersion, "2.34.2")
        XCTAssertEqual(found?.versions, ["0.2.0", "2.34.2"])
        XCTAssertEqual(found?.firstPublished, RegistryParser.date("2011-02-14T03:27:40Z"))
        XCTAssertNil(found?.deprecation)
        let yanked = RegistryParser.python(["info": ["name": "x", "yanked": true, "yanked_reason": "broken wheel"]])
        XCTAssertEqual(yanked?.deprecation, "its latest release is yanked: broken wheel")
        XCTAssertEqual(yanked?.versions, [])
        XCTAssertNil(yanked?.firstPublished)
        XCTAssertEqual(RegistryParser.python(["info": ["name": "x", "yanked": true]])?.deprecation,
                       "its latest release is yanked")
        XCTAssertNil(RegistryParser.python(["releases": [:]]))
    }

    func testParsesTheNpmDocument() {
        let found = RegistryParser.parse(Data(npm.utf8), in: .npm)
        XCTAssertEqual(found?.name, "request")
        XCTAssertEqual(found?.deprecation, "request has been deprecated")
        XCTAssertEqual(found?.versions, ["2.88.0", "2.88.2"])
        XCTAssertEqual(found?.firstPublished, RegistryParser.date("2011-01-22T00:36:12Z"))
        let unpublished = RegistryParser.node(["name": "gone", "time": ["unpublished": ["time": "2024-01-01"]]])
        XCTAssertEqual(unpublished?.versions, [])
        XCTAssertNil(unpublished?.latestVersion)
        XCTAssertNil(RegistryParser.node(["versions": [:]]))
    }

    func testParsesTheCratesDocument() {
        let found = RegistryParser.parse(Data(crates.utf8), in: .crates)
        XCTAssertEqual(found?.name, "serde")
        XCTAssertEqual(found?.versions, ["1.0.229"])
        XCTAssertEqual(found?.latestVersion, "1.0.229")
        XCTAssertEqual(found?.firstPublished, RegistryParser.date("2014-12-05T20:20:39Z"))
        XCTAssertEqual(RegistryParser.rust(["crate": ["name": "bare"]])?.versions, [])
        XCTAssertNil(RegistryParser.rust(["versions": []]))
        XCTAssertNil(RegistryParser.parse(Data("[1, 2]".utf8), in: .crates))
        XCTAssertNil(RegistryParser.parse(Data("not json".utf8), in: .pypi))
    }

    func testDates() {
        XCTAssertEqual(RegistryParser.date("2014-12-05T20:20:39.487502Z"), RegistryParser.date("2014-12-05T20:20:39Z"))
        XCTAssertEqual(RegistryParser.date("2011-01-22T00:36:12.640Z")?.timeIntervalSince1970, 1_295_656_572)
        XCTAssertNil(RegistryParser.date("2014-12-05T20:20:39.123"))
        XCTAssertNil(RegistryParser.date("yesterday"))
    }

    func testStaticRegistry() async {
        let registry = StaticRegistry([facts("Python_Dateutil")], offline: [.npm: "no network in tests"])
        let found = await registry.lookup("python-dateutil", in: .pypi)
        XCTAssertEqual(found, .found(facts("Python_Dateutil")))
        let missing = await registry.lookup("nope", in: .pypi)
        XCTAssertEqual(missing, .missing)
        let crate = await registry.lookup("serde", in: .crates)
        XCTAssertEqual(crate, .missing)
        let offline = await registry.lookup("react", in: .npm)
        XCTAssertEqual(offline, .unavailable("no network in tests"))
    }

    func testRequestsForEachRegistry() {
        let registry = PublicRegistry(fetcher: StubFetcher(table: [:]), userAgent: "test-agent", timeout: 3)
        XCTAssertEqual(registry.request(for: "Python_Dateutil", in: .pypi)?.url?.absoluteString,
                       "https://pypi.org/pypi/python-dateutil/json")
        XCTAssertEqual(registry.request(for: "@types/node", in: .npm)?.url?.absoluteString,
                       "https://registry.npmjs.org/@types%2Fnode")
        let crate = registry.request(for: "Serde_JSON", in: .crates)
        XCTAssertEqual(crate?.url?.absoluteString, "https://crates.io/api/v1/crates/serde-json")
        XCTAssertEqual(crate?.value(forHTTPHeaderField: "User-Agent"), "test-agent")
        XCTAssertEqual(crate?.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(crate?.timeoutInterval, 3)
        XCTAssertNil(registry.request(for: "<package>", in: .pypi))
        XCTAssertEqual(PublicRegistry().timeout, 8)
        XCTAssertTrue(PublicRegistry().userAgent.hasPrefix("PackageClaimKit/1.0"))
    }

    func testLookupStatuses() async {
        let fetcher = StubFetcher(table: [
            "https://pypi.org/pypi/requests/json": (200, pypi),
            "https://pypi.org/pypi/garbled/json": (200, "<html>"),
            "https://pypi.org/pypi/reqeusts/json": (404, "{\"message\": \"Not Found\"}"),
            "https://registry.npmjs.org/gone": (410, ""),
            "https://crates.io/api/v1/crates/serde": (503, "")
        ])
        let registry = PublicRegistry(fetcher: fetcher)
        let found = await registry.lookup("requests", in: .pypi)
        XCTAssertEqual(found, RegistryParser.parse(Data(pypi.utf8), in: .pypi).map(RegistryAnswer.found))
        let garbled = await registry.lookup("garbled", in: .pypi)
        XCTAssertEqual(garbled, .unavailable("PyPI sent an answer this kit cannot read"))
        let missing = await registry.lookup("reqeusts", in: .pypi)
        XCTAssertEqual(missing, .missing)
        let gone = await registry.lookup("gone", in: .npm)
        XCTAssertEqual(gone, .missing)
        let busy = await registry.lookup("serde", in: .crates)
        XCTAssertEqual(busy, .unavailable("crates.io answered HTTP 503"))
        let unreachable = await registry.lookup("tokio", in: .crates)
        XCTAssertEqual(unreachable, .unavailable("crates.io could not be reached (offline)"))
        let invalid = await registry.lookup("$PKG", in: .npm)
        XCTAssertEqual(invalid, .unavailable("`$PKG` is not a valid npm name"))
    }

    func testURLSessionFetcherReadsStatus() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CannedProtocol.self]
        let fetcher = URLSessionFetcher(session: URLSession(configuration: configuration))
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://pypi.org/pypi/x/json")))
        CannedProtocol.plainResponse = false
        let http = try await fetcher.fetch(request)
        XCTAssertEqual(http.status, 404)
        XCTAssertEqual(http.data, Data("{}".utf8))
        CannedProtocol.plainResponse = true
        let plain = try await fetcher.fetch(request)
        XCTAssertEqual(plain.status, -1)
        CannedProtocol.plainResponse = false
        _ = URLSessionFetcher()
    }
}

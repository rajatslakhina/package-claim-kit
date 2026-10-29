@testable import PackageClaimKit
import Foundation
import XCTest

func mentions(_ text: String) -> [PackageMention] {
    PackageReader().mentions(in: text)
}

func command(_ text: String) -> [PackageMention] {
    CommandReader.mentions(in: text)
}

func names(_ found: [PackageMention]) -> [String] {
    found.map(\.spelled)
}

func block(_ info: String, _ lines: String...) -> CodeRegion {
    CodeRegion(info: info, lines: lines, isBlock: true)
}

/// Midnight UTC on an ISO date.
func day(_ text: String) -> Date {
    RegistryParser.date(text + "T00:00:00Z") ?? .distantPast
}

let today = day("2026-10-29")

func facts(
    _ name: String,
    _ ecosystem: Ecosystem = .pypi,
    since: String = "2015-01-01",
    versions: Set<String> = ["1.0.0"],
    latest: String? = "1.0.0",
    deprecation: String? = nil
) -> PackageFacts {
    PackageFacts(
        ecosystem: ecosystem, name: name, firstPublished: day(since), latestVersion: latest, versions: versions,
        deprecation: deprecation
    )
}

func mention(_ name: String, _ ecosystem: Ecosystem = .pypi, version: String? = nil,
             index: String? = nil) -> PackageMention {
    PackageMention(
        ecosystem: ecosystem, name: name, version: version, origin: .command("pip install"),
        excerpt: "pip install \(name)", customIndex: index
    )
}

/// A fetcher that answers from a table of URL → (status, body), or throws for URLs it does not know.
struct StubFetcher: HTTPFetching {
    struct Offline: Error, LocalizedError {
        var errorDescription: String? { "offline" }
    }

    let table: [String: (Int, String)]

    func fetch(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        guard let url = request.url?.absoluteString, let (status, body) = table[url] else { throw Offline() }
        return (Data(body.utf8), status)
    }
}

/// A registry that counts how often it is asked, and can be switched off.
actor CountingRegistry: PackageRegistry {
    let base: StaticRegistry
    private(set) var asked: [String] = []
    var down = false

    init(_ packages: [PackageFacts]) {
        base = StaticRegistry(packages)
    }

    func setDown(_ value: Bool) { down = value }

    func lookup(_ name: String, in ecosystem: Ecosystem) async -> RegistryAnswer {
        asked.append("\(ecosystem.rawValue):\(name)")
        return down ? .unavailable("down for maintenance") : await base.lookup(name, in: ecosystem)
    }
}

/// Serves canned responses to a URLSession, so `URLSessionFetcher` runs for real without a network.
final class CannedProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var plainResponse = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url ?? URL(fileURLWithPath: "/")
        let response: URLResponse = Self.plainResponse
            ? URLResponse(url: url, mimeType: "application/json", expectedContentLength: 2, textEncodingName: nil)
            : HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil) ?? URLResponse()
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

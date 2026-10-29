@testable import PackageClaimKit
import XCTest

final class EvaluatorTests: XCTestCase {
    let evaluator = PackageEvaluator()

    func kinds(_ mention: PackageMention, _ answer: RegistryAnswer, elsewhere: [Ecosystem] = []) -> [PackageFinding.Kind] {
        evaluator.evaluate(mention, answer: answer, elsewhere: elsewhere, now: today).kinds
    }

    func testEachKind() {
        XCTAssertEqual(kinds(mention("requests"), .found(facts("requests"))), [.exists])
        XCTAssertEqual(kinds(mention("reqeusts"), .missing), [.notFound(suggestion: "requests", elsewhere: [])])
        XCTAssertEqual(kinds(mention("lodash"), .missing, elsewhere: [.npm]),
                       [.notFound(suggestion: nil, elsewhere: [.npm])])
        XCTAssertEqual(kinds(mention("requests"), .unavailable("down")), [.unchecked("down")])
        XCTAssertEqual(kinds(mention("gone", .npm), .found(facts("gone", .npm, versions: []))), [.noRelease])
        XCTAssertEqual(kinds(mention("requests", version: "3.0.0"), .found(facts("requests", latest: "2.34.2"))),
                       [.versionMissing(requested: "3.0.0", latest: "2.34.2")])
        XCTAssertEqual(kinds(mention("brand-new"), .found(facts("brand-new", since: "2026-10-20"))),
                       [.recentlyPublished(days: 9)])
        XCTAssertEqual(kinds(mention("request", .npm), .found(facts("request", .npm, deprecation: "see #3142"))),
                       [.deprecated("see #3142")])
        XCTAssertEqual(kinds(mention("colourama"), .found(facts("colourama", since: "2026-03-01"))),
                       [.lookalike(of: "colorama")])
        XCTAssertEqual(kinds(mention("preact", .npm), .found(facts("preact-x", .npm, since: "2015-09-01"))), [.exists])
        XCTAssertEqual(kinds(mention("reactt", .npm), .found(facts("reactt", .npm, since: "2026-10-29"))),
                       [.recentlyPublished(days: 0), .lookalike(of: "react")])
        XCTAssertEqual(kinds(mention("clock-skew"), .found(facts("clock-skew", since: "2026-11-02"))),
                       [.recentlyPublished(days: 0)])
        let undated = PackageFacts(ecosystem: .pypi, name: "reqests", firstPublished: nil, latestVersion: nil,
                                   versions: ["1"])
        XCTAssertEqual(kinds(mention("reqests"), .found(undated)), [.exists])
        let custom = evaluator.evaluate(mention("corp", index: "https://pypi.corp"), answer: .missing, now: today)
        XCTAssertEqual(custom.kinds, [.unchecked("the command installs from https://pypi.corp, not from PyPI")])
        XCTAssertNil(custom.facts)
    }

    func testVersionsComparePerEcosystem() {
        XCTAssertTrue(PackageEvaluator.has("2.31", in: facts("requests", versions: ["2.31.0"])))
        XCTAssertTrue(PackageEvaluator.has("V1.0.0", in: facts("x", versions: ["1"])))
        XCTAssertFalse(PackageEvaluator.has("2.31", in: facts("x", .npm, versions: ["2.31.0"])))
        XCTAssertEqual(PackageEvaluator.padded("0"), "0")
        XCTAssertEqual(PackageEvaluator.padded("1.10.0.0"), "1.10")
    }

    func testSeverities() {
        let all: [PackageFinding.Kind] = [
            .exists, .unchecked(""), .recentlyPublished(days: 1), .deprecated(""), .lookalike(of: ""),
            .notFound(suggestion: nil, elsewhere: []), .noRelease, .versionMissing(requested: "", latest: nil)
        ]
        XCTAssertEqual(all.map(\.severity), [.fine, .unchecked, .caution, .caution, .caution, .wrong, .wrong, .wrong])
        XCTAssertEqual(PackageFinding(mention: mention("x"), facts: nil, kinds: []).severity, .fine)
        XCTAssertLessThan(PackageFinding.Severity.caution, .wrong)
        XCTAssertEqual(PackagePolicy(), PackagePolicy(recentDays: 30, lookalikeDays: 365, crossCheck: true))
    }

    func testNearestWellKnownName() {
        let known = WellKnownPackages.default
        XCTAssertEqual(known.nearest(to: "python-requests", in: .pypi), "requests")
        XCTAssertEqual(known.nearest(to: "pyrich", in: .pypi), "rich")
        XCTAssertEqual(known.nearest(to: "lodash.js", in: .npm), "lodash")
        XCTAssertEqual(known.nearest(to: "beautiful-soup4", in: .pypi), "beautifulsoup4")
        XCTAssertEqual(known.nearest(to: "reqeusts", in: .pypi), "requests")
        XCTAssertEqual(known.nearest(to: "numpi", in: .pypi), "numpy")
        XCTAssertEqual(known.nearest(to: "Serde-JSON", in: .crates), "serde_json")
        XCTAssertNil(known.nearest(to: "requests", in: .pypi))
        XCTAssertNil(known.nearest(to: "zzzzzzzz", in: .pypi))
        XCTAssertNil(known.nearest(to: "numpyy-extras", in: .pypi))
        XCTAssertNil(WellKnownPackages([.pypi: ["requests"]]).nearest(to: "reqeusts", in: .npm))
        XCTAssertTrue(known.contains("PyYAML", in: .pypi))
        XCTAssertFalse(known.contains("serde", in: .npm))
        XCTAssertNil(WellKnownPackages.strip(("python-", ""), from: "python-x"))
    }

    func testNameDistance() {
        XCTAssertEqual(NameDistance.between("reqeusts", "requests", limit: 2), 1)
        XCTAssertEqual(NameDistance.between("kitten", "sitting", limit: 3), 3)
        XCTAssertEqual(NameDistance.between("", "ab", limit: 2), 2)
        XCTAssertEqual(NameDistance.between("abc", "abcdef", limit: 2), 3)
        XCTAssertEqual(NameDistance.between("abcdef", "uvwxyz", limit: 1), 2)
        XCTAssertEqual(NameDistance.between("ab", "ba", limit: 1), 1)
    }
}

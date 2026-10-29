@testable import PackageClaimKit
import XCTest

final class VetterTests: XCTestCase {
    let registry = [
        facts("requests", since: "2011-02-14", versions: ["2.34.2"], latest: "2.34.2"),
        facts("lodash", .npm, since: "2012-04-23", versions: ["4.18.1"], latest: "4.18.1"),
        facts("serde", .crates, since: "2014-12-05", versions: ["1.0.229"], latest: "1.0.229")
    ]

    func testReviewsLooksUpOnceAndCrossChecks() async {
        let counting = CountingRegistry(registry)
        let vetter = PackageVetter(registry: counting)
        let answer = """
        ```bash
        pip install requests==2.34.2 reqeusts lodash
        pip install Requests==2.34.2
        pip install corp-tools --index-url https://pypi.corp
        ```
        """
        let report = await vetter.review(answer, now: today)
        XCTAssertEqual(report.findings.map(\.mention.spelled), ["requests==2.34.2", "reqeusts", "lodash", "corp-tools"])
        XCTAssertEqual(report.findings.map(\.kinds), [
            [.exists],
            [.notFound(suggestion: "requests", elsewhere: [])],
            [.notFound(suggestion: nil, elsewhere: [.npm])],
            [.unchecked("the command installs from https://pypi.corp, not from PyPI")]
        ])
        XCTAssertEqual(report.verdict, .wrong)
        let asked = await counting.asked
        XCTAssertEqual(Set(asked), ["pypi:requests", "pypi:reqeusts", "pypi:lodash", "npm:reqeusts",
                                    "crates:reqeusts", "npm:lodash", "crates:lodash"])
        let lookups = await vetter.lookups
        XCTAssertEqual(lookups, 7)

        let again = await vetter.review("Then `npm i lodash` and `pip install requests`.", now: today)
        XCTAssertEqual(again.verdict, .verified)
        let hits = await vetter.cacheHits
        let reviews = await vetter.reviews
        XCTAssertEqual(hits, 2)
        XCTAssertEqual(reviews, 2)
    }

    func testUnavailableAnswersAreAskedAgain() async {
        let counting = CountingRegistry(registry)
        await counting.setDown(true)
        let vetter = PackageVetter(registry: counting, policy: PackagePolicy(crossCheck: false))
        let down = await vetter.review("`cargo add serde`", now: today)
        XCTAssertEqual(down.verdict, .unchecked)
        await counting.setDown(false)
        let up = await vetter.review("`cargo add serde`", now: today)
        XCTAssertEqual(up.verdict, .verified)
        let asked = await counting.asked
        XCTAssertEqual(asked, ["crates:serde", "crates:serde"])
    }

    func testNoCrossCheckWhenTurnedOff() async {
        let counting = CountingRegistry(registry)
        let vetter = PackageVetter(registry: counting, policy: PackagePolicy(crossCheck: false))
        let report = await vetter.review("`pip install lodash`", now: today)
        XCTAssertEqual(report.findings.first?.kinds, [.notFound(suggestion: nil, elsewhere: [])])
        let quiet = await vetter.review("No commands here, only prose: pip install it.")
        XCTAssertEqual(quiet.verdict, .noPackages)
    }
}

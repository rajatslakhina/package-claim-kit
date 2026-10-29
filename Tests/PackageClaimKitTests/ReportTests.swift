@testable import PackageClaimKit
import XCTest

final class ReportTests: XCTestCase {
    func finding(_ mention: PackageMention, _ kinds: PackageFinding.Kind...) -> PackageFinding {
        PackageFinding(mention: mention, facts: nil, kinds: kinds)
    }

    func testVerdicts() {
        XCTAssertEqual(PackageReport(findings: []).verdict, .noPackages)
        XCTAssertEqual(PackageReport(findings: [finding(mention("a"), .exists)]).verdict, .verified)
        XCTAssertEqual(PackageReport(findings: [finding(mention("a"), .exists), finding(mention("b"), .unchecked("x"))])
            .verdict, .unchecked)
        XCTAssertEqual(PackageReport(findings: [finding(mention("a"), .recentlyPublished(days: 2))]).verdict, .caution)
        XCTAssertEqual(PackageReport(findings: [finding(mention("a"), .noRelease)]).verdict, .wrong)
    }

    func testNoteFeedbackAndSummaryForAWrongName() {
        let report = PackageReport(findings: [
            finding(mention("rich"), .exists),
            finding(mention("fresh"), .recentlyPublished(days: 1)),
            finding(mention("reqeusts"), .notFound(suggestion: "requests", elsewhere: [])),
            finding(mention("lodash"), .notFound(suggestion: nil, elsewhere: [.npm, .crates]))
        ])
        XCTAssertEqual(report.flagged.map(\.mention.name), ["reqeusts", "lodash", "fresh"])
        XCTAssertEqual(report.count(.wrong), 2)
        XCTAssertEqual(report.note, """
        `reqeusts` (`pip install`): no package by that name on PyPI; did you mean `requests`? \
        `lodash` (`pip install`): no package by that name on PyPI; it is a package on npm and crates.io, \
        so the command uses the wrong tool. `fresh` (`pip install`): was first published yesterday. \
        A name that does not exist fails to install today, and anyone can register it tomorrow (slopsquatting): \
        check names before running the commands. Look at who published a new or look-alike package before \
        installing it.
        """)
        XCTAssertEqual(report.feedback, """
        These packages in your answer need fixing: `reqeusts` (`pip install`): no \
        package by that name on PyPI; did you mean `requests`? `lodash` (`pip install`): no package by \
        that name on PyPI; it is a package on npm and crates.io, so the command uses the wrong tool. Rewrite the \
        install commands and manifests with packages and versions that exist on their registry, or say plainly \
        that you are not sure of a name. Do not invent package names.
        """)
        XCTAssertEqual(report.summary, "4 packages: 2 wrong (reqeusts, lodash), 1 caution (fresh), 1 verified")
    }

    func testCautionDeprecationAndQuietReports() {
        let caution = PackageReport(findings: [
            finding(mention("colourama"), .lookalike(of: "colorama"), .recentlyPublished(days: 12))
        ])
        XCTAssertEqual(caution.note, "`colourama` (`pip install`): is a near-spelling of the well-known "
            + "`colorama`; was first published 12 days ago. Look at who published a new or look-alike package "
            + "before installing it.")
        XCTAssertNil(caution.feedback)
        let deprecated = PackageReport(findings: [finding(mention("request", .npm), .deprecated("see #3142"))])
        XCTAssertEqual(deprecated.feedback?.hasPrefix("These packages in your answer need fixing: "
            + "`request` (`pip install`): is deprecated: see #3142. Rewrite"), true)
        let quiet = PackageReport(findings: [finding(mention("rich"), .exists), finding(mention("x"), .unchecked("down"))])
        XCTAssertNil(quiet.note)
        XCTAssertNil(quiet.feedback)
        XCTAssertEqual(quiet.summary, "2 packages: 1 not checked (x), 1 verified")
        XCTAssertEqual(PackageReport(findings: []).summary, "packages: no install commands or manifests in the answer")
        XCTAssertEqual(PackageReport(findings: [finding(mention("rich"), .exists)]).summary, "1 package: 1 verified")
    }

    func testAdviceFollowsTheConcerns() {
        let report = PackageReport(findings: [
            finding(mention("lodash", .npm), .versionMissing(requested: "5.0.0", latest: "4.18.1"), .deprecated("old"),
                    .exists, .unchecked("x"))
        ])
        XCTAssertEqual(report.note, "`lodash` (`pip install`): npm has no version 5.0.0 (the latest is 4.18.1); is "
            + "deprecated: old; is on npm; was not checked: x. Pin a version the registry lists, or leave the "
            + "version out. Prefer a maintained replacement for a deprecated package.")
    }

    func testEveryClause() {
        let pinned = PackageMention(ecosystem: .npm, name: "lodash", version: "5.0.0", origin: .manifest("package.json"),
                                    excerpt: "\"lodash\": \"5.0.0\"")
        let sentence = finding(pinned, .exists, .noRelease, .versionMissing(requested: "5.0.0", latest: nil),
                               .versionMissing(requested: "5.0.0", latest: "4.18.1"), .recentlyPublished(days: 0),
                               .unchecked("npm answered HTTP 500")).sentence
        XCTAssertEqual(sentence, "`lodash@5.0.0` (in package.json): is on npm; is registered on npm but has no "
            + "release that can be installed; npm has no version 5.0.0; npm has no version 5.0.0 (the latest is "
            + "4.18.1); was first published today; was not checked: npm answered HTTP 500")
    }
}

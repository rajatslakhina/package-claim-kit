import Foundation
import PackageClaimKit

/// The demo's clock: every "first published N days ago" is measured from here.
let demoNow = date("2026-10-29")

func date(_ day: String) -> Date {
    (try? Date(day + "T00:00:00Z", strategy: .iso8601)) ?? .distantPast
}

/// A fixed registry snapshot. Names, first-publish dates and latest versions of the real packages are
/// what PyPI, npm and crates.io returned on 2026-10-29; `fastapi-jwt-shield` is made up for the demo.
let snapshot: [PackageFacts] = [
    PackageFacts(ecosystem: .pypi, name: "requests", firstPublished: date("2011-02-14"), latestVersion: "2.34.2",
                 versions: ["2.31.0", "2.32.3", "2.34.2"]),
    PackageFacts(ecosystem: .pypi, name: "ruff", firstPublished: date("2022-08-29"), latestVersion: "0.14.2",
                 versions: ["0.14.2"]),
    PackageFacts(ecosystem: .pypi, name: "fastapi", firstPublished: date("2018-12-08"), latestVersion: "0.120.1",
                 versions: ["0.120.1"]),
    PackageFacts(ecosystem: .pypi, name: "pyjwt", firstPublished: date("2011-10-12"), latestVersion: "2.10.1",
                 versions: ["2.10.1"]),
    PackageFacts(ecosystem: .pypi, name: "fastapi-jwt-shield", firstPublished: date("2026-10-23"),
                 latestVersion: "0.0.1", versions: ["0.0.1"]),
    PackageFacts(ecosystem: .npm, name: "lodash", firstPublished: date("2012-04-23"), latestVersion: "4.18.1",
                 versions: ["4.17.21", "4.18.1"]),
    PackageFacts(ecosystem: .npm, name: "request", firstPublished: date("2011-01-22"), latestVersion: "2.88.2",
                 versions: ["2.88.2"],
                 deprecation: "request has been deprecated, see https://github.com/request/request/issues/3142"),
    PackageFacts(ecosystem: .npm, name: "axios", firstPublished: date("2014-08-29"), latestVersion: "1.13.1",
                 versions: ["1.13.1"]),
    PackageFacts(ecosystem: .npm, name: "create-vite", firstPublished: date("2021-01-26"), latestVersion: "8.0.2",
                 versions: ["8.0.2"]),
    PackageFacts(ecosystem: .crates, name: "serde", firstPublished: date("2014-12-05"), latestVersion: "1.0.229",
                 versions: ["1.0.229"]),
    PackageFacts(ecosystem: .crates, name: "tokio", firstPublished: date("2016-07-01"), latestVersion: "1.48.0",
                 versions: ["1.48.0"])
]

func show(_ title: String, question: String, answer: String, report: PackageReport) {
    print("== \(title)")
    print("Q: \(question)")
    for line in answer.split(separator: "\n", omittingEmptySubsequences: false) {
        print("   | \(line)")
    }
    print("verdict: \(report.verdict.rawValue) — \(report.summary)")
    for finding in report.findings {
        let marks = finding.kinds.map(label).joined(separator: ", ")
        print("   \(finding.mention.ecosystem.registryName.padding(toLength: 9, withPad: " ", startingAt: 0)) "
            + "\(finding.mention.spelled.padding(toLength: 22, withPad: " ", startingAt: 0)) \(marks)")
    }
    if let note = report.note { print("note: \(note)") }
    if let feedback = report.feedback { print("feedback: \(feedback)") }
    print("")
}

/// A short label for each kind, for the demo's table.
func label(_ kind: PackageFinding.Kind) -> String {
    switch kind {
    case .exists: "exists"
    case let .notFound(suggestion, elsewhere):
        "NOT FOUND" + (suggestion.map { " (near \($0))" } ?? "")
            + (elsewhere.isEmpty ? "" : " (on " + elsewhere.map(\.registryName).joined(separator: ", ") + ")")
    case .noRelease: "no installable release"
    case let .versionMissing(requested, latest): "NO VERSION \(requested) (latest \(latest ?? "?"))"
    case .recentlyPublished(let days): "first published \(days) days ago"
    case .deprecated: "deprecated"
    case .lookalike(let name): "near-spelling of \(name)"
    case .unchecked(let reason): "not checked: \(reason)"
    }
}

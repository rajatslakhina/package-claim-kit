/// Every package an answer names, and what the registries said about each.
public struct PackageReport: Sendable, Equatable {
    public enum Verdict: String, Sendable {
        /// The answer has no install command or manifest in its code.
        case noPackages
        /// Every package exists, with its pinned version, and none is new, deprecated or a near-spelling.
        case verified
        /// Nothing is wrong, but at least one package could not be checked.
        case unchecked
        /// Every package exists, but at least one is new, deprecated or a near-spelling.
        case caution
        /// At least one package or pinned version does not exist.
        case wrong
    }

    public let findings: [PackageFinding]

    public init(findings: [PackageFinding]) {
        self.findings = findings
    }

    public var verdict: Verdict {
        switch findings.map(\.severity).max() {
        case nil: .noPackages
        case .fine: .verified
        case .unchecked: .unchecked
        case .caution: .caution
        case .wrong: .wrong
        }
    }

    /// The findings worth telling someone about: wrong or caution, worst first.
    public var flagged: [PackageFinding] {
        findings.filter { $0.severity >= .caution }.sorted { $0.severity > $1.severity }
    }

    public func count(_ severity: PackageFinding.Severity) -> Int {
        findings.filter { $0.severity == severity }.count
    }
}

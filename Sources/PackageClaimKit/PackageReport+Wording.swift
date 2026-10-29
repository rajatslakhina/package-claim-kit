extension PackageFinding.Kind {
    /// One clause about the package, for a note: "no package by that name on PyPI; did you mean `requests`?".
    func clause(for mention: PackageMention) -> String {
        let registry = mention.ecosystem.registryName
        switch self {
        case .exists:
            return "is on \(registry)"
        case let .notFound(suggestion, elsewhere):
            let other = elsewhere.map(\.registryName).joined(separator: " and ")
            let wrongTool = elsewhere.isEmpty ? "" : "; it is a package on \(other), so the command uses the wrong tool"
            let guess = suggestion.map { "; did you mean `\($0)`?" } ?? ""
            return "no package by that name on \(registry)" + wrongTool + guess
        case .noRelease:
            return "is registered on \(registry) but has no release that can be installed"
        case let .versionMissing(requested, latest):
            return "\(registry) has no version \(requested)" + (latest.map { " (the latest is \($0))" } ?? "")
        case .recentlyPublished(let days):
            return "was first published " + Self.ago(days)
        case .deprecated(let message):
            return "is deprecated: \(message)"
        case .lookalike(let name):
            return "is a near-spelling of the well-known `\(name)`"
        case .unchecked(let reason):
            return "was not checked: \(reason)"
        }
    }

    static func ago(_ days: Int) -> String {
        switch days {
        case 0: "today"
        case 1: "yesterday"
        default: "\(days) days ago"
        }
    }
}

extension PackageFinding {
    /// "`reqeusts` (`pip install reqeusts`): no package by that name on PyPI; did you mean `requests`?"
    public var sentence: String {
        "`\(mention.spelled)` (\(mention.source)): " + kinds.map { $0.clause(for: mention) }.joined(separator: "; ")
    }

    /// `sentence` with a full stop, unless it already ends in a question mark.
    var terminated: String {
        sentence.hasSuffix("?") ? sentence : sentence + "."
    }

    /// What a reader should do about the kinds this finding has, one advice per concern.
    var advice: Set<Advice> {
        Set(kinds.compactMap { kind in
            switch kind {
            case .notFound: .checkName
            case .noRelease, .versionMissing: .pickVersion
            case .recentlyPublished, .lookalike: .checkPublisher
            case .deprecated: .replace
            case .exists, .unchecked: nil
            }
        })
    }
}

enum Advice: Int, CaseIterable, Sendable {
    case checkName
    case pickVersion
    case replace
    case checkPublisher

    var text: String {
        switch self {
        case .checkName:
            "A name that does not exist fails to install today, and anyone can register it tomorrow "
                + "(slopsquatting): check names before running the commands."
        case .pickVersion: "Pin a version the registry lists, or leave the version out."
        case .replace: "Prefer a maintained replacement for a deprecated package."
        case .checkPublisher: "Look at who published a new or look-alike package before installing it."
        }
    }
}

extension PackageReport {
    /// A paragraph for the person reading the answer, when something is wrong or worth a look; nil otherwise.
    public var note: String? {
        let flagged = flagged
        guard !flagged.isEmpty else { return nil }
        let wanted = flagged.reduce(into: Set<Advice>()) { $0.formUnion($1.advice) }
        let advice = Advice.allCases.filter(wanted.contains).map(\.text)
        return (flagged.map(\.terminated) + advice).joined(separator: " ")
    }

    /// A re-prompt for the model, when a package or version does not exist or is deprecated; nil otherwise.
    public var feedback: String? {
        let fixable = findings.filter { finding in
            finding.severity == .wrong || finding.kinds.contains { if case .deprecated = $0 { true } else { false } }
        }
        guard !fixable.isEmpty else { return nil }
        return "These packages in your answer need fixing: "
            + fixable.map(\.terminated).joined(separator: " ")
            + " Rewrite the install commands and manifests with packages and versions that exist on their "
            + "registry, or say plainly that you are not sure of a name. Do not invent package names."
    }

    /// One line for a trace or a log.
    public var summary: String {
        guard !findings.isEmpty else { return "packages: no install commands or manifests in the answer" }
        let parts: [(PackageFinding.Severity, String)] = [
            (.wrong, "wrong"), (.caution, "caution"), (.unchecked, "not checked"), (.fine, "verified")
        ]
        let counts = parts.compactMap { severity, label -> String? in
            let names = findings.filter { $0.severity == severity }.map(\.mention.spelled)
            guard !names.isEmpty else { return nil }
            let listed = severity == .fine ? "" : " (" + names.joined(separator: ", ") + ")"
            return "\(names.count) \(label)" + listed
        }
        let noun = findings.count == 1 ? "package" : "packages"
        return "\(findings.count) \(noun): " + counts.joined(separator: ", ")
    }
}

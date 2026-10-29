import Foundation

/// Turns a mention and the registry's answer into a finding. Pure: no I/O, no clock of its own.
public struct PackageEvaluator: Sendable {
    public let policy: PackagePolicy
    public let wellKnown: WellKnownPackages

    public init(policy: PackagePolicy = PackagePolicy(), wellKnown: WellKnownPackages = .default) {
        self.policy = policy
        self.wellKnown = wellKnown
    }

    /// `elsewhere`: the other registries that have the name, for a name this one does not.
    public func evaluate(
        _ mention: PackageMention,
        answer: RegistryAnswer,
        elsewhere: [Ecosystem] = [],
        now: Date
    ) -> PackageFinding {
        if let index = mention.customIndex {
            let reason = "the command installs from \(index), not from \(mention.ecosystem.registryName)"
            return PackageFinding(mention: mention, facts: nil, kinds: [.unchecked(reason)])
        }
        switch answer {
        case .unavailable(let reason):
            return PackageFinding(mention: mention, facts: nil, kinds: [.unchecked(reason)])
        case .missing:
            let suggestion = wellKnown.nearest(to: mention.name, in: mention.ecosystem)
            return PackageFinding(
                mention: mention, facts: nil, kinds: [.notFound(suggestion: suggestion, elsewhere: elsewhere)]
            )
        case .found(let facts):
            return PackageFinding(mention: mention, facts: facts, kinds: kinds(mention, facts: facts, now: now))
        }
    }

    func kinds(_ mention: PackageMention, facts: PackageFacts, now: Date) -> [PackageFinding.Kind] {
        guard !facts.versions.isEmpty else { return [.noRelease] }
        let age = facts.firstPublished.map { max(0, Int(now.timeIntervalSince($0) / 86_400)) }
        var kinds: [PackageFinding.Kind] = []
        if let pin = mention.version, !Self.has(pin, in: facts) {
            kinds.append(.versionMissing(requested: pin, latest: facts.latestVersion))
        }
        if let age, age < policy.recentDays {
            kinds.append(.recentlyPublished(days: age))
        }
        if let message = facts.deprecation {
            kinds.append(.deprecated(message))
        }
        if let age, age < policy.lookalikeDays, let near = wellKnown.nearest(to: mention.name, in: mention.ecosystem) {
            kinds.append(.lookalike(of: near))
        }
        return kinds.isEmpty ? [.exists] : kinds
    }

    /// Whether the registry has the pinned version. PyPI versions compare under PEP 440's padding rule
    /// (`2.31` is `2.31.0`); npm and crates.io versions are exact strings.
    static func has(_ pin: String, in facts: PackageFacts) -> Bool {
        guard facts.ecosystem == .pypi else { return facts.versions.contains(pin) }
        let wanted = padded(pin)
        return facts.versions.contains { padded($0) == wanted }
    }

    static func padded(_ version: String) -> String {
        var parts = version.lowercased().drop { $0 == "v" }.split(separator: ".").map(String.init)
        while parts.count > 1, parts.last == "0" { parts.removeLast() }
        return parts.joined(separator: ".")
    }
}

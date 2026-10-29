import Foundation

/// Checks the packages in answers against a registry, for one conversation.
///
/// Lookups run concurrently and are remembered: a name asked about twice in a conversation is fetched
/// once. An `.unavailable` answer is not remembered, so a registry that was down is asked again next time.
public actor PackageVetter {
    struct Query: Sendable, Hashable {
        let ecosystem: Ecosystem
        let key: String
    }

    private let registry: any PackageRegistry
    private let reader = PackageReader()
    private let evaluator: PackageEvaluator
    private var cache: [Query: RegistryAnswer] = [:]
    /// Requests actually sent to the registry.
    public private(set) var lookups = 0
    /// Names answered from what this vetter already knew.
    public private(set) var cacheHits = 0
    public private(set) var reviews = 0

    public init(
        registry: any PackageRegistry,
        policy: PackagePolicy = PackagePolicy(),
        wellKnown: WellKnownPackages = .default
    ) {
        self.registry = registry
        self.evaluator = PackageEvaluator(policy: policy, wellKnown: wellKnown)
    }

    /// Every package `answer` names, checked. `now` is when "first published 3 days ago" is measured from.
    public func review(_ answer: String, now: Date = Date()) async -> PackageReport {
        reviews += 1
        var seen = Set<PackageMention>()
        let mentions = reader.mentions(in: answer).filter { mention in
            seen.insert(PackageMention(
                ecosystem: mention.ecosystem, name: mention.key, version: mention.version,
                origin: .command(""), excerpt: ""
            )).inserted
        }
        let checkable = mentions.filter { $0.customIndex == nil }
        let primary = await answers(for: checkable.map { Query(ecosystem: $0.ecosystem, key: $0.key) })
        let elsewhere = await crossCheck(checkable, primary: primary)
        let findings = mentions.map { mention in
            let query = Query(ecosystem: mention.ecosystem, key: mention.key)
            return evaluator.evaluate(
                mention, answer: primary[query] ?? .missing, elsewhere: elsewhere[query] ?? [], now: now
            )
        }
        return PackageReport(findings: findings)
    }

    /// For names their own registry does not have: the other registries that do.
    func crossCheck(_ mentions: [PackageMention], primary: [Query: RegistryAnswer]) async -> [Query: [Ecosystem]] {
        guard evaluator.policy.crossCheck else { return [:] }
        let missing = mentions.filter { primary[Query(ecosystem: $0.ecosystem, key: $0.key)] == .missing }
        let others = missing.flatMap { mention in
            Ecosystem.allCases.filter { $0 != mention.ecosystem && $0.accepts(mention.name) }.map {
                (home: Query(ecosystem: mention.ecosystem, key: mention.key),
                 other: Query(ecosystem: $0, key: $0.normalize(mention.name)))
            }
        }
        let found = await answers(for: others.map(\.other))
        var result: [Query: [Ecosystem]] = [:]
        for pair in others {
            if case .found = found[pair.other] {
                result[pair.home, default: []].append(pair.other.ecosystem)
            }
        }
        return result
    }

    /// The registry's answer for each query: remembered ones first, the rest fetched concurrently.
    func answers(for queries: [Query]) async -> [Query: RegistryAnswer] {
        var result: [Query: RegistryAnswer] = [:]
        var pending = Set<Query>()
        for query in queries {
            if let known = cache[query] {
                result[query] = known
                cacheHits += 1
            } else {
                pending.insert(query)
            }
        }
        let registry = registry
        let fetched = await withTaskGroup(of: (Query, RegistryAnswer).self) { group in
            for query in pending {
                group.addTask { (query, await registry.lookup(query.key, in: query.ecosystem)) }
            }
            var collected: [(Query, RegistryAnswer)] = []
            for await pair in group { collected.append(pair) }
            return collected
        }
        lookups += pending.count
        for (query, answer) in fetched {
            result[query] = answer
            if case .unavailable = answer { continue }
            cache[query] = answer
        }
        return result
    }
}

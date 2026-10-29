/// What the registry check found for one mention.
public struct PackageFinding: Sendable, Hashable {
    public enum Severity: Int, Sendable, Comparable {
        case fine
        case unchecked
        case caution
        case wrong

        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public enum Kind: Sendable, Hashable {
        /// On the registry, with the pinned version if one was pinned, and nothing else to say.
        case exists
        /// The registry has no package by this name. `elsewhere` lists the other registries that do,
        /// which means the command is for the wrong installer.
        case notFound(suggestion: String?, elsewhere: [Ecosystem])
        /// Registered, but nothing can be installed: unpublished, emptied or every version yanked.
        case noRelease
        /// The package exists; the pinned version does not.
        case versionMissing(requested: String, latest: String?)
        /// First published fewer than `PackagePolicy.recentDays` days ago.
        case recentlyPublished(days: Int)
        case deprecated(String)
        /// A near-spelling of a well-known package, first published within `PackagePolicy.lookalikeDays`.
        case lookalike(of: String)
        /// Nothing is known: the registry could not be asked, or the command names its own index.
        case unchecked(String)

        public var severity: Severity {
            switch self {
            case .exists: .fine
            case .unchecked: .unchecked
            case .recentlyPublished, .deprecated, .lookalike: .caution
            case .notFound, .noRelease, .versionMissing: .wrong
            }
        }
    }

    public let mention: PackageMention
    /// What the registry said, when it found the package.
    public let facts: PackageFacts?
    public let kinds: [Kind]

    public init(mention: PackageMention, facts: PackageFacts?, kinds: [Kind]) {
        self.mention = mention
        self.facts = facts
        self.kinds = kinds
    }

    public var severity: Severity { kinds.map(\.severity).max() ?? .fine }
}

/// The thresholds a finding is judged against.
public struct PackagePolicy: Sendable, Hashable {
    /// A package first published fewer days ago than this is reported, whatever its name. Default 30.
    public var recentDays: Int
    /// A near-spelling of a well-known package is reported when it was first published fewer days ago
    /// than this. Old near-spellings (`preact` next to `react`) are packages in their own right. Default 365.
    public var lookalikeDays: Int
    /// Whether a name missing from its registry is looked up on the others, to catch `pip install lodash`.
    public var crossCheck: Bool

    public init(recentDays: Int = 30, lookalikeDays: Int = 365, crossCheck: Bool = true) {
        self.recentDays = recentDays
        self.lookalikeDays = lookalikeDays
        self.crossCheck = crossCheck
    }
}

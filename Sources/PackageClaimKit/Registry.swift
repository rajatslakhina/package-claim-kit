import Foundation

/// What a registry knows about one package.
public struct PackageFacts: Sendable, Hashable {
    public let ecosystem: Ecosystem
    /// The name as the registry spells it.
    public let name: String
    /// When the first file of the first release was uploaded, if the registry says.
    public let firstPublished: Date?
    public let latestVersion: String?
    /// Versions that can still be installed: PyPI releases with files, npm versions, crates.io
    /// versions that are not yanked. Empty for an unpublished or emptied package.
    public let versions: Set<String>
    /// The registry's deprecation message for the latest version, when it has one.
    public let deprecation: String?

    public init(
        ecosystem: Ecosystem,
        name: String,
        firstPublished: Date?,
        latestVersion: String?,
        versions: Set<String>,
        deprecation: String? = nil
    ) {
        self.ecosystem = ecosystem
        self.name = name
        self.firstPublished = firstPublished
        self.latestVersion = latestVersion
        self.versions = versions
        self.deprecation = deprecation
    }
}

/// A registry's answer for one name.
public enum RegistryAnswer: Sendable, Hashable {
    case found(PackageFacts)
    /// The registry has no package by that name.
    case missing
    /// The registry could not be asked or its answer could not be read; nothing is known.
    case unavailable(String)
}

/// Looks packages up. `PublicRegistry` asks PyPI, npm and crates.io over HTTPS; `StaticRegistry` answers
/// from a list, for tests, demos and offline use.
public protocol PackageRegistry: Sendable {
    func lookup(_ name: String, in ecosystem: Ecosystem) async -> RegistryAnswer
}

/// A registry that answers from the packages it was given.
public struct StaticRegistry: PackageRegistry {
    private let packages: [Ecosystem: [String: PackageFacts]]
    private let offline: [Ecosystem: String]

    /// `offline` makes the listed ecosystems answer `.unavailable` with the given reason.
    public init(_ packages: [PackageFacts], offline: [Ecosystem: String] = [:]) {
        var table: [Ecosystem: [String: PackageFacts]] = [:]
        for facts in packages {
            table[facts.ecosystem, default: [:]][facts.ecosystem.normalize(facts.name)] = facts
        }
        self.packages = table
        self.offline = offline
    }

    public func lookup(_ name: String, in ecosystem: Ecosystem) async -> RegistryAnswer {
        if let reason = offline[ecosystem] {
            return .unavailable(reason)
        }
        return packages[ecosystem]?[ecosystem.normalize(name)].map(RegistryAnswer.found) ?? .missing
    }
}

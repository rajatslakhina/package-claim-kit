import Foundation

/// A public package registry that install commands and manifests name packages in.
public enum Ecosystem: String, Sendable, Hashable, CaseIterable, Codable {
    case pypi
    case npm
    case crates

    /// How the registry calls itself, for notes a person reads.
    public var registryName: String {
        switch self {
        case .pypi: "PyPI"
        case .npm: "npm"
        case .crates: "crates.io"
        }
    }

    /// The key two spellings of one package share on this registry.
    ///
    /// PyPI folds case and treats runs of `-`, `_` and `.` as one `-` (PEP 503). crates.io folds case and
    /// treats `-` and `_` alike. npm names are kept as written: the registry is case-sensitive and old
    /// mixed-case names still exist.
    public func normalize(_ name: String) -> String {
        switch self {
        case .pypi:
            var out = ""
            for char in name.lowercased() {
                guard "-_.".contains(char) else {
                    out.append(char)
                    continue
                }
                if out.last != "-" { out.append("-") }
            }
            return out
        case .npm:
            return name
        case .crates:
            return name.lowercased().replacingOccurrences(of: "_", with: "-")
        }
    }

    /// Whether `name` could be a package on this registry at all.
    ///
    /// Placeholders such as `<package>`, `$PKG`, `{name}` or `...` are not, and are never looked up.
    public func accepts(_ name: String) -> Bool {
        guard let first = name.first, let last = name.last, name.count <= 214 else { return false }
        switch self {
        case .pypi:
            return first.isASCIIAlphanumeric && last.isASCIIAlphanumeric
                && name.allSatisfy { $0.isASCIIAlphanumeric || "._-".contains($0) }
        case .npm:
            return Self.npmParts(name).map { parts in
                parts.allSatisfy { part in
                    !part.isEmpty && part.first != "." && part.first != "_"
                        && part.allSatisfy { $0.isASCIIAlphanumeric || "._-~".contains($0) }
                }
            } ?? false
        case .crates:
            return first.isASCIILetter && name.count <= 64
                && name.allSatisfy { $0.isASCIIAlphanumeric || "_-".contains($0) }
        }
    }

    /// `@scope/name` as `[scope, name]`, `name` as `[name]`; nil for anything else with a slash.
    static func npmParts(_ name: String) -> [Substring]? {
        guard name.hasPrefix("@") else {
            return name.contains("/") ? nil : [Substring(name)]
        }
        let parts = name.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 ? parts : nil
    }
}

extension Character {
    var isASCIILetter: Bool { isASCII && isLetter }
    var isASCIIAlphanumeric: Bool { isASCII && (isLetter || isNumber) }
}

import Foundation

/// Reads one package specifier (`requests[socks]==2.31.0`, `@types/node@20.11.5`, `serde@1.0.229`) into a
/// name and an exact version. Paths, URLs, archives and git references are not registry packages and
/// read as nil.
enum SpecParser {
    struct Spec: Sendable, Equatable {
        let name: String
        /// Set only for an exact pin.
        let version: String?
    }

    /// Words answers put where a real name goes.
    static let placeholders: Set<String> = [
        "package", "package-name", "package_name", "packagename", "pkg", "your-package",
        "your-package-name", "my-package", "some-package", "example-package", "foo", "bar", "baz"
    ]

    static func parse(_ raw: String, in ecosystem: Ecosystem) -> Spec? {
        let text = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
        let spec: Spec? = switch ecosystem {
        case .pypi: python(text)
        case .npm: node(text)
        case .crates: rust(text)
        }
        guard let spec, ecosystem.accepts(spec.name), spec.name.contains(where: \.isLetter),
              !placeholders.contains(spec.name.lowercased()) else {
            return nil
        }
        return spec
    }

    /// PEP 508, the part an install command uses: `name[extras]` and an optional `==` or `===` pin.
    static func python(_ text: String) -> Spec? {
        let local = ["://", "/", "\\", "@"].contains { text.contains($0) }
            || [".whl", ".zip", ".tar.gz", ".tgz"].contains { text.hasSuffix($0) }
        guard !local, !text.hasPrefix(".") else { return nil }
        let name = String(text.prefix { $0.isASCIIAlphanumeric || "._-".contains($0) })
        var rest = text.dropFirst(name.count)
        if rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
            rest = rest[rest.index(after: close)...]
        }
        let requirement = rest.prefix { $0 != ";" }.trimmingCharacters(in: .whitespaces)
        let pin = requirement.hasPrefix("===") ? requirement.dropFirst(3)
            : requirement.hasPrefix("==") ? requirement.dropFirst(2) : ""
        let version = pin.trimmingCharacters(in: .whitespaces)
        let exact = !version.isEmpty && !version.contains { "*,<>!~ ".contains($0) }
        return Spec(name: name, version: exact ? version : nil)
    }

    /// `name`, `name@version`, `@scope/name@tag`, and `alias@npm:real@version` (read as `real`).
    static func node(_ text: String) -> Spec? {
        let foreign = [
            "git+", "github:", "gitlab:", "bitbucket:", "file:", "link:", "workspace:", "http", ".", "/", "~"
        ]
        guard !foreign.contains(where: { text.hasPrefix($0) }), !text.hasSuffix(".tgz") else { return nil }
        let search = text.hasPrefix("@") ? text.index(after: text.startIndex) : text.startIndex
        guard let at = text[search...].firstIndex(of: "@") else {
            return Spec(name: text, version: nil)
        }
        let name = String(text[..<at])
        let version = String(text[text.index(after: at)...])
        if version.hasPrefix("npm:") {
            return node(String(version.dropFirst(4)))
        }
        let elsewhere = version.contains("/") || foreign.contains { version.hasPrefix($0) }
        guard !elsewhere else { return nil }
        return Spec(name: name, version: isExactSemver(version) ? version : nil)
    }

    /// `name` or `name@version` (`cargo add`, `cargo install`).
    static func rust(_ text: String) -> Spec? {
        let parts = text.split(separator: "@", maxSplits: 1).map(String.init)
        let version = parts.count == 2 ? parts[1] : nil
        return Spec(name: parts.first ?? text, version: version.flatMap { isExactSemver($0) ? $0 : nil })
    }

    /// `MAJOR.MINOR.PATCH` with an optional pre-release or build suffix: the only form npm and cargo
    /// install exactly.
    static func isExactSemver(_ version: String) -> Bool {
        let core = version.split(whereSeparator: { $0 == "-" || $0 == "+" }).first ?? ""
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false)
        return numbers.count == 3 && numbers.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }
}

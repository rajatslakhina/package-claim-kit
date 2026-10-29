import Foundation

/// Reads the dependencies out of a manifest an answer shows: `requirements.txt`, `package.json` or
/// `Cargo.toml`. A block is a manifest when its fence says so (```` ```requirements.txt ````), its first line
/// says so (`# requirements.txt`), or, for JSON and TOML, it has a dependency section.
enum ManifestReader {
    static let nodeSections = ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"]
    static let rustSections: Set<String> = ["[dependencies]", "[dev-dependencies]", "[build-dependencies]"]

    /// Nil when the region is not a manifest, so its lines are read as commands instead.
    static func mentions(in region: CodeRegion) -> [PackageMention]? {
        guard region.isBlock else { return nil }
        let first = region.lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
        let comment = first.hasPrefix("#") || first.hasPrefix("//") ? first : ""
        let label = (region.info + " " + comment).lowercased()
        let text = region.lines.joined(separator: "\n")
        if label.contains("requirements") {
            return requirements(region.lines)
        }
        if label.contains("package.json") || label.hasPrefix("json"),
           nodeSections.contains(where: { text.contains("\"\($0)\"") }) {
            return packageJSON(text)
        }
        let pyproject = text.contains("[project]") || text.contains("[tool.")
        if label.contains("cargo.toml") || (label.hasPrefix("toml") && !pyproject) {
            return cargo(region.lines)
        }
        return nil
    }

    static func requirements(_ lines: [String]) -> [PackageMention] {
        let entries = lines.map { line in
            (line.range(of: "#").map { String(line[..<$0.lowerBound]) } ?? line)
                .trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        let options = entries.filter { $0.hasPrefix("-") }
        let index = options.compactMap { option -> String? in
            let parts = option.split(whereSeparator: { $0 == " " || $0 == "=" }).map(String.init)
            return FlagTable.python.elsewhere.contains(parts[0]) ? parts.dropFirst().first ?? parts[0] : nil
        }.first
        return entries.filter { !$0.hasPrefix("-") }.compactMap { entry in
            SpecParser.parse(entry, in: .pypi).map {
                PackageMention(
                    ecosystem: .pypi, name: $0.name, version: $0.version, origin: .manifest("requirements.txt"),
                    excerpt: entry, customIndex: index
                )
            }
        }
    }

    /// Every `"name": "version"` pair inside the dependency objects. Read as text, not decoded, because
    /// answers write JSON with comments, trailing commas and `...`.
    static func packageJSON(_ text: String) -> [PackageMention] {
        nodeSections.flatMap { section -> [PackageMention] in
            guard let key = text.range(of: "\"\(section)\""),
                  let open = text[key.upperBound...].firstIndex(of: "{"),
                  let close = text[open...].firstIndex(of: "}") else { return [] }
            let strings = quotedStrings(in: text[open...close])
            return stride(from: 0, to: strings.count - 1, by: 2).compactMap { position in
                let (name, range) = (strings[position], strings[position + 1])
                return SpecParser.parse(name + "@" + range, in: .npm).map {
                    PackageMention(
                        ecosystem: .npm, name: $0.name, version: $0.version, origin: .manifest("package.json"),
                        excerpt: "\"\(name)\": \"\(range)\""
                    )
                }
            }
        }
    }

    static func quotedStrings(in text: Substring) -> [String] {
        let pieces = text.components(separatedBy: "\"")
        return stride(from: 1, to: pieces.count - 1, by: 2).map { pieces[$0] }
    }

    /// `name = "1.0"` and `name = { version = "=1.0.3", features = [...] }` lines in dependency sections.
    /// Git, path and workspace dependencies are not on crates.io and are left out; `package = "real"`
    /// renames are read as the real crate.
    static func cargo(_ lines: [String]) -> [PackageMention] {
        var inSection = false
        var found: [PackageMention] = []
        for line in lines.map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line.hasPrefix("[") {
                let header = line.lowercased()
                inSection = rustSections.contains(header)
                    || (header.hasPrefix("[target.") && header.hasSuffix("dependencies]"))
                continue
            }
            guard inSection, let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: equals)...])
            if let mention = cargoDependency(key, value: value, line: line) { found.append(mention) }
        }
        return found
    }

    static func cargoDependency(_ key: String, value: String, line: String) -> PackageMention? {
        let table = value.contains("{")
        guard !(table && ["git", "path", "workspace", "registry"].contains(where: { value.contains($0) })) else {
            return nil
        }
        let requirement = table ? tomlString("version", in: value) : quotedStrings(in: Substring(value)).first
        let name = table ? tomlString("package", in: value) ?? key : key
        let pin = requirement.flatMap { $0.hasPrefix("=") ? String($0.dropFirst()) : nil }
        guard Ecosystem.crates.accepts(name) else { return nil }
        return PackageMention(
            ecosystem: .crates, name: name, version: pin.flatMap { SpecParser.isExactSemver($0) ? $0 : nil },
            origin: .manifest("Cargo.toml"), excerpt: line
        )
    }

    /// The string value of `key = "..."` in an inline table.
    static func tomlString(_ key: String, in table: String) -> String? {
        guard let range = table.range(of: key) else { return nil }
        let after = table[range.upperBound...].drop { $0 == " " }
        guard after.hasPrefix("=") else { return nil }
        return quotedStrings(in: after).first
    }
}

import Foundation

/// Reads install and run commands out of code.
enum CommandReader {
    struct Match: Sendable, Equatable {
        let verb: String
        let rule: ToolRule
        let arguments: ArraySlice<String>
    }

    /// The commands in a region: lines joined across trailing backslashes, then split at `&&`, `||`,
    /// `;` and `|`. Comment lines and trailing comments are dropped.
    static func commands(in region: CodeRegion) -> [String] {
        var joined: [String] = []
        var pending = ""
        for line in region.lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix("\\") {
                pending += trimmed.dropLast().trimmingCharacters(in: .whitespaces) + " "
            } else {
                joined.append(pending + trimmed)
                pending = ""
            }
        }
        if !pending.isEmpty { joined.append(pending) }
        return joined.flatMap(split).filter { !$0.isEmpty }
    }

    static func split(_ line: String) -> [String] {
        guard !line.hasPrefix("#") else { return [] }
        var parts = [line.range(of: " #").map { String(line[..<$0.lowerBound]) } ?? line]
        for separator in ["&&", "||", ";", "|"] {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// The packages one command installs or runs.
    static func mentions(in command: String) -> [PackageMention] {
        guard let match = match(strip(command.split(whereSeparator: \.isWhitespace).map(String.init))) else {
            return []
        }
        let rule = match.rule
        let parsed = ParsedArguments(match.arguments, table: FlagTable.table(for: rule.ecosystem))
        return specs(parsed, rule: rule).compactMap { raw in
            guard let spec = SpecParser.parse(raw, in: rule.ecosystem) else { return nil }
            return PackageMention(
                ecosystem: rule.ecosystem,
                name: spec.name,
                version: rule.exactPins ? parsed.version ?? spec.version : nil,
                origin: .command(match.verb),
                excerpt: command,
                customIndex: parsed.index
            )
        }
    }

    /// Drops prompts, `sudo`, `RUN`, environment assignments, notebook `!`/`%`, and `python -m`, and
    /// reads `pip3` or `pip3.12` as `pip`.
    static func strip(_ tokens: [String]) -> [String] {
        let rest = tokens.drop { token in
            ["$", "%", ">", "PS>", "sudo", "RUN", "env", "time", "exec"].contains(token)
                || token.hasPrefix("-") || token.contains("=")
        }
        guard var head = rest.first else { return [] }
        if head.hasPrefix("!") || head.hasPrefix("%") { head.removeFirst() }
        var out = [head] + rest.dropFirst()
        if out.count > 2, out[0].hasPrefix("python") || out[0] == "py", out[1] == "-m" {
            out.removeFirst(2)
        }
        if out[0].hasPrefix("pip"), out[0].dropFirst(3).allSatisfy({ $0.isNumber || $0 == "." }) {
            out[0] = "pip"
        }
        return out
    }

    /// The longest known verb at the start of the tokens.
    static func match(_ tokens: [String]) -> Match? {
        for length in stride(from: min(3, tokens.count), through: 1, by: -1) {
            let verb = tokens.prefix(length).joined(separator: " ")
            if let rule = ToolRule.commands[verb] {
                return Match(verb: verb, rule: rule, arguments: tokens.dropFirst(length))
            }
        }
        return nil
    }

    static func specs(_ parsed: ParsedArguments, rule: ToolRule) -> [String] {
        switch rule.shape {
        case .every:
            return parsed.positional + parsed.packages
        case .first:
            return parsed.packages.isEmpty ? Array(parsed.positional.prefix(1)) : parsed.packages
        case .initializer:
            return parsed.positional.prefix(1).map(initializer)
        }
    }

    /// `vite@latest` → `create-vite@latest`, `@scope/app` → `@scope/create-app`, `@scope` → `@scope/create`:
    /// what `npm create` and its cousins actually run.
    static func initializer(_ raw: String) -> String {
        guard raw.hasPrefix("@") else { return "create-" + raw }
        guard let slash = raw.firstIndex(of: "/") else { return raw + "/create" }
        return String(raw[...slash]) + "create-" + raw[raw.index(after: slash)...]
    }
}

/// A command's arguments, sorted into positional ones and the flags that matter.
struct ParsedArguments: Sendable, Equatable {
    var positional: [String] = []
    var packages: [String] = []
    var version: String?
    var index: String?

    init(_ arguments: ArraySlice<String>, table: FlagTable) {
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            guard argument.hasPrefix("-"), argument.count > 1 else {
                positional.append(argument)
                continue
            }
            let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
            let flag = parts[0]
            let value = parts.count == 2 ? parts[1] : table.takesValue(flag) ? iterator.next() : nil
            record(flag, value: value, table: table)
        }
    }

    mutating func record(_ flag: String, value: String?, table: FlagTable) {
        if table.elsewhere.contains(flag) {
            index = value ?? flag
        }
        if table.packages.contains(flag), let value {
            packages.append(value)
        }
        if table.versions.contains(flag) {
            version = value.flatMap { SpecParser.isExactSemver($0) ? $0 : nil }
        }
    }
}

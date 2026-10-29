import Foundation

/// A piece of an answer that is code: a fenced block or an inline span.
struct CodeRegion: Sendable, Equatable {
    /// The fence's info string, lowercased (`bash`, `requirements.txt`, `json`); empty for inline code.
    let info: String
    let lines: [String]
    let isBlock: Bool
}

/// Finds the code in an answer. Prose is never read for commands: "you can pip install it" names no
/// package, and reading prose would look one up.
enum CodeRegions {
    static func find(in text: String) -> [CodeRegion] {
        var regions: [CodeRegion] = []
        var fence: OpenFence?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if trimmed.hasPrefix(open.marker), trimmed.drop(while: { $0 == open.marker.first }).isEmpty {
                    regions.append(CodeRegion(info: open.info, lines: open.lines, isBlock: true))
                    fence = nil
                } else {
                    fence?.lines.append(line)
                }
            } else if let marker = fenceMarker(trimmed) {
                let info = trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces).lowercased()
                fence = OpenFence(marker: marker, info: info, lines: [])
            } else {
                regions += inlineSpans(in: line).map { CodeRegion(info: "", lines: [$0], isBlock: false) }
            }
        }
        if let open = fence {
            regions.append(CodeRegion(info: open.info, lines: open.lines, isBlock: true))
        }
        return regions
    }

    struct OpenFence {
        let marker: String
        let info: String
        var lines: [String]
    }

    /// The run of three or more backticks or tildes that opens a fence.
    static func fenceMarker(_ trimmed: String) -> String? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let marker = String(trimmed.prefix { $0 == first })
        return marker.count >= 3 ? marker : nil
    }

    /// The code between single backticks; an unclosed span is not code.
    static func inlineSpans(in line: String) -> [String] {
        let parts = line.components(separatedBy: "`")
        return stride(from: 1, to: parts.count - 1, by: 2)
            .map { parts[$0].trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

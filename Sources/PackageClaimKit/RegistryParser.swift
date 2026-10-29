import Foundation

/// Reads the three registries' JSON. Lenient on purpose: a field a registry stops sending becomes nil,
/// not a failed lookup.
enum RegistryParser {
    typealias Object = [String: Any]

    static func parse(_ data: Data, in ecosystem: Ecosystem) -> PackageFacts? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? Object else { return nil }
        return switch ecosystem {
        case .pypi: python(root)
        case .npm: node(root)
        case .crates: rust(root)
        }
    }

    /// `info.name`, `info.version`, `info.yanked`, and `releases`: version → files with
    /// `upload_time_iso_8601`. A release with no files cannot be installed.
    static func python(_ root: Object) -> PackageFacts? {
        guard let info = root["info"] as? Object, let name = info["name"] as? String else { return nil }
        let releases = root["releases"] as? [String: [Object]] ?? [:]
        let uploads = releases.values.joined().compactMap { ($0["upload_time_iso_8601"] as? String).flatMap(date) }
        let yanked = (info["yanked"] as? Bool) == true
        let reason = (info["yanked_reason"] as? String).map { ": " + $0 } ?? ""
        return PackageFacts(
            ecosystem: .pypi, name: name, firstPublished: uploads.min(), latestVersion: info["version"] as? String,
            versions: Set(releases.filter { !$0.value.isEmpty }.keys),
            deprecation: yanked ? "its latest release is yanked" + reason : nil
        )
    }

    /// `name`, `dist-tags.latest`, `time.created`, and `versions`: version → manifest, whose
    /// `deprecated` is a message. An unpublished package keeps its name and `time` but no versions.
    static func node(_ root: Object) -> PackageFacts? {
        guard let name = root["name"] as? String else { return nil }
        let versions = root["versions"] as? Object ?? [:]
        let latest = (root["dist-tags"] as? Object)?["latest"] as? String
        let created = ((root["time"] as? Object)?["created"] as? String).flatMap(date)
        let deprecation = latest.flatMap { (versions[$0] as? Object)?["deprecated"] as? String }
        return PackageFacts(
            ecosystem: .npm, name: name, firstPublished: created, latestVersion: latest,
            versions: Set(versions.keys), deprecation: deprecation
        )
    }

    /// `crate.name`, `crate.created_at`, `crate.max_version`, and `versions[]` with `num` and `yanked`.
    static func rust(_ root: Object) -> PackageFacts? {
        guard let crate = root["crate"] as? Object, let name = crate["name"] as? String else { return nil }
        let versions = (root["versions"] as? [Object] ?? []).filter { ($0["yanked"] as? Bool) != true }
        return PackageFacts(
            ecosystem: .crates, name: name, firstPublished: (crate["created_at"] as? String).flatMap(date),
            latestVersion: crate["max_version"] as? String, versions: Set(versions.compactMap { $0["num"] as? String })
        )
    }

    /// ISO 8601 with or without fractional seconds (npm sends three digits, crates.io and PyPI six).
    static func date(_ text: String) -> Date? {
        var trimmed = text
        if let dot = text.firstIndex(of: "."), let end = text[dot...].dropFirst().firstIndex(where: { !$0.isNumber }) {
            trimmed = String(text[..<dot] + text[end...])
        }
        return try? Date(trimmed, strategy: .iso8601)
    }
}

/// One package an answer tells someone to install.
public struct PackageMention: Sendable, Hashable {
    /// Where in the answer the package was named.
    public enum Origin: Sendable, Hashable {
        /// An install or run command, by its verb: `pip install`, `npx`, `cargo add`.
        case command(String)
        /// A manifest, by its file name: `requirements.txt`, `package.json`, `Cargo.toml`.
        case manifest(String)
    }

    public let ecosystem: Ecosystem
    /// The name as the answer wrote it, without extras, version or quotes.
    public let name: String
    /// An exact version the answer pins (`==2.31.0`, `@4.17.21`, `"=1.0.3"`). Ranges are not pins.
    public let version: String?
    public let origin: Origin
    /// The command or manifest line the name came from, as written.
    public let excerpt: String
    /// The index or registry the command or manifest names instead of the public one, when it names one.
    /// The public registry says nothing about such a package, so it is reported as not checked.
    public let customIndex: String?

    public init(
        ecosystem: Ecosystem,
        name: String,
        version: String? = nil,
        origin: Origin,
        excerpt: String,
        customIndex: String? = nil
    ) {
        self.ecosystem = ecosystem
        self.name = name
        self.version = version
        self.origin = origin
        self.excerpt = excerpt
        self.customIndex = customIndex
    }

    /// The registry's key for the name: two spellings of one package share it.
    public var key: String { ecosystem.normalize(name) }

    /// The name with its pin, the way the ecosystem writes one: `requests==2.31.0`, `lodash@4.17.21`.
    public var spelled: String {
        guard let version else { return name }
        return name + (ecosystem == .pypi ? "==" : "@") + version
    }

    /// Where the name came from, for a note: the command's verb (`` `pip install` ``), or "in requirements.txt".
    public var source: String {
        switch origin {
        case .command(let verb): "`\(verb)`"
        case .manifest(let file): "in \(file)"
        }
    }
}

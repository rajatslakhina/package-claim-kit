/// Finds the packages an answer tells someone to install: in install and run commands inside code
/// (fenced blocks and inline spans), and in `requirements.txt`, `package.json` and `Cargo.toml` blocks.
public struct PackageReader: Sendable {
    public init() {}

    public func mentions(in text: String) -> [PackageMention] {
        CodeRegions.find(in: text).flatMap { region in
            ManifestReader.mentions(in: region)
                ?? CommandReader.commands(in: region).flatMap(CommandReader.mentions(in:))
        }
    }
}

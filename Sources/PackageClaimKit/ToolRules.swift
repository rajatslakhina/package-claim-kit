/// What an install or run command does with its arguments.
struct ToolRule: Sendable, Equatable {
    enum Shape: Sendable, Equatable {
        /// Every positional argument is a package (`pip install a b`, `npm i a b`).
        case every
        /// Only the first one is; the rest are its arguments (`npx cowsay hi`, `uvx ruff check`).
        case first
        /// The first one names an initializer: `npm create vite` runs the package `create-vite`.
        case initializer
    }

    let ecosystem: Ecosystem
    let shape: Shape
    /// False for `cargo add`, whose `serde@1.0.3` is a caret requirement, not a pin.
    var exactPins = true
}

/// Which flags take a value, per ecosystem, so `pip install -r requirements.txt` is not read as a
/// package called `requirements.txt`.
struct FlagTable: Sendable {
    /// Flags whose value is not a package.
    let valued: Set<String>
    /// Flags that point the command at another index or registry, or at git or a path.
    let elsewhere: Set<String>
    /// Flags whose value is a package (`npx -p cowsay`, `uvx --from httpie`).
    let packages: Set<String>
    /// Flags whose value is an exact version (`cargo install ripgrep --version 14.1.0`).
    let versions: Set<String>

    func takesValue(_ flag: String) -> Bool {
        valued.contains(flag) || elsewhere.contains(flag) || packages.contains(flag) || versions.contains(flag)
    }

    static func table(for ecosystem: Ecosystem) -> FlagTable {
        switch ecosystem {
        case .pypi: python
        case .npm: node
        case .crates: rust
        }
    }

    static let python = FlagTable(
        valued: [
            "-r", "--requirement", "-c", "--constraint", "-e", "--editable", "-t", "--target", "--prefix",
            "--root", "-f", "--find-links", "--python", "-p", "--group", "-G", "--extra", "-E", "--source",
            "--platform", "--python-version", "--cache-dir", "--proxy", "--timeout", "--trusted-host", "--cert",
            "--log", "--src"
        ],
        elsewhere: ["-i", "--index-url", "--extra-index-url", "--index", "--default-index"],
        packages: ["--with", "--from"],
        versions: []
    )

    static let node = FlagTable(
        valued: [
            "--prefix", "-w", "--workspace", "--tag", "--omit", "--include", "--cache", "-C", "--dir",
            "--filter", "-F", "--loglevel", "--install-strategy", "--save-prefix"
        ],
        elsewhere: ["--registry"],
        packages: ["-p", "--package"],
        versions: []
    )

    static let rust = FlagTable(
        valued: [
            "--features", "-F", "--rename", "--target", "--target-dir", "--root", "--profile", "-p", "--package",
            "--manifest-path", "--bin", "--example", "--branch", "--tag", "--rev", "--jobs", "-j", "--config",
            "-Z", "--color"
        ],
        elsewhere: ["--git", "--path", "--registry", "--index"],
        packages: [],
        versions: ["--version", "--vers"]
    )
}

extension ToolRule {
    /// Commands by their verb, after `sudo`, `python -m` and prompts are stripped.
    static let commands: [String: ToolRule] = {
        var rules: [String: ToolRule] = [:]
        let python = ToolRule(ecosystem: .pypi, shape: .every)
        for verb in ["pip install", "pip download", "pipx install", "uv add", "uv pip install", "uv tool install",
                     "poetry add", "pdm add", "pipenv install", "easy_install"] {
            rules[verb] = python
        }
        for verb in ["pipx run", "uvx", "uv tool run"] {
            rules[verb] = ToolRule(ecosystem: .pypi, shape: .first)
        }
        let node = ToolRule(ecosystem: .npm, shape: .every)
        for alias in ["install", "i", "in", "ins", "inst", "insta", "instal", "isnt", "isnta", "isntal",
                      "isntall", "add"] {
            rules["npm " + alias] = node
        }
        for verb in ["yarn add", "yarn global add", "pnpm add", "pnpm install", "pnpm i", "bun add", "bun install",
                     "bun i"] {
            rules[verb] = node
        }
        for verb in ["npx", "npm exec", "yarn dlx", "pnpm dlx", "bunx", "bun x"] {
            rules[verb] = ToolRule(ecosystem: .npm, shape: .first)
        }
        for verb in ["npm create", "npm init", "yarn create", "pnpm create", "bun create"] {
            rules[verb] = ToolRule(ecosystem: .npm, shape: .initializer)
        }
        rules["cargo add"] = ToolRule(ecosystem: .crates, shape: .every, exactPins: false)
        rules["cargo install"] = ToolRule(ecosystem: .crates, shape: .every)
        return rules
    }()
}

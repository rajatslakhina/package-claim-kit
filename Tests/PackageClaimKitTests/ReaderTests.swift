@testable import PackageClaimKit
import XCTest

final class ReaderTests: XCTestCase {
    func testCodeRegions() {
        let text = """
        Install it with `pip install requests` and run `ruff check`. An open ` tick is prose.
        ```bash
        npm i lodash
        ```bash
        ````
        ~~~toml
        [dependencies]
        ```
        """
        let regions = CodeRegions.find(in: text)
        XCTAssertEqual(regions.map(\.lines), [
            ["pip install requests"], ["ruff check"], ["npm i lodash", "```bash"], ["[dependencies]", "```"]
        ])
        XCTAssertEqual(regions.map(\.info), ["", "", "bash", "toml"])
        XCTAssertEqual(regions.map(\.isBlock), [false, false, true, true])
        XCTAssertEqual(CodeRegions.find(in: "Use `` here and `` there, `x`"), [
            CodeRegion(info: "", lines: ["x"], isBlock: false)
        ])
        XCTAssertNil(CodeRegions.fenceMarker("``not a fence"))
        XCTAssertNil(CodeRegions.fenceMarker(""))
    }

    func testCommandsAreSplitJoinedAndUncommented() {
        let region = block("bash", "# pip install commented-out", "pip install \\", "  requests  # the client",
                           "cd app && npm i lodash; cargo add serde || true | cat", "", "uvx \\")
        XCTAssertEqual(CommandReader.commands(in: region), [
            "pip install requests", "cd app", "npm i lodash", "cargo add serde", "true", "cat", "uvx"
        ])
    }

    func testPromptsSudoAndInterpretersAreStripped() {
        XCTAssertEqual(names(command("$ sudo -H pip3 install requests")), ["requests"])
        XCTAssertEqual(names(command("!pip install pandas")), ["pandas"])
        XCTAssertEqual(names(command("%pip install numpy")), ["numpy"])
        XCTAssertEqual(names(command("% python3.12 -m pip install httpx")), ["httpx"])
        XCTAssertEqual(names(command("py -m pip install rich")), ["rich"])
        XCTAssertEqual(names(command("RUN pip3.11 install flask")), ["flask"])
        XCTAssertEqual(names(command("CI=1 npm i axios")), ["axios"])
        XCTAssertEqual(names(command("pipx install black")), ["black"])
        XCTAssertEqual(command("python -m"), [])
        XCTAssertEqual(command("sudo"), [])
        XCTAssertEqual(command("brew install wget"), [])
        XCTAssertEqual(CommandReader.match([]), nil)
    }

    func testPythonCommands() {
        let found = command("pip install -U 'requests[socks]==2.31.0' Django>=4 -r requirements.txt ./local -e .")
        XCTAssertEqual(names(found), ["requests==2.31.0", "Django"])
        XCTAssertEqual(found.first?.origin, .command("pip install"))
        XCTAssertEqual(found.first?.excerpt, "pip install -U 'requests[socks]==2.31.0' Django>=4 -r requirements.txt ./local -e .")
        XCTAssertEqual(names(command("uv add fastapi===0.115.0 'pydantic==2.*' -")), ["fastapi==0.115.0", "pydantic"])
        XCTAssertEqual(names(command("uvx --from httpie http GET example.com")), ["httpie"])
        XCTAssertEqual(names(command("uvx ruff check .")), ["ruff"])
        XCTAssertEqual(names(command("uv tool run --with mkdocs-material mkdocs serve")), ["mkdocs-material"])
        XCTAssertEqual(names(command("pip install package-name your-package 2.31.0 git+https://x/y.git dist/a.whl")), [])
        let indexed = command("pip install --index-url=https://pypi.internal/simple corp-utils")
        XCTAssertEqual(indexed.first?.customIndex, "https://pypi.internal/simple")
        XCTAssertEqual(command("pip install corp-utils --extra-index-url").first?.customIndex, "--extra-index-url")
    }

    func testNodeCommands() {
        XCTAssertEqual(names(command("npm install --save-dev @types/node@20.11.5 lodash@latest typescript")),
                       ["@types/node@20.11.5", "lodash", "typescript"])
        XCTAssertEqual(names(command("yarn add left-pad --tag beta react@npm:preact@10.24.3")), ["left-pad", "preact@10.24.3"])
        XCTAssertEqual(names(command("pnpm add github:user/repo user/repo x@file:../x x@user/repo ./pkg.tgz")), [])
        XCTAssertEqual(names(command("npx -y create-react-app my-app")), ["create-react-app"])
        XCTAssertEqual(names(command("npx -p cowsay cowsay hello")), ["cowsay"])
        XCTAssertEqual(names(command("npx")), [])
        XCTAssertEqual(names(command("npm create vite@latest my-app -- --template react")), ["create-vite"])
        XCTAssertEqual(names(command("npm init @angular")), ["@angular/create"])
        XCTAssertEqual(names(command("yarn create @remix-run/app")), ["@remix-run/create-app"])
        XCTAssertEqual(names(command("npm init")), [])
        XCTAssertEqual(command("npm i corp-ui --registry https://npm.corp").first?.customIndex, "https://npm.corp")
    }

    func testRustCommands() {
        XCTAssertEqual(names(command("cargo add serde@1.0.229 tokio -F full")), ["serde", "tokio"])
        XCTAssertEqual(names(command("cargo install ripgrep --version 14.1.0")), ["ripgrep@14.1.0"])
        XCTAssertEqual(names(command("cargo install ripgrep@14.1.0")), ["ripgrep@14.1.0"])
        XCTAssertEqual(names(command("cargo install ripgrep --version ^14")), ["ripgrep"])
        XCTAssertEqual(command("cargo install --git https://github.com/x/y tool").first?.customIndex,
                       "https://github.com/x/y")
    }

    func testSpecParser() {
        XCTAssertEqual(SpecParser.parse("requests[socks", in: .pypi), SpecParser.Spec(name: "requests", version: nil))
        XCTAssertEqual(SpecParser.parse("flask==3.0,!=3.0.1", in: .pypi)?.version, nil)
        XCTAssertNil(SpecParser.parse(".hidden", in: .pypi))
        XCTAssertEqual(SpecParser.parse("@scope/name", in: .npm), SpecParser.Spec(name: "@scope/name", version: nil))
        XCTAssertNil(SpecParser.parse("", in: .crates))
        XCTAssertEqual(SpecParser.parse("serde@1", in: .crates), SpecParser.Spec(name: "serde", version: nil))
        XCTAssertTrue(SpecParser.isExactSemver("1.2.3-beta.1+build"))
        XCTAssertFalse(SpecParser.isExactSemver("1.2"))
        XCTAssertFalse(SpecParser.isExactSemver("1.2.x"))
        XCTAssertFalse(SpecParser.isExactSemver(""))
    }

    func testRequirementsManifest() {
        let text = """
        ```requirements.txt
        # web stack
        --index-url https://pypi.internal/simple
        -r base.txt
        flask==3.0.3  # pinned
        requests; python_version < "3.8"

        ./vendored
        ```
        """
        let found = mentions(text)
        XCTAssertEqual(names(found), ["flask==3.0.3", "requests"])
        XCTAssertEqual(found.first?.origin, .manifest("requirements.txt"))
        XCTAssertEqual(found.first?.excerpt, "flask==3.0.3")
        XCTAssertEqual(found.first?.customIndex, "https://pypi.internal/simple")
        XCTAssertEqual(found.first?.source, "in requirements.txt")
        let byComment = ManifestReader.mentions(in: block("", "# requirements.txt", "numpy", "--extra-index-url"))
        XCTAssertEqual(byComment?.map(\.spelled), ["numpy"])
        XCTAssertEqual(byComment?.first?.customIndex, "--extra-index-url")
        XCTAssertNil(ManifestReader.mentions(in: block("bash", "pip install -r requirements.txt")))
        XCTAssertNil(ManifestReader.mentions(in: CodeRegion(info: "", lines: ["x"], isBlock: false)))
        XCTAssertNil(ManifestReader.mentions(in: block("")))
    }

    func testPackageJSON() {
        let text = """
        ```json
        {
          "name": "app",
          "dependencies": { "react": "^18.3.1", "lodash": "4.17.21", "corp": "workspace:*", "x": "file:../x" },
          // comments are fine
          "devDependencies": {
            "real": "npm:vitest@2.1.4",
            "odd"
          }
        }
        ```
        """
        let found = mentions(text)
        XCTAssertEqual(names(found), ["react", "lodash@4.17.21", "vitest@2.1.4"])
        XCTAssertEqual(found.first?.excerpt, "\"react\": \"^18.3.1\"")
        XCTAssertEqual(found.first?.origin, .manifest("package.json"))
        XCTAssertEqual(names(mentions("```\n// package.json\n{\"dependencies\": {\"express\": \"4.21.1\"}}\n```")),
                       ["express@4.21.1"])
        XCTAssertNil(ManifestReader.mentions(in: block("json", "{\"name\": \"app\"}")))
    }

    func testCargoManifest() {
        let text = """
        ```toml
        [package]
        name = "app"

        [dependencies]
        serde = "1.0"
        tokio = { version = "1", features = ["full"] }
        rand = "=0.8.5"
        loose = "=0.8"
        mylib = { path = "../mylib" }
        shared = { workspace = true }
        json = { package = "serde_json", version = "=1.0.128" }
        flags = { features = ["version"] }
        "quoted" = "1"
        # a comment

        [target.'cfg(unix)'.dependencies]
        nix = "0.29"

        [dev-dependencies]
        criterion = "0.5"
        ```
        """
        let found = mentions(text)
        XCTAssertEqual(names(found), ["serde", "tokio", "rand@0.8.5", "loose", "serde_json@1.0.128", "flags",
                                      "nix", "criterion"])
        XCTAssertEqual(found.first?.excerpt, "serde = \"1.0\"")
        XCTAssertEqual(found.first?.origin, .manifest("Cargo.toml"))
        XCTAssertEqual(names(mentions("```\n# Cargo.toml\n[dependencies]\nanyhow = \"1\"\n```")), ["anyhow"])
        XCTAssertEqual(mentions("```toml\n[project]\ndependencies = [\"requests\"]\n[tool.poetry.dependencies]\n```"), [])
    }

    func testMentionSpellingAndSource() {
        XCTAssertEqual(mention("requests", version: "2.31.0").spelled, "requests==2.31.0")
        XCTAssertEqual(mention("lodash", .npm, version: "4.17.21").spelled, "lodash@4.17.21")
        XCTAssertEqual(mention("lodash", .npm).source, "`pip install`")
        XCTAssertEqual(mention("Python_Dateutil").key, "python-dateutil")
    }

    func testEcosystemNames() {
        XCTAssertEqual(Ecosystem.pypi.normalize("Python_Dateutil..x"), "python-dateutil-x")
        XCTAssertEqual(Ecosystem.npm.normalize("JSONStream"), "JSONStream")
        XCTAssertEqual(Ecosystem.crates.normalize("Serde_JSON"), "serde-json")
        XCTAssertEqual(Ecosystem.allCases.map(\.registryName), ["PyPI", "npm", "crates.io"])
        XCTAssertTrue(Ecosystem.pypi.accepts("zope.interface"))
        for bad in ["", "-x", "x-", "a b", String(repeating: "a", count: 215)] {
            XCTAssertFalse(Ecosystem.pypi.accepts(bad), bad)
        }
        XCTAssertTrue(Ecosystem.npm.accepts("@types/node"))
        for bad in ["@types", "a/b", "@/x", ".x", "_x", "x$", "@a/b/c"] {
            XCTAssertFalse(Ecosystem.npm.accepts(bad), bad)
        }
        XCTAssertTrue(Ecosystem.crates.accepts("serde_json"))
        for bad in ["1x", "x.y", String(repeating: "a", count: 65)] {
            XCTAssertFalse(Ecosystem.crates.accepts(bad), bad)
        }
    }
}

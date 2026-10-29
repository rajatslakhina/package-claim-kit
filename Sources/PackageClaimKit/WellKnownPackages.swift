/// A short, hand-picked list of names people install every day, per ecosystem. It is not a download
/// ranking: it is what a near-miss is measured against, so "reqeusts" can be answered with "requests".
public struct WellKnownPackages: Sendable {
    private let names: [Ecosystem: [String]]
    private let keys: [Ecosystem: Set<String>]

    public init(_ names: [Ecosystem: [String]]) {
        self.names = names
        self.keys = names.mapValues { Set($0.map(Self.fold)) }
    }

    public func contains(_ name: String, in ecosystem: Ecosystem) -> Bool {
        keys[ecosystem]?.contains(Self.fold(name)) == true
    }

    /// The well-known name `name` is a near-spelling of, or nil. In order: the same name with a
    /// `python-`, `py`, `node-`, `-js`, `.js`, `-rs` (and similar) affix added; the same letters with
    /// different separators; one edit away (two for names of six letters or more), counting a swap of
    /// neighbouring letters as one edit.
    public func nearest(to name: String, in ecosystem: Ecosystem) -> String? {
        let key = Self.fold(name)
        guard !contains(name, in: ecosystem), let candidates = names[ecosystem] else { return nil }
        let folded = candidates.map { (name: $0, key: Self.fold($0)) }
        let bare = Self.affixes.compactMap { Self.strip($0, from: key) }
        if let hit = folded.first(where: { bare.contains($0.key) }) {
            return hit.name
        }
        if let hit = folded.first(where: { Self.squash($0.key) == Self.squash(key) }) {
            return hit.name
        }
        let limit = key.count >= 6 ? 2 : 1
        let scored = folded.map { (name: $0.name, distance: NameDistance.between(key, $0.key, limit: limit)) }
        return scored.filter { $0.distance <= limit }.min { $0.distance < $1.distance }?.name
    }

    static let affixes: [(prefix: String, suffix: String)] = [
        ("python-", ""), ("py-", ""), ("py", ""), ("", "-python"), ("", "-py"), ("node-", ""), ("js-", ""),
        ("", "-js"), ("", ".js"), ("", "js"), ("", "-node"), ("rust-", ""), ("", "-rs"), ("", "-rust")
    ]

    static func strip(_ affix: (prefix: String, suffix: String), from key: String) -> String? {
        guard key.count > affix.prefix.count + affix.suffix.count + 1,
              key.hasPrefix(affix.prefix), key.hasSuffix(affix.suffix) else { return nil }
        return String(key.dropFirst(affix.prefix.count).dropLast(affix.suffix.count))
    }

    static func fold(_ name: String) -> String { name.lowercased() }

    static func squash(_ key: String) -> String { key.filter { !"-_.".contains($0) } }

    /// Seventy-odd names per ecosystem, picked by hand in October 2026.
    public static let `default` = WellKnownPackages([
        .pypi: [
            "requests", "numpy", "pandas", "scipy", "matplotlib", "seaborn", "scikit-learn", "tensorflow", "torch",
            "torchvision", "transformers", "flask", "django", "fastapi", "uvicorn", "pydantic", "sqlalchemy",
            "boto3", "botocore", "urllib3", "certifi", "setuptools", "wheel", "pip", "six", "python-dateutil",
            "pytz", "pyyaml", "jinja2", "click", "rich", "typer", "httpx", "aiohttp", "beautifulsoup4", "lxml",
            "pillow", "opencv-python", "pytest", "black", "mypy", "ruff", "openai", "anthropic", "langchain",
            "celery", "redis", "psycopg2-binary", "selenium", "cryptography", "paramiko", "tqdm", "jupyter",
            "notebook", "plotly", "polars", "sympy", "networkx", "nltk", "spacy", "gunicorn", "alembic", "pymongo",
            "protobuf", "grpcio", "tiktoken", "colorama", "python-dotenv", "playwright", "streamlit", "gradio"
        ],
        .npm: [
            "react", "react-dom", "next", "vue", "svelte", "preact", "express", "lodash", "axios", "moment", "dayjs",
            "date-fns", "typescript", "webpack", "vite", "esbuild", "rollup", "eslint", "prettier", "jest", "vitest",
            "mocha", "chai", "commander", "chalk", "debug", "dotenv", "uuid", "zod", "yup", "redux",
            "@reduxjs/toolkit", "react-router-dom", "tailwindcss", "postcss", "autoprefixer", "sass", "socket.io",
            "mongoose", "prisma", "@prisma/client", "sequelize", "pg", "mysql2", "redis", "ioredis", "jsonwebtoken",
            "bcrypt", "cors", "body-parser", "nodemon", "ts-node", "tsx", "rxjs", "three", "d3", "openai",
            "@anthropic-ai/sdk", "puppeteer", "playwright", "cheerio", "sharp", "multer", "passport", "graphql",
            "@apollo/client", "@types/node", "@types/react", "create-react-app", "create-vite", "create-next-app",
            "jscodeshift", "react-native", "expo"
        ],
        .crates: [
            "serde", "serde_json", "tokio", "rand", "clap", "anyhow", "thiserror", "log", "env_logger", "tracing",
            "tracing-subscriber", "reqwest", "hyper", "axum", "actix-web", "regex", "chrono", "time", "itertools",
            "rayon", "lazy_static", "once_cell", "futures", "async-trait", "bytes", "uuid", "base64", "sqlx",
            "diesel", "rusqlite", "bincode", "toml", "syn", "quote", "proc-macro2", "criterion", "ripgrep",
            "cargo-edit", "wasm-bindgen", "serde_yaml", "url", "image", "nom", "crossbeam", "parking_lot"
        ]
    ])
}

/// Optimal string alignment distance: insertions, deletions, substitutions and swaps of neighbouring
/// characters, each one edit. Stops early once every path is over `limit`.
enum NameDistance {
    static func between(_ lhs: String, _ rhs: String, limit: Int) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard abs(left.count - right.count) <= limit else { return limit + 1 }
        var previous: [Int] = []
        var row = Array(0...right.count)
        for leftIndex in stride(from: 1, through: left.count, by: 1) {
            let before = row
            row = [leftIndex] + Array(repeating: 0, count: right.count)
            for rightIndex in stride(from: 1, through: right.count, by: 1) {
                let cost = left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1
                var best = min(before[rightIndex] + 1, row[rightIndex - 1] + 1, before[rightIndex - 1] + cost)
                if leftIndex > 1, rightIndex > 1, left[leftIndex - 1] == right[rightIndex - 2],
                   left[leftIndex - 2] == right[rightIndex - 1] {
                    best = min(best, previous[rightIndex - 2] + 1)
                }
                row[rightIndex] = best
            }
            if row.allSatisfy({ $0 > limit }) { return limit + 1 }
            previous = before
        }
        return row[right.count]
    }
}

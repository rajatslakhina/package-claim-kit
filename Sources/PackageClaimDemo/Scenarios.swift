import PackageClaimKit

enum Scenarios {
    static func run() async {
        let registry = StaticRegistry(snapshot)
        let vetter = PackageVetter(registry: registry)
        let typo = "```bash\npip install reqeusts\n```"
        show("1. A misspelled name", question: "How do I make HTTP calls from Python?", answer: typo,
             report: await vetter.review(typo, now: demoNow))

        let installer = "Install it with `pip install lodash`, then `import lodash`."
        show("2. The right name, the wrong installer", question: "How do I deep-clone an object in Python?",
             answer: installer, report: await vetter.review(installer, now: demoNow))

        let pinned = "```bash\npip install requests==3.0.0  # the async-native release\n```"
        show("3. A version that was never released", question: "Which requests version supports async?",
             answer: pinned, report: await vetter.review(pinned, now: demoNow))

        let fresh = "```bash\npip install fastapi pyjwt fastapi-jwt-shield\n```"
        show("4. A package registered six days ago", question: "How do I add JWT auth to FastAPI?",
             answer: fresh, report: await vetter.review(fresh, now: demoNow))

        let manifest = """
        ```json
        {
          "dependencies": { "request": "^2.88.2", "axios": "1.13.1", "lodash": "5.0.0" }
        }
        ```
        """
        show("5. A package.json with a deprecated package and a version that does not exist",
             question: "Give me a package.json for a small HTTP client.", answer: manifest,
             report: await vetter.review(manifest, now: demoNow))

        let clean = """
        ```toml
        [dependencies]
        serde = { version = "1", features = ["derive"] }
        tokio = "=1.48.0"
        ```
        Then `npm create vite@latest web` for the front end and `uvx ruff check .` before you commit.
        """
        show("6. Everything checks out", question: "Set up a Rust service with a web front end.", answer: clean,
             report: await vetter.review(clean, now: demoNow))

        let offline = PackageVetter(registry: StaticRegistry(snapshot, offline: [.crates: "crates.io timed out"]))
        let unreachable = "`cargo add serde tokio`"
        show("7. A registry that cannot be reached", question: "Which crates do I need?", answer: unreachable,
             report: await offline.review(unreachable, now: demoNow))

        await conversation()
    }

    /// The feedback goes back to the model; the rewrite is checked again, from what the vetter remembers.
    static func conversation() async {
        let vetter = PackageVetter(registry: StaticRegistry(snapshot))
        let first = "```bash\npip install fastapi reqeusts fastapi-jwt-shield\n```"
        let report = await vetter.review(first, now: demoNow)
        show("8a. A conversation: the first answer", question: "Add authenticated HTTP calls to my FastAPI app.",
             answer: first, report: report)
        let rewrite = "```bash\npip install fastapi requests==2.32.3 pyjwt\n```"
        show("8b. The rewrite after the feedback", question: report.feedback ?? "", answer: rewrite,
             report: await vetter.review(rewrite, now: demoNow))
        let lookups = await vetter.lookups
        let hits = await vetter.cacheHits
        let reviews = await vetter.reviews
        print("session: \(reviews) reviews, \(lookups) registry lookups, \(hits) answered from memory")
    }
}

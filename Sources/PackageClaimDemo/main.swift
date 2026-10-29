import Foundation
import PackageClaimKit

// `swift run PackageClaimDemo` replays eight scenarios against a fixed registry snapshot, so the
// output is the same on every run. `swift run PackageClaimDemo --live` asks the real registries.
if CommandLine.arguments.contains("--live") {
    let vetter = PackageVetter(registry: PublicRegistry())
    let answer = """
    ```bash
    pip install requests reqeusts-fastclient-zz
    npm i lodash@4.17.21 request
    cargo add serde
    ```
    """
    show("Live: the public registries, today", question: "(live lookup)", answer: answer,
         report: await vetter.review(answer))
} else {
    print("PackageClaimKit demo — registry snapshot of 2026-10-29, clock fixed at 2026-10-29\n")
    await Scenarios.run()
}

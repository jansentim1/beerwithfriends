# BeerWithMe — working agreement

iPhone app (SwiftUI, iOS 17+) + Firebase backend. Testable core in `BeerKit/` (Swift
package), Cloud Functions in `functions/` (TypeScript, Node 20), rules at repo root.
Spec: `docs/superpowers/specs/2026-07-11-beerwithme-design.md`.
Plan + loop protocol: `docs/superpowers/plans/2026-07-11-beerwithme.md`. Loop state: `STATE.md`.

## Gates (all must be green before commit)

```
cd BeerKit && swift test                       # on a Mac with broken CLT: see README
npm --prefix functions test
firebase emulators:exec --project demo-beerwithme --only firestore,auth,storage "npm --prefix functions run test:emu"
```

## Environments

- **tim-server** (Linux, `~/beerwithme`): full backend + BeerKit dev; `swift`, `java` (21),
  `firebase`, `gh` on PATH. Deploys via the VM service account (no key file).
- **Mac**: same gates with the CLT workaround in README. Only Xcode can build `App/`.
- **Firebase project**: `beerwithme-prod` (GCP 344187290414), everything in europe-west4.
  Bucket `beerwithme-prod.firebasestorage.app`. Blaze plan. Firestore emulator port is 8085.

## Autonomy rules

1. Work in small commits on `main`; push after every green gate run (`git push`).
2. After a green run that touched `functions/`, `firestore.rules`, `firestore.indexes.json`
   or `storage.rules`: run `tools/deploy.sh --no-gates`. Never deploy on red.
3. Never commit `node_modules`, `.build`, `functions/lib`, generated Xcode projects, or secrets.
4. Blockers only Tim can clear go under "Needs Tim" in `STATE.md`. Known ones: Apple
   Developer account (Sign in with Apple, APNs key for FCM), Xcode for `App/`.
5. Firebase Auth has no providers configured yet; do not fake sign-in in production data.

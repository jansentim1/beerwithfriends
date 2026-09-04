# Loop state
- Current task: 12 (handover; compile loop now lives in CI)
- Done: 1-8, 9, 10 (all screens compiled on GitHub macOS runner, run 33852266356), 11 (report/block wired; docs/privacy-policy.md, docs/app-store-checklist.md)
- Infra done 2026-09-04: `ios-build` workflow (unsigned simulator compile on every App/BeerKit push), `ios-testflight` workflow (manual, cloud-managed signing), iOS app registered in beerwithme-prod, GoogleService-Info.plist in App/Resources (gitignored) + GitHub secret FIREBASE_PLIST_B64. All 7 functions deployed in europe-west4 and matching source.
- Parked: —
- Needs Tim (see docs/RUNBOOK.md steps 1-3): Apple Developer Program enrollment; App Store Connect API key + 4 GitHub secrets (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, APPLE_TEAM_ID); App ID with Push + Sign in with Apple; App Store Connect app record; APNs key uploaded to FCM; Firebase Auth initialized with the Apple provider.
- Mac note (historical): the Mac's Command Line Tools are corrupted (see README). No longer on the critical path; nothing requires a Mac.

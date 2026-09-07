# RUNBOOK: from this repo to an iPhone, with no Mac

Everything runs on tim-server (Linux) plus GitHub-hosted macOS runners for the parts
that need Xcode. Tim's iPhone does the Apple-side clicking and installs via TestFlight.

## 0. What already exists (verified 2026-09-04)

| Piece | State |
|---|---|
| Firebase project `beerwithme-prod` (GCP 344187290414) | Blaze plan, europe-west4 |
| Firestore `(default)`, bucket `beerwithme-prod.firebasestorage.app` | exist |
| All 7 Cloud Functions | deployed, match `functions/src` |
| iOS app registered in Firebase | app id `1:344187290414:ios:92093f630d8114015870bf`, bundle `com.timjansen.BeerWithFriends` |
| `App/Resources/GoogleService-Info.plist` | on tim-server (gitignored) and in GitHub secret `FIREBASE_PLIST_B64` |
| Firebase Auth | **not initialized, no Apple provider yet** (step 3) |
| `ios-build` workflow | compiles the app unsigned on every push touching App/BeerKit |
| `ios-testflight` workflow | manual; needs the Apple secrets from step 2 |

## 1. Apple Developer Program (Tim, iPhone, one time)

1. Install the Apple Developer app: https://apps.apple.com/app/apple-developer/id640199958
2. Account tab, Enroll Now, choose **Individual**, pay 99 USD. Approval takes 1 to 2 days.
3. Once approved, note the **Team ID** (10 characters) at
   https://developer.apple.com/account under Membership details.

## 2. App Store Connect API key and GitHub secrets (Tim, iPhone browser, one time)

1. https://appstoreconnect.apple.com/access/integrations/api, tap Generate API Key
   (first time: Request Access, then generate). Name `github-ci`, role **App Manager**.
2. Write down the **Key ID** and the **Issuer ID** shown on that page.
3. Download the `.p8` file once. Open it in Files, share, copy its full text.
4. https://github.com/jansentim1/beerwithfriends/settings/secrets/actions, add four secrets:

   | Secret | Value |
   |---|---|
   | `ASC_KEY_ID` | Key ID |
   | `ASC_ISSUER_ID` | Issuer ID |
   | `ASC_KEY_P8` | whole text of the `.p8` file, including BEGIN/END lines |
   | `APPLE_TEAM_ID` | Team ID |

   `FIREBASE_PLIST_B64` is already set.

5. Register the App ID and capabilities, in the browser at
   https://developer.apple.com/account/resources/identifiers/list:
   Register, App IDs, App, Bundle ID **explicit** `com.timjansen.BeerWithFriends`,
   tick **Push Notifications** and **Sign in with Apple**, Continue, Register.
   (xcodebuild can create this itself, but doing it here is more predictable.)

6. Create the app record in App Store Connect: https://appstoreconnect.apple.com/apps,
   plus button, New App, iOS, name Pints With Mates, primary language English, bundle id
   from the list, SKU `beerwithme`, full access. TestFlight builds attach to this record.

## 3. Push and Sign in with Apple wiring (Tim, iPhone browser, one time)

1. APNs key: https://developer.apple.com/account/resources/authkeys/list, plus,
   name `firebase-apns`, tick Apple Push Notifications service (APNs), Register,
   download the `.p8` once. Note the Key ID.
2. Firebase console, project beerwithme-prod, Project settings, Cloud Messaging,
   Apple app configuration, APNs Authentication Key, Upload: the `.p8`, its Key ID,
   and your Team ID. https://console.firebase.google.com/project/beerwithme-prod/settings/cloudmessaging
3. Firebase Auth: https://console.firebase.google.com/project/beerwithme-prod/authentication,
   Get started, Sign-in method, Add new provider, **Apple**, Enable, Save.
   Nothing else is required for a native iOS app (Services ID is web only).

## 4. Ship a build (from tim-server)

```
gh workflow run ios-testflight            # archive, sign in the cloud, upload
gh run watch                              # follow it, about 15 minutes
```

The build number is the GitHub run number, so every run is a new TestFlight build.
When it fails, download the logs:

```
gh run download <run-id> -n archive-logs
```

First-time signing: xcodebuild with the API key creates the distribution certificate
and provisioning profile automatically (cloud-managed signing). If it complains about
a missing agreement, accept the latest Paid Apps agreement at
https://appstoreconnect.apple.com/agreements.

## 5. Install on iPhones (Tim, iPhone)

1. Install TestFlight from the App Store.
2. App Store Connect, Pints With Mates, TestFlight tab. The processed build appears after
   5 to 15 minutes. The first build of a version asks you to answer the export
   compliance question once; later builds inherit it (Info.plist already says no
   non-exempt encryption).
3. Internal testing: add yourself under Internal Testing (App Store Connect users).
   Friends: External Testing, create a group, add their emails. The first external
   build needs a short Apple review, usually under a day. After that, new builds
   go to testers automatically.

## 6. Backend changes

Any change under `functions/`, `firestore.rules`, `firestore.indexes.json` or
`storage.rules`: run the gates, then `tools/deploy.sh --no-gates`. Uses the VM
service account, no login needed.

## 7. Day-to-day compile loop

Push anything that touches `App/` or `BeerKit/` and the `ios-build` workflow compiles
it in about 5 minutes. Read the result from tim-server:

```
gh run list --workflow ios-build --limit 3
gh run view <id> --log | grep -E 'error:|warning:.*App/Sources'
```

Free-plan budget is roughly 200 macOS minutes a month for a private repo. A compile run
costs about 5, a TestFlight run about 15.

# App Store submission checklist

Everything App Review will look at for PubDates, and where it is handled.

## App Store Connect app record

- Bundle id: `com.timjansen.BeerWithFriends` (from `project.yml` `bundleIdPrefix` + target name).
- Category: Social Networking. Secondary: Food & Drink.
- Age rating: **17+**. In the questionnaire answer "Frequent/Intense" for
  "Alcohol, Tobacco, or Drug Use or References" and "Frequent/Intense" for
  "Unrestricted Web Access: No". User Generated Content: Yes.
- Privacy policy URL: https://beerwithme-prod.web.app/privacy (site/privacy.html, deployed with `tools/deploy.sh --no-gates --hosting`; keep it in step with docs/privacy-policy.md)
  and paste the URL. Required for any app with accounts.
- Support URL: the repo README or the same page.

## App Privacy labels (the "nutrition label")

Declare these as **collected, linked to the user, not used for tracking**:

| Category | Data type | Purpose |
|---|---|---|
| Contact Info | Name (display name) | App functionality |
| User Content | Photos, Other user content (beer logs) | App functionality |
| Identifiers | User ID | App functionality |
| Location | Coarse location (place name and the place's position, opt-in) | App functionality |
| Contacts | none | |
| Usage Data | none | |
| Diagnostics | none (no crash SDK) | |

Do **not** tick "Data used to track you". Firebase Analytics is not linked, so no
advertising identifiers.

## User Generated Content requirements (App Review guideline 1.2)

All four are implemented; App Review checks each.

| Requirement | Where |
|---|---|
| Filter objectionable content | Photos are visible only to accepted friends, once, for 24 hours. State this in review notes. |
| Report mechanism | Long-press any feed row or friend row, Report, pick a reason. Writes `reports/`. |
| Block mechanism | Long-press feed row or friend row, Block. Server severs friendship both ways. Unblock in Settings. |
| Contact info for the developer | Privacy policy contact email; Support URL. |

Add to the **App Review notes**: "Content is only shared between mutually accepted friends.
Every photo expires after 24 hours and can be viewed once per friend. Report and block are
in the long-press menu on any beer or friend. A demo account is not needed; Sign in with Apple
works with any Apple ID, and a second reviewer account can add the first by username."

## Sign in with Apple (guideline 4.8)

Sign in with Apple is the **only** sign-in, so the "offer Sign in with Apple if you offer
other third-party logins" rule is satisfied trivially.

## Account deletion (guideline 5.1.1(v))

Settings, Delete account. Calls the `deleteAccount` Cloud Function which erases everything
and removes the Firebase Auth user. Reviewers test this; it must work on the production
project before submission.

## Permissions strings (Info.plist)

- `NSCameraUsageDescription` and `NSLocationWhenInUseUsageDescription` are set in `project.yml`.
- Notifications: permission is requested only after onboarding finishes, with an in-app
  explanation on the username screen first.
- No photo library, microphone or contacts access. Location only when-in-use and only after the user opts in.

## Screenshots needed

Take them on a real device via TestFlight (no simulator in this project). Required sizes are
generated from a 6.7" and a 6.1" iPhone; upload one set for 6.7" and App Store Connect
scales the rest if you tick "use for all sizes".

1. Home with a few beers in the feed and one "view once" chip.
2. The big "I'm drinking a beer" button on an empty feed.
3. Camera review screen.
4. Friends tab with an incoming request.
5. Photo viewer with the "view once" badge.

## Before pressing Submit

- [ ] Production Firebase project deployed: `firebase deploy --only functions,firestore:rules,firestore:indexes,storage`
- [ ] APNs key uploaded to Firebase Cloud Messaging and a push received on a real device.
- [ ] Sign in with Apple capability on the App ID and the Apple provider enabled in Firebase Auth.
- [ ] Account deletion tested end to end on production.
- [x] Privacy policy URL live (2026-09-11).
- [ ] Export compliance: answer "No" to non-exempt encryption (only HTTPS); set
      `ITSAppUsesNonExemptEncryption = NO` in Info.plist to skip the question per build.
- [ ] Build uploaded via CI, tested on TestFlight by at least two people cheersing each other.

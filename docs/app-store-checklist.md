# App Store submission checklist

Researched 2026-10-15 against Apple's live App Review Guidelines, the App Store
Connect age-rating definitions and screenshot specifications, and the state of our
App Store Connect record (app id 6809410863). Everything App Review will look at,
ordered by what gets a first submission rejected.

## Status 2026-10-15 evening

All eight section A items are fixed on main (typed place when location is refused,
real privacy link, honest purpose string, App Store link in the update screen,
privacy manifest, Contact row, groups rank by who is out, review mate `pubdates`
behind `config/app.reviewMate`). Store record filled via the API. Build 39 is attached to version 1.0 and five
rig screenshots (1260 x 2736) are uploaded. SUBMITTED 2026-10-15 (WAITING_FOR_REVIEW). Submission also needed:
copyright, contentRightsDeclaration, a price schedule (Free, base NLD) and
/v2/appAvailabilities for all territories; `tools/submit-review.py` does the submit.

## A. Rejection risks in the app (fix in code before the store build)

| # | Risk | Guideline | Evidence | Fix |
|---|---|---|---|---|
| 1 | Privacy policy link in Settings points at `https://example.com/beerwithme/privacy` (dead placeholder) | 5.1.1(i) link must be in-app; 2.1(a) no placeholder content | `App/Sources/Views/SettingsView.swift:45` | Point it at https://beerwithme-prod.web.app/privacy |
| 2 | Location is required to log a drink; refusal gives a dead end ("Open Settings" alert) | 5.1.2(i): "may not require users to enable system functionalities (e.g. push notifications, location services) in order to access functionality"; 5.1.1(iv): "if a user declines to share Location, offer the ability to manually enter an address" | `HomeView.swift` location alert; build 37 decision | Product decision for Tim: (a) allow logging without location (no pin, no place) or (b) a manual place field when denied. Keep the ask, drop the wall. |
| 3 | Location purpose string says "when you turn that on" | 5.1.1(ii): purpose strings must "clearly and completely describe your use" | `project.yml` NSLocationWhenInUseUsageDescription | "Puts the address you're drinking at on the drink you log, so your mates can find you. Only read when you log." |
| 4 | Forced-upgrade screen sends people to TestFlight | 2.1 / 2.3: store build must not reference TestFlight | `UpdateRequiredView.swift` | Link to the App Store page (id 6809410863) once live; copy "Grab the update from the App Store" |
| 5 | Reviewer signs in with their own Apple ID and sees an empty feed, no mates, nothing to review | 2.1(a) "provide a demo account with full access" | Sign in with Apple is the only login; content is mates-only | Build a review mate: username `pubdates`, server auto-accepts requests to it, a scheduled function keeps a live drink (with photo + place) on it every 45 min while the review flag is on. Review notes tell them to add `pubdates`. |
| 6 | No `PrivacyInfo.xcprivacy` in the app target; `@AppStorage`/`UserDefaults` are required-reason APIs | ITMS-91053 (upload warning that becomes a block) | `find` found none; Firebase 11 ships its own | Add `App/Resources/PrivacyInfo.xcprivacy` declaring `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1`, no tracking, collected data types matching the labels below |
| 7 | Daily group "Leaderboard", "First one takes the crown": ranks mates by drinks logged | 1.4.3: apps that "encourage ... excessive amounts of alcohol" are not permitted | `GroupsView.swift:223,579` | Decided 2026-10-15 (Tim): "Tonight's round", rank by who is out (first to log), not by count. Server fields `todayOutCount`/`todayFirstAt`, BeerKit ranking and GroupsView copy changed; total stays as a quiet line. |
| 8 | No in-app contact for support | 1.2 "published contact information", 1.5 support URL "include an easy way to contact you" | Settings has no contact row; site/index.html has none | Add a "Contact" row in Settings (mailto) and a line with the email on the site page used as Support URL |

Already fine: Sign in with Apple as the only login (4.8 satisfied), in-app account
deletion via `deleteAccount` (5.1.1(v), emulator-tested), report + block in the
long-press menu (1.2), no analytics or tracking SDKs, `ITSAppUsesNonExemptEncryption`
false, iPhone only (no iPad screenshots needed), no background location.

## B. App Store Connect record (today it is empty)

Checked via the API on 2026-10-15: name still "Pints With Mates", no category, no age
rating answered, no description, keywords, screenshots, privacy policy URL, support
URL or review notes. Version 1.0 is in PREPARE_FOR_SUBMISSION with no build attached.

| Field | Value to set | How |
|---|---|---|
| Name | PubDates (iTunes search 2026-10-15: no app with that name) | API `appInfoLocalizations` PATCH, from tim-server |
| Subtitle | "Tell your mates you're having one" | API |
| Primary category | Social Networking; secondary Food & Drink | API `appInfos` PATCH |
| Age rating | Answer: alcohol references **Frequent** (gives 18+), user-generated content Yes, messaging/chat Yes (group notes, reactions), social media **Yes** (feed with reactions; minimum 13+, we are 18+ anyway), unrestricted web access No, contests No | API `ageRatingDeclarations` PATCH. Social-media answers are mandatory for new submissions since September 2026. |
| Privacy policy URL | https://beerwithme-prod.web.app/privacy | API |
| Support URL | https://beerwithme-prod.web.app/ with a contact line added (A8) | API |
| Description, keywords, what's new | from docs/store-listing.md (to write) | API |
| Screenshots | iPhone 6.9" set, 1320 x 2868 portrait, 3 to 6 images, no alpha. Apple scales the rest. Must be 4+ appropriate (2.3.8): a pint is fine, no drunkenness. Capture on the rig with an iPhone 17 Pro Max simulator, seeded frames. | API `appScreenshotSets` upload |
| App Privacy labels | No public API. Tim in the browser: Collected, linked to user, not for tracking: Name (display name), User ID, Photos, Other user content, Precise Location (the address and coordinate on a drink), Coarse Location. Nothing used for tracking. | Browser only |
| App Review notes | See section C | API `appStoreReviewDetails` |
| Export compliance | Inherited from TestFlight builds (plist key set) | nothing |
| Build | A fresh `ios-testflight` run after section A is merged, then attach to version 1.0 | API |
| Release | Manual release after approval, so the TestFlight expiry and `minBuild` can be sequenced | `releaseType: MANUAL` |

## C. App Review notes (paste as reviewNotes)

"PubDates is a private, friends-only app: you log that you are having a drink, and
only mates who accepted your request see it, for a few hours at most. There is no public
content. Sign in with Apple is the only login, so there is no demo password: sign in
with any Apple ID, pick a username, then on the Mates tab add the username
`pubdates`. That account accepts automatically and always has a live drink with a
photo and a place, so the Home feed, Map, photo view-once, reactions and Groups all
have content. Report and Block are in the long-press menu on any drink or mate.
Delete account is in Settings. Location is asked when you log a drink; logging
works without it. The camera is the only photo source. Contact: twj.jansen@gmail.com."



## D. Order of work

1. Tim decides A2 (location wall) and A7 (leaderboard wording).
2. Code: A1, A3, A4, A6, A8, the `pubdates` review mate (A5) with emulator tests, and A2/A7 as decided. Gates green, deploy functions, push.
3. Store record via API: everything in B except privacy labels. Write docs/store-listing.md first and get Tim's OK on the copy.
4. Rig screenshots at 1320 x 2868, upload.
5. `gh workflow run ios-testflight`, attach the build to 1.0, submit for review (API `appStoreVersionSubmissions` / `reviewSubmissions`).
6. Tim in the browser: App Privacy labels (B), confirm the age-rating result shows 18+, press nothing else.
7. First review usually answers within 24 to 48 hours. Rejections come with a guideline number; answer in Resolution Center, resubmit the same build if only metadata changed.
8. After approval: switch `UpdateRequiredView` and the site to the App Store link, keep `minBuild` at or below the approved build, expire TestFlight builds only after the store build is live.

## Sources

- App Review Guidelines (1.2, 1.4.3, 1.5, 2.1, 2.3.6, 2.3.8, 4.8, 5.1.1, 5.1.2, 5.1.5): https://developer.apple.com/app-store/review/guidelines/
- Age rating values and definitions (frequent alcohol = 18+, social media = 13+ minimum): https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions
- Social media questions mandatory from September 2026: https://9to5mac.com/2026/07/09/apple-adds-social-media-questions-to-app-store-connect-age-rating-questionnaire/
- Screenshot specifications: https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications
- Required-reason APIs and ITMS-91053: https://developer.apple.com/forums/thread/750341
- Rejections over location walls and purpose strings: https://developer.apple.com/forums/thread/757532

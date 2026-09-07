# PubDates: the goal

_Draft 2026-09-07. Tim owns this file; Claude plans against it._

## One sentence

A group of friends can install PubDates from TestFlight and, within a minute, tell each
other "I'm having a beer", get a push, cheers back, and share a photo that can be seen
exactly once. It feels instant, looks like a real iPhone app, and is ready to submit to
the App Store.

## Done means (acceptance criteria)

| # | Criterion | How it is checked |
|---|---|---|
| 1 | Sign in with Apple, pick a username, reach the feed in under 10 s on a cold install | Tim + one friend, on device |
| 2 | Logging a beer shows the row instantly (< 100 ms perceived) and never duplicates | unit tests + on device |
| 3 | A friend receives the push within 5 s of the tap; cheers pushes back | two devices |
| 4 | Photo: capture, upload, friend views once, second attempt is refused, gone after 24 h | emulator tests + two devices |
| 5 | Friends: search by username, request, accept, remove, block, report all work and survive relaunch | UI tests + device |
| 6 | Sign out and delete account work online and offline (no hang) | unit tests + device in airplane mode |
| 7 | No crash in a week of use by 3+ testers | TestFlight crash reports (read via API) |
| 8 | UI passes an impeccable native audit with no critical findings; dark mode, Dynamic Type, VoiceOver labels | audit report in docs/design/ |
| 9 | All gates green: BeerKit tests, functions tests, emulator rules tests, cloud compile, UI test screenshots | CI |
| 10 | App Store checklist complete: icon, screenshots, privacy labels, age rating, policy URL | docs/app-store-checklist.md |

## Not in scope (v1)

Stats, leaderboards, streaks, non-beer drinks, group chats, Android, web, photo library
uploads, any tracking or analytics SDK.

## Constraints

- No Mac. Everything from tim-server, GitHub macOS runners, Tim's iPhone.
- Never deploy or ship on a red gate. TestFlight only after an adversarial review pass.
- Production data is real: no fake sign-ins, no test writes to beerwithme-prod.
- Money: Apple 99 USD/yr, Firebase Blaze at free-tier usage, GitHub Actions free (public repo).

## Decisions for Tim (fill in)

- Target date for App Store submission: ____
- First external testers (names/emails for the TestFlight group): ____
- App Store name: PubDates (confirm the App Store Connect record is renamed)
- Taste: a reference app whose feel you like, if any: ____

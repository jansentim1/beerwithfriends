# PubDates Privacy Policy

_Last updated: 2026-10-15_

PubDates is a small app for telling friends you are having a beer. This policy explains
what the app stores, why, and how to get rid of it. It is written to be read, not to be
scrolled past.

## What we collect

| Data | Why | Where it lives |
|---|---|---|
| Apple account identifier (from Sign in with Apple) | To sign you in. We never see your email or password; Sign in with Apple gives us an opaque user id. | Firebase Authentication |
| Username and display name | So friends can find and recognise you. | Firestore `users/{uid}`, `usernames/{name}` |
| Drink logs (timestamps, cheers count, quick replies) | The feed. Each entry is deleted 24 hours after it was logged, or as soon as you log your next drink. It leaves a friend's feed two hours after they first see it; that reading position stays on their phone and is never sent to us. | Firestore `beers/{beerId}` |
| Photos taken in the app | Optional, attached to a beer log. Stored for at most 24 hours. Each friend can view a photo exactly once; the server enforces this. | Firebase Storage `photos/{beerId}.jpg` |
| View and screenshot receipts | A view record is how the server enforces view-once: it has to know who has already looked. A screenshot record is kept alongside it. Neither is shown to anyone in the app today — you see who cheersed or replied, never who looked. Deleted with the drink. | Firestore under `beers/{beerId}` |
| Friend list, friend requests, blocks | To decide whose beers you see and who can see yours. | Firestore |
| Push notification token | To send "X is having a beer" and "Y cheersed you" notifications. Stored in a private subcollection only you and the server can read. Removed on sign-out. | Firestore `users/{uid}/private/push` |
| Place on a drink | Logging a drink asks for your location. If you grant it, the street address you are at and that position rounded to about 100 metres go on the drink. If you refuse, you type where you are instead and no position is stored. Mates see the place in the feed, and a drink with a position also shows on the Map tab. If you are at a named venue its name goes in front of the address. Drinking at home with location granted therefore shares your home address. Only people whose mate request you accepted can read it, and it is deleted with the drink. Nothing is read when you are not logging. | Firestore `beers/{beerId}.place` and `placeCoordinate`, deleted with the drink |
| What you drank | The drink type you picked (pils, wine, cocktail, ...). | Firestore `beers/{beerId}.drink` |
| Username changes | The time of your last username change, to limit changes to once a day. | Firestore `users/{uid}.usernameChangedAt` |
| Reports you file | Trust and safety review. Only the reporter's id, the reported user or beer, and the reason are stored. | Firestore `reports` |
| Groups you join | The Groups tab: group name, join code, your username and nickname as a member, how many drinks you and the group logged today and in total, and the time of your first drink of the day (so the group shows who is out). | Firestore `groups/{groupId}` |

We do not collect your email, contacts, photo library, analytics, or advertising
identifiers. Location is read only at the moment you log a drink, and only if you allow it, to name the place it goes out with. The camera is the only photo source, and only when you tap the camera button.

## What we do not do

- No advertising, no tracking, no selling or sharing of data with third parties.
- No analytics SDKs. The only third party is Google Firebase, which hosts the backend.
- Photos are never shown to anyone except friends you have accepted, once each, within 24 hours.

## Retention

- Beer logs and photos: deleted automatically 24 hours after logging, or when you log your next drink.
- Everything else: kept until you delete your account.

## Deleting your account

Settings, then Delete account. This runs a server function that removes your profile,
username reservation, beers, photos, friendships, requests, blocks, push token and
authentication record. It is immediate and cannot be undone. Reports you filed are kept
without your identifier for abuse-prevention purposes.

## Children

PubDates is about beer and is rated 17+. It is not intended for anyone under the legal
drinking age in their country.

## Security

All data is transferred over TLS. Access is governed by Firebase security rules that
restrict every document to its owner and accepted friends; the rules are tested in the
project's automated test suite.

## Contact

Questions or deletion requests: twj.jansen@gmail.com

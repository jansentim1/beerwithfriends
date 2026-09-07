# Pints With Mates Privacy Policy

_Last updated: 2026-09-04_

Pints With Mates is a small app for telling friends you are having a beer. This policy explains
what the app stores, why, and how to get rid of it. It is written to be read, not to be
scrolled past.

## What we collect

| Data | Why | Where it lives |
|---|---|---|
| Apple account identifier (from Sign in with Apple) | To sign you in. We never see your email or password; Sign in with Apple gives us an opaque user id. | Firebase Authentication |
| Username and display name | So friends can find and recognise you. | Firestore `users/{uid}`, `usernames/{name}` |
| Beer logs (timestamps, cheers count) | The feed. Each entry expires 24 hours after it was logged and is then deleted by a scheduled job. | Firestore `beers/{beerId}` |
| Photos taken in the app | Optional, attached to a beer log. Stored for at most 24 hours. Each friend can view a photo exactly once; the server enforces this. | Firebase Storage `photos/{beerId}.jpg` |
| View and screenshot receipts | So the photo owner can see who viewed their photo and whether a screenshot was taken. Deleted with the beer. | Firestore under `beers/{beerId}` |
| Friend list, friend requests, blocks | To decide whose beers you see and who can see yours. | Firestore |
| Push notification token | To send "X is having a beer" and "Y cheersed you" notifications. Stored in a private subcollection only you and the server can read. Removed on sign-out. | Firestore `users/{uid}/private/push` |
| Reports you file | Trust and safety review. Only the reporter's id, the reported user or beer, and the reason are stored. | Firestore `reports` |

We do not collect your email, contacts, location, photo library, analytics, or advertising
identifiers. The camera is the only photo source, and only when you tap the camera button.

## What we do not do

- No advertising, no tracking, no selling or sharing of data with third parties.
- No analytics SDKs. The only third party is Google Firebase, which hosts the backend.
- Photos are never shown to anyone except friends you have accepted, once each, for 24 hours.

## Retention

- Beer logs and photos: deleted automatically 24 hours after logging.
- Everything else: kept until you delete your account.

## Deleting your account

Settings, then Delete account. This runs a server function that removes your profile,
username reservation, beers, photos, friendships, requests, blocks, push token and
authentication record. It is immediate and cannot be undone. Reports you filed are kept
without your identifier for abuse-prevention purposes.

## Children

BeerWithMe is about beer and is rated 17+. It is not intended for anyone under the legal
drinking age in their country.

## Security

All data is transferred over TLS. Access is governed by Firebase security rules that
restrict every document to its owner and accepted friends; the rules are tested in the
project's automated test suite.

## Contact

Questions or deletion requests: twj.jansen@gmail.com

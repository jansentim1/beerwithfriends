# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

Groups of friends (20s to 40s, Dutch first, English UI) who drink beer together and apart
and want the small social ritual of "I'm having one" without a full social network. The
primary moment: a phone in one hand, a beer in the other, at a bar, a terrace, or the couch;
one thumb, a few seconds, often in bright sunlight or a dark bar. Secondary moment: a push
arrives and you want to cheers back in one tap.

## Product Purpose

PubDates lets you tell your friends you are having a beer with one tap. Friends get a push,
can cheers back (which pushes back to you), and can attach a live camera photo that each
friend may look at exactly once. Everything expires after 24 hours. Success: a group of
friends installs it and keeps using it for weeks because the loop is instant, low-effort
and a little bit fun.

## Positioning

The disappearing, view-once beer photo enforced by the server (not just hidden) plus the
push-and-cheers loop with zero feed scrolling. Not a stats app, not a leaderboard, not a
chat. One button.

## Operating Context

- Sign in with Apple, then a unique username. Friends are added by exact username or an
  invite link; no contacts access, no photo library.
- Native SwiftUI, iOS 17+, iPhone only. Firebase backend in europe-west4.
- Distribution via TestFlight now, App Store later (17+, UGC rules: report and block).
- Tim tests on a real iPhone; screenshots for review come from the CI simulator
  (`.github/workflows/ios-test.yml`) in light and dark mode.

## Capabilities and Constraints

- Screens: Onboarding (sign in, username), Home (drink picker, feed), Camera (live capture,
  review), Photo viewer (view once), Mates (requests, list, search, QR, invite), Map (mates'
  drinks at the bar's position, opt-in), Settings (profile, change username, privacy toggle,
  blocked users, sign out, delete account).
- Drinks: seven kinds (pils, special, wine, bubbles, cocktail, whisky, soft) drawn as vector
  glasses that fill on tap and empty in 15 minutes.
- Feed rows: owner, relative time, photo chip (sealed / seen / none), cheers pill.
- Photos: camera only, JPEG ≤ 1080 px, 24 h, view once per friend, screenshot receipts.
- Terminology: "beer" is the brand noun (app name, Beers tab, "I'm having a beer" copy);
  "drink" is the logged thing when the kind matters (pils, wine, cocktail... "log a drink",
  "N drinks logged", "Report this drink"). "cheers" (🍻) is the reaction; "view once" is the
  photo state; "mates" are friends.
- Hard constraints: no analytics, no tracking, no ads. Everything must work with one thumb.
- Undecided: App Store name confirmed as PubDates for the display name; the App Store
  Connect record still says "Pints With Mates" (Tim to confirm the rename).

## Brand Commitments

- Name: PubDates (bundle id stays com.timjansen.BeerWithFriends).
- Voice: warm, playful, short. Dutch directness in English. Emoji are part of the voice
  (🍺 🍻 📸 👀) but never replace an icon that carries meaning.
- References Tim made binding (2026-09-07): Instagram and Pinterest for polish; Tikkie for
  the friendly, bold, consumer-app warmth. [inferred from "look at how instagram looks and
  pinterest for design ... or like the tikkie app"]
- Icon: current one is a generated placeholder (two clinking pints on amber); to be replaced.

## Evidence on Hand

- Working backend and app on TestFlight (build 5). Real user: Tim. No testimonials, no
  metrics, no press. Do not fabricate any.
- Design spec: docs/superpowers/specs/2026-07-11-beerwithme-design.md. Goal and acceptance
  criteria: docs/GOAL.md.

## Product Principles

1. One thumb, one tap: the log button is the product; everything else is secondary.
2. Instant: optimistic UI everywhere; the network never blocks the ritual.
3. Ephemeral by design: 24 h and view-once are features, the UI should make them legible.
4. Friends, not followers: small groups, exact usernames, no discovery, no numbers to chase.
5. Native first: an iPhone user should never pause at an off-spec control.

## Accessibility & Inclusion

Dynamic Type through the system text styles, VoiceOver labels on every control, 44 pt
targets, Reduce Motion honored, contrast that survives sunlight and dark bars.

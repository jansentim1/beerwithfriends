# PubDates: design direction (v1 redesign, 2026-09-07)

Tim's brief: "look at how Instagram looks and Pinterest for design, or like the Tikkie
app." That is the canon played straight: a native iOS consumer social app at the craft
level of Instagram (feed rows, restraint, photo-forward), Pinterest (generous whitespace,
rounded surfaces, confident imagery) and Tikkie (one big friendly action per screen,
warm copy, a single bold accent). No concept tournament; competitor craft is the bar.

## Direction contract

THESIS (amended 2026-09-10): One row of glasses owns the screen; tapping a glass fills it
and logs the drink; the feed is the story of the last 24 hours, each drink draining as
time passes. Refuses the category default of a scrolling social feed with a small "+"
hidden in a corner.

OWN-WORLD: System backgrounds (white / near-black) with one committed accent, "pint
amber" (light: oklch(0.72 0.17 65) ≈ #E68A00; dark: oklch(0.80 0.16 70) ≈ #FFA733),
carrying the primary button, the sealed-photo chip and the tab tint. Ink is the system
label colour. SF Pro for everything, SF Rounded for the large title and the log button.
Corners 20 pt on the log button and feed cards, 12 pt on chips, fully round on pills.
Avatars are initials on an amber-tinted circle (no photos of people, only of beers).

STORY: "Tap when you crack one open; your mates hear it and cheers back." A first-time
user sees the button, taps it, sees their row appear with a spring, and understands the
loop before reading anything.

FIRST VIEWPORT (Home, amended 2026-09-10): large title "PubDates" collapsing on scroll;
under it one horizontal row of seven drawn glasses (72 pt, label beneath, last pick on a
soft amber tile) ending in a 56 pt round camera cell labelled "Photo"; one footnote "Tap a
glass to log it". Below, the feed: one row per drink, the drink's own glass at 44 pt in a
56 pt amber-wash circle showing the remaining level, name and relative time (with
"📍 place" when shared), right-aligned photo chip (sealed = amber pill "view once", seen
= quiet "seen"), reply pills and a cheers pill "🍻 3". Empty feed: illustration-free
empty state with a single secondary action "Add a mate".

FORM: native iOS canon (system nav, tab bar, sheets), position 1 of 1 by user pin; no
seed key (user-pinned direction, concept-seed not run).

Signature interaction (amended): tapping a glass plays a haptic `.success`, the glass
fills to the brim (liquid level 0.15-ish → 1.0, 350 ms, ease-out-quint), holds, settles
back, and the new row springs in at the top of the feed with its full glass, which then
drains over 24 hours. Reduce Motion: crossfade.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review,
the verdict, DESIGN.md, and every shipping raster carrying its provenance.

## Screen order and what changes

1. Home: hero button + camera, feed rows as above, swipe actions (report / block) in
   addition to the context menu, pull-to-refresh, empty state.
2. Onboarding: sign-in screen with a big rounded wordmark, one-line promise, Sign in with
   Apple at thumb height; username screen with live availability and the notification
   explainer as a quiet footnote.
3. Camera: full-bleed preview, 72 pt shutter, flip and cancel as circular glass buttons,
   review with "Retake" / "Use photo" as a rounded pair.
4. Photo viewer: black, owner name + "view once" pill, tap or swipe down to close.
5. Friends: inset grouped sections (Requests, Mates), avatar initials, search field with
   the exact-username hint, invite via ShareLink as a prominent secondary button.
6. Settings: inset grouped, profile header with big initial, an account row to change the
   username, privacy toggle, blocked users, sign out, delete account (double confirm stays).
7. Map: mates' active drinks as glass pins at the bar's position (opt-in), callout with
   who/what/where and the draining glass; empty state on material.

## Cross-cutting

Dynamic Type via text styles only; 44 pt minimum targets; VoiceOver labels on every
control; dark mode as first-class (system colours, accent tuned per scheme); Reduce
Motion crossfades; haptics on log, cheers, accept.

# PubDates: design direction (v1 redesign, 2026-09-07)

Tim's brief: "look at how Instagram looks and Pinterest for design, or like the Tikkie
app." That is the canon played straight: a native iOS consumer social app at the craft
level of Instagram (feed rows, restraint, photo-forward), Pinterest (generous whitespace,
rounded surfaces, confident imagery) and Tikkie (one big friendly action per screen,
warm copy, a single bold accent). No concept tournament; competitor craft is the bar.

## Direction contract

THESIS: One button owns the screen; the feed is the story of the last 24 hours, not a
timeline. Refuses the category default of a scrolling social feed with a small "+" hidden
in a corner.

OWN-WORLD: System backgrounds (white / near-black) with one committed accent, "pint
amber" (light: oklch(0.72 0.17 65) ≈ #E68A00; dark: oklch(0.80 0.16 70) ≈ #FFA733),
carrying the primary button, the sealed-photo chip and the tab tint. Ink is the system
label colour. SF Pro for everything, SF Rounded for the large title and the log button.
Corners 20 pt on the log button and feed cards, 12 pt on chips, fully round on pills.
Avatars are initials on an amber-tinted circle (no photos of people, only of beers).

STORY: "Tap when you crack one open; your mates hear it and cheers back." A first-time
user sees the button, taps it, sees their row appear with a spring, and understands the
loop before reading anything.

FIRST VIEWPORT (Home): large title "PubDates" collapsing on scroll; under it a full-width
amber log button 64 pt tall with rounded 🍺 "I'm having a beer" and, to its right, a
64 pt round camera button. Below, the feed: one row per beer, 56 pt avatar-initial
circle, name and relative time, right-aligned photo chip (sealed = amber pill "view
once", seen = quiet "seen") and a cheers pill "🍻 3". Empty feed: friendly illustration-free
empty state with a single secondary action "Add a mate".

FORM: native iOS canon (system nav, tab bar, sheets), position 1 of 1 by user pin; no
seed key (user-pinned direction, concept-seed not run).

Signature interaction: tapping the log button plays a haptic `.success`, the button
briefly "fills like a pint" (amber sweep bottom-to-top, 350 ms, ease-out-quint), and the
new row springs in at the top of the feed. Reduce Motion: crossfade.

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
6. Settings: inset grouped, profile header with big initial, blocked users, sign out,
   delete account (double confirm stays).

## Cross-cutting

Dynamic Type via text styles only; 44 pt minimum targets; VoiceOver labels on every
control; dark mode as first-class (system colours, accent tuned per scheme); Reduce
Motion crossfades; haptics on log, cheers, accept.

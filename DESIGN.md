---
name: PubDates
description: One amber button, a 24-hour feed of your mates' beers, and nothing to scroll for.
colors:
  pint-amber: "#E68A00"
  pint-amber-dark: "#FFA733"
  amber-ink: "#A35A00"
  amber-ink-dark: "#FFA733"
  stout-ink: "#291700"
  amber-wash: "rgba(230, 138, 0, 0.14)"
  amber-wash-dark: "rgba(255, 167, 51, 0.18)"
  ground: "#F2F2F7"
  ground-dark: "#000000"
  surface: "#FFFFFF"
  surface-dark: "#1C1C1E"
  glass-on-black: "rgba(255, 255, 255, 0.18)"
typography:
  wordmark:
    fontFamily: "SF Pro Rounded, -apple-system, system-ui, sans-serif"
    fontSize: "44pt (scaled with largeTitle)"
    fontWeight: 800
    lineHeight: 1.1
    letterSpacing: "normal"
  display:
    fontFamily: "SF Pro Rounded, -apple-system, system-ui, sans-serif"
    fontSize: "largeTitle (34pt)"
    fontWeight: 700
    lineHeight: 1.2
  headline:
    fontFamily: "SF Pro Rounded, -apple-system, system-ui, sans-serif"
    fontSize: "title (28pt)"
    fontWeight: 700
    lineHeight: 1.2
  title:
    fontFamily: "SF Pro Rounded, -apple-system, system-ui, sans-serif"
    fontSize: "title2 (22pt)"
    fontWeight: 700
    lineHeight: 1.25
  hero-label:
    fontFamily: "SF Pro Rounded, -apple-system, system-ui, sans-serif"
    fontSize: "title3 (20pt)"
    fontWeight: 700
    lineHeight: 1.25
  row-title:
    fontFamily: "SF Pro Text, -apple-system, system-ui, sans-serif"
    fontSize: "headline (17pt)"
    fontWeight: 600
    lineHeight: 1.3
  body:
    fontFamily: "SF Pro Text, -apple-system, system-ui, sans-serif"
    fontSize: "body (17pt)"
    fontWeight: 400
    lineHeight: 1.3
  secondary:
    fontFamily: "SF Pro Text, -apple-system, system-ui, sans-serif"
    fontSize: "subheadline (15pt)"
    fontWeight: 400
    lineHeight: 1.3
  footnote:
    fontFamily: "SF Pro Text, -apple-system, system-ui, sans-serif"
    fontSize: "footnote (13pt)"
    fontWeight: 400
    lineHeight: 1.35
  label:
    fontFamily: "SF Pro Text, -apple-system, system-ui, sans-serif"
    fontSize: "caption (12pt)"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "0.6pt"
rounded:
  hero: "20pt"
  card: "16pt"
  chip: "12pt"
  pill: "9999pt"
spacing:
  hairline: "2pt"
  xs: "4pt"
  sm: "8pt"
  md: "12pt"
  lg: "16pt"
  xl: "20pt"
  xxl: "24pt"
components:
  button-hero:
    backgroundColor: "{colors.pint-amber}"
    textColor: "{colors.stout-ink}"
    typography: "{typography.hero-label}"
    rounded: "{rounded.hero}"
    height: "64pt"
    width: "100%"
  button-hero-pressed:
    backgroundColor: "{colors.pint-amber}"
    textColor: "{colors.stout-ink}"
    size: "97%"
  button-round-icon:
    backgroundColor: "{colors.amber-wash}"
    textColor: "{colors.amber-ink}"
    rounded: "{rounded.pill}"
    size: "64pt"
  pill-filled:
    backgroundColor: "{colors.pint-amber}"
    textColor: "{colors.stout-ink}"
    typography: "{typography.secondary}"
    rounded: "{rounded.pill}"
    padding: "0 14pt"
    height: "36pt"
  pill-tinted:
    backgroundColor: "{colors.amber-wash}"
    textColor: "{colors.amber-ink}"
    typography: "{typography.secondary}"
    rounded: "{rounded.pill}"
    padding: "0 14pt"
    height: "36pt"
  pill-quiet:
    backgroundColor: "rgba(120, 120, 128, 0.12)"
    textColor: "rgba(60, 60, 67, 0.6)"
    typography: "{typography.secondary}"
    rounded: "{rounded.pill}"
    padding: "0 14pt"
    height: "36pt"
  status-pill:
    backgroundColor: "rgba(120, 120, 128, 0.12)"
    textColor: "rgba(60, 60, 67, 0.6)"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "0 10pt"
    height: "28pt"
  avatar:
    backgroundColor: "{colors.amber-wash}"
    textColor: "{colors.amber-ink}"
    rounded: "{rounded.pill}"
    size: "48pt"
  field-card:
    backgroundColor: "{colors.surface}"
    typography: "{typography.body}"
    rounded: "{rounded.card}"
    padding: "0 14pt"
    height: "52pt"
  eyebrow:
    textColor: "rgba(60, 60, 67, 0.6)"
    typography: "{typography.label}"
---

# Design System: PubDates

## Overview

**Creative North Star: "The One Big Button"**

PubDates is a native iOS consumer app played straight at the craft level of Instagram, Pinterest and Tikkie: system backgrounds, system type, system navigation, and a single committed accent doing all the talking. The one idea that owns every screen is that there is one thing to do here. On Home the amber log button is the product; the feed under it is the story of the last 24 hours rather than a timeline to scroll. Every other surface (Mates, Settings, Camera, the view-once photo) is quieter on purpose, so the button stays the loudest thing in the app.

The material is flat and tonal. There are no shadows anywhere; depth is carried by the difference between the grouped ground and the white (or near-black) surface cards, and by amber washes that lift a control without lifting it off the page. Corners are large and continuous (20 pt on the hero, 16 pt on cards, capsules on everything pill-shaped), which is what makes the app feel friendly rather than corporate. Dark mode is first class: the accent is re-tuned per scheme rather than dimmed, and the feed reads identically on white and on black.

The voice is warm, short and Dutch-direct in English: "I'm having a beer", "Nobody to hear you yet", "Add a mate". Emoji (🍺 🍻 📸 👀) are part of the voice, sitting inside labels next to words; they never replace an icon that carries meaning on its own.

**Key Characteristics:**
- One accent (pint amber), re-tuned per colour scheme, split into a fill role and a text role.
- Flat, tonal depth: grouped ground vs. surface card, amber wash for lift, no shadows.
- SF Pro for reading, SF Rounded bold for anything that names or commands.
- Large continuous corners: 20 pt hero, 16 pt card, capsule pills.
- Native iOS canon throughout: large collapsing titles, inset grouped lists, tab bar, sheets, swipe actions.
- Motion is a spring for arrivals and a 350 ms "pour" for the hero tap; Reduce Motion degrades to a flash and a crossfade.

## Colors

One accent on system neutrals; the accent has two roles (fill and ink) so it stays legible in sunlight and dark bars.

### Primary
- **Pint Amber** (`pint-amber`, light; `pint-amber-dark`, dark): the fill accent. Carries the hero log button, the filled "📸 View once" chip, the Accept and Add pills when they are live, the tab bar tint, and the Report swipe action. Tuned per scheme so it reads as the same beer on white and on black.
- **Stout Ink** (`stout-ink`): the ink on top of Pint Amber. Always dark regardless of scheme, so the hero label reads at 6.5:1 in light mode and 8.9:1 in dark mode.
- **Amber Ink** (`amber-ink`, light; `amber-ink-dark`, dark): amber as words and glyphs. Used for avatar initials, tinted-pill labels, the round camera button glyph, Settings row icons and link text, and the "Not you? Sign out" link. It is darker than the fill in light mode (5.2:1 on white, 4.6:1 on the amber wash) and identical to the fill in dark mode, where the bright amber already clears the bar on black.
- **Amber Wash** (`amber-wash`, light; `amber-wash-dark`, dark): the soft amber tint behind avatar circles, the round camera button, tinted pills (cheers, Invite a mate, Add with QR, Unblock) and the 88 pt onboarding badge. Never carries text other than Amber Ink.

### Neutral
- **Ground** (`ground` / `ground-dark`): `systemGroupedBackground`. The page behind inset grouped lists and the onboarding screens.
- **Surface** (`surface` / `surface-dark`): `secondarySystemGroupedBackground`. Inset grouped cards and the rounded text-field card on the username screen. Home uses a plain list on the system background, so its rows sit directly on white or black.
- **Label / Secondary label**: system `.primary` and `.secondary`. All body copy, row titles, relative times, footnotes and section headers.
- **Tertiary fill**: `tertiarySystemFill` behind quiet pills, the status pill and the beer counter.
- **Glass on black** (`glass-on-black`): white at 18% for the "View once" pill and the close button in the photo viewer; the camera uses the equivalent `systemUltraThinMaterialDark` blur behind its flip, cancel and Retake buttons.
- **System red**: the destructive tint (Block swipe action, Delete account, Remove mate, the "Taken" availability line). Green marks "Available 🍻"; orange marks an unverifiable check. These are system semantics, not brand colours.

### Named Rules
**The Fill-Or-Ink Rule.** Pint Amber is a fill; Amber Ink is a word. Any amber that carries text or a glyph on a light background uses `amber-ink`, never `pint-amber` (which is only 2.3:1 on white). The Settings list is tinted with `amber-ink` for exactly this reason; the tab bar is tinted with `pint-amber` because it renders on a blurred material. If a control has amber on both sides (fill and label), the label is Stout Ink.

**The One Loud Thing Rule.** On any screen at most one control is filled Pint Amber and full width. Home has the hero; the username screen has "Claim it"; the profile-unavailable screen has "Try again". Everything else on the same screen is tinted, quiet, or plain text.

**The Wash Ceiling Rule.** Amber Ink on Amber Wash clears WCAG AA at 4.6:1 with thin headroom. Do not darken the wash, lighten the ink, or stack a wash on a wash; if a new state needs more presence, step up to a filled pill with Stout Ink rather than tinting harder.

## Typography

**Display Font:** SF Pro Rounded, bold (with the system sans fallback)
**Body Font:** SF Pro Text (the system text styles, unchanged)
**Label Font:** SF Pro Text, semibold caption

**Character:** A friendly consumer pairing. Rounded bold names and commands (the wordmark, the large titles, the hero label, avatar initials); regular SF Pro carries everything you read. Every face is bound to a Dynamic Type text style, so the ramp scales as one; the only fixed-size faces are the avatar initials (40% of the circle) and the camera's UIKit controls.

### Hierarchy
- **Wordmark** (heavy, 44 pt scaled with largeTitle, single line with 0.5 minimum scale): the "PubDates" mark on the sign-in screen only.
- **Display** (rounded bold, `.largeTitle`): navigation large titles ("PubDates", "Mates", "Settings") via the nav bar appearance installed at launch, and the "Pick your username" title.
- **Headline** (rounded bold, `.title`): the profile-unavailable screen title.
- **Title** (rounded bold, `.title2`): the Home empty-state headline ("Nobody to hear you yet") and the Settings profile name.
- **Hero label** (rounded bold, `.title3`): the label inside every HeroButtonStyle button.
- **Row title** (`.headline`, semibold): feed row owner names, mate and request names, the photo viewer owner name.
- **Body** (`.body`): onboarding copy, text fields, Settings rows.
- **Secondary** (`.subheadline`): relative times, usernames, empty-state explanations, pill labels (semibold inside pills).
- **Footnote** (`.footnote`): hints under fields, the sign-in reassurance, the version footer, the photo viewer sub-line.
- **Label** (`.caption` semibold, 0.6 pt tracking, uppercase in Eyebrow): section headers in the Mates list and the text inside status pills (not uppercased there).

### Named Rules
**The Rounded-Names Rule.** SF Rounded is reserved for things that name or command: the wordmark, large titles, empty-state headlines, the profile name, the hero label and avatar initials. Row text, copy, hints and pills stay in SF Pro Text so the rounded face keeps its meaning.

**The Text-Style Rule.** Every font is a system text style (`.largeTitle` … `.caption`) or a `@ScaledMetric` relative to one. A raw point size is allowed only inside a fixed-size circle (avatar initials, the 88 pt badge glyph) or in the UIKit camera layer.

## Layout

Single-column iPhone layouts inside native containers. Every tab is a `NavigationStack` with a large title that collapses on scroll; the tab bar carries three items (Beers, Mates, Settings) tinted Pint Amber.

- **Home**: the hero row (amber log button, 64 pt tall, plus a 64 pt round camera button, 12 pt apart) lives inside the scroll view so the large title collapses natively. Under it a plain list (`.plain`, separators hidden) with one row per beer: 56 pt avatar, name over relative time, then the photo chip and the cheers pill on the right, 8 pt apart. Row insets are 10 pt vertical, 16 pt horizontal. At accessibility Dynamic Type sizes the row's trailing controls drop under the text into a vertical stack aligned leading. The empty state sits in the top half of the screen (min height 50% of the list) with a title, one line of copy and a single tinted pill.
- **Mates and Settings**: `.insetGrouped` lists. Rows use 12 pt between avatar and text, 2 pt between name and username, and 4 to 6 pt vertical row padding. Settings opens with a centred profile header (72 pt avatar, name, @username, beer counter) at 12 pt spacing.
- **Onboarding**: content centred in the upper part of a scroll view with 24 pt horizontal padding; the action stack is pinned at thumb height with 20 pt horizontal, 8 pt top, 12 pt bottom padding. Sign in with Apple is 56 pt tall and shares the hero's 20 pt radius so the two geometries match. The username form is a leading-aligned column at 24 pt spacing with 20 pt horizontal padding.
- **Camera**: full-bleed black preview with a 72 pt shutter (60 pt white core, 4 pt white ring), 48 pt glass circles for flip and cancel, and a 52 pt "Retake / Use photo" capsule pair in review.
- **Photo viewer**: black, status bar hidden, a 16 pt-inset header row (36 pt avatar, name, "View once" pill, 44 pt close circle) over the image; tap or drag down dismisses.

**Spacing rhythm**: 2 (name to username), 4, 8, 10, 12, 16, 20, 24 pt. 12 pt is the default gap between siblings in a row; 16 pt is the list content inset; 20 to 24 pt is the screen margin on onboarding.

**Touch targets**: every tappable control declares `minHeight: 44` (or `44 × 44` for icons) even where the visible pill is 36 pt tall; the hit area is bigger than the paint.

### Named Rules
**The Hero-Under-Title Rule.** The primary action sits directly under the large title, inside the scroll content, full width minus the camera button. It is never a floating button, never in a toolbar, never hidden behind a "+".

**The 44-Point Rule.** Visible height may be 28, 36 or 52 pt; the hit target is never under 44 pt.

## Elevation & Depth

Flat, with tonal layering and no shadows. Depth comes from three moves: the grouped ground against the surface card (inset grouped lists, the field card), the amber wash lifting a control off the surface without a shadow, and material blur (`systemUltraThinMaterialDark`, or white at 18%) over the camera preview and the black photo viewer. Pressed states compress in place (scale 0.97 on the hero, 0.94 on the round button, 0.95 on pills) instead of casting anything.

### Named Rules
**The No-Shadow Rule.** Nothing casts a shadow. A control that needs to read as raised gets an amber wash, a surface card, or a glass material, in that order of preference.

## Shapes

Large, continuous (superellipse) corners and true capsules. The hierarchy is: hero and Sign in with Apple at 20 pt (`hero`), surface cards and the field card at 16 pt (`card`), and every pill, chip, status badge, avatar and icon button as a capsule or circle. No borders anywhere except the camera shutter's 4 pt white ring; separators are hidden on Home and left to the system in grouped lists.

The 12 pt `chip` radius is declared in the theme but no shipped surface uses it: every chip in the build is a capsule. Treat 12 pt as reserved for a future non-capsule chip (for example a thumbnail chip) rather than as an existing shape.

Motion belongs with the shapes it moves: `Theme.spring` (response 0.42, damping 0.78) for rows arriving and requests resolving; `Theme.quick` (ease-out 0.18 s) for press scale, availability changes and enable/disable fades; `Theme.pour` (cubic-bezier 0.22, 1, 0.36, 1 over 0.35 s) only for the hero's fill sweep. Under Reduce Motion the sweep becomes a full-height flash that fades on `quick`, and feed insertion animates on `quick` instead of the spring.

## Components

### Buttons
Tactile and confident: they press down, they never glow.
- **Shape:** hero 20 pt continuous corners; everything else a capsule or circle.
- **Hero (`HeroButtonStyle`):** full width, min 64 pt, Pint Amber fill, Stout Ink label in the rounded title3 face. Signature "pour": each tap bumps a counter and a white-at-28% highlight sweeps from the bottom edge to the top over 350 ms on the pour curve, then fades over 250 ms; `isBusy` holds the highlight steady while a photo uploads. Pressed: scale 0.97 on `quick`. Disabled states dim to 50 to 70% opacity rather than changing colour.
- **Round icon (`RoundIconButtonStyle`):** 64 pt circle (size configurable), Amber Wash fill, Amber Ink glyph at 36% of the diameter, semibold. Used for the camera shortcut beside the hero. Pressed: scale 0.94.
- **Sign in with Apple:** the system button, 56 pt tall, clipped to the 20 pt hero radius so it reads as the same family as the hero.
- **Camera (UIKit):** 72 pt shutter with a white 4 pt ring and 60 pt white core; 48 pt glass circles (ultra-thin dark material, white glyph) for flip and cancel; a 52 pt capsule pair for Retake (glass) and Use photo (Pint Amber with Stout Ink).

### Chips
Pills (`PillButtonStyle`) carry every secondary action and reaction. Subheadline semibold, 14 pt horizontal padding, 36 pt visible height inside a 44 pt target, capsule.
- **Filled:** Pint Amber with Stout Ink. The sealed "📸 View once" photo chip, Accept on a request, Add when a username is valid, Use photo.
- **Tinted:** Amber Wash with Amber Ink. Cheers "🍻 n", Add a mate, Invite a mate, Add with QR, Unblock.
- **Quiet:** tertiary system fill with secondary label. Decline, an already-cheered beer (also disabled), Add while the field is empty, the test sign-in.
- **State:** the same pill changes emphasis with state (`canAdd ? .filled : .quiet`, `cheered ? .quiet : .tinted`) on `quick`; the label never changes colour independently of its background.

### Status pill (`StatusPill`)
Non-interactive counterpart to the quiet pill: caption semibold, secondary label, 10 pt horizontal padding, 28 pt tall, tertiary fill capsule. "Seen" on a viewed photo, "🍻 n" on your own beer's cheers count, "n beers logged" under the profile. In the photo viewer the same shape is white at 18% with white text.

### Avatar (`AvatarView`)
Initials (up to two, uppercased) in rounded bold at 40% of the diameter, Amber Ink on an Amber Wash circle; a 🍺 glyph when there is no name. Sizes in use: 36 (blocked rows, photo viewer), 44 (mates and requests), 56 (feed rows), 72 (Settings header). No photos of people, only of beers. The avatar is hidden from VoiceOver; the row label carries the name.

### Cards / Containers
- **Corner Style:** 16 pt continuous (`card`); inset grouped rows inherit the system's grouped radius.
- **Background:** Surface on Ground.
- **Shadow Strategy:** none (see Elevation & Depth).
- **Border:** none.
- **Internal Padding:** 14 pt horizontal in the field card; 4 to 8 pt vertical inside list rows.

### Inputs / Fields
- **Style:** the username and display-name fields sit in a Surface card at 16 pt radius, 52 pt min height, body text, 14 pt horizontal padding; the username field is prefixed with a secondary "@". The Mates search row is a native inset grouped row with a secondary magnifying glass, a plain text field and a trailing Add pill.
- **Focus:** system caret and keyboard; no border shift or glow.
- **Validation:** a footnote line under the field switches on `quick` between a secondary hint, "Checking…" with a spinner, green "Available 🍻", red "Taken — try another.", and orange for an unverifiable check.

### Navigation
- **Large titles** in rounded bold via `Theme.installNavigationBarAppearance()` (inline titles rounded semibold headline); default bar background; titles collapse on scroll.
- **Tab bar:** three items with filled SF Symbols (mug, person.2, gearshape), labels "Beers", "Mates", "Settings", tinted Pint Amber.
- **Lists:** Home is `.plain` with hidden separators and trailing swipe actions (Block in red, Report in Pint Amber) mirrored in the context menu; Mates and Settings are `.insetGrouped`.
- **Sheets and dialogs:** system sheets for the camera and photo viewer; system confirmation dialogs for Report, Block, Remove mate, Sign out and the double Delete account confirm.

### Eyebrow (`Eyebrow`)
The section header above groups in the Mates list: caption semibold, 0.6 pt tracking, uppercased, secondary colour ("ADD A MATE", "REQUESTS", "MATES"). It is the native grouped-list header restated in code and is used only as a list section header, never as a kicker above a headline. Settings uses the system `Section("…")` headers, which iOS 17 renders in title case; the two styles coexist in the build (see the not-canonized note below).

### Feed row (signature)
The row that tells the story: 56 pt avatar, headline name ("You" for your own), subheadline relative time, then on the trailing edge the photo chip (filled "📸 View once", quiet "Seen", or nothing) and the reaction pill (tinted "🍻 n" you can tap, quiet once you have cheered, a status pill on your own beer). New rows spring in at the top; a cheers tap fires a light haptic; a log fires `.success`.

## Do's and Don'ts

### Do:
- **Do** use `Theme.accent` only for fills and `Theme.accentInk` for any amber text or glyph on a light background (the Fill-Or-Ink Rule).
- **Do** keep exactly one full-width Pint Amber control per screen; demote every other action to a tinted or quiet pill.
- **Do** bind every font to a text style (`Theme.displayLarge`, `.headline`, `.subheadline`, `.caption`) or a `@ScaledMetric`, and let rows re-stack vertically at accessibility sizes.
- **Do** give every tappable control a 44 pt minimum target and a VoiceOver label that says what happens ("Log a beer with a photo", "View photo once").
- **Do** animate arrivals with `Theme.spring`, state changes with `Theme.quick`, and reserve `Theme.pour` for the hero; branch on Reduce Motion to a flash or crossfade.
- **Do** keep copy short and warm, with "beer", "mates", "cheers" and "view once" as the only nouns for those things, and emoji inside labels beside words.

### Don't:
- **Don't** put Pint Amber text on white or on the amber wash; it fails contrast at 2.3:1.
- **Don't** add shadows, borders or gradients to lift a control; use a wash, a surface card or a glass material.
- **Don't** introduce a second accent or use system blue; destructive stays system red, availability uses system green and orange, and nothing else gets a colour.
- **Don't** use a photo of a person anywhere; avatars are initials on amber.
- **Don't** use "drink", "post", "like" or "followers"; the words are beer, log, cheers, mates.
- **Don't** float the primary action or hide it in a toolbar; it lives full width under the large title.
- **Don't** use the Eyebrow as a kicker above a title or outside a list section header.

<!-- Not canonized: the app icon is a generated placeholder (two pints on amber) and is not part of this system; Settings' title-case system section headers and Mates' uppercase Eyebrow are both in the build and the split is left open rather than recorded as a rule; the photo viewer and chip states have no simulator captures yet, so their values above are from code; the 12 pt chip radius is declared but unused. -->

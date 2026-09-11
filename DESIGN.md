---
name: PubDates
description: A row of drawn glasses; tap one and your mates hear it; each glass empties in 15 minutes, the row stays two hours.
colors:
  pint-amber: "#E68A00"
  pint-amber-dark: "#FFA733"
  amber-ink: "#A35A00"
  amber-ink-dark: "#FFA733"
  stout-ink: "#291700"
  amber-wash: "rgba(230, 138, 0, 0.14)"
  amber-wash-dark: "rgba(255, 167, 51, 0.18)"
  ground: "#F2F2F7"
  ground-dark: "#151517"
  surface: "#FFFFFF"
  surface-dark: "#262629"
  glass-on-black: "rgba(255, 255, 255, 0.18)"
  glass-outline: "rgba(0, 0, 0, 0.55)"
  glass-outline-dark: "rgba(255, 255, 255, 0.55)"
  glass-body: "rgba(0, 0, 0, 0.05)"
  glass-body-dark: "rgba(255, 255, 255, 0.05)"
  liquid-special: "#8C3808"
  liquid-special-dark: "#B85414"
  liquid-wine: "#731430"
  liquid-wine-dark: "#9E2145"
  liquid-bubbles: "#EDD180"
  liquid-bubbles-dark: "#F5DE94"
  liquid-cocktail: "#99CF8F"
  liquid-cocktail-dark: "#A8DE9E"
  liquid-whisky: "#BD701C"
  liquid-whisky-dark: "#D98A2E"
  liquid-soft: "#472617"
  liquid-soft-dark: "#8F5736"
  foam: "#FCFAF0"
  foam-dark: "#F0EBDE"
typography:
  wordmark:
    fontFamily: "SF Pro Rounded, -apple-system, system-ui, sans-serif"
    fontSize: "44pt (@ScaledMetric relative to largeTitle)"
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
    fontWeight: 400
    lineHeight: 1.35
rounded:
  hero: "20pt"
  card: "16pt"
  chip: "12pt"
  pill: "9999px"
  circle: "50%"
spacing:
  xxs: "2pt"
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
  button-round-icon:
    backgroundColor: "{colors.amber-wash}"
    textColor: "{colors.amber-ink}"
    rounded: "{rounded.circle}"
    size: "56pt"
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
    backgroundColor: "rgba(118, 118, 128, 0.12)"
    textColor: "rgba(60, 60, 67, 0.6)"
    typography: "{typography.secondary}"
    rounded: "{rounded.pill}"
    padding: "0 14pt"
    height: "36pt"
  status-pill:
    backgroundColor: "rgba(118, 118, 128, 0.12)"
    textColor: "rgba(60, 60, 67, 0.6)"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "0 10pt"
    height: "28pt"
  avatar:
    backgroundColor: "{colors.amber-wash}"
    textColor: "{colors.amber-ink}"
    rounded: "{rounded.circle}"
    size: "44pt"
  picker-tile-favourite:
    backgroundColor: "{colors.amber-wash}"
    textColor: "{colors.amber-ink}"
    typography: "{typography.label}"
    rounded: "{rounded.chip}"
    padding: "6pt 2pt"
    width: "66pt"
  feed-glass-disc:
    backgroundColor: "{colors.amber-wash}"
    rounded: "{rounded.circle}"
    size: "56pt"
  map-pin:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.circle}"
    size: "36pt"
  field-card:
    backgroundColor: "{colors.surface}"
    typography: "{typography.body}"
    rounded: "{rounded.card}"
    padding: "0 14pt"
    height: "52pt"
---

# Design System: PubDates

## Overview

**Creative North Star: "The Row of Glasses"**

PubDates is a native iOS consumer app played straight at the craft level of Instagram, Pinterest and Tikkie: system backgrounds, system type, system navigation, one committed accent. What owns the screen is a horizontal row of seven drawn glasses under the large title. Every glass rests empty (the label under it names the drink); tapping one fills it to the brim, opens the camera, and the new row springs in at the top of the feed with the same glass full. Over the next 15 minutes that glass drains, on the feed row and on the map pin; the row stays two hours, and it is the only row that person has: a new drink replaces the old one. The feed is who is drinking right now, not a timeline to scroll; the camera is the last cell beside the row, not a competing control.

The material is flat and tonal. Nothing casts a shadow; depth comes from the grouped ground against a surface card, from amber washes that lift a control without lifting it off the page, and from system material blur over the map and the camera. Corners are large and continuous (20 pt hero, 16 pt card, 12 pt on the favourite tile, capsules on every pill). Dark mode is first class: the accent, the wash, every liquid and the foam are re-tuned per scheme rather than dimmed, and the glasses read as the same drinks on white and on black.

The glasses are the only place in the app with colour beyond amber, and they are content, not chrome: burgundy is wine, pale gold is bubbles, cola brown is a soft drink. Chrome stays amber, ink and system neutrals. The voice is warm, short and Dutch-direct in English: "Tap a glass to log it", "Nobody to hear you yet", "Add a mate", "Claim it 🍺". Emoji (🍺 🍻 📸 👀 📍) sit inside labels next to words and never replace an icon that carries meaning on its own.

**Key Characteristics:**
- One accent (pint amber) re-tuned per scheme, split into a fill role and a text role; the drawn glasses are the only other colour, and they are content.
- The hero is a scrolling row of seven vector glasses with a pinned round camera cell; every logged drink carries its glass, emptying in 15 minutes.
- Flat, tonal depth: ground vs. surface, amber wash for lift, material blur over map and camera, no shadows.
- SF Pro for reading, SF Rounded bold for everything that names or commands (large titles, empty-state headlines, the hero label, initials).
- Large continuous corners: 20 pt hero, 16 pt card, 12 pt favourite tile, capsules and circles everywhere else.
- Native iOS canon throughout: five-tab bar, large collapsing titles, plain list on Home, inset grouped elsewhere, sheets with detents, swipe actions and context menus.
- Motion is a 350 ms pour on the glass level, a spring on row arrival, a once-a-minute drain tick (each glass empties in 15 minutes), and a fade on the glass leaving the row; Reduce Motion cuts every one of them to a 180 ms state change.

## Colors

One accent on system neutrals, with two roles (fill and ink) so it stays legible in sunlight and dark bars; seven liquid colours that are drink content, not chrome.

### Primary
- **Pint Amber** (`pint-amber` light, `pint-amber-dark` dark): the fill accent. Carries the liquid in the pils glass, the filled "📸 View once" chip, Accept and Add pills when they are live, the "Use photo" and "Open Settings" capsules in the camera, the Share-place toggle, the tab bar tint, the Report swipe action, and the count badge on a map pin. Also the fill of `HeroButtonStyle` where it still ships (see Components). Tuned per scheme so it reads as the same beer on white and on black.
- **Stout Ink** (`stout-ink`): the ink on top of Pint Amber, always dark regardless of scheme (6.5:1 on the light fill, 8.9:1 on the dark fill). Hero labels, filled-pill labels, the pin count badge.
- **Amber Ink** (`amber-ink` light, `amber-ink-dark` dark): amber as words and glyphs. The favourite glass's caption, the camera cell glyph, avatar initials, tinted-pill labels, the Settings list tint (row glyphs and link text), the "Not you? Sign out" link, the bell glyph on the notification footnote. Measured at 5.2:1 on white and 4.6:1 on the amber wash in light mode; identical to the fill in dark mode, where bright amber already clears the bar on black.
- **Amber Wash** (`amber-wash` light, `amber-wash-dark` dark): the soft tint behind the favourite glass tile, the 56 pt camera cell, the 56 pt disc around a feed glass, the disc under a map pin, every avatar, every tinted pill, and the 88 pt onboarding badge. It carries Amber Ink or a drawn glass, never Pint Amber text.

### Secondary: the liquids
Content colours: each drink is an explicit, scheme-aware liquid, lifted in dark mode so no glass reads as a hole. They appear only inside `DrinkGlassView`.
- **Pils**: Pint Amber itself (the house colour is a pint).
- **Special beer** (`liquid-special`, `liquid-special-dark`): deep amber, a dubbel or a bock.
- **Wine** (`liquid-wine`, `liquid-wine-dark`): burgundy.
- **Bubbles** (`liquid-bubbles`, `liquid-bubbles-dark`): pale gold, with three static white (75%) bubbles standing in the flute.
- **Cocktail** (`liquid-cocktail`, `liquid-cocktail-dark`): pale green in a martini cone.
- **Whisky** (`liquid-whisky`, `liquid-whisky-dark`): caramel in a tumbler.
- **Soft drink** (`liquid-soft`, `liquid-soft-dark`): cola brown, with a stroked bendy straw.
- **Foam** (`foam`, `foam-dark`): cream rather than pure white, the head on a pils or a special beer, so it reads on both grounds.
- **Glass outline** (`glass-outline`, `glass-outline-dark`): the system label colour at 55%, stroked at 2.8% of the glass height (2 pt at 72 pt, 1.2 pt at 44 pt), round caps and joins. **Glass body** (`glass-body`, `glass-body-dark`): label at 5%, the fill of the empty cavity.

### Neutral
- **Ground** (`ground` / `ground-dark`): `systemGroupedBackground`. Behind inset grouped lists, onboarding, the QR sheet and the change-username sheet.
- **Surface** (`surface` / `surface-dark`): `secondarySystemGroupedBackground`. Inset grouped cards, the rounded field card, the disc under a map pin. Home is a plain list, so its rows sit directly on the system background.
- **Label / Secondary / Tertiary label**: system `.primary`, `.secondary`, `.tertiary`. Copy, row titles, relative times, glass captions, footnotes, the chevron on the Username row.
- **Tertiary fill**: `tertiarySystemFill` behind quiet pills, status pills and the drink counter.
- **Glass on black** (`glass-on-black`): white at 18% for the "👀 View once" pill and the close circle in the photo viewer; the camera uses `systemUltraThinMaterialDark` behind cancel, flip and Retake. The map's empty-state card uses `regularMaterial`.
- **System red, green, orange**: destructive tint (Block, Delete account, Remove mate, "Taken"), "Available 🍻", and an unverifiable check. Semantics, not brand.

### Named Rules
**The Fill-Or-Ink Rule.** Pint Amber is a fill; Amber Ink is a word. Any amber that carries text or a glyph on a light background uses `amber-ink`, never `pint-amber` (2.3:1 on white). Settings tints its list with `amber-ink` and its toggle with `pint-amber` for exactly this reason. If a control has amber on both sides, the label is Stout Ink.

**The Content Colour Rule.** Colour beyond amber lives only inside a drawn glass. Burgundy, gold, green, caramel and cola are liquids; they never become a badge, a chart, a tint or a second accent. The pils liquid is the accent, which is what makes the row read as one family.

**The Wash Ceiling Rule.** Amber Ink on Amber Wash clears WCAG AA at 4.6:1 with thin headroom. Do not darken the wash, lighten the ink, or stack a wash on a wash; when a state needs more presence, step up to a filled pill with Stout Ink.

## Typography

**Display Font:** SF Pro Rounded, bold (system sans fallback)
**Body Font:** SF Pro Text (the system text styles, unchanged)
**Label Font:** SF Pro Text caption (regular under the glasses, semibold in pills and eyebrows)

**Character:** A friendly consumer pairing. Rounded bold for the things that name or command (the wordmark, every large title, the empty-state headlines, the hero label, initials, the pin count); regular SF Pro for everything you read. Every face is bound to a Dynamic Type text style, so the ramp scales as one; fixed sizes exist only inside fixed circles (initials at 40% of the diameter, the 11 pt pin count) and in the UIKit camera layer.

### Hierarchy
- **Wordmark** (rounded heavy, 44 pt scaled with largeTitle, one line, 0.5 minimum scale): "PubDates" on the sign-in screen only.
- **Display** (rounded bold, `.largeTitle`): navigation large titles ("PubDates", "Mates", "Map", "Settings") via the nav bar appearance installed at launch, and "Pick your username". Inline titles ("Add with QR") are rounded semibold headline.
- **Headline** (rounded bold, `.title`): the profile-unavailable title.
- **Title** (rounded bold, `.title2`): empty-state headlines on Home and Map, the Settings profile name, the QR sheet's @username, a map callout's place name, "New username" on the change sheet, camera-denied notices.
- **Hero label** (rounded bold, `.title3`): the label inside `HeroButtonStyle`.
- **Row title** (`.headline` semibold): names on feed rows, mate and request rows, callout rows, the photo viewer.
- **Body** (`.body`): onboarding copy, text fields, Settings rows, camera-denied copy.
- **Secondary** (`.subheadline`): relative time and place on a row, usernames, empty-state explanations, the drink name in a callout; semibold inside pills.
- **Footnote** (`.footnote`): "Tap a glass to log it", field hints, the sign-in reassurance, the once-a-day note, the version footer, callout times.
- **Label** (`.caption`): captions under the seven glasses and the camera cell (regular, secondary, one line, 0.7 minimum scale, Amber Ink on the favourite); semibold in status pills; semibold, uppercase, 0.6 pt tracking in the Mates eyebrows.

### Named Rules
**The Rounded-Names Rule.** SF Rounded is reserved for things that name or command: wordmark, large titles, empty-state and sheet headlines, the profile name, the hero label, initials, the pin count. Row text, copy, hints, captions and pills stay in SF Pro Text so the rounded face keeps its meaning.

**The Text-Style Rule.** Every font is a system text style or a `@ScaledMetric` relative to one. A raw point size is allowed only inside a fixed circle or in the UIKit camera layer.

## Layout

Single-column iPhone layouts inside native containers. Every tab is a `NavigationStack` with a large title that collapses on scroll; the tab bar carries five items (Beers, Mates, Map, Settings) tinted Pint Amber.

- **Home** (`.plain` list, separators hidden): the hero row lives inside the list so the title collapses natively, with row insets 4 pt top, 16 pt sides, 20 pt bottom. It is a bottom-aligned `HStack` at 8 pt: the horizontal glass row, then the camera cell pinned outside the scroll so it is always in the first viewport (the glasses scroll beside it and the next one peeks). Under the row, one footnote "Tap a glass to log it" at 8 pt. The feed follows with no eyebrow: one row per drink at 10 pt vertical, 16 pt horizontal insets; 56 pt glass disc, name over time, then chip, reply pills and cheers pill on the trailing edge at 8 pt. At accessibility Dynamic Type sizes the trailing controls drop under the name into a leading-aligned column. The empty state claims at least half the viewport under the hero, with 24 pt insets, a title, one line and one tinted pill.
- **Glass row** (`DrinkPickerView`): cells at a 66 pt minimum width on a 2 pt gap, each a 56 × 72 pt bottom-aligned glass frame over a caption at 4 pt, padded 6 pt vertical and 2 pt horizontal; the row has 4 pt vertical and 12 pt trailing padding. `scrollTargetLayout` with `.viewAligned` paging so a flick lands on a glass; indicators hidden. Sized so four glasses fit beside the 56 pt camera cell and the fifth peeks by about 20 pt.
- **Mates and Settings**: `.insetGrouped` lists. Rows use 12 pt between avatar and text, 2 pt between name and username, 4 to 6 pt vertical row padding. Settings opens with a centred header (72 pt avatar, name, @username, drink counter at 12 pt spacing, 12 pt vertical padding, no section header) and then an "Account details" group whose Username row is label, secondary value and a tertiary chevron at a 44 pt minimum height.
- **Map**: the map fills the tab under the large title, flat standard style (the system swaps to the dark map itself), with the user-location button and compass as the only controls. The empty-state card floats at the centre on `regularMaterial`, 20 pt padding, 340 pt maximum width, 24 pt outer margin, and lets pans and pinches through. A tapped pin opens a sheet at `.fraction(0.25)` and `.medium` detents with a drag indicator, 16 pt horizontal and 20/16 pt vertical padding.
- **Onboarding**: hero centred in the upper part of a scroll view (18% top spacer, 24 pt margins); the action stack pinned at thumb height with 20 pt sides, 8 pt top, 12 pt bottom. Sign in with Apple is 56 pt tall at the hero's 20 pt radius. The username form is a leading column at 24 pt spacing with 20 pt margins.
- **Sheets**: the change-username sheet at `.medium` with a drag indicator, 20 pt margins, 24 pt top; the QR sheet at `.large` with an inline title and a Done button.
- **Camera**: full-bleed black preview; 72 pt shutter (60 pt core, 4 pt ring) 24 pt above the safe area; 48 pt glass circles 12 pt down and 16 pt in; a 52 pt Retake / Use photo capsule pair in review, 20 pt from the edges.
- **Photo viewer**: black, status bar hidden, a 16 pt-inset header (36 pt avatar, name, "👀 View once" pill, 44 pt close circle) over the image; tap or a 120 pt drag down dismisses.

**Spacing rhythm**: 2 (caption gap, name to username), 4, 6, 8, 10, 12, 16, 20, 24 pt. 8 pt between the cells of the hero row and between a row's trailing pills; 12 pt between an avatar or glass and its text; 16 pt is the list content inset; 20 to 24 pt is the screen margin on onboarding and sheets.

**Touch targets**: every tappable control declares a 44 pt minimum (or 44 × 44 for icons) even where the paint is 28, 36 or 36 pt; a map pin paints 36 pt inside a 44 pt circle; the glass cells are 66 × 96 pt.

### Named Rules
**The Glasses-Under-Title Rule.** The primary action is the glass row directly under the large title, inside the scroll content, with the camera pinned beside it. It is never a floating button, never in a toolbar, never behind a "+".

**The 44-Point Rule.** Visible height may be 28, 36 or 52 pt; the hit target is never under 44 pt.

## Elevation & Depth

Flat, with tonal layering and no shadows. Depth comes from four moves: the grouped ground against a surface card; the amber wash lifting a control, a glass or an initial off the surface; a surface disc under a wash under a glass on the map pin (a wash on a card); and material blur, `regularMaterial` for the map's empty card and `systemUltraThinMaterialDark` or white at 18% over the camera and the black photo viewer. Pressed states compress in place (0.97 on the hero, 0.94 on the round cell, 0.95 on pills, 0.88 on the shutter core) rather than casting anything. A glass never gets a drop shadow; its outline is what separates it from the wash.

### Named Rules
**The No-Shadow Rule.** Nothing casts a shadow. A control that needs to read as raised gets an amber wash, a surface card, or a material, in that order of preference. The one plate in the build with a shadow is the literal-white QR code surface, which cannot use tonal separation because scanners need black on white in both schemes; it is that plate's own exception, not a vocabulary.

## Shapes

Large, continuous (superellipse) corners, true capsules, and drawn glass silhouettes. The hierarchy: hero and Sign in with Apple, the QR plate and the QR viewfinder at 20 pt (`hero`); surface cards, the field card, the map's empty card and the QR aiming frame at 16 pt (`card`); the favourite glass tile at 12 pt (`chip`, wash only, no ring); every pill, chip, status badge, avatar, glass disc, pin and icon button a capsule or circle. No borders except the camera shutter's 4 pt white ring and the QR aiming frame's 3 pt white stroke; separators are hidden on Home and left to the system in grouped lists.

The glasses are geometry in a unit box scaled to the frame, so one set of numbers serves 72, 44, 32 and 22 pt. Only the bowl holds liquid; stems, feet and the straw are stroked decoration. Seven silhouettes: a tapered pint, a wide shallow chalice on a short stem (deliberately not a tulip, so beer and wine differ at 44 pt), a stemmed U bowl, a narrow flute, a martini cone, a short heavy tumbler, and a tall straight glass with a straw. Width follows the kind (0.42 of the height for a flute up to 0.66 for the chalice).

Motion belongs with the shapes it moves. `Theme.pour` (cubic-bezier 0.22, 1, 0.36, 1 over 350 ms) animates a glass's liquid level: on the picker a tapped glass fills to the brim and stays: the glass then mirrors the logged drink and empties over fifteen minutes; a second tap within a minute shakes the glass instead of logging. `Theme.spring` (response 0.42, damping 0.78) is for arrivals and departures: a new row at the top of the feed, requests resolving, the map camera framing its first pins. `Theme.quick` (ease-out 180 ms) is press scale, enable/disable fades, availability lines. Feed and pin glasses drain on a 60 s `TimelineView` tick, so the level is a state change and the liquid animates on `pour`. A picker cell leaving the viewport fades as a whole (glass and caption) to 45% opacity on an interactive `scrollTransition`, so the peek reads as "more this way" rather than a severed word. Under Reduce Motion every level change and insertion runs on `quick`, and the hero button's sweep becomes a full-height flash.

## Components

### Drink glass (`DrinkGlassView`, signature)
The object the whole app is built around: never an image, always drawn, so it can fill on tap and empty in fifteen minutes.
- **Anatomy:** glass body at 5% label; liquid clipped to the silhouette; a foam band on pils and special beer (cream, 7% of the height, sitting below the surface, gone in the last sliver of a drain); three static bubbles in the flute; a 55% label outline at 2.8% of the height with round caps; stems, feet and straw stroked only.
- **Level:** 0 is empty, 1 is the brim. Unlogged glasses rest at 0 (Tim: "all glasses should be empty unless filled"). A logged drink starts at 1 and drains linearly to 0 over 15 minutes; the row and the pin stay for two hours.
- **Sizes:** 72 pt in the picker (in a 56 × 72 frame), 44 pt on a feed row inside a 56 pt Amber Wash disc, 32 pt on a callout row, 22 pt on a map pin.
- **Accessibility:** decorative by itself; the containing row carries the label ("Tim is having Wine, glass 60 percent").

### Glass row (`DrinkPickerView`, signature)
Seven glasses in canonical order (pils, special beer, wine, bubbles, cocktail, whisky, soft drink), one tap each, in a horizontal `ScrollView` with view-aligned paging.
- **Cell:** glass over a caption, 66 pt minimum width, 6/2 pt padding, plain button style (the glass is the button, no tint on top). The last picked kind sits on a 12 pt Amber Wash tile with its caption in Amber Ink; other captions are secondary.
- **Tap:** `.success` haptic, the glass pours full on `pour`, the kind is handed off, and the glass then stays full, emptying with the drink over fifteen minutes. Taps within a minute of a log shake the glass instead (warning haptic). While a photo uploads the whole row dims to 50%.
- **Accessory:** the camera cell wears the same vertical chrome (6 pt inside, 4 pt on the scroll view) so "Photo" shares the captions' baseline. In the build it is pinned outside the scroll so it never leaves the first viewport.

### Camera cell (`RoundIconButtonStyle`)
A 56 pt Amber Wash circle with an Amber Ink camera glyph at 36% of the diameter, semibold, captioned "Photo" in secondary caption. Light haptic on tap; pressed scale 0.94. Its label says what it does: "Log a drink with a photo" using the last glass picked.

### Feed row (signature)
The story of one drink: the drawn glass at 44 pt in a 56 pt wash disc, headline name ("You" for your own), a subheadline line of relative time and, when shared, "· 📍 place" (the place truncates, the time never). On the trailing edge: the photo chip (filled "📸 View once", quiet "Seen", or nothing), reply pills (emoji and count, only when non-zero), and the cheers control (tinted "🍻 n" you can tap, quiet once cheered; a status pill on your own row, and only when there is a count). Swipe actions Block (red) and Report (Pint Amber); a context menu with quick replies first. New rows spring in at the top; a log fires `.success`, a cheers or reply fires `.light`.

### Buttons
Tactile and confident: they press down, they never glow.
- **Hero (`HeroButtonStyle`):** full width, 64 pt minimum, Pint Amber fill, Stout Ink label in the rounded title3 face, 20 pt corners. On each tap a white-at-28% highlight sweeps bottom to top over 350 ms on the pour curve and fades over 250 ms; `isBusy` holds it steady. It no longer lives on Home: it ships on the onboarding "Claim it 🍺" and "Try again", and on the change-username sheet's "Save". Disabled dims to 50 to 70% rather than recolouring.
- **Sign in with Apple:** the system button, 56 pt, clipped to the 20 pt hero radius; black in light mode, white in dark.
- **Camera (UIKit):** 72 pt shutter with a 4 pt white ring and 60 pt white core; 48 pt ultra-thin dark material circles for cancel and flip; a 52 pt capsule pair for Retake (material) and Use photo (Pint Amber, Stout Ink, headline text style). "Open Settings" on the denied state is the same amber capsule.

### Chips
Pills (`PillButtonStyle`) carry every secondary action and reaction: subheadline semibold, 14 pt horizontal padding, 36 pt visible height inside a 44 pt target, capsule, pressed 0.95.
- **Filled:** Pint Amber with Stout Ink. "📸 View once", Accept, Add when the field holds a name.
- **Tinted:** Amber Wash with Amber Ink. "🍻 n", Add a mate, Invite a mate, Add with QR, Share your link, Unblock, Open Settings (QR).
- **Quiet:** tertiary fill with secondary label. Decline, an already-cheered drink, Add on an empty field, the test sign-in.
- **State:** the same pill changes emphasis with state on `quick`; the label never changes colour independently of its background.

### Status pill (`StatusPill`)
Non-interactive: caption semibold, secondary label, 10 pt horizontal padding, 28 pt, tertiary fill capsule. "Seen", reply tallies, "🍻 n" on your own row, "n drinks logged" in the Settings header. On black (photo viewer) the same shape is white at 18% with white text.

### Avatar (`AvatarView`)
Up to two uppercase initials in rounded bold at 40% of the diameter, Amber Ink on an Amber Wash circle; a 🍺 glyph with no name. Sizes in use: 36 (blocked rows, photo viewer), 44 (mates, requests, callout rows), 56 (QR sheet), 72 (Settings header). Hidden from VoiceOver; the row carries the name. No photos of people, only of drinks.

### Map pin (signature)
A 36 pt surface disc with an Amber Wash overlay and the newest drink's glass at 22 pt, draining with the drink; a 18 pt Pint Amber count badge (11 pt rounded bold, Stout Ink) at the top-trailing corner when several mates share a place; 44 pt hit circle; light haptic on tap, then a callout sheet listing everyone there with avatar, name, drink, "📍 place", time and a 32 pt glass.

### Cards / Containers
- **Corner Style:** 16 pt continuous (`card`); inset grouped rows inherit the system radius; the map's empty card and the QR aiming frame share 16 pt.
- **Background:** Surface on Ground; `regularMaterial` when floating over the map.
- **Shadow Strategy:** none (see Elevation & Depth).
- **Border:** none.
- **Internal Padding:** 14 pt horizontal in the field card; 20 pt in the map card; 4 to 8 pt vertical inside list rows.

### Inputs / Fields
- **Style:** username, display-name and new-username fields sit in a Surface card at 16 pt, 52 pt minimum, body text, 14 pt horizontal padding, the username prefixed with a secondary "@". The Mates search is a bare field in a grouped row with a secondary magnifying glass and a trailing Add pill.
- **Focus:** system caret and keyboard; no border shift or glow.
- **Validation:** a footnote under the field switches on `quick` between a secondary hint, "Checking…" with a spinner, green "Available 🍻", red "Taken — try another.", secondary "That's you already.", and orange for an unverifiable check.

### Navigation
- **Large titles** in rounded bold via `Theme.installNavigationBarAppearance()`, inline titles in rounded semibold headline; default bar background; titles collapse on scroll.
- **Tab bar:** five items with filled SF Symbols (mug, person.2, map, trophy, gearshape), labels "Beers", "Mates", "Map", "Groups", "Settings", tinted Pint Amber.
- **Dark mode (decided 2026-09-11, Tim delegated):** kept, but lifted off system black. Ground #151517, cards #262629; every List hides the system scroll background and paints `Theme.ground`, every grouped Section paints `Theme.surface` on its rows (Menno: "heel donker" on the old pure black). Bars keep the system blur.
- **Lists:** Home is `.plain` with hidden separators, pull-to-refresh, swipe actions and context menus; Mates and Settings are `.insetGrouped`. Settings tints with Amber Ink; its Username row is a plain-styled button so the label stays primary and the value secondary.
- **Sheets and dialogs:** full-screen covers for camera and photo viewer; detented sheets for the map callout, change username and QR; system confirmation dialogs for Report, Block, Remove mate, and the double Delete account confirm.

### Eyebrow (`Eyebrow`)
The section header above groups in the Mates list: caption semibold, 0.6 pt tracking, uppercase, secondary ("ADD A MATE", "REQUESTS", "MATES"). Used only as a grouped-list section header, never as a kicker above a headline. Settings uses system `Section` headers, which iOS 17 renders in title case; both are in the build.

### Photo viewer
Black, status bar hidden. Header: 36 pt avatar, headline name in white, "👀 View once" in a white-18% capsule, a 44 pt white-18% close circle. The image and its chrome dim to 50% as a drag runs on; release past 120 pt dismisses, otherwise it snaps back. A screenshot fires a receipt to the owner.

## Do's and Don'ts

### Do:
- **Do** use `Theme.accent` only for fills and `Theme.accentInk` for any amber text or glyph on a light background (the Fill-Or-Ink Rule).
- **Do** draw every drink with `DrinkGlassView` empty when unlogged, full when just logged, and `fillLevel(now:)` while it drains; never a static icon or emoji in its place.
- **Do** keep colour beyond amber inside the glasses; chrome is amber, ink and system neutrals.
- **Do** bind every font to a text style (`Theme.displayLarge`, `.headline`, `.subheadline`, `.caption`) or a `@ScaledMetric`, and let rows re-stack vertically at accessibility sizes.
- **Do** give every tappable control a 44 pt minimum target and a VoiceOver label that says what happens ("I'm having a glass of wine", "Log a drink with a photo", "View photo once").
- **Do** animate a glass level with `Theme.pour`, arrivals with `Theme.spring`, state with `Theme.quick`, and drain on the 60 s timeline; branch on Reduce Motion to `quick`.
- **Do** keep copy short and warm: "beer" is the brand noun (app name, Beers tab), "drink" is the logged thing when the kind matters ("log a drink", "n drinks logged", "Report this drink"), "mates", "cheers", "view once"; emoji inside labels beside words.

### Don't:
- **Don't** put Pint Amber text on white or on the amber wash; it fails contrast at 2.3:1.
- **Don't** add shadows, borders or gradients to lift a control; use a wash, a surface card or a material.
- **Don't** introduce a second chrome accent or use system blue; destructive stays system red, availability uses system green and orange, and nothing else gets a colour outside a glass.
- **Don't** reshuffle the glass row or promote the favourite by position; the tile marks the last pick where it stands.
- **Don't** use a photo of a person anywhere; avatars are initials on amber.
- **Don't** put a repeating animation in a glass; bubbles are static, the drain ticks once a minute.
- **Don't** use "post", "like", "followers" or "friends" in the UI; the words are drink, log, cheers, mates.
- **Don't** float the primary action or hide it in a toolbar; the glass row lives under the large title with the camera pinned beside it.
- **Don't** use the Eyebrow as a kicker above a title or outside a list section header.

<!-- Not canonized: the app icon is a generated placeholder (two pints on amber) and is not part of this system; the map pin, its callout sheet and the change-username sheet have no simulator capture yet, so their values above are from code; the review screenshots predate the picker's scrollTransition fade and the camera caption's baseline fix, which are recorded from code; the QR plate's drop shadow is the one shadow in the build and is left as that plate's exception rather than a vocabulary; Settings' title-case system section headers and Mates' uppercase Eyebrow are both in the build and the split is left open rather than recorded as a rule; Amber Ink on Amber Wash is recorded at its measured 4.6:1 with the thin headroom stated, not rounded up. -->

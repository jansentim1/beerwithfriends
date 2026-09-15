# Who cheersed + photo captions — Design Spec

Date: 2026-09-15
Status: DRAFT for Tim. Mock (three artboards, strip opacity slider):
https://claude.ai/code/artifact/2a6cecb7-ae62-4519-a1dc-3dde02e531bb Two asks from mates' feedback (Tim, 2026-09-15): "you should be
able to see who liked the post" and "add text like Snapchat, a semi-opaque strip with
text in it". Open decisions are listed in §6; everything else is proposed as final.

## 1. Product summary

**A. Who cheersed.** Today a drink row shows "🍻 3" and nothing more. After this, the
count opens a sheet that lists every mate who cheersed, and every mate who sent a quick
reply ("On my way", "Jealous"), by name. The owner sees it on their own row; mates see
it on each other's rows. No new notifications.

**B. Captions.** After taking the photo, before "Use photo", you can type one line or
two of text that sits on a semi-opaque black strip across the photo, Snapchat style.
You can drag the strip up or down. The text is part of the photo: mates see it inside
the view-once photo, on the same strip, in the same place. The caption is also
whispered in the push ("joost is having a wine 📍 Café De Zon · "eindelijk vrijdag"").

Both features are mates-only, live for the drink's two hours, and deleted with it.

## 2. Feature A: who cheersed

### 2.1 Data

Today: `beers/{id}/cheers/{uid}` `{uid, at}` (create-only by the cheerser, readable by
owner and mates) and `beers/{id}.cheersCount` (incremented by `onCheersCreated`).
Replies: `beers/{id}/replies/{uid}` `{uid, kind, at}` mirrored by `onReplyCreated` into
`beers/{id}.replies` as `{uid: kind}`.

New: the two existing server mirrors also carry the name, so the feed needs no extra
reads and the sheet opens instantly from data it already has.

| Field on `beers/{id}` | Written by | Shape |
|---|---|---|
| `cheersBy` | `onCheersCreated` (after the count increment) | `{ uid: displayName }` |
| `replyNames` | `onReplyCreated` (next to the existing `replies` mirror) | `{ uid: displayName }` |

`displayName` is read from `users/{uid}` at mirror time (falls back to the username).
A later nickname change does not rewrite old mirrors: the drink is gone within two
hours anyway (same rule as `ownerName`).

Rules: unchanged. Both fields are server-written on a doc clients cannot update. The
`beers` create allowlist does not include them, so a client cannot seed them.

BeerKit: `BeerLog.cheersBy: [String: String]` (default `[:]`), `BeerLog.replyNames:
[String: String]` (default `[:]`). Decoding tolerates missing fields (old docs).
`BeerLog.cheersCount` stays the count of record (the map can lag the counter by a
function run; the sheet header uses the map's count so names and count agree).

### 2.2 Where it opens

- **Your own row:** the "🍻 n" status pill becomes a quiet button (same look; 44 pt
  target). Tap → the sheet. Hidden when n = 0, as today.
- **A mate's row:** the cheers pill keeps its job (tap = cheers; `.light` haptic;
  quiet once you have cheersed). Once cheersed, tapping the quiet pill opens the sheet.
  The context menu (already there for quick replies) gets **"Who cheersed"** as its last
  item, always available, so a mate can look before cheersing too.
- **Reply pills** (🏃 n, 😩 n): tap → the same sheet, scrolled to the replies section.

### 2.3 The sheet (`ReactionsSheet`)

`.sheet` at `.medium` and `.large` detents with a drag indicator, ground background,
20 pt margins, 24 pt top, following the change-username sheet.

- **Title:** "🍻 Cheers" in the rounded `.title2` (the Rounded-Names Rule: a headline).
  Under it, one secondary line: "3 mates cheersed your pils" / "…joost's wine".
- **Cheers list:** one row per entry of `cheersBy`, newest first (order from the
  subcollection is not available client-side without a read; the sheet sorts by name
  and shows no time — see §6). Row anatomy = the Mates list row: 44 pt avatar (initial
  on Amber Wash), display name in `.headline`, nothing else. No chevrons, no actions.
- **Replies section:** eyebrow "REPLIES" (Mates eyebrow style), rows of the same anatomy
  with a trailing status pill of the reply: "🏃 On my way" or "😩 Jealous". Only shown
  when there is at least one reply.
- **Empty:** the sheet cannot open at 0 from the pills; from the context menu it can:
  "No cheers yet 🍻" as the title's secondary line, an empty list, no illustration.
- **Owner's own cheers:** not possible (you cannot cheers yourself), nothing to special-case.
- Names update live: the sheet observes the same feed snapshot, so a cheers that lands
  while it is open appears in place.

### 2.4 Server

- `onCheersCreated`: after `cheersCount` increment, `update({ ["cheersBy.\(uid)"]:
  displayName })`. One extra read of `users/{uid}` (already done for the push text).
- `onReplyCreated`: alongside `replies.{uid} = kind`, write `replyNames.{uid} = displayName`.
- Emulator tests: cheers → `cheersBy` has the name; reply → `replyNames` has the name;
  a missing `displayName` falls back to the username.

### 2.5 Accessibility

Own-row pill: label "3 cheers", hint "See who cheersed". Mate's quiet pill: label "You
cheersed, 3 cheers", hint "See who cheersed". Sheet rows are one element each: "joost".
Reply rows: "menno, on my way".

## 3. Feature B: captions

### 3.1 Where you type

The camera's **review screen** (after the shutter: "Retake" / "Use photo"). Two ways in:

1. Tap anywhere on the photo.
2. A glass **"Aa"** circle (44 pt, `systemUltraThinMaterialDark`, white glyph) at the
   top-trailing corner, where the flip button sits during capture.

Either puts the caret in the strip and raises the keyboard. Snapchat does the same:
tap the snap to type.

### 3.2 The strip

- Full width of the photo, edge to edge, no corner radius, no margin.
- Fill: black at 45% (`rgba(0,0,0,0.45)`), no blur (blur reads as a system material;
  the strip should read as Snapchat's flat band). Same on light and dark, it sits on a
  photo.
- Text: white, SF Pro Text `.title3` semibold (20 pt at the default size), centred,
  12 pt vertical and 16 pt horizontal padding. Up to **3 lines**, up to **80
  characters**; the field stops accepting input at 80 (no counter, the caret just
  stops, like Snapchat). Newlines are allowed (return key inserts one; "Done" is the
  keyboard's toolbar button and the tap-outside).
- Position: vertically draggable with one finger on the strip; clamped so it stays
  fully on the photo. Default position: its centre at **62%** of the photo height
  (below the middle, where Snapchat drops it). Horizontal position is fixed.
- While the keyboard is up, the strip rides above the keyboard (its own position is
  remembered and restored on Done).
- Empty strip = no strip: if the text is empty when you tap Done, the strip disappears
  and the photo is captionless. "Retake" discards the caption too.
- Dynamic Type: the strip font follows `.title3`; at accessibility sizes the 3-line
  cap still applies (the strip grows, the position clamp keeps it on screen).

### 3.3 What is stored

**The caption is baked into the JPEG on the client.** At "Use photo" the app renders
the photo at its final pixel size (≤ 1080 on the long edge, as today) and draws the
strip and text on it at the same relative position and the same relative type size
(font size scaled by `photoPixelWidth / screenPointWidth`). The uploaded bytes are the
photo with its caption; view-once, the shield, the early delete and the two-hour
expiry all stay exactly as they are. Nothing new is served.

Alongside, the beer doc gets **`caption: String`** (trimmed, ≤ 80 chars, only when
non-empty) for three uses that need the text, not the pixels:

| Use | How |
|---|---|
| Push | `onBeerCreated` fanout: body `"joost is having a wine 📍 Café De Zon"` becomes `"… · "eindelijk vrijdag""` (caption in typographic quotes, appended after the place, truncated to 60 chars with … if needed). |
| VoiceOver | Photo viewer label "Photo from joost: eindelijk vrijdag". |
| Feed hint | The "📸 View once" chip gains nothing; the caption is a reason to open the photo, not something to give away in the row (Snapchat hides it too). A `💬` glyph is NOT added (see §6). |

Rules: `beers` create allowlist gains `caption`; optional; `is string`, `size() >= 1`,
`size() <= 80`. Rules test for 81 chars and for a non-string.

### 3.4 Rendering the strip in the photo

Shared pure function in BeerKit: `CaptionLayout` takes the caption, the photo pixel
size, the strip centre fraction and the on-screen scale, and returns the strip rect,
the font size and the text rect. The camera's review overlay and the JPEG renderer
both call it, so what you see is what gets uploaded. Unit-tested for: clamp of the
centre fraction; 1, 2 and 3 line heights; scale from a 393 pt screen to a 1080 px
photo.

The JPEG renderer: `UIGraphicsImageRenderer` at the downscaled pixel size (already
exists in `downscaledJPEG`), draws the image, then the strip (`UIColor.black
.withAlphaComponent(0.45)`), then the text with `NSAttributedString` (white, semibold
system font at the scaled size, centred paragraph style, line break by word). JPEG
quality unchanged (0.8).

### 3.5 Viewer

Unchanged: the caption is in the pixels. The shield still blanks it in screenshots.
The header's "👀 View once" pill stays. Accessibility label includes the caption (from
the beer doc).

### 3.6 Rig

The simulator has no camera, so the review screen is reached with a DEBUG launch flag
**`-UITestReviewSample`**: the camera opens straight into review with a bundled sample
JPEG, caption pre-filled ("eindelijk vrijdag 🍻") at the default position. Frames:
`07b-review-caption` (light and dark). The seed writes a second photo drink from menno
with a baked caption (rendered by the seed from `seed-photo.jpg` with node-canvas-free
drawing: the seed ships a second static JPEG `seed-photo-caption.jpg` generated once
with Pillow) and `caption` on the doc, so the unshielded viewer frame shows the strip
as mates will see it.

## 4. Copy

- Sheet title: "🍻 Cheers". Secondary: "{n} mate(s) cheersed your {drink}" / "…{name}'s {drink}".
- Eyebrow: "REPLIES". Reply pills: "🏃 On my way", "😩 Jealous".
- Context menu: "Who cheersed".
- Caption placeholder (empty strip while editing): "Say something…" in white at 60%.
- Camera "Aa" button VoiceOver: "Add a caption".
- Push: `{name} is having a {drink} 📍 {place} · "{caption}"`.

## 5. Tests and gates

- BeerKit: `BeerLog` decoding with/without `cheersBy`, `replyNames`, `caption`;
  `Caption.normalize` (trim, collapse blank lines, 80-char cap, 3-line cap);
  `CaptionLayout` geometry; `ReactionsViewModel` ordering (cheers by name, replies
  grouped, empty states).
- Functions unit: push body with and without caption, with and without place;
  truncation at 60.
- Emulator: rules (caption bounds, client cannot write `cheersBy`), `onCheersCreated`
  mirror, `onReplyCreated` names mirror.
- Rig: `07b-review-caption`, unshielded viewer frame with the captioned seed photo,
  `08h-cheers-sheet` from the populated home (seed: joost's wine has `cheersBy`
  {tim: "Tim", menno: "Menno"} and a reply from tim).

## 6. Decisions for Tim

1. **Cheers order and time.** Proposed: names only, alphabetical, no timestamps (the
   beer doc mirror has no order). Alternative: one extra read of the `cheers`
   subcollection when the sheet opens, newest first with "2 min" per row. Costs a read
   per open, gains recency. Proposed = names only.
2. **Caption in the push.** Proposed: yes, appended in quotes. Alternative: keep the
   push as it is and let the caption be a surprise inside the photo, Snapchat-style.
3. **Caption hint in the feed row.** Proposed: none. Alternative: a "💬" after "View
   once" when a caption exists.
4. **Strip opacity.** Proposed: black at 45%. Snapchat is close to 50%; 45% keeps more
   of the photo. The mock shows both.
5. **Caption without a photo.** Not possible: every drink has a photo since build 17,
   and the strip lives on the photo. No text-only drinks.

## 7. Out of scope

Stickers, drawing, fonts and colours for the caption; emoji reactions beyond the
existing cheers and two quick replies; seeing who *viewed* a photo in the same sheet
(the owner-only view receipts stay where they are, in the photo chip's "Seen" state).

## 8. Plan outline (for the plan doc, after approval)

1. Server: mirrors + push body + rules + emulator tests. Deploy.
2. BeerKit: models, `Caption`, `CaptionLayout`, `ReactionsViewModel`, tests.
3. App: `ReactionsSheet`, pills and context menu wiring (Opus worker 1); camera review
   caption strip + JPEG baking + `-UITestReviewSample` (Opus worker 2).
4. Rig: seed additions, three new frames. Fable finish review, fix round, build.

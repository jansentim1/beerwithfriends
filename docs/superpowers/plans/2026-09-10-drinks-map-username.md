# Drinks, map, username change (2026-09-10)

Tim: "let people change their names if available, add a map function so you can see where
people are, en niet alleen 'im having a beer' maar je moet selecteren wat voor drankje, met
foto's van de drankjes, en dat die gevuld moet worden als je klikt met animatie, en dat dat
glas over tijd ook leeg gaat."

## Decisions
- Drinks: `DrinkKind` (pils, special, wine, bubbles, cocktail, whisky, soft). Stored as
  `drink` on the beer doc (rules-pinned enum; missing = pils for old docs). Glasses are
  drawn in SwiftUI (`DrinkGlass` shape + liquid level) so they can fill on tap and drain
  over the 24 h lifetime (level = remaining fraction). Copy stays "beer"-flavoured in the
  app name; pushes say "Tim is having a glass of wine 🍷".
- Map: new Map tab (MapKit). Pins = mates' active drinks with a coordinate. Coordinate =
  the POI's or city's coordinate from the place lookup (never the device fix), stored as
  `placeCoordinate` GeoPoint only when sharing place is on. Rules: optional geopoint,
  only together with `place`.
- Username change: Settings → "Change username" with the live availability check;
  callable `changeUsername` (transaction: new free → delete old reservation, create new,
  update users/{uid}.usernameLower). Rate: once per day (server-enforced via
  `usernameChangedAt`).

## Work split
- Shared (Claude): BeerKit models/protocols/VM + tests; rules + tests; functions
  (changeUsername, push copy per drink) + tests; privacy docs.
- Worker A (Opus): DrinkGlass views, drink picker replacing the hero, feed glass with
  drain, HomeView.
- Worker B (Opus): MapView tab, LocationPlaceProvider returns coordinate, shell tab.
- Worker C (Opus): SettingsView change-username sheet, FirebaseAuthService.changeUsername.
- Review (Fable): finish review over rig screenshots; fix round; ship.

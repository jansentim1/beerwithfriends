import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { beerPushCopy } from "../src/pushes";
import { REVIEW_CAPTION, REVIEW_COORDINATE, REVIEW_PLACE, REVIEW_USERNAME } from "../src/reviewMate";

describe("review mate constants", () => {
  it("fit the rules and the client's shapes", () => {
    expect(REVIEW_USERNAME).toMatch(/^[a-z][a-z0-9_]{2,14}$/);
    expect(REVIEW_PLACE.length).toBeLessThanOrEqual(60);
    expect(REVIEW_CAPTION.length).toBeGreaterThanOrEqual(1);
    expect(REVIEW_CAPTION.length).toBeLessThanOrEqual(80);
    // Rounded to 3 decimals, like BeerKit's Coordinate.
    expect(Math.round(REVIEW_COORDINATE.latitude * 1000) / 1000).toBe(REVIEW_COORDINATE.latitude);
    expect(Math.round(REVIEW_COORDINATE.longitude * 1000) / 1000).toBe(REVIEW_COORDINATE.longitude);
  });

  it("ships a small JPEG photo", () => {
    const jpeg = readFileSync(new URL("../assets/review-pint.jpg", import.meta.url));
    expect(jpeg.subarray(0, 3)).toEqual(Buffer.from([0xff, 0xd8, 0xff]));
    expect(jpeg.length).toBeLessThan(60 * 1024);
  });
});

describe("beerPushCopy", () => {
  it("names the drink and the place", () => {
    expect(beerPushCopy({ ownerUid: "u", ownerName: "PubDates", hasPhoto: true, drink: "pint", place: "Café De Zon" }))
      .toEqual({ title: "PubDates is having a pint 🍺 at Café De Zon", body: "They added a photo 📸 — you get one look!" });
    expect(beerPushCopy({ ownerUid: "u", ownerName: "Tim", hasPhoto: false }).title).toBe("Tim is having a pils 🍺");
  });
});

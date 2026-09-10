import { describe, it, expect } from "vitest";
import { amsterdamDay, randomCode } from "../src/groups";

describe("groups helpers", () => {
  it("amsterdamDay rolls over at midnight Amsterdam, not UTC", () => {
    expect(amsterdamDay(new Date("2026-09-10T12:00:00Z"))).toBe("2026-09-10");
    expect(amsterdamDay(new Date("2026-09-10T22:30:00Z"))).toBe("2026-09-11"); // CEST
    expect(amsterdamDay(new Date("2026-12-10T23:30:00Z"))).toBe("2026-12-11"); // CET
  });
  it("codes are 6 chars from the unambiguous alphabet", () => {
    const c = randomCode(6, () => 0.999);
    expect(c).toHaveLength(6);
    expect(/^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$/.test(randomCode())).toBe(true);
  });
});

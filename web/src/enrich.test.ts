import { describe, expect, it } from "vitest";
import { citeLabel, refNumber, type Reference } from "./enrich";

const ref = (authors: string, id = "x"): Reference =>
  ({ id, authors, title: "T", venue: "V", year: 2019, url: "https://example.org", note: "n" });

describe("citeLabel", () => {
  it("names one, two, or the first of many authors by surname", () => {
    expect(citeLabel(ref("Raissi, M."))).toBe("Raissi 2019");
    expect(citeLabel(ref("Raissi, M.; Karniadakis, G. E."))).toBe("Raissi and Karniadakis 2019");
    expect(citeLabel(ref("Raissi, M.; Perdikaris, P.; Karniadakis, G. E."))).toBe("Raissi et al. 2019");
  });
  it("keeps an organisation name whole", () => {
    expect(citeLabel(ref("The Julia Project"))).toBe("The Julia Project 2019");
  });
  it("falls back to the year without authors", () => {
    expect(citeLabel(ref(""))).toBe("2019");
  });
});

describe("refNumber", () => {
  it("is the 1-based position, 0 when absent", () => {
    const all = [ref("A", "a"), ref("B", "b")];
    expect(refNumber(all, "b")).toBe(2);
    expect(refNumber(all, "z")).toBe(0);
  });
});

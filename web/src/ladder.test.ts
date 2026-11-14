import { describe, expect, it } from "vitest";
import { bestLadder, ladderTotals, type Ladder } from "./ladder";

const lad = (climbed: number, offered: number): Ladder => ({ rungs: [], climbed, offered });

describe("performance ladder records", () => {
  it("keeps the best climb: a slower rerun does not take a rung away", () => {
    let r = bestLadder(undefined, lad(1, 3));
    expect(r).toEqual({ climbed: 1, offered: 3 });
    r = bestLadder(r, lad(3, 3));
    expect(r).toEqual({ climbed: 3, offered: 3 });
    r = bestLadder(r, lad(2, 3));
    expect(r).toEqual({ climbed: 3, offered: 3 });
  });
  it("never records more rungs climbed than offered", () => {
    // a problem whose reference now allocates offers two rungs: a stored 3 of 3 becomes 2 of 2
    expect(bestLadder({ climbed: 3, offered: 3 }, lad(2, 2))).toEqual({ climbed: 2, offered: 2 });
  });
  it("counts only the given problems that have a record", () => {
    const recs = { a: { climbed: 3, offered: 3 }, b: { climbed: 1, offered: 2 }, other: { climbed: 3, offered: 3 } };
    expect(ladderTotals(recs, ["a", "b", "c"])).toEqual({ graded: 2, climbed: 4, offered: 5, top: 1 });
    expect(ladderTotals({}, ["a"])).toEqual({ graded: 0, climbed: 0, offered: 0, top: 0 });
  });
});

// The HUD backgrounds (site/assets/hud*.js) follow the site's rule that a shown
// number is real: draft 2's course ring must match the course manifests, and its
// recorded readouts must still be in the files they name.
import { describe, expect, it } from "vitest";
import hud from "../../site/assets/hud-v2.js?raw";
import hudSwitch from "../../site/assets/hud-switch.js?raw";
import symdiffBaseline from "../../projects/symdiff/measure_baseline.toml?raw";
import quarto from "../../site/_quarto.yml?raw";
import odeintBaseline from "../../projects/odeint/measure_baseline.toml?raw";
import odeintReport from "../../projects/odeint/case/report_fixtures.toml?raw";
import julia from "../../JULIA_VERSION?raw";
import { course } from "./course";

describe("HUD backgrounds", () => {
  it("draft 2's course ring matches the course manifests", () => {
    const m = /const COURSES = (\[.*?\]);\n/s.exec(hud);
    expect(m).not.toBeNull();
    const ring = JSON.parse(m![1]) as [string, number, string][];
    expect(ring).toEqual(course.courses.map((c) => [c.id.toUpperCase(), c.units.length, c.status]));
  });

  it("recorded readouts are still in the files they name", () => {
    expect(hud).toContain(`julia ${julia.trim()}`);
    expect(odeintReport).toMatch(/5\.18/);
    expect(odeintReport).toMatch(/1\.03/);
    expect(odeintBaseline).toMatch(/"dp54_step!\(kepler, h = 0\.01\)" = 0\n/);
    expect(odeintBaseline).toMatch(/"solve_adaptive\([^"]*\)" = 18\n/);
    expect(symdiffBaseline).toContain("JET 0.9.14");
    expect(symdiffBaseline).toMatch(/rewrite_innermost = "Any"/);
  });

  it("every HUD script is published and the switch loads them", () => {
    for (const f of ["assets/hud-v2.js", "assets/hud-switch.js"]) expect(quarto).toContain(`- ${f}`);
    expect(quarto).toContain('src="assets/hud-switch.js"');
    // every file the switch can load is one of the published ones
    const files = [...hudSwitch.matchAll(/^\s*\{ id: .*file: "([^"]+)"/gm)].map((m) => m[1]);
    expect(files).toEqual(["hud-v2.js"]);
    for (const f of files) expect(quarto).toContain(`- assets/${f}`);
  });
});

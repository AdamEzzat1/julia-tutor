// Picks which HUD background to run and adds a small switch to the navbar.
//   v2  = "Analysis" (assets/hud-v2.js): Jarvis-style scans of what the site teaches
//   off = no animation
// The choice is kept per browser (localStorage) and can be forced with ?hud=v2|off.
// Draft 1 ("Reactor", assets/hud.js) is not in the repo; to bring it back, add
// { id: "v1", label: "Reactor", file: "hud.js" } here and publish the file.
(() => {
  "use strict";
  const KEY = "jt-hud";
  const MODES = [
    { id: "v2", label: "Analysis", file: "hud-v2.js" },
    { id: "off", label: "Off", file: null },
  ];
  const base = (document.currentScript && document.currentScript.src) || "";
  const dir = base.slice(0, base.lastIndexOf("/") + 1);

  const store = {
    get() { try { return localStorage.getItem(KEY); } catch { return null; } },
    set(v) { try { localStorage.setItem(KEY, v); } catch { /* storage blocked: session only */ } },
  };
  const fromUrl = new URLSearchParams(location.search).get("hud");
  const find = (id) => MODES.find((m) => m.id === id);
  let mode = find(fromUrl) || find(store.get()) || MODES[0];

  if (mode.file) {
    const s = document.createElement("script");
    s.src = dir + mode.file;
    document.body.appendChild(s);
  }

  function addSwitch() {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "jt-hud-switch";
    const paint = () => {
      btn.textContent = "HUD: " + mode.label;
      btn.title = "Background: " + mode.label + " (click to change)";
      btn.setAttribute("aria-label", "Change background animation. Current: " + mode.label);
    };
    paint();
    btn.addEventListener("click", () => {
      mode = MODES[(MODES.indexOf(mode) + 1) % MODES.length];
      store.set(mode.id);
      const u = new URL(location.href); u.searchParams.delete("hud");
      location.replace(u.toString()); // reload: each HUD owns its canvas
    });
    const tools = document.querySelector(".quarto-navbar-tools");
    if (tools) tools.prepend(btn);
    else { btn.classList.add("floating"); document.body.appendChild(btn); }
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", addSwitch);
  else addSwitch();
})();

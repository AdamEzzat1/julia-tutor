import { StrictMode, type ComponentType } from "react";
import { createRoot } from "react-dom/client";
import "./styles.css";
import { CourseView } from "./views/Course";
import { ExplainView } from "./views/Explain";
import { GuidedView } from "./views/Guided";
import { HeroView } from "./views/Hero";
import { HoleMapView } from "./views/HoleMap";
import { LessonsView } from "./views/Lessons";
import { RulesView } from "./views/Rules";
import { SandboxView } from "./views/Sandbox";

// Quarto pages contain <div class="jt-mount" data-view="..."></div>; one bundle
// serves every page and mounts the view each one asks for.
const VIEWS: Record<string, ComponentType> = {
  hero: HeroView,
  lessons: LessonsView,
  explain: ExplainView,
  holemap: HoleMapView,
  rules: RulesView,
  course: CourseView,
  sandbox: SandboxView,
  guided: GuidedView,
};

for (const el of document.querySelectorAll<HTMLElement>(".jt-mount")) {
  const View = VIEWS[el.dataset.view ?? ""];
  if (!View) {
    el.textContent = `Unknown view: ${el.dataset.view}`;
    continue;
  }
  el.classList.add("jt");
  createRoot(el).render(
    <StrictMode>
      <View />
    </StrictMode>,
  );
}

import { StrictMode, type ComponentType } from "react";
import { createRoot } from "react-dom/client";
import "./styles.css";
import { CasesView } from "./views/Cases";
import { CourseView } from "./views/Course";
import { CourseLandingView } from "./views/CourseLanding";
import { ExplainView } from "./views/Explain";
import { GuidedView } from "./views/Guided";
import { HeroView } from "./views/Hero";
import { HoleMapView } from "./views/HoleMap";
import { LessonsView } from "./views/Lessons";
import { RulesView } from "./views/Rules";
import { SandboxView } from "./views/Sandbox";

// Quarto pages contain <div class="jt-mount" data-view="..."></div>; one bundle
// serves every page and mounts the view each one asks for. Other data-*
// attributes reach the view as `mount` (e.g. data-course on a landing page).
export type MountProps = { mount: Record<string, string | undefined> };
const VIEWS: Record<string, ComponentType<MountProps>> = {
  hero: HeroView,
  "course-landing": CourseLandingView,
  cases: CasesView,
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
      <View mount={{ ...el.dataset }} />
    </StrictMode>,
  );
}

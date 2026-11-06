# Sources and attribution — liquid-glass-motion

Composed 2026-08 from an indexed corpus of 14 sources plus a live verification pass against
developer.apple.com and local SDK `.swiftinterface` files (Xcode 26.2 / iOS 26.2 SDK, iOS 27
beta 4 documentation). All prose in this skill is written fresh; no source prose is reproduced.

## Vendored

- `scripts/` — Antoine van der Lee, SwiftUI-Agent-Skill (MIT, © 2026). License ships beside the
  scripts as `scripts/LICENSE-AvdLee-SwiftUI-Agent-Skill`. Trace-interpretation guidance in
  references/performance-and-instrumentation.md derives from the same source.

## Adapted code (permissive licenses)

- AThevon/genjutsu `swiftui-graphics` (MIT, © 2026 Adrien Thevon): shader recipes 2–3 and cost
  rules in references/metal-and-glass.md.
- existential-birds/beagle `beagle-ios` (Apache-2.0): Reduce Motion keep/remove and replacement
  tables, custom Transition and Core Animation bridge material.
- Thomas Ricouard — Dimillian/Skills (MIT): scroll-progress discipline, morph recipes.
- haider-nawaz/liquid-glass-skill (MIT): morph debug checklist.
- rshankras/claude-code-apple-skills (MIT): scrollTransition/visualEffect craft, shader
  decision table.

## Removed sources

- dpearson2699/swift-ios-skills (PolyForm Perimeter 1.0.0) was consulted during composition.
  PolyForm Perimeter is source-available, not open source, and is incompatible with this
  repository's MIT licence. Every claim that had rested on it — the spring parameterizations,
  the preset duration/bounce defaults, `UnitCurve`'s members, and the `phaseAnimator` closure
  shapes — was re-derived on 2026-08-09 directly from `SwiftUICore.swiftinterface` in the
  MacOSX26.2 SDK and is now tagged `[verified]` with that provenance. Those are Apple API
  facts, independently checkable by anyone with the SDK. Nothing in this skill derives from
  that source.

## Paraphrased only

- Apple WWDC sessions and Xcode-bundled documentation (via mirrors; Apple proprietary).
- Field reports: JuniperPhoton's Liquid Glass pitfalls writeup (menu-morph history), Blake
  Crosley's production notes (reduce-motion flicker case study, container heuristic,
  update-frequency heuristic).

Facts tagged `[verified]` were checked during composition and take precedence over any source.

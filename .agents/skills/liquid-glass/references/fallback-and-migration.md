# Fallback and migration

Scope: shipping glass code from a deployment target below 26, and the order in which an existing app
adopts glass. Exact API availability tables live in `availability-and-sdk27.md`; Mac-specific
sequencing detail lives in `appkit-and-mac-windows.md`.

## Availability gating discipline

- Gate per platform, with the real floor for each API. Glass itself is iOS 26.0 / macOS 26.0, but
  several neighbouring APIs are not on the same schedule. [verified]
- **Never write one combined `#available` for APIs whose floors differ.** The live example:
  `visibilityPriority(_:)` is iOS 27.0 but **macOS 26.1**, so `#available(iOS 27, macOS 27, *)`
  silently disables working code on macOS 26.1 and 26.2. Split the guard. [verified]
- Two more misattributions that cause the same damage in reverse: `appearsActive` is **iOS 18+ /
  macOS 15+** (back-deployed), and `sharedBackgroundVisibility(_:)` is **iOS 26.0 / macOS 26.0**.
  Neither needs an iOS 27 guard, and gating them behind one disables them on OS versions where they
  work. [verified]
- `ForEach` conforming to `ToolbarContent` back-deploys to iOS 16 / macOS 13 when built with the 27
  SDK — it needs no gate at all. [apple]
- Put the gate at a **builder or `ViewModifier` boundary**, not on a conditional-modifier helper.
  Inside a `.toolbar { }` builder, one `if #available` covering the whole new-API body with an
  `else` branch of plain items is Apple's prescribed shape. [apple]

```swift
// One gate, one body. Not a .if helper, not a per-modifier ternary chain.
private struct GlassPanel: ViewModifier {
    var shape: AnyShape

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.modifier(LegacyPanel(shape: shape))
        }
    }
}
```

- **Never gate glass with a `.if`-style conditional view modifier.** Mechanism, in Apple's causal
  order: the two branches are different view types, so SwiftUI sees a different view rather than a
  modified one, structural identity breaks, `@State` in that view and every descendant resets, and
  animations break because the framework removes one view and inserts another instead of
  interpolating. [apple]
- Do **not** rip out `.if` modifiers you find in an existing codebase. Removing one can change
  behavior and is out of scope for a glass change; flag it in review instead. [apple]
- To toggle glass on and off at a single call site, use the variant or the `isEnabled:` parameter —
  `.glassEffect(isOn ? .regular : .identity)` or `.glassEffect(.regular, in: shape, isEnabled: isOn)`
  — never by adding and removing the modifier. Mechanism: the modifier stays in the tree, so there
  is no layout recalculation and no identity change. iOS 26.0+ / macOS 26.0+. [multi]
- **The `Glass`-type trap:** a helper that *takes* a `Glass` parameter cannot be written as a clean
  `#available` branch, because the parameter type does not exist below 26. Only the no-argument
  wrapper can. Mark the configurable overload `@available(iOS 26.0, macOS 26.0, *)` and keep a
  separate ungated no-argument entry point. [multi]
- Do not emit `DefaultGlassEffectShape` as the documented default shape. The default is a capsule;
  that symbol is not a real type name. [multi]

## Pre-26 fallback: the material ladder

- Below iOS 26 / macOS 26, use the system material ladder rather than hand-built translucency:
  `.ultraThinMaterial` → `.thinMaterial` → `.regularMaterial` → `.thickMaterial` →
  `.ultraThickMaterial`. iOS 15.0+ / macOS 12.0+. [multi]
- Map by glass *intent*, not by looks: `.regular` glass → `.regularMaterial` (the default choice for
  most chrome), `.clear` glass → `.ultraThinMaterial`. Community sources disagree on this mapping;
  this is the version that follows from what each variant is for. [multi]
- On macOS the ladder alone is often the whole answer. A material-backed rounded rectangle is
  already idiomatic pre-Tahoe chrome, so no shim is needed — write the `#available` branch and stop.
  [multi]
- Prefer an `else` branch that returns the view **unchanged** when there is no honest substitute
  (for example a scroll-edge effect). Substituting an approximation is worse than the pre-26
  appearance the app already shipped. [single]

```swift
extension View {
    @ViewBuilder
    func softScrollEdgeIfAvailable() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self                       // no substitute, no regression
        }
    }
}
```

## The compatibility shim, when you need one

Use this only when the same surface must look deliberate on both sides of the floor and a bare
material reads as unfinished. It is an approximation of glass, not glass.

- Three ingredients and no more: a material fill in the same shape, one very subtle gradient to
  suggest a light direction, and a hairline stroke to define the edge. Anything heavier reads as
  2019-era "glassmorphism" and fights the real material when the app later runs on 26+. [multi]
- Keep it in one `ViewModifier` so the call site is version-agnostic and there is exactly one place
  to delete when the deployment target rises. [multi]
- Do not carry the shim's decorations into the glass branch. On 26+, custom shadows and borders on
  glass are wrong — the system owns edge treatment. [multi]

```swift
// Structure paraphrased from community compat shims; code written fresh.
private struct LegacyPanel: ViewModifier {
    var shape: AnyShape

    func body(content: Content) -> some View {
        content.background {
            shape
                .fill(.regularMaterial)
                .overlay {
                    LinearGradient(colors: [.white.opacity(0.22), .clear],
                                   startPoint: .top, endPoint: .center)
                        .clipShape(shape)
                }
                .overlay { shape.strokeBorder(.white.opacity(0.18), lineWidth: 1) }
        }
    }
}
```

## UIDesignRequiresCompatibility — state it precisely

- The Info.plist key `UIDesignRequiresCompatibility` **has not been removed**. It still exists, is
  documented as iOS/iPadOS/macOS/tvOS 26.0+, and still keeps the previous appearance for apps built
  against the 26 SDK. [verified]
- What changed: the system **ignores** it once you build against the 27 SDK (iOS 27, iPadOS 27, Mac
  Catalyst 27, macOS 27, tvOS 27 or later). [verified]
- So the defensible sentence is "ignored when building against the 27 SDK", never "removed in
  Xcode 27". A team still on Xcode 26.x can legitimately use it. Widely repeated secondary sources
  get this wrong. [verified]
- Treat it as a scheduling tool, not a strategy: it buys one SDK cycle, and the work it defers is
  the deletion work in phase 1 below. [multi]

## Migration workflow

Five phases, in this order. The ordering is the point: every phase after the first is judged against
what the previous one left on screen.

**Phase 1 — Audit and delete.** Recompile against the 26+ SDK, then find and remove the
customizations that existed to fake material on older systems: opaque bar and sheet backgrounds,
`.toolbarBackground` overrides, `UITabBar.appearance()` mutations, `.presentationBackground` on
sheets, dark scrims over hero imagery, and clipping that hides the region a bar would extend into.
Record what still looks wrong after deletion — that list, not the original one, is the real work.
[multi]

> **Do not skip ahead.** Adopting glass while the old scrims are still in place corrupts the
> scroll-edge baseline you are about to judge: the system's automatic edge effect is fighting a
> darkening layer you forgot you added, and you will misdiagnose it as a glass bug. Deletion first
> is not tidiness, it is what makes phase 3 legible. [multi]

**Phase 2 — Standard structure and components.** Update app structure (`NavigationSplitView`,
`TabView`, sheets, inspectors), toolbars, search placement, and controls to their current forms and
let them take system glass for free. Most chrome adopts correctly on recompile alone. Nothing custom
is added in this phase. [multi]

**Phase 3 — Custom glass surfaces.** Only now add `glassEffect` — and only to floating, functional
surfaces the app genuinely needs to make distinctive. Wrap any cluster of nearby glass in one
container (see `containers-and-sampling.md`), apply the effect after layout and appearance
modifiers, and restate the hit area with `.contentShape` to match the glass shape. iOS 26.0+ /
macOS 26.0+. [multi]

**Phase 4 — Motion.** Add morphing, transitions, and interactive response last, once the static
composition is right. Morph geometry depends on container spacing set in phase 3, so motion added
earlier gets tuned against a layout that then changes. The `liquid-glass-motion` skill owns this
phase. [multi]

**Phase 5 — Accessibility and performance pass.** Walk the app with Reduce Transparency, Increase
Contrast, and Reduce Motion on; check light and dark separately, and the clear and tinted
appearances; check Dynamic Type at the largest sizes; then measure scroll performance on older
hardware with and without the new glass so the cost is isolated rather than guessed. Details in
`accessibility.md` and `known-bugs-and-testing.md`. [multi]

- Throughout: keep version splits inside a `ButtonStyle`, `LabelStyle`, or small `View` rather than
  scattering `#available` through the view bodies. One gate per concept. [multi]
- Use `if #unavailable(iOS 26.0, *)` to *retain* a pre-26 customization you deleted in phase 1,
  rather than reintroducing it unconditionally. [multi]

## Checklist

- [ ] Every `#available` uses the real per-platform floor; no combined guard spanning APIs with
      different floors.
- [ ] `visibilityPriority` guarded as iOS 27 / macOS 26.1, not iOS 27 / macOS 27.
- [ ] `appearsActive` and `sharedBackgroundVisibility` are not sitting behind an iOS 27 guard.
- [ ] No `.if`-style conditional modifier introduced; existing ones flagged, not removed.
- [ ] Glass toggled with `.identity` or `isEnabled:`, not by adding and removing the modifier.
- [ ] Helpers taking a `Glass` parameter are `@available`-annotated, not `#available`-branched.
- [ ] Pre-26 branch is a material from the ladder, or `self` unchanged — not a decorated imitation.
- [ ] Shim decorations (gradient, stroke) exist only in the pre-26 branch.
- [ ] `UIDesignRequiresCompatibility` described as ignored on 27-SDK builds, never as removed.
- [ ] Deletion phase completed and its results looked at before any `glassEffect` was written.
- [ ] Motion added after the static composition was settled.
- [ ] Accessibility and performance pass run on real hardware, not only the simulator.

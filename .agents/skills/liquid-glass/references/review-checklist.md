# Glass review checklist

A diff-checkable audit. Every item below can be settled by reading the changed code — no build and
no device required. The handful that do need hardware are marked as such, and they belong to the
gates in `known-bugs-and-testing.md` and `accessibility.md`.

---

## A. Correctness

**1. Every glass call site is version-gated per platform and has a fallback.** [verified]
The floor for glass is **iOS 26.0 / macOS 26.0**. A gate has to name every platform the file ships
to: an iOS-only `#available(iOS 26, *)` quietly strips glass from a Mac target that could render it.

```swift
if #available(iOS 26.0, macOS 26.0, *) { … } else { /* .ultraThinMaterial ladder */ }
```

Reject a single **combined** guard wherever the two platforms sit on different floors:

- `visibilityPriority(_:)` on toolbar content: **iOS 27.0 but macOS 26.1.** A single
  `#available(iOS 27, macOS 27, *)` suppresses it on macOS 26.1 and 26.2 where it works. [verified]
- `.buttonStyle(.glass(_:))` — the configurable overload is **real**, but pin it to
  **iOS 26.1 / macOS 26.1**: the `GlassButtonStyle.init(_ glass:)` it calls is annotated 26.1 even
  though the enclosing extension reads 26.0. The plain `.buttonStyle(.glass)` is 26.0. And
  `glassProminent` has **no** configurable overload at all — tint it with `.tint(_:)` on the
  button, never by passing a `Glass`. [verified]

Reject gates placed on the **wrong symbol**. The classic is `.symbolEffect(.drawOn)`: the modifier
`symbolEffect(_:options:isActive:)` is **iOS 17.0 / macOS 14.0**, but the `.drawOn` / `.drawOff`
effects are **26.0** (Symbols.framework, and available on visionOS unlike glass). Guard the
**effect's** floor, not the modifier's. [verified]

Reject *needless* gates too — these are older than people think and gating them disables working
code: `appearsActive` is **iOS 18.0 / macOS 10.15** (back-deployed before macOS 15), not a WWDC26
API; `sharedBackgroundVisibility(_:)` is **iOS 26.0**; `matchedTransitionSource` /
`navigationTransition(.zoom)` are **iOS 18**; `ForEach` as `ToolbarContent` back-deploys to
**iOS 16**. [verified]

Prefer one `ViewModifier` / `ButtonStyle` / small `View` holding the version split over `#available`
scattered through the call sites — the branch-per-call-site form duplicates the whole subtree and
swaps view identity. [multi]

**2. Glass surfaces placed near each other share one `GlassEffectContainer`.** [multi]
Treat this as **correctness**, not tuning: glass cannot sample glass, so every unparented sibling
opens its own sampling region and the group ends up rendering inconsistently. Sharing a container is
also the precondition for morphing. `GlassEffectContainer(spacing:)`, iOS 26.0+ / macOS 26.0+.

**3. `glassEffect` sits last, after all layout and appearance modifiers.** [multi]
The rule the sources agree on most. Write `.padding().frame(…).glassEffect(…)` and never the
reverse — the effect has to see final geometry.

**4. `interactive()` appears only where something actually responds to input.** [verified]
It installs continuous gesture tracking, so on an inert view it is pure cost with nothing to
animate. `Glass.interactive(_:)` is **iOS 26.0+, macOS 26.0+, and Mac Catalyst 26.0+** — the widely
repeated "iOS only" claim is false, and Apple tuned it specifically for the Mac pointer, so do not
strip it from a Mac build. The claim traces back to a single AppKit sample that hand-rolls hover
with `NSTrackingArea`; that is needed only at the `NSGlassEffectView` level beneath SwiftUI and says
nothing about the SwiftUI API. [verified]

**5. Each morphing pair carries a `glassEffectID` and a shared `@Namespace`.** [multi]
`glassEffectID(_:in:)`, iOS 26.0+ / macOS 26.0+. The identifier names an *existing* glass effect, so
putting one on a view that has no `glassEffect()` and no glass button style names nothing and morphs
nothing. The remaining morph preconditions (same container, conditional rendering, `withAnimation`)
are audited in the liquid-glass-motion skill's `morphing.md`.

**6. Sibling surfaces settle on the same variant.** [multi]
Two toolbars in one app have no reason to disagree about `.regular` versus `.clear`.

> **Do not enforce "never mix `.regular` and `.clear`" as an absolute.** Two sources state it, and
> both contradict their own variant-selection guidance two sections earlier. Apple's guidance is
> that `.clear` belongs over media-rich regions and `.regular` everywhere else — which means a real
> app contains both. Flag *inconsistency within a peer group*, not coexistence across an app.
> [multi, over-restrictive as stated]

---

## B. Things that silently kill the material

**7. No `.opacity` fade on a glass view, and no ancestor with opacity < 1.** [multi]
Partial opacity forces the subtree into a separate composited layer and the refraction collapses.
This is a silent failure: it compiles, it renders, it just stops looking like glass. Glass
materializes; it does not fade.

**8. No glass on glass.** [multi]
Elements sitting *on* a glass surface get fills and vibrancy, not a second `glassEffect`. One
dominant glass layer per region — a native blurred header plus a custom glass child inside it is
the same defect wearing a different hat.

**9. Glass has something to refract.** [multi]
A flat single-color background behind glass reads as a tinted rectangle. Pure black is the worst
case. If the surface looks flat, the bug is in the layout behind it, not in the glass call. Let
content run edge-to-edge under floating chrome.

**10. No conditionally-applied glass modifier (`.if { }`).** [verified]
Wrapping a modifier in a condition changes the view's structural identity, which breaks animations
and resets `@State` — and the `.if` helper no longer compiles against the iOS 27 SDK. Use
`.glassEffect(cond ? .regular : .identity)` or the `isEnabled:` parameter instead. [verified]

**11. No `.clipShape` standing in for the `in:` shape parameter.** [multi]
The glass shape belongs in `glassEffect(_:in:)`. Clipping afterwards cuts the outer lensing and
does nothing for hit testing.

**12. No custom shadows or borders added to glass.** [multi]
The system owns the edge treatment and adapts it to the backdrop; a hand-added stroke fights it and
does not adapt under Increase Contrast.

---

## C. Interaction and accessibility

**13. `contentShape` on every custom-shape glass control.** [multi]
`.frame()` sets layout size only; the hit area still follows the content's geometry. Match the
`contentShape` to the glass shape. → `accessibility.md`.

**14. Inert glass uses `.disabled(true)`, not `.allowsHitTesting(false)`.** [verified]
Glass ignores `allowsHitTesting` and keeps reacting visually. → `known-bugs-and-testing.md`.

**15. Every glass animation you wrote is gated on `accessibilityReduceMotion`.** [multi]
The system tones down its *own* glass motion, not your `withAnimation` morphs. A single check at
app level is a review finding — each animated component needs its own. → `reduce-motion.md` in the
liquid-glass-motion skill.

**16. Hit targets use the right per-platform minimum.** [multi]
44×44pt on touch; system control metrics on macOS. **Never 44pt on Mac chrome.** →
`accessibility.md`.

**17. No `rotationEffect` on a glass view.** [version-pinned]
Open, unfixed, corrupts the glass geometry. → `known-bugs-and-testing.md`.

---

## D. Migration hygiene

**18. Legacy scrims and fills under the new glass are deleted, not layered.** [multi]
Deletion precedes addition. Look for survivors of the pre-26 world sitting under a glass surface:
`.toolbarBackground(…)` making a bar opaque, `.presentationBackground(Color.white)` on a sheet,
`UITabBar.appearance()` / `UINavigationBar.appearance()` global proxies, custom navigation
materials, hand-rolled `.ultraThinMaterial` backgrounds on chrome, and gradient scrims placed for
legibility that the material now provides. Each one defeats the glass it sits under.

**19. Renamed toolbar API is not left on the old spelling when building against the 27 SDK.**
[verified]
`toolbarMinimizeBehavior` was renamed to **`toolbarMinimizationBehavior(_:for:)`** at iOS 27
beta 4. Nearly every WWDC26 write-up — including one of Apple's own pages — still shows the old
name. Do not confuse it with `tabBarMinimizeBehavior(_:)`, which is a different API for tab bars,
iOS 26.0, unchanged. [verified]

**20. `UIDesignRequiresCompatibility` is described correctly if present.** [verified]
It was **not removed**. It still exists and still works for builds against the iOS 26 SDK; it is
merely *ignored* once you build against the iOS 27 SDK. Reject both "it's gone" and "it still
opts you out on 27".

**21. Glass is not gated onto visionOS — but the exclusion is per symbol, not blanket.** [verified]
Where Apple's rendered docs and the SDK disagree, the SDK wins: the docs render "visionOS 1.0" for
symbols the SDK marks `@available(visionOS, unavailable)`.

- **Unavailable on visionOS:** `glassEffect`, `GlassEffectContainer`, `glassEffectID` /
  `glassEffectUnion` / `glassEffectTransition`, the `Glass` type itself (including
  `.interactive()`), the glass button styles, `scrollEdgeEffectStyle`.
- **Available visionOS 26.0:** `backgroundExtensionEffect`, `ConcentricRectangle`,
  `tabBarMinimizeBehavior`, `.drawOn` / `.drawOff`.

Reject a blanket "no glass APIs on visionOS" that sweeps the second group in with the first.

---

## E. Known-bad API table

Symbols and figures that recur across community sources and LLM output and are **wrong**. Never
emit any of these; flag them on sight in review.

| Never emit | Why it's wrong / what's real instead | Confidence |
|---|---|---|
| `.scrollExtensionMode(.underSidebar)` | Does not exist. Absent from the SDK, 404 at six DocC paths, absent from release notes, zero web results — while known iOS 27 symbols resolve fine. Real API: **`backgroundExtensionEffect()`**, iOS/macOS/visionOS 26.0, whose documentation names the under-sidebar detail-column case verbatim. Two constraints come with it: apply it to **one** background view, and it clips the view to stop the mirrored copies overlapping. **Sourcing rule:** this fabrication ships inside Apple's *own* Xcode 27 bundled model-context documentation, with a full plausible code sample, and that document never mentions the real API — so Xcode-bundled model-context docs are **not authoritative**. Verify against DocC or the SDK. | [verified] |
| `.background(.secondaryBackground)` | No such `ShapeStyle`. Use `.background(.secondary)`, or a semantic color — `Color(.secondarySystemBackground)` on iOS, `.windowBackground` on macOS. Two independent skills repeat this same hallucination. | [multi] |
| `DefaultGlassEffectShape` | Not a type. It is a documentation placeholder written as if it were API. The default shape of `glassEffect(_:in:)` is a **capsule**; just omit `in:`. | [multi] |
| `UIViewCornerConfiguration(corners:cornerRadius:)` | Not a type. Real API: the **`UIView.cornerConfiguration`** property, assigned from a **`UICornerConfiguration`** factory. iOS 26.0+. (And note `layer.cornerRadius` stopped working for glass effect views at iOS 26 beta 3 — `cornerConfiguration` is the supported route.) | [verified] |
| `UIGlassEffect(glass:isInteractive:)` | Fabricated initializer, written by analogy with the SwiftUI `Glass` value. Real: **`UIGlassEffect()`** and set the **`isInteractive`** property. iOS 26.0+. | [verified] |
| `ScrollEdgeEffectStyle.sharp` / `.subtle` | Neither case exists. The real cases are **`.automatic` / `.hard` / `.soft`** (SDK-verified on 26.2, iOS and macOS). The wrong names circulate widely in write-ups. → `toolbars-and-scroll-edge.md`. | [verified] |
| `.searchToolbarBehavior(.minimized)` | Wrong case spelling — it is **`.minimize`** (the type offers `.automatic` / `.minimize`). | [verified] |
| `PhaseAnimator` / `.phaseAnimator` with a single-parameter `{ phase in }` closure | Wrong arity — will not compile. The real closure is **`{ content, phase in }`**. | [verified] |
| `.symbolVariableColor(value:)` | No such modifier. Variable color is a symbol *effect*: `.symbolEffect(.variableColor…)` (iOS 17+). | [multi] |
| `@Environment(\.accessibilityPrefersCrossFadeTransitions)` | No such SwiftUI environment value (SDK-checked: nothing in SwiftUI/SwiftUICore). The "Prefer Cross-Fade Transitions" setting is read via UIKit's **`UIAccessibility.prefersCrossFadeTransitions`** (iOS 14+/tvOS 14+, unavailable watchOS). → the liquid-glass-motion skill's `reduce-motion.md`. | [verified] |
| CAAnimation delegate via `uiView.next as? CAAnimationDelegate` | Silently returns `nil` — the responder chain is not the delegate chain, so the callback never fires and there is no error. Hold a real delegate object and assign it. | [multi] |
| `.glassBackgroundEffect(…)` on iOS or macOS | A **visionOS** API — and glass is annotated *unavailable* on visionOS in the SDK, so it is doubly misfiled. On iOS/macOS use `glassEffect(_:in:)`. | [verified] |
| "13% battery on iOS 26 vs 1% on iOS 18" | Unsourced viral anecdote: no methodology, no duration, no build, one device. Never cite it. Keep the qualitative claim — glass costs GPU, profile it — and drop the number. | [multi] |
| A 44pt minimum hit target **on macOS** | The iOS *touch* minimum applied to a pointer platform. Apple publishes no 44pt Mac rule; standard regular-size Mac controls are around 28pt. Copying it produces oversized, non-native Mac chrome. → `accessibility.md`. | [multi] |

---

## F. Reviewer stance

**Say where glass should *not* be used.** A glass review that only checks how glass was applied has
done half the job. The higher-value finding is usually a deletion. Flag: [multi]

- **Glass on the content layer.** Glass belongs to the navigation layer floating above content —
  bars, toolbars, floating controls, sheets. Not on lists, tables, media, text blocks, or the
  scrollable body. This is the single most common defect in glass adoption.
- **Glass on list or collection rows.** Every glass surface is a live sampling region; putting one
  in a recycled scrolling row multiplies that cost per visible row and looks wrong besides. Keep
  scrollable content glass-free and put the glass on the floating overlay above it.
- **Glass on static labels and decoration.** If nothing is interactive and nothing floats, the
  surface is content, and content does not get glass.
- **Glass as a full-screen background.** It has nothing to defer to.
- **Glass added where the system already provides it.** Toolbars, tab bars, sheets, and split-view
  sidebars adopt glass by recompiling against the 26 SDK. Hand-rolled glass on those is work that
  will drift from the system.
- **Hierarchy invented with glass instead of layout.** Build hierarchy with spacing and grouping
  first; glass is the last resort for hierarchy, not the first.

---

## Checklist

- [ ] Availability gated per platform, with a fallback; no combined guard where floors differ.
- [ ] Guards sit on the right symbol — `.drawOn`'s 26.0 floor, not `symbolEffect`'s iOS 17.
- [ ] `.buttonStyle(.glass(_:))` pinned to 26.1; no `Glass` argument passed to `glassProminent`.
- [ ] No needless gate on `appearsActive`, `sharedBackgroundVisibility`, or `matchedTransitionSource`.
- [ ] Sibling glass surfaces share one `GlassEffectContainer`.
- [ ] `glassEffect` applied after layout and appearance modifiers.
- [ ] `interactive()` only on genuinely interactive views (and not stripped from macOS).
- [ ] `glassEffectID` + shared `@Namespace` on every morphing pair, on views that actually have glass.
- [ ] No `.opacity` fade on glass; no ancestor with opacity < 1.
- [ ] No glass on glass; one dominant glass layer per region.
- [ ] Something worth refracting sits behind every glass surface.
- [ ] No `.if`-wrapped glass modifier; conditional glass uses `.identity` / `isEnabled:`.
- [ ] No `.clipShape` substituting for the `in:` shape; no hand-added shadows or borders.
- [ ] `contentShape` on every custom-shape glass control.
- [ ] `.disabled(true)`, not `.allowsHitTesting(false)`, for inert glass.
- [ ] Your glass animations are gated on `accessibilityReduceMotion`, per component.
- [ ] Per-platform hit-target minimums; no 44pt on Mac chrome.
- [ ] No `rotationEffect` on glass.
- [ ] Legacy bar/sheet/appearance-proxy customizations deleted, not layered under the glass.
- [ ] `toolbarMinimizationBehavior` spelling correct for the 27 SDK.
- [ ] No symbol from the known-bad table anywhere in the diff.
- [ ] Reviewer named at least one place glass should be removed, or explicitly found none.

# Morphing glass

Owns: `glassEffectID`, `glassEffectUnion`, `glassEffectTransition`, the geometry that makes a merge
happen, and why a morph silently does nothing. Availability of every symbol here: **iOS 26.0+,
macOS 26.0+, tvOS 26.0+, watchOS 26.0+; unavailable on visionOS** — unchanged in iOS 27, no new
glass APIs and no deprecations. `[verified]`

For the material itself (variants, tint, containers as a correctness requirement) see the
liquid-glass skill's `material-and-variants.md` and `containers-and-sampling.md`.

## The physical model — read before the API

Glass does not fade in. It **materializes**: the system ramps how strongly the surface bends and
scatters what is behind it, so the element resolves out of the backdrop instead of cross-dissolving
over it. `[apple]`

Size is part of that material. A larger glass surface reads as *thicker* glass — deeper shadow,
more lensing at the edges, a different specular response — so a change in size is a change in
material, not a change in a `frame` value. `[apple]`

Two consequences, and they are the reason this whole file exists:

- **Never fake a morph.** `.opacity`, a cross-fade, `matchedGeometryEffect` on a material-backed
  view, or animating `frame` on a glass view all animate geometry while the material stays fixed.
  The result is a rectangle that slides and then snaps. Only the system morph re-derives lensing and
  shadow per frame. `[multi]`
- **Never `.opacity(< 1)` on a glass view or any ancestor**, in motion or at rest — it composites
  the material as a flat image and kills the effect. `[multi]`

Corollary for review: a `.if`-style conditional view modifier around `.glassEffect()` swaps the view
for a different type, so SwiftUI removes and inserts instead of interpolating — structural identity
breaks, `@State` resets, and the morph is replaced by a pop. Use a ternary inside the modifier
argument, or `.glassEffect(isOn ? .regular : .identity)`. `[verified]` (SDK-27 material; see
`availability-and-sdk27.md` in the liquid-glass skill.)

## The four ingredients

All four must hold at once. Miss one and there is no error, no warning, and no morph. `[multi]`

1. Both elements live in the **same `GlassEffectContainer`**. `[multi]`
2. Each carries **`glassEffectID(_:in:)` with one shared `@Namespace`**. IDs must be
   `Hashable & Sendable` — never a model object, never a fresh `UUID()` per render. `[verified]`
3. The trigger is **insertion or removal from the view hierarchy** — an `if`, a `switch`, a
   `ForEach` element appearing. A value change on an always-present view is not a morph trigger.
   `[multi]`
4. The state change is made **inside an animation context**: `withAnimation { … }` at the mutation
   site, or `.animation(_:value:)` on the container. `[multi]`

```swift
@Namespace private var toolCluster           // ingredient 2: one namespace, declared here
@State private var showsSecondaryTool = false

VStack(spacing: 24) {
    GlassEffectContainer(spacing: 24) {      // ingredient 1: one container for both members
        HStack(spacing: 24) {
            if showsSecondaryTool {           // ingredient 3: this member enters and leaves
                Image(systemName: "paintbrush.fill")
                    .frame(width: 56, height: 56)
                    .glassEffect()
                    .glassEffectID("brush", in: toolCluster)
            }

            Image(systemName: "slider.horizontal.3")   // the permanent morph partner
                .frame(width: 56, height: 56)
                .glassEffect()
                .glassEffectID("adjust", in: toolCluster)
        }
    }

    // ingredient 4: the mutation happens inside an animation context
    Button("Brush") { withAnimation(.snappy) { showsSecondaryTool.toggle() } }
        .buttonStyle(.glass)
}
```

A fifth condition, reported by one source and cheap to honour: every element participating in one
morph should use the **same `Glass` variant and the same tint** (colour *and* opacity). Mixed
variants morph inconsistently. `[single]`

`GlassEffectContainer(spacing: CGFloat? = nil, @ViewBuilder content:)` — spacing is optional and
defaults to a system value. `[verified]`

## The geometry precondition almost everyone omits

The container's `spacing:` is a **merge-distance threshold in points, not layout padding**. Two glass
surfaces blend into one shape only while the gap between their nearest edges is within that
threshold; further apart, they stay separate pieces of glass and the "morph" degrades to two
independent appear/disappear animations. `[multi]`

So `spacing` and your stack's spacing are two different numbers that happen to interact: set the
container's spacing to the layout gap you want merged *through*, then check the real distance
between the nearest edges of the two glass shapes — not their centres, not the stack spacing you
typed. `[multi]`

Animating `spacing` itself is a legitimate effect: the surfaces pull apart and rejoin like droplets
as the threshold crosses the real gap. Use it deliberately; do not let it drift as an accident of a
layout animation. `[single]`

Two AppKit notes for a Mac-first codebase: `NSGlassEffectContainerView.spacing` defaults to **0**,
and Apple describes that default as suitable for batching without distortion — zero is a legitimate
production value there, the opposite emphasis from the SwiftUI examples that always show 20–40.
Merging on AppKit is driven by animating an `NSGlassEffectView`'s `frame` through `animator()` until
it comes within the container's spacing. `[apple]`

## When nothing happens

The morph's failure mode is **silence**. Nothing logs, nothing throws, the views just appear and
disappear. Work this checklist in order before touching timing or curves. `[multi]`

1. Are both elements inside the **same** `GlassEffectContainer` — not two containers, not one
   nested in another?
2. Does each have `glassEffectID` with the **same `@Namespace`** instance? A `@Namespace` declared
   in a child view is a different namespace on every rebuild.
3. Is the state change wrapped in `withAnimation` (or is `.animation(_:value:)` on a view that
   survives the change)?
4. Are the views **conditionally inserted and removed**, rather than hidden with `.opacity(0)`,
   `.hidden()`, or a zero frame?

Then the geometry question the four-question list misses: **are the nearest edges within the
container's `spacing`?** `[multi]`

Then the one the whole list misses: **is there a co-present partner to match geometry against?**
`.matchedGeometry` matches between glass effects alive *at the same time* as siblings — the
selection-lens-in-a-track case, where the lens is inserted in one cell while the track persists. An
`if / else` that swaps two mutually-exclusive branches sharing one `glassEffectID` satisfies all
four ingredients and still does not morph: at no frame do both shapes exist, so there is nothing to
match. Measured on macOS 26.2 with a harness logging every `Shape.path(in:)` call — the arriving
branch is asked for its path at its *final* rect on frame one and every frame after, while the
leaving branch is never asked again. SwiftUI does run a transition of the right duration (the
leaving branch stays alive ~380 ms), so it reads as the new shape appearing at full size over a
stale old one. Neither a container `spacing` of 40 nor an explicit `withAnimation` at the mutation
site changed it.

**The working pattern for a collapsed↔expanded swap is one glass surface that is never inserted or
removed**, whose `frame` and corner radius interpolate, with the content crossfading inside it at a
fixed layout width (so an interior `ScrollView` does not re-measure while the surface travels). No
matched-geometry machinery is involved, which also means the pre-26 fallback is the same animation
with stock material behind it rather than a second code path.
`[single — live-measured on macOS 26.2, 2026-08]`

Question four is the one that produces the canonical non-morph. The first three spellings below all
leave the view sitting in the hierarchy, so none of them is a trigger; only the last one actually
inserts and removes:

```swift
Badge().glassEffect().glassEffectID("badge", in: cluster)
    .opacity(showsBadge ? 1 : 0)             // inert — and flattens the material as a bonus

Badge().glassEffect().glassEffectID("badge", in: cluster)
    .hidden()                                // inert

Badge().glassEffect().glassEffectID("badge", in: cluster)
    .frame(height: showsBadge ? 44 : 0)      // inert — a zero frame is still a present view

if showsBadge {                              // the only one that morphs
    Badge().glassEffect().glassEffectID("badge", in: cluster)
}
```

Two more silent killers: a `Menu` inside a `GlassEffectContainer` (see the version box below), and
`.clipShape()` on a glass view — pass the shape through `glassEffect(_:in:)` instead, or the morph
animates a shape the clip then overrides. `[single]`

## glassEffectUnion — fusing without depending on distance

`glassEffectUnion(id:namespace:)` forces several views to render as **one continuous glass shape**,
regardless of how far apart they are. It is the Apple-Maps zoom-control look: two buttons, one piece
of glass. `[verified]`

Use it where `spacing` cannot help you: views generated in a `ForEach`, views that do not share an
`HStack`/`VStack` parent, or elements deliberately spaced further apart than any sane merge
threshold. `[multi]`

Tag each element with the pane it belongs to and let the data carry that, rather than deriving it
from a position in the array — the `id` you pass has the same stability requirement as any other
identity in SwiftUI:

```swift
struct MapControl: Identifiable {
    let id: String
    let symbol: String
    let pane: String        // which glass surface this control fuses into
}

GlassEffectContainer(spacing: 24) {
    HStack(spacing: 24) {
        ForEach(controls) { control in
            Image(systemName: control.symbol)
                .frame(width: 56, height: 56)
                .glassEffect()
                .glassEffectUnion(id: control.pane, namespace: paneNamespace)
        }
    }
}
```

Distinct union IDs **partition** rather than merge: every control tagged `"zoom"` fuses into one
pane, every control tagged `"compass"` into a second, and the two panes stay separate no matter how
close together they sit. `[multi]`

All members of a union must share the same union `id`, the same `Glass` variant, and the same tint
(colour and opacity); differing shapes fuse poorly. Violate any of these and the views simply do not
join, again with no diagnostic. `[multi]`

`glassEffectUnion` fuses; `glassEffectID` morphs between states. They are not alternatives and can
be used together on the same element. `[multi]`

## glassEffectTransition — how each element enters and leaves

`glassEffectTransition(_:)` takes a `GlassEffectTransition` value: `.matchedGeometry` (the default),
`.materialize`, or `.identity`. `[verified]` These are static properties on a struct, not enum cases
— do not `switch` over them. `[single]`

- **`.matchedGeometry`** — the element emerges from, and returns to, the geometry of its partner in
  the container. This is what makes an expanding cluster read as one object unfolding. Losing it is
  the difference between a button *growing out of* the toolbar and a button *appearing next to* the
  toolbar from nowhere. `[multi]`
- **`.materialize`** — the element resolves in place, without a geometric partner. Correct for
  elements too distant for a matched-geometry read, and the right substitute when Reduce Motion is
  on and you still want the material to arrive gracefully. `[single]`
- **`.identity`** — no transition. Only when you have a reason.

Placement rule: attach the transition to the **conditional child that is inserted and removed**, not
to the always-present container. A transition on a view that never leaves the hierarchy is inert.
`[single]`

```swift
if isExpanded {
    ActionButton()
        .glassEffect()
        .glassEffectID("action", in: namespace)
        .glassEffectTransition(reduceMotion ? .materialize : .matchedGeometry)
}
```

Reduce Motion: the system already decreases lensing and elastic response on its own glass. It does
**not** neuter your `withAnimation` morphs — gate those yourself. See `reduce-motion.md`. `[multi]`

## The interactive() squish

`Glass.interactive(_ isEnabled: Bool = true)` is **one boolean**. There is no spring, no damping, no
duration, no response curve — the squish, bounce, shimmer and touch-point illumination are entirely
system-owned and the API surface exposes nothing to tune. Do not promise a designer tunable jelly;
if the feel is wrong, the answer is a different control, not a parameter. `[verified]`

It is available on **iOS 26.0+, macOS 26.0+ and Mac Catalyst 26.0+** (also tvOS/watchOS 26.0;
unavailable on visionOS), with no per-member availability annotation — it inherits `Glass`'s
availability exactly. The widely repeated **"`.interactive()` is iOS-only" claim is false**, and
Apple gives the Mac a dedicated pointer optimization for it, so it is worth using on Mac rather than
avoiding. Write no platform-conditional code around it. `[verified]`

Where that myth came from, and why it does not apply to you: AppKit's `NSGlassEffectView` has no
`.interactive()` equivalent, so hover at that level is hand-rolled with `NSTrackingArea` plus an
animated `tintColor`. That is an **AppKit-level gap, not a SwiftUI limitation** — a Mac target using
SwiftUI glass gets the squish from the same one boolean an iPhone does. `[verified]`

Apply it only to views that genuinely take input — a `Button`, or a view with a gesture. On inert
content it adds continuous gesture tracking for an effect that never fires. Prefer
`.buttonStyle(.glass)` / `.buttonStyle(.glass(_:))` (the configurable overload is safest pinned to
**iOS 26.1+**) over hand-applying interactive glass to a button label. `[verified]`

One trap worth knowing here because it looks like a motion bug: glass **ignores
`.allowsHitTesting(false)`** — the action correctly never fires but the material still visibly
reacts to touches. Only `.disabled(true)` suppresses the reaction, and it also changes appearance.
`[verified]`

## Menu morph — version-pinned history, no current fix

`[version-pinned]` — recorded 2026-08-07. **Recheck on every OS update.** The full bug table lives in
the liquid-glass skill's `known-bugs-and-testing.md`; this is the motion-relevant summary.

| OS | Reported behaviour / workaround |
|---|---|
| 26.0–26.0.1 | Menu glass morph starts and ends as a rectangle then snaps to a circle. Workaround: apply `glassEffect(_:in:)` to the outer `Menu`, interactive. |
| 26.1 | The 26.0 workaround stopped working; a custom `ButtonStyle` applying glass to the style's label was the replacement. Also on 26.1: **putting a `Menu` inside a `GlassEffectContainer` breaks the morph** (it worked on 26.0). |
| 26.2 / 26.3.1 | Different, newer, confirmed bug: `.glassEffect(.regular)` on a `Label` used as a `Menu` label clips the shadow during the collapse morph, then pops. Reporter's workaround: `.glassEffect(.clear)` plus `.compositingGroup()`. Unanswered by Apple. |
| 27 betas | No information either way. Apple's iOS 27 beta 4 notes mention glass exactly once, and it is a UIKit toolbar fix. One adjacent change: `Menu` labels may now contain controls and gestures. |

The published guidance stops at 26.1 and its own author warned the behaviour keeps changing
underneath it. Treat every `Menu` + glass combination as needing visual verification on the actual
target OS — the deliverable is the test, not the workaround. Keep "don't put a `Menu` in a
`GlassEffectContainer`" as the standing rule; it was true on 26.1 and nothing since contradicts it.

Verification caveat that applies to all of the above: glass renders differently on the simulator than
on hardware, and its appearance is a **user setting** (26.1 presets, a continuous slider on 27).
Never accept the simulator as visual acceptance for a morph, and never assert exact glass pixels in a
screenshot test. `[verified]`

## Checklist

- Morphs are system animations. Never approximate one with opacity, cross-fade, `matchedGeometryEffect`, or an animated `frame`. `[multi]`
- No `.opacity(< 1)` on a glass view or any of its ancestors. `[multi]`
- All four ingredients present: one container, one `@Namespace` with per-element `glassEffectID`, conditional insertion/removal, mutation inside `withAnimation`. `[multi]`
- Nearest edges within the container's `spacing`, or nothing merges. `[multi]`
- IDs are `Hashable & Sendable` and stable across rebuilds — never a fresh `UUID()`. `[verified]`
- One `GlassEffectContainer` per morph group; never nested; never a `Menu` inside one. `[single]`
- Shape goes in `glassEffect(_:in:)`, never `.clipShape()` on the glass view. `[single]`
- `glassEffectTransition` goes on the conditional child, not the always-present container. `[single]`
- Union members share id, variant and tint, or they will not fuse. `[multi]`
- `.interactive()` is one boolean with no tunable parameters, on iOS 26.0+ **and** macOS 26.0+ — no platform-conditional code, and the AppKit `NSTrackingArea` workaround is not a SwiftUI concern. `[verified]`
- Gate your own morph animations on Reduce Motion; the system only tones down its own. `[multi]`
- Verify morphs on hardware, on the target OS version. Simulator ≠ acceptance. `[verified]`

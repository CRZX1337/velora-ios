# Containers and sampling

Why `GlassEffectContainer` exists, what `spacing:` actually controls, and when skipping the container is
a judgement call rather than a mistake.

Variants, tint and shape: see `material-and-variants.md`. Morphing, `glassEffectID` and
`glassEffectUnion` behavior: see the liquid-glass-motion skill (`morphing.md`).

## Availability

- `GlassEffectContainer` — **iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0; unavailable on visionOS.** [verified]
- Initializer, exactly: `init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content)`. `spacing` is
  optional and defaults to `nil`, meaning the system chooses. [verified]
- Spacing semantics are unchanged from iOS 26 through iOS 27. [verified]
- AppKit peer: `NSGlassEffectContainerView` (see `appkit-and-mac-windows.md`). UIKit peer:
  `UIGlassContainerEffect` (see `uikit-glass.md`). [apple]

## The mechanism everything else follows from

**A glass effect samples an area larger than the view it is applied to, and it cannot sample other glass.**
Two independently-glassed views therefore each open their own sampling region, sample the content
underneath *without* seeing each other, and render inconsistently where they meet or overlap. [multi]

**A `GlassEffectContainer` gives every glass view inside it one shared sampling region.** That is what
makes neighbouring surfaces agree with each other, and it is also what lets them merge and morph. [multi]

```swift
GlassEffectContainer(spacing: 24) {
    HStack(spacing: 24) {
        ToolButton(symbol: "pencil")
        ToolButton(symbol: "eraser")
    }
}
```

**Treat the visual-correctness argument and the performance argument as one argument, not two.** The
container is not an organizational nicety that happens to be faster — sharing the sampling region is
simultaneously what makes the pixels right and what avoids re-deriving the same backdrop per element.
Prefer stating the correctness half; it says what breaks. [multi]

The framing to avoid: "always use a container for better rendering performance", which is what Apple's
own SwiftUI glass prose says. It is unquantified, gives no threshold, and tells a reviewer nothing about
what a missing container looks like on screen. [apple] (weak — do not carry as the primary reason)

## `spacing:` is a merge threshold, not padding

**`spacing:` sets the distance within which neighbouring glass effects blend and morph into each other.**
Smaller values mean views must be closer before their effects fuse; larger values fuse them further
apart. It does not lay anything out. [multi]

**Tune it deliberately against the geometry you actually have.** It is a design parameter: if the gap
between two glass views exceeds the container spacing, they will never merge, and a morph between them
silently does nothing. [multi]

**Community SwiftUI examples cluster at 20–40, and Apple's samples commonly pair the container spacing
with the stack spacing.** No source states whether that pairing is required or coincidental — treat it
as a starting point to verify visually, not a rule. [multi]

**On AppKit the deliberate default is 0.** `NSGlassEffectContainerView.spacing` defaults to zero, and
Apple describes that default as suitable for batch processing while avoiding distortion — i.e. on the Mac,
zero buys the shared sampling region *without* merging, and is a legitimate production value rather than
an oversight. Do not "fix" a Mac container by copying an iOS number into it. [apple]

## Sizing

**Constrain the container's inner content, never the container.** Sizing the container itself fights the
sampling region it is trying to establish. [single]

```swift
GlassEffectContainer(spacing: 16) {
    VStack { … }
        .frame(width: 74)      // frame goes here
}
```

## When to skip the container

**Reach for a container when two or more glass elements are visible at once and animating or morphing at
the same time.** That is the case where independent sampling regions visibly disagree and where merging
is the whole point. [single]

**A handful of static glass views that never move, resize or morph is an unmeasured trade-off, not a
sin.** Nobody has published a measurement, so "wrap it or else" overstates what is known; wrap them when
they sit close enough to read as a group, and do not treat a lone floating control as a defect. [single]

**Do not scatter related glass elements across several containers.** Separate containers cannot sample
each other, which reproduces exactly the inconsistency the container was meant to remove. [multi]

**Do not put a `Menu` inside a `GlassEffectContainer` without checking it on the target OS** — it broke
Menu morphing on iOS 26.1 and the behavior has changed repeatedly since. See
`known-bugs-and-testing.md`. [version-pinned] (recheck on OS updates)

## Never stack glass on glass

**Glass cannot sample glass, so a vertical stack of individually-glassed panes reads as mud.** Use one
floating glass layer over plain content instead of layering materials. [multi]

```swift
// Wrong: three sampling regions, none of which can see the others.
VStack { Header().glassEffect(); Body().glassEffect(); Footer().glassEffect() }

// Right: content underneath, one glass layer above it.
ZStack { ContentView(); HeaderView().glassEffect() }
```

**A native blurred header plus a custom glass child inside it is the same mistake wearing a hat** — the
inner layer has only the outer layer's output to sample. Use a plain translucent view for header
accessories. [multi]

## Glass in scrolling content

**Keep glass off list and grid rows.** Every row that scrolls into view opens and tears down a sampling
region, and rows are the one place where element count is unbounded. Put glass on the floating overlay
controls above the scroll view, not on the things being scrolled. [multi]

**Avoid scrollable content nested inside a glass surface.** [single]

## The cost model — intuition only

The most-quoted performance model in the community corpus says each glass effect allocates a
`CABackdropLayer` costing three offscreen textures, so five loose glass views cost fifteen textures while
one container shares a single backdrop. `CABackdropLayer` is private Core Animation, the claim is uncited
in all three files that repeat it, and no source measured it. [single]

**Use it as intuition — glass is expensive per element, sharing is cheaper — and never quote the
arithmetic as a measured figure.** The defensible, source-backed statements are: real-time refraction
consumes GPU memory; glass samples more area than the element occupies; animating glass is the expensive
case; cap how many glass elements are on screen at once; test on older hardware. [multi] [apple]

Anything stronger than that needs a trace. Measurement method and instrumentation live in the
liquid-glass-motion skill (`performance-and-instrumentation.md`). The one published measurement *method*
worth copying: capture scroll performance with and without glass on a low-end device, so the glass cost is
isolated rather than guessed. [single]

**Never cite the "13% vs 1% battery" figure.** It is an unsourced single-device beta anecdote that has
been copied across the corpus. [multi] (rejected)

## Merging vs morphing vs union

Three different mechanisms share the container, and confusing them wastes time:

- **Merging** is automatic: two glass views inside container `spacing` of each other fuse their shapes. [multi]
- **Morphing** is an insertion/removal transition driven by `glassEffectID(_:in:)` plus a `@Namespace`
  plus an animated hierarchy change — the container and its spacing are preconditions, not the trigger.
  iOS 26.0+. [multi]
- **Union** (`glassEffectUnion(id:namespace:)`, iOS 26.0+) forces views into one continuous shape when
  they are too far apart for `spacing` to merge them, or are generated dynamically and share no stack
  parent. Different `id`s partition the set into subgroups. [multi]

Full treatment of the last two belongs to the liquid-glass-motion skill; do not re-derive it here.

## Glass over a hosted Metal layer

**`glassEffect` samples a `CAMetalLayer` sibling correctly; SwiftUI `Material` does not.** A
`MTKView`/`CAMetalLayer` hosted through `NSViewRepresentable`/`UIViewRepresentable` is not part of
the SwiftUI render tree, and a `Material` placed over it resolves against the *window* background
instead — it reads as nothing at all. Glass does not share that limitation: floating glass chrome
over a Metal-drawn canvas refracts the real rendered content.

Consequence for review: do **not** flag glass over a Metal canvas as a "nothing to refract"
violation (the `flat tinted rectangle` rule), and do not propose compositing chrome into the Metal
draw to fix a sampling problem that does not exist. The inverse is a real finding — a hand-rolled
gradient scrim over a Metal canvas is often correct precisely *because* `Material` failed there.
`[single — live-verified on macOS 26, 2026-08]`

## Checklist

- Glass elements that sit near each other share one `GlassEffectContainer`. [multi]
- Related glass is not split across multiple containers. [multi]
- `spacing:` was chosen against the real gap between elements, not copied. [multi]
- A Mac container's `spacing: 0` was left alone rather than "fixed" to an iOS value. [apple]
- Frames are applied to the container's content, not the container. [single]
- No glass on scrolling rows; no glass stacked on glass. [multi]
- No performance claim in the diff rests on the texture-count model or the battery figure. [single] [multi]

# Material and variants

Choosing whether to use glass at all, the three `Glass` variants, tint, shape, `interactive()`,
modifier order, and the ways glass silently stops looking like glass.

Containers and the sampling rule: see `containers-and-sampling.md`. Toolbars: see
`toolbars-and-scroll-edge.md`. Morphing and animation: see the liquid-glass-motion skill.

## Availability baseline

- `glassEffect(_:in:isEnabled:)`, the `Glass` value (`.regular`, `.clear`, `.identity`, `.tint(_:)`,
  `.interactive(_:)`), `GlassEffectContainer`, `glassEffectID(_:in:)`, `glassEffectUnion(id:namespace:)`,
  `GlassEffectTransition`, `scrollEdgeEffectStyle(_:for:)` and the glass button styles are all
  **iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0 — and unavailable on visionOS.** [verified]
- Apple's rendered documentation shows "visionOS 1.0" for these symbols. That is a rendering artifact;
  the SDK annotation `@available(visionOS, unavailable)` is authoritative. [verified]
- The entire iOS 26 glass surface carries into iOS 27 unchanged: no new glass APIs, none deprecated. [verified]
- Gate per platform, never with one combined guard. See `availability-and-sdk27.md`. [verified]

## Decide whether glass belongs here at all

**Put glass on the functional layer that floats above content, never on content itself.**
Glass reads as depth only while there is a content layer underneath it to be read as further away;
glassing lists, tables, media, text blocks or a full-screen background destroys that separation. [multi]

**Glass needs something worth refracting.** The material samples and bends what is behind it, so over a
flat single-color background there is nothing to bend and the result reads as a plain tinted rectangle —
the code is correct and the effect is simply absent. [single]

**Let content run edge-to-edge behind the chrome.** This is a layout requirement, not a styling
preference: the glass surface has to overlap real content for refraction to have any input. [single]

**Avoid pure black behind glass** for the same reason — refraction over black is visually flat. [single]

**Keep one dominant glass layer per region.** A native blurred bar plus a custom glass child inside it
produces muddy layering, because the second layer has only the first layer's output to sample. [multi]

**Build hierarchy with spacing, grouping and typography before reaching for any material.** Glass is the
last tool for hierarchy, not the first. [single]

**When reviewing, decide where glass should NOT be used, not only where it should.** [multi]

## The three variants

**`.regular` is the default and the right answer for nearly all chrome** — toolbars, bars, floating
controls, standard surfaces. Medium transparency, fully adaptive to whatever passes underneath.
iOS 26.0+/macOS 26.0+. [multi]

```swift
Text("Label").padding().glassEffect()          // == .glassEffect(.regular, in: .capsule)
```

**Use `.clear` only for a small floating control over media-rich content, and only with a dimming layer
under it.** It is high-transparency with *limited* adaptation, so it does not rescue its own legibility
the way `.regular` does. iOS 26.0+/macOS 26.0+. [multi] Three conditions its source states — media-rich
backdrop, backdrop tolerates dimming, foreground content is bold and bright — come from one lineage. [single]

**`.identity` is "no glass", used as a value rather than as a missing modifier.** iOS 26.0+/macOS 26.0+. [multi]

**Do not adopt "never mix `.regular` and `.clear`" as an absolute.** Two community sources assert it;
it contradicts their own variant-selection guidance, since `.clear` is correct over media regions and
`.regular` correct elsewhere, which means a real app contains both. [multi] (rejected as over-restriction)

## `.identity` is how you toggle glass conditionally

**Never wrap `glassEffect` in a custom `.if` view modifier.** Apple bans the pattern outright: the two
branches are different view types, so structural identity breaks, `@State` in that view and every
descendant resets, and animations degrade into an abrupt remove-and-insert instead of interpolating. [verified]

**Swap the `Glass` value instead, or pass `isEnabled:`.** The modifier stays in the tree, so identity
survives and the change can animate. [multi]

```swift
// Correct — one view type, glass varies by value.
content.glassEffect(showsGlass ? .regular : .identity, in: .rect(cornerRadius: 16))

// Also correct — same effect through the modifier's own parameter.
content.glassEffect(.regular, in: .rect(cornerRadius: 16), isEnabled: showsGlass)
```

The claim that `.identity` additionally avoids a layout recalculation comes from a single source
lineage; treat the identity-preservation argument as the load-bearing one. [single]

**Do not rip out an existing `.if` modifier you find in a codebase during unrelated work** — removing it
changes behavior. Flag it in review instead. [verified]

## Tint

**Tint only when the color carries meaning** — primary action, live state, alert. Tint is a hierarchy
signal, and tinting every surface for variety destroys the signal. iOS 26.0+/macOS 26.0+. [multi]

```swift
.glassEffect(.regular.tint(.blue))
```

**`.tint(_:)` and `.interactive(_:)` chain in either order** — they build the same `Glass` value. [multi]

**`.buttonStyle(.glass(_:))` takes a `Glass` value**, so a configured glass button needs no hand-rolled
`glassEffect`. The static `glass(_:)` function reads iOS 26.0 on the extension, but the
`GlassButtonStyle(_:)` initializer it calls is annotated **iOS 26.1 / macOS 26.1** — pin to 26.1. [verified]
`glassProminent` has **no** configurable overload; tint it with `.tint(_:)` on the button. [verified]

## Shape

**The default shape is a capsule; pass `in:` for anything else.** iOS 26.0+/macOS 26.0+. [apple]

```swift
.glassEffect(in: .rect(cornerRadius: 16))     // also .capsule, .circle, .ellipse, any Shape
```

**Use a concentric shape rather than a guessed radius when the glass sits inside a sheet, card or window
corner.** Concentric corners keep the inner and outer radii visually parallel across device geometries,
which is what makes a nested surface read as native. `ConcentricRectangle` is **iOS 26.0+, macOS 26.0+,
and genuinely visionOS 26.0+** (it is not a glass API, so the visionOS exclusion does not apply). [verified]
The `RoundedRectangle(cornerRadius: .containerConcentric)` / `.rect(cornerRadius: .containerConcentric)`
spelling is widely attested across sources. [multi]

**On the iOS 27 SDK, `GeometryProxy.concentricCornerRadii` / `concentricCornerRadii(in:)` give the
concentric radii directly**, without rendering a `ConcentricRectangle` to get them. iOS 27+. [verified]

**Never shape glass with `.cornerRadius(_:)`** — it is soft-deprecated as of the 27 SDKs; use `clipShape`,
a `fill`, or the `in:` shape argument. [verified]

**Glass shape is not the hit area.** Taps land on the label or symbol, not the whole pane, so restate the
shape with `contentShape` when the full glass area should be tappable. [multi]

```swift
.glassEffect(.regular, in: .rect(cornerRadius: 16))
.contentShape(.rect(cornerRadius: 16))
```

## `interactive()`

**`interactive()` makes the material respond to input in real time** — press scaling, release bounce,
shimmer, and illumination from the touch or pointer location that radiates into nearby glass. [multi]

**It is available on macOS, not iOS-only.** `Glass.interactive(_:)` carries no per-member availability
annotation, so it inherits the type's: **iOS 26.0, macOS 26.0 (and Mac Catalyst), tvOS 26.0,
watchOS 26.0; visionOS unavailable** — verified in the native macOS SDK slice, and Apple states the Mac
path carries a dedicated pointer optimization. Use it on Mac; do not gate it out. [verified]

**The "iOS only" claim in several community sources is false and traces to one AppKit sample.** That
sample hand-rolls hover with `NSTrackingArea` because AppKit's `NSGlassEffectView` sits below SwiftUI and
has no `Glass` value to configure — an AppKit-level limitation, not a statement about the SwiftUI API.
See `appkit-and-mac-windows.md`. [verified]

**Apply it only to surfaces that actually respond to touch, pointer or drag.** It adds continuous gesture
tracking and animation updates, and on an inert view it buys nothing. [multi]

**Do not add it to buttons.** `.buttonStyle(.glass)` and `.glassProminent` already carry the interactive
behavior; a second layer is redundant. [multi]

**`.allowsHitTesting(false)` does not suppress the visual reaction** — only `.disabled(true)` does, and
that also changes appearance. See `known-bugs-and-testing.md`. [verified]

## Modifier order

**Apply `.glassEffect()` after every modifier that affects the view's layout or appearance.** The
material is sized and shaped from the view it wraps, so padding, frame and foreground styling must
already be in place. This is the single most-repeated rule across every source. [apple] [multi]

```swift
Image(systemName: "sparkles")
    .font(.title2)
    .padding(12)          // layout first
    .glassEffect()        // material last
```

## Two things that silently collapse the material

**Never set `opacity` below 1 on a glass view or on any ancestor of one.** Partial opacity forces the
subtree into its own composited layer, and the refraction that defines the material collapses — the view
still renders, it just stops looking like glass. [single]

**Never stack glass on glass.** Glass cannot sample glass, so a stack of glassed views reads as mud; use
one floating glass layer over plain content. Mechanism and the container rule: `containers-and-sampling.md`. [multi]

## Glass appearance is not yours to assert

**Glass renders differently on the simulator than on hardware, in both directions.** Never accept a
simulator screenshot as visual acceptance for a glass change. [verified]

**Glass appearance is a user setting.** iOS 26.1 added Clear/Tinted presets; iOS 27 replaces them with a
continuous intensity slider (Settings → Appearance → Liquid Glass). Never assert exact glass pixels in a
screenshot test, and record which setting a reference capture was taken under. [verified]

**Dark, muddy glass over a bright or light-gray background in Dark Mode is by design, not a bug.** Apple
DTS closed this as expected behavior; the fix is adaptive background colors in your own app, per the Dark
Mode guidance — not a glass workaround. [verified]

**On the 2027 OSes, apps built with Xcode 27 automatically pick up a refreshed glass appearance** — better
diffusion of complex content behind the material, a darkened edge, brighter specular highlights. No code
change, but existing screenshots will differ. [verified]

## Checklist

- Glass sits on the functional layer only; content stays unglassed. [multi]
- There is real, varied content behind every glass surface. [single]
- No `opacity < 1` on any glass view or its ancestors. [single]
- No glass stacked on glass; one dominant glass layer per region. [multi]
- Conditional glass uses `.identity` or `isEnabled:`, never a custom `.if` modifier. [verified]
- `.glassEffect()` comes after all layout and appearance modifiers. [apple] [multi]
- `.clear` appears only over media, with a dimming layer. [multi] [single]
- Tint carries meaning; it is not decoration. [multi]
- `interactive()` is on interactive surfaces only, and not doubled up on glass buttons. [multi]
- Full-pane tap targets restate the shape with `contentShape`. [multi]
- Corners use `clipShape` / the `in:` shape / a concentric shape — never `.cornerRadius(_:)`. [verified]
- Availability is gated per platform, and visionOS is excluded from glass entirely. [verified]
- No glass appearance assertion rests on a simulator capture or a fixed pixel value. [verified]

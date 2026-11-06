# Transitions and navigation

Owns: zoom navigation transitions, custom `Transition` types, how toolbar and sheet chrome behaves
during a presentation, the pointer-versus-touch restraint rule, and control handoff across a layout
change. For glass morphing inside one screen see `morphing.md`; for scroll-linked motion see
`scroll-driven.md`; for the toolbar API inventory see the liquid-glass skill's
`toolbars-and-scroll-edge.md`.

## Zoom navigation transitions are iOS 18, not iOS 26

`matchedTransitionSource(id:in:)` and `navigationTransition(.zoom(sourceID:in:))` shipped in
**iOS 18 / macOS 15**. Several widely copied write-ups gate them behind `#available(iOS 26, *)`,
which needlessly drops the transition for a large installed base. `[verified]`

Requirements, all of which fail **silently** by falling back to a standard push: `[multi]`

- The destination is inside a `NavigationStack` or `NavigationSplitView` (not `NavigationView`, not
  hand-rolled navigation). Sheets and `fullScreenCover` work too.
- `.navigationTransition(...)` sits on the destination's **outermost** view, not on an inner
  container.
- The `@Namespace` is declared in a **common ancestor** of source and destination.
- Source and destination IDs match in **value and type**.
- The ID is stable across view updates — never a fresh `UUID()`.

```swift
@Namespace private var namespace

// Source: the ID of the item this row represents.
ForEach(items) { item in
    NavigationLink(value: item) { Thumbnail(item) }
        .matchedTransitionSource(id: item.id, in: namespace)
}
.navigationDestination(for: Item.self) { item in
    DetailView(item: item)
        .navigationTransition(.zoom(sourceID: item.id, in: namespace))
}
```

### The `selected?.id ?? ""` bug

A pattern that circulates in sample code derives the **source** ID from the current selection:

```swift
.matchedTransitionSource(id: selected?.id ?? "", in: namespace)   // wrong
```

Before selection this is `""`, so no source exists when the transition begins and it degrades to a
push. It also mixes the model's ID type with `String` in the `??`, which usually will not
type-check. The source ID must identify **the item the view represents**, which exists before any
selection happens. `[multi]`

Keep source and destination sizes comparable and shapes compatible (square → circle reads as a
glitch unless intended); the zoom interpolates between them literally. `[single]`

Reduce Motion: `.navigationTransition(.zoom)` is one of the APIs the system already adapts — do not
add your own gate around it. Same for `.contentTransition(.numericText())`, `.symbolEffect`, and
`.sensoryFeedback`. `[single]` See `reduce-motion.md`.

## Custom Transition types

`Transition` (iOS 17+/macOS 14+) replaces `AnyTransition.modifier(active:identity:)`. Implement
`body(content:phase:)` over `TransitionPhase`: `.willAppear`, `.identity`, `.didDisappear`.
`[multi]`

Key off `phase.isIdentity` rather than testing `.willAppear` alone, or removal is left unanimated —
the transition covers the entry and does nothing on the way out. `[multi]`

```swift
struct Defocus: Transition {
    var radius: CGFloat = 8

    func body(content: Content, phase: TransitionPhase) -> some View {
        let resolved = phase.isIdentity     // true at rest, false at both ends of the trip
        return content
            .blur(radius: resolved ? 0 : radius)
            .opacity(resolved ? 1 : 0)
    }
}

extension Transition where Self == Defocus {
    static var defocus: Defocus { Defocus() }   // reads as `.transition(.defocus)`
}
```

Before writing one, check the built-ins: `.blurReplace`, `.push(from:)`, `.move(edge:)`,
`.scale(_:anchor:)`, `.offset(_:)`, composed with `.combined(with:)` and split with
`.asymmetric(insertion:removal:)`. Asymmetric is usually the right call — a card that scales in and
slides out reads better than one `.slide` in both directions. `[multi]`

Two correctness rules that account for most "my transition does nothing" reports: `[multi]`

- **`.transition()` belongs on the view being inserted or removed**, never on an always-present
  parent. A `.transition` on a `VStack` that never leaves the hierarchy is inert.
- **The animation context must live outside the conditional.** An `.animation(...)` written inside
  the `if` is destroyed together with the view, so nothing remains to drive the exit. Put
  `withAnimation` at the mutation site, or `.animation(_:value:)` on an enclosing view that
  survives. See `animation-fundamentals.md`.

Never `.transition(.scale)` to zero — the default scales from 0 and the element vanishes into a
point, which reads as broken. Floor at 0.9–0.95 and combine with opacity. `[single]`

`matchedGeometryEffect` (iOS 14+) is the in-place shared-element tool for a single hierarchy, and it
allows exactly **one visible source per ID at a time**. `.opacity(0)` still counts as present, so
toggle with `if`/`else`, not opacity. For cross-screen continuity use the zoom transition above; for
glass surfaces use `glassEffectID` (`morphing.md`) — `matchedGeometryEffect` moves a frame but does
not animate the material. `[multi]`

## Toolbar behaviour during transitions

Toolbar controls **lift into the glass bar** during navigation transitions and back out again; the
system owns that motion when you build against the 26 SDK. Do not hand-animate toolbar items in and
out to reproduce it, and do not re-add custom bar backgrounds or scrim darkening — they fight the
lift and the scroll-edge effect. `[apple]`

Give each `ToolbarItem` a **stable `id`** when its content varies across navigation. Without one the
system cannot match items across the transition and controls animate to unrelated positions.
`[single]`

```swift
ToolbarItem(id: "done") { Button("Done") { … } }
```

`ForEach` conforms to `ToolbarContent` and back-deploys to iOS 16 / macOS 13 when built with the 27
SDK, so data-driven toolbars need no availability gating — but the individual items still need
stable IDs. `[verified]`

## Sheets and popovers

- Partial-height sheets get a Liquid Glass background automatically (they need at least one partial
  detent). **Remove `presentationBackground(_:)`** — it overrides the material and blocks the sheet's
  own morph. `[multi]`
- A sheet can zoom out of the control that presented it: `.matchedTransitionSource(id:in:)` on the
  toolbar button, `.navigationTransition(.zoom(sourceID:in:))` on the presented content. `[multi]`
- `.transition()` does **not** affect modal presentation. `.sheet` and `.fullScreenCover` use
  system-managed animation; customise by animating content *inside* the presented view or by using
  the zoom transition. `[multi]`
- **Building against the iOS 27 SDK resets control environment values inside sheets and popovers**:
  `controlSize`, `buttonSizing`, `buttonRepeatBehavior`, `menuIndicatorVisibility`, and
  `ButtonBorderShape` all return to defaults. Any glass button sizing or shape you relied on
  inheriting into a sheet changes appearance silently — set it explicitly inside the sheet.
  `[verified]`

## Pointer versus touch

Liquid Glass responds with **greater emphasis to direct touch and produces subdued effects for a
trackpad or pointer**. Custom motion should follow the same restraint: what reads as satisfying
under a finger reads as overwrought under a cursor. `[multi]`

Practically, on Mac and on iPad with a pointer attached: shorten durations, cut overshoot toward
critically damped, and drop decorative flourishes rather than scaling them down. This is a design
rule, not an API — there is no environment value that reports "pointer attached", so tie it to the
platform and to whether the interaction was pointer-driven. `[multi]`

Do **not** implement this by disabling `.interactive()` on Mac. That effect is available on
macOS 26.0+ and Apple tunes it for the pointer specifically, so removing it makes Mac glass *less*
correct, not more restrained — restrain your own motion instead. `[verified]` See `morphing.md`.

Same principle upstream of all of this: check whether the system already provides the motion before
writing any. System components adapt to accessibility settings and input method for free; custom
animation cannot match that without work you will not do on every OS release. `[apple]`

## One overlay, not two copies

When a control appears to travel between two positions across a layout change — a title that becomes
a toolbar button, a filter row that docks into a header — do **not** render both copies and
cross-fade them. Two live copies means two hit targets, two accessibility elements, and a visible
double image mid-flight. `[single]`

Expose a source anchor and a destination anchor with `anchorPreference`, then render **exactly one**
overlay that interpolates position and size between them from a single progress value:

```swift
enum Slot: Hashable { case origin, landing }

// Both of these publish a rectangle and nothing else — neither draws the control.
TitleBlock()
    .anchorPreference(key: HandoffAnchors.self, value: .bounds) { [Slot.origin: $0] }

ToolbarWell()
    .anchorPreference(key: HandoffAnchors.self, value: .bounds) { [Slot.landing: $0] }

// The single real control, placed into a frame interpolated from one progress value.
.overlayPreferenceValue(HandoffAnchors.self) { anchors in
    GeometryReader { proxy in
        if let start = anchors[.origin], let end = anchors[.landing] {
            let box = blend(proxy[start], proxy[end], handoff)
            TravellingControl()
                .frame(width: box.width, height: box.height)
                .position(x: box.midX, y: box.midY)
        }
    }
}

func blend(_ from: CGRect, _ to: CGRect, _ t: CGFloat) -> CGRect {
    func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
    return CGRect(x: lerp(from.minX, to.minX), y: lerp(from.minY, to.minY),
                  width: lerp(from.width, to.width), height: lerp(from.height, to.height))
}
```

The two anchor views exist to report geometry, so neither of them renders the control; the overlay
is the only thing on screen and the only hit target. Where the travelling control is glass, prefer
`glassEffectID` inside one `GlassEffectContainer` — the material morphs properly and you still end
up with a single element. `[single]`

## Checklist

- `matchedTransitionSource` / `navigationTransition(.zoom)` are **iOS 18+**; do not gate them behind iOS 26. `[verified]`
- The source ID identifies the item, not the current selection — it must exist before selection. `[multi]`
- IDs match in value and type, are stable across updates, and the `@Namespace` lives in a common ancestor. `[multi]`
- `.navigationTransition` goes on the destination's outermost view, inside a `NavigationStack`. `[multi]`
- Custom `Transition`s key off `phase.isIdentity`, or removal never animates. `[multi]`
- `.transition()` goes on the inserted/removed view; the animation context stays outside the conditional. `[multi]`
- One visible `matchedGeometryEffect` source per ID; `.opacity(0)` still counts as present. `[multi]`
- Let toolbar controls lift themselves; give varying `ToolbarItem`s stable IDs. `[apple]` `[single]`
- Delete `presentationBackground` from glass sheets. `[multi]`
- On the 27 SDK, re-set control size/shape explicitly inside sheets and popovers. `[verified]`
- Subdue custom motion for pointer input the way the system subdues glass. `[multi]`
- Control handoff renders exactly one interpolated overlay, never two visible copies. `[single]`

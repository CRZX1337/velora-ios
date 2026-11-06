# Scroll-driven motion

Owns: where scroll-linked work should run, how to derive and spend a scroll progress value, the
`scrollTransition` phase model, and how custom scroll motion coexists with glass chrome that is
already reacting to the same scroll. The chrome APIs themselves (`scrollEdgeEffectStyle`,
`tabBarMinimizeBehavior`, `toolbarMinimizationBehavior`, `ToolbarSpacer`) are inventoried in the
liquid-glass skill's `toolbars-and-scroll-edge.md` — this file only covers the interplay.

## Push per-frame work to the renderer

For purely visual scroll effects — opacity, scale, rotation, blur, offset — use `scrollTransition`
or `visualEffect(in:)`. Both run per frame **in the renderer and skip body re-evaluation entirely**,
so nothing invalidates as you scroll. Both are iOS 17+/macOS 14+. `[apple]`

```swift
.visualEffect { content, proxy in
    let minY = proxy.frame(in: .scrollView).minY
    return content.offset(y: minY > 0 ? -minY * 0.5 : 0)   // parallax, zero body runs
}
```

The anti-pattern is any path that turns scroll position into state: writing `contentOffset` into
`@State`, into an `@Observable` that views read directly, or — worst — into the **environment**.
Every write to any environment key forces every view reading any key in that subtree to be
re-checked, so a per-frame value in an `@Entry` is an invalidation storm. A `TimelineView` or
`CADisplayLink` driving an environment value is the same mistake with a different clock. `[apple]`

Closures SwiftUI may run off the main thread — the `visualEffect` closure, `Shape.path(in:)`,
`Layout` methods, the `onGeometryChange` transform — must **capture values, not touch `@MainActor`
state**, and must never write state at all. `[multi]`

```swift
.visualEffect { [pulse] content, proxy in           // captured, not read from self
    content.blur(radius: pulse ? 5 : 0)
}
```

## When the value must drive logic, coarsen it

Reach for observed scroll state only when the value drives something that is not rendering —
prefetching, analytics, a haptic, a toolbar mode. Then derive the smallest `Equatable` value you can
and publish only that. `[apple]`

```swift
@MainActor @Observable
final class HeaderState {
    private(set) var isCollapsed = false

    // Called every frame, but only a threshold crossing writes — so readers invalidate on flips.
    func offsetChanged(to y: CGFloat) {
        let collapsed = y > 50
        if collapsed != isCollapsed { isCollapsed = collapsed }
    }
}
```

The raw offset is never stored, so no view can accidentally start reading it. `isCollapsed` is the
whole published surface.

`onScrollGeometryChange(for:of:action:)` (iOS 18+/macOS 15+) does the same job at the source: it
transforms a rapidly changing `ScrollGeometry` into an `Equatable` and runs the action only when
**that** changes. Extract a `Bool` and the action fires on threshold crossings; extract
`contentOffset` and it fires every frame. `[multi]`

```swift
.onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 50 }
    action: { _, past in withAnimation(.easeOut(duration: 0.2)) { showTitle = !past } }
```

The same coarsening applies per row: give each list row its own `@Observable` rather than having
every row read one shared array. A row then invalidates at most **twice — entering and leaving** —
no matter how fast the scroll. `[apple]`

Never wrap a raw scroll callback in `withAnimation`. Scroll handlers fire per frame, so that starts
an animation per frame; gate on the threshold crossing as above. `[multi]`

## One normalized progress drives everything

Derive **one** `progress` in `0...1` from real scroll offset, then drive offset, opacity, blur,
scale, and chrome state from that single value. The alternative — parallel booleans (`isExpanded`,
`isSnapped`, `isShowingSecondary`) each with their own animation — desynchronises the moment a
gesture is interrupted. `[single]` This comes from one source, but it is architecturally sound and
worth following: it is the same discipline as a gesture's normalized completion fraction, and it is
the only shape that survives interruption cleanly.

Its corollary is the sharper half of the rule: **never mix two animation sources for one property.**
If `progress` drives opacity, no `.animation(_:value:)` and no `withAnimation` may also touch
opacity — they fight, and the result is a property that lags its siblings. `[single]`

```swift
// `.clamped(to:)` shows up in circulated samples but is not in the standard library — either
// spell the clamp out as below, or add the extension yourself.
.onScrollGeometryChange(for: CGFloat.self) { geometry in
    geometry.contentOffset.y + geometry.contentInsets.top
} action: { _, offset in
    progress = min(max(offset / max(revealDistance, 1), 0), 1)
}
```

Measure `revealDistance` — do not hard-code the divisor. Read the real reveal distance with
`onGeometryChange`, guard against zero, and write it back only when the measured value actually
changes, or the measurement feeds the layout that produces it and you get a feedback loop.
`[single]`

## scrollTransition phase math

`scrollTransition` hands you a `ScrollTransitionPhase` with three cases — `.topLeading` (entering),
`.identity` (fully visible), `.bottomTrailing` (leaving) — plus `phase.value`, a signed magnitude in
roughly −1…1. `[multi]`

- `phase.isIdentity` is the binary form: on-screen or not. Use it for a simple fade or dim.
- `phase.value` is the continuous form: multiply it into offsets, rotations, or scale for motion
  that tracks position rather than snapping between two states.

```swift
.scrollTransition { content, phase in
    content
        .opacity(phase.isIdentity ? 1 : 0.4)
        .scaleEffect(1 - abs(phase.value) * 0.1)
}
```

Apply a second `scrollTransition` to an overlay (a caption over an image, say) to give it a
different curve from the thing it sits on. `[single]`

## GeometryReader versus visualEffect

`visualEffect` gives you the view's `GeometryProxy` **without inserting a `GeometryReader` into the
layout**, and its closure can only apply visual modifiers — offset, scale, rotation, blur, hue —
nothing that triggers a re-layout. That restriction is exactly why it stays fast inside a scroll
view. `[multi]`

Use `GeometryReader` only when you actually need the measurement to affect layout, and remember it
expands to fill and changes the layout of what it wraps. For "where is this view, so I can shift it
visually", `visualEffect` is the correct tool and `GeometryReader` is a regression. `[multi]`

## Chrome that reacts to the same scroll

The system is already animating on scroll, and your motion has to share the frame with it: `[apple]`

- `tabBarMinimizeBehavior(_:)` (**iOS 26.0**, iOS-only among the non-macOS platforms) minimizes the
  tab bar as content scrolls. `[verified]`
- `scrollEdgeEffectStyle(_:for:)` (**iOS 26.0+**, unavailable on visionOS) controls the treatment
  where content meets a bar — `.soft` fades gradually (the iOS default), `.hard` cuts with a
  dividing line (mostly a Mac look). **One per view edge**, and never add one where no floating UI
  exists. `[multi]`
- Bar minimization on the toolbar side was renamed at iOS 27 beta 4 —
  `toolbarMinimizationBehavior(_:for:)`. Do not confuse it with `tabBarMinimizeBehavior`. See
  `toolbars-and-scroll-edge.md`. `[verified]`

Three interplay rules: `[multi]`

1. **Delete custom scrim and background-darkening under bars.** The scroll edge effect already
   blurs and fades content there; running both produces a double gradient that darkens as you
   scroll.
2. **Fold chrome state into the same `progress`.** If a header collapses while the tab bar
   minimizes, drive your header from progress and let the system own the bar — do not add a second
   threshold that fires at a slightly different offset.
3. **Keep glass off scrolling rows.** Glass belongs on the chrome floating above the scroll view;
   per-row glass is a separate sampling region per cell, re-rendered every frame of the scroll.

Also worth knowing while auditing a scrolling screen: continuous animations — `PhaseAnimator`
without a trigger, `.symbolEffect(.pulse)`, anything `repeatForever` — keep running while scrolled
out of view, because a lazy stack keeps buffer views alive. Prefer triggered animations inside
scrolling content. `[single]`

## Glass over animating content: an update-frequency heuristic

Glass samples a region larger than itself, every frame, from whatever is behind it. The cost
therefore scales with how often the backdrop changes, not with the glass element itself. `[apple]`

The working heuristic, offered as a heuristic because **no published threshold exists**: `[single]`

- Backdrop changing at around **1 Hz** (a clock, a progress figure, a slowly crossfading photo) —
  fine, ship it.
- Backdrop changing at **display rate** (a 60 Hz audio visualiser, a shader-driven field, video with
  motion) under glass — unproven, and likely to fight any morph running at the same time, since both
  are re-deriving lensing per frame over content that has itself changed.

If you need chrome over a fast-moving backdrop, measure it before committing: Instruments →
Animation Hitches on a real device, on the target OS, with the app in Release. Do not accept the
simulator as evidence — glass renders differently there, and the SwiftUI Instruments lane comes back
empty on the simulator anyway. See `performance-and-instrumentation.md`. `[verified]`

## Checklist

- Purely visual scroll effects use `scrollTransition` or `visualEffect(in:)`; they skip body re-evaluation. `[apple]`
- Never route a per-frame scroll value through `@State` fan-out or the environment. `[apple]`
- `visualEffect` closures capture values, never read `@MainActor` state and never write state. `[multi]`
- When scroll must drive logic, coarsen to a threshold and publish only the coarsened value. `[apple]`
- `onScrollGeometryChange` extracts the smallest `Equatable` value — a `Bool` where a `Bool` will do. `[multi]`
- Never wrap a raw per-frame scroll callback in `withAnimation`. `[multi]`
- One normalized progress drives every property of a scroll-linked reveal. `[single]`
- Exactly one animation source per property. `[single]`
- Measure the reveal distance; never hard-code the divisor; guard against zero and feedback loops. `[single]`
- Prefer `visualEffect` over `GeometryReader` whenever the measurement is only used visually. `[multi]`
- Delete custom scrims under bars; one scroll edge effect per edge. `[multi]`
- Keep glass on the chrome, not on scrolling rows. `[multi]`
- Glass over a display-rate backdrop is unproven — measure on hardware before shipping it. `[single]`

# Phase animators, keyframe animators, and symbol effects

Multi-step motion: sequences that run through named states, tracks that run in parallel on a
timeline, and the SF Symbols effects that cover most of what people hand-roll. This file also
corrects four claims that recur across the corpus and produce wrong review findings.

Tags: `[verified]` SDK/doc-checked this session · `[apple]` Apple doc, unverified · `[multi]` 2+
independent sources agree · `[single]` one source, verify before relying on it.

---

## 1. PhaseAnimator

`PhaseAnimator` / `.phaseAnimator(...)` walks a sequence of phases, applying your modifiers for each
one and animating between them. Phases run **sequentially, never in parallel** — if two properties
need different curves at the same instant, that is a keyframe animator. iOS 17+ / macOS 14+ /
tvOS 17+ / watchOS 10+ / visionOS 1+. Nothing changed in iOS 26 or 27. `[verified]`

### The two forms behave completely differently

**Without a trigger, it loops forever.** `phaseAnimator(_:content:animation:)` cycles the phases
continuously from the moment the view appears. It does not run once and settle. `[multi]`

```swift
// Loops for as long as the view exists.
.phaseAnimator([1.0, 1.1]) { view, scale in view.scaleEffect(scale) }
```

Consequences worth knowing before you use this form: `[multi]`

- It keeps running when scrolled out of view. A `LazyVStack` keeps a buffer of off-screen rows
  alive, so a no-trigger animator inside a row burns CPU and battery where nobody can see it. In
  scroll views, prefer the trigger form.
- It has no state change to gate on, so Reduce Motion cannot be handled by swapping the animation.
  Branch at the view level instead — see `reduce-motion.md`.

**With a trigger, one change plays the whole sequence once and settles back on the first phase.** It
does **not** advance one phase per trigger change. These are burst semantics. `[verified]`

```swift
// One tap = one full pulse out and back.
.phaseAnimator([1.0, 1.5, 1.0], trigger: tapCount) { view, scale in
    view.scaleEffect(scale)
}
```

> **Do not "correct" this back.** Apple's own reference page for
> `phaseAnimator(_:trigger:content:animation:)` describes one-phase-per-trigger — "the modifier
> provides its content closure with the value of the second phase … the next time the trigger input
> changes, this procedure repeats" — and **that page is wrong**. It is a documentation defect,
> confirmed against WWDC23 session 10157 ("when a change occurs, it begins animating through the
> phases") plus three independent references. A widely-distributed skill corpus repeats the false
> claim and weights it at 30/100 in its own eval, so a correct answer scores as wrong there. If you
> change this rule, you are changing it to match a known-bad source. `[verified]`

The pulse idiom above is the disproof: under one-phase-per-trigger, a single tap would scale to 1.5
and *stay there* until the next tap.

### Getting the API shape right

**The content closure takes two parameters: `{ content, phase in }`.** A single-parameter
`{ phase in }` closure is a recurring hallucination and does not compile. `[verified]`

```swift
.phaseAnimator(Phase.allCases, trigger: reactionCount) { content, phase in
    content.scaleEffect(phase.scale).offset(y: phase.offset)
} animation: { phase in
    switch phase {
    case .initial: .smooth
    case .move:    .easeInOut(duration: 0.3)
    case .scale:   .spring(duration: 0.3, bounce: 0.7)
    }
}
```

**Prefer a `CaseIterable & Hashable` enum over a raw number array.** Per-phase values live on the
enum as computed properties, so the content closure reads as a description rather than as index
arithmetic. SwiftUI walks `allCases` in declaration order. iOS 17+. `[multi]`

**Use an incrementing counter as the trigger, not a toggled `Bool`.** SwiftUI dedupes equal values,
so rapid taps on a `Bool` collapse into a single sequence. `trigger: tapCount` with `tapCount += 1`
survives tap-spam. iOS 17+. `[single]`

**The `animation:` closure returns the animation used *into* the given phase.** Its declared return
type is `Animation?` — `SwiftUICore.swiftinterface` (MacOSX26.2) reads
`animation: @escaping (Phase) -> SwiftUICore.Animation?` — so `nil` compiles and means *no
animation*, giving that phase an instant cut rather than an error. Return a default (`.smooth`) from
any case you have no opinion about, or you will ship un-animated phases that look like dropped
frames. The same interface confirms the content closure's arity: it takes **two** parameters,
`(PlaceholderContentView<Self>, Phase)`, not one. iOS 17+. `[verified]`

**The content closure runs every frame — apply view modifiers only.** No formatting, no allocation,
no sorting. Precompute in `body` and capture the plain value. iOS 17+. `[multi]`

**In Swift 6 the content and animation closures are `@Sendable`.** Do not read `@State` or
`@Environment` from nested helper closures inside the modifier; capture plain values in `body` first,
or route them through the animated value model. Swift 6. `[multi]`

---

## 2. KeyframeAnimator

Use a keyframe animator when you need **exact values at exact times**, or when several properties
must animate on **different curves simultaneously**. Tracks run in parallel, one per property.
iOS 17+ / macOS 14+. `[multi]`

```swift
.keyframeAnimator(initialValue: AnimationValues(), trigger: likeCount) { content, value in
    content.scaleEffect(value.scale).offset(y: value.verticalOffset)
} keyframes: { _ in
    KeyframeTrack(\.scale) {
        SpringKeyframe(1.2, duration: 0.15)
        CubicKeyframe(1.0, duration: 0.25)
    }
    KeyframeTrack(\.verticalOffset) {
        LinearKeyframe(-20, duration: 0.15)
        SpringKeyframe(0, duration: 0.25)
    }
}
```

**The four keyframe types.** `LinearKeyframe` constant velocity (mechanical); `CubicKeyframe` classic
ease; `SpringKeyframe` natural arrival with optional overshoot; `MoveKeyframe` an instant jump with
no interpolation, for resetting to a baseline mid-sequence. iOS 17+. `[multi]`

**`duration: nil` on a `SpringKeyframe` means the spring's own natural settling time — not zero, not
instant.** `SpringKeyframe`'s `duration` is `TimeInterval?` and defaults to `nil`, so
`SpringKeyframe(1.5)` is valid and animates normally. A review rule in circulation claims omitting
`duration` makes the keyframe instant; it is wrong, and applying it produces false findings.
iOS 17+. `[multi]`

**In a repeating keyframe animator, make every track's total duration equal.** Tracks loop
independently on their own length, so unequal totals drift out of sync after the first cycle.
iOS 17+. `[single]`

**`KeyframeTimeline` evaluates a track outside SwiftUI** — `timeline.duration`,
`timeline.value(time: 0.25)` — which is how you unit-test choreography without a UI test. iOS 17+.
`[multi]`

Same two hazards as phase animators: the content closure runs every frame (modifiers only), and in
Swift 6 the closures are `@Sendable` (capture values, do not read `@State` from nested closures).
`[multi]`

---

## 3. `withAnimation` has a completion API — since iOS 17

**Do not write, and do not accept in review, "SwiftUI has no animation completion callback, so use
`DispatchQueue.main.asyncAfter`."** That advice is outdated and still circulating. iOS 17+. `[multi]`

```swift
withAnimation(.smooth(duration: 0.35), completionCriteria: .logicallyComplete) {
    isPresented = false
} completion: {
    cleanUp()
}
```

`.logicallyComplete` fires when the animation reaches its target value; `.removed` fires when it is
fully removed, which for a spring is later. Hand-timed `asyncAfter` de-synchronizes the moment the
duration or the curve changes. iOS 17+. `[multi]`

For the related trap — a `.transaction { }` completion **without** a `value:` firing exactly once,
ever — see `animation-fundamentals.md` §5.

---

## 4. Choosing between them

| Situation | Use |
|---|---|
| 3+ ordered states, each a whole-view "look" | `PhaseAnimator` `[multi]` |
| Motion that returns to where it started (pulse, shake, bounce) | `PhaseAnimator` with a trigger `[multi]` |
| A different curve per step of the sequence | `PhaseAnimator` with the `animation:` closure `[multi]` |
| Two properties on different curves at the same time | `KeyframeAnimator` `[multi]` |
| Exact value at an exact time (a spec with numbers) | `KeyframeAnimator` `[multi]` |
| Ambient loop with no trigger | `PhaseAnimator` without a trigger — and gate it `[multi]` |
| A single property changing between two states | Neither. `withAnimation` or `.animation(_:value:)` `[multi]` |

Escalate in that order: `withAnimation` first, `PhaseAnimator` at three or more ordered states,
`KeyframeAnimator` only when you need parallel time-based tracks. Do not start at the top. `[multi]`

**Neither animator drives a glass morph.** A glass surface changing size or merging with a
neighbour is a system animation driven by `glassEffectID` plus a state change inside a
`GlassEffectContainer` — see `morphing.md`. Wrapping glass in a phase animator animates the view,
not the material.

---

## 5. Symbol effects

SF Symbol effects cover a large share of what people build by hand, and the system already handles
Reduce Motion for them (see `reduce-motion.md` §2).

**Discrete versus indefinite.** `value:` fires the effect on each change; `isActive:` holds it while
true. Scope with `.byLayer` or `.wholeSymbol`. Options: `.default`, `.repeating`, `.nonRepeating`,
`.repeat(3)`, `.repeat(.periodic(3, delay: 0.5))`, `.repeat(.continuous)`, `.speed(2.0)`. iOS 17+.
`[multi]`

**Availability splits at iOS 18.** iOS 17+: `.bounce`, `.pulse`, `.variableColor`, `.scale`,
`.appear`, `.disappear`, `.replace`. iOS 18+: `.breathe`, `.rotate`, `.wiggle`, and
`.replace.magic(fallback:)`. `[multi]`

**`.symbolEffect` silently does nothing on anything that is not an SF Symbol.** No error, no warning.
iOS 17+. `[multi]`

**`.symbolVariableColor(value:)` does not exist.** It is a fabricated API planted in at least one
eval and repeated by models. The real spelling is the `.variableColor` effect with chained modifiers:
`.cumulative` / `.iterative`, `.reversing` / `.nonReversing`, `.dimInactiveLayers` /
`.hideInactiveLayers`. iOS 17+. `[verified]`

```swift
Image(systemName: "wifi")
    .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: isScanning)
```

**`.drawOn` and `.drawOff` are real, and the `isActive:` overload is valid.** They live in the
**Symbols** framework, not SwiftUI: `iOS 26.0+, macOS 26.0+, tvOS 26.0+, watchOS 26.0+,
visionOS 26.0+`. `DrawOnSymbolEffect` conforms to `IndefiniteSymbolEffect`, which is exactly the
constraint `symbolEffect(_:options:isActive:)` requires, so the call type-checks. `[verified]`

```swift
if #available(iOS 26.0, macOS 26.0, *) {
    Image(systemName: "signature")
        .symbolEffect(.drawOn, options: .default, isActive: hasSigned)
}
```

Four details that matter: `[verified]`

- **Gate the effect, not the modifier — this is the trap.** `symbolEffect(_:options:isActive:)` is
  iOS 17 / macOS 14, so the compiler will not stop you at a lower deployment target; `.drawOn` is
  what requires 26.0. The `#available` check belongs around the effect.
- Variants are `.byLayer`, `.wholeSymbol`, `.individually`; `.drawOff` adds `.reversed` /
  `.nonReversed`.
- Because `DrawOnSymbolEffect` *also* conforms to `TransitionSymbolEffect`, it works as a
  transition: `.transition(.symbolEffect(.drawOn))`.
- Unlike the Liquid Glass APIs, these **are** available on visionOS 26 — do not sweep them into the
  glass visionOS exclusion.

**Variable-value symbols are a separate mechanism from effects.**
`Image(systemName:variableValue:)` takes 0.0…1.0 for percentage fill (iOS 16+), and
`.symbolVariableValueMode(.draw)` / `.color` chooses how that value renders (iOS 26+ / macOS 26+).
`[single]`

**`.contentTransition(.numericText(...))` and `.contentTransition(.symbolEffect)` do nothing without
a paired animation.** `.animation(.snappy, value: count)` on the same view is what drives them.
`.contentTransition` and `.numericText` are iOS 16+; the `.symbolEffect` content transition is
iOS 17+. `[multi]`

---

## Checklist

- [ ] No-trigger `phaseAnimator` is used only where a forever-loop is intended, and it is gated for
      Reduce Motion at the view level. `[multi]`
- [ ] No no-trigger animator lives inside a `LazyVStack`/`List` row. `[multi]`
- [ ] Trigger-form `phaseAnimator` is written expecting the **full sequence per trigger change**, and
      the correction is noted where a reviewer might "fix" it back. `[verified]`
- [ ] Every phase closure is `{ content, phase in }` — no single-parameter form. `[verified]`
- [ ] Triggers are incrementing counters, not toggled `Bool`s. `[single]`
- [ ] Phase/keyframe content closures contain view modifiers only; no work, no `@State` reads from
      nested closures. `[multi]`
- [ ] No review finding claims a missing keyframe `duration` is "instant". `[multi]`
- [ ] Repeating keyframe tracks all have the same total duration. `[single]`
- [ ] No `DispatchQueue.main.asyncAfter` standing in for animation completion. `[multi]`
- [ ] Escalation order respected: `withAnimation` → `PhaseAnimator` → `KeyframeAnimator`. `[multi]`
- [ ] No `.symbolVariableColor(value:)` anywhere. `[verified]`
- [ ] `.drawOn` / `.drawOff` sites gate the **effect** at 26.0, not the modifier. `[verified]`
- [ ] Glass morphs use `glassEffectID`, not a phase or keyframe animator. `[multi]`

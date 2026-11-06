# Animation fundamentals

The SwiftUI animation model, at the level of detail glass motion needs. Every glass morph, toolbar
lift, and scroll-driven effect in this skill is built out of the pieces below, so get these right
before reaching for a glass-specific API.

Tags: `[verified]` SDK/doc-checked this session · `[apple]` Apple doc, unverified · `[multi]` 2+
independent sources agree · `[single]` one source, verify before relying on it.

---

## 1. Springs

**Use a preset unless you can name what is wrong with it.** The three presets are the same spring
with different bounce, and they cover almost every UI case. iOS 17+ / macOS 14+. `[multi]`

| Preset | Equivalent | Use for |
|---|---|---|
| `.smooth` | `spring(duration: 0.5, bounce: 0)` | Appearance and disappearance, no overshoot |
| `.snappy` | `spring(duration: 0.5, bounce: 0.15)` | Default for responsive UI, controls, most glass morphs |
| `.bouncy` | `spring(duration: 0.5, bounce: 0.3)` | Playful feedback, celebrations |

**`.snappy` runs for 0.5 seconds, not 0.3.** All three presets take `(duration:extraBounce:)` with
`duration` defaulting to **0.5**; `extraBounce` adds to the preset's own bounce, it does not replace
it. Two widely-copied community tables list `.snappy` at 0.3 or 0.4 — both are wrong, and anything
derived from them animates faster than the real preset. iOS 17+. `[multi]`

**Four ways to build a spring; prefer the perceptual ones.** `Spring(duration:bounce:)` and
`Spring(response:dampingRatio:)` describe how the motion *feels*; `Spring(mass:stiffness:damping:)`
and `Spring(settlingDuration:dampingRatio:epsilon:)` describe physics. Pick one parameterization for
the whole codebase — mixing them makes two springs impossible to compare by eye. iOS 17+.
`[verified]` — all four initialisers read from `SwiftUICore.swiftinterface` (MacOSX26.2), with
`duration` defaulting to `0.5`, `bounce` to `0.0`, `mass` to `1.0`, and `epsilon` to `0.001`.

**Stay inside `response: 0.2...0.5` and `dampingFraction: 0.7...1.0` for ~95% of UI.** Below 0.2
response reads as twitchy; above 0.6 reads as sluggish and should be reserved for a signature
moment. `dampingFraction: 0` oscillates forever — never ship it. iOS 17+. `[multi]`

**Springs are the wrong tool for constant-speed loops.** A shimmer or breathing pulse needs uniform
velocity: `.linear(duration: 1.2).repeatForever(autoreverses: true)`. A spring accelerates and
decelerates, so a looped spring visibly stutters at the seam. All versions. `[multi]`

**Define 3–5 named animations for the app and use nothing else.** Consistency of feel comes from a
small vocabulary, not from tuning each call site. All versions. `[multi]`

```swift
extension Animation {
    static let tap = Animation.spring(response: 0.2, dampingFraction: 0.85)   // 0.45 for sheets,
    static let hero = Animation.spring(response: 0.5, dampingFraction: 0.85)  // 0.15 for drags
}
```

**Springs retarget on interruption; that is why they are the default for anything interactive.** A
running spring blends into a new target from its current position and velocity instead of snapping,
so a user who taps twice quickly sees one continuous motion — never add code to "wait for the
animation to finish". A spring is also queryable (`spring.value(target:initialVelocity:time:)`,
`.velocity(...)`, `.settlingDuration(...)`), which is how you hand a velocity to Core Animation or
assert motion in a test. `[multi]` / `[single]` for the query API. iOS 17+.

---

## 2. Custom curves without leaving SwiftUI

**SwiftUI does cubic Bezier. Do not drop to Core Animation for a timing curve.** `UnitCurve` covers
it, including a designer-supplied web curve. iOS 17+. `[multi]`

```swift
let overshoot = UnitCurve.bezier(startControlPoint: .init(x: 0.68, y: -0.55),
                                 endControlPoint:   .init(x: 0.27, y: 1.55))
view.animation(.timingCurve(overshoot, duration: 0.4), value: isOpen)
view.animation(.timingCurve(0.68, -0.55, 0.27, 1.55, duration: 0.4), value: isOpen)  // same, inline
```

`UnitCurve` also gives `.value(at:)`, `.velocity(at:)`, `.inverse`, and the named curves. iOS 17+.
`[multi]`

**`CustomAnimation` is the escape hatch above `UnitCurve`.** Implement
`animate(value:time:context:) -> V?` and return `nil` when the animation is complete — that return
is how a decay or physics animation terminates. iOS 17+. `[multi]`

### When Core Animation is genuinely the right layer

Six cases, and a Bezier curve is not one of them: layer-only properties (`shadowPath`, `borderWidth`,
`cornerRadius` on a `CALayer`); additive animations stacking on one property; `CGPath`-driven motion
(`CAKeyframeAnimation.path` with `rotationMode = .rotateAuto`); frame-synchronized drawing via
`CADisplayLink`; `CAMediaTimingFunction`-specific timing inside an existing layer tree; and
performance-critical particle or effect systems. `[multi]`

**Always set the layer's model value to the end state alongside the animation** — Core Animation
animates the *presentation* layer, so without the model write the layer snaps back the moment the
animation is removed. And **never animate the same property from both engines**: SwiftUI and Core
Animation keep separate state, so a property driven by both produces undefined motion. All versions.
`[multi]`

**`preferredFrameRateRange` is a hint, not a setting.** The system picks the actual rate from
hardware, power, thermal state, and everything else animating on screen. Drive per-frame work from
`CADisplayLink.targetTimestamp` and scale the work to the rate you actually got — code that assumes
it forced 120 Hz will misbehave the moment the device throttles. iOS 15+. `[single]`

**The `CAAnimationDelegate` responder-chain cast is a silent failure.** `uiView.next as?
CAAnimationDelegate` yields `nil` — a `UIView`'s `next` responder does not conform — so the
animation runs and the completion callback never fires, with no warning. The `Coordinator` of the
representable is the delegate. This exact line appears in circulated sample code; treat it as a
known-bad pattern. All versions. `[single]`

```swift
func makeUIView(context: Context) -> BadgeView {
    let badge = BadgeView()                                    // layers are built here, never in updateUIView
    badge.layer.add(liftAnimation(reportingTo: context.coordinator), forKey: "lift")
    badge.layer.transform = CATransform3DMakeScale(1.2, 1.2, 1)  // model value, or the layer snaps back
    return badge
}

private func liftAnimation(reportingTo delegate: CAAnimationDelegate) -> CASpringAnimation {
    let lift = CASpringAnimation(perceptualDuration: 0.5, bounce: 0.15)   // iOS 17+
    lift.keyPath = "transform.scale"
    lift.duration = lift.settlingDuration     // ask the spring how long it needs
    lift.delegate = delegate                  // the Coordinator — never `view.next as? CAAnimationDelegate`
    return lift
}
```

`CASpringAnimation(perceptualDuration:bounce:)` (iOS 17+) is the same curve family as SwiftUI's
`Spring(duration:bounce:)`, so bridged motion can match the SwiftUI side exactly: `.smooth` →
`(0.5, 0.0)`, `.snappy` → `(0.5, 0.15)`, `.bouncy` → `(0.5, 0.3)`. `[verified]` — the shared
`duration: 0.5` default is read straight from the SDK: `SwiftUICore.swiftinterface` (MacOSX26.2)
declares all three presets as `(duration: TimeInterval = 0.5, extraBounce: Double = 0.0)`, which is
also why community tables listing `.snappy` at 0.3 or 0.4 are wrong. See §1.

**Four rules for Core Animation inside a representable.** Create layers in `makeUIView`, never in
`updateUIView`; stop display links in `dismantleUIView`; guard against restarting an animation
because `updateUIView` runs on *every* state change; and set model values alongside animations.
`invalidate()` every `CADisplayLink` — a live one keeps the CPU out of idle. All versions. `[multi]`

**On iOS 18+ the bridge is much shorter.** `UIView.animate(.spring(duration: 0.5, bounce: 0.2)) { … }`
takes SwiftUI `Animation` values directly, and `context.animate { … }` inside `updateUIView` inherits
whatever animation the surrounding SwiftUI transaction carries. Prefer these over hand-built
`CABasicAnimation` whenever the property is animatable by UIKit. iOS 18+. `[single]`

---

## 3. Implicit versus explicit, and who wins

**Three scoping tools, three jobs.** `withAnimation(_:) { }` when you own the state mutation (a
button action, an `onChange`); `.animation(_:value:)` when any change to that value should always
animate; `.animation(_:body:)` (iOS 17+) when only selected modifiers should animate. `[multi]`

**Bare `.animation(_:)` is deprecated and animates every change in the subtree.** Always bind a
value. iOS 15+ deprecation. `[multi]`

**Place the animation modifier *after* the modifiers it should animate.** Modifier order is
evaluation order, so an `.animation` above `.frame` never sees the frame change. All versions.
`[multi]`

**An implicit `.animation` further down the view tree silently beats the `withAnimation` in your
action.** A `.animation(.bouncy, value: flag)` on the button wins over
`withAnimation(.linear) { flag.toggle() }` inside that button's own action. Sources disagree on the
exact resolution, which is itself the argument for the rule: `[single]` for the direction, `[multi]`
for the rule.

> **One animation source per property.** If a property is driven by both an implicit modifier and an
> explicit `withAnimation`, delete one. Do not try to reason about which wins.

To force the explicit one through, block the implicit modifier with
`.transaction { $0.disablesAnimations = true }`. All versions. `[multi]`

**Disable animation with a transaction, not a zero-duration animation.**
`.animation(.linear(duration: 0), value:)` is a hack that still schedules an animation.
All versions. `[multi]`

**In hot paths, animate on a threshold crossing, not per event.** Scroll and drag handlers fire every
frame; wrapping each in `withAnimation` starts an animation per frame. All versions. `[multi]`

```swift
let shouldShow = offset.y < -50
if shouldShow != showTitle { withAnimation(.easeOut(duration: 0.2)) { showTitle = shouldShow } }
```

**Never call `withAnimation` inside `body`** — `body` re-runs whenever anything it reads changes, so
the animation fires at arbitrary times; trigger from an action or `.onChange`. And keep it around
the **minimal state mutation**: not a network call, not a `Task { }`, because only the synchronous
state writes inside the closure are animated. All versions. `[multi]`

---

## 4. The animation context must live outside the conditional

**An `.animation` attached inside an `if` is destroyed with the view, so removal never animates.**
The insertion looks fine, which is why this survives review. Put the animation context on the
enclosing container, or wrap the mutation in `withAnimation`. All versions. `[multi]`

```swift
// WRONG — the animation is removed together with DetailView, so nothing drives the exit
if showDetail { DetailView().transition(.slide).animation(.snappy, value: showDetail) }

// RIGHT — context outlives the child
VStack { if showDetail { DetailView().transition(.slide) } }
    .animation(.snappy, value: showDetail)
```

This is the same rule that makes glass morphs no-op: the animation belongs to the container that
survives, and `glassEffectTransition` belongs to the child that comes and goes. See `morphing.md`.

**A transition with no animation context is silently ignored** — the view appears and disappears with
no error — and **`.transition()` goes on the view being inserted or removed, never on an
always-present parent.** All versions. `[multi]`

**Property animation and transitions are different machinery.** A property animation interpolates a
view that exists before *and* after the change; a transition animates a view into or out of the
render tree. Reaching for the wrong one is the most common reason "nothing animates". All versions.
`[multi]`

**An inline `.blur(radius: flag ? 0 : 10)` is not a transition** and will not animate on removal —
the view is gone before the modifier can interpolate. All versions. `[single]`

---

## 5. Transactions

**`withAnimation` is sugar for `withTransaction`.** A `Transaction` is the value that travels with an
update through the view tree; the animation is one field on it. All versions. `[multi]`

```swift
withTransaction(Transaction(animation: .snappy)) { isExpanded.toggle() }
```

**Use `.transaction { }` to override or suppress animation for one subtree** while the parent
animates: `.transaction { $0.animation = nil }`. Custom `TransactionKey`s go further and let the
animation depend on *why* the change happened — a server push animating differently from a user tap,
or a drag setting `isInteractive` so downstream views pick a tighter spring. iOS 17+. `[multi]`

**`.transaction` *without* a `value:` registers its completion exactly once, ever.** A completion
added there fires on the first update and never again — a silent one-shot bug. Use
`.transaction(value:) { … }`, or better, `withAnimation(_:completionCriteria:_:completion:)`
(iOS 17+, see `phase-and-keyframe.md`). `[single]`

---

## 6. Identity stability

Unstable identity is not a performance nit: it converts insert, remove, and reorder animations into
abrupt replacements, and resets `@State` in the whole subtree while it does it. `[apple]`

**`ForEach` element identity must be stable and unique.** SwiftUI diffs the previous id set against
the new one to classify insert / remove / move / update; with stable ids a row keeps its on-screen
presence as it moves, a new row fades in, a removed row transitions out. Anti-patterns, all of which
break motion: array indices or `id: \.self` on an index; `.enumerated()` with `id: \.offset`; a
fresh `UUID()` constructed inside `body`; an `id` derived from a mutable property
(`var id: String { title }`). Apple's test question, worth applying literally: **"if I edit this
element in place, does its id change?"** If yes, SwiftUI plays a removal plus an insertion instead of
an in-place update, and drops focus and per-row state with it. `[apple]`

**Never animate an `.id()` change.** Changing `.id` destroys and recreates the view; there is nothing
to interpolate. Use a transition for view swaps, or `matchedGeometryEffect` for position and size.
All versions. `[multi]`

**Never write a conditional view modifier (`.if(cond) { $0.foo() }`).** The `@ViewBuilder` `if`/`else`
produces two different view *types*, so toggling the condition destroys structural identity, resets
`@State` in the view and all descendants, and turns what should be a smooth property change into an
abrupt add-and-remove. Use a ternary inside the modifier argument instead. If you *find* an existing
`.if` in code you were not asked to change, flag it — do not refactor it, because removing it changes
behavior. SDK 27 makes this explicit; the mechanism applies on every version. `[verified]`

```swift
// WRONG
content.if(isHighlighted) { $0.foregroundStyle(.red) }
// RIGHT — identity preserved, SwiftUI animates the change
content.foregroundStyle(isHighlighted ? .red : .primary)
```

Availability gating is the one legitimate structural branch, and it belongs at the builder or
`ViewModifier` level rather than per-modifier. See the liquid-glass skill's
`availability-and-sdk27.md`.

**`.geometryGroup()` when a parent's geometry animates and children appear during that animation.**
It resolves the parent's geometry before handing it down, fixing children that render at the wrong
position mid-animation. iOS 17+. `[multi]`

---

## 7. `@Animatable` and hand-written `animatableData`

**Use the `@Animatable` macro instead of writing `animatableData` by hand.** It synthesizes the
requirement from the stored properties of a custom `Shape`, `View`, or `ViewModifier`. Stored
properties must conform to `VectorArithmetic` (or `Animatable`); computed properties are never
included. iOS 26+ / macOS 26+. `[apple]`

```swift
@Animatable
struct WaveShape: Shape {
    var frequency: Double
    var amplitude: CGFloat
    @AnimatableIgnored var drawClockwise: Bool   // not interpolatable — opt it out
}
```

**When the macro cannot synthesize, it names the offending property at compile time.** The fix is a
decision, not a workaround: if the change *should* animate, make the property's type conform to
`Animatable`/`VectorArithmetic`; otherwise mark it `@AnimatableIgnored`. iOS 26+. `[apple]`

**The deployment fork below 26 is `AnimatablePair`.** At iOS 26+ the multi-value carrier is
`AnimatableValues<A, B>`; below 26 it is `AnimatablePair<A, B>` accessed as `.first` / `.second`,
nested for three or more properties. `[apple]` — the reported `AnimatableValues` accessor shape
(`newValue.value.0` / `.value.1`) is **UNCONFIRMED** against the SDK; check it before committing to
that spelling. The `AnimatablePair` half is safe either way.

**Hand-write `animatableData` when interpolation needs logic, not a copy** — three named cases:
normalization, clamping, and driving a derived value. Apple's example wraps a wave's `phase` into
`0..<2π` so a long-running animation does not accumulate unbounded values. But **a custom
`Animatable` type that omits `animatableData` entirely fails silently**: it falls back to
`EmptyAnimatableData` and jumps to the final value with no error and no warning. `[apple]` `[single]`

---

## 8. What to animate: a ranking, not a rule

Two sources in this corpus give opposite absolutes ("never animate `.frame`" versus "animating
`.frame` is the cheaper option"). Both are locally true. The usable form is a ranking —
**transforms > frame changes > identity changes**. `[multi]`

1. **Transforms** — `scaleEffect`, `offset`, `rotationEffect`, `opacity`. Handled by the compositor;
   no layout pass. Prefer these whenever the effect is visual.
2. **Frame and layout changes** — `frame`, `padding`, stack spacing. Each frame runs layout. Real
   cost, but correct when the layout genuinely changes (a row that grows must actually grow).
3. **Identity changes** — `.id()` swaps, distinct `if`/`else` branches, `.if` modifiers. Not an
   animation at all: the view is destroyed and rebuilt, `@State` resets, and the motion becomes an
   abrupt replacement.

For a size change that must also move a glass surface, the answer is the glass morph, not a
hand-rolled frame animation — see `morphing.md`.

**Supporting moves.** Stagger rather than animating dozens at once
(`.animation(.snappy.delay(Double(index) * 0.05), value: isVisible)`, total spread capped at ~0.5s).
Conform expensive views to `Equatable` and call `.equatable()`, remembering that a new stored
property means updating `==` or the view goes stale. For purely visual scroll-driven effects use
`scrollTransition` / `visualEffect(in:)`, which skip body re-evaluation entirely — see
`scroll-driven.md`. `.drawingGroup()` flattens a subtree into one Metal-backed layer at the cost of
hit testing and accessibility on its contents — see `metal-and-glass.md`. `[multi]`

---

## 9. Reduce Motion

Every rule above produces motion the system will **not** gate for you: `withAnimation`, phase and
keyframe animators, and glass morphs all keep running with Reduce Motion on. Gating is your job and
has its own file — `reduce-motion.md`. Do not ship animation code from this file without it.

---

## Checklist

- [ ] Animation comes from a named preset or one of 3–5 app-wide `Animation` constants, and
      `.snappy` is treated as a 0.5s spring — no table claims 0.3 or 0.4. `[multi]`
- [ ] No `.animation(_:)` without a `value:` or body closure, and it sits *after* the modifiers it
      animates. `[multi]`
- [ ] Exactly one animation source per animated property. `[multi]`
- [ ] The animation context lives outside every conditional whose removal must animate, and
      `.transition()` is on the inserted/removed view rather than a permanent parent. `[multi]`
- [ ] No `withAnimation` inside `body`, none wrapping async work, and hot paths animate on threshold
      crossings rather than per frame. `[multi]`
- [ ] `ForEach` ids are stable, unique, and unchanged by in-place edits. `[apple]`
- [ ] No `.if(...)` conditional modifiers; availability gating sits at builder/`ViewModifier` level.
      `[verified]`
- [ ] No `.id()` change is being treated as an animation. `[multi]`
- [ ] Custom `Animatable` types use `@Animatable` (26+) or supply `animatableData` explicitly.
      `[apple]`
- [ ] Core Animation is used only for one of the six listed reasons — never for a Bezier curve —
      every CA animation sets the layer's model value, and every `CADisplayLink` is invalidated.
      `[multi]`
- [ ] No `uiView.next as? CAAnimationDelegate` anywhere. `[single]`
- [ ] Animated properties are transforms where possible; no identity change is being animated.
      `[multi]`
- [ ] `reduce-motion.md` has been applied to everything above. `[multi]`

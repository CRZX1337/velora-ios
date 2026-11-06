# Reduce Motion

Reduce Motion is a vestibular accessibility setting, not a preference toggle. Large translation,
zoom, rotation, bouncing, and parallax can cause nausea, dizziness, and migraine in people who turn
it on. This file is the owner of motion accessibility for the whole skill: what the system handles,
what it never touches, what to keep, what to replace, and how to gate it.

Tags: `[verified]` SDK/doc-checked this session · `[apple]` Apple doc, unverified · `[multi]` 2+
independent sources agree · `[single]` one source, verify before relying on it.

---

## 1. The corpus finding that should change how you read every glass tutorial

**No source in this corpus gates its own glass animation examples.** The two repositories with real
Reduce Motion material contain no glass API content at all; the repositories that teach
`glassEffectID` morphing either say nothing about Reduce Motion, or declare
`@Environment(\.accessibilityReduceMotion)` in one file and never apply it to a single one of their
own animations. The two topics never meet, even inside the same repo. `[multi]`

Practical consequence: **assume any glass or motion sample you find — blog post, skill, generated
code — is ungated, and fix it as you adopt it.** Do not read "the system adapts glass automatically"
as covering the animation you wrote around it. See §2 for exactly where that sentence stops being
true.

---

## 2. What the system already does for you

**Four APIs need no Reduce Motion handling — the system adapts them itself.** Adding your own gate
around these is harmless but redundant, and gating them *off* entirely is a regression. `[single]`

| API | Availability |
|---|---|
| `.contentTransition(.numericText(...))` | iOS 16+ / macOS 13+ |
| `.symbolEffect(...)` | iOS 17+ / macOS 14+ |
| `.navigationTransition(.zoom(sourceID:in:))` | iOS 18+ (not 26 — verify before gating) `[verified]` |
| `.sensoryFeedback(_:trigger:)` | iOS 17+ |

**Standard system components adapt too** — navigation push/pop, sheets, tab switches, and the
system's own toolbar and tab-bar glass animations tone themselves down. This is the strongest
argument for using system motion instead of rebuilding it: custom animation cannot match that
adaptiveness for free. `[multi]`

**The system also reduces its own elastic and bouncy glass effects** under Reduce Motion. `[multi]`

### Where that stops

**The system tones down its own glass animation. It does not touch yours.** `[multi]`

Not handled, ever:

- every `withAnimation { … }` you write, including the one driving a glass morph
- `.animation(_:value:)` and `.animation(_:body:)`
- `PhaseAnimator` and `KeyframeAnimator`, in both forms
- `.repeatForever` loops, shimmer, breathing pulses, ambient motion
- `scrollTransition` / `visualEffect` parallax and scroll-driven scale
- custom `Transition` types and `matchedGeometryEffect`
- `glassEffectID` morphs and `glassEffectTransition` — the morph is a system animation, but *you*
  decided when it runs, and the system will run it

One widely-circulated glass skill states "Reduced Motion — no code changes required." That claim is
materially incomplete and it is the single most consequential accessibility defect in the corpus:
the same document teaches `withAnimation { isExpanded.toggle() }` glass morphs in five separate
places, none of them gated. `[multi]`

---

## 3. Read the setting

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

Available on every OS version this skill targets; no gating needed. `[multi]`

UIKit: `UIAccessibility.isReduceMotionEnabled`, plus
`UIAccessibility.reduceMotionStatusDidChangeNotification` to react while the app is running.
`[multi]`

AppKit: `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`, with
`NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` for live changes. `[single]`

**Read it where the animation lives, not once at the top of the app.** A single check in the root
view is a review finding: it cannot gate the spring inside a leaf component. Every component that
animates non-trivially owns its own check, or inherits one through a shared `ViewModifier` (§6).
`[single]`

There is a companion setting, "Prefer Cross-Fade Transitions", that users enable *in addition to*
Reduce Motion and which asks specifically for crossfades over slides. **There is no SwiftUI
environment value for it** — SDK-checked: nothing in SwiftUI/SwiftUICore. The real API is UIKit's
`UIAccessibility.prefersCrossFadeTransitions` (iOS 14+/tvOS 14+, a global getter, unavailable on
watchOS), with `UIAccessibility.prefersCrossFadeTransitionsStatusDidChange` for updates. Read it
through a small wrapper if you need it in SwiftUI; do not invent
`accessibilityPrefersCrossFadeTransitions`. `[verified]`

---

## 4. Keep or remove

Removing all animation is the wrong correction. The goal is to remove vestibular triggers — large
movement, zoom, rotation, bouncing — while keeping the motion that communicates state. A UI that
snaps between states with no feedback at all is harder to follow, not easier. `[multi]`

| Safe to keep | Take out, or soften |
|---|---|
| Fades, crossfades, any pure opacity change | Anything that travels a distance — slide, push, a large offset |
| Colour, tint, and material appearance changes | Zoom and scale changes |
| A state change with no animation at all | Overshoot in every form: bounce, wobble, shake, spring ring-out |
| Small, short scale nudges — roughly 5% or less | Rotation and flipping |
| Motion the finger is driving, frame by frame | Motion that plays itself: parallax, ambient drift |
| Progress indicators that do not bounce | Anything that loops — `repeatForever`, a trigger-less `PhaseAnimator` |

`[multi]`

**Gesture-driven motion stays.** A sheet that follows the user's finger is not vestibular motion —
the user is causing it, frame by frame, and stopping it is disorienting. Gate the *release* spring
(drop the overshoot), not the tracking. `[single]`

**Three degradations, best to worst: crossfade → shortened → instant.** Reach for the first one that
still reads. `[multi]`

1. **Crossfade** — replace movement with an opacity transition.
2. **Shortened** — same animation, 0.1–0.15s, bounce removed.
3. **Instant** — no animation. Correct for looping and ambient motion; a last resort elsewhere.

**When you cannot decide, a 0.15–0.2s opacity cross-dissolve is almost always right.** `[multi]`

---

## 5. Per-animation replacements

Read this table as "what you wrote" on the left and "what it should become" on the right.

| Written | Becomes |
|---|---|
| A spring carrying any bounce | The same change on `.easeOut(duration: 0.15)`, bounce removed `[multi]` |
| `.move(edge:)`, a push, any slide | An opacity crossfade `[multi]` |
| A flip or a rotation | An opacity crossfade `[single]` |
| Scroll-driven parallax offset | No offset at all — the layer sits still `[multi]` |
| Entrances staggered by index | Every item fading in together, no per-item delay `[multi]` |
| A shimmer or skeleton sweep | A flat grey placeholder that does not move `[single]` |
| A breathing or pulsing indicator on `repeatForever` | The indicator held static at full opacity — not a slower pulse `[multi]` |
| An animated `MeshGradient` | The gradient, frozen `[single]` |
| The zoom navigation transition | Left exactly as it is; this one the system adapts `[single]` |
| **A glass morph (`glassEffectID` driven by `withAnimation`)** | A crossfade, or `glassEffectTransition(.materialize)` `[single]` |
| **A glass container merging or splitting on a layout change** | The same layout change with no animation context around it `[single]` |
| **The `.interactive()` press response on glass** | Left alone — a brief, small, user-caused reaction the system already tones down `[single]` |

**A repeating animation must be skipped, not retimed.** Slowing a pulse down leaves a pulse. And a
no-trigger `PhaseAnimator` has no state change to gate on, so the branch has to be at the view
level. `[multi]`

```swift
if reduceMotion {
    StatusDot()                                   // static, full opacity
} else {
    StatusDot().phaseAnimator([1.0, 1.15]) { view, s in view.scaleEffect(s) }
}
```

---

## 6. Gating patterns

**The workhorse: a `nil` animation.** Both `withAnimation` and `.animation(_:value:)` take an
`Animation?`, so passing `nil` performs the state change with no animation while keeping every other
line identical. Prefer `nil` over `.none` — same meaning, less ambiguity at a glance. `[multi]`

```swift
.animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isExpanded)

withAnimation(reduceMotion ? nil : .snappy) { isExpanded.toggle() }
```

**Prefer substitution over `nil` where a crossfade still reads.** `nil` is the "instant" rung of the
ladder; one rung up is usually better: `[multi]`

```swift
.animation(reduceMotion ? .easeInOut(duration: 0.15) : .bouncy, value: isExpanded)
```

**Gate at `ViewModifier` level so the decision exists once.** This is how you avoid the "checked only
at the top level" review finding without repeating the ternary in forty call sites. `[single]`

```swift
struct GlassMorph: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Bool

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy, value: value)
    }
}
```

**A helper that returns `Animation?` composes with `withAnimation` directly.** `[single]`

```swift
extension Animation {
    static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
```

**Symbols: `.symbolEffectsRemoved(reduceMotion)`** strips inherited symbol effects from a subtree
when you want more than the system's own adaptation. iOS 17+. `[single]`

### Gating a glass morph

The morph is driven by a state change inside a `GlassEffectContainer` (see `morphing.md`). Gate the
**animation context**, not the state change — the layout must still update, it just must not travel.

```swift
GlassEffectContainer(spacing: 20) {
    if isExpanded { ExpandedControls().glassEffectID("controls", in: ns) }
    else          { CollapsedButton().glassEffectID("controls", in: ns) }
}
.animation(reduceMotion ? nil : .snappy, value: isExpanded)   // context outside the conditional
```

That `.animation` placement is not optional even without accessibility in play — see
`animation-fundamentals.md` §4.

**`glassEffectTransition(.materialize)` is the reduce-motion-friendly morph substitute.** Where
`.matchedGeometry` travels a glass shape across the screen, `.materialize` has the surface appear and
disappear in place — no positional movement to trigger anything. Put it on the conditional child, not
on the always-present container. iOS 26+ / macOS 26+. `[single]`

```swift
if isShowingPanel {
    Panel()
        .glassEffect()
        .glassEffectTransition(reduceMotion ? .materialize : .matchedGeometry)
}
```

---

## 7. Case study: the default glass morph read as flickering

Reduce Motion users reported the **default** glass morph as *flickering*, not as motion — the
material's kinetic transition, seen without the smoothing the full-motion version implies, registers
as a flash rather than as a shape travelling. `[single]` — a field report, not documented Apple
behavior; treat it as a strong signal rather than a specification.

Two things follow, and both matter more than the anecdote:

1. **"It's the system's own animation" is not an exemption.** The system tones down its glass
   effects; it does not decide *when* your morph runs. A morph you trigger is a morph you own.
2. **Under Reduce Motion, an ungated morph can be worse than no animation.** The failure mode is not
   "slightly too much movement" — it is a visual artifact the user cannot interpret. That is why
   `.materialize` or a plain crossfade is the substitute, not a shorter version of the same morph.

If you can test with real users, test this specific interaction with Reduce Motion on. It is the one
place where the default is actively bad rather than merely unnecessary.

---

## 8. Beyond gating: the rest of motion accessibility

**Animation must never be the only feedback channel.** If the only signal that a save succeeded is a
bounce, a Reduce Motion user gets no confirmation at all. Pair motion with text, a state change, an
icon, or haptics. `[multi]`

**Announce animated state changes to VoiceOver.**
`AccessibilityNotification.Announcement("Added to favourites").post()`. If an animation blocks touch
while it runs, it must be announced, or the user experiences controls that stopped responding for no
reason. iOS 14+. `[single]`

**Never blanket-disable interaction during an animation.** Every animation should be interruptible —
springs retarget for free. `.allowsHitTesting(false)` across an animating region needs a stated
reason. Note that on glass, `.allowsHitTesting(false)` does **not** suppress the material's visual
reaction anyway; only `.disabled(true)` does, and that changes appearance. See the liquid-glass
skill. `[verified]`

**Scale animation distances with Dynamic Type.** A 20pt slide tuned at the default text size is
proportionally tiny at accessibility sizes. `[single]`

```swift
@Environment(\.dynamicTypeSize) private var dynamicTypeSize
let slideDistance: CGFloat = dynamicTypeSize.isAccessibilitySize ? 40 : 20
```

**Animated content must meet contrast at every frame**, not only at the endpoints — no mid-transition
invisible text. `[single]`

**Focus indicators must never be hidden by animation**, and after an animated navigation, verify
focus lands on the right element. `[single]`

**Any looping animation needs a way to stop it.** Under Reduce Motion that way is: do not start it.
`[single]`

---

## 9. Testing

- iOS/iPadOS: Settings → Accessibility → Motion → Reduce Motion. `[multi]`
- macOS: System Settings → Accessibility → Display → Reduce motion. `[multi]`
- Toggle it **while the app is running** — code that reads the value once at launch and caches it
  will pass a cold test and fail a real one. `[single]`
- Glass renders differently in the simulator than on hardware, and its appearance is a user setting.
  Never treat a simulator screenshot as visual acceptance for a gated glass animation; check the
  gate's *logic* in a unit test and the *look* on a device. `[verified]`
- Pair this pass with Reduce Transparency and Increase Contrast — the three settings interact on
  glass, and the material is why they matter. See the liquid-glass skill's `accessibility.md`.
  `[multi]`

---

## Checklist

- [ ] Every non-trivial animation branches on `accessibilityReduceMotion` — at the component or
      `ViewModifier` level, not only at the app root. `[single]`
- [ ] Every glass morph (`glassEffectID` + `withAnimation`) is gated. `[multi]`
- [ ] Reduce Motion path is a crossfade or a 0.1–0.15s no-bounce animation, not a blanket removal of
      all motion. `[multi]`
- [ ] Looping and ambient motion is **skipped**, not slowed. `[multi]`
- [ ] No-trigger `PhaseAnimator`s are branched at the view level, not gated by animation swap.
      `[multi]`
- [ ] Parallax and scroll-driven offsets go static; scroll-driven opacity may stay. `[multi]`
- [ ] Gesture tracking still follows the finger; only the release spring is tamed. `[single]`
- [ ] `.materialize` or a crossfade replaces `.matchedGeometry` glass transitions. `[single]`
- [ ] The four system-handled APIs are left alone, not double-gated or removed. `[single]`
- [ ] Animation is never the only feedback channel; animated state changes are announced. `[multi]`
- [ ] Animation distances scale with Dynamic Type. `[single]`
- [ ] No blanket `allowsHitTesting(false)` during animation. `[multi]`
- [ ] Tested by toggling the setting with the app running, on hardware for anything glass.
      `[verified]`

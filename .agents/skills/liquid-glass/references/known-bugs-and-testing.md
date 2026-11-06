# Known glass bugs, and how to test glass

Two halves. First, a version-pinned bug table — every entry is dated and says which OS it was seen
on, because glass behavior has changed at nearly every 26.x point release. Second, the testing
policy, which exists because glass appearance is a **user setting** and the simulator does not
render it the way hardware does.

**Research date for every entry: 2026-08-07.** iOS 27 is at developer beta 4.

**Recheck on OS updates.** Every `[version-pinned]` row below is a snapshot, not a standing fact.
Re-verify against the OS you actually ship before relying on any workaround.

---

## 0. The iOS 27 status of all of this: unknown, not fixed

Apple's iOS 27 beta 4 release notes contain the word "glass" **exactly once**, and that one mention
is a UIKit toolbar fix:

> the background might not appear on a bottom toolbar when `UIBarButtonItem.hidesSharedBackground`
> hides a toolbar item's glass background (radar 174773785) — UIKit → Resolved Issues

There is **no SwiftUI glass entry** in New Features, Resolved Issues, Known Issues, or
Deprecations. Apple has published nothing either way about any bug below. [verified]

So: treat every 26.x bug in this file as **status-unknown on iOS 27**, never as fixed. Absence of a
bug report is not evidence of a fix. [verified]

The reassuring half: the entire iOS 26 glass API surface carries to iOS 27 unchanged, with no new
glass APIs and no deprecations. Your code compiles; only behavior is in question. [verified]

---

## 1. Bug table

| # | Symptom | Seen on | Status | Workaround | Confidence |
|---|---|---|---|---|---|
| 1 | Menu glass morph starts and ends as a rectangle, then snaps to a circle with no animation | 26.0, 26.0.1, 26.1 | Unknown after 26.1 | **None current** — see §1.1 | [version-pinned] |
| 2 | Glass `Label` used as a `Menu` label: shadow clips during the collapse morph, then pops back | 26.2 (sim), 26.3.1 (device) | Open, unanswered by Apple (Mar 2026) | `.glassEffect(.clear)` + `.compositingGroup()` on the Menu | [version-pinned] |
| 3 | `rotationEffect` on a glass view corrupts the glass shape / grows its geometry with the angle | 26 RC through release; no fix reported since | Open, zero replies (Sep 2025) | Don't rotate glass. UIKit bridge if you must — see §1.3 | [version-pinned] |
| 4 | Circular/custom-shape glass button only hit-tests the SF Symbol, not the glass area | 26.x, no fix reported | Open | `contentShape` matching the glass shape (permanent practice) | [multi] |
| 5 | Glass ignores `.allowsHitTesting(false)` — the action correctly never fires, but the glass still visually reacts to touch | 26.x (Feb 2026 report) | Open, unanswered | `.disabled(true)` — which also changes appearance | [verified] |
| 6 | Interactive glass in a `RoundedRectangle` responds with **capsule** hit geometry | ~26.0–26.1 era | Unverified since Nov 2025 | `.buttonStyle(.glass)` instead of hand-rolled glass on a Button | [single] [version-pinned] |
| 7 | `.buttonStyle(.glassProminent)` + `.buttonBorderShape(.circle)` shows rendering artifacts | ~26.0–26.1 era | Unverified since Nov 2025 | `.clipShape(Circle())` — but re-verify; on a fixed build this clips the outer lensing | [single] [version-pinned] |
| 8 | Widgets render a black background in Standard and Dark modes | 26.0-era | Unverified; "no complete fix" reported | Tinted and Transparent modes work with `Color.clear` | [single] [version-pinned] |
| — | Glass renders dark/muddy in Dark Mode over bright or light-gray backgrounds | all | **Not a bug** — see §2 | Adaptive background colors in your app | [verified] |

### 1.1 Menu morph: history, not a fix

The only published guidance on the Menu circle-morph bug stops at **iOS 26.1**, and its own author
warned that Apple keeps changing the underlying behavior. Both workarounds are recorded here as
history. Neither is "the fix". [version-pinned]

- **iOS 26.0–26.0.1:** apply `glassEffect(_:in:)` to the **outer `Menu`** rather than the inner
  label, and make it interactive. The source states explicitly that this works only on 26.0–26.0.1.
- **iOS 26.1:** a custom `ButtonStyle` that applies `glassEffect` to the style's own label, applied
  with `buttonStyle(_:)`.
- **iOS 26.1:** putting a `Menu` inside a `GlassEffectContainer` **breaks** the morph. True on 26.1;
  worked on 26.0; unverified since. Keep the rule, mark it unverified past 26.1.
- **iOS 26.2 / 26.3.1:** a *different*, better-evidenced Menu morph bug — row 2 above.
- **iOS 27:** one adjacent change lands in exactly this area. Beta 4 lifts the restriction that Menu
  labels cannot contain controls, gestures, or view representables (radar 169091260). That is the
  machinery a custom-`ButtonStyle` workaround operates in, so Menu label handling was reworked —
  but nothing says the morph changed. [verified]

**The deliverable is the test, not the code.** Treat every `Menu` + glass combination as needing
visual verification on the OS you ship, on hardware. Do not copy a version-pinned workaround
forward. [version-pinned]

### 1.3 `rotationEffect` and the UIKit escape hatch

The mechanism: the glass shape is derived from the view's original bounds combined with its current
bounds, so a rotated frame yields a wrong shape. Reported both as size growth proportional to the
rotation angle and as capsule → circle → rotated-capsule flicker — same root cause. Confirmed on
iOS 26 RC, so it survived the whole beta cycle into release. Zero Apple replies. [version-pinned]

```swift
// Reproduces the bug.
Image(systemName: "globe")
    .padding()
    .glassEffect(in: .rect(cornerRadius: 20))
    .rotationEffect(.degrees(30))
```

**Rule: never apply `rotationEffect` to a view carrying `glassEffect`.** [version-pinned]

If the design genuinely requires rotated glass, drop to UIKit: `UIGlassEffect` in a
`UIVisualEffectView` behind a `UIViewRepresentable`, with corner rounding via
`UIView.cornerConfiguration` — **not** `layer.cornerRadius`, which stopped working for glass effect
views at iOS 26 beta 3. `cornerConfiguration` is the settled API, not a stopgap. Both are iOS 26.0+
and neither is deprecated on iOS 27. [verified] → recipe in `uikit-glass.md`.

### 1.4 Hit testing: two separate facts

- **Glass area ≠ hit area.** The glass surface shows press feedback across its whole extent while
  taps only register on the glyph or text. Fix with `contentShape` matching the glass shape (or
  `.clipShape(Circle())` when the *material itself* should follow the circle, not just the target).
  Present this as permanent practice rather than a bug workaround — `clipped()` has never affected
  hit testing in SwiftUI, so defining the content shape explicitly is correct regardless. [multi]
  → snippet in `accessibility.md`.
- **Glass ignores `.allowsHitTesting(false)`.** The button's action correctly never fires, but the
  interactive glass keeps reacting visually to touches. The UIKit equivalents
  (`isUserInteractionEnabled = false`, overriding `hitTest(_:with:)`) behave correctly; SwiftUI's
  only working suppression is `.disabled(true)`, which also changes the control's appearance.
  Reported Feb 2026, unanswered by Apple. **To make a glass control inert, use `.disabled(true)`.**
  [verified]

---

## 2. Not a bug: dark glass in Dark Mode

An Apple DTS engineer answered this in February 2026: a glass control darkening in Dark Mode over a
brightly-colored gradient or a light-gray background is **expected behavior**. DTS pointed at
adaptive-color guidance, not at any glass workaround. [verified]

The reporter had already tried clean builds, deleting derived data, reinstalling Xcode, turning
Reduce Transparency off, disabling Metal diagnostics, extended sRGB/P3 window configuration,
`.preferredColorScheme(nil)`, and a TestFlight build. None of it helped, because none of it was the
problem.

**The fix is adaptive background colors in your own app.** Do not carry this as an open bug with a
glass workaround. [verified]

Two things it does *not* explain, which are separately real:

1. The reporter's simulator-vs-device discrepancy — see §3.
2. The glass appearance user setting — the reporter had it on the most transparent option, which is
   the setting most likely to pick up a dark backdrop. See §3.

---

## 3. Testing policy

### 3.1 Glass appearance is a user setting

- **iOS 26.1** added two presets (Clear and Tinted).
- **iOS 27** replaces those with a **continuous intensity slider** at Settings → Appearance →
  Liquid Glass, spanning near-total transparency to a heavy tint. [verified]

So there is no single correct appearance for a glass surface. Two users on the same build, same
device, same content see different glass.

On top of that, apps **automatically** pick up the refreshed iOS 27 appearance when built with
Xcode 27, with no code change: better diffusion of complex content behind the glass, a darkened
edge, and brighter specular highlights. Same source, different pixels. [verified]

### 3.2 The simulator does not render glass like hardware

Confirmed as reported and unanswered by Apple: the simulator has been observed showing **more**
glass effect than hardware — extra bubbles around navigation bar buttons in Light Mode, more
elaborate picker transitions, different element positions. It differs in **both directions**, so
"it looked fine in the simulator" and "it looked broken in the simulator" are equally worthless as
evidence. [verified]

### 3.3 The three rules that follow

1. **Never assert exact glass pixels in a screenshot test.** The appearance is a user setting, it
   changes across SDK builds, and it differs by execution environment. Such a test fails for
   reasons that have nothing to do with your change. [verified]
2. **Never accept simulator-only evidence as visual acceptance for a glass change.** Any change to
   a glass surface's appearance must be checked on hardware. [verified]
3. **Prefer structural assertions over pixel assertions.** [verified]

### 3.4 What to assert instead

Test the things that are stable and that actually break:

- The glass view **exists** in the hierarchy and is reachable (this is what catches a `.if`-wrapped
  or availability-gated surface that silently vanished).
- The control **is hit-testable over its full area** — measure the target's frame, or assert the
  tap at the glass edge invokes the action. This catches the glyph-only hit-testing class of bug
  directly.
- **Hit target size** meets the platform minimum.
- **Layout geometry** — positions, spacing, safe-area insets. If you want a snapshot test of layout,
  disable the material for the snapshot (`isEnabled: false`, or `.identity`) so the glass is not in
  the image at all. You then get a stable picture that still regresses on layout.
- The **accessibility paths render**: Reduce Transparency on, Increase Contrast on, largest Dynamic
  Type size.
- **Scroll performance with and without glass**, measured on a low-end device — an A/B so the glass
  cost is isolated rather than guessed. [single]

Whenever you do capture a glass screenshot for human review, **record the OS version, the device or
simulator, the color scheme, and the glass appearance setting** alongside it. A screenshot without
those four facts cannot be compared to anything later. [verified]

---

## 4. Sourcing rule for glass APIs

Xcode 27's bundled model-context documentation is **not authoritative**. It is LLM-facing prose,
and it contains at least one fully fabricated API presented with working-looking sample code
(`scrollExtensionMode(.underSidebar)`, which resolves nowhere in the SDK, DocC, release notes, or
the web — while the real API for that job, `backgroundExtensionEffect()`, is absent from that same
document entirely). [verified]

Verify any glass symbol against DocC or the SDK `.swiftinterface` before teaching or emitting it.
The glass APIs live in **SwiftUICore.framework**, not SwiftUI.framework — grep there.
→ full list of symbols that do not exist: the known-bad API table in `review-checklist.md`.

---

## Checklist

- [ ] No `rotationEffect` on any view carrying `glassEffect`.
- [ ] Inert glass controls use `.disabled(true)`, never `.allowsHitTesting(false)`.
- [ ] Every custom-shape glass control has a matching `contentShape`.
- [ ] Any `Menu` + glass combination was visually verified on the shipping OS, on hardware.
- [ ] No version-pinned workaround copied forward without re-verifying it on the target OS.
- [ ] Dark-Mode darkening was fixed with adaptive background colors, not a glass workaround.
- [ ] No screenshot test asserts glass pixels.
- [ ] Visual acceptance for the glass change came from hardware, not the simulator.
- [ ] Any glass screenshot records OS, device, color scheme, and glass appearance setting.
- [ ] Every glass API used was checked against DocC or the SDK, not against bundled Xcode prose.

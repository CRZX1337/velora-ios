# Accessibility on Liquid Glass

The **material** adapts itself. **Your** animations, **your** contrast choices, and **your** hit
targets do not. This file covers the split: what you get free, what you still own, and the test
gate that catches the difference.

Animation gating is not owned here — see `reduce-motion.md` in the liquid-glass-motion skill.

---

## 1. Free: the system adapts the material

No code. This happens for `glassEffect`, the glass button styles, and system chrome alike.

| User setting | What the system does to glass | Confidence |
|---|---|---|
| Reduce Transparency | More frosting, less lensing. The material **stays**; it becomes more opaque. | [multi] |
| Increase Contrast | Stark fills plus a visible border; glass can render near-black/near-white with a contrasting edge. | [multi] |
| Reduce Motion | The system's **own** glass motion — lensing response, elastic press feedback — is toned down. | [multi] |
| Liquid Glass appearance | User-chosen tint/transparency applied to all glass. Two presets on iOS 26.1; a continuous slider at Settings → Appearance → Liquid Glass on iOS 27. | [verified] |
| Light/Dark backdrop | Small surfaces (nav bars, tab bars) flip light/dark as content scrolls under them; large surfaces (sidebars, menus) adapt without flipping, because flipping something large is jarring. | [multi] |
| Text and SF Symbols on glass | Automatic vibrancy: color, brightness, and saturation are adjusted against the backdrop. | [multi] |

Two consequences worth stating plainly:

- **`.regular` glass is legible by default.** It has full adaptive behavior over any backdrop, which
  is why it is the right variant for almost all chrome. iOS 26.0+ / macOS 26.0+. [multi]
- **`.clear` glass is not.** It has *limited* adaptivity by design, so legibility over media is your
  job: dim the content beneath it, and keep the foreground on it bold and bright. Treat a `.clear`
  surface with no dimming layer as an accessibility defect, not a style choice. iOS 26.0+ /
  macOS 26.0+. [multi]

**Do not fight these adaptations.** Overriding them with hand-rolled opacity or a hand-rolled
"high contrast mode" produces something worse than the system default and stops tracking the user's
setting. [multi]

---

## 2. Not free: what you still own

1. **Your animations.** The system tones down its own glass motion; it does not touch your
   `withAnimation { isExpanded.toggle() }` morph, your entrance springs, or your looping
   decoration. Every glass animation you write needs its own Reduce Motion path. A single check at
   the top of the app is not enough — each animated component needs one. [multi]
   → Mechanism, keep/remove table, and gating snippets: `reduce-motion.md` (liquid-glass-motion).
2. **Your contrast.** Vibrancy adjusts the *rendering* of foreground content; it does not rescue a
   low-contrast color pair, a thin font, or a raster image. Hold 4.5:1 minimum for text on glass and
   verify it over bright, dark, and high-saturation backdrops. [multi]
3. **Your background colors.** Glass rendering dark or muddy in Dark Mode over a bright gradient or
   a light-gray background is **expected behavior**, confirmed by Apple DTS — not a bug and not
   something a glass workaround fixes. The fix is adaptive background colors in your own app.
   [verified] → detail in `known-bugs-and-testing.md`.
4. **Your hit targets.** Glass draws a large surface; hit testing does not follow it automatically.
   See §5. [multi]
5. **Your semantics.** Never encode meaning in color, tint, or translucency alone — pair it with an
   icon, a label, or a shape. Glass shifts tint against its backdrop, so a tint-only signal is
   unreliable by construction. [multi]
6. **VoiceOver on icon-only glass controls.** Glass chrome is symbol-heavy by design; every
   symbol-only button needs a label, and animated state changes need an announcement. [multi]

---

## 3. Environment values

```swift
@Environment(\.accessibilityReduceTransparency) private var reduceTransparency  // iOS 13+/macOS 10.15+
@Environment(\.accessibilityReduceMotion)       private var reduceMotion        // iOS 13+/macOS 10.15+
@Environment(\.colorSchemeContrast)             private var contrast            // .standard | .increased
```

In AppKit, read the workspace preferences instead — the SwiftUI environment is not available
outside a view body: [single]

```swift
NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
```

Read these to change **your content** (drop a decorative gradient, swap a thin weight for a heavier
one, skip an animation). Do not read them to replace the material — the material already adapted.
[multi]

---

## 4. `.identity`, and why you usually should not reach for it

`Glass.identity` is the variant that renders **no glass**. iOS 26.0+ / macOS 26.0+. [verified]

The snippet that circulates in most guides is wrong as a default:

```swift
// Common, and usually a downgrade:
.glassEffect(reduceTransparency ? .identity : .regular)
```

Under Reduce Transparency the system **frosts** the glass — it keeps the material and makes it more
opaque. This snippet deletes the material instead, so the surface loses the border, the shadow, and
the adaptive legibility work the system was doing. You have replaced a good behavior with a worse
one. [multi]

Legitimate uses of `.identity`:

- Toggling glass off for a surface where you added glass the system never would, and you have
  measured that frosting is not enough over that particular content.
- Any conditional glass at all: prefer `.glassEffect(cond ? .regular : .identity)` over adding and
  removing the modifier. Swapping the variant keeps one view identity and one layout pass; wrapping
  the modifier in a condition changes structural identity and breaks animation and `@State`.
  [multi] → the `.if`-modifier ban is in `review-checklist.md`.

`glassEffect(_:in:isEnabled:)` also takes `isEnabled: Bool` (default `true`), which disables the
effect in place. Same benefit, fewer characters. iOS 26.0+ / macOS 26.0+. [multi]

---

## 5. Mechanisms, not just rules

### SF Symbols adapt to vibrancy; raster images do not

Prefer an SF Symbol over a bitmap on any glass surface. Symbols participate in the vibrancy pass —
their color and weight are adjusted against the backdrop. A PNG or JPEG is composited as-is and
will read as a flat sticker sitting on the glass, at whatever contrast it happened to have. If a
raster image must sit on glass, give it its own opaque or tinted backing shape rather than placing
it bare. [multi]

### Avoid Ultralight, Thin, and Light weights on glass

Thin strokes lose against a refracting background: the backdrop shows through the counters and the
stroke edges blur into the lensing. Use `.medium` or heavier for anything small on glass, and match
symbol weight to the weight of the text beside it. [single, but mechanically sound]

Keep a text-size floor too — below roughly 11pt, nothing on glass survives a busy backdrop. [single]

### `contentShape(_:)` expands the hit area; `.frame()` alone does not

`.frame()` sets the layout size. Hit testing still follows the content's own geometry, so a 20pt
symbol inside a 44pt frame with a glass background is a 20pt target. Clipping does not help either
— `clipped()` has never affected hit testing in SwiftUI. Restate the shape explicitly: [multi]

```swift
Button { … } label: {
    Image(systemName: "wand.and.stars")
}
.frame(width: 44, height: 44)              // layout only
.glassEffect(.regular, in: .rect(cornerRadius: 16))
.contentShape(.rect(cornerRadius: 16))     // this is what makes the whole glass tappable
```

Match the `contentShape` to the glass shape. This is permanent practice, not a bug workaround —
though it also happens to be the fix for the glyph-only hit-testing bug in
`known-bugs-and-testing.md`. iOS 26.0+ / macOS 26.0+ for `glassEffect`; `contentShape` is much
older and needs no gate. [multi]

### Hit-target minimums are per platform — never copy the iOS number to the Mac

- **iOS / iPadOS (touch): 44×44pt minimum.** [apple]
- **macOS (pointer): smaller.** Apple does not publish a 44pt rule for the Mac, and standard
  regular-size AppKit/SwiftUI controls are around 28pt tall. Applying 44pt to Mac chrome produces
  visibly oversized, non-native toolbars and sidebars. [multi]

Do not invent a Mac number. Use the system control metrics — pick a `controlSize` and let the
control size itself — and reserve explicit `.frame(width:height:)` targets for touch platforms.
Several widely-copied guides state 44pt as a universal minimum; that is the iOS touch number
misapplied. [multi] → it is in the known-bad table in `review-checklist.md`.

### Keep hit targets stable while glass animates

A morph that moves or resizes a control mid-gesture is an accessibility failure, not a polish
issue — someone with a motor impairment aims at where the target was. If a glass cluster expands,
keep the always-present control's position and size fixed and grow the new items around it.
[single]

### Dynamic Type

Glass containers must resize with the text inside them. Check that morph geometry, container
`spacing`, and any fixed `.frame(width:)` on glass content still hold at the largest accessibility
size — a fixed-width glass badge clips its label there. [multi]

---

## 6. The test gate

Run every item before calling a glass change done. Each of these has caught a real defect in this
material.

1. **Light and Dark, separately.** State it as its own step, not an assumption — glass flips its
   own light/dark treatment based on the backdrop, so the two are genuinely different renderings,
   not inverted copies of one another. [multi]
2. **Reduce Transparency on.** Confirm the surface is frosted and still readable, and that you did
   not delete the material with a reflexive `.identity`. [multi]
3. **Increase Contrast on.** Confirm borders appear and your own tints do not fight them. [multi]
4. **Reduce Motion on.** Confirm your morphs and entrances are gated, not just the system's.
   [multi]
5. **Glass appearance setting.** Check at least the default and the most transparent setting —
   two presets on iOS 26.1, a continuous slider on iOS 27. Record which setting any screenshot was
   taken under. [verified]
6. **Backdrops: bright, dark, and high-saturation.** Three named cases, not "some backgrounds".
   [single]
7. **Dynamic Type at the largest accessibility size.** [multi]
8. **VoiceOver.** Labels on symbol-only glass controls; announcements for animated state changes;
   focus lands correctly after an animated navigation. [multi]
9. **On a device, not the simulator,** for anything about appearance. The simulator renders glass
   differently from hardware in both directions. [verified] → `known-bugs-and-testing.md`.

---

## Checklist

- [ ] No hand-rolled opacity or contrast override that bypasses a system accessibility setting.
- [ ] `.clear` glass has a dimming layer under it and bold, bright content on it.
- [ ] Every glass animation you wrote is gated on `accessibilityReduceMotion`, per component.
- [ ] No `.identity` swap that merely reproduces (worse) what Reduce Transparency already does.
- [ ] Conditional glass uses `.identity` or `isEnabled:`, never a conditionally-applied modifier.
- [ ] SF Symbols, not raster images, on glass.
- [ ] No Ultralight/Thin/Light weights on glass; nothing smaller than ~11pt.
- [ ] `contentShape` matches the glass shape on every custom-shape glass control.
- [ ] Hit targets: 44pt on touch platforms; system control metrics on macOS — never 44pt on Mac chrome.
- [ ] Targets do not move or resize mid-interaction.
- [ ] Meaning is never carried by color, tint, or translucency alone.
- [ ] Symbol-only glass buttons have accessibility labels.
- [ ] Tested Light and Dark separately, with Reduce Transparency / Increase Contrast / Reduce Motion on.
- [ ] Appearance verified on hardware, with the glass appearance setting recorded.

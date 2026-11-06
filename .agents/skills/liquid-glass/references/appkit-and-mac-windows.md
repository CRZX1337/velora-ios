# AppKit glass and Mac window chrome

Scope: `NSGlassEffectView` and friends, hover on AppKit, glass window chrome for a Mac app, and the
order in which a Mac app should adopt glass. SwiftUI material semantics live in
`material-and-variants.md`; the sampling model in `containers-and-sampling.md`; gating in
`availability-and-sdk27.md`.

## NSGlassEffectView

- `NSGlassEffectView` is the AppKit glass primitive: a `NSView` subclass that embeds its
  `contentView` in the material. macOS 26.0+. [apple]
- `cornerRadius` and `tintColor` are first-class properties — no layer work, unlike UIKit.
  macOS 26.0+. [apple]
- Constrain your subviews against the glass view's `contentView`, not against the glass view itself.
  Mechanism: only `contentView` is guaranteed to be inside the glass effect; arbitrary subviews of
  the glass view have inconsistent z-order behavior. This is a correctness rule, not a style
  preference. [apple]
- Keep tints subtle and semantic — state or interactivity, never decoration. [apple]

```swift
@available(macOS 26.0, *)
func makeStatusPanel() -> NSGlassEffectView {
    let panel = NSGlassEffectView(frame: NSRect(x: 20, y: 20, width: 200, height: 100))
    panel.cornerRadius = 16
    panel.tintColor = NSColor.controlAccentColor.withAlphaComponent(0.25)

    // Assign the host first; every glassed subview then hangs off this one view.
    let host = NSView()
    panel.contentView = host

    let caption = NSTextField(labelWithString: "Ready")
    caption.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(caption)

    NSLayoutConstraint.activate([
        caption.centerXAnchor.constraint(equalTo: host.centerXAnchor),
        caption.centerYAnchor.constraint(equalTo: host.centerYAnchor)
    ])
    return panel
}
```

- Gate call sites on `#available(macOS 26.0, *)`, or mark the enclosing declaration
  `@available(macOS 26.0, *)`. The types do not exist below 26. [verified]

## NSGlassEffectContainerView

- `NSGlassEffectContainerView` is the AppKit peer of `GlassEffectContainer`: it merges nearby glass
  views and cuts render passes. macOS 26.0+. [apple]
- Glass views go into the container's `contentView`, not into the container directly. [multi]
- `spacing` defaults to **0**, and Apple states that default is "suitable for batch processing while
  avoiding distortion". On AppKit, zero is a legitimate production value — you get the render
  batching without merge distortion. Do not copy SwiftUI's 20–40pt spacing onto a Mac container out
  of habit. [apple]
- Merging is driven by animating geometry: animate a glass view's `frame` through `animator()`
  inside `NSAnimationContext.runAnimationGroup`, and the merge fires when it comes within the
  container's `spacing`. [apple]

```swift
let container = NSGlassEffectContainerView(frame: bounds)
container.spacing = 0                       // deliberate default: batching without merging

let content = NSView(frame: container.bounds)
container.contentView = content
content.addSubview(glass1)                  // NSGlassEffectView instances
content.addSubview(glass2)
```

## Material is not glass on macOS 26

- `NSVisualEffectView` is the previous generation. It remains valid for window and sidebar backing
  material, but it is **not** Liquid Glass and does not participate in glass sampling or
  merging. macOS 10.10+. [multi]
- Community "Liquid Glass in AppKit" write-ups that set `.material = .sidebar` and
  `.blendingMode = .behindWindow` are describing the pre-Tahoe world. On macOS 26+, glass is
  `NSGlassEffectView`. [multi]
- The same distinction holds in SwiftUI: `.background(.regularMaterial)` is the material ladder,
  `.glassEffect()` is glass. See `fallback-and-migration.md` for when the ladder is still the right
  answer. [multi]

## Hover on a pure-AppKit glass surface

- **In SwiftUI on Mac, `.interactive()` is the answer.** `Glass.interactive()` is iOS 26.0+ **and
  macOS 26.0+** (plus Mac Catalyst), with a dedicated pointer optimization on Mac per WWDC26. Do not
  hand-roll hover for a SwiftUI glass surface. [verified]
- The "interactive is iOS-only" claim that circulates in community skills is false. It comes from
  one AppKit sample that hand-rolls hover — an implementation detail one layer below SwiftUI, not a
  statement about the SwiftUI API. [verified]
- The hand-rolled pattern is needed **only at the AppKit level**: `NSGlassEffectView` sits below
  SwiftUI's `Glass` value and exposes no interactive property, so a glass surface you build directly
  out of `NSGlassEffectView` gets hover from an `NSTrackingArea` plus an animated `tintColor`
  through `animator()`. macOS 26.0+ for the glass class; tracking areas are macOS 10.5+. [apple]
- Recreate press and shimmer only if the surface genuinely needs them. A tint fade is the honest
  Mac equivalent of hover; the iOS press/bounce choreography is not a Mac idiom. [single]
- Production caveat: a tracking area built once in `init` from a static `bounds` rect does not
  follow a resizing view. Rebuild it in `updateTrackingAreas()`. [multi]

```swift
@available(macOS 26.0, *)
final class HoverGlassView: NSGlassEffectView {
    private static let fade = 0.2
    private let hoverTint = NSColor.controlAccentColor.withAlphaComponent(0.2)

    // Called again on every resize, so the hot zone keeps matching the view.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for stale in trackingAreas {
            removeTrackingArea(stale)
        }
        let hotZone = NSTrackingArea(rect: bounds,
                                     options: [.mouseEnteredAndExited, .activeInActiveApp],
                                     owner: self)
        addTrackingArea(hotZone)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        crossfadeTint(to: hoverTint)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        crossfadeTint(to: nil)
    }

    /// nil restores the untinted material.
    private func crossfadeTint(to color: NSColor?) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fade
            animator().tintColor = color
        }
    }
}
```

## Tahoe glass window chrome

The recipe below rests on a single community source, and it is the only window-chrome recipe in the
material we surveyed. Treat it as a pattern that works, not as a proven mechanism.

- Build a settings or utility window from an `NSWindowController` with an `NSHostingController`
  root, rather than a SwiftUI `Window` scene, when you want macOS 26 glass window chrome. The
  reported reason is that the style mask must be set at `NSWindow` construction time and SwiftUI's
  `Window` scene does not expose it. macOS 26 for the glass look; the controller pattern itself
  works on macOS 14+. [single]
- The source attributes the rounded glass chrome to including `.fullSizeContentView` in the style
  mask. **Present this as an unproven causal claim**: macOS 26 applies the new chrome to ordinary
  windows, and `.fullSizeContentView` is documented as making the content view fill the title-bar
  area. The source's own code also sets `titlebarAppearsTransparent = false`, which argues against
  its explanation. Ship the pattern, not the mechanism. [single]
- A grouped `Form` in a detail pane needs `.scrollContentBackground(.hidden)` or its opaque
  background sits on top of the window glass. This one has a clear mechanism and is worth applying
  everywhere a `Form` sits on glass chrome. macOS 13.0+ for the modifier. [single]
- The same source claims an `NSToolbar` must exist for the glass title-bar treatment, obtained by
  putting a `.toolbar { }` on the split view. Unverified, no fallback offered for a toolbar-less
  window. [single]
- Gate `scrollEdgeEffectStyle` behind `#available(macOS 26.0, *)` in a `@ViewBuilder` passthrough
  extension whose else-branch returns `self` unchanged, so pre-26 gets no visual regression. See
  `fallback-and-migration.md`. macOS 26.0+. [single]

## Adopting glass on macOS: order of operations

Distilled from one vendor macOS adoption guide; it is the clearest statement anywhere that adoption
is mostly a deletion task.

- **Adopt with the least custom chrome possible.** System controls already carry correct glass,
  vibrancy, and scroll-edge behavior; every hand-built equivalent is a surface that will drift from
  the system. [single]
- **Sequence: standard chrome first, custom glass last.** Update app structure, toolbars, search
  placement, sheets, and controls before adding a single `glassEffect`. Reserve custom glass for
  surfaces the app genuinely needs to make distinctive. [single]
- **Adoption starts as deletion.** Audit for extra fills, dark scrims, opaque backgrounds, and
  clipping — added to fake material on older OS versions — and remove them *before* adding any
  effect. Left in place they obscure the material and corrupt the automatic scroll-edge effect, so
  you end up judging new glass against a broken baseline. [single]
- Do not port iPhone behavior to the Mac: tab-bar minimize and bottom accessories are iPhone
  patterns. Prefer a conventional top toolbar with native split-view and inspector placement.
  [single]
- Do not put a custom opaque background behind a `NavigationSplitView` sidebar, a system toolbar, or
  a sheet just because an older OS version needed one. [single]
- Methodology note that saves real debugging time: a SwiftPM GUI app launched as a bare executable
  does not get foreground activation, so glass renders wrong and a design bug looks like a rendering
  bug. Launch it as a proper `.app` bundle before judging any glass regression. [single]
- Mac control shapes diverge from iPhone: bordered buttons default to a capsule at larger sizes, but
  mini/small/medium control sizes keep a rounded rectangle for denser layouts. macOS 26.0+. [single]

## Reading accessibility settings from AppKit

- In AppKit, read `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` and
  `.accessibilityDisplayShouldReduceMotion` — the SwiftUI environment values are not available to
  you. macOS 10.10+. [single]
- What the system adapts for free, and what you still own, is covered in `accessibility.md`. Do not
  duplicate that logic here. [multi]

## Checklist

- [ ] Subviews constrained against the glass view's `contentView`, never against the glass view.
- [ ] Glass views added to the container's `contentView`, not to the container.
- [ ] Container `spacing` is a deliberate choice; 0 is correct on AppKit unless you actually want a
      merge.
- [ ] No `NSVisualEffectView` presented or reviewed as Liquid Glass.
- [ ] SwiftUI glass on Mac uses `.interactive()` — not skipped on the false belief that it is
      iOS-only, and not replaced by hand-rolled hover.
- [ ] Hand-rolled hover appears only on `NSGlassEffectView`-hosted surfaces, as a tint fade through
      `animator()`, with the tracking area rebuilt in `updateTrackingAreas()`.
- [ ] Every AppKit glass type gated on `#available(macOS 26.0, *)` or an `@available` declaration.
- [ ] Forms on glass chrome carry `.scrollContentBackground(.hidden)`.
- [ ] Scrims, opaque fills, and clipping were deleted *before* any glass was added.
- [ ] Standard chrome updated before custom glass surfaces exist.
- [ ] The app was judged running as a real `.app` bundle in the foreground.

# UIKit glass

Scope: Liquid Glass in a UIKit view hierarchy, and the `UIViewRepresentable` escape hatch to use
when SwiftUI glass renders wrong. Material semantics live in `material-and-variants.md`; the
sampling model lives in `containers-and-sampling.md`; gating discipline lives in
`availability-and-sdk27.md`.

## The base construction

- Build glass as an *effect*, not a view subclass: `UIVisualEffectView(effect: UIGlassEffect())`.
  `UIGlassEffect` is a `UIVisualEffect`; the host is the ordinary `UIVisualEffectView`.
  iOS 26.0+ / iPadOS 26.0+. [apple]
- The initializer takes no arguments. Configure the effect afterwards through its properties —
  `tintColor` and `isInteractive`. iOS 26.0+. [apple]
- Never emit `UIGlassEffect(glass:isInteractive:)`. That initializer does not exist; it is a
  SwiftUI-shaped invention that recurs across community skills and fails to compile. [multi]
- Add content to `effectView.contentView`, never to the effect view directly. Mechanism: the effect
  view draws the material into its own backing layer and only `contentView` composites above
  it. [multi]
- Gate every UIKit glass call site. The `UIGlassEffect` type itself only exists on iOS 26+, so an
  ungated reference is a compile-time availability error, not a runtime fallback. [verified]

```swift
if #available(iOS 26.0, *) {
    let effect = UIGlassEffect()
    effect.tintColor = .systemBlue          // semantic only — see material-and-variants.md
    effect.isInteractive = true             // only on genuinely tappable/draggable surfaces

    let effectView = UIVisualEffectView(effect: effect)
    effectView.frame = CGRect(x: 20, y: 100, width: 220, height: 56)
    view.addSubview(effectView)

    let label = UILabel()
    label.text = "Glass"
    effectView.contentView.addSubview(label)   // NOT effectView.addSubview(label)
}
```

- `isInteractive` is the UIKit peer of SwiftUI's `Glass.interactive()`, which is iOS 26.0+ **and**
  macOS 26.0+ — the widespread "interactive is iOS-only" claim is wrong. [verified]

## Corner rounding

- Round a glass effect view through `UIView.cornerConfiguration` (type `UICornerConfiguration`),
  not `layer.cornerRadius` + `clipsToBounds`. Both are iOS 26.0+. [verified]
- Mechanism and history: `layer.cornerRadius` stopped shaping glass effect views in iOS 26 beta 3,
  and `cornerConfiguration` became the supported route from beta 4 onward. It is the settled API,
  not a stopgap. [verified]
- Apple's Xcode-bundled UIKit glass doc still teaches the `layer.cornerRadius` + `clipsToBounds`
  pattern. It is stale on this point; prefer `cornerConfiguration`. [verified]
- `UIViewCornerConfiguration(corners:cornerRadius:)` does not exist. The property name and the
  concept are real; that type and that memberwise initializer are fabricated and appear in more
  than one community source — never emit them. [multi]
- Build the value from `UICornerConfiguration`'s factory methods — SDK-verified (26.2)
  spellings: `.corners(radius:)`, the per-corner
  `.corners(topLeftRadius:topRightRadius:bottomLeftRadius:bottomRightRadius:)`,
  `.capsule(maximumRadius:)` (parameter optional), `.uniformCorners(radius:)`,
  `.uniformEdges(topRadius:bottomRadius:)` / `.uniformEdges(leftRadius:rightRadius:)`, and
  the `.uniformTopRadius`/`Bottom`/`Left`/`Right` family. Radii are `UICornerRadius`
  values. [verified]

```swift
if #available(iOS 26.0, *) {
    effectView.cornerConfiguration = .capsule()          // or .corners(radius: .fixed(12))
}
```

## Containers

- `UIGlassContainerEffect` is the UIKit peer of `GlassEffectContainer`, and it is itself an effect
  applied to a `UIVisualEffectView`. iOS 26.0+. [apple]
- Individual glass effect views go into the *container view's* `contentView`, not into the
  container view directly — same rule as any other `UIVisualEffectView`. [multi]
- `spacing` is the merge-distance threshold in points, with the same semantics as SwiftUI's
  container: effects closer together than `spacing` blend into one shape. iOS 26.0+. [apple]

```swift
if #available(iOS 26.0, *) {
    let containerEffect = UIGlassContainerEffect()
    containerEffect.spacing = 12                    // merge distance, not layout padding

    let containerView = UIVisualEffectView(effect: containerEffect)
    let glass1 = UIVisualEffectView(effect: UIGlassEffect())
    let glass2 = UIVisualEffectView(effect: UIGlassEffect())

    containerView.contentView.addSubview(glass1)
    containerView.contentView.addSubview(glass2)
}
```

- Why the container is mandatory rather than an optimization — glass cannot sample glass — is
  argued once in `containers-and-sampling.md`. The correctness argument applies identically to
  UIKit. [multi]

## Hosting SwiftUI glass inside UIKit

- Set `sizingOptions = [.intrinsicContentSize]` on the `UIHostingController` so the hosted glass
  sizes to its content instead of stretching to the container. iOS 16.0+ for the property. [multi]
- Put a hosted glass control in `navigationItem.titleView` rather than
  `leftBarButtonItem` / `rightBarButtonItem`; bar items produce sizing and layout side effects with
  hosted content. [single]
- Prefer native `UIBarButtonItem`s for bar content and reserve hosting for a custom surface that has
  no bar-item equivalent. [single]

## The escape hatch: drop below SwiftUI when glass misrenders

- When a SwiftUI glass surface renders wrong, the Core Animation / UIKit layer underneath usually
  renders it correctly. Wrap `UIVisualEffectView` + `UIGlassEffect` in a `UIViewRepresentable` and
  set the shape explicitly through `cornerConfiguration`. [version-pinned]
- The confirmed trigger: `.rotationEffect` on a view that has `glassEffect` grows the glass geometry
  in proportion to the rotation angle and distorts the shape. Reported September 2025, confirmed on
  iOS 26 RC, no Apple reply and no fix noted through iOS 27 beta 4. **Recheck on OS updates before
  relying on the workaround, and prefer not rotating glassed views at all.**
  [version-pinned] (last checked against iOS 27 beta 4 material, 2026-08)
- Other honest triggers: precise render control inside a complex layout, and integrating glass into
  an existing UIKit hierarchy. Do not reach for the bridge for ordinary styling. [single]

```swift
@available(iOS 26.0, *)
struct GlassSurface: UIViewRepresentable {
    var isInteractive = false

    func makeUIView(context: Context) -> UIVisualEffectView {
        let effect = UIGlassEffect()
        effect.isInteractive = isInteractive
        let view = UIVisualEffectView(effect: effect)
        // Explicit shape — this is the point of dropping down a layer.
        view.cornerConfiguration = .capsule()
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        (view.effect as? UIGlassEffect)?.isInteractive = isInteractive
    }
}
```

- Mark the whole representable `@available(iOS 26.0, *)` rather than gating inside `makeUIView`.
  A type that stores or returns iOS 26 types cannot be compiled for a lower floor. [verified]

## UIKit peers of chrome APIs owned elsewhere

| SwiftUI | UIKit | Availability | Owner file |
|---|---|---|---|
| `sharedBackgroundVisibility(.hidden)` on toolbar content | `UIBarButtonItem.hidesSharedBackground` | iOS 26.0+ | `toolbars-and-scroll-edge.md` |
| `scrollEdgeEffectStyle(_:for:)` | `scrollView.topEdgeEffect` / `.bottomEdgeEffect` / `.leftEdgeEffect` / `.rightEdgeEffect`, each with `.style` and `.isHidden` | iOS 26.0+ | `toolbars-and-scroll-edge.md` |
| custom bar reshaping the scroll edge | `UIScrollEdgeElementContainerInteraction` (`.scrollView`, `.edge`, then `addInteraction`) | iOS 26.0+ | `toolbars-and-scroll-edge.md` |
| pre-26 fallback material | `UIBlurEffect` in a `UIVisualEffectView` | iOS 8.0+ | `fallback-and-migration.md` |

[apple] for every row.

## Checklist

- [ ] `UIGlassEffect()` — no-argument init, properties set afterwards; no `glass:`/`isInteractive:`
      init anywhere in the diff.
- [ ] Every subview added to `contentView`, never to the `UIVisualEffectView`.
- [ ] Corner shape set via `cornerConfiguration`; no `layer.cornerRadius` on a glass effect view; no
      `UIViewCornerConfiguration`.
- [ ] Glass effect views live in the container view's `contentView`, and `spacing` is set as a merge
      distance rather than copied from a layout constant.
- [ ] `isInteractive` only on views that actually take a tap or drag.
- [ ] Every glass call site inside `if #available(iOS 26.0, *)`, or inside a type marked
      `@available(iOS 26.0, *)`.
- [ ] Hosted SwiftUI glass uses `sizingOptions = [.intrinsicContentSize]` and sits in `titleView`,
      not a bar button item.
- [ ] The representable escape hatch is used for a named rendering bug, not as a default styling
      route — and the bug was re-checked on the current OS.

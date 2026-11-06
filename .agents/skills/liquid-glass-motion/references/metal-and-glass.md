# Metal and Liquid Glass

Three different relationships, and they are not interchangeable. Decide which one you are in before
writing a shader.

| Relationship | What it means | Verdict |
|---|---|---|
| **Metal *as* glass** | You render your own glass with Metal instead of using the system material | Leaving the platform. Last resort. |
| **Metal *alongside* glass** | System glass on the functional layer, your shaders on the content layer beneath | The recommended pattern. |
| **Metal *under* glass chrome** | A live Metal/Canvas surface behind a glass toolbar or sidebar | Best-looking glass you can ship. |

## Setup gate (applies to all three)

- **Install the Metal Toolchain before writing any `.metal` file** — Xcode Settings → Components.
  It is a separately downloadable component; without it the shader source does not compile and the
  error points at the toolchain, not your code. `[multi]`
- **Shader modifiers are iOS 17+ / macOS 14+**, independent of the iOS 26 glass floor. A shader
  layer works on OS versions where `glassEffect` does not exist. `[multi]`

---

## (a) Metal as a glass replacement

**The system glass pipeline is closed.** There is no public hook to supply a fragment function,
change the lensing math, or read its intermediate textures. `Glass` exposes three variants
(`.regular`, `.clear`, `.identity`) plus `.tint(_:)` and `.interactive()` — that is the entire
customization surface. If you need lensing the system does not do, you are not customizing glass,
you are replacing it. iOS 26+ / macOS 26+. `[multi]`

Two community libraries do the replacement, and both are worth knowing so you can recognize the
shape of the work:

- **BarredEwe/LiquidGlass** — snapshots the view hierarchy behind the effect, uploads it as an
  `MTLTexture`, and runs a fragment shader over it in an `MTKView`. Performance is only acceptable
  with a `.once` or `.manual` refresh policy; a continuously refreshing snapshot re-renders the
  backdrop hierarchy every frame. `[single]`
- **DnV1eX/LiquidGlassKit** — an iOS 13–18 backport plus customization beyond what the native
  material allows. `[single]`

**Name the trade-off before you reach for either; do not recommend one by default.** `[single]`
What you give up the moment you leave the system material:

- Reduce Transparency, Increase Contrast, and Reduce Motion adaptation stop being free. You
  implement every one by hand off `@Environment(\.accessibilityReduceTransparency)` and friends
  (see the liquid-glass skill's `accessibility.md`).
- The user's glass appearance setting (26.1 presets, 27 continuous slider) no longer applies to
  your surface, so your chrome drifts away from the rest of the system as the user moves it.
- Automatic vibrant text treatment, adaptive shadows, and the scroll-edge effects stop applying.
- You own it across every future OS release; the system material gets renderer improvements for
  free.

Legitimate reasons to accept that: a pre-26 deployment target that must still look like glass, or a
signature effect the material provably cannot express. "I want a different blur radius" is not one.

---

## (b) Metal alongside glass — the recommended pattern

**Put system glass on the functional layer and your shader on the content layer beneath it.** The
glass keeps every system behavior; the shader gives the glass something worth refracting. This also
fixes the most common complaint about glass — that it looks like a flat grey card — because the
cause is a flat single-colour background with no detail to bend. `[multi]`

```swift
ZStack(alignment: .bottom) {
    ShaderBackdrop()          // your content layer: Canvas / Image / MTKView + shader
    Toolbar().glassEffect()   // system glass, untouched
}
```

- **Never apply a shader to a glass view or to any ancestor of one.** A shader modifier forces the
  subtree into its own composited layer, which is the same failure as `opacity < 1` on glass: the
  material stops sampling what is behind it and collapses to a tint. `[single]`
- **Glass still cannot sample other glass**, so the shader layer must be genuinely below the glass
  in the ZStack, not a sibling glass surface (see the liquid-glass skill's
  `containers-and-sampling.md`). `[multi]`

### The three shader modifiers

Pick by what SwiftUI injects into your function — that dictates what the effect can physically do.
iOS 17+ / macOS 14+. `[multi]`

| Modifier | Injected arguments | Returns | Can it read neighbours? | Use for |
|---|---|---|---|---|
| `.colorEffect` | `float2 position, half4 color` | a colour | No | tints, dissolves, grain, sheen |
| `.distortionEffect` | `float2 position` | a new sample position | It only moves pixels | ripples, jelly, haze |
| `.layerEffect` | `float2 position, SwiftUI::Layer layer` | a colour | Yes, via `layer.sample()` | lensing, aberration, blur-like effects |

`.layerEffect` is the superset and the expensive one; it is the image-processor of the three.
Your own Swift-side arguments start after the injected ones.

### Writing the shader

Every `.metal` file needs the SwiftUI header and the `[[ stitchable ]]` attribute; SwiftUI then
generates `ShaderLibrary.<functionName>(...)` for you. `[multi]`

```metal
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]]
half4 tinted(float2 position, half4 color, half4 tint) {
    return half4(color.rgb * tint.rgb, color.a);
}
```

```swift
.colorEffect(ShaderLibrary.tinted(.color(themeAccent)))
```

- **`position` and every sample coordinate are in points (user space), not pixels.** That is why
  `maxSampleOffset` is expressed in points and why the same shader behaves the same at 2× and 3×.
  `[single]`
- **Never hardcode a colour inside a shader** — retheming then requires a recompile. Pass it as
  `.color(_:)`. `[single]`
- **Shaders are stateless per-pixel functions with no memory between frames.** Pass elapsed time in
  explicitly from `TimelineView(.animation)` or a keyframe-driven value. `[multi]`
- **Gate any continuously animating shader on Reduce Motion** — a `TimelineView(.animation)` shader
  is ambient looping motion, which is exactly the category that must be neutralized. See
  `reduce-motion.md`. `[multi]`

### maxSampleOffset

**`maxSampleOffset` must match the distance your shader actually samples.** Underestimate and the
effect clips at the view edge; overestimate and you pay for texture area you never read. Zero is
correct only when you sample the current pixel and nothing else. `[multi]`

Per-recipe starting values: **2pt** for chromatic aberration, **8pt** for heat haze, **50pt** for a
touch ripple. `[single]`

**Clamp the displacement inside the shader.** An unclamped `1/distance` falloff produces runaway
sample coordinates near the origin — garbage pixels, and sampling past the offset you declared.
`[single]`

### Cost model

**Every shader modifier is a full GPU render pass.** `[multi]`

- Never stack more than one `.layerEffect` on a view.
- Never stack more than three `.colorEffect`s.
- **Prototype stacked, collapse into ONE `[[ stitchable ]]` function for ship.** Stacked modifiers
  are for iterating on parameters, not for shipping. `[multi]`

Relative cost: `.colorEffect` low → `.distortionEffect` medium → `.layerEffect` high →
`.glassEffect` medium-high → `Canvas` + `TimelineView` variable. `[single]`

**There is no true multi-pass in SwiftUI's shader API.** A stitchable shader cannot feed another
shader, and there are no ping-pong buffers. Effects that fundamentally need intermediate textures —
bloom, depth of field, screen-space reflections, multi-tap Gaussian blur — require MetalKit with
your own `MTLTexture`s, which puts you in relationship (a) or (c), not (b). A luminance-threshold
glow is a cheap one-pass approximation of bloom, not bloom. `[multi]`

**Escalate in order: built-in modifier → `.visualEffect` → `Canvas` → Metal shader.** Each step adds
GPU passes and loses system integration. Reach for a shader only when the effect is per-pixel *and*
animated; if you can describe it in vectors, `Canvas` is the answer. `[single]`

### Recipe 1 — refraction under glass (`.layerEffect`)

The Snell's-law-flavoured approach: treat the surface as a lens and offset the background sample
position by the normalized distance from the centre. Flat in the middle, bending hardest at the rim,
which is what real refraction through a curved surface does. Use it on the content layer to
exaggerate the sense of depth beneath a glass toolbar or card.

```metal
// Refraction pattern written for this skill.
[[ stitchable ]]
half4 lens(float2 position, SwiftUI::Layer layer, float2 size, float strength) {
    float2 center   = size * 0.5;
    float2 toCenter = position - center;
    float  radius   = min(center.x, center.y);
    float  d        = length(toCenter) / max(radius, 1.0);   // 0 at centre, 1 at the rim

    // Rim-weighted bend, faded to zero before the edge so there is no visible seam.
    float  bend = d * d * smoothstep(1.0, 0.85, d);
    float2 dir  = toCenter / max(length(toCenter), 1e-4);

    return layer.sample(position - dir * bend * strength);
}
```

```swift
.visualEffect { content, proxy in
    content.layerEffect(
        ShaderLibrary.lens(
            .float2(Float(proxy.size.width), Float(proxy.size.height)),
            .float(24)
        ),
        maxSampleOffset: CGSize(width: 24, height: 24)
    )
}
```

`.visualEffect` is the cheapest way to hand the view's size to the shader — it exposes the
`GeometryProxy` without inserting a `GeometryReader` into layout. If that composition does not
typecheck on your SDK, capture the size with `.onGeometryChange(for: CGSize.self)` (iOS 18+) into
`@State` and apply `.layerEffect` directly. `strength` and `maxSampleOffset` must stay equal.
`[single]`

### Recipe 2 — sheen / holographic (`.colorEffect`)

```metal
constant float2 kSweepAxis   = float2(0.02, 0.01);              // sweep direction, per point
constant half3  kLumaWeights = half3(0.299, 0.587, 0.114);

// One sine per channel, each started a third of a cycle after the last, so the hue
// walks around the wheel instead of the three channels pumping together.
half3 spectrum(float t) {
    const float third = 2.0943951;                              // a third of a full turn, radians
    return half3(sin(t)                * 0.5 + 0.5,
                 sin(t + third)        * 0.5 + 0.5,
                 sin(t + third * 2.0)  * 0.5 + 0.5);
}

[[ stitchable ]]
half4 sheen(float2 position, half4 color, float phase, float mixAmount) {
    float sweep = dot(position, kSweepAxis) + phase * 0.6;
    half  luma  = dot(color.rgb, kLumaWeights);
    return half4(mix(color.rgb, spectrum(sweep) * luma * 2.0, mixAmount), color.a);
}
```

```swift
.colorEffect(ShaderLibrary.sheen(.float(phase), .float(0.5)))
```

- The even spacing between the three channel offsets is what makes the hue travel. Bunch them
  closer and the sweep collapses toward one colour; the thirds of a turn are the whole effect.
  `[single]`
- Weighting the result by luma is what keeps dark regions dark — remove it and the entire surface
  washes out. `[single]`
- `phase` is the parameter to drive: elapsed time for an idle shimmer, scroll offset for a
  scroll-linked one (see `scroll-driven.md`), drag translation for a card you can tilt.
- Cheap: no neighbour access, safe full-screen. `maxSampleOffset` does not apply.

### Recipe 3 — heat haze (`.distortionEffect`)

```metal
// A repeatable pseudo-random value in 0…1 for a lattice point: one sin, one fract,
// no texture fetch. Standard shader folklore, and cheap enough to run per pixel.
float latticeValue(float2 cell) {
    return fract(sin(dot(cell, float2(127.1, 311.7))) * 43758.5453);
}

// Blend the four lattice points around p. The smoothstep weight is what removes the
// grid: with a linear weight the cell boundaries are visible as creases.
float smoothField(float2 p) {
    float2 cell = floor(p);
    float2 within = fract(p);
    float2 w = within * within * (3.0 - 2.0 * within);

    float bottomLeft  = latticeValue(cell);
    float bottomRight = latticeValue(cell + float2(1, 0));
    float topLeft     = latticeValue(cell + float2(0, 1));
    float topRight    = latticeValue(cell + float2(1, 1));

    return mix(mix(bottomLeft, bottomRight, w.x),
               mix(topLeft,    topRight,    w.x), w.y);
}

[[ stitchable ]]
float2 haze(float2 position, float time, float strength) {
    float2 field = position * 0.02;
    // Two lookups into the same field, walked along different axes, so the horizontal
    // and vertical wobble never line up into a single scrolling direction.
    float dx = smoothField(field + float2(0.0, time * 2.0)) - 0.5;
    float dy = smoothField(field + float2(time, 0.0))       - 0.5;
    return position + clamp(float2(dx, dy) * strength, -strength, strength);
}
```

```swift
TimelineView(.animation) { timeline in
    let t = Float(timeline.date.timeIntervalSinceReferenceDate)
    backdrop.distortionEffect(
        ShaderLibrary.haze(.float(t), .float(8)),
        maxSampleOffset: CGSize(width: 8, height: 8)
    )
}
```

- Keep `strength` and `maxSampleOffset` equal, and keep both small — 8pt is visible and still
  plausible. `[single]`
- **Branch-free math matters most in `.distortionEffect`.** If `smoothField` turns out to be the hot
  path on older hardware, sample a noise texture instead of computing it per pixel. `[single]`
- Domain warping — offsetting one noise lookup by another — is what makes the motion read as organic
  rather than as a scrolling pattern. `[single]`

---

## (c) Metal under glass chrome

**An `MTKView` (via `NSViewRepresentable`/`UIViewRepresentable`) or a `Canvas` sitting below a glass
toolbar produces the best-looking glass you can ship**, because the material finally has a dynamic,
detailed backdrop to refract instead of a flat fill. `[multi]`

```swift
ZStack {
    MetalBackdrop()                    // content layer, fills behind the bars
        .ignoresSafeArea()
    VStack { /* … */ }
}
.toolbar { /* system glass toolbar */ }
```

Rules that still bind here:

- The Metal surface is the **content layer**. Glass belongs on the navigation layer only; do not put
  `glassEffect` on the Metal view itself. `[multi]`
- **Glass cannot sample other glass** — the layer under the chrome must be your Metal/Canvas view,
  not another glass surface. `[multi]`
- Let the backdrop run edge-to-edge behind the bars, or the glass has nothing to refract at exactly
  the point where it is most visible. Pair with `backgroundExtensionEffect()` where a static image
  is involved (see the liquid-glass skill's `toolbars-and-scroll-edge.md`). `[multi]`
- **`.drawingGroup()` flattens a subtree into a single Metal-backed layer** — useful for many
  overlapping animated views, but it disables hit-testing and accessibility on the contents. Never
  apply it to anything interactive. `[multi]`
- A continuously redrawing backdrop is a battery and thermal cost that runs whether or not the user
  is looking at it. Cap the rate (`TimelineView(.animation(minimumInterval:))`), pause it off-screen
  and when the window is inactive, and gate it on Reduce Motion. Measure it — see
  `performance-and-instrumentation.md`. `[multi]`

---

## Checklist

- [ ] Metal Toolchain installed (Xcode Settings → Components) before any `.metal` file.
- [ ] You picked a relationship deliberately: replacement / alongside / under-chrome.
- [ ] No shader modifier on a glass view or any ancestor of one.
- [ ] Modifier chosen by injected arguments, not by habit — `layerEffect` only when you sample.
- [ ] `maxSampleOffset` equals the real sampling distance; zero only if you sample the current pixel.
- [ ] Displacement clamped inside the shader.
- [ ] At most one `.layerEffect`, at most three `.colorEffect`s; collapsed into one function to ship.
- [ ] No colours hardcoded in MSL; time passed in explicitly.
- [ ] Any continuous shader animation gated on `accessibilityReduceMotion`.
- [ ] If you replaced the system material, every accessibility adaptation is re-implemented by hand.
- [ ] Effects needing intermediate textures (bloom, DoF, SSR) moved to MetalKit, not faked with
      stacked modifiers.

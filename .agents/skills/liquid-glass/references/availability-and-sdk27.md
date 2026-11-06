# Availability and SDK 27 firewall

ALWAYS read this file before generating or reviewing any glass, toolbar, or adoption code.
It exists because availability misattribution is the single most common error in Liquid Glass
material — including Apple's own docs and every community skill audited to build this one.
Facts below were verified 2026-08 against developer.apple.com and SDK `.swiftinterface`
annotations (glass APIs live in SwiftUICore, not SwiftUI). Tag legend: see SKILL.md.

## The core glass surface — stable

Everything here is iOS 26.0+ / macOS 26.0+ and carries to iOS 27 / macOS 27 **unchanged**.
iOS 27 adds zero new glass APIs and deprecates none. [verified]

| API | Notes |
|---|---|
| `glassEffect(_:in:)` | `Glass` variants: `.regular`, `.clear`, `.identity`; `.tint(_:)`, `.interactive()` — `.interactive()` is iOS 26.0 **and macOS 26.0** (pointer-optimized on Mac per WWDC26); the community "iOS-only" claim is false [verified] |
| `GlassEffectContainer(spacing:content:)` | init unchanged through 27 |
| `glassEffectID(_:in:)` | with `@Namespace` |
| `glassEffectUnion(id:namespace:)` | |
| `glassEffectTransition(_:)` | `.matchedGeometry`, `.materialize` |
| `scrollEdgeEffectStyle(_:for:)` | Cases are `.automatic`, `.hard`, `.soft` — SDK-verified. The `.sharp`/`.subtle` names circulating in write-ups do not exist. [verified] |
| `tabBarMinimizeBehavior(_:)` | iOS 26; distinct from the toolbar-minimization API below |
| `ConcentricRectangle` | iOS 26+, real despite thin community coverage |
| `sharedBackgroundVisibility(_:)` | iOS 26+; scoped to **ToolbarContent** — it is NOT a View modifier |
| `backgroundExtensionEffect()` | iOS/macOS/**visionOS** 26.0. The API for content extending under a sidebar/inspector (detail column of a NavigationSplitView). Apply to ONE background view; it clips to prevent mirrored copies overlapping. [verified] |
| `.buttonStyle(.glass)` / `.glassProminent` | iOS/macOS 26.0. The configurable `.glass(_:)` overload taking a `Glass` value is real but its initializer is **26.1** — pin to 26.1. `glassProminent` has NO configurable overload; tint via `.tint(_:)`. [verified] |

**visionOS split** — not a blanket exclusion [verified]:
- Unavailable on visionOS: `glassEffect`, `GlassEffectContainer`, `glassEffectID`/`Union`/
  `Transition`, `Glass` (incl. `.interactive()`), the glass button styles, `scrollEdgeEffectStyle`.
- Available visionOS 26.0: `backgroundExtensionEffect`, `ConcentricRectangle`,
  `tabBarMinimizeBehavior`, symbol `.drawOn`/`.drawOff`.
- Docs artifact: Apple docs render "visionOS 1.0" for symbols the SDK marks
  `@available(visionOS, unavailable)`. Where docs and SDK disagree, the SDK wins.
- `glassBackgroundEffect` is the visionOS-only API — never emit it for iOS/macOS. [verified]

**Fabricated API warning**: `scrollExtensionMode(.underSidebar)` does not exist — absent from
the SDK, 404 at every DocC path, zero release-note presence. It originates in Xcode 27's
bundled model-context documentation, which ships it with a plausible full code sample and
never mentions the real API (`backgroundExtensionEffect`). Sourcing rule: **Xcode's bundled
LLM-facing docs are not authoritative** — verify against developer.apple.com or the SDK.
[verified]

**Availability guard goes on the effect, not the modifier**: e.g. `symbolEffect(_:options:isActive:)`
is iOS 17+ but `.drawOn`/`.drawOff` (Symbols.framework) need 26.0 — guard the 26.0 floor. [verified]

## Misattributed availability — corrections

| API | Real availability | Commonly misstated as |
|---|---|---|
| `appearsActive` (environment) | iOS 18+/macOS 10.15+, back-deployed | "new in WWDC26/27". `ControlActiveState` was formally deprecated at macOS 27.0 — that deprecation is the WWDC26 event; the replacement is years older. Guarding `appearsActive` behind 27 disables working code on 18–26. Caveat: Apple's page says non-macOS always reads `true`, yet WWDC26 demos iPad inactive-window dimming — iPad behavior UNCONFIRMED, test before relying on it. [verified] |
| `visibilityPriority(_:)` | **iOS 27 but macOS 26.1** (`.low`/`.high` iOS+macOS only) | "iOS 27/macOS 27". A combined `#available(iOS 27, macOS 27, *)` wrongly suppresses it on macOS 26.1/26.2. Gate per-platform. [verified] |
| `matchedTransitionSource` / `navigationTransition(.zoom)` | iOS 18+ | "iOS 26+". Dating it 26 needlessly drops the zoom transition for the 18–25 base. [verified] |
| `ForEach` as `ToolbarContent` | back-deploys to iOS 16/macOS 13 — no gating needed | "iOS 27" [apple] |
| `ToolbarOverflowMenu` / `.toolbarOverflowMenu` | iOS 27 / visionOS 27 **only** — no macOS | "all platforms 27" [apple] |

## Renames and soft-deprecations — never emit the old name

Apple's own rule for its coding assistant: never recommend or generate a soft-deprecated API.

| Old (do not emit) | Current |
|---|---|
| `toolbarMinimizeBehavior` | `toolbarMinimizationBehavior(_:for:)` — renamed at iOS 27 beta 4; every WWDC26 write-up and Apple's own updates page still show the old name [verified] |
| `controlActiveState` | `appearsActive` |
| `.cornerRadius(_:)` | `clipShape(.rect(cornerRadius:))` / shape `fill` |
| `toolbarBackground(_:for:)` | `toolbarBackgroundVisibility(_:for:)` |
| `toolbar(_:for:)` (visibility) | `toolbarVisibility(_:for:)` |
| `.tabItem { }` / `TabView(selection:content:)` | `Tab(title:image:value:content:)` model |
| `AnimatablePair` (at 26+) | `AnimatableValues` + `@Animatable` macro; keep `AnimatablePair` only below a 26 floor |

## Building against the 27 SDK — source breakages that hit glass code

- **The `.if` conditional-modifier idiom is banned** (`extension View { func if... }`,
  `.if(condition) { $0.glassEffect() }`). It destroys structural identity: animations break and
  `@State` resets. Use a ternary inside the modifier (`.glassEffect(flag ? .regular : .identity)`)
  or gate at the ViewModifier/builder level. Do not mass-refactor existing `.if` usages — flag
  them where they wrap glass/animated state. [apple]
- `.overlay(Color.blue.opacity(0.7))`-style one-liners **no longer compile** under
  `@ContentBuilder` ("ambiguous use of 'opacity'"). Use the trailing-closure form:
  `.overlay { Color.blue.opacity(0.7) }`. This is the exact shape of most community
  glass-tint recipes. [apple]
- `@State` is now a **macro**. If migration errors appear, do not "fix" by reordering `init`
  assignments — Apple explicitly calls that fix wrong. Follow the migration diagnostics. [apple]
- `@ViewBuilder` is unified under `@ContentBuilder`; `TupleContent` replaces `TupleView`. [apple]
- Inside **sheets and popovers**, `controlSize`, `buttonSizing`, `buttonRepeatBehavior`,
  `menuIndicatorVisibility`, and `ButtonBorderShape` reset to defaults when built against the
  27 SDK — glass buttons in sheets can silently change size/shape after an SDK bump. [verified]

## The compatibility flag — the truth

`UIDesignRequiresCompatibility` was **not removed**. Building against the iOS 27 SDK the system
ignores it; building against the iOS 26 SDK it still works, and Apple's Adopting Liquid Glass
guide still recommends it as a transition tool. The "removed in Xcode 27" claim traces to SEO
blogs only. State the SDK condition when you mention it. [verified]

## Gating discipline

1. Gate per-platform, with each API's real floor. Different floors → separate `#available`
   clauses, never one combined check.
2. Gate at the view-builder or ViewModifier level; never with a `.if` helper (see above).
3. `if #available(iOS 26.0, macOS 26.0, *)` + a Material-based fallback branch is the standard
   shape — see fallback-and-migration.md.
4. On visionOS there is nothing to gate: glass does not exist there.

## Checklist

- [ ] Every glass API emitted carries its real floor (table above), per platform.
- [ ] No soft-deprecated or renamed API emitted (table above).
- [ ] No `.if` conditional-modifier wrapping; ternary or ViewModifier gating instead.
- [ ] `.overlay`/`.background` use trailing-closure form.
- [ ] `visibilityPriority`/`appearsActive`/zoom-transition floors not over-tightened.
- [ ] Compatibility-flag advice states the SDK condition.

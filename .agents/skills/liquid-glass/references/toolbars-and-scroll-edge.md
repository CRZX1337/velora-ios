# Toolbars and scroll edge

Toolbar glass, the SDK-27 toolbar surface with exact availability, scroll-edge treatment, bar
minimization, and extending content under a sidebar or inspector.

Material, variants and shapes: `material-and-variants.md`. Containers: `containers-and-sampling.md`.
SDK-27 source breakages and the general gating shape: `availability-and-sdk27.md`.

## Availability inventory

This area is where availability traps cluster. Check the row before writing the call.

| API | iOS | macOS | watchOS | tvOS | visionOS | Tag |
|---|---|---|---|---|---|---|
| `ToolbarSpacer(.fixed/.flexible)` | 26 | 26 | — | — | — | [apple] [multi] |
| `sharedBackgroundVisibility(_:)` | 26.0 | 26.0 | n/a | n/a | n/a | [verified] |
| `scrollEdgeEffectStyle(_:for:)` | 26.0 | 26.0 | 26.0 | 26.0 | n/a | [verified] |
| `tabBarMinimizeBehavior(_:)` | 26.0 | n/a | — | — | 26.0 | [verified] |
| `backgroundExtensionEffect()` | 26.0 | 26.0 | 26.0 | 26.0 | 26.0 | [verified] |
| `visibilityPriority(_:)`, `.automatic` | 27 | **26.1** | 27 | 27 | 27 | [verified] |
| `ToolbarItemVisibilityPriority.low` / `.high` | 27 | 26.1 | n/a | n/a | n/a | [verified] |
| `ToolbarItemVisibilityPriority(higherThan:/lowerThan:)` | 27 | 27 | n/a | n/a | n/a | [verified] |
| `ToolbarOverflowMenu` / `.toolbarOverflowMenu` | 27 | n/a | n/a | n/a | 27 | [verified] |
| `ToolbarItemPlacement.topBarPinnedTrailing` | 27 | n/a | n/a | n/a | 27 | [verified] |
| `toolbarMinimizationBehavior(_:for:)`, `.automatic` | 27 | 27 | 27 | 27 | 27 | [verified] |
| `.onScrollDown` / `.onScrollUp` / `.never` (bar minimization) | 27 | n/a | n/a | n/a | n/a | [verified] |
| `toolbarMinimizationSafeAreaAdjustment(_:for:)`, `.automatic` | 27 | 27 | 27 | 27 | 27 | [verified] |
| `.enabled` / `.disabled` (safe-area adjustment) | 27 | n/a | n/a | n/a | n/a | [verified] |
| `contentMarginsRemoved(_:)` | 27 | 27 | 27 | 27 | 27 | [verified] |
| `ToolbarPlacement.statusBar` | 27 | n/a | n/a | n/a | n/a | [verified] |
| `ForEach` as `ToolbarContent` (**back-deploys, no gating**) | 16 | 13 | 9 | 16 | 1 | [apple] |
| `EmptyView` as `ToolbarContent` | 27 | 27 | 27 | 27 | 27 | [apple] |

**`visibilityPriority` is the trap: iOS 27 but macOS 26.1.** A single
`if #available(iOS 27, macOS 27, *)` guard suppresses it on macOS 26.1 and 26.2, where it works. Gate
each platform on its own floor. [verified]

**Glass itself is unavailable on visionOS**, but several APIs in this file are not glass APIs and are
genuinely available there — `backgroundExtensionEffect()`, `tabBarMinimizeBehavior(_:)`,
`ToolbarOverflowMenu`, `.topBarPinnedTrailing`. Do not sweep them into the glass exclusion. [verified]

## Toolbar glass is automatic — do not hand-build it

**Toolbar items adopt Liquid Glass simply by building against the 26 SDK.** The bar floats, items group
automatically, symbols are prioritized over text. Anything you hand-roll here is a surface that will drift
from the system. [multi]

**Delete conflicting chrome before judging the result.** Legacy opaque backgrounds, darkening scrims and
custom bar fills were added to fake material on older OS versions; left in place they hide the glass and
interfere with the automatic scroll-edge effect, so you end up evaluating glass against a corrupted
baseline. Removal comes before any additive step. [single]

**Specifically: strip extra darkening, blur or custom background layers from content that passes under a
toolbar before deciding the scroll-edge treatment is wrong.** [single]

**Partial-height sheets get an inset glass background automatically; remove `presentationBackground`
overrides that existed only to imitate frosted material.** Requires at least one partial detent. [multi]

**The toolbar modifiers were renamed in the 27 SDKs** — `toolbarBackground(_:for:)` →
`toolbarBackgroundVisibility(_:for:)`, `toolbar(_ visibility:for:)` → `toolbarVisibility(_:for:)`,
`.navigationBarLeading`/`.navigationBarTrailing` → `.topBarLeading`/`.topBarTrailing`,
`statusBarHidden(_:)` → `.toolbarVisibility(_, for: .statusBar)`. Nearly every WWDC25-era snippet uses
the old spellings. Details in `availability-and-sdk27.md`. [verified]

## Composing a toolbar

**Use the glass button styles for toolbar buttons rather than putting `.glassEffect` on a label.**
The styles carry the correct material, metrics, interactive behavior and platform shape; a hand-glassed
label carries none of it and will not match the bar. iOS 26.0+/macOS 26.0+. [multi]

```swift
Button("Export", systemImage: "square.and.arrow.up") { … }
    .buttonStyle(.glassProminent)      // primary action
    .buttonBorderShape(.capsule)       // only when the shape must be explicit
```

**`.buttonStyle(.glass)` is the secondary action, `.glassProminent` the primary one.** [multi]

**Do not hand-set prominence on `.confirmationAction`** — that placement already renders prominent. [multi]

**Reach for `buttonBorderShape` only when the default is wrong.** Bordered buttons default to a capsule at
larger sizes; on macOS the mini/small/medium sizes deliberately keep a rounded rectangle for density, so
forcing a capsule there makes Mac chrome look oversized. [single]

**Group items with `ToolbarSpacer` instead of stuffing an `HStack` into one `ToolbarItem`.**
`.fixed` splits related actions into a visually distinct glass cluster; `.flexible` pushes a leading
action away from a trailing group. iOS 26+/macOS 26+. [multi]

```swift
.toolbar {
    ToolbarItem { ShareLink(item: url) }
    ToolbarSpacer(.fixed)
    ToolbarItemGroup { UndoButton(); RedoButton() }
}
```

**Give a toolbar item a stable `id` when it survives navigation**, or it re-animates on every push and pop.
Stable identity is also what `.toolbar(id:)` customization requires. [multi]

**`.toolbar(removing: .title)` cleans the bar on a full-bleed hero screen.** [single]

**On the 27 SDK, `ForEach` conforms to `ToolbarContent`**, so a data-driven toolbar needs no gating — the
conformance back-deploys to iOS 16 / macOS 13. `EmptyView`'s conformance does not; it requires 27. [apple]

## Non-glass content in a glass toolbar

**Use `sharedBackgroundVisibility(.hidden)` to drop one item out of the bar's shared glass background** —
an avatar, a thumbnail, a color swatch: content that is itself an image and should not be sitting on a
material. iOS 26.0+/macOS 26.0+, `tvOS`/`watchOS`/`visionOS` unavailable. [verified]

**It is scoped to `ToolbarContent` and `CustomizableToolbarContent`, not to `View`.** Applying it as a view
modifier does not compile; it attaches to the toolbar item. [verified]

```swift
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        AvatarView(user: user)
    }
    .sharedBackgroundVisibility(.hidden)     // on the item, not on AvatarView
}
```

**Its UIKit counterpart is `UIBarButtonItem.hidesSharedBackground`**, which had a bottom-toolbar
background defect fixed in iOS 27; whether SwiftUI shared the defect is unstated. [verified]

**On the 27 SDK, `contentMarginsRemoved(_:)` makes toolbar content sit flush with the bar edge** — the
edge-to-edge artwork case, and the natural partner to hiding the shared background. iOS 27, macOS 27,
watchOS 27, tvOS 27, visionOS 27. [verified]

**`.badge(_:)` on a toolbar button** is attested by two community sources for notification counts but is
documented by Apple for `List` rows and `Tab`s. Verify it compiles before relying on it. [single]

## Read-only status does not belong in a control slot

**Never put non-interactive status text or an indicator in a toolbar item slot.** Toolbar items inherit the
control affordance — the glass background, the grouping, the press feedback — so a label placed there
reads as a button and invites taps that do nothing. Put status in the content area, in a subtitle, or in
`ToolbarItem(placement: .largeSubtitle)`, which is the sanctioned slot for secondary title content and
takes precedence over `navigationSubtitle(_:)`. [apple] [multi]

## Scroll-edge effect

**Tune where scrolling content meets a bar with `scrollEdgeEffectStyle(_:for:)`, rather than building a
custom bar background.** It controls the treatment at the boundary — the thing that keeps text legible as
it slides under floating chrome. iOS 26.0+/macOS 26.0+, unavailable on visionOS. Styles: `.automatic`
(system decides from context), `.hard` (hard cutoff with a dividing line), `.soft`. [verified]

```swift
ScrollView { … }
    .scrollEdgeEffectStyle(.hard, for: .top)
```

**Reach for it on dense UIs with several floating elements**, where `.automatic` has to guess and usually
guesses for a simpler layout than you have. It only matters where scrolling content actually intersects a
safe-area edge or a bar; on a screen with no such intersection it changes nothing. [single]

**Do not confuse it with `backgroundExtensionEffect()`.** One treats the edge where content meets chrome;
the other duplicates content under a sidebar. They solve different problems and neither substitutes for
the other. [verified]

**UIKit exposes the same treatment per edge** — `UIScrollView.topEdgeEffect` / `.bottomEdgeEffect` /
`.leftEdgeEffect` / `.rightEdgeEffect`, each with `.style` and `.isHidden`, plus
`UIScrollEdgeElementContainerInteraction` for a view overlaying the scroll view. See `uikit-glass.md`. [apple]

## Minimizing bars on scroll

**Tab bar and toolbar minimization are two different APIs. Do not substitute one for the other.** [verified]

**`tabBarMinimizeBehavior(_:)` collapses the tab bar as the person scrolls.** iOS 26.0+ and visionOS 26.0+;
not macOS. Cases `.automatic`, `.onScrollDown`, `.onScrollUp`. Unchanged in iOS 27. [verified]

```swift
TabView { … }
    .tabBarMinimizeBehavior(.onScrollDown)
```

**`toolbarMinimizationBehavior(_:for:)` minimizes a *bar*, and it is an iOS 27 API.** iOS 27, macOS 27,
watchOS 27, tvOS 27, visionOS 27 for `.automatic`; `.onScrollDown`, `.onScrollUp` and `.never` are **iOS
only**. [verified]

```swift
ScrollView { … }
    .toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
```

**It was renamed from `toolbarMinimizeBehavior` at iOS 27 beta 4**, and every WWDC26 write-up still shows
the old name — including Apple's own SwiftUI updates page, which links a URL that now 404s. If a source
shows `toolbarMinimizeBehavior`, it predates beta 4. [verified]

**`toolbarMinimizationSafeAreaAdjustment(_:for:)` decides whether content reflows during the minimize
animation** by shrinking the safe area to follow the bar. `.automatic` on all 27 platforms; `.enabled`
and `.disabled` are iOS only. Set it explicitly when a scroll view visibly jumps as the bar collapses. [verified]

**Do not port iPhone tab-bar minimize or bottom-accessory behavior to a Mac app.** Prefer a conventional
top toolbar with native split-view and inspector placement. [single]

**Related iOS 26 tab-bar surface**, for context rather than as this file's subject:
`tabViewBottomAccessory { }` for a persistent strip above the tab bar, with
`@Environment(\.tabViewBottomAccessoryPlacement)` reporting `.expanded` / `.collapsed`; and
`Tab(…, role: .search)` for the floating search affordance. iOS 26.0+. [multi]

## Overflow (iOS 27)

**Overflow is automatic on the 27 SDK.** When items exceed the available width — narrow window, resized
app, iPhone — the system moves the surplus into a trailing overflow menu. Hand-rolled overflow logic
written for iOS 26 is now redundant. The 27 APIs steer that behavior; they do not implement it. [verified]

**`visibilityPriority(_:)` sets overflow eagerness** on a `ToolbarItem` or `ToolbarItemGroup`: higher
priority stays in the bar, lower overflows first. `.automatic` default; `.low`/`.high` iOS and macOS only;
relative `ToolbarItemVisibilityPriority(higherThan:)` / `(lowerThan:)` are iOS 27 / macOS 27. Remember the
**macOS 26.1** floor. [verified]

**`ToolbarOverflowMenu { }` holds content that always lives in the overflow menu**, never in the bar. Its
body is a *view* builder — put buttons directly inside, not wrapped in `ToolbarItem`. The
`.toolbarOverflowMenu { }` modifier on `View` is the equivalent outside a toolbar builder. iOS 27 and
visionOS 27 only. [verified]

**`ToolbarItem(placement: .topBarPinnedTrailing)` never overflows**, however constrained the bar. iOS 27
and visionOS 27 only. [verified]

**`ToolbarPlacement.statusBar` makes the status bar a toolbar placement**, replacing `statusBarHidden(_:)`
on iOS: `.toolbarVisibility(.hidden, for: .statusBar)`. iOS 27 only. `statusBarHidden(_:)` is
soft-deprecated everywhere and hard-deprecated (no effect) on visionOS 27. [verified]

## Search chrome

**Attach `searchable` at the level that matches the intended scope** — on the `NavigationSplitView` for a
whole hierarchy, on the `TabView` when one tab owns search. Do not hand-place the field; the system
positions it per platform. [single]

**Expect the dedicated search tab to render as a centered field above suggestions on iPad and Mac**, not as
a bottom bar. [single]

**`searchToolbarBehavior(.minimize)` collapses search into a button-like control that expands on
tap**, and `DefaultToolbarItem(kind: .search, placement: .bottomBar)` repositions the system
field. iOS 26+. The case is `.minimize` (SDK-verified: `SearchToolbarBehavior` declares
`.automatic` and `.minimize`); the `.minimized` spelling in community write-ups does not
compile. [verified]

## Extending content under a sidebar or inspector

**Use `backgroundExtensionEffect()`.** It duplicates the view into mirrored copies placed around it on any
edge with available safe area and blurs them, so artwork continues behind a floating sidebar or inspector
instead of ending at a hard edge. **iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0** — this
one *is* available on visionOS, unlike the glass APIs. Apple's documentation names the use case verbatim:
a view in the detail column of a `NavigationSplitView`, extending under the sidebar or inspector. [verified]

```swift
NavigationSplitView {
    SidebarView()
} detail: {
    BannerView()
        .backgroundExtensionEffect()
}
.inspector(isPresented: $showsInspector) { InspectorView() }
```

**Apply it to one background view, not several.** Apple states both constraints plainly: use it with
discretion on a single piece of background content, weighing visual clarity and performance; and it clips
the view to stop the mirrored copies overlapping each other. [verified]

Community sources add that the extended view needs an unconstrained frame
(`.resizable().aspectRatio(contentMode: .fill)` plus a `minWidth: 0, maxWidth: .infinity, minHeight: 0,
maxHeight: .infinity` frame), with `.clipped()` and `.ignoresSafeArea(edges: .top)` on the parent when it
gets clipped. [single]

**`scrollExtensionMode(.underSidebar)` should not be emitted.** It appears only in Apple's Xcode-bundled
model-context documentation and the two verbatim copies of that file — always at the same line — with
plausible-looking sample code. It is absent from the iOS 26.2 SDK, returns 404 at every DocC path, and
appears in no release note, while known iOS 27 symbols resolve normally. Treat it as nonexistent and use
`backgroundExtensionEffect()` instead. The sourcing lesson generalizes: Xcode's bundled LLM-facing docs
are not authoritative — that file ships this fabricated API with a full, plausible code sample and never
mentions the real one. Verify any symbol taken from it against developer.apple.com or the SDK. [verified]

## Gating toolbar code

**Put one `if #available` inside the `.toolbar { … }` builder covering the whole new-API body**, with an
`else` branch of plain `ToolbarItem`s. Conditionals already worked in toolbar builders before the 27 SDK,
so the builder is the cleanest gate site — cleaner than gating each modifier. [apple]

```swift
.toolbar {
    if #available(iOS 27, *) {
        ToolbarOverflowMenu { ChoosePhotoButton(); ExportButton() }
    } else {
        ToolbarItem { ExportButton() }
    }
}
```

**Never emit these calls unconditionally below the floor** — the typecheck fails with
`'<API>' is only available in iOS 27.0 or newer`. For a modifier that cannot live in a builder, wrap it in
a `ViewModifier` whose `body(content:)` branches on `#available`. [apple]

## Checklist

- No hand-built bar backgrounds; system toolbar glass left to do its job. [multi]
- Legacy scrims, darkening layers and custom fills under the bar were removed before the effect was judged. [single]
- Toolbar buttons use `.glass` / `.glassProminent`, not `.glassEffect` on a label. [multi]
- Grouping uses `ToolbarSpacer`, not an `HStack` inside one item. [multi]
- Non-glass items (avatars, thumbnails) use `sharedBackgroundVisibility(.hidden)` on the *item*. [verified]
- No read-only status sitting in a toolbar control slot. [apple] [multi]
- `visibilityPriority` is gated iOS 27 / macOS 26.1 separately, never as one combined guard. [verified]
- `toolbarMinimizationBehavior` (iOS 27) and `tabBarMinimizeBehavior` (iOS 26) are not confused for each other. [verified]
- No `toolbarMinimizeBehavior` — that name predates iOS 27 beta 4. [verified]
- Under-sidebar content uses `backgroundExtensionEffect()`; `scrollExtensionMode` appears nowhere. [verified]
- iOS 27 toolbar APIs are gated inside the `.toolbar` builder with a fallback branch. [apple]

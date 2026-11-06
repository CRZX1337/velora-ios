# Sources and attribution — liquid-glass

Composed 2026-08 from an indexed corpus of 14 sources plus a live verification pass against
developer.apple.com and local SDK `.swiftinterface` files (Xcode 26.2 / iOS 26.2 SDK, iOS 27
beta 4 documentation). All prose in this skill is written fresh; no source prose is reproduced.

## Adapted code / checklist structures (permissive licenses)

- Thomas Ricouard — Dimillian/Skills `swiftui-liquid-glass` (MIT): review-checklist core items.
- haider-nawaz/liquid-glass-skill (MIT): morph debug checklist, pitfall entries.
- rshankras/claude-code-apple-skills (MIT): NSGlassEffectView / NSGlassEffectContainerView and
  hover patterns in appkit-and-mac-windows.md.

## Paraphrased only (no license or Apple proprietary)

- Apple: Xcode-bundled Liquid Glass docs (SwiftUI/UIKit/AppKit/WidgetKit) and the Xcode 27
  Agent Skills export — via the artemnovichkov/xcode-27-system-prompts and
  superagents-lab/xcode27-skills mirrors. Note: one fabricated API was found in this material;
  see references/review-checklist.md.
- conorluddy/LiquidGlassReference and its SohrabZ/liquid-glass-skills repackaging (no license).
- openai/plugins `liquid-glass` (macOS adoption sequencing; no plugin license).
- fayazara/macos-app-skills (Tahoe window-chrome pattern; no license).
- giorgio-a11y/liquid-glass-guide (accessibility mechanisms; no license).
- praveenperera `ios26-liquid-glass` (recovered from git history; license unknown).
- devanshuDesai/agent-skills `expo-liquid-glass` (MIT): the opacity-kills-glass failure mode.

Facts tagged `[verified]` were checked during composition and take precedence over any source.

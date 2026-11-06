# Performance and instrumentation

Glass and motion performance work goes wrong in one specific way: someone reasons about the cost
model, restructures the view tree, and never measures. This file gives you the mental model *and*
the measurement workflow, in that order, with a hard rule that the trace decides.

## The mechanical model — intuition only

**Treat this as directional, not numeric. It describes Apple's internals, which are not
documented; never quote a number from it.** `[single]`

- Each glass backdrop is not a single draw. The material samples an area larger than itself and
  refracts it, which means the renderer needs several offscreen textures before it can composite
  the final frame. So "one more glass surface" is not one more draw call — it is another small
  pipeline.
- A `GlassEffectContainer` gives the surfaces inside it one shared sampling region, so N separate
  backdrops collapse toward one. That is *also* why the container is a correctness rule and not an
  optimization: glass cannot sample other glass, so surfaces in separate containers sample
  inconsistently. The mechanism is owned by the liquid-glass skill's `containers-and-sampling.md`.
- Consequence you can act on: **the cost scales with how many glass surfaces are simultaneously
  visible and changing**, not with how many exist in the file.

### When a container is genuinely warranted

- **Warranted:** two or more glass surfaces visible at the same time, near each other, animating
  or morphing simultaneously. Here the container is required for correctness anyway, and the
  collapse is a real saving. `[multi]`
- **Unmeasured-tradeoff territory:** a single glass surface, or several that never coexist on
  screen. Adding a container costs you nothing visible and buys you nothing you have measured. Do
  not restructure a view tree for it and do not claim a speedup you have not recorded. `[single]`
- **Never nest containers.** `[multi]`

### Update frequency is the real lever

The cheapest glass frame is the one you do not invalidate. Before touching the material, check
what is re-running:

- Purely visual scroll-driven effects belong in `scrollTransition` / `visualEffect(in:)` — they
  push per-frame work to the renderer and skip body re-evaluation entirely. Owned by
  `scroll-driven.md`.
- Values that change every frame (scroll offset, drag translation, hover location, animation
  progress) must never go into the environment or into a widely-read `@Observable` property
  without coarsening to a threshold first. Owned by `scroll-driven.md`.
- **Per-frame closures stay cheap.** `KeyframeAnimator` content closures, `visualEffect`
  closures, `TextRenderer.draw`, and `Animatable` view bodies run every frame — no allocation,
  no date formatting, no layout math inside. `[single]`
- **Do not put `glassEffect` on every cell of a `LazyVStack` or `List`.** Each cell becomes its
  own glass surface, created and destroyed while scrolling. Glass belongs on the chrome; keep the
  cells opaque. (Design reason: the liquid-glass skill's `material-and-variants.md`.) `[multi]`
- **Continuous animations keep running when scrolled out of view** — a lazy stack keeps a buffer
  of views alive, so a `repeatForever` or trigger-less `PhaseAnimator` in a cell burns frames off
  screen. Prefer triggered animations inside scrollable content. `[multi]`

---

## Measure before optimizing

Everything above is a hypothesis generator. The trace decides. `xctrace` ships with Xcode; the
Instruments app reads the same `.trace` bundles if you prefer a GUI.

### Recording

```bash
# Discovery first — which devices and templates exist.
xcrun xctrace list devices
xcrun xctrace list templates

# Attach to a running app with the SwiftUI template.
xcrun xctrace record --template 'SwiftUI' --device 'My iPhone' \
    --attach YourApp --output app.trace

# Launch cold, to capture startup.
xcrun xctrace record --template 'SwiftUI' --device 'My iPhone' \
    --launch /path/to/YourApp.app --output launch.trace

# Time-boxed recording (stops itself — the reliable form in scripts and agent sessions).
xcrun xctrace record --template 'Time Profiler' --device 'My iPhone' \
    --attach YourApp --time-limit 30s --output 30s.trace
```

- Interactive recordings stop with Ctrl+C; from a script, background the process and send it
  `SIGINT` (`kill -INT`), then wait for the trace to finalize — killing it hard corrupts the
  bundle. When you can, prefer `--time-limit`, which needs no signalling at all.
- Prefer `--attach` / `--launch` over `--all-processes`; a system-wide trace captures unrelated
  apps and inflates every table you will read later.
- Pick a new `--output` per run; a `.trace` bundle should never be overwritten in place.

### Reading the trace

```bash
# Table of contents: which runs and instrument tables the bundle holds.
xcrun xctrace export --input app.trace --toc

# Export one table as XML by its schema, e.g. the time profile:
xcrun xctrace export --input app.trace \
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]'
```

Useful schemas from the SwiftUI and Time Profiler templates: `time-profile` (main-thread
samples), the hang and hitch tables, and the SwiftUI update tables. Export what you need and
aggregate with your own scripting — or open the bundle in Instruments, where the SwiftUI
template's cause views answer "why does this view keep updating" interactively.

**Scope before you analyse.** A whole-session trace averages your problem away. Reproduce the
slow interaction inside a short, deliberate window (or bracket it with `os_signpost` markers you
can find in the export), and read only that window.

### The interpretation fork

**Before reading hot symbols, work out how much of the window the main thread was actually
running.** The Time Profiler samples the main thread at a fixed interval, so an N-millisecond
window predicts a proportional number of main-thread running samples. Compare what you got with
what the window length predicts: `[single]`

- **Far fewer samples than the window predicts** — the main thread was **blocked**: I/O, a lock,
  a synchronous XPC call, `Task.sleep`, awaiting an actor. The hot symbols you see are the
  moments main *was* running, so they are not the culprit. Hunt for the code that *initiates*
  the blocking work and move it off main.
- **Samples roughly match the window** — the main thread was **CPU-bound**. The hot symbols
  *are* the culprit. Hoist work out of view bodies, cache it, debounce it.
- In between: treat both hypotheses as live.

System frames tell you what the code was doing; the user-code caller one frame up is what you
fix. Frames named `swift_`, `dyld`, `objc_`, `CA*`, `CF*`, `NS*`, `__open`, `pthread*` are
signposts, not targets — `__open` means "look for the `FileHandle` / `Data(contentsOf:)` /
`JSONDecoder.decode` call site". `[single]`

### "Who keeps invalidating this view?"

The SwiftUI template records update *causes*, not just update costs. In Instruments, follow the
cause chain for the view that keeps re-rendering. Signatures worth recognizing: `[single]`

- an `@AppStorage`/`UserDefaults` write fanning out to every reader on each change;
- an environment value written high in the tree and re-installed every layout pass — a modifier
  applied too widely;
- view creation/reuse churn as a top source — identity instability (unstable `.id`, `AnyView`,
  conditional structure swaps).

**Fixing one high-fan-out source usually collapses many downstream hot views** — structural
invalidation bugs are cheaper to fix than per-view optimizations. `[single]`

### Fix order

1. Blocked-main hangs.
2. CPU-bound hangs.
3. High-fan-out invalidation sources.
4. Hitches attributed to expensive app updates.
5. `onChange` / gesture / action callbacks over ~16ms.
6. Heaviest views by total body time.

Frame budget for context: 16.67ms at 60fps, 8.33ms on ProMotion at 120fps. `[multi]`

---

## HARD CAVEAT — the simulator

**The SwiftUI template only populates its SwiftUI tables on a real device — a physical
iPhone/iPad, or the host Mac. On the iOS Simulator it records and those tables come back
empty.** Use `--template 'Time Profiler'` for simulator work. `[single]`

- **Never treat a simulator trace as glass performance acceptance.** The simulator does not run
  the device GPU pipeline, so glass rendering cost there tells you nothing about hardware.
- **Never treat a simulator screenshot as glass visual acceptance either.** Glass renders
  differently in the simulator than on hardware, and its appearance is a user setting (26.1
  presets, 27 continuous slider). See the liquid-glass skill's `known-bugs-and-testing.md`.
  `[verified]`
- For a Mac app this caveat mostly evaporates — the host Mac counts as a real device. Record the
  Mac app directly.

---

## Checklist

- [ ] You measured before you restructured; the trace, not the cost model, named the fix.
- [ ] No number from the mechanical model was quoted as fact.
- [ ] Container added for correctness (2+ glass surfaces coexisting and animating), not as a
      speculative optimization.
- [ ] Per-frame closures allocate nothing and format nothing.
- [ ] Glass is on chrome, not on lazy-stack cells.
- [ ] Continuous animations inside scrollable content are triggered, not `repeatForever`.
- [ ] Trace scoped to the slow interaction, not a whole session.
- [ ] Main-thread running share read *before* the hot symbols, and the right branch taken.
- [ ] Recording used `--attach` / `--launch`, not `--all-processes`.
- [ ] No simulator trace or screenshot used as glass acceptance.

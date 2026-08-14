# TextMate Revived — Phase 6: Liquid Glass

Design for adopting macOS 26's Liquid Glass material across the application's own UI.

## Goal

Make TextMate look like a macOS 26 application, and keep it looking current through future
system releases without per-release work. Concretely: every surface that shows a material
should use `NSGlassEffectView`, and interactive controls should be standard AppKit controls
that inherit system styling rather than drawing themselves.

## Scope

**In scope.** The application's own chrome: status bars, choosers, tooltips, overlays, the
file browser's header and actions bars, preferences, window chrome, and the tab bar's
background.

**Out of scope, deliberately.**

- **PR #1469 (`textmate/textmate`).** "My take on modernizing TextMate", +19,490/−5,877 across
  550 files. It is a fork-sized rewrite that adds whole new applications (CompareMate,
  SyntaxMate, QuickLookExtensions) and reintroduces 11 `.rave` files — the build system Phase 2
  deleted. There is no "UI part" that lifts out cleanly.
- **`OakTextView`'s own drawing.** Text needs an opaque backdrop; glass behind body text is
  unreadable.
- **`Printing.mm`.** No screen presence.
- **Native `NSWindow` tabbing.** See "The tab bar" below.

## Constraints

- **Deployment target is macOS 26.0.** No `@available` guards, no fallback paths. Where a
  surface currently has an `NSVisualEffectView`, it is replaced outright rather than branched
  around. This is a real simplification against which most third-party examples must be read —
  iTerm2's glass adoption, for instance, carries an `@available(macOS 26, *)` guard and an
  `NSVisualEffectView` fallback that would be dead code here.
- **The app is publicly released.** Each increment ships as its own release and is verified
  before the next begins.
- **No UI test infrastructure exists.** Visual regressions cannot be caught by the test suite;
  see "Verification".

## Architecture

### The foundation

Three constructors added to `Frameworks/OakAppKit/src/OakUIConstructionFunctions` — an existing
shared seam already imported by 46 files, so this widens a seam rather than inventing a layer.

| Function | Returns | Purpose |
|---|---|---|
| `OakCreateGlassContainer()` | `NSGlassEffectContainerView` | Groups adjacent glass elements so they sample the backdrop together |
| `OakCreateGlassBackground(style, tint)` | `NSGlassEffectView` | A glass surface. `style` is `NSGlassEffectViewStyleRegular` (chrome over content) or `…Clear` (overlays). `tint` may be `nil`, meaning the system default; when non-nil it must be a dynamic colour resolving for both light and dark |
| `OakGlassChromeMetrics()` | `OakGlassMetrics` struct — `CGFloat cornerRadius; NSEdgeInsets contentInsets;` | Shared chrome geometry, so surfaces do not each invent their own |

**`NSGlassEffectView` hosts content through its `contentView` property**, not by adding
subviews directly. Callers set `glassView.contentView = someView`. Encoding this in the
constructors is most of their value: getting it wrong at 12 call sites would be 12 bugs.

**The container merges adjacent glass elements — but only if you ask it to.** An earlier draft of
this spec said a container alone was enough, and that two neighbouring `NSGlassEffectView`s would
otherwise seam. That was wrong, and the SDK header says so plainly. Corrected 2026-08-14 after a
review checked it:

> `contentView` — "Elevates the z-order of **descendants of `contentView`**… **Merges descendants
> together** if the views are sufficiently similar and within the proximity specified in `spacing`."
>
> `spacing` — "The default value, zero, is sufficient for batch processing eligible glass effect
> views, while **avoiding distortion and merging effects** for other views in close proximity."

Two consequences, both of which the constructors now encode:

1. **Merging requires a non-zero `spacing`.** A default container batches for performance and
   deliberately does *not* merge nearby glass. `OakCreateGlassContainer(spacing)` takes it as a
   parameter defaulting to `0`, so a caller that wants merging must say so.
2. **Content goes in the container's `contentView`**, not as direct subviews — merging and z-order
   elevation apply to `contentView`'s descendants only.

The file browser's `OFBHeaderView` and `OFBActionsView` are the case that needs a non-zero value;
what value is a screenshot question for increment 4, not a guess to bake in now.

### Verified behaviour of `NSGlassEffectView`

The header documents the contract; it does not document how the view behaves under Auto Layout,
which is what every adoption site actually needs to know. The following was measured against the
real AppKit on 2026-08-14 by constructing the views in a throwaway program, not inferred:

| Question | Answer |
|---|---|
| `intrinsicContentSize` of a glass view | `(-1, -1)` — `NSViewNoIntrinsicMetric`. Glass has no size of its own. |
| `fittingSize` with a `contentView` set | Exactly the content's fitting size. Setting `contentView` installs the constraints internally — **do not add your own glass↔content constraints.** |
| `fittingSize` with no `contentView` | `0 × 0`. A bare glass surface used purely as a background **must** be given explicit size or position constraints, or it collapses. |
| `contentView.superview` | **Not** the glass view — a private `ContentHolderView` sits between them. Code comparing `content.superview == glassView`, or walking exactly one level up, is wrong. |
| `glassView.subviews` | Always 2, even when bare. Never test emptiness by counting subviews, and never index into them. |
| Replacing `contentView` | Detaches the previous content and re-sizes correctly. The getter round-trips the exact object you set. |
| Default `cornerRadius` | `8.0`, not zero. `OakGlassChromeMetrics().cornerRadius` deliberately overrides it. |
| Default `style` / `tintColor` | `NSGlassEffectViewStyleRegular` / `nil`. |
| `NSGlassEffectContainerView.spacing` default | `0`, and a bare container's `fittingSize` is `0 × 0` for the same reason as above. |

The consequence for adoption is smaller than it looks: a control that already has an
`intrinsicContentSize` gets glass almost for free, because content-driven sizing is automatic. A
surface that wants glass purely as a backdrop is the case that needs constraints written by hand.

One ordering fact from AppKit generally, not from glass: **a view's own `drawRect:` paints beneath
its subviews.** Any surface that currently draws its text or symbols in `drawRect:` therefore
cannot simply gain a glass subview behind them — the glass would cover the drawing. Those surfaces
must move their content into the glass view's `contentView` instead.

Deliberately **not** included: any colour abstraction or appearance manager. Glass handles
light and dark itself. The existing `NSAppearanceNameAqua`/`DarkAqua` detection in
`OakTextView.mm`, `OakToolTip.mm` and `OakKeyEquivalentView.mm` stays as it is. If the
foundation starts growing into a theming framework, that is the signal to stop and reconsider.

### Migration sequence

Six increments, ordered by blast radius. Each ships as its own release.

| # | Surface | Files | Risk |
|---|---|---|---|
| 1 | Foundation | `OakUIConstructionFunctions` | None — additive, no callers yet |
| 2 | Small controls | `OakKeyEquivalentView` | Low — self-contained, rarely visible |
| 3 | Overlays | `OTVHUD`, `OakToolTip`, `OakChoiceMenu` | Low — transient, `Clear` style, no layout impact |
| 4 | Chrome bars | `OTVStatusBar`, `HOStatusBar`, `OFBHeaderView`, `OFBActionsView` | Medium — always visible; needs the container |
| 5 | Choosers and window | `OakChooser`, `OakPasteboardChooser`, `BundlesPreferences`, window chrome | Medium — window chrome is where regressions show |
| 6 | Tab bar | `OakTabBarView` | Medium — see below |

Increments 2 and 3 come first because they are where glass's behaviour is learned at near-zero
cost. If `NSGlassEffectView` fights TextMate's layout assumptions, that surfaces on a tooltip
rather than on the status bar.

**`OFBFinderTagsChooser` was dropped from increment 2 on 2026-08-14**, once its code was read. It
is not a control in a window — `FileBrowserViewController.mm:572` assigns it to an `NSMenuItem`'s
`view`, so it lives inside a context menu. It has no background of its own precisely because the
menu draws one behind it, and adding an `NSGlassEffectView` would put a second material layer
inside a surface that already has one. A custom menu-item view's job is to blend into the menu's
material, not to bring its own. If a later screenshot pass shows the chooser reading as flat
against the surrounding menu, the fix is to match the menu's material — not to introduce glass
here.

That leaves increment 2 with one target, which is enough: `OakKeyEquivalentView` exercises every
hard part at once — it paints its own background in `drawRect:`, draws its text there too, carries
a focus ring it masks by hand, chooses colours from the effective appearance, and hosts a sibling
subview (the clear button) that must stay above the new glass.

This ordering has independent corroboration: iTerm2, a mature macOS application, has begun
adopting `NSGlassEffectView` and applied it to its Open Quickly chooser, chat toolbar and a
text-field container — overlays and choosers — while leaving its tab bar untouched.

### The tab bar

**The custom tab bar is kept and modernised. Native `NSWindow` tabbing is rejected.**

Native tabbing groups *separate windows*; each tab is a window with its own content. TextMate's
model is the inverse, and the code is unambiguous about it: `DocumentWindowController` holds
`NSArray<OakDocument*> documents` in one `NSWindow`, alongside exactly one `fileBrowser`,
`layoutView`, `htmlOutputWindowController` and `textView`. Session storage names the concept —
`restoreSession` iterates `session["projects"]`, one entry per window, each holding a
`documents` array.

**A window in TextMate is a project, not a document.** Adopting native tabbing would mean one
project per tab: open five files from a folder and get five file browsers onto that same
folder. That is not a tab bar change; it changes what a window means, and the session format,
`mate` and the ODB editor suite all assume the current shape. TextMate already made this
decision explicitly — `AppController.mm` sets `NSWindow.allowsAutomaticWindowTabbing = NO`.

iTerm2 reached the same conclusion for the same structural reason: its windows hold many
sessions, and it uses a custom `PSMTabBarControl` rather than native tabbing.

What the modernisation does: the tab bar's background becomes an `NSGlassEffectView`, grouped
with the window chrome above it in a shared container. Its close, overflow and new-tab controls
are **already** standard `NSButton`/`OakRolloverButton` and need no change. The remaining
custom `drawRect:` covers tab shapes and selection state — TextMate-specific behaviour that no
system control provides.

## Verification

Per increment: build, capture the affected surface in **both light and dark appearance**,
maintainer reviews, then ship.

The existing test suite keeps its role. It cannot see a visual regression, but it catches
layout and lifecycle breakage — the failure mode that crashes rather than merely looks wrong.
Screenshots cover what tests cannot; tests cover what screenshots cannot.

Deployment is through the release pipeline, never `bin/deploy-local`: a locally-built app is
ad-hoc signed and cannot self-update, which would strand the maintainer on a build that no
longer receives updates.

## Risks

| Risk | Mitigation |
|---|---|
| Glass fights TextMate's manual layout | Increments 2–3 are cheap probes; discovered on a tooltip, not the status bar |
| Adjacent glass surfaces seam visibly | `NSGlassEffectContainerView` is part of the foundation, not an afterthought |
| Contrast regressions in one appearance | Both appearances captured every increment |
| Foundation grows into a theming framework | Explicit stop condition: if it exceeds the three constructors, reconsider |
| Tab bar work destabilises tab behaviour | Chrome only; the interactive controls are already standard and untouched |

## What this phase does not deliver

It does not restructure the window/document model, adopt native tabbing, restyle the text
canvas, or merge any part of PR #1469. Those are separate decisions with separate rationales,
and none is a prerequisite for looking like a macOS 26 application.

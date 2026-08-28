# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

From 1.0.0 on, the supported surface is `setup(opts)` and its `keys` option: a
breaking change to either takes a major bump. Everything else
the module exposes is outside that promise — `M.run`, the callable module, and
the internals the offline spec reaches for — and so are the tuning knobs, which
exist to work around how the layout engine reacts to a resize and may change in
any release.

## [Unreleased]

### Removed

- **`loop` is no longer an option.** The ladder is a cycle, and now
  unconditionally: `loop = false` stopped a chord dead at either end of it, which
  made the same keypress on the same layout do something or nothing depending on
  where the column already sat. Stepping a ladder exists to take that dependence
  away, so the exception goes. A config still passing `loop` binds and runs; the
  value is ignored, so one that set `false` now wraps.

- **`min_width` is no longer an option.** The floor a non-focused column may not
  be squeezed below stays exactly where it was — a twelfth of the available
  width — but it is now derived rather than configured, like the ladder it trims.
  What a column needs in order to stay useful is a property of the monitor, and
  the option only offered ways to get that wrong. A config still passing
  `min_width` binds and runs as before; the value is ignored.

## [1.1.0] — 2026-08-27

Hyprecise read a workspace as one row of columns. A workspace cut across its full
width is not one row, and every chord on one was a silent no-op.

### Added

- **A row is a maximal y-interval that no window crosses**, and a chord is about
  the focused window's row alone. It is the same sweep that finds columns, turned
  ninety degrees, and it runs first — because it says which windows the column
  reading is then about. `M.rows` joins `M.columns` in the pure core, and
  `row_tolerance` (default 8) joins `column_tolerance` beside it.

### Fixed

- **A row below a full-width window can be resized.** `A` across the top with
  `B | C` beneath it read as a *single* column, because `A` crosses the `B | C`
  boundary — so there was no boundary to move and all four chords, from all three
  windows, did nothing at all. `B` and `C` are now a row of two: on a 3440
  monitor, `Right` from `C` takes them from `1699 | 1699` to `2266 | 1132`, and
  `A` keeps its 3414 to the pixel.
- **A grid resizes one row at a time.** Two side-by-side splits stacked one above
  the other present exactly the edges a single row of columns would, and come
  apart the moment either half is moved — so 1.0.1 detected that and refused the
  layout outright, leaving every chord on a grid dead. Read as two rows, each has
  its own boundary and moves without disturbing the other, whether or not the two
  rows are split at the same place. The one grid that still moves as a whole is
  the one built as a pair of stacks side by side, where both rows are halves of a
  single vertical split: that split is genuinely shared, and no dispatch can
  separate them.
- **A row of one is a no-op rather than a phantom column.** The full-width window
  over a pair has no neighbour to share a boundary with, and heights are out of
  scope, so a chord from it changes nothing — including the nudges it would have
  asked with.

### Changed

- `M.row_windows` is `M.workspace_windows`. It filters the workspace by monitor
  and workspace, which is a step before the row reading rather than the row
  reading itself. Outside the supported surface, and untouched in behaviour.
- The offline spec grows a row-detection section and drives the real `run` over
  four multi-row trees, checking both halves of what a chord owes them: the
  focused row lands on its plan, and every window outside it keeps its geometry
  to the pixel. 138 assertions, up from 119. The twelve focus-and-direction
  results on a single-row workspace are byte-identical to 1.0.1, live on
  Hyprland 0.56.2.

## [1.0.1] — 2026-08-26

One bug, in the half of hyprecise that had no tests: what a resize dispatch does
was assumed rather than known. Nothing in the supported surface changes, and on
the one layout the old code handled the result is byte-identical.

### Fixed

- **A row that is not a right-nested spiral no longer comes apart.** A dispatch
  does not widen the window it names. It takes the first side-by-side split above
  that window and moves it RIGHTWARD by the delta, whichever side of the split
  the window is on — so it widens a window on the left of it and *narrows* one on
  the right. `apply` assumed the former for every column, which is only true of
  the tree the dwindle spiral builds when windows are opened one after another.
  Move a window in from another workspace, or open one while an older window is
  focused, and the middle column's dispatch is inverted: on a 3440 monitor,
  `Right` on the middle of `844 | 839 | 1699` asked it to grow by 572px and left
  it at **69px**, after which the sweep oscillated for all four passes and gave
  up, leaving the wreck. Every one of the twelve focus-and-direction combinations
  on that row was wrong; all twelve now land exactly on a ladder stop.
- **The last column can change width.** The sweep walked columns `1..n-1` and
  relied on the last one absorbing the remainder. In a left-leaning tree the last
  boundary is driven only by the last column's own anchor, so that column was
  pinned: it held the same width across every chord, from every focus.
- **A grid is no longer mistaken for a row of columns.** Two side-by-side splits
  stacked one above the other at the same ratio present exactly the edges a
  single row of columns would, and there is nothing in the geometry to tell them
  apart. Resizing them split the top row and left the bottom one alone, and the
  ragged result then read as one column with no anchor — so every later keypress
  was a silent no-op until the layout was repaired by hand.
- **A boundary no window can move is refused rather than thrashed at.** A split
  whose two halves are themselves side-by-side splits is nobody's nearest split,
  so no dispatch reaches it and the row cannot be arranged as planned. Such a
  keypress now changes nothing at all instead of half-serving the plan.

### Changed

- **`apply` works in boundaries, not column widths.** A boundary is what a
  dispatch moves, so naming it makes a delta mean one thing throughout — move
  *this* boundary rightward by that many pixels — no matter which of its two
  columns is asked. Which boundary a column drives is not in the geometry, so
  hyprecise asks: it nudges the column, watches where its left edge went, and
  undoes the nudge. The same nudge answers whether the column is a column at all,
  because a real one takes its whole row with it.
- The number of sweeps keeps up with the number of columns. A boundary nearer the
  root of the layout tree rescales the ones below it, so one sweep settles only
  the outermost; `max_passes` is now a floor rather than a fixed four.
- The offline spec drives the real `run` against a model of the dwindle layout in
  `tests/dwindle.lua`, transcribed from Hyprland 0.56.2 and calibrated against
  live geometry. The half of hyprecise that issues dispatches is only correct in
  terms of how the layout engine answers them, so the answers are modelled rather
  than assumed: 119 assertions, up from 99, nine of which fail against 1.0.0.

## [1.0.0] — 2026-08-25

The supported surface is now fixed. Two things a 0.1.0 config could rely on are
gone — the `mode` option and the ragged-layout fallback — which is what makes
this a major rather than a 0.2.0.

### Added

- `setup(opts)`: hyprecise registers its own bindings, so the integration is one
  line in a Hyprland Lua config instead of an eighteen-line snippet. It binds
  through `hl.bind` directly, which works with or without Omarchy — the two
  install paths in the README collapse into one.
- `keys` option, taking either a modifier prefix (`"SUPER + ALT"`, arrows
  appended) or a per-direction table of chords (`{ left = "SUPER + H", ... }`),
  which binds only the directions it names.
- Bindings now carry descriptions, so they appear in
  `omarchy menu keybindings --print`.

### Fixed

- **A nested column no longer breaks the row.** Columns were bucketed by exact
  x-interval, so a column subdivided into a tree — `A | B | C` where `C` is split
  into `D` over `E`, and `E` into `F | G` — was read as five columns rather than
  three, failed the tiling check, and fell through to the fallback that nudges
  only the focused window. It now reads as `A | B | C` at any depth, and the
  chord does the same thing from every window inside `C`: on a 3440 monitor,
  `Right` from `D`, from `F` and from `G` all take the row from
  `1699 | 839 | 844` to `1410 | 1409 | 563`, with the `F | G` split inside `C`
  keeping its proportions.

### Changed

- **A column is a maximal x-interval that no window crosses.** Windows whose
  x-intervals overlap are one column, however deeply the layout engine has
  subdivided them, and hyprecise never looks inside one. This replaces bucketing
  by exact interval, and with it the whole notion of a layout that cannot be
  decomposed into columns: overlapping windows now merge into the column they
  share instead of producing a contradictory reading of the row.
- **A resize is aimed at its column's anchor** — the member spanning the whole
  column, ties going to the topmost. A window that spans its column has no
  side-by-side split above it inside the column, so the first such split the
  layout engine walks up to is the column's own outer boundary. Aiming at the
  focused window instead would move whichever boundary happened to be nearest it
  in the tree, which is what made a nested column unresizable.
- **A keypress is confined to one row, by filtering.** Windows are selected by
  the focused window's monitor *and* workspace, and anything outside that is
  dropped before the layout is read. Columns are read from x-intervals alone, so
  a foreign window would otherwise be read as a real column and the genuine ones
  shrunk to make room for it. Every column a keypress touches is now on the
  current monitor by construction. Windows that were never columns — floating,
  hidden, unmapped, fullscreen — are ignored as before.
- **The ladder follows the monitor.** The available width — logical width less
  whatever a side bar reserves at the left or right — is divided into as many
  equal slices as fit while keeping each near 540px, and every multiple of a
  slice short of the whole is a stop. 540 is the value that reproduces both of
  the hand-picked ladders it replaces: 1920 still gets quarters and 3440 still
  gets sixths, while the sizes in between and beyond — 2560, 3840, 5120 — now
  get a ladder built for them instead of one built for a different screen. A
  vertical bar no longer pushes the outermost stops underneath itself.
- **Stops are fractions of the row, not of the screen.** The row is what the
  columns actually add up to, which is smaller than the screen by the gaps. Each
  stop therefore names a width a column can really have: on a 3440 monitor with
  10px gaps and 3px borders the half stop is 1699 rather than 1720, and the fair
  share now lands exactly on a stop instead of a pixel beside one. Existing
  ladders shift by at most 48px, about 1.4% of an ultrawide, with no change to
  how many stops there are or how many presses reach any of them.
- Row selection and column reading both live in the pure core, as
  `M.row_windows`, `M.columns` and `M.anchored`, so which windows a keypress may
  touch and how they are grouped are covered by the offline spec rather than
  living in the untested Hyprland shell.
- The offline spec covers granularity across monitor sizes, row membership,
  nesting at several depths, the flipped column that distinguishes the anchor
  from the topmost window, straddling windows, columns with no anchor, and the
  tolerance boundary between merging and not: 99 assertions, up from 46.

### Removed (breaking)

- **The ragged-layout fallback.** A layout with no full-height cut now reads as a
  single column, and a single column has no boundary to move, so the chord is
  silent where it used to nudge the focused window along a screen-fraction
  ladder. Two cases lose behaviour: `[A][B]` over a full-width `C`, and a
  workspace subdivided entirely within itself. Both are the deliberate cost of
  hyprecise dealing only in top-level columns. `M.decomposable` is gone; the new
  `M.anchored` reports the one layout that is still refused — a column no member
  spans, which a row split top and bottom before each half is split side by side
  can produce.
- The `mode` option. The ladder is no longer something to choose: its shape is
  read from the monitor. A `mode` left in an existing `setup()` call is ignored
  silently and can simply be deleted. The supported surface is now `keys`,
  `loop` and `min_width`.

Configs using the previous hand-rolled loop keep working — `M.run` and the
callable module are unchanged — but both are deprecated as of 1.0.0 and sit
outside the supported surface. Move to `setup()`. See
[ADR 0001](docs/adr/0001-hyprecise-registers-its-own-bindings.md) for why the
binding moved inside the module.

## [0.1.0] — 2026-08-24

Initial release.

### Added

- Width stepping for the focused column along a ladder of discrete stops, bound
  to four directions. Height is never touched.
- Equal redistribution: whatever the focused column does not take is split evenly
  among the remaining columns, with remainder pixels handed out one at a time so
  repeated presses cannot drift.
- `auto` / `wide` / `compact` ladder modes — sixths on wide monitors, quarters
  otherwise, chosen by monitor width under `auto`.
- Fair share spliced into every ladder, so an even split is always one keypress
  away, and a floor for non-focused columns so a neighbour can never be starved.
- Screen-space direction handling: `right` moves the focused column's right
  boundary rightward, falling back to its left boundary for the rightmost column.
- Fallback for ragged layouts, which have no column decomposition to share width
  across.
- Offline spec covering the pure decision core: 46 assertions, no compositor
  required.

[1.1.0]: https://github.com/vitormil/hyprecise/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/vitormil/hyprecise/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/vitormil/hyprecise/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/vitormil/hyprecise/releases/tag/v0.1.0

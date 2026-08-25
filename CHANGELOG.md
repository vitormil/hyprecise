# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

While the version is `0.x`, a documented option may still be withdrawn — as
`mode` was — and the tuning knobs may change without a major bump.

## [Unreleased]

### Removed

- The `mode` option. The ladder is no longer something to choose: its shape is
  read from the monitor. A `mode` left in an existing `setup()` call is ignored
  silently and can simply be deleted. The supported surface is now `keys`,
  `loop` and `min_width`.

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

### Changed

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
- **A keypress is confined to one row.** Windows are selected by the focused
  window's monitor *and* workspace. A tiled window from outside that row would
  bucket into a phantom column and shrink the real windows to make room for it,
  so its presence abandons the keypress instead. Windows that were never columns
  — floating, hidden, unmapped, fullscreen — are ignored as before and trigger
  nothing.
- The selection moved into the pure core as `M.row_windows`, so which windows a
  keypress may touch is now covered by the offline spec rather than living in
  the untested Hyprland shell.
- The offline spec covers granularity across monitor sizes and row membership:
  80 assertions, up from 46.

Configs using the previous hand-rolled loop keep working — `M.run` and the
callable module are unchanged. See
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

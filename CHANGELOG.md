# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

While the version is `0.x`, the three documented options are stable but the
tuning knobs may change without a major bump.

## [Unreleased]

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

- The offline spec covers chord derivation: 57 assertions, up from 46.

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

# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

While the version is `0.x`, the three documented options are stable but the
tuning knobs may change without a major bump.

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

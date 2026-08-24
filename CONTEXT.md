# Context

The vocabulary hyprecise is designed and discussed in. Definitions only — how any
of this is implemented is a question for the source.

## Column

A vertical slice of the workspace: every tiled window sharing the same
x-interval. A column may hold a single window or a vertical stack of several; the
stack is still one column, because it presents one pair of vertical edges to its
neighbours. Columns are what hyprecise resizes. Windows are not.

## Row

The full set of columns on a workspace, read left to right. Hyprecise reasons
about one row at a time: the one the focused window belongs to.

## Boundary

A vertical edge shared between two adjacent columns, or between a column and the
screen. Every resize is the movement of exactly one boundary. Naming the boundary
is what lets a direction be expressed in screen space ("move the right edge
rightward") instead of in intent ("grow") — which is ambiguous for a column that
has no neighbour on the side you pressed.

## Stop

One of the discrete widths the focused column is allowed to occupy. A keypress
always lands it exactly on a stop, never on a free-floating offset from wherever
it happened to be.

## Ladder

The ordered set of stops available for the current keypress. It is derived rather
than configured: the mode contributes its fractions, the fair share is folded in,
and stops that would starve a neighbour past the floor are dropped.

## Mode

Which evenly spaced fractions of the monitor seed the ladder. `wide` uses sixths,
`compact` uses quarters, `auto` chooses by monitor width. A wide monitor earns
finer stops because there is room for adjacent stops to look different.

## Fair share

The width every column would have if the row were split evenly. It is always
reachable as a stop, so "make it even again" is one keypress away from anywhere.

## Floor

The narrowest a non-focused column may become. It exists so that widening the
focused column can never squeeze a neighbour into uselessness.

## Snap

The tolerance below which two widths count as the same stop. It is what keeps a
keypress from resolving to a move too small to see.

## Decomposable

A row is decomposable when its columns tile it side by side without overlapping —
when the layout really is a row of columns, and width can be shared out among
them.

## Ragged

A layout that is not decomposable: some window straddles a boundary its
neighbours observe, so no single left-to-right reading of the row exists. There
is no set of columns to distribute width across, and hyprecise falls back to
moving only the focused window.

# Context

The vocabulary hyprecise is designed and discussed in. Definitions only — how any
of this is implemented is a question for the source.

## Column

A vertical slice of the workspace: a maximal x-interval that no window crosses. A
column may hold a single window, a vertical stack of several, or a whole tree of
splits nested to any depth; it is still one column, because it presents one pair
of vertical edges to its neighbours. What a column contains is never looked at.
Columns are what hyprecise resizes. Windows are not.

## Anchor

The member of a column whose x-interval spans the whole column. A resize is
always aimed at the anchor, because a window that spans its column has no
boundary of its own inside the column — so the first boundary above it is the
column's, and moving it moves the column rather than something nested within.
Ties go to the topmost. A column with no anchor cannot be resized, and a row
containing one is left alone.

## Row

The full set of columns on one workspace of one monitor, read left to right.
Hyprecise reasons about exactly one row at a time — the focused window's — and
never reads or moves a window outside it. A workspace lives on a single monitor,
so the two halves of that boundary normally coincide; a window found on neither
is not part of the row and takes no part in the reckoning.

## Available width

The monitor's logical width less anything reserved at its left or right edges. A
bar along the top of the screen reserves height and does not enter into it; a bar
down one side does. The granularity is read from this and nothing else.

## Row width

The width the columns actually share out: the sum of their widths. Smaller than
the available width by the gaps between and around the windows. Stops are
fractions of this, so every stop names a width a column can really have.

## Boundary

A vertical edge shared between two adjacent columns, or between a column and the
screen. An x-coordinate is a boundary exactly when no window crosses it, which is
what makes a column's contents irrelevant to where its edges are. Every resize is
the movement of exactly one boundary. Naming the boundary
is what lets a direction be expressed in screen space ("move the right edge
rightward") instead of in intent ("grow") — which is ambiguous for a column that
has no neighbour on the side you pressed.

It is also what a dispatch moves, and it moves it rightward by the delta
whichever side of it the window sits on. So the same dispatch widens one of the
boundary's two columns and narrows the other, and a delta only means one thing
once the boundary rather than the column is named.

## Driver

The column whose dispatch moves a given boundary. Each column drives exactly one
of its two edges, and which one is a property of the layout tree rather than of
the geometry, so it has to be asked for. Two columns can drive the boundary they
share, which leaves another with no driver at all; a boundary with no driver
cannot be moved, so a row containing one is left alone.

## Nudge

The one question hyprecise can ask about a layout it cannot see: move a column a
little and look at what the row did. Where the column's left edge went names its
driven boundary; whether the row still reads as the same columns sharing out the
same total says whether it was a column in the first place, rather than an
alignment two independent splits happened to share. A nudge is always undone
before anything else happens, and is larger than the slack columns are bucketed
with, or a row that has come apart still reads as the row it was.

## Chord

The key combination that names a direction. Four of them, one per direction, are
what hyprecise presents to a person; a chord is the only way a resize is ever
asked for. A modifier alone — `SUPER + ALT` — denotes the set of four, because
the directions are arrows and the arrow is implied by the direction it names.

## Stop

One of the discrete widths the focused column is allowed to occupy. A keypress
always lands it exactly on a stop, never on a free-floating offset from wherever
it happened to be.

## Ladder

The ordered set of stops available for the current keypress. It is derived rather
than configured: the granularity says how many stops there are, the fair share is
folded in, and stops that would starve a neighbour past the floor are dropped.

## Granularity

How many equal slices the row is cut into. Derived from the available width and
never chosen: a wide monitor earns finer stops because there is room for adjacent
stops to look different, and it earns them by being wide rather than by being
told that it is.

## Slice

One granularity-th of the row. The spacing between adjacent stops, and the unit a
ladder is measured in.

## Fair share

The width every column would have if the row were split evenly. It is always
reachable as a stop, so "make it even again" is one keypress away from anywhere.

## Floor

The narrowest a non-focused column may become. It exists so that widening the
focused column can never squeeze a neighbour into uselessness.

## Snap

The tolerance below which two widths count as the same stop. It is what keeps a
keypress from resolving to a move too small to see.

## Convergence tolerance

The margin within which a column counts as having arrived at its target width.
It exists because a resize is asked for rather than commanded — the layout
engine answers approximately — so "close enough" has to be a number; a keypress
whose entire requested move falls inside it is abandoned rather than issued.

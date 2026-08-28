# hyprecise

[![tests](https://github.com/vitormil/hyprecise/actions/workflows/test.yml/badge.svg)](https://github.com/vitormil/hyprecise/actions/workflows/test.yml)

**Easy window resizing for Hyprland.**

Hyprland's built-in resize bindings move a window by a fixed pixel delta — press
the key four times and you land somewhere arbitrary, different every session.
Hyprecise steps the focused *column* onto the next stop of a fixed ladder of
widths instead, and splits whatever is left equally among the other columns of
that *row*. The same keypress on the same layout always produces the same
result.

It controls width, and only width. No dispatch it issues ever changes a window's
height.

```
   ┌────────────┬────────────┬────────────┐
   │     A      │     B      │     C      │
   └────────────┴────────────┴────────────┘
         1/3          1/3          1/3

                      │  SUPER + ALT + Right  (A focused)
                      ▼

   ┌──────────────────┬─────────┬─────────┐
   │        A         │    B    │    C    │
   └──────────────────┴─────────┴─────────┘
           1/2            1/4       1/4

                      │  SUPER + ALT + Right
                      ▼

   ┌────────────────────────┬──────┬──────┐
   │           A            │  B   │  C   │
   └────────────────────────┴──────┴──────┘
              2/3              1/6    1/6
```

## Requirements

- **Hyprland with Lua configuration.** Developed and used on 0.56.2.
- **[Omarchy](https://omarchy.org) 4.0+** — optional. Hyprecise is not an Omarchy
  plugin and has no Omarchy dependency. The integration is the same line either
  way: `setup()` calls `hl.bind` directly, and Omarchy's `o.bind` is only a
  wrapper over that.
- **Lua 5.4+ or LuaJIT** — only to run the test suite. Not needed at runtime;
  Hyprland embeds its own interpreter.

## Install

The repository *is* the install. Clone it straight into place:

```sh
git clone https://github.com/vitormil/hyprecise.git ~/.config/hyprecise
```

Then add one line to your Hyprland Lua config — `~/.config/hypr/bindings.lua`
on Omarchy, wherever you keep bindings otherwise:

```lua
dofile(os.getenv("HOME") .. "/.config/hyprecise/hyprecise.lua").setup()
```

That binds `SUPER + ALT + <arrow>` to the four directions, with descriptions, so
they show up in `omarchy menu keybindings --print` alongside everything else.
Pass `keys` to bind something else:

```lua
dofile(os.getenv("HOME") .. "/.config/hyprecise/hyprecise.lua").setup({
  keys = "SUPER + CTRL", -- a different modifier, arrows appended
})
```

`setup()` runs while your config is being read, so it is written never to throw:
if anything goes wrong it binds nothing, prints a `hyprecise:` line to the
Hyprland log and raises a notification. It cannot take the rest of your bindings
down with it. Each keypress is separately wrapped, for the same reason.

> [!IMPORTANT]
> **On Omarchy, `SUPER + ALT + <arrow>` is already taken.** Personal bindings
> load after Omarchy's defaults, so the line above replaces these four:
>
> | Binding | Omarchy default it replaces |
> |---|---|
> | `SUPER + ALT + Left`  | Move window to group on left |
> | `SUPER + ALT + Right` | Move window to group on right |
> | `SUPER + ALT + Up`    | Move window to group on top |
> | `SUPER + ALT + Down`  | Move window to group on bottom |
>
> There is no clean alternative to move to: Omarchy binds *every* modifier over
> the arrows — plain `SUPER` focuses, `SHIFT` swaps, `ALT` groups, `SHIFT + ALT`
> moves the workspace between monitors, `CTRL` walks a group. So if you use
> window grouping, either give hyprecise non-arrow chords with `keys`, or rehome
> the group bindings — they are ordinary
> `hl.dsp.window.move({ into_group = "l" })` dispatches and will work anywhere
> you put them.
>
> Hyprecise binds with a description, so whatever it takes over is visible in
> `omarchy menu keybindings --print` rather than merely gone.

## Shortcuts

| Shortcut | Action |
|---|---|
| `SUPER + ALT + Right` | Move the focused column's **right** edge rightward\* |
| `SUPER + ALT + Left`  | Move the focused column's **left** edge leftward\* |
| `SUPER + ALT + Up`    | Jump to the widest stop (press again for the even split) |
| `SUPER + ALT + Down`  | Jump to the even split (press again for the narrowest stop) |

The ladder is a cycle: a step past the widest stop lands on the narrowest, and
one past the narrowest lands on the widest.

\* For the **rightmost** column the right edge *is* the screen edge and cannot
move, so `Right` moves its left edge rightward instead — the column shrinks.
`Left` likewise grows it. This is what makes a two-window layout behave the same
way from either focus position, and it is deliberate, not a bug.

Every path is silent. Nothing happens on a floating or fullscreen window, on a
workspace with fewer than two tiled windows, on a row that is a single column, or
when the requested move would be smaller than the convergence tolerance.

A keypress only ever reads or moves windows on the focused window's own
workspace, on the focused window's own monitor, in the focused window's own row.
Anything else is dropped before the layout is read, so every column a keypress
touches is on the current monitor by construction.

## Rows and columns

A **column** is a maximal x-interval that no window crosses. A **row** is the
same reading turned ninety degrees. A chord moves one boundary of the focused
window's row, and never looks inside a column.

```
   ┌────────────┬────────────┬─── C ──────┐
   │            │            │     D      │
   │     A      │     B      ├──────┬─────┤
   │            │            │  F   │  G  │
   └────────────┴────────────┴──────┴─────┘

   the row is  A │ B │ C  — three columns, always
```

Split a column, split the halves again — it is still one column. `Right` does
the same thing from `D`, `F` and `G`, because all three are `C`, and the splits
inside keep their proportions.

```
   ┌───────────────────────────────────────┐
   │                   A                   │   row 1
   ├──────────────────┬────────────────────┤
   │        B         │         C          │   row 2
   └──────────────────┴────────────────────┘

                      │  SUPER + ALT + Right  (C focused)
                      ▼

   ┌───────────────────────────────────────┐
   │                   A                   │   unchanged
   ├────────────────────────────┬──────────┤
   │             B              │    C     │
   └────────────────────────────┴──────────┘
```

Rows resize one at a time. A grid is two rows, each with its own boundary, and
they need not be split at the same place; a workspace with no full-width cut is
one row holding everything, which is what most workspaces are.

Two layouts are exceptions. A window straddling its neighbours' boundary leaves
its row a single column, which has no boundary to move, so nothing happens. And
where two rows are the halves of *one* vertical split — a grid built as two
stacks side by side rather than two rows stacked — that split belongs to both
rows at once, so moving it moves both. No dispatch exists that would separate
them.

## Breakpoints

The ladder's shape is not configurable, because there is nothing to get wrong.
Hyprecise cuts the **available width** — the monitor's logical width, less
whatever a side bar reserves — into as many equal slices as fit while keeping
each near 540px. Every multiple of a slice short of the whole is a stop.

| Monitor | Available width | Slices | Stops (of the row) |
|---|---|---|---|
| 1366 | up to 1889 | 3 | thirds |
| 1920 | 1890–2429 | 4 | quarters |
| 2560 | 2430–2969 | 5 | fifths |
| 3440 | 2970–3509 | 6 | sixths |
| 3840 | 3510–4049 | 7 | sevenths |
| 5120 | 4050 and up | 8 | eighths |

## Options

`keys` is the option, and the whole of the supported surface: from 1.0.0 on, a
breaking change to it takes a major version bump.

| Option | Default | Meaning |
|---|---|---|
| `keys` | `"SUPER + ALT"` | A modifier prefix, which binds all four arrows. Or a table naming chords per direction — `{ left = "SUPER + H", right = "SUPER + L", up = "SUPER + K", down = "SUPER + J" }` — which binds only the directions it names. |

If gaps or thick borders make one column read as two, `column_tolerance`
(default 8) is the knob to raise — `row_tolerance` (also 8) is its counterpart
for rows. Both are internal and may change in any release.

## Updating

```sh
git -C ~/.config/hyprecise pull
```

That tracks `master`, which is where releases land. To sit on a fixed version
instead, check out its tag and move when you choose to:

```sh
git -C ~/.config/hyprecise checkout v1.0.0
```

No reload needed. `setup()` records the path it was loaded from and re-reads the
module on every keypress, so the next press uses the new code — which is also why you can edit `hyprecise.lua` and test
a change immediately.

## Tests

The decision core is pure: it takes widths, a focus index and a direction, and
returns target widths. It never calls Hyprland. So it is testable offline, and
the suite runs anywhere:

```sh
lua tests/hyprecise_spec.lua
```

137 assertions covering granularity across monitor sizes, ladder construction,
stepping, redistribution, width conservation, the floor, workspace membership
(including the dropping of out-of-scope windows), row detection, column detection
(vertical stacks, nested trees at several depths, straddling windows, and columns
with no anchor), and chord derivation. The half that issues dispatches is driven
against a model of the dwindle layout in `tests/dwindle.lua`. CI runs them on
every push and pull request.

## How it works

The design rationale lives in the header comment of
[`hyprecise.lua`](hyprecise.lua) — the ladder, the equal split, the screen-space
direction rule, and why a resize is aimed at a column's anchor.
[`CONTEXT.md`](CONTEXT.md) defines the vocabulary those comments use: *row*,
*column*, *anchor*, *available width*, *row width*, *stop*, *slice*, *ladder*,
*granularity*, *fair share*, *boundary*, *chord*, *snap*, *convergence
tolerance*. [`docs/adr/`](docs/adr) records the decisions behind the shape of the
thing.

## License

MIT. See [LICENSE](LICENSE).

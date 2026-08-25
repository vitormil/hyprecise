# hyprecise

[![tests](https://github.com/vitormil/hyprecise/actions/workflows/test.yml/badge.svg)](https://github.com/vitormil/hyprecise/actions/workflows/test.yml)

**Precise, repeatable window width control for Hyprland.**

Hyprland's built-in resize bindings move a window by a fixed pixel delta — press
the key four times and you land somewhere arbitrary, different every session.
Hyprecise steps the focused *column* onto the next stop of a fixed ladder of
widths instead, and splits whatever is left equally among the other columns. The
same keypress on the same layout always produces the same result.

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

<!-- demo: drop the recording here as ![demo](docs/demo.gif) -->

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
Pass options to change any of it:

```lua
dofile(os.getenv("HOME") .. "/.config/hyprecise/hyprecise.lua").setup({
  keys = "SUPER + CTRL", -- a different modifier, arrows appended
  loop = true, -- wrap around the ends of the ladder
  min_width = 400, -- never squeeze a neighbour below this
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

\* For the **rightmost** column the right edge *is* the screen edge and cannot
move, so `Right` moves its left edge rightward instead — the column shrinks.
`Left` likewise grows it. This is what makes a two-window layout behave the same
way from either focus position, and it is deliberate, not a bug.

Every path is silent. Nothing happens on a floating or fullscreen window, on a
workspace with fewer than two tiled windows, on a single column (a lone window or
a pure vertical stack has no vertical boundary to move), or when the requested
move would be smaller than the convergence tolerance.

A keypress only ever reads or moves windows on the focused window's own
workspace, on the focused window's own monitor. If a tiled window outside that
row ever turns up, hyprecise abandons the keypress rather than resize on a
reading of the layout it cannot trust.

## The ladder follows the monitor

There is nothing to configure about the shape of the ladder, because there is
nothing to get wrong. Hyprecise divides the monitor's **available width** — its
logical width less anything a side bar reserves — into as many equal *slices* as
will fit while keeping each one about 540px, the narrowest column still worth
having. Every multiple of a slice short of the whole is a stop.

| Monitor | Slices | Stops |
|---|---|---|
| 1366 | 3 | thirds |
| 1920 | 4 | quarters |
| 2560 | 5 | fifths |
| 3440 | 6 | sixths |
| 3840 | 7 | sevenths |
| 5120 | 8 | eighths |

The stops themselves are fractions of the **row** — the widths your windows
actually add up to — not of the screen, so a stop always names a width a column
can really have. On a 3440 monitor with 10px gaps and 3px borders the row is
3398, and the half stop is 1699 rather than 1720.

## Options

Pass these to `setup()`. These three are the supported surface.

| Option | Default | Meaning |
|---|---|---|
| `keys` | `"SUPER + ALT"` | A modifier prefix, which binds all four arrows. Or a table naming chords per direction — `{ left = "SUPER + H", right = "SUPER + L", up = "SUPER + K", down = "SUPER + J" }` — which binds only the directions it names. |
| `loop` | `true` | Wrap around the ends of the ladder. With `false`, pressing past the widest or narrowest stop does nothing. |
| `min_width` | `nil` | Floor in px for a *non-focused* column. `nil` means available width ÷ 12. Raising it removes wide stops from the ladder. |

### Tuning

Geometry heuristics, exposed for debugging. **Treat these as internal** — they
exist to work around how the layout engine reacts to a resize, and they may
change between releases without a major version bump.

| Option | Default | Meaning |
|---|---|---|
| `snap` | `nil` | Tolerance for "already on this stop". `nil` means `max(16, available width ÷ 100)`. Every other epsilon derives from it. |
| `column_tolerance` | `8` | Pixel slack when bucketing windows into columns. Raise it if gaps or borders cause windows in one column to be read as two. |
| `converge_tolerance` | `4` | Below this many pixels of error, a column counts as on target. |
| `max_passes` | `4` | Sweeps attempted before giving up. A dwindle resize is tree-relative, so one pass does not always converge. |

## Updating

```sh
git -C ~/.config/hyprecise pull
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

80 assertions covering granularity across monitor sizes, ladder construction,
stepping, redistribution, width conservation, the floor, row membership
(including the abort on an out-of-scope window), column detection (including
vertical stacks and ragged layouts), and chord derivation. CI runs them on every
push and pull request.

## How it works

The design rationale lives in the header comment of
[`hyprecise.lua`](hyprecise.lua) — the ladder, the equal split, the screen-space
direction rule, and why ragged layouts are handled separately.
[`CONTEXT.md`](CONTEXT.md) defines the vocabulary those comments use: *column*,
*row*, *available width*, *row width*, *stop*, *slice*, *ladder*, *granularity*,
*fair share*, *boundary*, *chord*, *decomposable*, *ragged*, *snap*. [`docs/adr/`](docs/adr) records the decisions behind the shape of the
thing.

## License

MIT. See [LICENSE](LICENSE).

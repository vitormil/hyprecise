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
  plugin and has no Omarchy dependency; Omarchy just happens to ship the Lua
  config setup that makes the binding a one-liner.
- **Lua 5.4+ or LuaJIT** — only to run the test suite. Not needed at runtime;
  Hyprland embeds its own interpreter.

## Install

The repository *is* the install. Clone it straight into place:

```sh
git clone https://github.com/vitormil/hyprecise.git ~/.config/hyprecise
```

Then add the bindings.

### Omarchy

In `~/.config/hypr/bindings.lua`:

```lua
-- hyprecise: step the focused column's WIDTH through a ladder of sizes, with
-- the other columns splitting what is left over equally. Runs in-process --
-- no subprocess, no hyprctl, no jq.
local hyprecise_path = os.getenv("HOME") .. "/.config/hyprecise/hyprecise.lua"
local hyprecise_opts = {
  mode = "auto", -- auto | wide | compact  (auto: >=3440px uses sixths)
  loop = true, -- wrap around the ends of the ladder
  min_width = nil, -- floor for a non-focused column; nil = monitor/12
}

-- dofile on every press, so edits to hyprecise.lua take effect without
-- reloading Hyprland. pcall so a bug in it can never take the compositor down.
for _, direction in ipairs({ "Left", "Right", "Up", "Down" }) do
  o.bind("SUPER + ALT + " .. direction, nil, function()
    local ok, err = pcall(function()
      dofile(hyprecise_path)(direction:lower(), hyprecise_opts)
    end)
    if not ok then
      hl.notification.create({ text = "hyprecise: " .. tostring(err), duration = 5000 })
    end
  end)
end
```

### Plain Hyprland (no Omarchy)

Identical, except `o.bind(keys, nil, fn)` becomes `hl.bind(keys, fn)`:

```lua
local hyprecise_path = os.getenv("HOME") .. "/.config/hyprecise/hyprecise.lua"
local hyprecise_opts = { mode = "auto", loop = true, min_width = nil }

for _, direction in ipairs({ "Left", "Right", "Up", "Down" }) do
  hl.bind("SUPER + ALT + " .. direction, function()
    local ok, err = pcall(function()
      dofile(hyprecise_path)(direction:lower(), hyprecise_opts)
    end)
    if not ok then
      hl.notification.create({ text = "hyprecise: " .. tostring(err), duration = 5000 })
    end
  end)
end
```

> [!IMPORTANT]
> **On Omarchy, `SUPER + ALT + <arrow>` is already taken.** Personal bindings
> load after Omarchy's defaults, so pasting the snippet above silently replaces
> these four:
>
> | Binding | Omarchy default it replaces |
> |---|---|
> | `SUPER + ALT + Left`  | Move window to group on left |
> | `SUPER + ALT + Right` | Move window to group on right |
> | `SUPER + ALT + Up`    | Move window to group on top |
> | `SUPER + ALT + Down`  | Move window to group on bottom |
>
> If you use window grouping, either bind hyprecise to a different chord or
> rehome the group bindings — they are ordinary `hl.dsp.window.move({ into_group = "l" })`
> dispatches and will work anywhere you put them.

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

## Options

Pass these in the `hyprecise_opts` table. These three are the supported surface.

| Option | Default | Meaning |
|---|---|---|
| `mode` | `"auto"` | `"wide"` seeds the ladder with sixths of the monitor, `"compact"` with quarters. `"auto"` picks `wide` at ≥3440px, `compact` below. |
| `loop` | `true` | Wrap around the ends of the ladder. With `false`, pressing past the widest or narrowest stop does nothing. |
| `min_width` | `nil` | Floor in px for a *non-focused* column. `nil` means monitor width ÷ 12. Raising it removes wide stops from the ladder. |

### Tuning

Geometry heuristics, exposed for debugging. **Treat these as internal** — they
exist to work around how the layout engine reacts to a resize, and they may
change between releases without a major version bump.

| Option | Default | Meaning |
|---|---|---|
| `snap` | `nil` | Tolerance for "already on this stop". `nil` means `max(16, monitor ÷ 100)`. Every other epsilon derives from it. |
| `column_tolerance` | `8` | Pixel slack when bucketing windows into columns. Raise it if gaps or borders cause windows in one column to be read as two. |
| `converge_tolerance` | `4` | Below this many pixels of error, a column counts as on target. |
| `max_passes` | `4` | Sweeps attempted before giving up. A dwindle resize is tree-relative, so one pass does not always converge. |

## Updating

```sh
git -C ~/.config/hyprecise pull
```

No reload needed. The binding re-reads the module on every keypress, so the next
press uses the new code — which is also why you can edit `hyprecise.lua` and test
a change immediately.

## Tests

The decision core is pure: it takes widths, a focus index and a direction, and
returns target widths. It never calls Hyprland. So it is testable offline, and
the suite runs anywhere:

```sh
lua tests/hyprecise_spec.lua
```

46 assertions covering ladder construction, stepping, redistribution, width
conservation, the floor, and column detection (including vertical stacks and
ragged layouts). CI runs them on every push and pull request.

## How it works

The design rationale lives in the header comment of
[`hyprecise.lua`](hyprecise.lua) — the ladder, the equal split, the screen-space
direction rule, and why ragged layouts are handled separately.
[`CONTEXT.md`](CONTEXT.md) defines the vocabulary those comments use: *column*,
*stop*, *ladder*, *fair share*, *boundary*, *decomposable*, *ragged*, *snap*.

## License

MIT. See [LICENSE](LICENSE).

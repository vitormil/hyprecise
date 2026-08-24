# 1. Hyprecise registers its own bindings

## Status

Accepted — 2026-08-24

## Context

Integrating hyprecise took eighteen lines of Lua in the user's `bindings.lua`: a
path variable, an options table, a loop over the four directions, a `dofile` per
press, a `pcall`, and a notification on failure. The README carried that snippet
twice — once for Omarchy, once for plain Hyprland — because the two use
different binder functions.

Three things made that worth revisiting:

- The two variants are not actually different. Omarchy's `o.bind` is a wrapper
  that folds a description into an options table and calls `hl.bind`. One call
  to `hl.bind` covers both.
- Every user pasted the same loop, so every user reimplemented hyprecise's error
  policy, its reload behaviour and its chord layout by copy. A fix to any of
  those could not reach them.
- The snippet passed no description, so the four bindings it took over were
  invisible in `omarchy menu keybindings --print`.

The cost of fixing it is that hyprecise stops being a library that only ever
runs when a key is pressed.

## Decision

Expose `setup(opts)`, which registers the bindings itself. The whole integration
becomes one line:

```lua
dofile(os.getenv("HOME") .. "/.config/hyprecise/hyprecise.lua").setup()
```

Chords come from a `keys` option that takes either shape: a string is a modifier
prefix and denotes all four arrows; a table names chords per direction and binds
only what it names. Deriving one from the other is pure, lives in `M.chords`,
and is covered by the offline spec.

`M.run` and the `__call` metamethod stay, undocumented, so configs holding the
old loop keep working across a `git pull`.

## Consequences

**Hyprecise now runs at config-load time,** which is a failure mode it did not
have. An error raised while `bindings.lua` is being read could take unrelated
bindings with it, so `setup` never throws: the body is wrapped, and a failure
binds nothing, prints a `hyprecise:` line and attempts a notification. Bad input
is not an error either — unusable `keys` yield no chords, so `setup` degrades to
a no-op instead of a crash.

**The module re-reads itself on every press.** Editing `hyprecise.lua` or
pulling an update takes effect on the next keystroke with no `hyprctl reload`,
which the README promises in two places. Keeping that promise once the binding
moved inside the module means the module must know its own path, which it learns
from `debug.getinfo(1, "S").source`. On a Lua built without the `debug` library
this degrades to the module loaded at config time: hot-reload is lost, the
bindings are not.

**The default chord is now a decision hyprecise makes,** not one the user sees
at the call site. `SUPER + ALT + <arrow>` collides with Omarchy's group
bindings, and there is no collision-free alternative — Omarchy binds every
modifier over the arrows. The mitigation is that `setup` passes a description on
every bind, so what it replaced is discoverable where users already look, and
`keys` makes moving off the arrows a one-word change.

**`setup` itself is untested.** It touches the global `hl`, so it sits with
`run`, `apply` and `resize` on the impure side of the file, which the spec does
not reach. Only `chords` is specced. The spec's stated property — no compositor,
no Hyprland API — is preserved.

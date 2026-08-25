-- -----------------------------------------------------------------------------
-- Project: Hyprecise - Precise window resizing for Hyprland
-- Author: Vitor Oliveira
-- License: MIT
--
-- Copyright (c) 2025 Vitor Oliveira
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
-- -----------------------------------------------------------------------------
--
-- Hyprecise controls the WIDTH of tiled columns, and only the width. No
-- dispatch it issues ever changes a window's height.
--
-- The workspace is read as a row of columns. A column is a maximal x-interval
-- that no window crosses: windows whose x-intervals overlap belong to the same
-- column, however deeply the layout engine has subdivided it. So a column
-- holding a nested tree of splits is one column, exactly as a lone window is,
-- and hyprecise never looks inside one. Resizing moves the focused column onto
-- the next stop of a "ladder" of widths, and the remaining columns split what
-- is left over EQUALLY.
--
-- Every resize is aimed at its column's ANCHOR: the member spanning the whole
-- column. A window that spans its column has no side-by-side split above it
-- inside the column, so the first such split the layout engine walks up to is
-- the column's own outer boundary -- which is what moves the boundary between
-- two columns rather than one nested inside them. A column with no anchor
-- cannot be resized, and the keypress is abandoned.
--
-- Direction is expressed in screen space, not in grow/shrink terms: `right`
-- moves the focused column's RIGHT boundary rightward. For every column but the
-- last that boundary is movable, so the column grows. For the last column the
-- right boundary is the screen edge, so `right` falls back to moving its LEFT
-- boundary rightward and the column shrinks. That rule is what makes a
-- two-window layout behave the way it always has, from either focus position.
--
-- The ladder is derived, never configured. How many stops it has follows from
-- the monitor's available width; where those stops sit follows from the width
-- the columns actually share out.
--
-- The pure decision logic (`row_windows`, `columns`, `anchored`,
-- `granularity`, `base_ladder`, `build_ladder`, `plan`, `step`, `chords`) has
-- no Hyprland dependency and is exercised by tests/hyprecise_spec.lua under
-- plain `lua`.

local M = {}

-- --------------------------------------------------------------------------
-- Helpers
-- --------------------------------------------------------------------------

local function idiv(a, b)
  return math.floor(a / b)
end

local function round(x)
  return math.floor(x + 0.5)
end

local DEFAULTS = {
  keys = "SUPER + ALT", -- modifier prefix, or a direction -> chord table
  loop = true, -- wrap around the ends of the ladder
  min_width = nil, -- floor for a non-focused column; nil = available/12
  snap = nil, -- "same stop" tolerance; nil = max(16, available/100)
  column_tolerance = 8, -- px slack when bucketing windows into columns
  converge_tolerance = 4, -- px; below this a column is considered on target
  max_passes = 4, -- sweep attempts before giving up
}

local function with_defaults(user)
  local opts = {}
  for k, v in pairs(DEFAULTS) do
    opts[k] = v
  end
  for k, v in pairs(user or {}) do
    if v ~= nil then
      opts[k] = v
    end
  end
  return opts
end

-- The "same stop" tolerance. Every other epsilon is derived from it, so a
-- keypress can never produce a move smaller than the ambiguity that made two
-- ladder stops indistinguishable in the first place.
local ARROW = { left = "Left", right = "Right", up = "Up", down = "Down" }

--- Expand the `keys` option into a direction -> chord map.
---
--- A string is a modifier prefix and denotes all four chords, because the four
--- directions are arrows and always have been. A table is taken literally, and
--- binds only the directions it names -- which is how a vim-style layout, or a
--- horizontal-only one, gets expressed.
function M.chords(keys)
  if keys == nil then
    keys = DEFAULTS.keys
  end
  local out = {}
  if type(keys) == "string" then
    local prefix = keys:gsub("%s*%+%s*$", ""):gsub("%s+$", "")
    for direction, arrow in pairs(ARROW) do
      out[direction] = prefix .. " + " .. arrow
    end
  elseif type(keys) == "table" then
    for direction in pairs(ARROW) do
      if type(keys[direction]) == "string" then
        out[direction] = keys[direction]
      end
    end
  end
  return out
end

local function snap_of(available, opts)
  return opts.snap or math.max(16, idiv(available, 100))
end

-- --------------------------------------------------------------------------
-- Row membership (pure)
-- --------------------------------------------------------------------------

--- The tiled members of the row: the focused window's own monitor and
--- workspace, and nothing else.
---
--- `scope` is the monitor and workspace the focused window belongs to. A
--- Hyprland workspace lives on exactly one monitor, so every window handed here
--- should already be in scope; one that is not is not part of this row and takes
--- no part in the reckoning. Columns are read from x-intervals alone, so an
--- out-of-scope window would otherwise be read as a real one -- a window on the
--- next monitor along has an x beyond this monitor's right edge and becomes a
--- phantom rightmost column, and the real windows get shrunk to make room for
--- it. Dropping it removes that danger without making the chord dead.
---
--- Windows excluded for the ordinary reasons -- unmapped, hidden, floating,
--- fullscreen -- were never part of the row either: a floating scratchpad is
--- simply not a column, wherever it lives.
--- @param windows table array of HL.Window
--- @param scope table { monitor = id, workspace = id }
--- @return table
function M.row_windows(windows, scope)
  local out = {}
  for _, w in ipairs(windows or {}) do
    if w.mapped and not w.hidden and not w.floating and (w.fullscreen or 0) == 0 then
      local m, ws = w.monitor, w.workspace
      if m and ws and m.id == scope.monitor and ws.id == scope.workspace then
        out[#out + 1] = w
      end
    end
  end
  return out
end

-- --------------------------------------------------------------------------
-- Columns (pure)
-- --------------------------------------------------------------------------

--- Read the boxes as a row of columns.
---
--- A column is a maximal x-interval that no window crosses. Sorting by left
--- edge and sweeping left to right finds them in one pass: a box starting
--- before the running interval ends crosses no boundary, so it joins the column
--- and may extend it; anything else begins a new column past a boundary nobody
--- occupies.
---
--- That is the whole of hyprecise's dealing with nested layouts, and it deals
--- with them by not looking. A column split into a tree of windows is one
--- column because its members overlap each other, exactly as a plain vertical
--- stack is one column because its members share an x-interval. Neither the
--- depth of the tree nor the shape of it is ever inspected.
---
--- Each column also gets its ANCHOR: the member spanning the whole interval,
--- ties going to the topmost. It is the one window whose resize is guaranteed
--- to move the column's own boundary rather than one inside it, because
--- spanning the column means having no side-by-side split above it within the
--- column. A column may have none -- see `M.anchored`.
---
--- @param boxes table array of { x, y, w, id }
--- @param tol number px slack; boxes must overlap by more than this to join
--- @return table array of columns, sorted left to right
function M.columns(boxes, tol)
  tol = tol or DEFAULTS.column_tolerance

  local sorted = {}
  for i, b in ipairs(boxes) do
    sorted[i] = b
  end
  table.sort(sorted, function(a, b)
    if a.x ~= b.x then
      return a.x < b.x
    end
    return a.w > b.w
  end)

  local cols = {}
  for _, b in ipairs(sorted) do
    local c = cols[#cols]
    if c and b.x < c.x + c.w - tol then
      local right = math.max(c.x + c.w, b.x + b.w)
      c.w = right - c.x
      c.members[#c.members + 1] = b
    else
      cols[#cols + 1] = { x = b.x, w = b.w, members = { b } }
    end
  end

  for _, c in ipairs(cols) do
    local anchor, anchor_y
    c.ids = {}
    for _, b in ipairs(c.members) do
      c.ids[#c.ids + 1] = b.id
      local spans = b.x <= c.x + tol and b.x + b.w >= c.x + c.w - tol
      if spans and (anchor == nil or b.y < anchor_y) then
        anchor, anchor_y = b.id, b.y
      end
    end
    c.anchor = anchor
    c.members = nil
  end
  return cols
end

--- True when every column has an anchor, and so can be resized at all.
---
--- A column without one is a chain of windows that overlap each other without
--- any of them covering the lot -- a row split top and bottom first, then each
--- half split side by side at a different ratio, produces exactly that. There
--- is no window whose resize is known to move the outer boundary, so rather
--- than move an inner one and call it done, the keypress is abandoned.
function M.anchored(cols)
  for _, c in ipairs(cols) do
    if not c.anchor then
      return false
    end
  end
  return true
end

-- --------------------------------------------------------------------------
-- Ladder (pure)
-- --------------------------------------------------------------------------

-- The narrowest column still worth having. Granularity is chosen to put a slice
-- as near this as the available width allows, which is the whole of what used to
-- be the `mode` option: a wide monitor earns finer stops because there is room
-- for adjacent stops to look different -- and it earns them by being wide, not
-- by being told it is. 540 is the value that reproduces both of the hand-picked
-- ladders it replaces, quarters at 1920 and sixths at 3440, so no monitor that
-- was already served well is served worse.
local IDEAL_SLICE = 540

-- Below three slices a ladder has one stop either side of the fair share and
-- stops being a ladder; above eight, adjacent stops on any real monitor differ
-- by about a window border.
local MIN_SLICES, MAX_SLICES = 3, 8

--- How many equal slices the row is cut into, read from the available width.
function M.granularity(available)
  local slices = round(available / IDEAL_SLICE)
  if slices < MIN_SLICES then
    return MIN_SLICES
  elseif slices > MAX_SLICES then
    return MAX_SLICES
  end
  return slices
end

--- The stops, as fractions of the row: every multiple of a slice short of the
--- whole. Taken as `row * k / slices` rather than as multiples of a rounded
--- slice, so a fair share that divides the row evenly lands exactly on a stop
--- instead of a pixel beside one.
function M.base_ladder(row_width, slices)
  local stops = {}
  for k = 1, slices - 1 do
    stops[k] = idiv(row_width * k, slices)
  end
  return stops
end

--- Splice the equal-split width into the ladder and drop stops that would
--- starve another column below the floor.
--- @param available number monitor width less its left and right reservations
--- @param row_width number the width the columns actually share out
--- @return table ladder, number fair
function M.build_ladder(available, row_width, n, opts)
  opts = with_defaults(opts)
  local stops = M.base_ladder(row_width, M.granularity(available))
  local fair = idiv(row_width, n)
  local snap = snap_of(available, opts)

  -- Insert `fair`, replacing any stop it is indistinguishable from. Keeping
  -- both would leave two stops a few px apart and make one keypress a
  -- near-no-op.
  local spliced, placed = {}, false
  for _, s in ipairs(stops) do
    if not placed and math.abs(s - fair) <= snap then
      spliced[#spliced + 1] = fair
      placed = true
    elseif not placed and s > fair then
      spliced[#spliced + 1] = fair
      spliced[#spliced + 1] = s
      placed = true
    else
      spliced[#spliced + 1] = s
    end
  end
  if not placed then
    spliced[#spliced + 1] = fair
  end

  -- The floor is a fraction of the screen, not of the ladder. It says what a
  -- column needs in order to stay useful, which is a property of the monitor and
  -- not of how many stops happen to fit across it.
  local floor_w = opts.min_width or idiv(available, 12)
  local max_focused = row_width - (n - 1) * floor_w
  local ladder = {}
  for _, s in ipairs(spliced) do
    if s >= floor_w and s <= max_focused then
      ladder[#ladder + 1] = s
    end
  end
  return ladder, fair
end

-- --------------------------------------------------------------------------
-- Target selection (pure)
-- --------------------------------------------------------------------------

--- Spread `row_width - target` equally over the non-focused columns, handing
--- the remainder pixels out one at a time so repeated presses cannot drift.
local function distribute(row_width, target, n, focused)
  local targets = {}
  local rest = row_width - target
  local each = idiv(rest, n - 1)
  local extra = rest - each * (n - 1)
  local k = 0
  for i = 1, n do
    if i == focused then
      targets[i] = target
    else
      k = k + 1
      targets[i] = each + (k <= extra and 1 or 0)
    end
  end
  return targets
end

local DIRECTIONS = { left = true, right = true, up = true, down = true }

--- Decide the target width of every column.
--- @param input table { widths, focused, direction, available_width, opts }
--- @return table|nil { targets, ladder, fair, target, row_width }, nil on no-op
function M.plan(input)
  if not DIRECTIONS[input.direction] then
    return nil
  end
  local widths = input.widths
  local n = #widths
  local focused = input.focused
  if n < 2 or not focused or focused < 1 or focused > n then
    return nil
  end

  local opts = with_defaults(input.opts)
  local available = input.available_width
  local snap = snap_of(available, opts)

  local row_width = 0
  for _, w in ipairs(widths) do
    row_width = row_width + w
  end

  local ladder, fair = M.build_ladder(available, row_width, n, opts)
  if #ladder == 0 then
    return nil
  end
  -- The floor may have trimmed `fair` off the ladder; keep it in range so
  -- up/down always land on a reachable width.
  local fair_stop = math.max(ladder[1], math.min(ladder[#ladder], fair))

  local current = widths[focused]
  local target = M.step(ladder, current, fair_stop, input.direction, focused == n, snap, opts.loop)
  if not target or math.abs(target - current) <= opts.converge_tolerance then
    return nil
  end

  return {
    targets = distribute(row_width, target, n, focused),
    ladder = ladder,
    fair = fair_stop,
    target = target,
    row_width = row_width,
  }
end

--- Move one stop along the ladder, past `current` in the requested direction.
function M.step(ladder, current, fair, direction, is_last, snap, loop)
  local lo, hi = ladder[1], ladder[#ladder]

  if direction == "up" then
    if math.abs(current - hi) <= snap then
      return fair
    end
    return hi
  elseif direction == "down" then
    if math.abs(current - fair) <= snap then
      return lo
    end
    return fair
  end

  local grow
  if direction == "right" then
    grow = not is_last
  else
    grow = is_last
  end

  if grow then
    for _, s in ipairs(ladder) do
      if s > current + snap then
        return s
      end
    end
    return loop and lo or hi
  end
  for i = #ladder, 1, -1 do
    if ladder[i] < current - snap then
      return ladder[i]
    end
  end
  return loop and hi or lo
end

-- --------------------------------------------------------------------------
-- Hyprland shell (impure)
-- --------------------------------------------------------------------------

--- Logical width of a monitor, accounting for rotation and scale. Window
--- coordinates are logical, so the raw `width` is wrong on a scaled output.
local function monitor_width(m)
  local w, h = m.width, m.height
  local transform = m.transform or 0
  if transform % 2 == 1 then
    w, h = h, w
  end
  local scale = m.scale or 1
  if scale and scale > 0 then
    w = w / scale
  end
  return round(w)
end

--- The available width: the monitor's logical width less whatever is reserved
--- at its left or right edges. A vertical bar is reserved space, and stops taken
--- from the raw width would put the outermost of them underneath it. Reservations
--- are in logical coordinates, like window geometry, so they subtract after the
--- scale has been divided out.
local function available_width(m)
  local reserved = m.reserved or {}
  return monitor_width(m) - (reserved.left or 0) - (reserved.right or 0)
end

local function tiled_windows(ws, scope)
  return M.row_windows(hl.get_workspace_windows(ws), scope)
end

local function resize(win, delta)
  hl.dispatch(hl.dsp.window.resize({
    x = delta,
    y = 0,
    relative = true,
    window = "address:" .. win.address,
  }))
end

--- Walk the columns left to right, nudging each onto its target and re-reading
--- geometry as we go. Each nudge is aimed at the column's anchor, which spans
--- the column -- so its width IS the column's width, and moving it moves the
--- column's own boundary. A dwindle resize is tree-relative, so one sweep only
--- converges for right-nested trees; repeat until everything is on target.
local function apply(cols, targets, opts)
  for _ = 1, opts.max_passes do
    for i = 1, #cols - 1 do
      local delta = targets[i] - cols[i].win.size.x
      if math.abs(delta) > opts.converge_tolerance then
        resize(cols[i].win, delta)
      end
    end
    local worst = 0
    for i = 1, #cols do
      local err = math.abs(targets[i] - cols[i].win.size.x)
      if err > worst then
        worst = err
      end
    end
    if worst <= opts.converge_tolerance then
      return true
    end
  end
  return false
end

--- Entry point. Silent on every no-op path: this runs on a keybind, so there
--- is nowhere for a message to go.
local function run(direction, user_opts)
  if not DIRECTIONS[direction] then
    return
  end
  local opts = with_defaults(user_opts)

  local win = hl.get_active_window()
  if not win or win.floating or (win.fullscreen or 0) ~= 0 then
    return
  end
  local ws, monitor = win.workspace, win.monitor
  if not ws or not monitor then
    return
  end

  -- Everything hyprecise reads or moves belongs to one row: the focused window's
  -- workspace on the focused window's monitor. Anything else is dropped, so the
  -- columns it goes on to read are this monitor's and no others'.
  local scope = { monitor = monitor.id, workspace = ws.id }
  local wins = tiled_windows(ws, scope)
  if not wins or #wins < 2 then
    return
  end

  local boxes = {}
  for i, w in ipairs(wins) do
    boxes[i] = { x = w.at.x, y = w.at.y, w = w.size.x, id = i }
  end

  local cols = M.columns(boxes, opts.column_tolerance)
  if #cols < 2 then
    -- One column: a lone window, a vertical stack, or a workspace subdivided
    -- entirely inside itself. There is no boundary between columns to move and
    -- heights are out of scope, so there is nothing to do.
    return
  end

  if not M.anchored(cols) then
    return
  end

  local widths, focused = {}, nil
  for i, c in ipairs(cols) do
    widths[i] = c.w
    c.win = wins[c.anchor]
    -- The focused window may be nested arbitrarily deep; what matters is only
    -- which column holds it. Its own geometry is never used.
    for _, id in ipairs(c.ids) do
      if wins[id].address == win.address then
        focused = i
      end
    end
  end
  if not focused then
    return
  end

  local plan = M.plan({
    widths = widths,
    focused = focused,
    direction = direction,
    available_width = available_width(monitor),
    opts = opts,
  })
  if not plan then
    return
  end

  apply(cols, plan.targets, opts)
end

M.run = run

-- --------------------------------------------------------------------------
-- Binding (impure)
-- --------------------------------------------------------------------------

--- Path of this file. `dofile` remembers the path it was handed and `source`
--- gives it back with a leading "@", so a handler can re-read the module on
--- every press. Nil on a Lua built without the debug library, which costs the
--- reload-on-edit behaviour and nothing else.
local SELF = debug and debug.getinfo(1, "S").source:match("^@(.*)")

local DESCRIPTIONS = {
  left = "Hyprecise: move the left edge leftward",
  right = "Hyprecise: move the right edge rightward",
  up = "Hyprecise: jump to the widest stop",
  down = "Hyprecise: jump to the even split",
}

--- Bind hyprecise to the keyboard. One line in a Hyprland Lua config is the
--- whole integration:
---
---   dofile(os.getenv("HOME") .. "/.config/hyprecise/hyprecise.lua").setup()
---
--- `hl.bind` is called directly rather than Omarchy's `o.bind`, which is only a
--- wrapper over it -- so the same call works with or without Omarchy.
---
--- This runs while the config file is being read, unlike everything else here,
--- which runs on a keypress. So it must never throw: an error raised at that
--- moment would take the rest of the user's bindings down with it.
function M.setup(user_opts)
  local ok, err = pcall(function()
    local opts = with_defaults(user_opts)
    for direction, chord in pairs(M.chords(opts.keys)) do
      hl.bind(chord, function()
        -- Re-read the module on every press, so an edit or a `git pull` takes
        -- effect on the next keystroke. pcall so a bug in it can never take
        -- the compositor down.
        local pressed, oops = pcall(function()
          local current = SELF and dofile(SELF) or M
          current.run(direction, opts)
        end)
        if not pressed then
          hl.notification.create({ text = "hyprecise: " .. tostring(oops), duration = 5000 })
        end
      end, { description = DESCRIPTIONS[direction] })
    end
  end)
  if not ok then
    -- Nothing is bound. Say so where a Hyprland user will find it.
    print("hyprecise: setup failed: " .. tostring(err))
    pcall(function()
      hl.notification.create({ text = "hyprecise: setup failed: " .. tostring(err), duration = 8000 })
    end)
  end
  return ok
end

return setmetatable(M, {
  __call = function(_, direction, opts)
    return run(direction, opts)
  end,
})

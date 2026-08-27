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
-- The workspace is read as a stack of ROWS, and one of them -- the focused
-- window's -- as a line of COLUMNS. A row is a maximal y-interval that no window
-- crosses; a column is a maximal x-interval that no window crosses. They are the
-- same reading of the layout on the two axes, and the row reading comes first
-- because it says which windows the column reading is about. A workspace with no
-- full-width horizontal cut is a single row holding everything, which is what
-- hyprecise has always read; one with such a cut -- a window over a pair, a
-- grid, a stack of bands -- gives each row its own boundaries, and a chord moves
-- the focused row's and leaves the other rows where they are.
--
-- Within that row, windows whose x-intervals overlap belong to the same column,
-- however deeply the layout engine has subdivided it. So a column holding a
-- nested tree of splits is one column, exactly as a lone window is, and
-- hyprecise never looks inside one. Resizing moves the focused column onto the
-- next stop of a "ladder" of widths, and the remaining columns of that row split
-- what is left over EQUALLY.
--
-- Every resize is aimed at its column's ANCHOR: the member spanning the whole
-- column. A window that spans its column has no side-by-side split above it
-- inside the column, so the first such split the layout engine walks up to is
-- the column's own outer boundary -- which is what moves the boundary between
-- two columns rather than one nested inside them. A column with no anchor
-- cannot be resized, and the keypress is abandoned.
--
-- What a dispatch does with that split is move it RIGHTWARD by the delta,
-- whichever side of it the anchor sits on. So the same dispatch widens a column
-- whose anchor is the split's left half and narrows one whose anchor is its
-- right half, and nothing in the geometry says which a column is. Hyprecise
-- therefore asks, by nudging each column and watching where its left edge went,
-- and then works in BOUNDARIES rather than widths -- because a boundary is what
-- a dispatch moves, and naming it makes the delta mean one thing no matter
-- which of its two columns is asked.
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
-- The pure decision logic (`workspace_windows`, `rows`, `columns`, `anchored`,
-- `granularity`, `base_ladder`, `build_ladder`, `plan`, `step`, `chords`) has
-- no Hyprland dependency and is exercised by tests/hyprecise_spec.lua under
-- plain `lua`. `run` itself is exercised there too, against a model of the
-- dwindle layout in tests/dwindle.lua: the half of hyprecise that issues
-- dispatches is only correct in terms of how the layout engine answers them, so
-- the answers are modelled rather than assumed.

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
  row_tolerance = 8, -- px slack when bucketing windows into rows
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
-- Workspace membership (pure)
-- --------------------------------------------------------------------------

--- The tiled windows of the workspace: the focused window's own monitor and
--- workspace, and nothing else. Everything a keypress may read or move is drawn
--- from this set, and the rows and columns below are read from nothing else.
---
--- `scope` is the monitor and workspace the focused window belongs to. A
--- Hyprland workspace lives on exactly one monitor, so every window handed here
--- should already be in scope; one that is not takes no part in the reckoning.
--- Columns are read from x-intervals alone, so an out-of-scope window would
--- otherwise be read as a real one -- a window on the next monitor along has an
--- x beyond this monitor's right edge and becomes a phantom rightmost column,
--- and the real windows get shrunk to make room for it. Dropping it removes that
--- danger without making the chord dead.
---
--- Windows excluded for the ordinary reasons -- unmapped, hidden, floating,
--- fullscreen -- were never columns either: a floating scratchpad is simply not
--- a column, wherever it lives.
--- @param windows table array of HL.Window
--- @param scope table { monitor = id, workspace = id }
--- @return table
function M.workspace_windows(windows, scope)
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
-- Rows and columns (pure)
-- --------------------------------------------------------------------------

--- Sweep boxes into maximal intervals along one axis.
---
--- Sorting by near edge and walking left to right -- or top to bottom -- finds
--- them in one pass: a box starting before the running interval ends crosses no
--- boundary, so it joins the interval and may extend it; anything else begins a
--- new one past a boundary nobody occupies.
---
--- `pos` and `len` name the axis: "x" and "w" for columns, "y" and "h" for rows.
--- A row is the same reading of the layout turned ninety degrees, and one sweep
--- is easier to be sure of than two.
local function sweep(boxes, tol, pos, len)
  local sorted = {}
  for i, b in ipairs(boxes) do
    sorted[i] = b
  end
  table.sort(sorted, function(a, b)
    if a[pos] ~= b[pos] then
      return a[pos] < b[pos]
    end
    return a[len] > b[len]
  end)

  local groups = {}
  for _, b in ipairs(sorted) do
    local g = groups[#groups]
    if g and b[pos] < g[pos] + g[len] - tol then
      local far = math.max(g[pos] + g[len], b[pos] + b[len])
      g[len] = far - g[pos]
      g.members[#g.members + 1] = b
    else
      groups[#groups + 1] = { [pos] = b[pos], [len] = b[len], members = { b } }
    end
  end
  return groups
end

--- Read the boxes as a stack of rows.
---
--- A row is a maximal y-interval that no window crosses -- the mirror of a
--- column, and read by the same sweep. A workspace of windows side by side is
--- one row, however deeply each of them is subdivided, because every one of them
--- spans the whole height and so they all overlap. A workspace cut across its
--- full width -- one window over a pair, a grid, a stack of bands -- is as many
--- rows as the cuts leave.
---
--- Rows carry no anchor. An anchor exists to say which window's resize moves a
--- column's own boundary, and hyprecise never moves a horizontal one: a row is
--- only ever used to say which windows a keypress is about.
---
--- @param boxes table array of { x, y, w, h, id }
--- @param tol number px slack; boxes must overlap by more than this to join
--- @return table array of rows, sorted top to bottom
function M.rows(boxes, tol)
  local rows = sweep(boxes, tol or DEFAULTS.row_tolerance, "y", "h")
  for _, r in ipairs(rows) do
    r.ids = {}
    for _, b in ipairs(r.members) do
      r.ids[#r.ids + 1] = b.id
    end
    r.members = nil
  end
  return rows
end

--- Read the boxes as a row of columns.
---
--- A column is a maximal x-interval that no window crosses, found by the sweep
--- above.
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
  local cols = sweep(boxes, tol, "x", "w")

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
  return M.workspace_windows(hl.get_workspace_windows(ws), scope)
end

local function resize(win, delta)
  hl.dispatch(hl.dsp.window.resize({
    x = delta,
    y = 0,
    relative = true,
    window = "address:" .. win.address,
  }))
end

--- The focused row as it stands, read back from live geometry.
local function read_row(wins, opts)
  local boxes = {}
  for i, w in ipairs(wins) do
    boxes[i] = { x = w.at.x, y = w.at.y, w = w.size.x, id = i }
  end
  return M.columns(boxes, opts.column_tolerance)
end

--- Ask one column two questions at once, by nudging it and looking at what the
--- whole row did. Returns the edge that moved, and whether the row survived
--- being asked; the nudge is undone before either is reported.
---
--- WHICH EDGE. A dispatch moves the first side-by-side split above the anchor.
--- Everything between the anchor and that split is a top/bottom split, which
--- leaves the x-interval alone, so the split IS one of the column's own edges --
--- but which of the two depends on the side of it the anchor sits on, and no
--- amount of geometry says. Where the column's left edge went does.
---
--- WHETHER IT IS A COLUMN AT ALL. An x-interval no window crosses need not be a
--- thing that moves as one. Two side-by-side splits stacked one above the other
--- at the same ratio -- a grid -- present exactly the edges a single column
--- would, and come apart the moment either half is moved. A real column takes
--- its whole row with it, so the row still reads as the same columns afterwards
--- and still shares out the same total width.
local function ask(wins, win, nudge, columns, total, opts)
  local x0, w0 = win.at.x, win.size.x
  resize(win, nudge)

  local left = win.at.x ~= x0
  local answered = left or win.size.x ~= w0
  local after = read_row(wins, opts)
  local sum = 0
  for _, c in ipairs(after) do
    sum = sum + c.w
  end
  local intact = #after == columns and math.abs(sum - total) <= 1

  resize(win, -nudge)
  return answered and (left and "left" or "right") or nil, intact
end

--- Which edge every column drives. Nil when the row does not survive being
--- asked, which is the grid above and anything else whose columns are an
--- accident of alignment rather than a property of the layout.
---
--- The nudge has to be bigger than the slack columns are bucketed with,
--- otherwise a row that has come apart still reads as the row it was.
local function survey(wins, cols, opts)
  local nudge = 2 * opts.column_tolerance + 1
  local total = 0
  for _, c in ipairs(cols) do
    total = total + c.w
  end

  local edge = {}
  for i = 1, #cols do
    local answer, intact = ask(wins, cols[i].win, nudge, #cols, total, opts)
    if not intact then
      return nil
    end
    if not answer then
      -- A split already at the layout engine's ratio limit will not go further
      -- one way. Ask the other way before concluding anything.
      answer, intact = ask(wins, cols[i].win, -nudge, #cols, total, opts)
      if not intact or not answer then
        return nil
      end
    end
    edge[i] = answer
  end
  return edge
end

--- Pair every boundary with the column that moves it, so that a delta means one
--- thing throughout: move THIS boundary rightward by that many pixels,
--- whichever of its two columns is asked.
---
--- Nil when some boundary belongs to no column. A split lies strictly inside the
--- box it divides, so the first column's split can only be its right edge and
--- the last column's only its left -- but in between, two columns can both drive
--- the boundary they share and leave another with nobody, which is what a split
--- whose halves are themselves side-by-side splits looks like from here. Such a
--- boundary cannot be moved at all, so the row cannot be arranged as planned and
--- the keypress is abandoned rather than half-served.
local function drivers(wins, cols, opts)
  local edge = survey(wins, cols, opts)
  if not edge then
    return nil
  end

  local driver = {}
  for i = 1, #cols do
    local boundary = edge[i] == "right" and i or i - 1
    if boundary >= 1 and boundary <= #cols - 1 and not driver[boundary] then
      driver[boundary] = cols[i].win
    end
  end
  for j = 1, #cols - 1 do
    if not driver[j] then
      return nil
    end
  end
  return driver
end

--- Walk the boundaries, moving each onto the position the target widths put it
--- at, and re-reading geometry as we go.
---
--- Boundaries rather than columns, because a boundary is what a dispatch moves:
--- it slides one split rightward by the delta and rescales whatever sits on the
--- far side of it, however many columns that is. A boundary nearer the root of
--- the layout tree therefore disturbs the ones below it, so one sweep settles
--- only the outermost, the next settles the one below that, and the number of
--- sweeps has to keep up with the number of columns.
---
--- A boundary's position is read as the width of everything to the left of it,
--- which moves pixel for pixel with the boundary because the gaps never change.
local function apply(wins, cols, targets, opts)
  local driver = drivers(wins, cols, opts)
  if not driver then
    return false
  end

  local want, running = {}, 0
  for j = 1, #cols - 1 do
    running = running + targets[j]
    want[j] = running
  end

  local function have(j)
    local sum = 0
    for i = 1, j do
      sum = sum + cols[i].win.size.x
    end
    return sum
  end

  for _ = 1, math.max(opts.max_passes, #cols) do
    for j = 1, #cols - 1 do
      local delta = want[j] - have(j)
      if math.abs(delta) > opts.converge_tolerance then
        resize(driver[j], delta)
      end
    end
    local worst = 0
    for j = 1, #cols - 1 do
      local err = math.abs(want[j] - have(j))
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

--- The windows of the row `address` is in, in the order the row reading found
--- them. Empty when the focused window is not among the boxes, which it always
--- is: a window is in exactly one row.
local function focused_row(wins, boxes, address, tol)
  for _, r in ipairs(M.rows(boxes, tol)) do
    for _, id in ipairs(r.ids) do
      if wins[id].address == address then
        local out = {}
        for _, member in ipairs(r.ids) do
          out[#out + 1] = wins[member]
        end
        return out
      end
    end
  end
  return {}
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

  -- Everything hyprecise reads or moves belongs to the focused window's
  -- workspace on the focused window's monitor. Anything else is dropped, so the
  -- rows and columns it goes on to read are this monitor's and no others'.
  local scope = { monitor = monitor.id, workspace = ws.id }
  local tiled = tiled_windows(ws, scope)
  if not tiled or #tiled < 2 then
    return
  end

  local boxes = {}
  for i, w in ipairs(tiled) do
    boxes[i] = { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y, id = i }
  end

  -- Which ROW the keypress is about. A workspace cut across its full width is
  -- several rows, and each of them has its own boundaries; a chord moves the
  -- focused window's row and leaves the others where they are. A workspace with
  -- no such cut is one row holding every window, which is what it has always
  -- been read as.
  local wins = focused_row(tiled, boxes, win.address, opts.row_tolerance)
  if #wins < 2 then
    -- A row of one: a full-width window over a pair, focused on the full-width
    -- one. It has no neighbour to share a boundary with, and heights are out of
    -- scope, so there is nothing to do.
    return
  end

  -- Re-box against the row, so a column's `anchor` and `ids` index the row's own
  -- windows and every later reading is confined to it.
  local row_boxes = {}
  for i, w in ipairs(wins) do
    row_boxes[i] = { x = w.at.x, y = w.at.y, w = w.size.x, id = i }
  end

  local cols = M.columns(row_boxes, opts.column_tolerance)
  if #cols < 2 then
    -- One column: a lone window, a vertical stack, or a row subdivided entirely
    -- inside itself. There is no boundary between columns to move and heights
    -- are out of scope, so there is nothing to do.
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

  apply(wins, cols, plan.targets, opts)
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

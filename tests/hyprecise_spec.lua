-- Offline tests for the pure decision core of hyprecise.
--
-- Run from the repository root with any Lua 5.4+ interpreter, or LuaJIT:
--   lua tests/hyprecise_spec.lua
--
-- No compositor required. The suite touches no Hyprland API -- only
-- M.workspace_windows, M.rows, M.columns, M.anchored, M.granularity,
-- M.base_ladder, M.build_ladder, M.step and M.plan -- which is the whole reason
-- the decision logic is kept pure.

local here = arg[0]:match("(.*)/") or "."
local M = dofile(here .. "/../hyprecise.lua")

local MW = 3440 -- the ultrawide these fixtures are sized for, less nothing:
-- its bar reserves height, not width, so available width is the full 3440.
local passed, failed = 0, 0

local function fmt(v)
  if type(v) ~= "table" then
    return tostring(v)
  end
  local parts = {}
  for _, x in ipairs(v) do
    parts[#parts + 1] = tostring(x)
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return a == b
  end
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

local function check(name, got, want)
  if same(got, want) then
    passed = passed + 1
    print(string.format("ok    %-46s %s", name, fmt(got)))
  else
    failed = failed + 1
    print(string.format("FAIL  %-46s got %s want %s", name, fmt(got), fmt(want)))
  end
end

local function plan(widths, focused, direction, opts)
  return M.plan({
    widths = widths,
    focused = focused,
    direction = direction,
    available_width = MW,
    opts = opts,
  })
end

local function targets(widths, focused, direction, opts)
  local p = plan(widths, focused, direction, opts)
  return p and p.targets or nil
end

-- ---------------------------------------------------------------------------
-- Ladder construction
-- ---------------------------------------------------------------------------

-- Granularity is read from the monitor and cannot be asked for. The two widths
-- that used to have hand-picked ladders keep exactly the ladders they had.
check("granularity @1366 clamps up to the minimum", M.granularity(1366), 3)
check("granularity @1600", M.granularity(1600), 3)
check("granularity @1920 -> quarters, as `compact` did", M.granularity(1920), 4)
check("granularity @2560 -> fifths", M.granularity(2560), 5)
check("granularity @3440 -> sixths, as `wide` did", M.granularity(MW), 6)
check("granularity @3840 -> sevenths", M.granularity(3840), 7)
check("granularity @5120 clamps down to the maximum", M.granularity(5120), 8)

-- A ladder that got coarser as the monitor got wider would be nonsense.
local monotonic, previous = true, 0
for w = 640, 8000, 10 do
  local g = M.granularity(w)
  if g < previous then
    monotonic = false
  end
  previous = g
end
check("granularity never decreases with width", monotonic, true)

-- A side bar is reserved WIDTH, so it reaches the ladder; the top bar on this
-- monitor reserves height and does not.
check("a 300px side bar leaves granularity alone", M.granularity(MW - 300), 6)
check("a 900px side bar coarsens the ladder", M.granularity(MW - 900), 5)

-- Stops are fractions of the ROW, not of the screen. Real geometry: two windows
-- on this monitor sum to 3398, not 3440 -- gaps and borders eat 42px.
check("base_ladder over a 3398 row, 6 slices", M.base_ladder(3398, 6), { 566, 1132, 1699, 2265, 2831 })
check("base_ladder over a 1900 row, 4 slices", M.base_ladder(1900, 4), { 475, 950, 1425 })
check("base_ladder yields one stop short of the whole", #M.base_ladder(3398, 8), 7)

-- Taking a stop as row*k/slices rather than as a multiple of a rounded slice is
-- what lands the fair share exactly on one instead of a pixel beside it.
local l2, fair2 = M.build_ladder(MW, 3398, 2)
check("N=2 fair share IS a stop, nothing to splice", { l2[3], fair2 }, { 1699, 1699 })
check("N=2 ladder", l2, { 566, 1132, 1699, 2265, 2831 })

local l3 = M.build_ladder(MW, 3382, 3)
check("N=3 ladder (fair 1127 is already stop 2)", l3, { 563, 1127, 1691, 2254 })

local l4 = M.build_ladder(MW, 3380, 4)
check("N=4 ladder (fair 845 spliced in)", l4, { 563, 845, 1126, 1690, 2253 })

local l6 = M.build_ladder(MW, 3360, 6)
check("N=6 ladder (top stops trimmed by floor)", l6, { 560, 1120, 1680 })

-- The floor reads the screen, not the ladder, so it does not move when the
-- number of windows does -- and past a certain crowd it is what is left of the
-- ladder.
local crowded = M.build_ladder(MW, 3398, 10)
check("at ten columns only the stops that clear the floor survive", crowded, { 339, 566 })

-- ---------------------------------------------------------------------------
-- N=2 -- must keep behaving the way it always has, from either focus position
-- ---------------------------------------------------------------------------

local two = { 1719, 1679 }

check("N=2 focus0 right  -> left col grows", targets(two, 1, "right"), { 2265, 1133 })
check("N=2 focus1 right  -> left col grows (inverts)", targets(two, 2, "right"), { 2266, 1132 })
check("N=2 focus0 left   -> left col shrinks", targets(two, 1, "left"), { 1132, 2266 })
check("N=2 focus1 left   -> right col grows", targets(two, 2, "left"), { 1133, 2265 })

-- The key property the whole direction rule exists to preserve: `right` moves
-- the boundary rightward no matter which of the two windows is focused.
local r0 = targets(two, 1, "right")
local r1 = targets(two, 2, "right")
check("N=2 right grows col0 from BOTH focuses", { r0[1] > two[1], r1[1] > two[1] }, { true, true })
local x0 = targets(two, 1, "left")
local x1 = targets(two, 2, "left")
check("N=2 left shrinks col0 from BOTH focuses", { x0[1] < two[1], x1[1] < two[1] }, { true, true })

check("N=2 focus0 up     -> maximize", targets(two, 1, "up"), { 2831, 567 })
check("N=2 maxed  up     -> back to equal", targets({ 2831, 567 }, 1, "up"), { 1699, 1699 })
check("N=2 focus0 down   -> already equal, minimize", targets(two, 1, "down"), { 566, 2832 })
check("N=2 wide   down   -> equalize", targets({ 2831, 567 }, 1, "down"), { 1699, 1699 })

-- ---------------------------------------------------------------------------
-- N=3 -- the case that motivated the rewrite
-- ---------------------------------------------------------------------------

local three = { 1719, 829, 834 } -- live geometry from workspace 2

check("N=3 focus0 right  -> others shrink equally", targets(three, 1, "right"), { 2254, 564, 564 })
check("N=3 focus1 right  -> middle grows", targets(three, 2, "right"), { 1128, 1127, 1127 })
check("N=3 focus2 right  -> LAST col shrinks", targets(three, 3, "right"), { 1410, 1409, 563 })
check("N=3 focus2 left   -> LAST col grows", targets(three, 3, "left"), { 1128, 1127, 1127 })
check("N=3 focus0 down   -> equalize", targets(three, 1, "down"), { 1127, 1128, 1127 })
check("N=3 focus0 up     -> maximize", targets(three, 1, "up"), { 2254, 564, 564 })

-- ---------------------------------------------------------------------------
-- N=4 / N=5
-- ---------------------------------------------------------------------------

local four = { 845, 845, 845, 845 }
check("N=4 focus0 right", targets(four, 1, "right"), { 1126, 752, 751, 751 })
check("N=4 focus3 right  -> LAST col shrinks", targets(four, 4, "right"), { 939, 939, 939, 563 })

local five = { 676, 676, 676, 676, 676 }
-- The row is 3380, so the 2254 left over splits 564/564/563/563.
check("N=5 focus2 right", targets(five, 3, "right"), { 564, 564, 1126, 563, 563 })

-- ---------------------------------------------------------------------------
-- No-ops and edges
-- ---------------------------------------------------------------------------

check("N=1 -> no-op", plan({ 3414 }, 1, "right"), nil)
check("bad direction -> no-op", plan(two, 1, "sideways"), nil)
check("focus out of range -> no-op", plan(two, 3, "right"), nil)

check("loop=true wraps past the top", targets({ 2831, 567 }, 1, "right", { loop = true }), { 566, 2832 })
check("loop=false clamps (no-op at the top)", plan({ 2831, 567 }, 1, "right", { loop = false }), nil)
check("loop=true wraps past the bottom", targets({ 566, 2832 }, 1, "left", { loop = true }), { 2831, 567 })

-- Too many columns for the floor to allow any stop at all.
local many = {}
for i = 1, 12 do
  many[i] = 283
end
check("N=12 -> ladder empty, no-op", plan(many, 1, "right"), nil)

-- ---------------------------------------------------------------------------
-- Invariants that must hold for every plan
-- ---------------------------------------------------------------------------

local layouts = { two, three, four, five, { 1000, 1200, 1198 }, { 2831, 283, 284 } }
local dirs = { "left", "right", "up", "down" }
local sum_ok, floor_ok, height_ok = true, true, true

for _, widths in ipairs(layouts) do
  local row_width = 0
  for _, w in ipairs(widths) do
    row_width = row_width + w
  end
  for focused = 1, #widths do
    for _, dir in ipairs(dirs) do
      local p = plan(widths, focused, dir)
      if p then
        local total = 0
        for _, t in ipairs(p.targets) do
          total = total + t
          if t < 1 then
            floor_ok = false
          end
        end
        if total ~= row_width then
          sum_ok = false
        end
        -- The plan describes widths only; nothing in it can move a height.
        for k in pairs(p) do
          if k == "heights" or k == "y" then
            height_ok = false
          end
        end
      end
    end
  end
end

check("every plan conserves total width", sum_ok, true)
check("no plan produces a non-positive column", floor_ok, true)
check("no plan carries any height component", height_ok, true)

-- Non-focused columns are always equal to within one pixel.
local equal_ok = true
for _, widths in ipairs(layouts) do
  for focused = 1, #widths do
    for _, dir in ipairs(dirs) do
      local p = plan(widths, focused, dir)
      if p and #widths > 2 then
        local lo, hi
        for i, t in ipairs(p.targets) do
          if i ~= focused then
            lo = (lo == nil or t < lo) and t or lo
            hi = (hi == nil or t > hi) and t or hi
          end
        end
        if hi - lo > 1 then
          equal_ok = false
        end
      end
    end
  end
end
check("non-focused columns equal within 1px", equal_ok, true)

-- ---------------------------------------------------------------------------
-- Workspace membership -- which windows a keypress is allowed to touch
-- ---------------------------------------------------------------------------

local SCOPE = { monitor = 0, workspace = 2 }

--- A window fixture. Everything defaults to "tiled, and on this monitor and
--- workspace"; pass `monitor = false` to make the field absent altogether.
local function win(t)
  t = t or {}
  return {
    mapped = t.mapped ~= false,
    hidden = t.hidden or false,
    floating = t.floating or false,
    fullscreen = t.fullscreen or 0,
    monitor = t.monitor ~= false and { id = t.monitor or SCOPE.monitor } or nil,
    workspace = t.workspace ~= false and { id = t.workspace or SCOPE.workspace } or nil,
  }
end

local function members(list)
  local tiled = M.workspace_windows(list, SCOPE)
  return tiled and #tiled or nil
end

check("all in scope -> every tiled window", members({ win(), win() }), 2)
check("floating is not a column", members({ win(), win({ floating = true }) }), 1)
check(
  "hidden, unmapped and fullscreen are not columns",
  members({ win(), win({ hidden = true }), win({ mapped = false }), win({ fullscreen = 2 }) }),
  1
)
check("no windows -> an empty workspace, not a refusal", members({}), 0)
check("no list at all -> an empty workspace, not a refusal", members(nil), 0)

-- Scope is a filter, not a veto. A tiled window from elsewhere sits at an x
-- beyond this monitor, so read as a column it would be a phantom rightmost one
-- and the real windows would be shrunk to make room for it. Dropping it removes
-- that danger while leaving the chord alive for the windows that do belong.
check("tiled window on another monitor is dropped", members({ win(), win({ monitor = 1 }) }), 1)
check("tiled window on another workspace is dropped", members({ win(), win({ workspace = 9 }) }), 1)
check("tiled window with no monitor is dropped", members({ win({ monitor = false }), win() }), 1)
check("tiled window with no workspace is dropped", members({ win({ workspace = false }), win() }), 1)
check("a workspace of foreign windows is empty, not a refusal", members({ win({ monitor = 1 }), win({ monitor = 2 }) }), 0)
check("an in-scope workspace is never trimmed", members({ win(), win(), win() }), 3)

-- An out-of-scope window that was never going to be a column aborts nothing. A
-- floating scratchpad on the next monitor along is simply not part of this
-- workspace.
check("floating window from elsewhere is ignored", members({ win(), win({ floating = true, monitor = 1 }) }), 1)
check("hidden window from elsewhere is ignored", members({ win(), win({ hidden = true, workspace = 9 }) }), 1)

--- A box fixture: { x, y, w } and, where a test is about rows, a height. The
--- default height is one that reaches the bottom of a 1440 screen, so a fixture
--- that says nothing about heights is a single full-height row.
local function boxes(list)
  local out = {}
  for i, b in ipairs(list) do
    out[i] = { x = b[1], y = b[2], w = b[3], h = b[4] or (1430 - b[2]), id = i }
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Row detection
-- ---------------------------------------------------------------------------
--
-- A row is a maximal y-interval that no window crosses -- the mirror of a
-- column, read by the same sweep. It says which windows a keypress is about;
-- the column reading then happens inside it.

--- How many windows each row holds, top to bottom.
local function rows_of(list)
  local out = {}
  for i, r in ipairs(M.rows(boxes(list))) do
    out[i] = #r.ids
  end
  return out
end

-- Windows side by side span the full height and so all overlap: one row. Every
-- layout hyprecise handled before rows existed still reads as exactly that.
check("3 side-by-side windows -> 1 row", rows_of({ { 13, 39, 1120 }, { 1159, 39, 1120 }, { 2305, 39, 1122 } }), { 3 })
check("a lone window -> 1 row", rows_of({ { 13, 39, 3414 } }), { 1 })

-- The layout the row reading exists for: A across the top, B and C below it.
-- The whole workspace reads as ONE column, because A crosses the B | C
-- boundary -- so without rows there is nothing here to resize.
local TWO_ROWS = { { 13, 39, 3414, 686 }, { 13, 741, 1699, 686 }, { 1728, 741, 1699, 686 } }
check("A over B | C -> 2 rows", rows_of(TWO_ROWS), { 1, 2 })
check("the lower row holds B and C", M.rows(boxes(TWO_ROWS))[2].ids, { 2, 3 })
check("and the workspace as a whole is one column", #M.columns(boxes(TWO_ROWS)), 1)
check("while the lower row is two", #M.columns(boxes({ TWO_ROWS[2], TWO_ROWS[3] })), 2)

-- A grid is two rows of two, each with its own boundary.
local GRID = { { 13, 39, 1699, 686 }, { 1728, 39, 1699, 686 }, { 13, 741, 1699, 686 }, { 1728, 741, 1699, 686 } }
check("a grid -> 2 rows of 2", rows_of(GRID), { 2, 2 })

-- A column that spans the full height overlaps every band beside it, so there is
-- no full-width cut and the workspace is a single row -- which is what makes a
-- nested column go on being one column rather than becoming two rows.
check("a full-height column beside a stack -> 1 row", rows_of({ { 13, 39, 1699 }, { 1728, 39, 1699, 686 }, { 1728, 741, 1699, 686 } }), { 3 })

-- Three bands, which is also what a pure vertical stack is: each member is its
-- own row, and a row of one has no boundary to move.
check("three bands -> 3 rows", rows_of({ { 13, 39, 3414, 450 }, { 13, 505, 3414, 456 }, { 13, 977, 3414, 450 } }), { 1, 1, 1 })

-- Rows are found top to bottom whatever order the windows arrive in.
check("rows are ordered top to bottom", rows_of({ { 13, 741, 1699, 686 }, { 1728, 741, 1699, 686 }, { 13, 39, 3414, 686 } }), { 1, 2 })

-- The same tolerance rule as columns: the gap between two tiled rows is real,
-- and a couple of px of border overlap must not merge them.
check("touching rows do not merge", #M.rows(boxes({ { 13, 0, 3414, 720 }, { 13, 720, 3414, 720 } })), 2)
check("rows overlapping within tolerance do not merge", #M.rows(boxes({ { 13, 0, 3414, 725 }, { 13, 720, 3414, 720 } })), 2)
check("rows overlapping past tolerance do merge", #M.rows(boxes({ { 13, 0, 3414, 740 }, { 13, 720, 3414, 720 } })), 1)

-- ---------------------------------------------------------------------------
-- Column detection
-- ---------------------------------------------------------------------------

--- The widths of the columns a layout reads as, left to right.
local function widths_of(list)
  local out = {}
  for i, c in ipairs(M.columns(boxes(list))) do
    out[i] = c.w
  end
  return out
end

local flat = M.columns(boxes({ { 13, 39, 1719 }, { 1758, 39, 829 }, { 2613, 39, 814 } }))
check("3 side-by-side windows -> 3 columns", #flat, 3)
check("3 columns keep their own widths", widths_of({ { 13, 39, 1719 }, { 1758, 39, 829 }, { 2613, 39, 814 } }), { 1719, 829, 814 })
check("every plain column is its own anchor", { flat[1].anchor, flat[2].anchor, flat[3].anchor }, { 1, 2, 3 })
check("3 plain columns are anchored", M.anchored(flat), true)

-- A column holding a vertical stack is still one column.
local stacked = M.columns(boxes({ { 13, 39, 1719 }, { 13, 750, 1719 }, { 1758, 39, 1669 } }))
check("vertical stack collapses to 1 column", #stacked, 2)
check("stacked column keeps both windows", #stacked[1].ids, 2)
check("stacked column is anchored by the topmost", stacked[1].anchor, 1)
check("stacked layout is anchored", M.anchored(stacked), true)

-- The case this rule exists for. A | B | C, where C is split into D over E and
-- E is split into F | G. Nesting must not add columns: the row is A | B | C.
local NESTED = { { 13, 39, 1120 }, { 1159, 39, 1120 }, { 2305, 39, 1122 }, { 2305, 760, 548 }, { 2879, 760, 548 } }
local nested = M.columns(boxes(NESTED))
check("nested column does not split the row", #nested, 3)
check("nested row reads A | B | C", widths_of(NESTED), { 1120, 1120, 1122 })
check("nested column holds all three windows", #nested[3].ids, 3)
check("nested column is anchored by the spanning member", nested[3].anchor, 3)
check("nested layout is anchored", M.anchored(nested), true)

-- The same column with the nested half on TOP. The anchor is the member that
-- spans the column, not the topmost one -- picking the topmost here would aim
-- the resize at the F | G boundary and the column would never reach its target.
local FLIPPED = { { 13, 39, 1120 }, { 1159, 39, 1120 }, { 2305, 760, 1122 }, { 2305, 39, 548 }, { 2879, 39, 548 } }
local flipped = M.columns(boxes(FLIPPED))
check("a flipped nested column reads the same", widths_of(FLIPPED), { 1120, 1120, 1122 })
check("anchor spans the column, is not merely topmost", flipped[3].anchor, 3)

-- Deeper nesting changes nothing: the rule never looks inside a column.
local DEEP = { { 13, 39, 1120 }, { 1159, 39, 1120 }, { 2305, 39, 1122 }, { 2305, 760, 548 }, { 2879, 760, 270 }, { 3175, 760, 252 } }
check("depth is never inspected", widths_of(DEEP), { 1120, 1120, 1122 })

-- [A][B] over a full-width C: C crosses the A|B boundary, so there is no
-- boundary there and the whole lot is one column. One column is a no-op.
local straddled = M.columns(boxes({ { 13, 39, 1719 }, { 1758, 39, 1669 }, { 13, 760, 3414 } }))
check("a straddling window leaves 1 column", #straddled, 1)
check("the straddling window is the anchor", straddled[1].anchor, 3)

-- Split top and bottom first, then each half side by side at a different ratio:
-- the four windows chain-overlap into one interval that none of them spans.
local BLOB = { { 13, 39, 800 }, { 839, 39, 1200 }, { 2065, 39, 1362 }, { 839, 760, 700 }, { 1565, 760, 1862 } }
local blob = M.columns(boxes(BLOB))
check("a chain-overlap blob is one column beside X", #blob, 2)
check("the blob has no anchor", blob[2].anchor, nil)
check("a row with an anchorless column is refused", M.anchored(blob), false)

-- A single full-screen window, and a pure vertical stack, are both one column.
check("lone window -> 1 column", #M.columns(boxes({ { 13, 39, 3414 } })), 1)
check("pure vertical stack -> 1 column", #M.columns(boxes({ { 13, 39, 3414 }, { 13, 750, 3414 } })), 1)

-- Adjacent columns must not merge on the pixel or two of slack the tolerance
-- allows for borders. The real gap between two tiled windows here is 26px.
check("touching columns do not merge", #M.columns(boxes({ { 0, 39, 1720 }, { 1720, 39, 1720 } })), 2)
check("columns overlapping within tolerance do not merge", #M.columns(boxes({ { 0, 39, 1725 }, { 1720, 39, 1720 } })), 2)
check("columns overlapping past tolerance do merge", #M.columns(boxes({ { 0, 39, 1740 }, { 1720, 39, 1720 } })), 1)

-- ---------------------------------------------------------------------------
-- Chords
-- ---------------------------------------------------------------------------

local function chord_count(keys)
  local n = 0
  for _ in pairs(M.chords(keys)) do
    n = n + 1
  end
  return n
end

check("default keys bind four directions", chord_count(nil), 4)
check("default keys -> SUPER + ALT + Right", M.chords(nil).right, "SUPER + ALT + Right")
check("default keys -> SUPER + ALT + Up", M.chords(nil).up, "SUPER + ALT + Up")
check("prefix is honoured", M.chords("SUPER + CTRL").left, "SUPER + CTRL + Left")

-- A prefix written the way it reads in a binding line, with the joining "+"
-- already there, must not produce "SUPER + ALT +  + Down".
check("trailing + in prefix is dropped", M.chords("SUPER + ALT + ").down, "SUPER + ALT + Down")

local vim = { left = "SUPER + H", right = "SUPER + L", up = "SUPER + K", down = "SUPER + J" }
check("explicit map binds four", chord_count(vim), 4)
check("explicit map is taken literally", M.chords(vim).right, "SUPER + L")

-- A partial map is a request for fewer bindings, not an error.
local horizontal = { left = "SUPER + H", right = "SUPER + L" }
check("partial map binds only what it names", chord_count(horizontal), 2)
check("partial map leaves up unbound", M.chords(horizontal).up, nil)

-- Anything else binds nothing, so setup() is a no-op rather than a crash.
check("unusable keys bind nothing", chord_count(42), 0)
check("stray direction keys are ignored", chord_count({ sideways = "SUPER + S" }), 0)

-- ---------------------------------------------------------------------------
-- Applying a plan -- the half that issues dispatches
-- ---------------------------------------------------------------------------
--
-- A plan is only worth as much as the dispatches that carry it out, and those
-- are only correct in terms of how the layout engine replies. tests/dwindle.lua
-- supplies the replies; hyprecise's real `run` is driven against it, so what is
-- checked here is the shipped code path and not a copy of it.
--
-- The row a chord lands on is compared against the plan hyprecise itself made
-- for that row, never against a number typed in here: the question these ask is
-- whether hyprecise does what it decided to do.

local D = dofile(here .. "/dwindle.lua")

local function leaf(name)
  return { leaf = name }
end
local function side(a, b)
  return { h = true, ratio = 1.0, a, b }
end
local function stack(a, b)
  return { h = false, ratio = 1.0, a, b }
end

--- Press a chord on a tree and say how far the row ended from the plan.
--- @return number worst error in px, table row, table|nil plan
local function press(root, focus, direction)
  D.equalise(root)
  local plan = D.plan(M, root, focus, direction)
  local result = D.press(M, root, focus, direction)
  if not plan then
    return 0, result.after, nil
  end
  local worst = 0
  for i, want in ipairs(plan.targets) do
    worst = math.max(worst, math.abs((result.after[i] or 0) - want))
  end
  return worst, result.after, plan
end

--- True when the chord landed the row on the plan, within the tolerance
--- hyprecise itself calls "on target".
local function lands(root, focus, direction)
  local worst, _, plan = press(root, focus, direction)
  return plan ~= nil and worst <= 8
end

--- True when two snapshots agree to the pixel, on every window.
local function identical(before, after)
  for name, b in pairs(before) do
    local a = after[name]
    if not a or b.x ~= a.x or b.y ~= a.y or b.w ~= a.w or b.h ~= a.h then
      return false
    end
  end
  return true
end

--- True when the chord changed nothing at all, anywhere on the workspace --
--- which is what a refusal has to look like, the nudges it asks with included.
local function untouched(root, focus, direction)
  D.equalise(root)
  local before = D.snapshot(root)
  D.press(M, root, focus, direction)
  return identical(before, D.snapshot(root))
end

--- True when the chord left every window OUTSIDE the focused row exactly where
--- it was. A chord is about one row; the others are not its business.
local function isolated(root, focus, direction)
  D.equalise(root)
  local mine = {}
  for _, l in ipairs(D.row(M, root, focus)) do
    mine[l.leaf] = true
  end
  local before, elsewhere = D.snapshot(root), {}
  for name, g in pairs(before) do
    if not mine[name] then
      elsewhere[name] = g
    end
  end
  D.press(M, root, focus, direction)
  return identical(elsewhere, D.snapshot(root))
end

--- Both halves of what a chord owes a multi-row workspace: the focused row
--- lands on its plan, and no other row moves at all.
local function lands_in_row(root, focus, direction)
  return isolated(root, focus, direction) and lands(root, focus, direction)
end

--- The four chords from every focus position, over one tree.
local function every_chord(make, predicate)
  local n = #D.leaves((function()
    local r = make()
    D.recalc(r)
    return r
  end)())
  for focus = 1, n do
    for _, dir in ipairs({ "left", "right", "up", "down" }) do
      local root = make()
      D.equalise(root)
      if not predicate(root, D.leaves(root)[focus], dir) then
        return false, string.format("focus %d, %s", focus, dir)
      end
    end
  end
  return true
end

-- The model has to reproduce the layout engine before anything built on it
-- means a thing. A dispatch moves the first side-by-side split above the window
-- RIGHTWARD, so it widens a window on the left of that split and NARROWS one on
-- the right -- which is the fact the whole boundary reading exists for.
local A, B, C = leaf("A"), leaf("B"), leaf("C")
local nested = side(side(A, C), B) -- A and C share a split; B is the outer sibling
D.equalise(nested)
check("model: a row of three reads as three columns", #D.columns(M, nested), 3)
check("model: the left column drives its RIGHT edge", D.governs(A), "right")
check("model: the middle column drives its LEFT edge", D.governs(C), "left")
check("model: the last column drives its LEFT edge", D.governs(B), "left")

local widths_before = D.columns(M, nested)
D.resize(nested, C, 100)
local widths_after = D.columns(M, nested)
check("model: +100px on the middle column NARROWS it by 100", widths_after[2], widths_before[2] - 100)
check("model: and widens its left neighbour by 100", widths_after[1], widths_before[1] + 100)
check("model: while the row shares out the same total", widths_after[1] + widths_after[2] + widths_after[3], widths_before[1] + widths_before[2] + widths_before[3])

-- Two windows: one boundary, and it is the only thing either of them can move.
check("N=2 lands on the plan from either focus", every_chord(function()
  return side(leaf("A"), leaf("B"))
end, lands), true)

-- Three columns, both ways the layout engine can build them. The spiral is what
-- opening windows one after another gives; the other is what moving one in from
-- elsewhere gives, and it is the one where the middle column's dispatch is
-- inverted.
check("N=3 spiral lands on the plan", every_chord(function()
  return side(leaf("A"), side(leaf("B"), leaf("C")))
end, lands), true)
check("N=3 with the pair on the left lands on the plan", every_chord(function()
  return side(side(leaf("A"), leaf("B")), leaf("C"))
end, lands), true)

-- Four columns, every shape the engine can build them in.
check("N=4 spiral lands on the plan", every_chord(function()
  return side(leaf("A"), side(leaf("B"), side(leaf("C"), leaf("E"))))
end, lands), true)
check("N=4 pair nested right lands on the plan", every_chord(function()
  return side(leaf("A"), side(side(leaf("B"), leaf("C")), leaf("E")))
end, lands), true)
check("N=4 pair nested left lands on the plan", every_chord(function()
  return side(side(leaf("A"), side(leaf("B"), leaf("C"))), leaf("E"))
end, lands), true)
check("N=4 leaning fully left lands on the plan", every_chord(function()
  return side(side(side(leaf("A"), leaf("B")), leaf("C")), leaf("E"))
end, lands), true)

-- Nesting inside a column changes nothing: the column is resized, not its
-- contents, and it reaches its target from every window inside it.
check("a column holding a stack lands on the plan", every_chord(function()
  return side(leaf("A"), side(stack(leaf("B"), leaf("C")), leaf("E")))
end, lands), true)
check("a column holding a tree lands on the plan", every_chord(function()
  return side(side(leaf("A"), stack(leaf("B"), side(leaf("C"), leaf("E")))), leaf("F"))
end, lands), true)

-- A boundary whose split has a side-by-side split on BOTH sides is nobody's
-- nearest one, so no dispatch can move it and the row cannot be arranged as
-- planned. Refusing is the only honest answer, and it has to leave no trace.
check("a boundary no window can move is refused", every_chord(function()
  return side(side(leaf("A"), leaf("B")), side(leaf("C"), leaf("E")))
end, untouched), true)

-- ---------------------------------------------------------------------------
-- Rows -- a chord is about the focused window's row and no other
-- ---------------------------------------------------------------------------

--- The four chords over one tree, from every window whose name `only` names --
--- or from every window, when it names none.
local function from(make, predicate, only)
  return every_chord(make, function(root, focus, dir)
    if only and not only[focus.leaf] then
      return true
    end
    return predicate(root, focus, dir)
  end)
end

-- The layout the row reading exists for. A across the top, B | C below: the
-- workspace reads as one column, because A crosses the B | C boundary, so every
-- chord from every window was a silent no-op. Now B and C are a row of two.
local function OVER_PAIR()
  return stack(leaf("A"), side(leaf("B"), leaf("C")))
end
check("A over B | C: the lower row lands on its plan", from(OVER_PAIR, lands_in_row, { B = true, C = true }), true)

-- A is a row of one. It has no neighbour to share a boundary with, and heights
-- are out of scope, so there is nothing a chord from it could do.
check("A over B | C: the full-width row is a no-op", from(OVER_PAIR, untouched, { A = true }), true)

-- Depth inside a row changes nothing: the row is read as columns exactly as a
-- whole workspace was.
check("a row of three below a full-width window lands on the plan", from(function()
  return stack(leaf("A"), side(leaf("B"), side(leaf("C"), leaf("E"))))
end, lands_in_row, { B = true, C = true, E = true }), true)

-- Two side-by-side splits stacked one above the other are two rows, each with
-- its own boundary to move. Read as a single row of columns -- which is also
-- exactly what a grid looks like -- they came apart the moment either half
-- moved, so hyprecise refused the layout outright and every chord on a grid was
-- dead. Each row now resizes on its own, and the other one does not stir.
check("a grid resizes one row at a time", every_chord(function()
  return stack(side(leaf("A"), leaf("B")), side(leaf("C"), leaf("E")))
end, lands_in_row), true)

-- Three rows, and the third is nested one level deeper than the first two: how
-- the bands were arrived at is no more inspected than the inside of a column.
check("three rows resize independently", every_chord(function()
  return stack(side(leaf("A"), leaf("B")), stack(side(leaf("C"), leaf("E")), side(leaf("F"), leaf("G"))))
end, lands_in_row), true)

-- A row whose columns are of different depths, under a row of two: the row
-- reading has to come first, or the workspace reads as one column again.
check("rows of different shapes do not disturb each other", every_chord(function()
  return stack(side(leaf("A"), leaf("B")), side(stack(leaf("C"), leaf("E")), leaf("F")))
end, lands_in_row), true)

-- A pure vertical stack is a row per window, and a row of one is a no-op --
-- which is what a full-width stack was before rows too, by way of reading as a
-- single column.
check("a vertical stack is still a no-op", every_chord(function()
  return stack(leaf("A"), stack(leaf("B"), leaf("C")))
end, untouched), true)

-- Whatever a chord does, it never leaves a column narrower than the layout could
-- have been asked for. This is the failure the boundary reading exists to
-- prevent: a dispatch applied with the wrong sign collapses a column to a few
-- dozen pixels and then oscillates until the passes run out.
local no_collapse = true
for _, make in ipairs({
  function() return side(side(leaf("A"), leaf("B")), leaf("C")) end,
  function() return side(side(leaf("A"), side(leaf("B"), leaf("C"))), leaf("E")) end,
  function() return side(side(side(leaf("A"), leaf("B")), leaf("C")), leaf("E")) end,
  function() return side(leaf("A"), side(side(leaf("B"), leaf("C")), leaf("E"))) end,
}) do
  local ok = every_chord(make, function(root, focus, dir)
    local _, row = press(root, focus, dir)
    for _, w in ipairs(row) do
      if w < 200 then
        return false
      end
    end
    return true
  end)
  no_collapse = no_collapse and ok
end
check("no chord collapses a column", no_collapse, true)

-- A row already far from any stop still lands on one; the ladder is absolute,
-- not relative to where the row happened to be.
local lopsided = side(side(leaf("A"), leaf("B")), leaf("C"))
D.recalc(lopsided)
lopsided.ratio, lopsided[1].ratio = 1.7, 0.4
D.recalc(lopsided)
local worst = select(1, (function()
  local plan = D.plan(M, lopsided, D.leaves(lopsided)[1], "right")
  local result = D.press(M, lopsided, D.leaves(lopsided)[1], "right")
  local w = 0
  for i, want in ipairs(plan.targets) do
    w = math.max(w, math.abs((result.after[i] or 0) - want))
  end
  return w
end)())
check("a lopsided row still lands on the plan", worst <= 8, true)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)

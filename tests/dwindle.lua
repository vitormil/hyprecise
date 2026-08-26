-- A model of Hyprland's dwindle layout, enough of one to answer a resize.
--
-- Half of hyprecise is only correct in terms of how the layout engine replies to
-- a dispatch, so the spec cannot exercise that half against assumptions about
-- the reply. It exercises it against this instead: the split arithmetic of
-- Hyprland 0.56.2, transcribed from
-- src/layout/algorithm/tiled/dwindle/DwindleAlgorithm.cpp -- `resizeTarget` with
-- `dwindle:smart_resizing` on, which is the default, and
-- `recalcSizePosRecursive` -- and calibrated against live geometry on a 3440x1440
-- monitor with gaps_out 10, gaps_in 5 and border 3.
--
-- The one fact the whole thing exists to reproduce: a dispatch takes the first
-- SIDE-BY-SIDE split above the window and moves it rightward by the delta. It
-- does not care which side of that split the window is on, so it widens a window
-- on the left of it and narrows one on the right.
--
-- A tree is built from two kinds of table:
--     { h = true,  ratio = 1.0, <child>, <child> }   side by side
--     { h = false, ratio = 1.0, <child>, <child> }   top over bottom
--     { leaf = "A" }                                 a window
--
-- Nothing here is loaded at runtime; hyprecise never sees it.

local D = {}

local WA = { x = 0, y = 26, w = 3440, h = 1414 } -- work area: a bar along the top
local GAPS_OUT, GAPS_IN, BORDER = 10, 5, 3

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function recalc(node, box, parent)
  node.box, node.parent = box, parent
  if node.leaf then
    return
  end
  if node.h then
    local first = clamp(box.w / 2 * node.ratio, 0, box.w)
    recalc(node[1], { x = box.x, y = box.y, w = first, h = box.h }, node)
    recalc(node[2], { x = box.x + first, y = box.y, w = box.w - first, h = box.h }, node)
  else
    local first = clamp(box.h / 2 * node.ratio, 0, box.h)
    recalc(node[1], { x = box.x, y = box.y, w = box.w, h = first }, node)
    recalc(node[2], { x = box.x, y = box.y + first, w = box.w, h = box.h - first }, node)
  end
end

--- Lay the tree out over the work area.
function D.recalc(root)
  recalc(root, { x = WA.x, y = WA.y, w = WA.w, h = WA.h }, nil)
end

--- Window geometry as Hyprland reports it: the node box less the gap on each
--- side -- outer against a work-area edge, inner between windows -- and the
--- border.
function D.geom(leaf)
  local b = leaf.box
  local function gap(v, edge)
    return math.abs(v - edge) < 1 and GAPS_OUT or GAPS_IN
  end
  local x = math.floor(b.x + gap(b.x, WA.x) + BORDER + 0.5)
  local y = math.floor(b.y + gap(b.y, WA.y) + BORDER + 0.5)
  return {
    x = x,
    y = y,
    -- noNegativeSize(): a box squeezed past nothing reports nothing, not less
    w = math.max(0, math.floor(b.x + b.w - gap(b.x + b.w, WA.x + WA.w) - BORDER + 0.5) - x),
    h = math.max(0, math.floor(b.y + b.h - gap(b.y + b.h, WA.y + WA.h) - BORDER + 0.5) - y),
  }
end

--- Every window, left to right and then top to bottom.
function D.leaves(root)
  local out = {}
  local function walk(n)
    if n.leaf then
      out[#out + 1] = n
      return
    end
    walk(n[1])
    walk(n[2])
  end
  walk(root)
  table.sort(out, function(a, b)
    if a.box.x ~= b.box.x then
      return a.box.x < b.box.x
    end
    return a.box.y < b.box.y
  end)
  return out
end

--- `resizewindowpixel <dx> 0` on one window: add `dx * 2 / box.w` to the ratio
--- of the first side-by-side split above it. Raising a ratio grows children[0],
--- the LEFT child, so the split's boundary goes rightward by dx either way.
function D.resize(root, leaf, dx)
  local g = D.geom(leaf)
  if math.abs(g.x - WA.x) < 5 and math.abs(g.x + g.w - (WA.x + WA.w)) < 5 then
    return -- DISPLAYLEFT and DISPLAYRIGHT together zero the movement
  end
  local cur = leaf
  while cur.parent do
    if cur.parent.h then
      local p = cur.parent
      p.ratio = clamp(p.ratio + dx * 2.0 / p.box.w, 0.1, 1.9)
      D.recalc(root)
      return
    end
    cur = cur.parent
  end
end

--- Which boundary a dispatch on this window moves: "right" when it sits on the
--- left of its governing split, "left" when it sits on the right, nil when it
--- has no side-by-side ancestor at all. The spec uses this to say what a tree IS;
--- hyprecise has to find it out by asking.
function D.governs(leaf)
  local cur = leaf
  while cur.parent do
    if cur.parent.h then
      return cur.parent[1] == cur and "right" or "left"
    end
    cur = cur.parent
  end
  return nil
end

--- Set every side-by-side ratio so the windows get equal x-intervals: roughly
--- the state hyprecise's own equalise chord leaves a row in, and a fair starting
--- point for a chord that is about to move away from it.
function D.equalise(root)
  local function count(n)
    if n.leaf then
      return 1
    end
    if not n.h then
      return math.max(count(n[1]), count(n[2]))
    end
    return count(n[1]) + count(n[2])
  end
  local function fix(n)
    if n.leaf then
      return
    end
    if n.h then
      local l = count(n[1])
      n.ratio = 2.0 * l / (l + count(n[2]))
    end
    fix(n[1])
    fix(n[2])
  end
  fix(root)
  D.recalc(root)
end

-- --------------------------------------------------------------------------
-- Driving the real hyprecise against it
-- --------------------------------------------------------------------------

--- A window handle shaped like HL.Window. `at` and `size` read through to the
--- current box rather than copying it, because Hyprland's do: a dispatch is
--- visible in the handles you already hold, which is the whole reason hyprecise
--- can re-read geometry as it goes.
local function handle(leaf, monitor)
  return {
    leaf = leaf,
    address = leaf.leaf,
    mapped = true,
    hidden = false,
    floating = false,
    fullscreen = 0,
    monitor = monitor,
    workspace = { id = 1 },
    at = setmetatable({}, {
      __index = function(_, k)
        return D.geom(leaf)[k]
      end,
    }),
    size = setmetatable({}, {
      __index = function(_, k)
        local g = D.geom(leaf)
        return k == "x" and g.w or (k == "y" and g.h or nil)
      end,
    }),
  }
end

--- Run hyprecise's real `run` against `root`, with `focus` the focused window.
--- Installs a global `hl` for the duration and takes it away again, so nothing
--- outside this call can mistake the model for a compositor.
--- @return table { before, after, dispatches } -- column widths either side
function D.press(M, root, focus, direction, opts)
  D.recalc(root)
  local monitor = {
    id = 0,
    width = WA.w,
    height = 1440,
    scale = 1,
    transform = 0,
    reserved = { left = 0, right = 0, top = WA.y, bottom = 0 },
  }
  local leaves = D.leaves(root)
  local handles, by_leaf = {}, {}
  for i, l in ipairs(leaves) do
    handles[i] = handle(l, monitor)
    by_leaf[l] = handles[i]
  end

  local dispatches = 0
  local saved = _G.hl
  _G.hl = {
    get_active_window = function()
      return by_leaf[focus]
    end,
    get_workspace_windows = function()
      return handles
    end,
    dispatch = function(fn)
      if fn then
        fn()
      end
    end,
    dsp = {
      window = {
        resize = function(o)
          return function()
            for _, h in ipairs(handles) do
              if h.address == o.window:gsub("^address:", "") then
                dispatches = dispatches + 1
                D.resize(root, h.leaf, o.x)
                return
              end
            end
          end
        end,
      },
    },
    notification = { create = function() end },
  }

  local before = D.columns(M, root)
  local ok, err = pcall(M.run, direction, opts)
  _G.hl = saved
  if not ok then
    error(err, 0)
  end
  return { before = before, after = D.columns(M, root), dispatches = dispatches }
end

--- The row as hyprecise reads it: the widths of its columns, left to right.
function D.columns(M, root)
  local boxes = {}
  for i, l in ipairs(D.leaves(root)) do
    local g = D.geom(l)
    boxes[i] = { x = g.x, y = g.y, w = g.w, id = i }
  end
  local out = {}
  for i, c in ipairs(M.columns(boxes, 8)) do
    out[i] = c.w
  end
  return out
end

--- What hyprecise's planner wants for this row, so the spec can check the result
--- against hyprecise's own intention rather than against a hand-copied number.
function D.plan(M, root, focus, direction, opts)
  D.recalc(root)
  local leaves = D.leaves(root)
  local boxes = {}
  for i, l in ipairs(leaves) do
    local g = D.geom(l)
    boxes[i] = { x = g.x, y = g.y, w = g.w, id = i }
  end
  local cols = M.columns(boxes, 8)
  if #cols < 2 or not M.anchored(cols) then
    return nil
  end
  local widths, focused = {}, nil
  for i, c in ipairs(cols) do
    widths[i] = c.w
    for _, id in ipairs(c.ids) do
      if leaves[id] == focus then
        focused = i
      end
    end
  end
  if not focused then
    return nil
  end
  return M.plan({
    widths = widths,
    focused = focused,
    direction = direction,
    available_width = WA.w,
    opts = opts,
  })
end

D.WA = WA
return D

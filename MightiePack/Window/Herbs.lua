-- MightiePack — the Herbs tab (card t_a5de2f16, review layout item 1).
--
-- The owner's answer to "this tab looks sparse" was two columns, not a smaller
-- frame: the herbs on the left, the selected herb's own drop table and personal
-- count on the right. The frame is still 960x640 for every tab.
--
-- This is the BROWSE/HISTORY surface. The hover panel (NodeTrailHerbPanel) is
-- still the in-the-moment farming surface and is untouched by this file: it
-- pops when a herb is moused, exactly as before, and nothing here merges the
-- two or improves one into the other.
--
-- Everything drawn here is read from the same sources the tooltip reads:
--   * the herb list and counts — HerbData.NODES + NodeTrailDB.herbs.stats
--     .gathers (the lifetime aggregate the recorder maintains);
--   * the detail rows — Tooltip.BuildLines(name), the tooltip's own builder,
--     rendered through TooltipPanel's row helper (Window/Common.lua).
-- So the tab cannot claim a number the tooltip would not.

local _, pkg = ...

local W = pkg.Window
local C = W and W.UI
local L = {}
if type(W) == "table" then W.Herbs = L end

local MAX_ROWS = 400

local function call(obj, name, ...)
  local f = type(obj) == "table" and obj[name]
  if type(f) ~= "function" then return false end
  local ok, r = pcall(f, obj, ...)
  if not ok then return false end
  return true, r
end

local function ns()
  return type(pkg.NodeTrail) == "table" and pkg.NodeTrail or nil
end

--- The herb DB, read WITHOUT creating it: opening a tab must not write a fresh
--- NodeTrailDB into a character that has never gathered.
local function herbDB()
  local n = ns()
  if type(n) ~= "table" then return nil end
  local db = rawget(_G, "NodeTrailDB")
  if type(db) ~= "table" or type(db.herbs) ~= "table" then return nil end
  return db.herbs
end

--- One entry per herb we know about, richest first. A herb with no personal
--- history is still listed: the drop table is researched data and is worth
--- reading before you have ever picked one.
function L.Entries()
  local n = ns()
  local H = n and n.HerbData
  if type(H) ~= "table" or type(H.NODES) ~= "table" then return {} end
  local herbs = herbDB()
  local gathers = type(herbs) == "table" and type(herbs.stats) == "table"
    and type(herbs.stats.gathers) == "table" and herbs.stats.gathers or {}
  local out = {}
  for name, node in pairs(H.NODES) do
    if type(name) == "string" then
      local item = type(node) == "table" and node.item or nil
      local count = type(item) == "number" and tonumber(gathers[item]) or nil
      out[#out + 1] = { id = name, text = name, count = count or 0 }
    end
  end
  table.sort(out, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.text < b.text
  end)
  if #out > MAX_ROWS then
    local cut = {}
    for i = 1, MAX_ROWS do cut[i] = out[i] end
    out = cut
  end
  return out
end

--- The right-hand column for one herb: the tooltip's own lines.
--- Returns title, sub, lines.
function L.Detail(name)
  local n = ns()
  local H = n and n.HerbData
  if type(H) ~= "table" or type(name) ~= "string" then
    return "", "", {}
  end
  local herbs = herbDB()
  local node = type(H.GetNode) == "function" and H.GetNode(name) or nil
  local count = nil
  if type(node) == "table" and type(node.item) == "number" and type(herbs) == "table"
    and type(herbs.stats) == "table" and type(herbs.stats.gathers) == "table" then
    count = tonumber(herbs.stats.gathers[node.item])
  end
  local sub = (count and count > 0)
    and ("gathered " .. tostring(count) .. " time" .. (count == 1 and "" or "s") .. " on this account")
    or "no personal gathers yet — the table below is researched data"
  local T = n and n.Tooltip
  local lines, reason
  if type(T) == "table" and type(T.BuildLines) == "function" then
    local ok, l, why = pcall(T.BuildLines, name)
    if ok then lines, reason = l, why end
  end
  if type(lines) ~= "table" then
    return name, sub .. (type(reason) == "string" and ("  ·  " .. reason) or ""), {}
  end
  return name, sub, lines
end

local function ensure(host)
  if type(L.list) == "table" and type(L.detail) == "table" then
    return L.list, L.detail
  end
  if type(C) ~= "table" or type(host) ~= "table" then return nil end
  local height = 500
  local okH, h = call(host, "GetHeight")
  if okH and type(h) == "number" and h > 120 then height = h end
  L.list = C.List(host, {
    title = "Herbs", x = 0, width = 300, height = height,
    onPick = function(name) L.Show(name) end,
  })
  L.detail = C.Detail(host, { title = "Detail", x = 308, width = 636, height = height })
  return L.list, L.detail
end

--- Show one herb's detail. Called by the list's pick handler and by Render.
function L.Show(name)
  local _, detail = ensure(W.hosts and W.hosts.herbs)
  if type(detail) ~= "table" then return false end
  if type(name) ~= "string" then name = L.selected end
  if type(name) ~= "string" then return false end
  L.selected = name
  local title, sub, lines = L.Detail(name)
  detail.SetLines(title, sub, lines)
  return true
end

--- The tab's renderer. Runs on every activation, so the list is current after
--- a gather without a reload.
function L.Render()
  local host = W.hosts and W.hosts.herbs
  if type(host) ~= "table" then return false end
  local n = ns()
  if type(n) ~= "table" or not n.enabled then
    local list, detail = ensure(host)
    if type(list) == "table" then list.SetEntries({}) end
    if type(detail) == "table" then
      detail.SetLines("Herbs", W.MODULE_OFF_TEXT.herbs, {})
    end
    return false
  end
  local list, detail = ensure(host)
  if type(list) ~= "table" or type(detail) ~= "table" then return false end
  local entries = L.Entries()
  list.SetEntries(entries)
  local pick = L.selected
  if type(pick) ~= "string" then
    pick = entries[1] and entries[1].id or nil
  end
  L.Show(pick)
  return true
end

if type(W) == "table" and type(W.OnSelect) == "function" then
  W.OnSelect("herbs", L.Render)
end

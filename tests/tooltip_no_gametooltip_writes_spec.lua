-- t_f4ff9ea6 — the grep gate: the addon no longer writes into GameTooltip.
--
-- The herb block used to be appended to Blizzard's tooltip and then propped up
-- (frame widen, measured re-size, line wrap). All three lost to the client's own
-- layout, so the append path was removed outright rather than fixed again. This
-- spec is the gate that keeps it removed: it walks the addon tree and fails on
-- the first write, hook or method replacement aimed at the tooltip.
--
-- What it asserts, in order:
--   A. no field assignment on GameTooltip anywhere in the addon;
--   B. exactly ONE `GameTooltip:HookScript` may exist in the whole tree, and it
--      must be Touchstone's read-only item post-call fallback — any new one,
--      anywhere, fails this spec by name;
--   C. ZERO of them (and zero AddLine/AddDoubleLine/SetWidth/SetHeight/SetText/
--      Show/SetOwner/Clear/ClearLines) in Modules/NodeTrail — the tooltip path
--      this card owns;
--   D. the two tooltip files never CALL :HookScript( (their comments saying
--      "no HookScript" are the documentation of that rule, not a violation);
--   E. the two tooltip files call neither C_EventUtils nor
--      COMBAT_LOG_EVENT_UNFILTERED (the card's other constraints).
--
-- Not loaded by the addon TOC.
local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. msg .. "\n")
  end
end

local ADDON = root .. "/MightiePack"
local NODETRAIL = ADDON .. "/Modules/NodeTrail"

local function filesUnder(dir)
  local out = {}
  local ok, pipe = pcall(io.popen, "find '" .. dir .. "' -type f -name '*.lua' 2>/dev/null")
  if not ok or not pipe then
    return out
  end
  for path in pipe:lines() do
    out[#out + 1] = path
  end
  pipe:close()
  table.sort(out)
  return out
end

local function readLines(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local text = f:read("*a")
  f:close()
  return text
end

-- Every line of every file, with the file's short name attached.
local function scan(dir)
  local hits = {}
  for _, path in ipairs(filesUnder(dir)) do
    local text = readLines(path)
    if text then
      local lineNo = 0
      for line in (text .. "\n"):gmatch("(.-)\n") do
        lineNo = lineNo + 1
        hits[#hits + 1] = { path = path, line = lineNo, text = line }
      end
    end
  end
  return hits
end

local function grep(hits, pattern)
  local out = {}
  for _, h in ipairs(hits) do
    if h.text:find(pattern) then
      out[#out + 1] = h
    end
  end
  return out
end

local function describe(list, max)
  local parts = {}
  for i, h in ipairs(list) do
    if max and i > max then
      parts[#parts + 1] = ("…+%d more"):format(#list - max)
      break
    end
    parts[#parts + 1] = ("%s:%d"):format(h.path:gsub("^" .. root:gsub("%p", "%%%0") .. "/", ""), h.line)
  end
  return table.concat(parts, ", ")
end

local addonHits = scan(ADDON)
check(#addonHits > 0, "the addon tree was walked (found .lua files under MightiePack)")

-- ── A. no field assignment on GameTooltip, anywhere in the addon ─────────
-- `GameTooltip.SetText == nil` is a comparison, not a write; `[^=]` keeps the
-- match to a single `=`. A field write is `GameTooltip.something = ...`.
local fieldWrites = {}
for _, h in ipairs(addonHits) do
  local rest = h.text:gsub("GameTooltip%.[%a_]+%s*=[^=].*$", "WRITE")
  if rest ~= h.text then
    fieldWrites[#fieldWrites + 1] = h
  end
end
check(#fieldWrites == 0,
  "A: no field is assigned on GameTooltip (found " .. describe(fieldWrites) .. ")")

-- ── B. exactly one GameTooltip:HookScript in the tree — the known fallback ─
local hooks = grep(addonHits, "GameTooltip:HookScript")
check(#hooks == 1,
  ("B: exactly one GameTooltip:HookScript remains (Touchstone's read-only item fallback), got %d: %s")
    :format(#hooks, describe(hooks)))
if #hooks == 1 then
  check(hooks[1].path:find("Modules/Touchstone/ChestAdvisor/ChestAdvisor.lua", 1, true) ~= nil,
    "B: the single remaining hook is Touchstone's read-only item post-call fallback (got "
      .. hooks[1].path .. ")")
  check(hooks[1].text:find("OnTooltipSetItem", 1, true) ~= nil,
    "B: it is the OnTooltipSetItem fallback, not a content write")
end

-- ── C. NodeTrail writes nothing into the tooltip ─────────────────────────
local WRITES = {
  "GameTooltip:HookScript",
  "GameTooltip:AddLine",
  "GameTooltip:AddDoubleLine",
  "GameTooltip:SetWidth",
  "GameTooltip:SetHeight",
  "GameTooltip:SetText",
  "GameTooltip:SetOwner",
  "GameTooltip:Show",
  "GameTooltip:ClearLines",
  "GameTooltip:Clear",
  "GameTooltip:SetScale",
  "GameTooltip:SetBackdrop",
  "GameTooltip:SetPoint",
}
local ntHits = scan(NODETRAIL)
check(#ntHits > 0, "C: the NodeTrail tree was walked")
for _, pattern in ipairs(WRITES) do
  local found = grep(ntHits, pattern:gsub("%-", "%%-"))
  check(#found == 0,
    ("C: no `%s` in Modules/NodeTrail (found %s)"):format(pattern, describe(found)))
end

-- ── D. the tooltip files do not mention HookScript at all ────────────────
for _, rel in ipairs({ "Modules/NodeTrail/UI/Tooltip.lua",
  "Modules/NodeTrail/UI/TooltipPanel.lua" }) do
  local path = ADDON .. "/" .. rel
  local text = readLines(path)
  check(text ~= nil, "D: " .. rel .. " exists")
  if text then
    -- The CALL, not the word: both files say "no HookScript" in their comments
    -- on purpose, and a comment cannot hook anything.
    check(text:find(":HookScript%s*%(") == nil,
      "D: " .. rel .. " never calls :HookScript(")
  end
end

-- ── E. the card's other forbidden calls, in the tooltip path ─────────────
for _, rel in ipairs({ "Modules/NodeTrail/UI/Tooltip.lua",
  "Modules/NodeTrail/UI/TooltipPanel.lua" }) do
  local text = readLines(ADDON .. "/" .. rel) or ""
  check(text:find("C_EventUtils", 1, true) == nil,
    "E: " .. rel .. " never calls C_EventUtils")
  check(text:find("COMBAT_LOG_EVENT_UNFILTERED", 1, true) == nil,
    "E: " .. rel .. " never registers COMBAT_LOG_EVENT_UNFILTERED")
end

-- ── F. the panel module still exposes the surface the poller and diag use ─
local panelPath = ADDON .. "/Modules/NodeTrail/UI/TooltipPanel.lua"
local panelSrc = readLines(panelPath) or ""
for _, fnName in ipairs({ "function P:Update", "function P:Hide", "function P:Diag",
  "function P:TextLines", "function P:Wrap", "function P:TooltipRect" }) do
  check(panelSrc:find(fnName, 1, true) ~= nil,
    "F: UI/TooltipPanel.lua defines " .. fnName)
end

if failed > 0 then
  io.stderr:write(failed .. " no-GameTooltip-write check(s) failed\n")
  os.exit(1)
end
print(("tooltip_no_gametooltip_writes_spec: ok (%d file(s) scanned, %d known touchstone hook)"
  ):format(#filesUnder(ADDON), #hooks))

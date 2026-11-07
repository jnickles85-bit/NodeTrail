if MightiePackTouchstoneSkip then return end
--- StatForge diagnostics: client/flavor detection, an API capability probe,
--- and a copyable report for manual testing.
---
--- Why this exists: the manual release matrix is blocked on checks that need a
--- live client and a human tester. This module answers "what does this client
--- actually expose?" so a failing check reports a number instead of a guess.
---
--- Card t_adf556d6 RETIRED the export half, and with it this module's capture
--- half. The SNAPSHOT line and the COUNT line described a snapshot the addon no
--- longer builds (Snapshot.lua is deleted), so they are gone: a diagnostics tool
--- that reports on a capture that cannot happen would lie. What remains is every
--- fact that is about the CLIENT -- CLIENT, PROJECT, PROBE, FLAVOR -- which is
--- exactly what the advisor needs when a verdict goes wrong on someone's machine.
---
--- Every symbol is probed independently and the sweep never aborts on the
--- first absent or throwing API, because the interesting client is always the
--- one where something is missing.

StatForge = StatForge or {}
local SF = StatForge

local VALUE_MAX = 60

--- Collapse to one greppable line and bound the length.
local function oneLine(value)
  local s = tostring(value)
  s = s:gsub("%s+", " ")
  if #s > VALUE_MAX then
    s = s:sub(1, VALUE_MAX - 3) .. "..."
  end
  return s
end

local function resolveGlobal(name)
  local head, tail = name:match("^([%w_]+)%.([%w_]+)$")
  if head then
    local tbl = _G[head]
    if type(tbl) ~= "table" then return nil end
    return tbl[tail]
  end
  return _G[name]
end

-- ---------------------------------------------------------------------------
-- Capability probe
-- ---------------------------------------------------------------------------
--- Ordered probe list. The order is the report order: containers, items,
--- talents, then the character sheet.
local PROBES = {
  -- bags / containers
  { "C_Container.GetContainerNumSlots", { 0 } },
  { "C_Container.GetContainerItemLink", { 0, 1 } },
  { "GetContainerNumSlots", { 0 } },
  { "GetContainerItemLink", { 0, 1 } },
  -- items
  { "GetInventoryItemLink", { 1 } },
  { "GetItemInfo", { "itemId" } },
  { "C_Item.GetItemInfo", { "itemId" } },
  -- talents / specialization
  { "GetNumTalentTabs", {} },
  { "GetNumTalents", { 1 } },
  { "GetTalentInfo", { 1, 1 } },
  { "GetTalentLink", { 1, 1 } },
  { "GetSpecialization", {} },
  { "C_SpecializationInfo.GetSpecialization", {} },
  -- character sheet
  { "GetCritChance", {} },
  { "GetRangedCritChance", {} },
  { "GetSpellCritChance", { 2 } },
  { "GetSpellBonusDamage", { 2 } },
  { "GetSpellBonusHealing", {} },
  { "GetDodgeChance", {} },
  { "GetParryChance", {} },
  { "GetBlockChance", {} },
  { "UnitDefenseSkill", { "player" } },
  { "UnitAttackPower", { "player" } },
  { "UnitRangedAttackPower", { "player" } },
  { "UnitArmor", { "player" } },
  { "UnitHealth", { "player" } },
  { "UnitMana", { "player" } },
}

--- "itemId" is a placeholder so probes can be described before the caller knows
--- which item to ask about; it resolves to a real id when one is available,
--- because GetItemInfo(1) answers nil on a healthy client and that is useless.
local function probeArgs(args, itemId)
  if not args then return nil end
  local out = {}
  for i, a in ipairs(args) do
    out[i] = (a == "itemId") and itemId or a
  end
  return out
end

--- pcall prefixes a failed error() with "file:line: ". That location points at
--- the *probed* API's stub, not at anything the tester can act on, so keep the
--- message and drop the noise.
local function stripLocation(message)
  local s = tostring(message)
  return (s:gsub("^[%w%._%-/\\]*%.lua:%d+: ", ""))
end

local function formatResult(ok, first)
  if not ok then
    return "err(" .. oneLine(stripLocation(first)) .. ")"
  end
  if first == nil then
    return "nil"
  end
  local t = type(first)
  if t == "number" or t == "string" or t == "boolean" then
    return "ok(" .. oneLine(first) .. ")"
  end
  return "ok(<" .. t .. ">)"
end

--- Probe every listed symbol. Returns (probes, values) where probes is the
--- ordered descriptor list and values maps symbol name -> return value (nil
--- when absent). Never throws. opts.itemId (optional) is the item id used for
--- the GetItemInfo probes.
function SF.ProbeApiTable(opts)
  opts = opts or {}
  local itemId = tonumber(opts.itemId) or 1
  local values = {}
  for _, probe in ipairs(PROBES) do
    local fn = resolveGlobal(probe[1])
    values[probe[1]] = fn
  end
  return PROBES, values, itemId
end

--- One report line per probe, always including the ABSENT ones.
function SF.ProbeReportLines(opts)
  local probes, values, itemId = SF.ProbeApiTable(opts)
  local lines = {}
  for _, probe in ipairs(probes) do
    local name = probe[1]
    local fn = values[name]
    local status
    if fn == nil then
      status = "ABSENT"
    else
      -- Probe arguments are passed explicitly rather than via unpack()/
      -- table.unpack(): this module ships to a client whose Lua version we are
      -- explicitly not assuming. Every entry in PROBES has 0, 1, or 2 args.
      local args = probeArgs(probe[2], itemId) or {}
      local callOk, callResult
      if #args == 0 then
        callOk, callResult = pcall(fn)
      elseif #args == 1 then
        callOk, callResult = pcall(fn, args[1])
      else
        callOk, callResult = pcall(fn, args[1], args[2])
      end
      -- The "PRESENT" marker is part of the report contract: absence and a
      -- failing call are different bugs, so the line must distinguish them.
      status = "PRESENT " .. formatResult(callOk, callResult)
    end
    lines[#lines + 1] = "PROBE " .. name .. " = " .. status
  end
  return lines, values
end

-- ---------------------------------------------------------------------------
-- Client and flavor
-- ---------------------------------------------------------------------------
--- Does the client's interface number match ANY value the TOC declares?
--- The TOC's `## Interface:` line is a SET (Constants.lua: SF.TOC_INTERFACE_TARGETS),
--- not one number. The single-value compare this replaces was audit B7 (card
--- t_4412b04b): the owner's `_classic_beta_` client reports 16001, which the TOC
--- declares, yet the report printed a false `tocMatch=false` on every `/sf diag`.
--- Returns true/false, or nil when the client's number is unusable (the caller then
--- reports `unknown` — nil MUST NOT be collapsed into false).
local function interfaceMatchesDeclared(toc)
  local client = tostring(tonumber(toc) or "")
  if client == "" then return nil end
  for _, target in ipairs(SF.TOC_INTERFACE_TARGETS or {}) do
    if tostring(tonumber(target) or "") == client then return true end
  end
  return false
end

--- Client build info plus the addon's own interface targets, so a TOC/interface
--- mismatch is visible instead of showing up as "the addon did nothing".
function SF.ClientReportLine()
  local target = tostring(SF.TOC_INTERFACE or "?")
  if type(GetBuildInfo) ~= "function" then
    return 'CLIENT GetBuildInfo=ABSENT addonToc="' .. target .. '" tocMatch=unknown'
  end
  local ok, version, build, date, toc = pcall(GetBuildInfo)
  if not ok then
    return "CLIENT GetBuildInfo=err(" .. oneLine(version) ..
      ') addonToc="' .. target .. '" tocMatch=unknown'
  end
  local match = interfaceMatchesDeclared(toc)
  if match == nil then
    match = "unknown"
  else
    match = match and "true" or "false"
  end
  return ('CLIENT version="%s" build="%s" date="%s" toc="%s" addonToc="%s" tocMatch=%s')
    :format(
      oneLine(version or "?"), oneLine(build or "?"), oneLine(date or "?"),
      oneLine(toc or "?"), target, match)
end

local PROJECT_CONSTANTS = {
  "WOW_PROJECT_ID",
  "WOW_PROJECT_MAINLINE",
  "WOW_PROJECT_CLASSIC",
  "WOW_PROJECT_BURNING_CRUSADE_CLASSIC",
  "WOW_PROJECT_WRATH_CLASSIC",
  "WOW_PROJECT_CATACLYSM_CLASSIC",
  "WOW_PROJECT_MISTS_CLASSIC",
}

function SF.ProjectReportLines()
  local lines = {}
  for _, name in ipairs(PROJECT_CONSTANTS) do
    local value = _G[name]
    lines[#lines + 1] = "PROJECT " .. name .. " = " ..
      (value ~= nil and tostring(value) or "ABSENT")
  end
  return lines
end

--- Infer the client flavor from API *presence* (never from a hardcoded
--- expansion id). Returns (verdict, tags).
function SF.InferFlavor(values)
  values = values or {}
  local function present(name) return values[name] ~= nil end

  local tags = {}
  local classicTalents = present("GetNumTalentTabs") and present("GetNumTalents")
    and present("GetTalentInfo")
  local retailSpecs = present("GetSpecialization")
    or present("C_SpecializationInfo.GetSpecialization")
  if classicTalents then tags[#tags + 1] = "classic-talent-trees" end
  if retailSpecs then tags[#tags + 1] = "retail-specialization" end
  if present("C_Container.GetContainerNumSlots") then tags[#tags + 1] = "C_Container-bag-api" end
  if present("GetContainerNumSlots") then tags[#tags + 1] = "legacy-container-globals" end
  if present("C_Item.GetItemInfo") then tags[#tags + 1] = "C_Item-item-cache" end
  if present("GetItemInfo") then tags[#tags + 1] = "legacy-item-cache-global" end
  if not present("UnitDefenseSkill") and not present("UnitAttackPower") then
    tags[#tags + 1] = "no-legacy-sheet-stat-api"
  end

  local verdict
  if classicTalents and retailSpecs then
    verdict = "mixed"
  elseif classicTalents then
    verdict = "classic-style"
  elseif retailSpecs then
    verdict = "retail-style"
  else
    verdict = "unknown"
    tags[#tags + 1] = "no-talent-api"
  end
  return verdict, tags
end

function SF.FlavorReportLine(values)
  local verdict, tags = SF.InferFlavor(values)
  return "FLAVOR " .. verdict .. " [" .. table.concat(tags, ", ") .. "]"
end

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------
--- Build the report body and return it as an ordered list of single lines.
--- Rebuilt on every call: a cached report would describe a previous client
--- state, which is exactly the confusion this module exists to remove.
function SF.BuildDiagnosticsReportLines()
  local lines = {}
  lines[#lines + 1] = "Touchstone diagnostics v" .. tostring(SF.VERSION)
  lines[#lines + 1] = 'ADDON version="' .. tostring(SF.VERSION) ..
    '" toc="' .. tostring(SF.TOC_INTERFACE or "?") .. '"'
  lines[#lines + 1] = SF.ClientReportLine()
  for _, line in ipairs(SF.ProjectReportLines()) do
    lines[#lines + 1] = line
  end

  -- Card t_adf556d6: the item-cache probes (GetItemInfo / C_Item.GetItemInfo)
  -- used to be fed a real item id harvested from the snapshot. With the capture
  -- gone there is no snapshot to harvest from, so no itemId is passed and those
  -- two probes resolve their placeholder arg to 1 -- exactly the honest reading
  -- on a healthy client (GetItemInfo(1) answers nil, and the report says so).
  local probeLines, values = SF.ProbeReportLines()
  lines[#lines + 1] = SF.FlavorReportLine(values)

  lines[#lines + 1] = "# API probes"
  for _, line in ipairs(probeLines) do
    lines[#lines + 1] = line
  end
  return lines
end

--- The same report as one copyable string.
function SF.BuildDiagnosticsReport()
  return table.concat(SF.BuildDiagnosticsReportLines(), "\n")
end

--- Print the report to the chat frame one line at a time. A single print() of a
--- multi-line string collapses to one unreadable chat line in WoW, so /sf doctor
--- emits each line separately (the panel is still opened alongside it).
function SF.PrintDiagnosticsReport()
  SF.Print("diagnostics report — also opening the copyable panel")
  for _, line in ipairs(SF.BuildDiagnosticsReportLines()) do
    print(line)
  end
end

-- ---------------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------------
--- Select the whole report so the tester can press Ctrl+C and paste it.
--- Classic Era exposes no clipboard API, so selection is the copy mechanism
--- (the Export tab's JSON area works the same way).
function SF.CopyDiagnosticsReport()
  local report = SF.BuildDiagnosticsReport()
  if SF.diagEditBox then
    SF.diagEditBox:SetText(report)
    if SF.diagEditBox.HighlightText then
      SF.diagEditBox:HighlightText(0, #report)
    end
    if SF.diagEditBox.SetFocus then
      SF.diagEditBox:SetFocus()
    end
    SF.Print("diagnostics selected — press Ctrl+C to copy.")
  else
    SF.Print("diagnostics: open the panel with /sf diag first.")
  end
  return report
end

function SF.ShowDiagnosticsPanel()
  if SF.diagFrame and SF.diagEditBox then
    SF.diagFrame:Show()
    SF.diagFrame:Raise()
    SF.diagEditBox:SetText(SF.BuildDiagnosticsReport())
    return SF.diagFrame
  end

  local f = CreateFrame("Frame", "StatForgeDiagFrame", UIParent, "BackdropTemplate")
  f:SetSize(880, 560)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  f:SetBackdropColor(0.043, 0.047, 0.063, 0.97)
  f:SetBackdropBorderColor(0.271, 0.635, 0.620, 0.85)

  local titleBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
  titleBar:SetPoint("TOPLEFT", 1, -1)
  titleBar:SetPoint("TOPRIGHT", -1, -1)
  titleBar:SetHeight(32)
  titleBar:EnableMouse(true)
  titleBar:RegisterForDrag("LeftButton")
  titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
  titleBar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

  local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("LEFT", 12, 0)
  title:SetText(SF.Accent("Touchstone diagnostics") .. "  ·  copy this into chat")

  local close = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
  close:SetPoint("RIGHT", -4, 0)

  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hint:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 12, -8)
  hint:SetWidth(840)
  hint:SetJustifyH("LEFT")
  hint:SetText("Every API is listed as PRESENT or ABSENT — the first ABSENT line is usually the bug. "
    .. "Re-run this after changing zones or reloading; it always reads live state.")
  hint:SetTextColor(0.482, 0.506, 0.588)

  local refreshBtn = SF.UI_CreateButton(f, "Refresh", 110, 26)
  refreshBtn:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", -8, -10)
  refreshBtn:SetScript("OnClick", function()
    SF.diagEditBox:SetText(SF.BuildDiagnosticsReport())
  end)

  local copyBtn = SF.UI_CreateButton(f, "Copy report (Ctrl+C)", 190, 26)
  copyBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 10, 0)
  copyBtn:SetPrimary(true)
  copyBtn:SetScript("OnClick", function() SF.CopyDiagnosticsReport() end)

  local scroll = CreateFrame("ScrollFrame", "StatForgeDiagScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", refreshBtn, "BOTTOMLEFT", 8, -10)
  scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 14)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetFontObject("ChatFontNormal")
  edit:SetWidth(800)
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(0)
  edit:SetTextInsets(8, 8, 8, 8)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  scroll:SetScrollChild(edit)

  edit:SetText(SF.BuildDiagnosticsReport())

  SF.diagEditBox = edit
  SF.diagFrame = f
  -- guarded: tinsert(_G.UISpecialFrames) would throw if UISpecialFrames is absent
  if type(UISpecialFrames) == "table" then
    tinsert(UISpecialFrames, "StatForgeDiagFrame")
  end
  return f
end

-- NodeTrail — the herb tooltip path (t_f4ff9ea6).
--
-- This module no longer writes anything into Blizzard's tooltip. It answers one
-- question for the poller — "is the hovered thing one of OUR herb nodes?" — and
-- then hands the block to `ns.TooltipPanel`, which owns a frame of its own.
--
-- The append path is gone on purpose, and so are the three workarounds built on
-- top of it (widen the frame, measure-and-size the frame, wrap our lines to the
-- client's width). All three lost the same race: this client sizes the
-- tooltip's backdrop at SHOW time and re-derives it on every subsequent show, so
-- anything we did to the frame was reset — or, worse, the backdrop stopped
-- covering our lines while our text stayed on the raw map. Nothing that writes
-- into GameTooltip is kept here, because nothing that writes into GameTooltip
-- can be made to hold.
--
-- What remains is read-only: GetOwner, the line font strings' text and font, and
-- the frame's geometry. No HookScript, no SetScript, no AddLine, no SetWidth, no
-- Show on the tooltip — the panel is ours from creation to hide.
local _, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

local T = {}
ns.Tooltip = T

-- At most ~5 refresh evaluations per second. The panel is redrawn from this
-- tick; nothing else drives it.
local POLL_INTERVAL = 0.2

-- "Open Alchemy once to list recipe uses" is only truthful while a scan is
-- actually POSSIBLE. On a client with no trade-skill API at all (both the
-- legacy globals and C_TradeSkillUI absent — the Forever 16001 report: the hint
-- sat up forever with no way to clear it), printing it promises a step the
-- player can never complete, so the line is dropped; `/nt status` carries the
-- explanation instead (t_0d5badc3).
local function recipeAPIAvailable()
  if type(ns.Recipes) ~= "table" or type(ns.Recipes.APIInfo) ~= "function" then
    return false
  end
  local ok, info = pcall(ns.Recipes.APIInfo, ns.Recipes)
  if not ok or type(info) ~= "table" then
    return false
  end
  return info.available == true
end

--- The character's profession, as the client reports it (t_d4848ce0).
--- Returns true (has it), false (does not) or nil (this client cannot say).
--- The panel's data build is the only place the gate belongs: nothing here
--- touches the tooltip.
local function professionAnswer(skill)
  local mod = ns.Profession
  if type(mod) ~= "table" then
    return nil
  end
  local fn = (skill == "skinning") and "Skinning" or "Herbalism"
  if type(mod[fn]) ~= "function" then
    return nil
  end
  local ok, answer = pcall(mod[fn], mod)
  if not ok then
    return nil
  end
  if answer == true or answer == false then
    return answer
  end
  return nil
end

-- ── secret values ─────────────────────────────────────────────────────────
-- The live client hands back SECRET strings for creature names (a secret may
-- be shown but never measured, sliced, formatted or converted). The beast block
-- passes the name straight to the panel's display-only slot; every other read
-- of a client string is guarded here first, and `issecretvalue` is the only
-- operation that is always safe.
local function isSecretValue(v)
  if type(issecretvalue) ~= "function" then
    return false
  end
  local ok, s = pcall(issecretvalue, v)
  return ok and s == true
end

-- The unit's GUID, or nil when this client will not give a readable one. A
-- secret GUID is never parsed: the recorder's own parse refuses one too.
local function unitGUID(unit)
  if type(UnitGUID) ~= "function" then
    return nil
  end
  local ok, g = pcall(UnitGUID, unit)
  if not ok or type(g) ~= "string" or g == "" or isSecretValue(g) then
    return nil
  end
  return g
end

-- The creature type as the client names it (lowercased for the comparison, so
-- a client that says "beast" and one that says "Beast" both answer).
local function creatureTypeOf(unit)
  if type(UnitCreatureType) ~= "function" then
    return nil, "UnitCreatureType absent"
  end
  local ok, t = pcall(UnitCreatureType, unit)
  if not ok then
    return nil, "UnitCreatureType raised: " .. tostring(t)
  end
  if isSecretValue(t) then
    return nil, "UnitCreatureType answered a secret value, so it cannot be compared"
  end
  if type(t) ~= "string" or t == "" then
    return nil, "UnitCreatureType answered nothing"
  end
  local okL, lower = pcall(string.lower, t)
  if not okL or type(lower) ~= "string" or lower == "" then
    return nil, "the creature type could not be read"
  end
  return lower, nil
end

-- The unit's name, or nil. A secret name is returned UNTOUCHED (it may be
-- shown); a name that is really the GUID is dropped, because this client
-- answers UnitName with the GUID for some units and printing a GUID where a
-- name belongs is a lie (the recorder's usableName exists for the same reason).
local function unitName(unit, guid)
  if type(UnitName) ~= "function" then
    return nil
  end
  local ok, name = pcall(UnitName, unit)
  if not ok or name == nil then
    return nil
  end
  if isSecretValue(name) then
    return name
  end
  if type(name) ~= "string" or name == "" then
    return nil
  end
  local okC, looksLikeGUID = pcall(function()
    if type(guid) == "string" and name == guid then
      return true
    end
    return name:match("^Creature%-%d") ~= nil
  end)
  if okC and looksLikeGUID then
    return nil
  end
  return name
end

-- The creature types the beast block may speak about. A humanoid, mechanical,
-- undead or elemental hover gets nothing at all — this block is about what a
-- SKINNABLE BEAST's corpse and skinning gave (t_c0221fd7).
--
-- `UnitCreatureType` answers a LOCALIZED string this client keeps in its DBC
-- (the exe carries no "Beast" literal), and this client's `textLocale` is
-- enUS. A translated client needs its own entry here, exactly like
-- Profession.NAMES; an entry this table does not know is not a beast, so the
-- failure direction stays "draw nothing".
local BEAST_TYPES = { beast = true, beasts = true }

--- Where the picks count comes from: NodeTrailDB.herbs.maps is ONE saved table
--- for every character on the account (Recorder.lua keys nothing by character),
--- so the wording says so. Calling it "your picks" on a character that never
--- gathered a single herb is the lie this card exists to remove.
local function picksLine(gathers)
  if gathers and gathers > 0 then
    return "Picks: " .. gathers .. " (all characters)"
  end
  return "Picks: none yet (all characters)"
end

--- The block's content, as data. Rows are { left = <name>, right = <value> } —
--- two columns, exactly like the client's own double lines. No header line: the
--- block opens with the node name (the left column of the node's own drop row).
---
--- Returns (lines, reason). `lines` is nil — and `reason` says why — when the
--- block must not be drawn at all: this character has no Herbalism, so an herb
--- node has no personal history to show and the node knowledge is not theirs to
--- see (t_d4848ce0).
function T.BuildLines(name)
  local node = ns.HerbData.GetNode(name)
  if not node then return nil, "not one of our herb nodes" end
  local answer = professionAnswer()
  if answer == false then
    return nil, "no Herbalism on this character — the herb block is hidden"
  end
  local lines = {}
  local drops, gathers = ns.HerbData.GetDropLines(name)
  if drops then
    for _, d in ipairs(drops) do
      -- t_04c983cc, reworked by t_e27da774: the row's name comes from ONE
      -- resolver (Data/ItemNames.lua) in one order — the name the record
      -- captured at loot time (the slot's own item link), then our researched
      -- table, then GetItemInfo, and only then
      -- `item <id> (name unavailable)`. A bare number printed as a name was the
      -- bug Mightie reported; `249399` is "Frilled Lichen" and the name was
      -- there at gather time.
      local itemName = ns.HerbData.ItemLabel(d)
      local right = d.pct .. "%" .. (d.source == "base" and " (base)" or "")
      table.insert(lines, { left = itemName, right = right })
    end
  end
  -- The picks line only appears when the client CONFIRMED this character can
  -- gather: an unreadable profession (nil) keeps the node knowledge below but
  -- claims no personal history at all.
  if answer == true then
    table.insert(lines, { left = picksLine(gathers) })
  end
  -- PARKED (Mightie, 2026-11-09): "lets just take that part out of the tooltip
  -- info for now. we can bring it back later if we decide to. the % of drops is
  -- fine for now". The recipe-uses block is behind a default-OFF switch, not
  -- deleted: the scan, the gate and /nt recipediag all keep working, so turning
  -- it back on is one config value and no code. This client answers
  -- craftable=true and IsRecipeProfessionLearned=true for recipes he cannot
  -- make, so the line needs the count-only gate finished before it earns its
  -- place in a tooltip again.
  -- Read the stored profile WITHOUT creating it: ns.GetDB() would build a fresh
  -- NodeTrailDB in the middle of a tooltip render (and in a spec that has
  -- deliberately cleared it), which is not a render's job.
  local prof = (type(NodeTrailDB) == "table" and type(NodeTrailDB.profile) == "table")
    and NodeTrailDB.profile or nil
  local showUses = prof ~= nil and prof.showAlchemyUses == true
  local uses = showUses and ns.Recipes:Uses(node.item) or nil
  if not showUses then -- luacheck: ignore 542
    -- parked: no recipe lines and no "open Alchemy once" hint either, so a
    -- parked feature cannot advertise itself in a tooltip.
  elseif uses then
    if uses.filtered then
      -- Only what the character can actually make now (t_04c983cc). Mightie:
      -- "alchemy tooltip is giving info for crafts i cant do yet." The
      -- availability was captured by the scan; this is a filter, not a second
      -- calculation. Nothing is dropped silently: the withheld recipes are
      -- counted in one short tail.
      if #uses.craftable > 0 then
        local text = "Alchemy: " .. table.concat(uses.craftable, ", ")
        if uses.excluded > 0 then
          text = text .. ", +" .. uses.excluded .. " more you can't make yet"
        end
        table.insert(lines, { left = text })
      else
        -- Every scanned recipe is above his skill or unlearned. Listing none is
        -- right; saying "none" is how the player learns WHY the line changed.
        table.insert(lines, {
          left = ("Alchemy: none you can make yet (%d recipe(s) withheld)"):format(uses.excluded),
        })
      end
    else -- luacheck: ignore 542
      -- t_4ab7c230: the scan could not learn availability for this recipe
      -- (this client answered no craftable count, no learned flag and no
      -- required skill). The honest answer is NOT an unfiltered list with a
      -- caveat — a line that advertises eight crafts he cannot make is worse
      -- than no line — so draw nothing here. The options panel carries the one
      -- short reason (Rc:HiddenHint) and /nt recipediag the raw signals.
    end
  elseif NodeTrailDB and NodeTrailDB.recipes and NodeTrailDB.recipes.alchemyScanned == nil
    and recipeAPIAvailable() then
    -- A scan that already ran (the Alchemy window was open, its recipes were
    -- read) but found no reagent slots is INCOMPLETE: re-promising "open
    -- Alchemy once" promises a step that was already taken, so say what
    -- actually happened instead (t_81da8886).
    local d = (ns.Recipes and type(ns.Recipes._diag) == "table") and ns.Recipes._diag or nil
    if d and d.gated == "no-reagents" then
      table.insert(lines, { left = "Alchemy scan found no reagents — none saved" })
    else
      table.insert(lines, { left = "Open Alchemy once to list recipe uses" })
    end
  end
  return lines
end

--- The BEAST block's content, as data (t_c0221fd7). Mightie: "we should have
--- some information when hovering over beasts that says what we might get if we
--- kill it and skin it. Same as herbing just another step in the middle."
---
--- Returns (lines, reason, cid). `lines` is nil when nothing may be drawn; the
--- reason is nil too when the hover was simply not a creature, so the caller
--- keeps its own "not a herb tooltip" answer for every other window.
---
--- The gates, in the order they are cheaper and more authoritative:
---   * a mouseover unit must exist                (no unit → not ours, no reason)
---   * its GUID must be a Creature GUID           (a player/pet/object → not ours)
---   * its NPC id must parse                      (the records are keyed by it)
---   * the client must call it a BEAST             (humanoids/mechanicals → nothing)
---   * the character must have Skinning            (same gate as the herb block)
---   * the client must not say "not skinnable"     (only when it actually answers)
--- Then every number comes from our own recorded corpses (Data/SkinHints.lua).
--- The creature is matched by NPC ID, NOT by the displayed name: names repeat
--- across zones and the client can hand a name back as a secret value.
function T.BuildBeastLines(unit)
  unit = unit or "mouseover"
  local H = ns.SkinHints
  if type(H) ~= "table" or type(H.Rows) ~= "function" then
    return nil, nil, nil
  end
  if type(UnitExists) ~= "function" then
    return nil, nil, nil
  end
  local okE, exists = pcall(UnitExists, unit)
  if not okE or exists ~= true then
    return nil, nil, nil
  end
  local guid = unitGUID(unit)
  if guid == nil then
    return nil, nil, nil
  end
  -- A literal dash is %-, and Lua patterns have no alternation: one test.
  local isCreature = false
  local okP, matched = pcall(function() return guid:match("^Creature%-%d") ~= nil end)
  if okP then
    isCreature = matched == true
  end
  if not isCreature then
    return nil, nil, nil
  end
  local cid = H.CreatureID(guid)
  if type(cid) ~= "number" then
    return nil, "the creature's GUID carries no readable NPC id", nil
  end
  local creatureType, typeWhy = creatureTypeOf(unit)
  if creatureType == nil then
    -- Cannot confirm it is a beast → say nothing (a hidden block is the safe
    -- direction: appearing on a humanoid would be the worse mistake).
    return nil, "not a beast: " .. tostring(typeWhy), cid
  end
  if not BEAST_TYPES[creatureType] then
    return nil, "not a beast (" .. tostring(creatureType) .. ")", cid
  end
  local answer = professionAnswer("skinning")
  if answer ~= true then
    -- t_5ba9b43c: only a CONFIRMED skinner sees this block. The herb block hides
    -- on a definitive "no" and shows on "unknown" because its node knowledge
    -- (HerbData's researched drop table) is not personal — there is something
    -- true left to say without the picks line. The beast block has no such
    -- table: every row is an aggregate of this character's own recorded corpses
    -- (Data/SkinHints.lua never invents one), so "unknown" leaves nothing that
    -- is both true and useful, and the panel abstains.
    --
    -- The live report (skinned: 0 beside "(yours)" percentages on a
    -- non-skinner) is exactly this branch: the old code tested `== false` and
    -- let nil through. A definitive "no" cannot produce that block — the gate
    -- already hid it.
    --
    -- The GATE is the shared one: professionAnswer -> ns.Profession:Skinning,
    -- the same three measured tiers the herb block asks about Herbalism. Only
    -- what each consumer does with "unknown" differs, and each site says why.
    if answer == false then
      return nil, "no Skinning on this character — the beast block is hidden", cid
    end
    return nil, "Skinning could not be read on this client — the beast block abstains "
      .. "rather than show records it cannot attribute", cid
  end
  local skinnable = H.SkinFlag(unit)
  if skinnable == false then
    return nil, "the client reports this creature as not skinnable", cid
  end
  local name = unitName(unit, guid)
  local lines = H.Rows(cid, name)
  if type(lines) ~= "table" or #lines == 0 then
    return nil, "no rows for this creature", cid
  end
  return lines, nil, cid
end

--- Is the hovered object one of our herb nodes? Reads only: the owner test and
--- the client's first line of text. A client whose tooltip object lacks
--- GetOwner (or a caller passing no tooltip at all) is not a herb hover —
--- answer "no" instead of raising.
function T:GetHoveredNodeName(tooltip)
  if type(tooltip) ~= "table" or type(tooltip.GetOwner) ~= "function" then
    return nil
  end
  if UnitExists and UnitExists("mouseover") then
    return nil
  end
  local owner = tooltip:GetOwner()
  if owner ~= UIParent and owner ~= WorldFrame and owner ~= nil then
    return nil
  end
  local fs = _G["GameTooltipTextLeft1"]
  local text = fs and fs.GetText and fs:GetText()
  if text and ns.HerbData.GetNode(text) then
    return text
  end
  return nil
end

-- ── refresh decision ring ────────────────────────────────────────────────
-- The in-client flicker report ("the block appears, then goes away super
-- fast") cannot be diagnosed from a screenshot: what matters is who evaluated
-- the tooltip, what it found, and whether the panel was touched. The last eight
-- decisions are kept and printed by /nt ttdiag AFTER the fact.
local RING_MAX = 8
local RING = {}
local evalCount = 0

--- The sequence number is taken when an evaluation STARTS, and the entry is
--- stored when it finishes: the operator has to read the outer evaluation
--- first.
local function nextSeq()
  evalCount = evalCount + 1
  return evalCount
end

local function ringPush(entry)
  RING[#RING + 1] = entry
  while #RING > RING_MAX do
    table.remove(RING, 1)
  end
end

function T.RingEntries()
  local out = {}
  for i = 1, #RING do
    out[i] = RING[i]
  end
  table.sort(out, function(a, b)
    return (a.n or 0) < (b.n or 0)
  end)
  return out
end

function T:Ring() -- compat alias, returns the same table
  return RING
end

-- ── the one writer: our own panel ─────────────────────────────────────────
local function panelModule()
  local panel = ns.TooltipPanel
  if type(panel) ~= "table" or type(panel.Update) ~= "function" then
    return nil
  end
  return panel
end

--- Evaluate the tooltip and bring the panel in line with it. This is the ONLY
--- caller of the panel, and it never touches the tooltip: the tooltip is read
--- for the hovered name and its rect, and nothing else.
function T:Refresh(tooltip, source)
  source = source or "poll"
  local entry = {
    n = nextSeq(),
    source = source,
    when = type(GetTime) == "function" and GetTime() or nil,
  }
  local panel = panelModule()
  local name = self:GetHoveredNodeName(tooltip)
  local lines, why, kind, cid
  if name then
    kind = "herb"
    lines, why = T.BuildLines(name)
  else
    -- Not one of our herb nodes. A UNIT hover may still be a beast with
    -- recorded corpses (t_c0221fd7) — the beast block is the herb block's
    -- "other step in the middle". Everything else falls through to the hide
    -- below, unchanged.
    kind = "beast"
    lines, why, cid = T.BuildBeastLines("mouseover")
    if lines == nil and why == nil then
      kind = nil -- not a creature at all: not our tooltip, no beast decision
    end
  end
  entry.kind = kind
  entry.name = name -- a herb node name (our own table); never a client string
  if cid ~= nil then
    entry.cid = cid
  end
  if not lines then
    -- Not a herb tooltip (unknown object, some other window) or a beast we may
    -- not speak about. Whatever is in there is the client's, and our panel must
    -- not linger.
    local reason = why
    if not reason and kind == nil then
      reason = "not a herb tooltip"
    end
    reason = reason or "no lines for this node"
    if type(panel) == "table" then
      panel:Hide(reason)
    end
    entry.panelShown = false
    entry.skip = reason
    ringPush(entry)
    return
  end
  if panel == nil then
    entry.skip = "panel module not loaded (UI/TooltipPanel.lua)"
    ringPush(entry)
    return
  end
  local info = panel:Update(lines, tooltip)
  entry.panelShown = type(info) == "table" and info.shown or false
  entry.rows = type(info) == "table" and info.rows or nil
  entry.width = type(info) == "table" and info.width or nil
  entry.widest = type(info) == "table" and info.widest or nil
  entry.skip = (type(info) == "table" and info.skip)
    or ("panel shows " .. tostring(entry.rows or "?") .. " row(s)")
  ringPush(entry)
end

-- ── the poller ────────────────────────────────────────────────────────────
--- One poll step, callable directly (the specs drive it; the addon's private
--- frame calls it on a clock). While the tooltip is hidden the panel is hidden
--- and no evaluation is spent; while it is shown the panel is rebuilt from the
--- hovered node's lines.
function T:Poll(tooltip)
  tooltip = tooltip or GameTooltip
  if type(tooltip) ~= "table" then
    return nil
  end
  local shown = false
  if type(tooltip.IsShown) == "function" then
    local ok, value = pcall(tooltip.IsShown, tooltip)
    shown = ok and value == true
  end
  local panel = panelModule()
  if not shown then
    -- The tooltip went away: the panel goes with it. Nothing else to do, and
    -- no ring entry — a hidden tooltip is not an evaluation.
    if type(panel) == "table" and type(panel.IsShown) == "function" and panel:IsShown() then
      panel:Hide("tooltip hidden")
      T._hiddenHides = (T._hiddenHides or 0) + 1
    end
    return false
  end
  self:Refresh(tooltip, "poll")
  return true
end

-- ── /nt ttdiag ─────────────────────────────────────────────────────────────
-- The in-client evidence channel. It prints, in this order: the refresh ring
-- (who evaluated the tooltip and what was decided), the PANEL's own rect /
-- width budget / widest line, and then what the tooltip itself holds — line
-- count, anchors, measured edges and the screen verdict. Cheap (a handful of
-- pcall-guarded reads) and safe on a client missing most of the API.
function T:Diag()
  local function say(msg)
    local line = "NodeTrail ttdiag: " .. tostring(msg)
    if type(DEFAULT_CHAT_FRAME) == "table" and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
      local ok = pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, line)
      if ok then
        return
      end
    end
    pcall(print, line)
  end

  local function px(v)
    if type(v) == "number" then
      return string.format("%.0f", v)
    end
    return "absent"
  end

  -- 1) The ring goes first: it is the evidence even when the tooltip is closed
  --    by the time /nt ttdiag is typed.
  local ring = T.RingEntries()
  if type(ring) ~= "table" or #ring == 0 then
    say("refresh ring: empty (no evaluation recorded yet)")
  else
    say(("refresh ring: last %d evaluation(s), oldest first"):format(#ring))
    for i = 1, #ring do
      local e = ring[i] or {}
      local function flag(v)
        if v == nil then
          return "-"
        end
        return v and "yes" or "no"
      end
      say((("eval #%s src=%s kind=%s cid=%s name=%s panel=%s rows=%s width=%s widest=%s — %s")):format(
        tostring(e.n or "?"), tostring(e.source or "?"), tostring(e.kind or "-"),
        tostring(e.cid or "-"), tostring(e.name or "-"),
        flag(e.panelShown), tostring(e.rows or "-"), px(e.width), px(e.widest),
        tostring(e.skip or "")))
    end
  end

  -- 2) The profession gate (t_d4848ce0): which API this client exposes for the
  --    character's professions, what it said about THIS character, and which
  --    rule the block's visibility came from. A hidden herb block has to be
  --    diagnosable from here — otherwise "no block on my skinner" and "the
  --    feature is broken" look identical.
  local profMod = ns.Profession
  if type(profMod) ~= "table" or type(profMod.Diagnose) ~= "function" then
    say("profession: module not loaded (Data/Profession.lua) — the block cannot tell whether this character has Herbalism, so it shows without a picks line")
  else
    local okProf, profLines = pcall(profMod.Diagnose, profMod)
    if not okProf or type(profLines) ~= "table" then
      say("profession: diag raised — " .. tostring(profLines))
    else
      for _, l in ipairs(profLines) do
        say("profession: " .. tostring(l))
      end
    end
  end

  -- 2b) Herb drop labels (t_04c983cc, t_e27da774): every drop id the panel can
  --     print that OUR table does not name, resolved the way the panel resolves
  --     it — what the record stored at loot time, what the client answers, and
  --     the label the panel prints. This is where "item 249399" on the panel
  --     becomes an answerable question, and where an id that could not be named
  --     is listed with the lookups that failed.
  local herbData = ns.HerbData
  if type(herbData) == "table" and type(herbData.NameProbeLines) == "function" then
    local okHd, hdLines = pcall(herbData.NameProbeLines)
    if not okHd or type(hdLines) ~= "table" then
      say("herb item: probe raised — " .. tostring(hdLines))
    else
      for _, l in ipairs(hdLines) do
        say("herb item: " .. tostring(l))
      end
    end
  end

  -- 3) The beast block's own evidence (t_c0221fd7): which store it reads, how
  --    many corpse records this character has, what the last beast hover
  --    aggregated, and the MEASURED answer to "does this client know whether a
  --    creature is skinnable". A hidden beast block has to be diagnosable from
  --    here for the same reason as the herb gate above.
  local hints = ns.SkinHints
  if type(hints) ~= "table" or type(hints.Diag) ~= "function" then
    say("beast block: module not loaded (Data/SkinHints.lua)")
  else
    local okH, hLines = pcall(hints.Diag, hints)
    if not okH or type(hLines) ~= "table" then
      say("beast block: diag raised — " .. tostring(hLines))
    else
      for _, l in ipairs(hLines) do
        say("beast: " .. tostring(l))
      end
    end
  end

  -- 4) The panel: its rect, the width budget it computed against, whether it
  --    is on screen, and the widest of OUR lines. These are the numbers the
  --    next report has to quote.
  local panel = ns.TooltipPanel
  if type(panel) == "table" and type(panel.Diag) == "function" then
    local okP, d = pcall(panel.Diag, panel)
    if not okP or type(d) ~= "table" then
      say("panel: diag raised — " .. tostring(d))
    elseif not d.created then
      say("panel: not created yet (no herb has been hovered since login)")
    else
      say(("panel: %s rows=%s rect L=%s B=%s R=%s T=%s (%.0fx%.0f local)"):format(
        d.shown and "SHOWN" or ("hidden — " .. tostring(d.hideReason or "?")),
        tostring(d.rows), px(d.left), px(d.bottom), px(d.right), px(d.top),
        tonumber(d.width) or 0, tonumber(d.height) or 0))
      say(("panel: width budget=%s (45%% of the screen) widest of our lines=%s%s text-only=%s placement=%s%s"):format(
        px(d.cap), px(d.widest),
        type(d.widestText) == "string" and (" \"" .. d.widestText .. "\"") or "",
        px(d.widestTextPx),
        tostring(d.placement or "?"), (d.clampedX or d.clampedY) and " (clamped into the screen)" or ""))
      say(("panel: font=%s applied=%s backdrop=%s"):format(
        tostring(d.font or "absent"), d.fontApplied and "yes" or "no",
        tostring(d.backdrop or "?")))
      if type(d.width) == "number" and type(d.needWidth) == "number" then
        -- The verdict is built from MEASURED TEXT only — no column gap, no
        -- padding — and refuses to say yes when a text-bearing row measured 0.
        -- Otherwise a client that cannot measure reports "text 12" (the column
        -- gap) at a 72 px minimum and the six-hover report proves nothing. Both
        -- figures are printed, and when the independent meter measured nothing
        -- that is said too.
        local textPx = tonumber(d.widestTextPx) or 0
        local padX = 2 * (d.padX or 0)
        local needText = textPx + padX
        local how = ("panel %s vs text %s + padding %s = %s"):format(
          px(d.width), px(textPx), px(padX), px(needText))
        if type(d.widestMeasuredTextPx) == "number" then
          how = how .. (", measured independently with %s (%s px)"):format(
            tostring(d.font or "?"), px(d.widestMeasuredTextPx))
        else
          how = how .. "; no independent measurement on this client"
        end
        if d.blind then
          how = how .. "; a text-bearing row measured 0"
        end
        say(("panel: covers its widest line=%s (%s; raw rows=%s floor=%spx; drawn rows report %s)"):format(
          d.covers and "yes" or "NO", how, tostring(d.rawRows or 0), px(d.rawFloor), px(d.widest)))
      end
    end
  else
    say("panel: module not loaded (UI/TooltipPanel.lua)")
  end

  -- 4) What the tooltip itself holds. Read-only, every read pcall-guarded.
  local gt = GameTooltip
  local function blockState()
    if type(panel) == "table" and type(panel.TextLines) == "function" then
      local okT, lines = pcall(panel.TextLines, panel)
      if okT and type(lines) == "table" and #lines > 0 then
        return ("block: %d row(s) in the panel (nothing is appended to the tooltip)"):format(#lines)
      end
    end
    return "block: none (the panel carries the herb block; the tooltip only holds the client's lines)"
  end
  if type(gt) ~= "table" then
    say("GameTooltip unavailable")
    return
  end
  local function readNum(method)
    local f = gt[method]
    if type(f) ~= "function" then
      return nil
    end
    local ok, value = pcall(f, gt)
    if ok and type(value) == "number" then
      return value
    end
    return nil
  end
  local shown = false
  if type(gt.IsShown) == "function" then
    local ok, value = pcall(gt.IsShown, gt)
    shown = ok and value == true
  end
  if not shown then
    say("tooltip hidden; " .. blockState())
    return
  end
  local n = readNum("NumLines")
  local w = readNum("GetWidth")
  local h = readNum("GetHeight")
  say(("NumLines=%s W=%s H=%s"):format(
    n and tostring(n) or "?",
    w and string.format("%.0f", w) or "?",
    h and string.format("%.0f", h) or "?"))
  local npts = readNum("GetNumPoints") or 0
  if npts > 0 and type(gt.GetPoint) == "function" then
    for i = 1, npts do
      -- Real GetPoint contract: point, relativeTo, relativePoint, x, y.
      local okP, point, relativeTo, relativePoint, xOfs, yOfs = pcall(gt.GetPoint, gt, i)
      if not okP then
        say(("point %d: GetPoint error"):format(i))
      else
        local relName = "?"
        if type(relativeTo) == "table" then
          if type(relativeTo.GetName) == "function" then
            local okn, nm = pcall(relativeTo.GetName, relativeTo)
            if okn and type(nm) == "string" then
              relName = nm
            end
          end
          if relName == "?" then relName = "frame" end
        end
        say(("point %d: %s of %s %s xOfs=%s yOfs=%s"):format(
          i,
          type(point) == "string" and point or "?",
          relName,
          type(relativePoint) == "string" and relativePoint or "?",
          type(xOfs) == "number" and string.format("%.0f", xOfs) or tostring(xOfs),
          type(yOfs) == "number" and string.format("%.0f", yOfs) or tostring(yOfs)))
      end
    end
  else
    say("points: none (frame unanchored)")
  end
  if type(gt.GetLeft) == "function" and type(gt.GetRight) == "function"
    and type(gt.GetTop) == "function" and type(gt.GetBottom) == "function" then
    local okE, l = pcall(gt.GetLeft, gt)
    local r, t, b
    if okE then
      local okR, rr = pcall(gt.GetRight, gt)
      local okT, tt = pcall(gt.GetTop, gt)
      local okB, bb = pcall(gt.GetBottom, gt)
      if okR then r = rr end
      if okT then t = tt end
      if okB then b = bb end
    end
    if type(l) == "number" and type(r) == "number" and type(t) == "number" and type(b) == "number" then
      say(("measured: left=%.0f right=%.0f top=%.0f bottom=%.0f"):format(l, r, t, b))
    else
      say("measured: edge getters present but returned non-numbers")
    end
  end
  if type(UIParent) == "table" and type(UIParent.GetWidth) == "function"
    and type(UIParent.GetHeight) == "function" then
    local okS, sw, sh = pcall(function()
      return UIParent:GetWidth(), UIParent:GetHeight()
    end)
    if okS and type(sw) == "number" and type(sh) == "number" then
      say(("screen %.0fx%.0f"):format(sw, sh))
    else
      say("screen: UIParent size unavailable")
    end
  else
    say("screen: UIParent absent")
  end
  if T._error then
    say("error: " .. tostring(T._error))
  end
  say(blockState())
end

--- Enable the poller. There is nothing to hook: the panel is driven by this
--- clock alone, and the tooltip is never written to, never hooked and never
--- shown. A client without GameTooltip:IsShown cannot drive the panel at all,
--- and says so instead of half-working.
function T:Enable()
  if self._enabled then return end
  self._enabled = true
  if type(GameTooltip) ~= "table" then
    self._noPoll = "GameTooltip is not available on this client"
    return
  end
  if type(GameTooltip.IsShown) ~= "function" then
    self._noPoll = "GameTooltip:IsShown is not available on this client — the panel cannot be driven"
    return
  end
  if type(CreateFrame) ~= "function" then
    self._noPoll = "CreateFrame is not available on this client — no poll clock"
    return
  end
  local ok, poll = pcall(CreateFrame, "Frame", "NodeTrailTooltipPoll")
  if not ok or type(poll) ~= "table" or type(poll.SetScript) ~= "function" then
    self._noPoll = "CreateFrame refused the poll frame"
    return
  end
  self.poller = poll
  local accum = 0
  poll:SetScript("OnUpdate", function(_, elapsed)
    accum = accum + (elapsed or POLL_INTERVAL)
    if accum < POLL_INTERVAL then
      return
    end
    accum = 0
    local okPoll, err = pcall(T.Poll, T, GameTooltip)
    if not okPoll then
      T._error = tostring(err)
    end
  end)
  -- Show the clock frame: a bare Frame has no texture, so this is invisible —
  -- it only subscribes the OnUpdate above.
  if type(poll.Show) == "function" then
    poll:Show()
  end
end

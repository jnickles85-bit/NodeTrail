local _, pkg = ...

local panel = CreateFrame("Frame", "MightiePackOptionsPanel")
panel.name = "MightiePack"

local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
title:SetText("MightiePack")

local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
subtitle:SetText("Tick a module to turn it on. Turning one off needs a UI reload.")

local modulesHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
modulesHeader:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
modulesHeader:SetText("Modules")

local boxes = {}
pkg.optionsBoxes = boxes

-- Forward declaration: syncCheckboxes (defined above the Alchemy
-- widgets) calls this after the body is assigned.
local relayoutLowerSections

-- ── Row layout ──────────────────────────────────────────────────────
-- Widgets are anchored to the previous row (vertical flow), not to a
-- precomputed Y on the panel. That is what made the skinning-circle status
-- overlap its checkbox and left a large gap before "Scan now" (space was
-- reserved for hidden error/note lines).
-- moduleOrder is complete by the time this file loads (the TOC lists every
-- module before Options.lua).
local SUB_INDENT = 36
local ROW_GAP = 8
local SUB_GAP = 4
local SECTION_GAP = 16
local STATUS_WIDTH = 400

-- NodeTrail's indented sub-options (skinning, auto-refresh, farming
-- circle) only appear when that module is in moduleOrder.
local nodeTrailListed = false
for _, name in ipairs(pkg.moduleOrder or {}) do
  if name == "NodeTrail" then
    nodeTrailListed = true
    break
  end
end

-- ── Skinning sub-option helpers (t_5507a0ba) ────────────────────────
-- The probe is NodeTrail's, so the toggle is NodeTrail's too: it lives at
-- NodeTrailDB.skinning.enabled (not MightiePackDB.modules.Skinning) and is
-- owned by the NodeTrail namespace. Every lookup is guarded so the panel
-- still renders when NodeTrail (or the probe files) did not load.
local function ntModule()
  local nt = pkg.NodeTrail
  if type(nt) == "table" then
    return nt
  end
  return nil
end

local function nodeTrailOn()
  if type(pkg.IsModuleEnabled) ~= "function" then
    return false
  end
  local ok, on = pcall(pkg.IsModuleEnabled, "NodeTrail")
  return ok and on == true
end

local function skinningOn()
  local nt = ntModule()
  if nt and type(nt.IsSkinningEnabled) == "function" then
    local ok, on = pcall(nt.IsSkinningEnabled)
    if ok then
      return on == true
    end
  end
  return false
end

-- t_57550700: ON by default (Mightie's final call: "doesnt need to come off by
-- default"). What the box turns on is a re-plan every `autoRefreshPicks`
-- gathers — not one per herb, which is what made the line move under him.
local function autoRefreshOn()
  local nt = ntModule()
  if nt and type(nt.IsAutoRefreshRoute) == "function" then
    local ok, on = pcall(nt.IsAutoRefreshRoute)
    if ok then
      return on == true
    end
  end
  return true
end

-- t_b46e5e87: the skinning farming circle's switch (default ON). Its own key at
-- NodeTrailDB.skinroute.enabled, separate from the probe and from the herb route.
local function skinRouteOn()
  local nt = ntModule()
  if nt and type(nt.IsSkinRouteEnabled) == "function" then
    local ok, on = pcall(nt.IsSkinRouteEnabled)
    if ok then
      return on == true
    end
  end
  return true
end

-- The one sentence the circle's row shows, and ONLY for a confirmed skinner:
-- a non-skinner must not see a "no data" line anywhere (t_b46e5e87). It states
-- the count needed whenever nothing can be drawn yet.
local function skinRouteNote()
  local nt = ntModule()
  if not nt then
    return nil
  end
  local Pr = nt.Profession
  if type(Pr) ~= "table" or type(Pr.Skinning) ~= "function" then
    return nil
  end
  local okG, answer = pcall(Pr.Skinning, Pr)
  if not okG or answer ~= true then
    return nil
  end
  if type(nt.SkinRoute) ~= "table" or type(nt.SkinRoute.StatusText) ~= "function" then
    return nil
  end
  local ok, line = pcall(nt.SkinRoute.StatusText, nt.SkinRoute)
  if ok and type(line) == "string" and line ~= "" then
    return line
  end
  return nil
end

-- Apply the sub-toggle: persist it and re-evaluate the layer immediately.
local function applySkinRoute(on)
  local nt = ntModule()
  if not nt then
    pkg.Print("skinning circle: NodeTrail is not loaded — the sub-option was not saved")
    return false
  end
  if type(nt.SetSkinRouteEnabled) ~= "function" then
    pkg.Print("skinning circle: NodeTrail has no sub-option setter — the sub-option was not saved")
    return false
  end
  local okS, errS = pcall(nt.SetSkinRouteEnabled, on)
  if not okS then
    pkg.Print("skinning circle: could not save the sub-option: " .. tostring(errS))
    return false
  end
  local route, why
  if type(nt.RefreshSkinRoute) == "function" then
    local okR, r, w = pcall(nt.RefreshSkinRoute)
    if okR then
      route, why = r, w
    else
      pkg.Print("skinning circle: refresh failed: " .. tostring(r))
      return false
    end
  end
  if on then
    if route then
      pkg.Print(("Skinning farming circle on — %d-point green loop over %d clusters on this map.")
        :format(#route.path, #route.clusters))
    elseif why == "NOT_SKINNER" then
      pkg.Print("Skinning farming circle on, but this character has no Skinning — nothing is drawn.")
    elseif why == "GATE_UNREADABLE" or why == "NO_GATE" then
      pkg.Print("Skinning farming circle on, but this client cannot read the character's professions — nothing is drawn.")
    else
      local line = (type(nt.SkinRoute) == "table" and type(nt.SkinRoute.StatusText) == "function")
        and nt.SkinRoute:StatusText() or nil
      pkg.Print("Skinning farming circle on, but " .. (line or "there is no route to draw yet") .. ".")
    end
  else
    pkg.Print("Skinning farming circle off — the green loop is cleared; the herb route is unaffected.")
  end
  return true
end

-- Apply the sub-toggle: persist it, then start/stop the probe immediately.
-- The setter (NodeTrail's ns.SetSkinningEnabled) also records this as the
-- player's own choice (t_ba64b076 skinUserSet), which is what keeps an "off"
-- from being overridden by a later default or migration.
-- No reload is needed — switching off unregisters the probe's events and
-- drops its session buffer (P:Disable) — so this deliberately does NOT
-- raise MIGHTIEPACK_DISABLE_MODULE. That popup exists to warn about a
-- reload; there is nothing to warn about here, and the chat line says so.
local function applySkinning(on)
  local nt = ntModule()
  if not nt then
    pkg.Print("skinning: NodeTrail is not loaded — the sub-option was not saved")
    return false
  end
  if type(nt.SetSkinningEnabled) ~= "function" then
    pkg.Print("skinning: NodeTrail has no sub-option setter — the sub-option was not saved")
    return false
  end
  local okS, errS = pcall(nt.SetSkinningEnabled, on)
  if not okS then
    pkg.Print("skinning: could not save the sub-option: " .. tostring(errS))
    return false
  end
  if on then
    if type(nt.EnableSkinning) == "function" then
      local okE, errE = nt.EnableSkinning()
      if okE == false then
        pkg.Print("skinning: probe did not start: " .. tostring(errE))
        return false
      end
    end
    pkg.Print("Skinning (experimental) on — recording corpses into NodeTrailDB; /mp skindiag dump shows what was stored.")
  else
    if type(nt.DisableSkinning) == "function" then
      nt.DisableSkinning()
    end
    pkg.Print("Skinning (experimental) off — the probe stopped now; no UI reload needed.")
  end
  return true
end


-- ── Touchstone "Gear for" picker ────────────────────────────────────
-- Indented under the Touchstone checkbox. A cycling button (UIDropDownMenu
-- is not assumed present on 16001). Hidden while Touchstone is off so the
-- NodeTrail row stays anchored directly under Touchstone (existing layout
-- contract). When Touchstone is on, NodeTrail is re-anchored under this
-- row so the two do not overlap. Changing the value writes ChestAdvisorDB
-- .gearFor and rescans immediately (ChestAdvisor.setGearFor).
local function playerClassToken()
  if type(UnitClass) ~= "function" then return nil end
  local ok, _, tok = pcall(UnitClass, "player")
  if ok and type(tok) == "string" then return tok end
  return nil
end

local function talentSpecName()
  if not (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
      and C_SpecializationInfo.GetSpecializationInfo) then
    return nil
  end
  local ok, idx = pcall(C_SpecializationInfo.GetSpecialization)
  if not ok or type(idx) ~= "number" or idx == 0 then return nil end
  local ok2, _, name = pcall(C_SpecializationInfo.GetSpecializationInfo, idx)
  if ok2 and type(name) == "string" and name ~= "" then return name end
  return nil
end

local function gearForChoices()
  local talent = talentSpecName()
  local autoLabel = talent and ("Auto (talents: " .. talent .. ")") or "Auto (talents)"
  local out = { { key = nil, label = autoLabel } }
  if type(ChestAdvisor) == "table" and type(ChestAdvisor.specsFor) == "function" then
    local list = ChestAdvisor.specsFor(playerClassToken())
    if type(list) == "table" then
      for _, e in ipairs(list) do
        out[#out + 1] = { key = e.key, label = e.name }
      end
    end
  end
  return out
end

local function currentGearForKey()
  if type(ChestAdvisor) == "table" and type(ChestAdvisor.gearForKey) == "function" then
    local ok, key = pcall(ChestAdvisor.gearForKey)
    if ok then return key end
  end
  return nil
end

local function applyGearFor(key)
  if type(ChestAdvisor) == "table" and type(ChestAdvisor.setGearFor) == "function" then
    pcall(ChestAdvisor.setGearFor, key)
  end
end

local function refreshGearForButton()
  local btn = boxes.GearFor
  if not btn or type(btn.SetText) ~= "function" then return end
  local want = currentGearForKey()
  local label = "Auto (talents)"
  for _, c in ipairs(gearForChoices()) do
    if (c.key == nil and want == nil) or (c.key ~= nil and c.key == want) then
      label = c.label
      break
    end
  end
  btn:SetText(label)
end

local function cycleGearFor()
  local choices = gearForChoices()
  if #choices == 0 then return end
  local want = currentGearForKey()
  local idx = 1
  for i, c in ipairs(choices) do
    if (c.key == nil and want == nil) or (c.key ~= nil and c.key == want) then
      idx = i
      break
    end
  end
  local nxt = choices[(idx % #choices) + 1]
  applyGearFor(nxt and nxt.key or nil)
  refreshGearForButton()
end

local function touchstoneOn()
  if boxes.Touchstone and type(boxes.Touchstone.GetChecked) == "function" then
    return boxes.Touchstone:GetChecked() and true or false
  end
  if type(pkg.IsModuleEnabled) == "function" then
    local ok, on = pcall(pkg.IsModuleEnabled, "Touchstone")
    if ok then return on == true end
  end
  return false
end

local function placeGearForRow()
  local ts = boxes.Touchstone
  if not ts then return end
  if not boxes.GearForLabel then
    local lab = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lab:SetText("Gear for")
    boxes.GearForLabel = lab
  end
  if not boxes.GearFor then
    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    if type(btn.SetSize) == "function" then btn:SetSize(220, 22) end
    if type(btn.SetWidth) == "function" then btn:SetWidth(220) end
    if type(btn.SetHeight) == "function" then btn:SetHeight(22) end
    btn:SetScript("OnClick", function()
      cycleGearFor()
    end)
    btn:SetScript("OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("Gear for")
      GameTooltip:AddLine("Which spec Touchstone scores and gates gear for, using that spec's Wowhead stat priority. Auto follows your current talents. A chosen spec wins over talents and over /up role. Tanks default to Wowhead's Balanced list (or Defensive for Feral Bear); other variants are in this list.", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
      if GameTooltip then GameTooltip:Hide() end
    end)
    boxes.GearFor = btn
  end
  local lab, btn = boxes.GearForLabel, boxes.GearFor
  if type(lab.ClearAllPoints) == "function" then lab:ClearAllPoints() end
  lab:SetPoint("TOPLEFT", ts, "BOTTOMLEFT", SUB_INDENT - 16, -SUB_GAP)
  if type(btn.ClearAllPoints) == "function" then btn:ClearAllPoints() end
  btn:SetPoint("LEFT", lab, "RIGHT", 8, 0)
  refreshGearForButton()
  local nt = boxes.NodeTrail
  if touchstoneOn() then
    if type(lab.Show) == "function" then lab:Show() end
    if type(btn.Show) == "function" then btn:Show() end
    if nt and type(nt.ClearAllPoints) == "function" then
      nt:ClearAllPoints()
      nt:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", -(SUB_INDENT - 16), -ROW_GAP)
    end
  else
    if type(lab.Hide) == "function" then lab:Hide() end
    if type(btn.Hide) == "function" then btn:Hide() end
    if nt and type(nt.ClearAllPoints) == "function" then
      nt:ClearAllPoints()
      nt:SetPoint("TOPLEFT", ts, "BOTTOMLEFT", 0, -ROW_GAP)
    end
  end
end

function pkg.relayoutOptions()
  placeGearForRow()
  if type(relayoutLowerSections) == "function" then
    relayoutLowerSections()
  end
end

local function syncCheckboxes()
  for index, name in ipairs(pkg.moduleOrder or {}) do
    local def = pkg.modules and pkg.modules[name]
    if def then
      local cb = boxes[name]
      if not cb then
        cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        local prevMod
        for i = 1, (index or 1) - 1 do
          local earlier = (pkg.moduleOrder or {})[i]
          if earlier and boxes[earlier] then
            prevMod = boxes[earlier]
          end
        end
        if prevMod then
          cb:SetPoint("TOPLEFT", prevMod, "BOTTOMLEFT", 0, -ROW_GAP)
        else
          cb:SetPoint("TOPLEFT", modulesHeader, "BOTTOMLEFT", 0, -ROW_GAP)
        end

        local label
        if cb.Text or cb.text then
          label = cb.Text or cb.text
        else
          label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
          label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        end
        local labelText = def.title or name
        if def.stub then
          labelText = labelText .. " (coming soon)"
        end
        label:SetText(labelText)

        if def.stub then
          cb:Disable()
        else
          cb:SetScript("OnClick", function(self)
            local on = self:GetChecked() and true or false
            if on then
              pkg.SetModuleEnabled(name, true)
              pkg.EnableModules()
              -- A module can refuse to run (Touchstone while the standalone
              -- addon folder is installed). Its Enable() has already printed
              -- why; "enabled." here would be a lie.
              if not def.inert then
                pkg.Print((def.title or name) .. " enabled.")
              end
              -- The skinning sub-option is greyed out while NodeTrail is
              -- off; re-sync so it becomes usable the moment it is on.
              syncCheckboxes()
            else
              StaticPopup_Show("MIGHTIEPACK_DISABLE_MODULE", def.title or name, nil, { name = name, checkbox = self })
            end
          end)
        end

        cb:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:SetText(def.title or name)
          if def.notes then
            GameTooltip:AddLine(def.notes, 1, 1, 1, true)
          end
          GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function()
          GameTooltip:Hide()
        end)

        boxes[name] = cb
      end

      if def.stub then
        cb:SetChecked(false)
      else
        cb:SetChecked(pkg.IsModuleEnabled(name))
      end
    end
  end

  -- ── Skinning sub-option (t_5507a0ba) ──────────────────────────────
  -- Indented under the NodeTrail checkbox, its own checkbox, and NOT a
  -- module row: Mightie's "Skinning should be inside NodeTrail." Greyed out
  -- and inert while NodeTrail is off (the probe is NodeTrail's), persisted
  -- in NodeTrailDB.skinning.enabled, applied immediately in both
  -- directions — no reload, so no MIGHTIEPACK_DISABLE_MODULE popup here.
  if nodeTrailListed then
    local sb = boxes.Skinning
    if not sb then
      sb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
      local ntCb = boxes.NodeTrail or boxes["NodeTrail"]
      if ntCb then
        sb:SetPoint("TOPLEFT", ntCb, "BOTTOMLEFT", SUB_INDENT - 16, -SUB_GAP)
      else
        sb:SetPoint("TOPLEFT", modulesHeader, "BOTTOMLEFT", SUB_INDENT - 16, -SUB_GAP)
      end

      local skinLabel
      if sb.Text or sb.text then
        skinLabel = sb.Text or sb.text
      else
        skinLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        skinLabel:SetPoint("LEFT", sb, "RIGHT", 4, 0)
      end
      skinLabel:SetText("Skinning (experimental)")

      sb:SetScript("OnClick", function(self)
        if not nodeTrailOn() then
          -- inert: NodeTrail owns the probe, so it cannot be on without it
          self:SetChecked(skinningOn())
          return
        end
        applySkinning(self:GetChecked() and true or false)
        syncCheckboxes()
      end)
      sb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Skinning (experimental)")
        GameTooltip:AddLine("NodeTrail's skinning probe: kill -> loot -> skin -> skin-loot capture for "
          .. "/mp skindiag and /mp skindiag dump. On by default: a fresh install records from the "
          .. "first corpse with no setup. Turn it off at any time — the choice is kept across "
          .. "/reload and every update, and no UI reload is needed now.", 1, 1, 1, true)
        GameTooltip:Show()
      end)
      sb:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)

      boxes.Skinning = sb
    end

    sb:SetChecked(skinningOn())
    if nodeTrailOn() then
      sb:Enable()
    else
      sb:Disable()
    end
  end

  -- ── Auto-refresh route sub-option (t_2bc15917, default flipped t_57550700)
  -- Mightie: "yes it needs to be automated for sure, at least on /reloads".
  -- The automatic behaviour has to be visible and switchable, so it is a
  -- checkbox beside the skinning one, persisted in
  -- NodeTrailDB.route.autoRefresh. It is OFF by default: ON is what re-planned
  -- the whole zone route under him while he gathered, and the line he was
  -- following is the ground he is walking. The /reload restore is NOT this
  -- switch — that always happens. It applies immediately in both directions:
  -- switching it off keeps the line that is drawn and stops pick-triggered
  -- rebuilds; switching it on rebuilds now and lets the next pick schedule one.
  if nodeTrailListed then
    local ab = boxes.AutoRefresh
    if not ab then
      ab = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
      if boxes.Skinning then
        ab:SetPoint("TOPLEFT", boxes.Skinning, "BOTTOMLEFT", 0, -SUB_GAP)
      else
        ab:SetPoint("TOPLEFT", modulesHeader, "BOTTOMLEFT", SUB_INDENT - 16, -SUB_GAP)
      end

      local autoLabel
      if ab.Text or ab.text then
        autoLabel = ab.Text or ab.text
      else
        autoLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        autoLabel:SetPoint("LEFT", ab, "RIGHT", 4, 0)
      end
      autoLabel:SetText("Auto-refresh route")

      ab:SetScript("OnClick", function(self)
        local nt = ntModule()
        if not nodeTrailOn() or not nt then
          self:SetChecked(autoRefreshOn())
          return
        end
        -- t_57550700: one implementation of the switch, shared with
        -- /nt autorefresh — so the box also rebuilds at once when turned on.
        local okS, value
        if type(nt.SetAutoRefresh) == "function" then
          okS, value = pcall(nt.SetAutoRefresh, self:GetChecked() and "on" or "off")
        elseif type(nt.SetAutoRefreshRoute) == "function" then
          okS, value = pcall(nt.SetAutoRefreshRoute, self:GetChecked() and true or false)
        else
          self:SetChecked(autoRefreshOn())
          return
        end
        if not okS then
          pkg.Print("auto-refresh: could not save the sub-option: " .. tostring(value))
        elseif value then
          pkg.Print("Auto-refresh route on — the route is rebuilt a few seconds after each gather.")
        else
          pkg.Print("Auto-refresh route off — the route stays as it is until /nt reload.")
        end
        syncCheckboxes()
      end)
      ab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Auto-refresh route")
        GameTooltip:AddLine("When on, a route you started is rebuilt and drawn again after a /reload or a login " ..
          "(if it is younger than the saved-route limit and you are on its map), and the line follows the " ..
          "herbs you gather — once, a few seconds after the last pick. Off keeps the line as it is.",
          1, 1, 1, true)
        GameTooltip:Show()
      end)
      ab:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)

      boxes.AutoRefresh = ab
    end

    ab:SetChecked(autoRefreshOn())
    if nodeTrailOn() then
      ab:Enable()
    else
      ab:Disable()
    end
  end

  -- ── Skinning farming circle sub-option (t_b46e5e87) ─────────────────
  -- The circle is a DRAW layer, so its switch is independent of the probe and of
  -- the herb route. The status line under it is shown ONLY to a confirmed
  -- skinner and says how many more skinned corpses this map needs — the maps
  -- themselves stay clean until there is real skinning data.
  if nodeTrailListed then
    local rb = boxes.SkinRoute
    if not rb then
      rb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
      if boxes.AutoRefresh then
        rb:SetPoint("TOPLEFT", boxes.AutoRefresh, "BOTTOMLEFT", 0, -SUB_GAP)
      elseif boxes.Skinning then
        rb:SetPoint("TOPLEFT", boxes.Skinning, "BOTTOMLEFT", 0, -SUB_GAP)
      else
        rb:SetPoint("TOPLEFT", modulesHeader, "BOTTOMLEFT", SUB_INDENT - 16, -SUB_GAP)
      end

      local rbLabel
      if rb.Text or rb.text then
        rbLabel = rb.Text or rb.text
      else
        rbLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        rbLabel:SetPoint("LEFT", rb, "RIGHT", 4, 0)
      end
      rbLabel:SetText("Skinning farming circle")

      rb:SetScript("OnClick", function(self)
        if not nodeTrailOn() then
          self:SetChecked(skinRouteOn())
          return
        end
        applySkinRoute(self:GetChecked() and true or false)
        syncCheckboxes()
      end)
      rb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Skinning farming circle")
        GameTooltip:AddLine("A green closed loop through the places this character has killed AND skinned on "
          .. "the current zone's map. Built from your own recorded corpses only. It stays hidden until the map "
          .. "has enough skinned corpses to make a circle, until a Skinning character is logged in, and while "
          .. "this box is unticked. The herb route (white) is a separate line and is not affected.",
          1, 1, 1, true)
        GameTooltip:Show()
      end)
      rb:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)

      boxes.SkinRoute = rb
    end

    local note = boxes.SkinRouteNote
    if not note then
      note = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      note:SetPoint("TOPLEFT", rb, "BOTTOMLEFT", 20, -SUB_GAP)
      if type(note.SetWidth) == "function" then note:SetWidth(STATUS_WIDTH) end
      if type(note.SetJustifyH) == "function" then pcall(note.SetJustifyH, note, "LEFT") end
      if type(note.SetWordWrap) == "function" then pcall(note.SetWordWrap, note, true) end
      if type(note.SetNonSpaceWrap) == "function" then pcall(note.SetNonSpaceWrap, note, true) end
      if type(note.SetTextColor) == "function" then pcall(note.SetTextColor, note, 0.7, 0.7, 0.7) end
      note:SetText("")
      boxes.SkinRouteNote = note
    end
    local text = skinRouteNote()
    if text then
      note:SetText(text)
      note:Show()
    else
      note:SetText("")
      note:Hide()
    end

    rb:SetChecked(skinRouteOn())
    if nodeTrailOn() then
      rb:Enable()
    else
      rb:Disable()
    end
  end
  placeGearForRow()
  relayoutLowerSections()
end

-- ── Recipes block (NodeTrail's Alchemy recipe scan) ─────────────────
-- The scan used to be invisible unless you knew /nt status, and
-- learning a recipe never refreshed it (t_36412359). This block
-- surfaces the SAME truth the panel/slash share (Rc:StatusLine —
-- four states: scanned / not scanned yet / cannot list / no reagents)
-- plus a "Scan now" button (Rc:TryScanNow). Every lookup is pcall'd,
-- so the panel still renders when the NodeTrail module is off.
local function ntRecipes()
  if pkg and pkg.NodeTrail and type(pkg.NodeTrail.Recipes) == "table" then
    return pkg.NodeTrail.Recipes
  end
  return nil
end

-- Style a gray, word-wrapped status line that sits on its own row.
local function styleStatusLine(fs)
  if type(fs.SetWidth) == "function" then fs:SetWidth(STATUS_WIDTH) end
  if type(fs.SetJustifyH) == "function" then pcall(fs.SetJustifyH, fs, "LEFT") end
  if type(fs.SetWordWrap) == "function" then pcall(fs.SetWordWrap, fs, true) end
  if type(fs.SetNonSpaceWrap) == "function" then pcall(fs.SetNonSpaceWrap, fs, true) end
  if type(fs.SetTextColor) == "function" then pcall(fs.SetTextColor, fs, 0.7, 0.7, 0.7) end
end

-- Re-anchor the Alchemy and Feedback sections under the last visible
-- module widget so a shown/hidden status line never overlaps a checkbox
-- and hidden recipe notes do not leave a hole above "Scan now".
local recHeader, recStatus, recError, recNote, recButton
local feedbackHeader, bugButton, ideaButton

local function lastModuleWidget()
  local note = boxes.SkinRouteNote
  if note and ((type(note.IsShown) == "function" and note:IsShown()) or note.shown == true) then
    return note, -(SUB_INDENT + 20 - 16)
  end
  if boxes.SkinRoute then
    return boxes.SkinRoute, -(SUB_INDENT - 16)
  end
  if boxes.AutoRefresh then
    return boxes.AutoRefresh, -(SUB_INDENT - 16)
  end
  if boxes.Skinning then
    return boxes.Skinning, -(SUB_INDENT - 16)
  end
  if boxes.NodeTrail then
    return boxes.NodeTrail, 0
  end
  local last
  for _, name in ipairs(pkg.moduleOrder or {}) do
    if boxes[name] then last = boxes[name] end
  end
  if last then return last, 0 end
  return modulesHeader, 0
end

local function lastAlchemyWidget()
  if recNote and ((type(recNote.IsShown) == "function" and recNote:IsShown()) or recNote.shown == true) then
    return recNote
  end
  if recError and ((type(recError.IsShown) == "function" and recError:IsShown()) or recError.shown == true) then
    return recError
  end
  return recButton or recStatus or recHeader
end

function relayoutLowerSections()
  if not recHeader or type(recHeader.SetPoint) ~= "function" then
    return
  end
  local anchor, dx = lastModuleWidget()
  if type(recHeader.ClearAllPoints) == "function" then recHeader:ClearAllPoints() end
  recHeader:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", dx or 0, -SECTION_GAP)
  if feedbackHeader and type(feedbackHeader.SetPoint) == "function" then
    local above = lastAlchemyWidget()
    if type(feedbackHeader.ClearAllPoints) == "function" then feedbackHeader:ClearAllPoints() end
    if above then
      feedbackHeader:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -SECTION_GAP)
    end
  end
end

-- The recipe block starts under the last module/sub-option row (re-anchored
-- in relayoutLowerSections once those rows exist).
recHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
recHeader:SetPoint("TOPLEFT", modulesHeader, "BOTTOMLEFT", 0, -120)
recHeader:SetText("Alchemy Recipes")

recStatus = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
recStatus:SetPoint("TOPLEFT", recHeader, "BOTTOMLEFT", 0, -6)
styleStatusLine(recStatus)
recStatus:SetText("")

-- Create Scan now before recError so the error line can sit under the
-- button from the start (scripts are attached after syncRecipesBlock).
recButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
recButton:SetPoint("TOPLEFT", recStatus, "BOTTOMLEFT", 0, -8)
recButton:SetSize(96, 24)
recButton:SetText("Scan now")

recError = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
recError:SetPoint("TOPLEFT", recButton, "BOTTOMLEFT", 0, -6)
recError:SetText("")
recError:Hide()
styleStatusLine(recError)

-- t_4ab7c230: when the client answers no availability at all, the herb tooltip
-- draws NO Alchemy line (a list of crafts he cannot make is worse than none).
-- This is the one short place the reason lives, so nobody re-opens the card
-- expecting a fix this client cannot support.
recNote = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
recNote:SetPoint("TOPLEFT", recError, "BOTTOMLEFT", 0, -4)
recNote:SetText("")
recNote:Hide()
styleStatusLine(recNote)

local function syncRecipesBlock()
  local rec = ntRecipes()
  if rec and type(rec.StatusLine) == "function" then
    local ok, line = pcall(rec.StatusLine, rec)
    if ok and type(line) == "string" then
      recStatus:SetText(line)
    else
      recStatus:SetText("recipes: status unavailable (" .. tostring(line) .. ")")
    end
    recStatus:Show()
  else
    recStatus:SetText("recipe module not loaded — turn NodeTrail on")
    recStatus:Show()
  end
  local err
  if rec and type(rec.LastError) == "function" then
    local okE, e = pcall(rec.LastError, rec)
    if okE and type(e) == "string" and e ~= "" then
      err = e
    end
  end
  if err then
    recError:SetText("last error: " .. err)
    recError:Show()
  else
    recError:SetText("")
    recError:Hide()
  end
  -- The hidden-list explanation (t_4ab7c230). nil when the gate is working or
  -- nothing is saved yet, so the line stays invisible in the normal case.
  local hint
  if rec and type(rec.HiddenHint) == "function" then
    local okH, h = pcall(rec.HiddenHint, rec)
    if okH and type(h) == "string" and h ~= "" then
      hint = h
    end
  end
  if hint then
    recNote:SetText(hint)
    recNote:Show()
  else
    recNote:SetText("")
    recNote:Hide()
  end
  relayoutLowerSections()
end

recButton:SetScript("OnClick", function()
  local rec = ntRecipes()
  if rec and type(rec.TryScanNow) == "function" then
    local ok, done, msg = pcall(rec.TryScanNow, rec)
    if not ok then
      DEFAULT_CHAT_FRAME:AddMessage("NodeTrail recipes: scan failed: " .. tostring(done))
    else
      DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
  else
    DEFAULT_CHAT_FRAME:AddMessage("NodeTrail recipes: module not loaded (turn NodeTrail on)")
  end
  syncRecipesBlock()
end)
recButton:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText("Rescan your learned Alchemy recipes now")
  GameTooltip:AddLine("Needs the Alchemy window open. A learned recipe also refreshes automatically the next time you open Alchemy.", 1, 1, 1, true)
  GameTooltip:Show()
end)
recButton:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)

-- ── Bug report entry point ──────────────────────────────────────────
-- Opens the same selectable popup as /mp bug. The report is pre-filled
-- (version, client, modules, class+level, zone, last Lua error) for the
-- player to copy with Ctrl+C. Nothing is uploaded.
feedbackHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
feedbackHeader:SetPoint("TOPLEFT", recButton, "BOTTOMLEFT", 0, -SECTION_GAP)
feedbackHeader:SetText("Feedback")

bugButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
bugButton:SetPoint("TOPLEFT", feedbackHeader, "BOTTOMLEFT", 0, -8)
bugButton:SetSize(128, 24)
bugButton:SetText("Report a bug")
bugButton:SetScript("OnClick", function()
  if type(pkg.OpenBugReport) == "function" then
    -- Same popup as /mp bug.
    pkg.OpenBugReport()
  else
    DEFAULT_CHAT_FRAME:AddMessage("MightiePack: bug report form unavailable (BugReport module did not load)")
  end
end)
bugButton:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText("Open a pre-filled bug report — press Ctrl+C to copy, then paste it in #mightiepack-bugs on Discord")
  GameTooltip:AddLine("Nothing is uploaded: copy the report and paste it into the #mightiepack-bugs Discord channel.", 1, 1, 1, true)
  GameTooltip:Show()
end)
bugButton:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)

ideaButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
ideaButton:SetPoint("LEFT", bugButton, "RIGHT", 8, 0)
ideaButton:SetSize(150, 24)
ideaButton:SetText("Suggest an idea")
ideaButton:SetScript("OnClick", function()
  if type(pkg.OpenIdeaReport) == "function" then
    -- Same popup as /mp idea.
    pkg.OpenIdeaReport()
  else
    DEFAULT_CHAT_FRAME:AddMessage("MightiePack: idea form unavailable (BugReport module did not load)")
  end
end)
ideaButton:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText("Open a pre-filled idea form — press Ctrl+C to copy, then paste it into #mightiepack-ideas")
  GameTooltip:AddLine("Nothing is uploaded: copy the idea and paste it into the #mightiepack-ideas Discord channel.", 1, 1, 1, true)
  GameTooltip:Show()
end)
ideaButton:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)

panel:SetScript("OnShow", function()
  syncCheckboxes()
  syncRecipesBlock()
  relayoutLowerSections()
end)

relayoutLowerSections()

StaticPopupDialogs["MIGHTIEPACK_DISABLE_MODULE"] = {
  text = "Turn off %s?\nThis needs a UI reload. OK reloads now; Cancel keeps it on.",
  button1 = OKAY,
  button2 = CANCEL,
  OnAccept = function(self, data)
    if data and data.name then
      pkg.SetModuleEnabled(data.name, false)
    end
    ReloadUI()
  end,
  OnCancel = function(self, data)
    if data and data.checkbox then
      data.checkbox:SetChecked(pkg.IsModuleEnabled(data.name))
    end
  end,
  OnHide = function(self)
    local data = self.data
    if data and data.checkbox then
      data.checkbox:SetChecked(pkg.IsModuleEnabled(data.name))
    end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

pcall(function()
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    pkg.settingsCategory = category
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end)

function pkg.OpenOptions()
  if pkg.settingsCategory and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(pkg.settingsCategory:GetID())
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
  else
    panel:Show()
  end
end

pkg.optionsPanel = panel

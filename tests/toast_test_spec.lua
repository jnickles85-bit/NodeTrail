-- t_4bae0617: the deterministic test toast, and the MEASURED lifetime of the
-- real panel.
--
-- Run from the repo root:  lua5.1 tests/toast_test_spec.lua
--
-- The "Upgrade found!" toast could only be seen when a real bag item happened to
-- be judged an UPGRADE, so nothing about its lifetime, fade or dismiss had a
-- test. This spec runs the REAL addon file against a simulated client (virtual
-- clock, frames, animation groups) and measures how long the panel is actually
-- on screen, from the frame's own shown state — not from the configured value.
--
-- THE CONTRACT THAT MATTERS: on this client AnimationGroup:Stop() reports
-- OnFinished (the same behaviour the file's own comment about
-- "Stopped and Played in one frame" describes). Every show stops both groups
-- before playing the fade-in, so a finish handler that trusts a bare OnFinished
-- ends the show it has just started. Both client contracts are exercised below:
-- the toast must survive its full lifetime under EITHER.

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."
local ADVISOR = root .. "/MightiePack/Modules/Touchstone/ChestAdvisor/ChestAdvisor.lua"

local DEFAULT_LIFETIME = 3.5   -- TOAST_DEFAULTS.lifetime
local FADE_OUT = 0.25          -- TOAST.fadeOut
local TICK = 0.25              -- TOAST.tick

-- ═══ the simulated client ══════════════════════════════════════════════════
-- Every scenario gets its own clock, frames and globals, exactly like a fresh
-- login: the addon file is loaded again into that environment.
local function scenario(opts, body)
  local stopFires = opts.stopFires == true
  local clock = 0
  local pending = {}

  local function schedule(delay, fn)
    local t = { at = clock + delay, fn = fn }
    pending[#pending + 1] = t
    return t
  end
  local function step(dt)
    local target = clock + dt
    while true do
      local best, bi
      for i = 1, #pending do
        local t = pending[i]
        if not t.cancelled and t.at <= target + 1e-9 and (not best or t.at < best.at) then
          best, bi = t, i
        end
      end
      if not best then break end
      clock = best.at
      table.remove(pending, bi)
      best.fn()
    end
    clock = target
  end

  _G.C_Timer = {
    After = function(d, fn) return schedule(d, fn) end,
    NewTicker = function(interval, fn)
      local obj = { cancelled = false }
      local function tick()
        if obj.cancelled then return end
        fn()
        if not obj.cancelled then schedule(interval, tick) end
      end
      obj.Cancel = function() obj.cancelled = true end
      schedule(interval, tick)
      return obj
    end,
  }

  local textures = {}
  local function makeTexture()
    local t = {}
    local function noop() end
    t.SetPoint, t.SetAllPoints, t.SetColorTexture, t.SetTexCoord, t.SetSize,
      t.SetWidth, t.SetHeight, t.SetShown, t.SetVertexColor, t.SetBlendMode,
      t.Hide, t.Show = noop, noop, noop, noop, noop, noop, noop, noop, noop, noop, noop, noop
    t.SetTexture = function(_, v) t.texture = v; textures[#textures + 1] = v end
    t.GetTexture = function() return t.texture end
    return t
  end
  local function makeFontString()
    local fs = { text = "" }
    local function noop() end
    fs.SetPoint, fs.SetAllPoints, fs.SetTextColor, fs.SetJustifyH, fs.SetShown,
      fs.Hide, fs.Show = noop, noop, noop, noop, noop, noop, noop
    fs.SetText = function(_, v) fs.text = tostring(v) end
    fs.GetText = function() return fs.text end
    return fs
  end
  local function makeAnimGroup(frame)
    local ag = { scripts = {}, animations = {}, frame = frame }
    function ag:CreateAnimation(kind)
      local a = { kind = kind, duration = 0 }
      function a:SetDuration(d) self.duration = d end
      function a:SetFromAlpha(v) self.from = v end
      function a:SetToAlpha(v) self.to = v end
      function a:SetOffset(x, y) self.dx, self.dy = x, y end
      function a:SetSmoothing() end
      function a:SetOrder() end
      self.animations[#self.animations + 1] = a
      return a
    end
    function ag:SetScript(k, fn) self.scripts[k] = fn end
    function ag:GetScript(k) return self.scripts[k] end
    function ag:IsPlaying() return self.playing == true end
    function ag:Play()
      local dur = 0
      for _, a in ipairs(self.animations) do if a.duration > dur then dur = a.duration end end
      self.playing = true
      self.ticket = schedule(dur, function()
        self.playing = false
        self.ticket = nil
        for _, a in ipairs(self.animations) do
          if a.kind == "Alpha" and a.to and self.frame and self.frame.SetAlpha then
            self.frame:SetAlpha(a.to)
          end
        end
        local cb = self.scripts.OnFinished
        if cb then cb() end
      end)
      return true
    end
    function ag:Stop()
      if self.ticket then self.ticket.cancelled = true; self.ticket = nil end
      self.playing = false
      -- The client behaviour this spec is built to survive.
      if stopFires then
        local cb = self.scripts.OnFinished
        if cb then cb() end
      end
    end
    function ag:Finish()
      if self.ticket then self.ticket.cancelled = true; self.ticket = nil end
      self.playing = false
      local cb = self.scripts.OnFinished
      if cb then cb() end
    end
    return ag
  end

  local frames = {}
  local hides = {}      -- clock at every Hide() that took a SHOWN panel off screen
  local function makeFrame(kind, name, parent, template)
    local f = { kind = kind, name = name, parent = parent, template = template,
      scripts = {}, events = {}, alpha = 1, shown = true }
    local function noop() end
    f.RegisterEvent = function(_, e) f.events[e] = true end
    f.UnregisterEvent = function(_, e) f.events[e] = nil end
    f.IsEventRegistered = function(_, e) return f.events[e] == true end
    f.SetScript = function(_, k, fn) f.scripts[k] = fn end
    f.GetScript = function(_, k) return f.scripts[k] end
    f.HookScript = noop
    f.SetPoint = function(self, p, _, _, x, y) self.point, self.x, self.y = p, x, y end
    f.GetPoint = function(self) return self.point or "TOP", nil, "TOP", self.x or 0, self.y or -140 end
    f.ClearAllPoints = noop
    f.SetAllPoints, f.SetSize, f.SetWidth, f.SetHeight, f.SetScale,
      f.SetFrameStrata, f.SetFrameLevel, f.SetParent, f.SetClampedToScreen,
      f.SetBackdrop, f.SetBackdropColor, f.SetBackdropBorderColor, f.EnableMouse,
      f.RegisterForClicks, f.SetMovable, f.RegisterForDrag, f.StartMoving,
      f.StopMovingOrSizing, f.SetText = noop, noop, noop, noop, noop, noop, noop, noop, noop, noop,
      noop, noop, noop, noop, noop, noop, noop, noop, noop, noop
    f.GetFrameLevel = function() return 1 end
    f.GetFrameStrata = function() return "HIGH" end
    f.SetAlpha = function(self, a) self.alpha = a end
    f.GetAlpha = function(self) return self.alpha end
    f.Show = function(self) self.shown = true end
    f.Hide = function(self)
      if self.shown == true and self.__isToast then hides[#hides + 1] = clock end
      self.shown = false
    end
    f.IsShown = function(self) return self.shown == true end
    f.CreateTexture = function() return makeTexture() end
    f.CreateFontString = function() return makeFontString() end
    f.CreateAnimationGroup = function() return makeAnimGroup(f) end
    frames[#frames + 1] = f
    if name then
      _G[name] = f
      if name == "ChestAdvisorToast" then f.__isToast = true end
    end
    setmetatable(f, { __index = function(_, k)
      if type(k) == "string" and k:match("^[A-Z]") then return function() end end
      return nil
    end })
    return f
  end

  local chat = {}
  _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end }
  _G.SlashCmdList = {}
  _G.CreateFrame = makeFrame
  _G.UIParent = makeFrame("Frame", "UIParent")
  frames = {}
  local bagsOpened = 0
  _G.OpenAllBags = function() bagsOpened = bagsOpened + 1 end
  _G.OpenBackpack = function() bagsOpened = bagsOpened + 1 end
  _G.GetTime = function() return clock end
  _G.InCombatLockdown = function() return false end
  _G.GetLocale = function() return "enUS" end
  -- The test entry has NO item id and NO link: the icon read throws and the
  -- show must fall back cleanly, exactly like an item whose data is missing.
  _G.C_Item = {
    GetItemIconByID = function() error("no item id on the test entry") end,
    GetItemInfo = function() error("no link on the test entry") end,
    GetItemInfoInstant = function() error("no item id on the test entry") end,
  }
  _G.C_PlayerInfo = { CanUseItem = function() return true end }
  _G.C_Map = { GetBestMapForUnit = function() return 0 end }
  _G.Verdict = {}
  _G.ChestAdvisor = nil
  _G.ChestAdvisorDB = { role = {}, toast = {} }
  _G.ChestAdvisorToast = nil

  local pkg = {
    Print = function(_, m) chat[#chat + 1] = tostring(m) end,
    modules = {}, modState = {},
  }
  pkg.IsModuleEnabled = function() return true end
  pkg.RegisterModule = function() end

  local chunk, loadErr = loadfile(ADVISOR)
  check(chunk ~= nil, "loadfile ChestAdvisor.lua: " .. tostring(loadErr))
  if not chunk then return nil end
  local ok, runErr = pcall(chunk, "MightiePack", pkg)
  check(ok, "ChestAdvisor.lua loads: " .. tostring(runErr))
  if not ok then return nil end
  check(type(ChestAdvisor._initToastSurface) == "function", "the toast surface is published")
  if type(ChestAdvisor._initToastSurface) ~= "function" then return nil end
  ChestAdvisor._initToastSurface()
  ChestAdvisor._initLogAndSlash()
  check(type(SlashCmdList.CHESTADVISOR) == "function", "/up,/ts handler registered")

  local ctx = {
    step = step,
    now = function() return clock end,
    textures = textures,
    bagsOpened = function() return bagsOpened end,
    state = function() return ChestAdvisor.toastState and ChestAdvisor.toastState() or nil end,
    frame = function() return _G.ChestAdvisorToast end,
    slash = function(msg)
      for i = #chat, 1, -1 do chat[i] = nil end
      local ok2, err = pcall(SlashCmdList.CHESTADVISOR, msg)
      check(ok2, "slash '" .. tostring(msg) .. "' ran without error: " .. tostring(err))
      return table.concat(chat, "\n")
    end,
    -- Run the clock until the panel is taken off screen, returning the time
    -- between now and that Hide(). Measured from the FRAME's own visibility, so
    -- the number is the client's, not the addon's own opinion (cross-checked
    -- against toastState().showMs where the spec prints it).
    measure = function()
      local t0 = clock
      local deadline = clock + DEFAULT_LIFETIME + 5
      local seen = #hides
      while clock < deadline do
        step(0.01)
        if #hides > seen then
          return { ms = math.floor((hides[#hides] - t0) * 1000 + 0.5), at = hides[#hides] }
        end
      end
      return { ms = nil }
    end,
  }
  return body(ctx)
end

-- ═══ 1. the command exists, is documented, and raises the real panel ═══════
local helpText
local afterFirst
scenario({ stopFires = true }, function(c)
  local help = c.slash("help")
  helpText = help
  check(help:find("/up toasts", 1, true) ~= nil,
    "/up help documents /up toasts (got: " .. help:gsub("\n", " | "):sub(1, 200) .. ")")
  check(help:find("testtoast", 1, true) ~= nil, "/up help documents the /up testtoast alias")
  check(help:find("/up toast <on|off>", 1, true) ~= nil, "the existing /up toast line is still there")

  check(type(ChestAdvisor.testToast) == "function", "ChestAdvisor.testToast is published")

  local out = c.slash("toasts")
  check(out:find("unknown command", 1, true) == nil,
    "/up toasts is a known command (got: " .. out:gsub("\n", " | "):sub(1, 240) .. ")")
  check(out:find("test toast", 1, true) ~= nil, "/up toasts confirms what it did")

  local st, f = c.state(), c.frame()
  check(type(st) == "table", "toastState is readable")
  if type(st) ~= "table" or not f then return end
  check(st.shown == true, "one toast is on screen (shown=" .. tostring(st.shown) .. ")")
  check(st.fired == 1, "fired is 1 after one /up toasts (got " .. tostring(st.fired) .. ")")
  check(st.queue == 0, "nothing left queued after one show (got " .. tostring(st.queue) .. ")")
  check(math.abs((st.lifetimeLeft or -1) - DEFAULT_LIFETIME) < 0.001,
    "the countdown starts at the configured lifetime (got " .. tostring(st.lifetimeLeft) .. ")")
  check(f.itemName and f.itemName:GetText() == "Test Upgrade",
    "the synthetic entry's name is on the panel (got " .. tostring(f.itemName and f.itemName:GetText()) .. ")")
  check(f.header and f.header:GetText() == "Upgrade found!",
    "the panel keeps the real header (got " .. tostring(f.header and f.header:GetText()) .. ")")
  -- buildToastMessage's documented fallback for an entry with no item id.
  check(f.sub and f.sub:GetText() == "Better item in your bags",
    "the message comes from buildToastMessage's fallback (got " .. tostring(f.sub and f.sub:GetText()) .. ")")
  -- The icon must fall back cleanly: the synthetic entry has no id, so the
  -- client read throws and the shipped fallback texture is used.
  local iconTex
  for _, t in ipairs(c.textures) do
    if type(t) == "string" and t:find("INV_Misc_Bag_08", 1, true) then iconTex = t end
  end
  check(iconTex ~= nil, "the icon fell back to the shipped texture")

  -- A second run while one is up must JOIN THE QUEUE, never stack a panel.
  local out2 = c.slash("toasts")
  local st2 = c.state()
  check(st2~= nil and st2.shown == true and st2.fired == 1 and st2.queue == 1,
    "the second /up toasts queues instead of stacking (shown=" .. tostring(st2 and st2.shown)
      .. " fired=" .. tostring(st2 and st2.fired) .. " queued=" .. tostring(st2 and st2.queue) .. ")")
  check(out2:find("queued: 1", 1, true) ~= nil,
    "the second run reports the queued toast (got: " .. out2:gsub("\n", " | "):sub(1, 160) .. ")")

  -- Nothing the scan owns may be touched: no dedupe entry, no log row.
  check((st2 and st2.told or -1) == 0, "toastedLinks was not marked (told=" .. tostring(st2 and st2.told) .. ")")
  check(ChestAdvisorDB.log == nil, "no row was written to ChestAdvisorDB.log")

  -- The measurement: from the frame's own shown flag, under the STRICT client
  -- contract (Stop() reports OnFinished).
  local m = c.measure()
  check(type(m.ms) == "number", "the panel was seen on and then off screen")
  if type(m.ms) == "number" then
    print(string.format("  measured on-screen: %d ms (configured %.2fs + %.2fs fade-out), queue rotated to %s",
      m.ms, DEFAULT_LIFETIME, FADE_OUT, tostring(c.state().fired)))
    check(m.ms >= (DEFAULT_LIFETIME + FADE_OUT) * 1000 - 100,
      "the toast stayed up for its full lifetime, not less (measured " .. m.ms .. " ms)")
    check(m.ms <= (DEFAULT_LIFETIME + FADE_OUT) * 1000 + 150,
      "the toast did not outlive its lifetime + fade-out (measured " .. m.ms .. " ms)")
  end

  -- Rotation: the queued toast took the screen after the first expired.
  local st3 = c.state()
  check(st3 and st3.fired == 2,
    "the queued toast rotated in (fired=" .. tostring(st3 and st3.fired) .. ")")
  check(st3 and st3.queue == 0, "the queue drained (queued=" .. tostring(st3 and st3.queue) .. ")")

  -- …and the second one gets its own full lifetime.
  local m2 = c.measure()
  check(type(m2.ms) == "number" and m2.ms >= (DEFAULT_LIFETIME + FADE_OUT) * 1000 - 100,
    "the rotated toast also lived its full lifetime (measured " .. tostring(m2.ms) .. " ms)")

  local st4 = c.state()
  check(st4 and st4.shown == false, "after the rotation nothing is on screen (shown=" .. tostring(st4 and st4.shown) .. ")")
  check(st4 and st4.lifetimeLeft == 0, "lifetimeLeft is 0 once the panel is gone (got " .. tostring(st4 and st4.lifetimeLeft) .. ")")

  -- /up diag must SHOW all of it: fired, the dead panel, and the measurement.
  local diag = c.slash("diag")
  check(diag:find("--- toast ---", 1, true) ~= nil,
    "/up diag prints a toast block without a scan ledger (got: " .. diag:gsub("\n", " | "):sub(1, 300) .. ")")
  check(diag:find("fired: 2", 1, true) ~= nil, "/up diag reports fired: 2 (got: " .. diag:gsub("\n", " | "):sub(1, 400) .. ")")
  check(diag:find("shown: false", 1, true) ~= nil, "/up diag reports shown: false")
  check(diag:find("lifetime left: 0", 1, true) ~= nil, "/up diag reports lifetime left: 0")
  check(diag:find("configured lifetime: 3.50s", 1, true) ~= nil, "/up diag reports the configured lifetime")
  check(diag:find("last show on screen: ", 1, true) ~= nil, "/up diag reports the MEASURED on-screen time")

  afterFirst = { fired = st4 and st4.fired, told = st4 and st4.told, ms = m.ms }
end)

check(afterFirst ~= nil, "scenario 1 ran to completion")

-- ═══ 2. the same measurement when Stop() does NOT report OnFinished ═══════
-- The other half of the client contract. A fix that depends on Stop() staying
-- silent would be a different bug (a panel that never hides); the lifetime must
-- be the same either way.
scenario({ stopFires = false }, function(c)
  c.slash("toasts")
  local m = c.measure()
  local st = c.state()
  check(type(m.ms) == "number", "lenient client: the panel was seen on and off screen")
  if type(m.ms) == "number" then
    print(string.format("  measured on-screen (lenient client): %d ms", m.ms))
    check(m.ms >= (DEFAULT_LIFETIME + FADE_OUT) * 1000 - 100,
      "lenient client: the toast stayed up for its full lifetime (measured " .. m.ms .. " ms)")
    check(m.ms <= (DEFAULT_LIFETIME + FADE_OUT) * 1000 + 150,
      "lenient client: the toast did not outlive its lifetime + fade-out (measured " .. m.ms .. " ms)")
  end
  check(st and st.shown == false and st.lifetimeLeft == 0,
    "lenient client: the panel is gone and the countdown is spent")
end)

-- ═══ 3. the login baseline is untouched by the test command ═══════════════
-- The baseline is the FIRST scan's set: whatever is already UPGRADE at that scan
-- must be marked told and never toasted. If /up toasts had consumed the gate, the
-- first real scan after it would toast a pre-existing bag item.
scenario({ stopFires = true }, function(c)
  c.slash("toasts")
  c.measure()                                   -- let the test toast finish
  local before = c.state()
  check(before and before.fired == 1, "one test toast fired (got " .. tostring(before and before.fired) .. ")")

  -- The first real scan: pre-existing upgrades are baseline, so silence.
  ChestAdvisor._maybeToastUpgrades({
    ["[Worn-But-In-Bags]"] = { verdict = "UPGRADE", id = 100, bag = 0, slot = 1 },
  })
  local mid = c.state()
  check(mid and mid.fired == 1,
    "the first real scan after /up toasts is still the silent baseline (fired=" .. tostring(mid and mid.fired) .. ")")
  check(mid and mid.queue == 0, "the baseline scan queued nothing (queued=" .. tostring(mid and mid.queue) .. ")")

  -- A link that was NOT in that baseline is news, and must toast: the gate was
  -- left where the scan expects it, not advanced by the test command.
  ChestAdvisor._maybeToastUpgrades({
    ["[Looted-After-Login]"] = { verdict = "UPGRADE", id = 101, bag = 0, slot = 2 },
  })
  local after = c.state()
  check(after and after.fired == 2,
    "a genuinely new upgrade still toasts after the test command (fired=" .. tostring(after and after.fired) .. ")")
end)

-- ═══ 4. the other end path: right-click dismiss, measured ══════════════════
scenario({ stopFires = true }, function(c)
  c.slash("toasts")
  local t0 = c.now()
  while c.now() < t0 + 0.5 do c.step(0.01) end
  local f = c.frame()
  check(f ~= nil and type(f.scripts.OnClick) == "function", "the panel carries a click handler")
  if not (f and type(f.scripts.OnClick) == "function") then return end
  local shownBefore = c.state()
  check(shownBefore and shownBefore.shown == true, "the toast is still up at 0.5s")
  f.scripts.OnClick(f, "RightButton")
  local st = c.state()
  check(st and st.shown == false, "right-click takes the panel off screen (shown=" .. tostring(st and st.shown) .. ")")
  check(st and st.lastEnd == "dismissed",
    "the dismiss is recorded as such (got " .. tostring(st and st.lastEnd) .. ")")
  check(st and type(st.showMs) == "number" and st.showMs >= 450 and st.showMs <= 650,
    "the dismiss records the MEASURED time it was up (~500 ms, got " .. tostring(st and st.showMs) .. ")")
  check(c.bagsOpened() == 0, "a right-click dismiss does not open the bags (opened " .. c.bagsOpened() .. ")")
  -- Nothing was queued behind it, so the panel is really gone and the countdown
  -- is spent — no timer fires a second finish.
  local after = {}
  while c.now() < t0 + 3.0 do c.step(0.01) end
  after = c.state()
  check(after and after.shown == false and after.lifetimeLeft == 0,
    "nothing reappears after the dismiss (shown=" .. tostring(after and after.shown) .. ")")
end)

-- ═══ 5. the refusal when the toast is switched off ════════════════════════
scenario({ stopFires = true }, function(c)
  -- The addon file assigns a fresh ChestAdvisorDB at load, so create the key.
  ChestAdvisorDB.toast = ChestAdvisorDB.toast or {}
  ChestAdvisorDB.toast.enabled = false
  local out = c.slash("toasts")
  local st = c.state()
  check(out:find("toast is off", 1, true) ~= nil,
    "with the toast off, /up toasts says so instead of drawing (got: " .. out:gsub("\n", " | "):sub(1, 200) .. ")")
  check(st and st.fired == 0, "nothing was drawn while the toast is off (fired=" .. tostring(st and st.fired) .. ")")
end)

print((failed == 0 and "toast_test_spec: ok" or (failed .. " check(s) failed")))
if failed > 0 then os.exit(1) end

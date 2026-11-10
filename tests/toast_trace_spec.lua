-- t_fe7a636a: the toast's transition trace, and the lifetime it promises.
--
-- Run from the repo root:  lua5.1 tests/toast_trace_spec.lua
--
-- The report on build 5455eea was "the upgrade toast is a flash": milliseconds
-- on a real client, while the previous spec measured 3750 ms out of the same
-- file. A simulated client cannot say WHICH transition ran early on the real
-- one, so this spec does the two things the card asks for:
--
--   1. It replays the TRACE path: /up toastdebug on, raise one toast, read the
--      buffer back, and check the exact line vocabulary plus the number the
--      card grades — the gap between `shown` and `finish` must be at least the
--      configured lifetime minus one tick.
--
--   2. It drives the two client behaviours that turn a toast into a flash and
--      that the 5455eea file had no answer for:
--        * a client whose AnimationGroup:Play() does nothing — the alpha was
--          just set to 0 and nothing else ever raises it;
--        * a client where something else hides the panel mid-show.
--      In both, the panel must be VISIBLE for the configured lifetime.
--
-- Every check here fails on 5455eea: there is no /up toastdebug at all, the
-- alpha stays down under a dead animation group, and a hidden panel is never
-- put back.

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
local FADE_IN = 0.18           -- TOAST.fadeIn
local TICK = 0.25              -- TOAST.tick

-- ═══ the simulated client ══════════════════════════════════════════════════
-- One clock, one set of frames and own globals per scenario, exactly like a
-- fresh login: the addon file is loaded again into that environment.
--
-- opts.stopFires  — AnimationGroup:Stop() reports OnFinished (the contract the
--                   file's own comments describe).
-- opts.playDead   — AnimationGroup:Play() does nothing at all: no animation
--                   runs, no alpha is ever written, and no OnFinished arrives.
-- Scenario 4 hides the panel from OUTSIDE the toast block on purpose: that is
-- the card's "another path hides it" half, and the addon cannot know the path.
local function scenario(opts, body)
  local stopFires = opts.stopFires == true
  local playDead = opts.playDead == true
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
      if playDead then return true end
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

  local chat, trace = {}, {}
  local function plain(s)
    return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  end
  _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m)
    local text = plain(m)
    chat[#chat + 1] = text
    local payload = text:match("^toast debug (.*)$")
    if payload then trace[#trace + 1] = payload end
  end }
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

  local visSeconds, visFirst, visLast = 0, nil, nil
  local function visibleNow()
    local f = _G.ChestAdvisorToast
    if type(f) ~= "table" or f.shown ~= true then return false end
    local a = f.GetAlpha and f.GetAlpha(f) or f.alpha
    return (tonumber(a) or 1) > 0.5
  end

  local ctx = {
    step = step,
    now = function() return clock end,
    slash = function(msg)
      for i = #chat, 1, -1 do chat[i] = nil end
      local ok2, err = pcall(SlashCmdList.CHESTADVISOR, msg)
      check(ok2, "slash '" .. tostring(msg) .. "' ran without error: " .. tostring(err))
      return table.concat(chat, "\n")
    end,
    trace = function() return trace end,
    traceText = function() return table.concat(trace, "\n") end,
    clearTrace = function() for i = #trace, 1, -1 do trace[i] = nil end end,
    state = function() return ChestAdvisor.toastState and ChestAdvisor.toastState() or nil end,
    frame = function() return _G.ChestAdvisorToast end,
    hides = function() return hides end,
    hidden = function() return #hides end,
    scan = function(verdicts) ChestAdvisor._maybeToastUpgrades(verdicts) end,
    -- Advance the clock to `t`, sampling whether the panel is really on screen
    -- (shown AND opaque enough to see) every 10 ms.
    advance = function(t)
      while clock < t - 1e-9 do
        step(0.01)
        if visibleNow() then
          visSeconds = visSeconds + 0.01
          if not visFirst then visFirst = clock end
          visLast = clock
        end
      end
    end,
    visible = function() return visibleNow() end,
    visibleSeconds = function() return visSeconds end,
    visibleFirst = function() return visFirst end,
    visibleLast = function() return visLast end,
    -- Read one field out of the first trace line matching a Lua pattern.
    lineT = function(pat)
      for _, l in ipairs(trace) do
        if l:find(pat) then return tonumber(l:match("t=(%d+%.%d+)$")), l end
      end
      return nil, nil
    end,
    countLines = function(pat)
      local n = 0
      for _, l in ipairs(trace) do if l:find(pat) then n = n + 1 end end
      return n
    end,
  }
  return body(ctx)
end

-- ═══ 1. the switch: off by default, and only /up toastdebug turns it on ════
scenario({ stopFires = true }, function(c)
  local help = c.slash("help")
  check(help:find("/up toastdebug", 1, true) ~= nil,
    "/up help documents /up toastdebug (got: " .. help:gsub("\n", " | "):sub(1, 240) .. ")")

  -- Nothing is traced until the switch is on: this is the "off by default" half.
  local out = c.slash("toasts")
  check(out:find("test toast", 1, true) ~= nil, "/up toasts still raises a toast")
  check(#c.trace() == 0,
    "with the switch off, no trace line is written (got " .. #c.trace() .. ")")

  local dump = c.slash("toastdebug dump")
  check(dump:find("no trace lines yet", 1, true) ~= nil,
    "/up toastdebug dump on an empty buffer says so (got: " .. dump:gsub("\n", " | "):sub(1, 200) .. ")")

  local on = c.slash("toastdebug")
  check(on:find("toast debug is ON", 1, true) ~= nil,
    "a bare /up toastdebug turns it on (got: " .. on:gsub("\n", " | "):sub(1, 200) .. ")")
  check(c.state() and c.state().debug == true, "toastState reports debug = true")

  local off = c.slash("toastdebug off")
  check(off:find("toast debug is off", 1, true) ~= nil,
    "/up toastdebug off turns it off (got: " .. off:gsub("\n", " | "):sub(1, 200) .. ")")
  check(c.state() and c.state().debug == false, "toastState reports debug = false")

  local on2 = c.slash("toastdebug on")
  check(on2:find("toast debug is ON", 1, true) ~= nil, "/up toastdebug on turns it on")
  c.advance(4.5)
end)

-- ═══ 2. the trace names every transition, in the card's vocabulary ════════
scenario({ stopFires = true }, function(c)
  c.slash("toastdebug on")
  c.slash("toasts")
  c.advance(4.5)

  local text = c.traceText()
  check(c.countLines("^show id=%d+ ") > 0, "trace has `show id=<n>` (trace: " .. text:gsub("\n", " | "):sub(1, 300) .. ")")
  check(c.countLines("^shown id=%d+ alpha=%d+%.%d+ ") > 0, "trace has `shown id=<n> alpha=<a>`")
  check(c.countLines("^fadeIn play id=%d+ ") > 0, "trace has `fadeIn play id=<n>`")
  check(c.countLines("^animation finished: group=fadeIn id=%d+ fadeFor=") > 0,
    "trace has the fade-in group's OnFinished line")
  check(c.countLines("^animation finished: group=fadeOut id=%d+ fadeFor=%d+ ") > 0,
    "trace has the fade-out group's OnFinished line WITH the show id it is armed for")
  check(c.countLines("^tick id=%d+ left=%d+%.%d+ ") > 0, "trace has `tick id=<n> left=<seconds>`")
  check(c.countLines("^expire id=%d+ reason=timer ") > 0, "trace has `expire ... reason=timer`")
  check(c.countLines("^finish id=%d+ reason=fadeOnFinished lifeLeft=%d+%.%d+ ") > 0,
    "trace has `finish ... reason=fadeOnFinished lifeLeft=<seconds>`")

  -- At most one tick line per second: the lifetime is 3.5 s, so 3 or 4 lines.
  local ticks = c.countLines("^tick id=")
  check(ticks <= math.ceil(DEFAULT_LIFETIME) + 1,
    "tick lines are throttled to one per second (got " .. ticks .. " over " .. DEFAULT_LIFETIME .. "s)")

  -- THE NUMBER THE CARD GRADES: shown -> finish lasts the configured lifetime.
  local tShown = c.lineT("^shown id=")
  local tFinish = c.lineT("^finish id=")
  check(type(tShown) == "number" and type(tFinish) == "number",
    "the trace carries both `shown` and `finish` (shown=" .. tostring(tShown) .. " finish=" .. tostring(tFinish) .. ")")
  if type(tShown) == "number" and type(tFinish) == "number" then
    print(string.format("  trace: shown at %.3f, finish at %.3f -> %.0f ms on screen (configured %.2fs)",
      tShown, tFinish, (tFinish - tShown) * 1000, DEFAULT_LIFETIME))
    check(tFinish - tShown >= DEFAULT_LIFETIME - TICK,
      string.format("shown -> finish is at least the lifetime minus one tick (%.3f s, want >= %.3f)",
        tFinish - tShown, DEFAULT_LIFETIME - TICK))
    check(tFinish - tShown <= DEFAULT_LIFETIME + FADE_OUT + TICK,
      string.format("shown -> finish is not much longer than lifetime + fade-out (%.3f s)", tFinish - tShown))
  end

  -- The panel really was on screen for that time, not just claimed to be.
  check(c.visibleSeconds() >= DEFAULT_LIFETIME - TICK,
    string.format("the panel was visible for %.2fs (want >= %.2fs)",
      c.visibleSeconds(), DEFAULT_LIFETIME - TICK))

  -- /up diag carries the switch and the repair counters.
  local diag = c.slash("diag")
  check(diag:find("trace: ON", 1, true) ~= nil, "/up diag reports the trace switch (got: "
    .. diag:gsub("\n", " | "):sub(1, 400) .. ")")
  check(diag:find("revived this session: 0", 1, true) ~= nil, "/up diag reports the revive counter")
  check(diag:find("alpha restored: 0", 1, true) ~= nil, "/up diag reports the alpha-restore counter")

  -- …and the buffer can be read back afterwards, which is the whole point.
  local dump = c.slash("toastdebug dump")
  check(dump:find("finish id=", 1, true) ~= nil,
    "/up toastdebug dump prints the last lines back (got: " .. dump:gsub("\n", " | "):sub(1, 200) .. ")")
end)

-- ═══ 3. a client whose fade-in animation does nothing ══════════════════════
-- toastPlayFadeIn sets the alpha to 0 and relies on the animation to raise it.
-- On this client the group was Stopped and Played in one frame, which the file
-- itself documents as able to drop the animation: the panel then stays at
-- alpha 0 for the whole show — the show is real, the toast is invisible, and
-- the only frame anyone sees is the one before the set. That is a flash.
scenario({ stopFires = true, playDead = true }, function(c)
  c.slash("toastdebug on")
  c.slash("toasts")
  c.advance(1.0)
  check(c.visible() == true,
    "the panel is visible one second in even though the fade-in never ran (alpha="
      .. tostring(c.frame() and c.frame().alpha) .. ")")
  c.advance(4.5)
  check(c.visibleSeconds() >= DEFAULT_LIFETIME - TICK,
    string.format("a dead fade-in still leaves the panel up for the lifetime (visible %.2fs, want >= %.2fs)",
      c.visibleSeconds(), DEFAULT_LIFETIME - TICK))
  local restoreT = c.lineT("^alpha restore id=")
  check(type(restoreT) == "number", "the trace names the alpha repair (lines: "
    .. c.traceText():gsub("\n", " | "):sub(1, 300) .. ")")
  if type(restoreT) == "number" then
    print(string.format("  dead fade-in: alpha restored at %.3f, visible %.2fs of %.2fs",
      restoreT, c.visibleSeconds(), DEFAULT_LIFETIME))
    check(restoreT <= FADE_IN + TICK,
      string.format("the alpha is restored right after the fade-in should have ended (at %.3f)", restoreT))
  end
  check(c.countLines("^finish id=%d+ reason=") > 0, "the show still ends through the one finish step")
end)

-- ═══ 4. something else hides the panel during a live show ══════════════════
-- The card's other half: "either another path hides the panel". Whatever it is,
-- a live show must not be eaten by it: the panel comes back and the show still
-- runs to its deadline.
scenario({ stopFires = true }, function(c)
  c.slash("toastdebug on")
  c.slash("toasts")
  c.advance(0.4)
  -- The hide is the client's, not the addon's.
  local f = c.frame()
  if f then f:Hide() end
  check(c.visible() == false, "the rogue hide took the panel off screen")
  c.advance(1.0)
  check(c.visible() == true, "the next tick put the panel back on screen")
  c.advance(4.5)
  check(c.countLines("^revive id=%d+ ") > 0, "the trace names the revive (lines: "
    .. c.traceText():gsub("\n", " | "):sub(1, 300) .. ")")
  local tFinish = c.lineT("^finish id=")
  check(type(tFinish) == "number", "the show still finished")
  if type(tFinish) == "number" then
    print(string.format("  rogue hide at 0.400: revived, finish at %.3f", tFinish))
    check(tFinish >= DEFAULT_LIFETIME - TICK,
      string.format("a hidden panel does not shorten the show (finish at %.3f, want >= %.3f)",
        tFinish, DEFAULT_LIFETIME - TICK))
  end
  check(c.visibleSeconds() >= DEFAULT_LIFETIME - 2 * TICK,
    string.format("the panel was visible for nearly the whole life despite the hide (%.2fs)",
      c.visibleSeconds()))
end)

-- ═══ 5. a scan during the fade-out must not cut the fade short ═════════════
-- maybeToastUpgrades finished a toast whose `lifetimeLeft <= 0`, which is true
-- for the WHOLE fade-out window (0.25 s). A scan landing there ended the show on
-- the spot. The trace has to show which path ended a show, and the fade now
-- belongs to the expiry that armed it.
scenario({ stopFires = true }, function(c)
  c.scan({})                                   -- take the login baseline
  c.slash("toastdebug on")
  c.slash("toasts")
  local before = c.hidden()
  c.advance(DEFAULT_LIFETIME + 0.05)            -- into the fade-out window
  c.scan({ ["[Looted-During-Fade]"] = { verdict = "UPGRADE", id = 101, bag = 0, slot = 2 } })
  c.advance(4.6)
  local hs = c.hides()
  check(#hs > before, "the panel was hidden at least once")
  if #hs > before then
    local at = hs[before + 1]
    print(string.format("  scan during the fade-out: first hide at %.3f (expiry was %.2f, fade ends %.2f)",
      at, DEFAULT_LIFETIME, DEFAULT_LIFETIME + FADE_OUT))
    check(at >= DEFAULT_LIFETIME + FADE_OUT - 0.02,
      string.format("a scan landing in the fade-out did not cut it short (hide at %.3f)", at))
  end
  check(c.countLines("^finish id=%d+ reason=rescan") == 0,
    "no show was ended by the rescan path (lines: " .. c.traceText():gsub("\n", " | "):sub(1, 300) .. ")")
  local st = c.state()
  check(st and st.fired >= 2, "the queued upgrade rotated in afterwards (fired="
    .. tostring(st and st.fired) .. ")")
end)

-- ═══ 6. a scan while a toast is LIVE never ends it ═════════════════════════
scenario({ stopFires = true }, function(c)
  c.scan({})
  c.slash("toastdebug on")
  c.slash("toasts")
  c.advance(0.5)
  c.scan({ ["[Looted-Mid-Show]"] = { verdict = "UPGRADE", id = 101, bag = 0, slot = 2 } })
  local st = c.state()
  check(st and st.shown == true, "the toast is still up after the scan")
  check(st and st.queue == 1, "the scan's upgrade joined the queue (queued="
    .. tostring(st and st.queue) .. ")")
  c.advance(4.6)
  local tShown = c.lineT("^shown id=")
  local tFinish = c.lineT("^finish id=")
  check(type(tShown) == "number" and type(tFinish) == "number", "both trace stamps are present")
  if type(tShown) == "number" and type(tFinish) == "number" then
    print(string.format("  scan mid-show at 0.500: shown %.3f -> finish %.3f (%.0f ms)",
      tShown, tFinish, (tFinish - tShown) * 1000))
    check(tFinish - tShown >= DEFAULT_LIFETIME - TICK,
      "a mid-show scan does not shorten the show")
  end
  local st2 = c.state()
  check(st2 and st2.fired == 2, "the queued upgrade then rotated in (fired="
    .. tostring(st2 and st2.fired) .. ")")
end)

-- ═══ 7. the setting can take a live toast down — and says so ══════════════
-- /up toast off clears the panel through maybeToastUpgrades. That is a real end
-- path, so it reads in the same vocabulary: a SavedVariables value that says
-- "off" would otherwise look exactly like a flash.
scenario({ stopFires = true }, function(c)
  c.slash("toastdebug on")
  c.slash("toasts")
  c.advance(1.0)
  check(c.visible() == true, "the toast is up before the setting changes")
  ChestAdvisorDB.toast = ChestAdvisorDB.toast or {}
  ChestAdvisorDB.toast.enabled = false
  c.scan({})
  check(c.visible() == false, "turning the toast off takes the panel down")
  check(c.countLines("^expire id=%d+ reason=other ") > 0,
    "the trace names the setting as the reason (lines: "
      .. c.traceText():gsub("\n", " | "):sub(1, 300) .. ")")
  c.advance(3.0)
  check(c.visible() == false, "nothing revives a toast that the setting turned off")
end)

print((failed == 0 and "toast_trace_spec: ok" or (failed .. " check(s) failed")))
if failed > 0 then os.exit(1) end

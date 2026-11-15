-- tools/probe_hosted_body.lua — look at what the hosted Touchstone body DRAWS.
--
-- Card t_07f778ca, review 2. The specs asserted the pack's own chrome and the
-- body's outer backdrop; they never asserted the RENDERED tree under the body,
-- so the body's inner content frame kept painting its own border and its own
-- title bar survived on the live client (the pack hid it by measuring a child's
-- height, which the harness and the client disagreed about).
--
-- This probe ASSERTS NOTHING. It opens the window through the live path —
-- W.Open("touchstone"), the same call the tab renderer makes — and prints every
-- frame and fontstring under the body with the three things that decide what a
-- player sees: is it shown (through every ancestor), does its backdrop paint a
-- border, and what colour is its text. The specs are the assertions; this is the
-- evidence they are aimed at.
--
--   lua5.1 tools/probe_hosted_body.lua
--
-- Run it with the Lua 5.1 on this box:
--   %LOCALAPPDATA%\Programs\Lua51\bin\lua5.1.exe tools/probe_hosted_body.lua

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tools/[^/]+$") or "."

local C = dofile(root .. "/tests/support/wowclient.lua")
C.Install({ width = 1920, height = 1080 })

local pkg = {}
local function loadFile(path)
  local chunk, err = loadfile(root .. "/MightiePack/" .. path)
  if not chunk then error("loadfile " .. path .. ": " .. tostring(err)) end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  if not ok then error("load " .. path .. ": " .. tostring(e)) end
end

MightiePackDB = { modules = { Touchstone = true }, seen = { firstRun = true }, bugCount = 0 }
StatForgeDB = { ui = { scale = 1 }, firstUse = false }

local toc = assert(io.open(root .. "/MightiePack/MightiePack.toc", "r"))
local tocText = toc:read("*a")
toc:close()
for line in tocText:gmatch("[^\r\n]+") do
  local t = line:gsub("^%s+", ""):gsub("%s+$", "")
  if t ~= "" and not t:match("^##") then loadFile(t) end
end
pcall(pkg.EnableModules)

local W, T = pkg.Window, pkg.Theme
W.Open("touchstone")

local SF = rawget(_G, "StatForge")
local body = rawget(_G, "StatForgeMainFrame")
if type(body) ~= "table" then
  print("probe: StatForgeMainFrame does not exist — the body never attached")
  os.exit(1)
end

local function hex(c, a)
  if type(c) ~= "table" then return "none" end
  return string.format("#%02x%02x%02x@%.2f",
    math.floor((c[1] or 0) * 255 + 0.5),
    math.floor((c[2] or 0) * 255 + 0.5),
    math.floor((c[3] or 0) * 255 + 0.5),
    c[4] or 1)
end

local function file(p) return type(p) == "string" and p:gsub("^Interface\\Buttons\\", "") or "nil" end

local function describe(f, path, depth)
  local bd = f.backdrop
  local bits = {}
  bits[#bits + 1] = string.rep("  ", depth) .. path
  bits[#bits + 1] = f.kind or "Frame"
  if f.Name then bits[#bits + 1] = "name=" .. tostring(f.Name) end
  bits[#bits + 1] = "selfShown=" .. tostring(f.shown)
  bits[#bits + 1] = "shown=" .. tostring(C.Visible(f))
  if type(bd) == "table" then
    bits[#bits + 1] = "bg=" .. file(bd.bgFile) .. " edge=" .. file(bd.edgeFile)
    if type(f.backdropColor) == "table" then bits[#bits + 1] = "fill=" .. hex(f.backdropColor) end
  end
  if f.kind == "FontString" then
    local text = tostring(f.text or "")
    if #text > 42 then text = text:sub(1, 42) .. "…" end
    bits[#bits + 1] = "text=" .. string.format("%q", text)
    bits[#bits + 1] = "color=" .. hex(f.color)
  end
  print(table.concat(bits, "  "))
  for i, child in ipairs(f.children or {}) do
    describe(child, path .. "[" .. i .. "]", depth + 1)
  end
end

print("== hosted body: " .. tostring(body:GetName()) .. " parent=" ..
  tostring(body:GetParent() and body:GetParent().Name or body:GetParent()))
local bd = body.backdrop
if type(bd) == "table" then
  print(string.format("body backdrop    : bgFile=%s edgeFile=%s insets=%s/%s/%s/%s",
    file(bd.bgFile), file(bd.edgeFile),
    tostring(bd.insets and bd.insets.left), tostring(bd.insets and bd.insets.right),
    tostring(bd.insets and bd.insets.top), tostring(bd.insets and bd.insets.bottom)))
end
print("== the tree the body draws")
for i, child in ipairs(body:GetChildren()) do
  describe(child, "child[" .. i .. "]", 0)
end

-- The accent the body ships, for comparison against anything the probe prints.
if type(SF) == "table" and type(SF.Colors) == "table" then
  print("== vendored accent: " .. hex(SF.Colors.accent))
end
print("== pack ledger accent: " .. hex({ T.R("ledgerAccent") }))

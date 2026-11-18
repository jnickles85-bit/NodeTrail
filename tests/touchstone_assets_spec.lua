-- Asset-path invariant for the vendored Touchstone.
--
-- Upstream used to hardcode the art path as Interface\AddOns\Touchstone\..., which
-- is where the standalone addon lived. Once the files are vendored under
-- MightiePack/Modules/Touchstone/, that path resolves to nothing: the bag arrow and
-- the toast arrow render as empty textures, so an upgrade is judged (the item
-- tooltip says "Touchstone: Upgrade") but never marked in the bags.
--
-- THE MECHANISM MOVED UPSTREAM (StatForge card t_a875a586, pin eebfba4): every
-- texture is now resolved at USE time through SF.AssetPath, and a host points the
-- root at its own folder once with SF.SetAssetRoot. So the invariant is no longer
-- "the file defines a constant" — it is:
--
--   1. no vendored file builds a marker texture path of its own;
--   2. every file that names marker.tga resolves it through SF.AssetPath (or the
--      pin's own assetPath() helper), never by concatenating a literal;
--   3. the pack claims the root, once, from Modules.lua, and the root is the
--      folder these files actually live in;
--   4. the retired pack constant (MIGHTIEPACK_TOUCHSTONE_ASSETS) is gone: a file
--      that still carried it would be a second source of truth for the same path.
--
-- Fails on build 51656e0, which still hardcoded the standalone path.

local here = (arg and arg[0] or "tests/touchstone_assets_spec.lua"):match("^(.*)[/\\][^/\\]*$") or "."
local root = here:gsub("[/\\]tests$", "")
if root == "tests" then root = "." end
local dir = root .. "/MightiePack/Modules/Touchstone"

local fails = 0
local function check(cond, msg)
  if not cond then
    print("FAIL: " .. msg)
    fails = fails + 1
  end
end

local function readAll(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local files = {}
-- GNU find on CI (Linux). A Windows checkout has no GNU find — `find` there is a
-- text-search tool — so `dir /b /s` is the second attempt. Same two forms the
-- standalone addon's tree-walking spec uses.
local function collect(cmd, pattern)
  local got = {}
  local ok, pipe = pcall(io.popen, cmd)
  if not ok or not pipe then return got end
  for line in pipe:lines() do
    local path = line:gsub("\\", "/"):gsub("%s+$", "")
    if path:match(pattern) then got[#got + 1] = path end
  end
  pipe:close()
  return got
end
files = collect('find "' .. dir .. '" -name "*.lua" 2>/dev/null', "%.lua$")
if #files == 0 then
  files = collect('dir /b /s "' .. dir:gsub("/", "\\") .. '\\*.lua" 2>nul', "%.lua$")
end
table.sort(files)
check(#files > 0, "found vendored Touchstone lua files under " .. dir)

local usesMarker = 0
for _, path in ipairs(files) do
  local src = readAll(path)
  check(src ~= nil, "readable: " .. path)
  if src then
    local short = path:match("([^/\\]+)$")
    check(src:find("MIGHTIEPACK_TOUCHSTONE_ASSETS", 1, true) == nil,
      short .. ": does not carry the retired pack asset constant "
        .. "(the pin resolves paths through SF.AssetPath)")
    if src:find("marker.tga", 1, true) then
      usesMarker = usesMarker + 1
      local viaSeam = src:find("SF.AssetPath(", 1, true) ~= nil
        or src:find("assetPath(", 1, true) ~= nil
      check(viaSeam,
        short .. ": marker.tga is resolved through SF.AssetPath, not concatenated")
    end
  end
end
check(usesMarker >= 2,
  "at least the bag/toast file and the upgrades tab reference marker.tga (got "
    .. usesMarker .. ")")

-- The pack claims the root, once, and it is the folder these files live in.
local modules = readAll(root .. "/MightiePack/Modules.lua") or ""
check(modules:find("sf%.SetAssetRoot", 1) ~= nil,
  "Modules.lua claims the asset root through the pin's SF.SetAssetRoot")
check(modules:find("Modules\\\\Touchstone\\\\ChestAdvisor\\\\", 1, true) ~= nil,
  "the claimed root is the vendored folder (Modules\\Touchstone\\ChestAdvisor\\)")

-- A claim that is never reached is not a claim: the module's Enable() must call it.
check(modules:find("claimPresentation%(%)", 1) ~= nil,
  "the module's Enable() calls claimPresentation()")

if fails == 0 then
  print("touchstone_assets_spec: ok")
else
  print(("touchstone_assets_spec: %d failure(s)"):format(fails))
  os.exit(1)
end

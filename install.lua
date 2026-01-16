local DEFAULT_BASE_URL = "https://raw.githubusercontent.com/RobertC02/CC-StargateTestScript/main"
local MANIFEST_PATH = "manifest.json"
local TEMP_MANIFEST = "stargate/.manifest.tmp"

local args = { ... }
local baseUrl = args[1] or DEFAULT_BASE_URL
if baseUrl:sub(-1) == "/" then
  baseUrl = baseUrl:sub(1, -2)
end

local function ensureDir(path)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
end

local function readFile(path)
  local handle = fs.open(path, "r")
  if not handle then
    return nil
  end
  local content = handle.readAll()
  handle.close()
  return content
end

local function download(url, path)
  if fs.exists(path) then
    fs.delete(path)
  end
  ensureDir(path)
  local ok = shell.run("wget", url, path)
  if not ok then
    error("Failed to download: " .. url)
  end
end

download(baseUrl .. "/" .. MANIFEST_PATH, TEMP_MANIFEST)

local manifest = textutils.unserializeJSON(readFile(TEMP_MANIFEST) or "")
if type(manifest) ~= "table" or type(manifest.files) ~= "table" then
  error("Invalid manifest")
end

for _, file in ipairs(manifest.files) do
  if type(file) == "table" and type(file.source) == "string" then
    local dest = file.dest or file.source
    download(baseUrl .. "/" .. file.source, dest)
  end
end

if fs.exists(TEMP_MANIFEST) then
  fs.delete(TEMP_MANIFEST)
end

print("Install complete.")

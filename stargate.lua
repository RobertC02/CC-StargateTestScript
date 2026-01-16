-- Stargate control program for Advanced Crystal Interface
-- GUI-driven via monitor

local DATA_DIR = "stargate"
local CONFIG_PATH = DATA_DIR .. "/config.json"
local ADDR_PATH = DATA_DIR .. "/addresses.json"

local defaultConfig = {
  whitelistEnabled = true,
  terminateIncoming = false,
  alarmLatched = false,
  alarmSide = "bottom",
  textScale = 0.5
}

local validSides = {
  top = true,
  bottom = true,
  left = true,
  right = true,
  front = true,
  back = true
}

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

local function ensureDir()
  if not fs.exists(DATA_DIR) then
    fs.makeDir(DATA_DIR)
  end
end

local function loadJson(path, defaultValue)
  if not fs.exists(path) then
    return defaultValue
  end
  local handle = fs.open(path, "r")
  if not handle then
    return defaultValue
  end
  local content = handle.readAll()
  handle.close()
  local ok, data = pcall(textutils.unserializeJSON, content)
  if ok and type(data) == "table" then
    return data
  end
  return defaultValue
end

local function saveJson(path, data)
  ensureDir()
  local handle = fs.open(path, "w")
  handle.write(textutils.serializeJSON(data))
  handle.close()
end

local function normalizeConfig(cfg)
  cfg = type(cfg) == "table" and cfg or {}
  if type(cfg.whitelistEnabled) ~= "boolean" then
    cfg.whitelistEnabled = defaultConfig.whitelistEnabled
  end
  if type(cfg.terminateIncoming) ~= "boolean" then
    cfg.terminateIncoming = defaultConfig.terminateIncoming
  end
  if type(cfg.alarmLatched) ~= "boolean" then
    cfg.alarmLatched = defaultConfig.alarmLatched
  end
  if type(cfg.alarmSide) ~= "string" or not validSides[cfg.alarmSide] then
    cfg.alarmSide = defaultConfig.alarmSide
  end
  if type(cfg.textScale) ~= "number" then
    cfg.textScale = defaultConfig.textScale
  end
  return cfg
end

local function addressToString(address)
  if type(address) ~= "table" or #address == 0 or #address > 8 then
    return "-"
  end
  local s = "-"
  for i = 1, #address do
    s = s .. tostring(address[i]) .. "-"
  end
  return s
end

local function normalizeAddressEntry(entry)
  if type(entry) ~= "table" then
    return nil
  end
  local name = type(entry.name) == "string" and entry.name or ""
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  local addr = {}
  if type(entry.address) == "table" then
    for _, v in ipairs(entry.address) do
      local n = tonumber(v)
      if n and n >= 1 and n <= 38 then
        addr[#addr + 1] = math.floor(n)
      end
    end
  end
  while #addr > 8 do
    table.remove(addr)
  end
  while #addr > 0 and addr[#addr] == 0 do
    table.remove(addr)
  end
  local whitelisted = entry.whitelisted == true
  return { name = name, address = addr, whitelisted = whitelisted }
end

local function normalizeAddresses(list)
  local result = {}
  if type(list) == "table" then
    for _, entry in ipairs(list) do
      local clean = normalizeAddressEntry(entry)
      if clean then
        result[#result + 1] = clean
      end
    end
  end
  return result
end

ensureDir()
local config = normalizeConfig(loadJson(CONFIG_PATH, defaultConfig))
local addresses = normalizeAddresses(loadJson(ADDR_PATH, {}))

local function saveConfig()
  saveJson(CONFIG_PATH, config)
end

local function saveAddresses()
  saveJson(ADDR_PATH, addresses)
end

local interface = peripheral.find("advanced_crystal_interface")
if not interface then
  error("Advanced crystal interface not connected")
end

local monitor = peripheral.find("monitor")
local screen = monitor or term

if monitor then
  monitor.setTextScale(config.textScale or 0.5)
end

local screenW, screenH = screen.getSize()
local layout = {
  w = screenW,
  h = screenH,
  topH = 3,
  bottomH = 1,
  navW = 18,
  statusW = 28
}
layout.mainX = layout.navW + 1
layout.mainY = layout.topH + 1
layout.mainW = layout.w - layout.navW - layout.statusW
layout.mainH = layout.h - layout.topH - layout.bottomH
layout.statusX = layout.w - layout.statusW + 1
layout.bottomY = layout.h

local theme = {
  bg = colors.black,
  panel = colors.gray,
  panelDark = colors.lightGray,
  text = colors.white,
  muted = colors.lightGray,
  accent = colors.blue,
  accent2 = colors.green,
  warn = colors.orange,
  danger = colors.red,
  button = colors.blue,
  buttonAlt = colors.gray,
  buttonDisabled = colors.black
}

local state = {
  page = "home",
  message = "",
  messageUntil = 0,
  selectedIndex = 1,
  scroll = 0,
  dialRequest = nil,
  dialing = false,
  alarmActive = false,
  deleteConfirmIndex = nil,
  edit = nil,
  nameBuffer = "",
  status = {
    connected = false,
    dialingOut = false,
    wormholeOpen = false,
    irisPercent = 0,
    chevrons = 0,
    filterType = 0,
    connectedAddressStr = "-",
    localAddressStr = "-"
  }
}

local function safeCall(fn, ...)
  local ok, result = pcall(fn, ...)
  if ok then
    return result
  end
  return nil
end

do
  local localAddr = safeCall(interface.getLocalAddress)
  if type(localAddr) == "table" then
    state.status.localAddressStr = addressToString(localAddr)
  end
end

local function setMessage(msg, duration)
  state.message = msg or ""
  state.messageUntil = os.clock() + (duration or 4)
end

local function setAlarm(on, forceOff)
  if not on and config.alarmLatched and not forceOff then
    return
  end
  state.alarmActive = on
  if validSides[config.alarmSide] then
    redstone.setOutput(config.alarmSide, on)
  end
end

local function resetAlarm()
  setAlarm(false, true)
end

local function applyWhitelist()
  local ok = pcall(interface.setFilterType, config.whitelistEnabled and 1 or 0)
  if not ok then
    setMessage("Failed to set filter type", 5)
    return
  end
  if not config.whitelistEnabled then
    return
  end
  pcall(interface.clearWhitelist)
  for _, entry in ipairs(addresses) do
    if entry.whitelisted and type(entry.address) == "table" then
      local len = #entry.address
      if len >= 6 and len <= 8 then
        pcall(interface.addToWhitelist, entry.address)
      end
    end
  end
end

local function buildDialAddress(addr)
  local dial = {}
  for i = 1, #addr do
    dial[i] = addr[i]
  end
  if #dial > 0 and dial[#dial] ~= 0 then
    dial[#dial + 1] = 0
  end
  return dial
end

local function updateStatus()
  state.status.connected = safeCall(interface.isStargateConnected) or false
  state.status.dialingOut = safeCall(interface.isStargateDialingOut) or false
  state.status.wormholeOpen = safeCall(interface.isWormholeOpen) or false
  local iris = safeCall(interface.getIrisProgressPercentage) or 0
  state.status.irisPercent = math.floor(iris + 0.5)
  state.status.chevrons = safeCall(interface.getChevronsEngaged) or 0
  state.status.filterType = safeCall(interface.getFilterType) or 0
  if state.status.wormholeOpen then
    local addr = safeCall(interface.getConnectedAddress) or {}
    state.status.connectedAddressStr = addressToString(addr)
  else
    state.status.connectedAddressStr = "-"
  end
end

local function dialAddress(entry)
  if not entry or type(entry.address) ~= "table" then
    setMessage("Invalid address", 4)
    return false
  end
  local len = #entry.address
  if len < 6 or len > 8 then
    setMessage("Address length must be 6-8", 4)
    return false
  end
  if config.whitelistEnabled and not entry.whitelisted then
    setMessage("Entry not whitelisted", 4)
    return false
  end
  if safeCall(interface.isStargateConnected) then
    setMessage("Stargate already connected", 4)
    return false
  end

  safeCall(interface.closeIris)
  local dial = buildDialAddress(entry.address)
  for i = 1, #dial do
    local ok = pcall(interface.engageSymbol, dial[i])
    if not ok then
      setMessage("Dial failed at symbol " .. tostring(dial[i]), 5)
      return false
    end
    sleep(0.5)
  end

  local timeout = os.clock() + 30
  while os.clock() < timeout do
    if safeCall(interface.isWormholeOpen) then
      safeCall(interface.openIris)
      return true
    end
    if not safeCall(interface.isStargateConnected) and (safeCall(interface.getChevronsEngaged) or 0) == 0 then
      break
    end
    sleep(0.1)
  end
  setMessage("Dial timed out", 5)
  return false
end

local function ensureSelection()
  if #addresses == 0 then
    state.selectedIndex = 0
    state.scroll = 0
    return
  end
  if state.selectedIndex < 1 then
    state.selectedIndex = 1
  end
  if state.selectedIndex > #addresses then
    state.selectedIndex = #addresses
  end
end

local function getListMetrics()
  local listHeaderY = layout.mainY
  local actionsH = 3
  local listH = layout.mainH - actionsH - 1
  if listH < 1 then
    listH = 1
  end
  return {
    headerY = listHeaderY,
    listY = listHeaderY + 1,
    listH = listH,
    actionsY = listHeaderY + 1 + listH,
    actionsH = actionsH
  }
end

local function adjustScroll()
  ensureSelection()
  if #addresses == 0 then
    state.scroll = 0
    return
  end
  local metrics = getListMetrics()
  if state.selectedIndex < state.scroll + 1 then
    state.scroll = state.selectedIndex - 1
  end
  if state.selectedIndex > state.scroll + metrics.listH then
    state.scroll = state.selectedIndex - metrics.listH
  end
  if state.scroll < 0 then
    state.scroll = 0
  end
  local maxScroll = math.max(0, #addresses - metrics.listH)
  if state.scroll > maxScroll then
    state.scroll = maxScroll
  end
end

local function startEdit(index)
  local entry
  if index and addresses[index] then
    entry = normalizeAddressEntry(addresses[index])
  else
    entry = { name = "", address = {}, whitelisted = true }
  end
  state.edit = {
    index = index,
    entry = entry,
    symbol = 1
  }
  state.page = "edit"
end

local function saveEdit()
  if not state.edit then
    return
  end
  local entry = state.edit.entry
  entry.name = (entry.name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local len = #entry.address
  if len < 6 or len > 8 then
    setMessage("Address length must be 6-8", 5)
    return
  end
  if entry.name == "" then
    entry.name = addressToString(entry.address)
  end
  if state.edit.index then
    addresses[state.edit.index] = entry
    state.selectedIndex = state.edit.index
  else
    addresses[#addresses + 1] = entry
    state.selectedIndex = #addresses
  end
  saveAddresses()
  if config.whitelistEnabled then
    applyWhitelist()
  end
  state.page = "addresses"
  state.edit = nil
  adjustScroll()
  setMessage("Address saved", 3)
end

local function cancelEdit()
  state.page = "addresses"
  state.edit = nil
  setMessage("Edit canceled", 2)
end

local function startNameInput()
  if not state.edit then
    return
  end
  state.nameBuffer = state.edit.entry.name or ""
  state.page = "name"
end

local function commitNameInput()
  if state.edit then
    state.edit.entry.name = state.nameBuffer
  end
  state.page = "edit"
end

local function cancelNameInput()
  state.page = "edit"
end

local function dialSelected()
  if state.dialRequest or state.dialing then
    setMessage("Dialer busy", 3)
    return
  end
  if state.selectedIndex == 0 or not addresses[state.selectedIndex] then
    setMessage("No address selected", 3)
    return
  end
  state.dialRequest = state.selectedIndex
  setMessage("Dial queued", 2)
end

local function toggleWhitelistEnabled()
  config.whitelistEnabled = not config.whitelistEnabled
  saveConfig()
  applyWhitelist()
  setMessage("Whitelist " .. (config.whitelistEnabled and "enabled" or "disabled"), 3)
end

local function toggleTerminateIncoming()
  config.terminateIncoming = not config.terminateIncoming
  saveConfig()
  setMessage("Terminate incoming " .. (config.terminateIncoming and "enabled" or "disabled"), 3)
end

local function toggleAlarmLatched()
  config.alarmLatched = not config.alarmLatched
  saveConfig()
  setMessage("Alarm latch " .. (config.alarmLatched and "enabled" or "disabled"), 3)
end

local function cycleAlarmSide()
  local sides = { "bottom", "top", "left", "right", "front", "back" }
  local currentIndex = 1
  for i = 1, #sides do
    if sides[i] == config.alarmSide then
      currentIndex = i
      break
    end
  end
  local nextSide = sides[(currentIndex % #sides) + 1]
  redstone.setOutput(config.alarmSide, false)
  config.alarmSide = nextSide
  redstone.setOutput(config.alarmSide, state.alarmActive)
  saveConfig()
  setMessage("Alarm side: " .. config.alarmSide, 3)
end

local function toggleSelectedWhitelist()
  if state.selectedIndex == 0 or not addresses[state.selectedIndex] then
    setMessage("No address selected", 3)
    return
  end
  local entry = addresses[state.selectedIndex]
  entry.whitelisted = not entry.whitelisted
  saveAddresses()
  if config.whitelistEnabled then
    applyWhitelist()
  end
  setMessage("Whitelist set to " .. (entry.whitelisted and "ON" or "OFF"), 3)
end

local function deleteSelected()
  if state.selectedIndex == 0 or not addresses[state.selectedIndex] then
    setMessage("No address selected", 3)
    return
  end
  if state.deleteConfirmIndex == state.selectedIndex then
    table.remove(addresses, state.selectedIndex)
    state.deleteConfirmIndex = nil
    saveAddresses()
    if config.whitelistEnabled then
      applyWhitelist()
    end
    ensureSelection()
    adjustScroll()
    setMessage("Address deleted", 3)
  else
    state.deleteConfirmIndex = state.selectedIndex
    setMessage("Press Delete again to confirm", 4)
  end
end

local function fillRect(x, y, w, h, bg)
  if w <= 0 or h <= 0 then
    return
  end
  screen.setBackgroundColor(bg)
  local line = string.rep(" ", w)
  for yy = y, y + h - 1 do
    screen.setCursorPos(x, yy)
    screen.write(line)
  end
end

local function writeAt(x, y, text, fg, bg)
  if bg then
    screen.setBackgroundColor(bg)
  end
  if fg then
    screen.setTextColor(fg)
  end
  screen.setCursorPos(x, y)
  screen.write(text)
end

local buttons = {}

local function resetButtons()
  buttons = {}
end

local function drawButton(id, x, y, w, h, label, opts)
  opts = opts or {}
  local enabled = opts.enabled ~= false
  local bg = opts.bg or theme.button
  local fg = opts.fg or theme.text
  if not enabled then
    bg = theme.buttonDisabled
    fg = theme.muted
  end
  fillRect(x, y, w, h, bg)
  local text = label
  if #text > w then
    text = text:sub(1, w)
  end
  local labelX = x + math.floor((w - #text) / 2)
  local labelY = y + math.floor(h / 2)
  writeAt(labelX, labelY, text, fg, bg)
  if enabled and opts.onClick then
    buttons[#buttons + 1] = { id = id, x = x, y = y, w = w, h = h, onClick = opts.onClick }
  end
end

local function findButton(x, y)
  for _, btn in ipairs(buttons) do
    if x >= btn.x and x <= btn.x + btn.w - 1 and y >= btn.y and y <= btn.y + btn.h - 1 then
      return btn
    end
  end
  return nil
end

local function drawHeader()
  fillRect(1, 1, layout.w, layout.topH, theme.accent)
  writeAt(2, 2, "Stargate Control", theme.text, theme.accent)
  local timeText = textutils.formatTime(os.time(), true)
  writeAt(layout.w - #timeText - 1, 2, timeText, theme.text, theme.accent)
end

local function drawNav()
  fillRect(1, layout.topH + 1, layout.navW, layout.mainH, theme.panel)
  local navEnabled = state.page == "home" or state.page == "addresses" or state.page == "settings"
  local y = layout.topH + 2
  local btnH = 3
  local btnW = layout.navW - 2

  local function navButton(label, page)
    local isActive = state.page == page
    drawButton(
      "nav_" .. page,
      2,
      y,
      btnW,
      btnH,
      label,
      {
        bg = isActive and theme.accent2 or theme.buttonAlt,
        enabled = navEnabled,
        onClick = navEnabled and function()
          state.page = page
          state.deleteConfirmIndex = nil
        end or nil
      }
    )
    y = y + btnH + 1
  end

  navButton("Home", "home")
  navButton("Addresses", "addresses")
  navButton("Settings", "settings")
end

local function drawStatus()
  fillRect(layout.statusX, layout.topH + 1, layout.statusW, layout.mainH, theme.panel)
  local x = layout.statusX + 1
  local y = layout.topH + 2
  local valueX = layout.statusX + 12

  local function line(label, value, color)
    writeAt(x, y, label .. ":", theme.muted, theme.panel)
    local v = tostring(value)
    local maxLen = layout.statusX + layout.statusW - valueX - 1
    if #v > maxLen then
      v = v:sub(1, maxLen)
    end
    writeAt(valueX, y, v, color or theme.text, theme.panel)
    y = y + 1
  end

  local connColor = state.status.connected and theme.accent2 or theme.danger
  line("Conn", state.status.connected and "YES" or "NO", connColor)
  local dir = "-"
  if state.status.connected then
    dir = state.status.dialingOut and "OUT" or "IN"
  end
  line("Dir", dir, state.status.dialingOut and theme.accent2 or theme.warn)
  line("Wormhole", state.status.wormholeOpen and "OPEN" or "CLOSED", state.status.wormholeOpen and theme.accent2 or theme.muted)
  line("Iris", tostring(state.status.irisPercent) .. "%", state.status.irisPercent == 100 and theme.danger or theme.text)
  line("Chevrons", state.status.chevrons, theme.text)
  line("Alarm", state.alarmActive and "ON" or "OFF", state.alarmActive and theme.danger or theme.muted)
  local filterText = "OFF"
  if state.status.filterType == 1 then
    filterText = "WL"
  elseif state.status.filterType == -1 then
    filterText = "BL"
  end
  line("Filter", filterText, state.status.filterType == 1 and theme.accent2 or theme.muted)
  line("Remote", state.status.connectedAddressStr, theme.text)
  line("Local", state.status.localAddressStr, theme.text)
end

local function drawHome()
  fillRect(layout.mainX, layout.mainY, layout.mainW, layout.mainH, theme.bg)
  writeAt(layout.mainX + 2, layout.mainY + 1, "Quick Actions", theme.text, theme.bg)

  local bx = layout.mainX + 2
  local by = layout.mainY + 3
  local bw = 18
  local bh = 3
  local gap = 2

  drawButton("open_iris", bx, by, bw, bh, "Open Iris", {
    onClick = function()
      safeCall(interface.openIris)
      setMessage("Iris opening", 2)
    end
  })
  drawButton("close_iris", bx + bw + gap, by, bw, bh, "Close Iris", {
    onClick = function()
      safeCall(interface.closeIris)
      setMessage("Iris closing", 2)
    end
  })
  drawButton("disconnect", bx + (bw + gap) * 2, by, bw, bh, "Disconnect", {
    onClick = function()
      local ok = safeCall(interface.disconnectStargate)
      setMessage(ok and "Disconnect requested" or "Cannot disconnect", 3)
    end
  })

  drawButton("reset_alarm", bx, by + bh + 2, bw, bh, "Reset Alarm", {
    onClick = function()
      resetAlarm()
      setMessage("Alarm reset", 2)
    end
  })
  drawButton("apply_whitelist", bx + bw + gap, by + bh + 2, bw, bh, "Apply WL", {
    onClick = function()
      applyWhitelist()
      setMessage("Whitelist applied", 2)
    end
  })

  if state.dialing then
    writeAt(layout.mainX + 2, by + bh * 2 + 6, "Dialer busy...", theme.warn, theme.bg)
  end
end

local function drawAddresses()
  fillRect(layout.mainX, layout.mainY, layout.mainW, layout.mainH, theme.bg)
  local metrics = getListMetrics()

  local colIdx = 4
  local colWL = 3
  local colName = math.floor(layout.mainW * 0.3)
  if colName < 18 then
    colName = 18
  end
  local colAddr = layout.mainW - colIdx - colWL - colName - 4
  if colAddr < 10 then
    colAddr = 10
    colName = layout.mainW - colIdx - colWL - colAddr - 4
  end

  writeAt(layout.mainX + 1, metrics.headerY, "ID", theme.muted, theme.bg)
  writeAt(layout.mainX + colIdx + 2, metrics.headerY, "Name", theme.muted, theme.bg)
  writeAt(layout.mainX + colIdx + colName + 3, metrics.headerY, "Address", theme.muted, theme.bg)
  writeAt(layout.mainX + colIdx + colName + colAddr + 4, metrics.headerY, "WL", theme.muted, theme.bg)

  for row = 0, metrics.listH - 1 do
    local index = state.scroll + row + 1
    local y = metrics.listY + row
    if index <= #addresses then
      local entry = addresses[index]
      local selected = index == state.selectedIndex
      local bg = selected and theme.panel or theme.bg
      fillRect(layout.mainX, y, layout.mainW, 1, bg)
      local idText = string.format("%02d", index)
      local nameText = entry.name or ""
      local addrText = addressToString(entry.address)
      if #nameText > colName then
        nameText = nameText:sub(1, colName)
      end
      if #addrText > colAddr then
        addrText = addrText:sub(1, colAddr)
      end
      writeAt(layout.mainX + 1, y, idText, theme.text, bg)
      writeAt(layout.mainX + colIdx + 2, y, nameText, theme.text, bg)
      writeAt(layout.mainX + colIdx + colName + 3, y, addrText, theme.text, bg)
      writeAt(layout.mainX + colIdx + colName + colAddr + 4, y, entry.whitelisted and "Y" or "N", entry.whitelisted and theme.accent2 or theme.muted, bg)
    else
      fillRect(layout.mainX, y, layout.mainW, 1, theme.bg)
    end
  end

  local buttonCount = 7
  local gap = 1
  local btnW = math.floor((layout.mainW - gap * (buttonCount - 1)) / buttonCount)
  local btnH = metrics.actionsH
  local x = layout.mainX
  local y = metrics.actionsY

  local hasSelection = state.selectedIndex > 0 and addresses[state.selectedIndex] ~= nil

  drawButton("addr_add", x, y, btnW, btnH, "Add", {
    onClick = function()
      startEdit(nil)
    end
  })
  x = x + btnW + gap
  drawButton("addr_edit", x, y, btnW, btnH, "Edit", {
    enabled = hasSelection,
    onClick = function()
      startEdit(state.selectedIndex)
    end
  })
  x = x + btnW + gap
  drawButton("addr_delete", x, y, btnW, btnH, "Delete", {
    enabled = hasSelection,
    onClick = function()
      deleteSelected()
    end
  })
  x = x + btnW + gap
  drawButton("addr_dial", x, y, btnW, btnH, "Dial", {
    enabled = hasSelection and not state.dialing,
    onClick = function()
      dialSelected()
    end
  })
  x = x + btnW + gap
  drawButton("addr_wl", x, y, btnW, btnH, "WL Toggle", {
    enabled = hasSelection,
    onClick = function()
      toggleSelectedWhitelist()
    end
  })
  x = x + btnW + gap
  drawButton("addr_up", x, y, btnW, btnH, "Up", {
    onClick = function()
      if state.selectedIndex > 1 then
        state.selectedIndex = state.selectedIndex - 1
        state.deleteConfirmIndex = nil
        adjustScroll()
      end
    end
  })
  x = x + btnW + gap
  drawButton("addr_down", x, y, btnW, btnH, "Down", {
    onClick = function()
      if state.selectedIndex < #addresses then
        state.selectedIndex = state.selectedIndex + 1
        state.deleteConfirmIndex = nil
        adjustScroll()
      end
    end
  })
end

local function drawSettings()
  fillRect(layout.mainX, layout.mainY, layout.mainW, layout.mainH, theme.bg)
  writeAt(layout.mainX + 2, layout.mainY + 1, "Settings", theme.text, theme.bg)

  local bx = layout.mainX + 2
  local by = layout.mainY + 3
  local bw = 28
  local bh = 3
  local gap = 2

  drawButton("set_whitelist", bx, by, bw, bh, "Whitelist: " .. (config.whitelistEnabled and "ON" or "OFF"), {
    onClick = function()
      toggleWhitelistEnabled()
    end
  })
  drawButton("set_terminate", bx, by + (bh + gap), bw, bh, "Terminate In: " .. (config.terminateIncoming and "ON" or "OFF"), {
    onClick = function()
      toggleTerminateIncoming()
    end
  })
  drawButton("set_latch", bx, by + (bh + gap) * 2, bw, bh, "Alarm Latch: " .. (config.alarmLatched and "ON" or "OFF"), {
    onClick = function()
      toggleAlarmLatched()
    end
  })
  drawButton("set_alarm_side", bx, by + (bh + gap) * 3, bw, bh, "Alarm Side: " .. config.alarmSide, {
    onClick = function()
      cycleAlarmSide()
    end
  })
  drawButton("set_apply", bx, by + (bh + gap) * 4, bw, bh, "Apply Whitelist", {
    onClick = function()
      applyWhitelist()
      setMessage("Whitelist applied", 2)
    end
  })
  drawButton("set_reset_alarm", bx, by + (bh + gap) * 5, bw, bh, "Reset Alarm", {
    onClick = function()
      resetAlarm()
      setMessage("Alarm reset", 2)
    end
  })
end

local function drawEdit()
  fillRect(layout.mainX, layout.mainY, layout.mainW, layout.mainH, theme.bg)
  local entry = state.edit and state.edit.entry or { name = "", address = {}, whitelisted = false }
  writeAt(layout.mainX + 2, layout.mainY + 1, state.edit and state.edit.index and "Edit Address" or "Add Address", theme.text, theme.bg)

  local x = layout.mainX + 2
  local y = layout.mainY + 3

  local nameText = entry.name
  if nameText == "" then
    nameText = "(unnamed)"
  end
  local maxNameLen = layout.mainW - 20
  if #nameText > maxNameLen then
    nameText = nameText:sub(1, maxNameLen)
  end
  writeAt(x, y, "Name: " .. nameText, theme.text, theme.bg)
  drawButton("edit_name", layout.mainX + layout.mainW - 16, y - 1, 14, 3, "Edit Name", {
    onClick = function()
      startNameInput()
    end
  })

  y = y + 2
  writeAt(x, y, "Address: " .. addressToString(entry.address), theme.text, theme.bg)
  y = y + 1
  writeAt(x, y, "Symbols: " .. table.concat(entry.address, " "), theme.muted, theme.bg)
  y = y + 1
  writeAt(x, y, "Length: " .. tostring(#entry.address) .. " (valid 6-8)", theme.muted, theme.bg)

  drawButton("edit_wl", layout.mainX + layout.mainW - 16, y - 1, 14, 3, entry.whitelisted and "WL: ON" or "WL: OFF", {
    onClick = function()
      entry.whitelisted = not entry.whitelisted
    end
  })

  local controlsY = layout.mainY + 11
  writeAt(x, controlsY, "Symbol: " .. tostring(state.edit.symbol), theme.text, theme.bg)
  local btnY = controlsY + 1
  local btnW = 6
  local btnH = 3
  local gap = 1
  drawButton("sym_minus5", x, btnY, btnW, btnH, "-5", {
    onClick = function()
      state.edit.symbol = clamp(state.edit.symbol - 5, 1, 38)
    end
  })
  drawButton("sym_minus1", x + (btnW + gap), btnY, btnW, btnH, "-1", {
    onClick = function()
      state.edit.symbol = clamp(state.edit.symbol - 1, 1, 38)
    end
  })
  drawButton("sym_plus1", x + (btnW + gap) * 2, btnY, btnW, btnH, "+1", {
    onClick = function()
      state.edit.symbol = clamp(state.edit.symbol + 1, 1, 38)
    end
  })
  drawButton("sym_plus5", x + (btnW + gap) * 3, btnY, btnW, btnH, "+5", {
    onClick = function()
      state.edit.symbol = clamp(state.edit.symbol + 5, 1, 38)
    end
  })

  local rowY = btnY + btnH + 1
  drawButton("sym_add", x, rowY, 12, 3, "Add", {
    onClick = function()
      if #entry.address >= 8 then
        setMessage("Max 8 symbols", 3)
        return
      end
      entry.address[#entry.address + 1] = state.edit.symbol
    end
  })
  drawButton("sym_back", x + 13, rowY, 12, 3, "Back", {
    onClick = function()
      if #entry.address > 0 then
        table.remove(entry.address)
      end
    end
  })
  drawButton("sym_clear", x + 26, rowY, 12, 3, "Clear", {
    onClick = function()
      entry.address = {}
      state.edit.entry.address = entry.address
    end
  })

  local saveY = layout.mainY + layout.mainH - 4
  drawButton("edit_save", layout.mainX + 2, saveY, 14, 3, "Save", {
    onClick = function()
      saveEdit()
    end
  })
  drawButton("edit_cancel", layout.mainX + 18, saveY, 14, 3, "Cancel", {
    onClick = function()
      cancelEdit()
    end
  })
end

local function drawNameInput()
  fillRect(layout.mainX, layout.mainY, layout.mainW, layout.mainH, theme.bg)
  writeAt(layout.mainX + 2, layout.mainY + 1, "Edit Name", theme.text, theme.bg)

  local maxLen = layout.mainW - 4
  local displayName = state.nameBuffer
  if #displayName > maxLen then
    displayName = displayName:sub(#displayName - maxLen + 1)
  end
  writeAt(layout.mainX + 2, layout.mainY + 3, displayName, theme.text, theme.bg)

  local keyRows = {
    "1234567890",
    "QWERTYUIOP",
    "ASDFGHJKL",
    "ZXCVBNM"
  }

  local keyW = 5
  local keyH = 3
  local gap = 1
  local startY = layout.mainY + 6
  for r = 1, #keyRows do
    local row = keyRows[r]
    local rowWidth = #row * keyW + (#row - 1) * gap
    local startX = layout.mainX + math.floor((layout.mainW - rowWidth) / 2)
    for i = 1, #row do
      local ch = row:sub(i, i)
      local x = startX + (i - 1) * (keyW + gap)
      local y = startY + (r - 1) * (keyH + gap)
      drawButton("key_" .. ch .. "_" .. r .. "_" .. i, x, y, keyW, keyH, ch, {
        onClick = function()
          if #state.nameBuffer < 32 then
            state.nameBuffer = state.nameBuffer .. ch
          end
        end
      })
    end
  end

  local controlY = startY + #keyRows * (keyH + gap) + 1
  drawButton("name_space", layout.mainX + 2, controlY, 10, 3, "Space", {
    onClick = function()
      if #state.nameBuffer < 32 then
        state.nameBuffer = state.nameBuffer .. " "
      end
    end
  })
  drawButton("name_back", layout.mainX + 13, controlY, 10, 3, "Back", {
    onClick = function()
      state.nameBuffer = state.nameBuffer:sub(1, math.max(0, #state.nameBuffer - 1))
    end
  })
  drawButton("name_clear", layout.mainX + 24, controlY, 10, 3, "Clear", {
    onClick = function()
      state.nameBuffer = ""
    end
  })
  drawButton("name_ok", layout.mainX + 35, controlY, 10, 3, "OK", {
    onClick = function()
      commitNameInput()
    end
  })
  drawButton("name_cancel", layout.mainX + 46, controlY, 10, 3, "Cancel", {
    onClick = function()
      cancelNameInput()
    end
  })
end

local function drawBottomBar()
  fillRect(1, layout.bottomY, layout.w, 1, theme.panelDark)
  local message = state.message
  if message == "" then
    message = "Ready"
  end
  if #message > layout.w - 2 then
    message = message:sub(1, layout.w - 2)
  end
  writeAt(2, layout.bottomY, message, theme.text, theme.panelDark)
end

local function render()
  resetButtons()
  screen.setBackgroundColor(theme.bg)
  screen.setTextColor(theme.text)
  screen.clear()
  drawHeader()
  drawNav()
  drawStatus()
  if state.page == "home" then
    drawHome()
  elseif state.page == "addresses" then
    drawAddresses()
  elseif state.page == "settings" then
    drawSettings()
  elseif state.page == "edit" then
    drawEdit()
  elseif state.page == "name" then
    drawNameInput()
  end
  drawBottomBar()
end

local function handleTouch(x, y)
  local btn = findButton(x, y)
  if btn and btn.onClick then
    btn.onClick()
    return
  end
  if state.page == "addresses" then
    local metrics = getListMetrics()
    if x >= layout.mainX and x <= layout.mainX + layout.mainW - 1 and y >= metrics.listY and y < metrics.listY + metrics.listH then
      local index = state.scroll + (y - metrics.listY) + 1
      if index <= #addresses then
        state.selectedIndex = index
        state.deleteConfirmIndex = nil
        adjustScroll()
      end
    end
  end
end

local function handleKey(key)
  if state.page == "addresses" then
    if key == keys.up and state.selectedIndex > 1 then
      state.selectedIndex = state.selectedIndex - 1
      state.deleteConfirmIndex = nil
      adjustScroll()
    elseif key == keys.down and state.selectedIndex < #addresses then
      state.selectedIndex = state.selectedIndex + 1
      state.deleteConfirmIndex = nil
      adjustScroll()
    end
  elseif state.page == "name" then
    if key == keys.backspace then
      state.nameBuffer = state.nameBuffer:sub(1, math.max(0, #state.nameBuffer - 1))
    elseif key == keys.enter then
      commitNameInput()
    end
  end
end

local function uiLoop()
  local refresh = os.startTimer(0.25)
  render()
  while true do
    local event, p1, p2, p3 = os.pullEvent()
    if event == "timer" and p1 == refresh then
      if state.message ~= "" and os.clock() > state.messageUntil then
        state.message = ""
      end
      updateStatus()
      render()
      refresh = os.startTimer(0.25)
    elseif event == "monitor_touch" then
      handleTouch(p2, p3)
      render()
    elseif event == "mouse_click" then
      handleTouch(p2, p3)
      render()
    elseif event == "key" then
      handleKey(p1)
      render()
    end
  end
end

local function securityLoop()
  local prevConnected = false
  while true do
    local connected = safeCall(interface.isStargateConnected) or false
    local dialingOut = safeCall(interface.isStargateDialingOut) or false
    if connected and not prevConnected then
      if not dialingOut then
        setAlarm(true)
      end
    end
    if connected and not dialingOut and config.terminateIncoming then
      safeCall(interface.disconnectStargate)
    end
    if not connected and prevConnected then
      setAlarm(false, false)
    end
    prevConnected = connected
    sleep(0.1)
  end
end

local function dialerLoop()
  while true do
    if state.dialRequest then
      local index = state.dialRequest
      state.dialRequest = nil
      state.dialing = true
      setMessage("Dialing...", 3)
      local entry = addresses[index]
      if entry then
        dialAddress(entry)
      else
        setMessage("No address selected", 3)
      end
      state.dialing = false
    end
    sleep(0.1)
  end
end

ensureSelection()
adjustScroll()
applyWhitelist()
setAlarm(false, true)

parallel.waitForAny(uiLoop, securityLoop, dialerLoop)
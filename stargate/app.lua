-- Stargate control program for Advanced Crystal Interface
-- GUI-driven via monitor

local util = dofile("stargate/util.lua")
local storage = dofile("stargate/storage.lua")
local gateModule = dofile("stargate/gate.lua")

local DATA_DIR = "stargate"
local CONFIG_PATH = DATA_DIR .. "/config.json"
local ADDR_PATH = DATA_DIR .. "/addresses.json"

local defaultConfig = {
  whitelistEnabled = true,
  terminateIncoming = false,
  incomingOverride = false,
  irisLock = false,
  alarmLatched = false,
  alarmSide = "bottom",
  textScale = 0.5
}

local defaultAddresses = {
  { name = "MW Overworld (IS)", address = { 27, 25, 4, 35, 10, 28 }, whitelisted = true },
  { name = "MW Overworld (EG)", address = { 1, 35, 4, 31, 15, 30, 32 }, whitelisted = true },
  { name = "MW Abydos (IS)", address = { 26, 6, 14, 31, 11, 29 }, whitelisted = true },
  { name = "MW Abydos (EG)", address = { 1, 17, 2, 34, 26, 9, 33 }, whitelisted = true },
  { name = "MW Chulak (IS)", address = { 8, 1, 22, 14, 36, 19 }, whitelisted = true },
  { name = "MW Chulak (EG)", address = { 1, 9, 14, 21, 17, 3, 29 }, whitelisted = true },
  { name = "MW Cavum Tenebrae (IS)", address = { 18, 7, 3, 36, 25, 15 }, whitelisted = true },
  { name = "MW Cavum Tenebrae (EG)", address = { 1, 34, 12, 18, 7, 31, 6 }, whitelisted = true },
  { name = "MW The Nether (IS)", address = { 27, 23, 4, 34, 12, 28 }, whitelisted = true },
  { name = "MW The Nether (EG)", address = { 1, 35, 6, 31, 15, 28, 32 }, whitelisted = true },
  { name = "MW Rima (IS)", address = { 33, 20, 10, 22, 3, 17 }, whitelisted = true },
  { name = "MW Rima (EG)", address = { 1, 31, 21, 8, 19, 2, 9 }, whitelisted = true },
  { name = "MW Unitas (IS)", address = { 2, 27, 8, 34, 24, 15 }, whitelisted = true },
  { name = "MW Unitas (EG)", address = { 1, 12, 34, 24, 15, 8, 17 }, whitelisted = true },
  { name = "MW Proxima Cen. Ad Astra (IS)", address = { 26, 20, 4, 36, 9, 27 }, whitelisted = true },
  { name = "MW Proxima Cen. Ad Astra (EG)", address = { 1, 36, 28, 4, 6, 26, 22 }, whitelisted = true },
  { name = "MW The End (IS)", address = { 13, 24, 2, 19, 3, 30 }, whitelisted = true },
  { name = "PG The End (IS)", address = { 14, 30, 6, 13, 17, 23 }, whitelisted = true },
  { name = "MW/PG The End (EG)", address = { 18, 24, 8, 16, 7, 35, 30 }, whitelisted = true },
  { name = "PG Lantea (IS)", address = { 29, 5, 17, 34, 6, 12 }, whitelisted = true },
  { name = "PG Lantea (EG)", address = { 18, 20, 1, 15, 14, 7, 19 }, whitelisted = true },
  { name = "PG Athos (IS)", address = { 21, 14, 24, 1, 26, 28 }, whitelisted = true },
  { name = "PG Athos (EG)", address = { 18, 21, 14, 24, 1, 26, 28 }, whitelisted = true },
  { name = "ID Othala (IS, No dest)", address = { 1, 6, 13, 3, 35, 8 }, whitelisted = true },
  { name = "ID Othala (EG, No dest)", address = { 10, 26, 22, 15, 32, 2, 8 }, whitelisted = true }
}

local validSides = {
  top = true,
  bottom = true,
  left = true,
  right = true,
  front = true,
  back = true
}

storage.ensureDir(DATA_DIR)
local config = storage.normalizeConfig(storage.loadJson(CONFIG_PATH, defaultConfig), defaultConfig, validSides)
local loadedAddresses = storage.loadJson(ADDR_PATH, nil)
local addresses = storage.normalizeAddresses(loadedAddresses or {})
if #addresses == 0 then
  addresses = storage.normalizeAddresses(defaultAddresses)
  storage.saveJson(ADDR_PATH, DATA_DIR, addresses)
end

local function saveConfig()
  storage.saveJson(CONFIG_PATH, DATA_DIR, config)
end

local function saveAddresses()
  storage.saveJson(ADDR_PATH, DATA_DIR, addresses)
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
  irisManualOpen = false,
  incomingBlocked = false,
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
    topSignal = false,
    connectedAddressStr = "-",
    localAddressStr = "-"
  }
}

local function setMessage(msg, duration)
  state.message = msg or ""
  state.messageUntil = os.clock() + (duration or 4)
end

local gate = gateModule.new({
  interface = interface,
  config = config,
  addresses = addresses,
  state = state,
  validSides = validSides,
  setMessage = setMessage,
  util = util
})

local safeCall = util.safeCall
local addressToString = util.addressToString

local applyWhitelist = gate.applyWhitelist
local setAlarm = gate.setAlarm
local resetAlarm = gate.resetAlarm
local updateStatus = gate.updateStatus
local dialAddress = gate.dialAddress

local function incomingOpenAllowed()
  return redstone.getInput("top") == true
end

local function isIncomingNow()
  local connected = safeCall(interface.isStargateConnected)
  if not connected then
    return false
  end
  return not safeCall(interface.isStargateDialingOut)
end

local function canOpenIris()
  if isIncomingNow() and (not config.incomingOverride or not incomingOpenAllowed()) then
    return false
  end
  return true
end

local function manualOpenIris()
  if not canOpenIris() then
    if isIncomingNow() and not config.incomingOverride then
      setMessage("Incoming override is off", 4)
    else
      setMessage("Incoming: top signal required", 4)
    end
    return
  end
  safeCall(interface.openIris)
  state.irisManualOpen = true
  setMessage("Iris opening", 2)
end

local function manualCloseIris()
  safeCall(interface.closeIris)
  state.irisManualOpen = false
  setMessage("Iris closing", 2)
end

local function autoCloseIris(force)
  if force or not (config.irisLock and state.irisManualOpen) then
    safeCall(interface.closeIris)
  end
  if force or not config.irisLock then
    state.irisManualOpen = false
  end
end

do
  local localAddr = safeCall(interface.getLocalAddress)
  if type(localAddr) == "table" then
    state.status.localAddressStr = addressToString(localAddr)
  end
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
    entry = storage.normalizeAddressEntry(addresses[index])
  else
    entry = { name = "", address = {}, whitelisted = true }
  end
  state.edit = {
    index = index,
    entry = entry,
    symbolBuffer = ""
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

local function inputSymbolDigit(digit)
  if not state.edit then
    return
  end
  local buffer = state.edit.symbolBuffer or ""
  if #buffer >= 2 then
    return
  end
  if digit == 0 and #buffer == 0 then
    return
  end
  state.edit.symbolBuffer = buffer .. tostring(digit)
end

local function deleteSymbolDigit()
  if not state.edit then
    return
  end
  local buffer = state.edit.symbolBuffer or ""
  state.edit.symbolBuffer = buffer:sub(1, math.max(0, #buffer - 1))
end

local function clearSymbolBuffer()
  if state.edit then
    state.edit.symbolBuffer = ""
  end
end

local function addSymbolFromBuffer()
  if not state.edit then
    return
  end
  local buffer = state.edit.symbolBuffer or ""
  if buffer == "" then
    setMessage("Enter a symbol", 3)
    return
  end
  local value = tonumber(buffer)
  if not value or value < 1 or value > 38 then
    setMessage("Symbol must be 1-38", 3)
    return
  end
  if #state.edit.entry.address >= 8 then
    setMessage("Max 8 symbols", 3)
    return
  end
  state.edit.entry.address[#state.edit.entry.address + 1] = value
  state.edit.symbolBuffer = ""
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

local function dialSelectedOnce()
  if state.dialRequest or state.dialing then
    setMessage("Dialer busy", 3)
    return
  end
  if state.selectedIndex == 0 or not addresses[state.selectedIndex] then
    setMessage("No address selected", 3)
    return
  end
  state.dialRequest = { index = state.selectedIndex, tempWhitelist = true }
  setMessage("Dial once queued", 2)
end

local function toggleWhitelistEnabled()
  config.whitelistEnabled = not config.whitelistEnabled
  saveConfig()
  applyWhitelist()
  setMessage("Whitelist " .. (config.whitelistEnabled and "enabled" or "disabled"), 3)
end

local function toggleIrisLock()
  config.irisLock = not config.irisLock
  saveConfig()
  setMessage("Iris lock " .. (config.irisLock and "enabled" or "disabled"), 3)
end

local function toggleTerminateIncoming()
  config.terminateIncoming = not config.terminateIncoming
  saveConfig()
  setMessage("Terminate incoming " .. (config.terminateIncoming and "enabled" or "disabled"), 3)
end

local function toggleIncomingOverride()
  config.incomingOverride = not config.incomingOverride
  saveConfig()
  setMessage("Incoming override " .. (config.incomingOverride and "enabled" or "disabled"), 3)
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
  line("Mode", state.irisManualOpen and "MAN" or "AUTO", state.irisManualOpen and theme.accent2 or theme.muted)
  line("Lock", config.irisLock and "ON" or "OFF", config.irisLock and theme.accent2 or theme.muted)
  line("Incoming", config.incomingOverride and "ALLOW" or "BLOCK", config.incomingOverride and theme.accent2 or theme.muted)
  line("TopSig", state.status.topSignal and "ON" or "OFF", state.status.topSignal and theme.accent2 or theme.muted)
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
      manualOpenIris()
    end
  })
  drawButton("close_iris", bx + bw + gap, by, bw, bh, "Close Iris", {
    onClick = function()
      manualCloseIris()
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

  local buttonCount = 8
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
  drawButton("addr_dial_once", x, y, btnW, btnH, "DialOnce", {
    enabled = hasSelection and not state.dialing,
    onClick = function()
      dialSelectedOnce()
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
  drawButton("set_incoming_override", bx, by + (bh + gap), bw, bh, "Incoming: " .. (config.incomingOverride and "ALLOW" or "BLOCK"), {
    onClick = function()
      toggleIncomingOverride()
    end
  })
  drawButton("set_iris_lock", bx, by + (bh + gap) * 2, bw, bh, "Iris Lock: " .. (config.irisLock and "ON" or "OFF"), {
    onClick = function()
      toggleIrisLock()
    end
  })
  drawButton("set_terminate", bx, by + (bh + gap) * 3, bw, bh, "Terminate In: " .. (config.terminateIncoming and "ON" or "OFF"), {
    onClick = function()
      toggleTerminateIncoming()
    end
  })
  drawButton("set_latch", bx, by + (bh + gap) * 4, bw, bh, "Alarm Latch: " .. (config.alarmLatched and "ON" or "OFF"), {
    onClick = function()
      toggleAlarmLatched()
    end
  })
  drawButton("set_alarm_side", bx, by + (bh + gap) * 5, bw, bh, "Alarm Side: " .. config.alarmSide, {
    onClick = function()
      cycleAlarmSide()
    end
  })
  drawButton("set_apply", bx, by + (bh + gap) * 6, bw, bh, "Apply Whitelist", {
    onClick = function()
      applyWhitelist()
      setMessage("Whitelist applied", 2)
    end
  })
  drawButton("set_reset_alarm", bx, by + (bh + gap) * 7, bw, bh, "Reset Alarm", {
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
  local buffer = state.edit.symbolBuffer or ""
  local bufferText = buffer == "" and "-" or buffer
  writeAt(x, controlsY, "Input: " .. bufferText, theme.text, theme.bg)

  local btnW = 6
  local btnH = 3
  local gap = 1
  local gridX = x
  local gridY = controlsY + 1

  local function digitButton(label, col, row, digit)
    drawButton("sym_digit_" .. label, gridX + col * (btnW + gap), gridY + row * (btnH + gap), btnW, btnH, label, {
      onClick = function()
        inputSymbolDigit(digit)
      end
    })
  end

  digitButton("1", 0, 0, 1)
  digitButton("2", 1, 0, 2)
  digitButton("3", 2, 0, 3)
  digitButton("4", 0, 1, 4)
  digitButton("5", 1, 1, 5)
  digitButton("6", 2, 1, 6)
  digitButton("7", 0, 2, 7)
  digitButton("8", 1, 2, 8)
  digitButton("9", 2, 2, 9)
  drawButton("sym_del", gridX, gridY + (btnH + gap) * 3, btnW, btnH, "Del", {
    onClick = function()
      deleteSymbolDigit()
    end
  })
  digitButton("0", 1, 3, 0)
  drawButton("sym_buf_clear", gridX + (btnW + gap) * 2, gridY + (btnH + gap) * 3, btnW, btnH, "Clr", {
    onClick = function()
      clearSymbolBuffer()
    end
  })

  local actionX = gridX + (btnW + gap) * 3 + 2
  local actionW = 12
  drawButton("sym_add", actionX, gridY, actionW, btnH, "Add", {
    onClick = function()
      addSymbolFromBuffer()
    end
  })
  drawButton("sym_back", actionX, gridY + (btnH + gap), actionW, btnH, "Pop", {
    onClick = function()
      if #entry.address > 0 then
        table.remove(entry.address)
      end
    end
  })
  drawButton("sym_clear", actionX, gridY + (btnH + gap) * 2, actionW, btnH, "AddrClr", {
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
    if connected and not dialingOut then
      if not config.incomingOverride then
        autoCloseIris(true)
        safeCall(interface.disconnectStargate)
        if not state.incomingBlocked then
          setMessage("Incoming blocked (menu override off)", 4)
          state.incomingBlocked = true
        end
      else
        state.incomingBlocked = false
        if config.terminateIncoming then
          safeCall(interface.disconnectStargate)
        elseif incomingOpenAllowed() then
          safeCall(interface.openIris)
          if not config.irisLock then
            state.irisManualOpen = false
          end
        else
          autoCloseIris(true)
        end
      end
    else
      state.incomingBlocked = false
    end
    if not connected and prevConnected then
      setAlarm(false, false)
      autoCloseIris(false)
    end
    prevConnected = connected
    sleep(0.1)
  end
end

local function dialerLoop()
  while true do
    if state.dialRequest then
      local request = state.dialRequest
      state.dialRequest = nil
      state.dialing = true
      local index = request
      local opts = nil
      local message = "Dialing..."
      if type(request) == "table" then
        index = request.index
        if request.tempWhitelist then
          opts = { tempWhitelist = true }
          message = "Dialing once..."
        end
      end
      setMessage(message, 3)
      local entry = addresses[index]
      if entry then
        dialAddress(entry, opts)
      else
        setMessage("No address selected", 3)
      end
      state.dialing = false
    end
    sleep(0.1)
  end
end

local function run()
  ensureSelection()
  adjustScroll()
  applyWhitelist()
  setAlarm(false, true)
  parallel.waitForAny(uiLoop, securityLoop, dialerLoop)
end

return {
  run = run
}

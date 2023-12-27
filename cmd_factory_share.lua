function widget:GetInfo()
  return {
    name = "Factory Share Command",
    desc = "Adds a command for factories that automatically shares units to another player after they are created",
    author = "citrine",
    date = "2023",
    license = "GNU GPL, v2 or later",
    version = 4,
    layer = 0,
    enabled = false,
    handler = true,
  }
end

-- user configuration
-- ==================

local config = {
  highlightFactories = "always",
  highlightUnits = "always",
}

-- engine call optimizations
-- =========================
local SpringGetUnitDefID = Spring.GetUnitDefID
local SpringGetUnitTeam = Spring.GetUnitTeam
local SpringGetSpectatingState = Spring.GetSpectatingState
local SpringGetMyTeamID = Spring.GetMyTeamID
local SpringGetCommandQueue = Spring.GetCommandQueue
local SpringGiveOrderToUnit = Spring.GiveOrderToUnit
local SpringGetTeamUnits = Spring.GetTeamUnits
local SpringGetSelectedUnits = Spring.GetSelectedUnits
local SpringGetTeamAllyTeamID = Spring.GetTeamAllyTeamID
local SpringShareResources = Spring.ShareResources
local SpringGetUnitPosition = Spring.GetUnitPosition
local SpringGiveOrderToUnitArray = Spring.GiveOrderToUnitArray
local SpringGetCameraState = Spring.GetCameraState
local SpringIsGUIHidden = Spring.IsGUIHidden
local SpringIsUnitSelected = Spring.IsUnitSelected
local SpringGetUnitRadius = Spring.GetUnitRadius
local SpringGetTeamColor = Spring.GetTeamColor
local SpringGetModKeyState = Spring.GetModKeyState
local SpringWorldToScreenCoords = Spring.WorldToScreenCoords
local SpringSelectUnitArray = Spring.SelectUnitArray
local SpringI18N = Spring.I18N
local SpringIsSphereInView = Spring.IsSphereInView
local SpringGetTeamList = Spring.GetTeamList
local SpringGetTeamInfo = Spring.GetTeamInfo
local SpringGetUnitHealth = Spring.GetUnitHealth

local glDeleteList = gl.DeleteList
local glCreateList = gl.CreateList
local glCallList = gl.CallList
local glColor = gl.Color
local glPushMatrix = gl.PushMatrix
local glTranslate = gl.Translate
local glPopMatrix = gl.PopMatrix
local glVertex = gl.Vertex
local glBeginEnd = gl.BeginEnd
local glLineWidth = gl.LineWidth
local glScale = gl.Scale

local mathPi = math.pi
local mathCos = math.cos
local mathSin = math.sin
local mathFloor = math.floor

-- utils
-- =====

local function tableToString(t)
  if type(t) ~= "table" then
    return tostring(t)
  end

  local str = "{"
  for key, value in pairs(t) do
    str = str .. key .. "=" .. tableToString(value) .. ", "
  end
  str = str .. "}"
  return str
end

local function glListCache(originalFunc)
  local cache = {}

  local function clearCache()
    for key, listID in pairs(cache) do
      glDeleteList(listID)
    end
    cache = {}
  end

  local function decoratedFunc(...)
    local rawParams = { ... }
    local params = {}
    for index, value in ipairs(rawParams) do
      if index > 1 then
        table.insert(params, value)
      end
    end

    local key = tableToString(params)

    if cache[key] == nil then
      local function fn()
        originalFunc(unpack(params))
      end
      cache[key] = glCreateList(fn)
    end

    glCallList(cache[key])
  end

  local decoratedFunction = setmetatable({}, {
    __call = decoratedFunc,
    __index = {
      invalidate = clearCache,
      getCache = function()
        return cache
      end,
      getListID = function(...)
        local params = { ... }
        local key = tableToString(params)
        return cache[key]
      end
    }
  })

  return decoratedFunction
end

local function contains(table, value)
  for _, v in ipairs(table) do
    if v == value then
      return true
    end
  end
  return false
end

local function filterList(list, predicate)
  local result = {}
  for _, item in ipairs(list) do
    if predicate(item) then
      table.insert(result, item)
    end
  end
  return result
end

-- widget code
-- ===========
-- the command that a user can execute, params = { targetUnitID }
local CMD_AUTO_SHARE_UNIT = 195623
local CMD_AUTO_SHARE_UNIT_DESCRIPTION = {
  id = CMD_AUTO_SHARE_UNIT,
  type = CMDTYPE.ICON_UNIT,
  name = 'Share Unit',
  cursor = 'settarget',
  action = 'factoryshare',
}

-- the command that the unit actually receives, params = { targetTeamID }
local CMD_AUTO_SHARE_TEAM = 195624

-- commands that move the location of a unit, used for display location of share order icon
local MOVE_LIKE_COMMANDS = { CMD.MOVE, CMD.FIGHT }

local myTeamID = SpringGetMyTeamID()
local myAllyTeamID = SpringGetTeamAllyTeamID(myTeamID)

-- factory -> { targetTeamID, orderPosition }
local shareCommandCache = {}

local function updateShareCommandCacheForUnit(unitID)
  shareCommandCache[unitID] = nil
  local cmdQueue = SpringGetCommandQueue(unitID, -1)
  if cmdQueue ~= nil and #cmdQueue > 0 then
    local currentPosition = nil
    for i = 1, #cmdQueue do
      local cmd = cmdQueue[i]
      if contains(MOVE_LIKE_COMMANDS, cmd.id) then
        currentPosition = cmd.params
      elseif cmd.id == CMD_AUTO_SHARE_TEAM then
        -- should only be one share command in the queue, but earlier ones will be overwritten by later ones anyways
        shareCommandCache[unitID] = {
          targetTeamID = cmd.params[1],
          orderPosition = currentPosition,
        }
      end
    end
  end
end

local function rebuildShareCommandCache()
  shareCommandCache = {}
  local teamIDs = {}
  if SpringGetSpectatingState() then
    teamIDs = SpringGetTeamList()
  else
    teamIDs = SpringGetTeamList(myAllyTeamID)
  end
  for _, teamID in ipairs(teamIDs) do
    local units = SpringGetTeamUnits(teamID)
    for _, unitID in ipairs(units) do
      updateShareCommandCacheForUnit(unitID)
    end
  end
end

-- draw
-- ====

local function generateDashedCircleVertices(radius, numSegments, numDashes, period, offset)
  local segmentAngle = 2 * mathPi / numSegments
  local numDashesBreaks = 2 * numDashes
  for i = 1, numSegments do
    local angle1 = segmentAngle * i
    local angle2 = segmentAngle * (i + 1)

    local x1 = radius * mathCos(angle1)
    local z1 = radius * mathSin(angle1)
    local x2 = radius * mathCos(angle2)
    local z2 = radius * mathSin(angle2)

    local progress = i / numSegments
    local dashIndex = mathFloor(progress * numDashesBreaks + offset)

    if dashIndex % period == 1 then
      glVertex(x1, 0, z1)
      glVertex(x2, 0, z2)
    end
  end
end

local function generateCircleVertices(radius, numSegments, center)
  if center then
    glVertex(0, 0, 0)
  end
  local segmentAngle = 2 * mathPi / numSegments
  for i = 1, numSegments do
    local angle1 = segmentAngle * i
    local angle2 = segmentAngle * (i + 1)

    local x1 = radius * mathCos(angle1)
    local z1 = radius * mathSin(angle1)
    local x2 = radius * mathCos(angle2)
    local z2 = radius * mathSin(angle2)
    glVertex(x1, z1)
    glVertex(x2, z2)
  end
end

local function generateArrowVerticesQuad(w, h)
  if h == nil then
    h = w
  end
  glVertex(-w, h / 2)
  glVertex(-w / 2, h / 2)
  glVertex(-w / 2, -h / 2)
  glVertex(-w, -h / 2)
end

local function generateArrowVerticesTriangle(size)
  glVertex(-size / 2, size)
  glVertex(size / 2, 0)
  glVertex(-size / 2, -size)
end

local drawShareIcon = glListCache(function(r, g, b)
  glPushMatrix()

  local offset = 0.4

  glTranslate(offset, 0, 0)
  glColor(0.1, 0.1, 0.1)
  glBeginEnd(GL.TRIANGLE_FAN, generateCircleVertices, 0.875, 64, true);
  glColor(r, g, b, 1)
  glBeginEnd(GL.TRIANGLE_FAN, generateCircleVertices, 0.75, 64, true);

  glTranslate(-offset, 0, 0)
  glColor(0.1, 0.1, 0.1)
  glBeginEnd(GL.QUADS, generateArrowVerticesQuad, 1);
  glBeginEnd(GL.TRIANGLES, generateArrowVerticesTriangle, 1);

  glColor(0.8, 0.8, 0.8)
  glTranslate(offset * 0.15, 0, 0)
  glBeginEnd(GL.QUADS, generateArrowVerticesQuad, 0.95, 0.75);
  glTranslate(-offset * 0.25, 0, 0)
  glBeginEnd(GL.TRIANGLES, generateArrowVerticesTriangle, 0.75);

  glPopMatrix()
end)

local drawUnitHighlight = glListCache(function(r, g, b)
  glColor(r, g, b, 1)
  glBeginEnd(GL.LINES, generateDashedCircleVertices, 1, 96, 12, 2, 0);
end)

-- hooks
-- =====

function widget:PlayerChanged(playerID)
  -- find now-dead teams, remove all invalidated share commands, and update cache
  local deadTeamIDs = {}
  for _, teamID in ipairs(SpringGetTeamList()) do
    local _, _, isDead = SpringGetTeamInfo(teamID)
    if isDead then
      table.insert(deadTeamIDs, teamID)
    end
  end

  if #deadTeamIDs > 0 then
    for unitID, shareCommandInfo in pairs(shareCommandCache) do
      if contains(deadTeamIDs, shareCommandInfo.targetTeamID) then
        local cmdQueue = SpringGetCommandQueue(unitID, -1)
        if #cmdQueue > 0 then
          for i = 1, #cmdQueue do
            local cmd = cmdQueue[i]
            if cmd.id == CMD_AUTO_SHARE_TEAM or cmd.id == CMD_AUTO_SHARE_UNIT then
              SpringGiveOrderToUnit(unitID, CMD.REMOVE, { cmd.tag }, {})
            end
          end
        end
        shareCommandCache[unitID] = nil
      end
    end
  end
end

local function canShareCommand(unitID)
  if UnitDefs[SpringGetUnitDefID(unitID)].isFactory then
    return true
  else
    local _, _, _, _, buildProgress = SpringGetUnitHealth(unitID)
    if buildProgress < 1 then
      return true
    end
  end

  return false
end

function widget:CommandsChanged()
  if SpringGetSpectatingState() then
    return
  end

  local selectedUnits = SpringGetSelectedUnits()
  if #selectedUnits > 0 then
    local customCommands = widgetHandler.customCommands
    for i = 1, #selectedUnits do
      if canShareCommand(selectedUnits[i]) then
        customCommands[#customCommands + 1] = CMD_AUTO_SHARE_UNIT_DESCRIPTION
        return
      end
    end
  end
end

local rebuildShareCommandCachePeriod = 5 * 30 + 1
function widget:GameFrame(frame)
  if frame % rebuildShareCommandCachePeriod == 0 then
    rebuildShareCommandCache()
  end
end

local updateShareCommandCacheForUnitQueue = {}
function widget:Update()
  for _, unitID in ipairs(updateShareCommandCacheForUnitQueue) do
    updateShareCommandCacheForUnit(unitID)
  end
  updateShareCommandCacheForUnitQueue = {}
end

function widget:UnitCmdDone(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
  if cmdID == CMD_AUTO_SHARE_TEAM then
    if not UnitDefs[unitDefID].isFactory then
      if #cmdParams < 1 then
        return true
      end

      -- share unit
      shareCommandCache[unitID] = nil

      if unitTeam == myTeamID then
        local selectedUnits = SpringGetSelectedUnits()

        SpringSelectUnitArray({ unitID }, false)
        SpringShareResources(cmdParams[1], "units")
        SpringSelectUnitArray(selectedUnits, false)
      end
    end
  end
end

function widget:UnitFromFactory(unitID, unitDefID, unitTeam, factID, factDefID, userOrders)
  if SpringGetTeamAllyTeamID(unitTeam) ~= myAllyTeamID then
    return
  end

  updateShareCommandCacheForUnit(unitID)
end

function widget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
  if not (cmdOpts.shift or cmdOpts.meta) and SpringGetTeamAllyTeamID(unitTeam) == myAllyTeamID then
    -- this might have removed a share command, so recheck queue
    table.insert(updateShareCommandCacheForUnitQueue, unitID)
  end
end

function widget:CommandNotify(cmdID, cmdParams, cmdOpts)
  if cmdID == CMD_AUTO_SHARE_UNIT then
    local targetUnitID = cmdParams[1]
    local targetTeamID = SpringGetUnitTeam(targetUnitID)
    if targetTeamID == myTeamID or SpringGetTeamAllyTeamID(targetTeamID) ~= myAllyTeamID then
      -- invalid target, don't do anything
      return true
    end

    local selectedUnits = filterList(SpringGetSelectedUnits(), function(unitID)
      return canShareCommand(unitID)
    end)

    -- remove all previous share commands and update cache
    for _, unitID in ipairs(selectedUnits) do
      local cmdQueue = SpringGetCommandQueue(unitID, -1)
      local currentPosition = nil
      if #cmdQueue > 0 then
        for i = 1, #cmdQueue do
          local cmd = cmdQueue[i]
          if contains(MOVE_LIKE_COMMANDS, cmd.id) then
            currentPosition = cmd.params
          end
          if cmd.id == CMD_AUTO_SHARE_TEAM or cmd.id == CMD_AUTO_SHARE_UNIT then
            SpringGiveOrderToUnit(unitID, CMD.REMOVE, { cmd.tag }, {})
          end
        end
      end
      shareCommandCache[unitID] = {
        targetTeamID = targetTeamID,
        orderPosition = currentPosition,
      }
    end

    -- add new team-format command
    SpringGiveOrderToUnitArray(selectedUnits, CMD_AUTO_SHARE_TEAM, { targetTeamID }, cmdOpts)

    -- skip adding original unit-style command
    return true
  end
end

local function getCameraDistance()
  local cameraState = SpringGetCameraState()
  return cameraState.height or cameraState.dist or cameraState.py or 3500
end

function widget:DrawWorldPreUnit()
  if SpringIsGUIHidden() then
    return
  end

  if config.highlightUnits == "never" and config.highlightFactories == "never" then
    return
  end

  local cameraDistance = getCameraDistance()
  local scale = 1800 / cameraDistance
  for unitID, shareCommandInfo in pairs(shareCommandCache) do
    local unitDefID = SpringGetUnitDefID(unitID)

    if unitDefID ~= nil then
      local isFactory = UnitDefs[unitDefID].isFactory
      local display = false
      if isFactory then
        if config.highlightFactories == "always" then
          display = true
        elseif (config.highlightFactories == "selected" and SpringIsUnitSelected(unitID)) then
          display = true
        end
        glLineWidth(5 * scale)
      elseif not isFactory then
        if config.highlightUnits == "always" then
          display = true
        elseif (config.highlightUnits == "selected" and SpringIsUnitSelected(unitID)) then
          display = true
        end
        glLineWidth(2 * scale)
      end

      if display then
        local x, y, z = SpringGetUnitPosition(unitID)
        local radius = SpringGetUnitRadius(unitID)
        if radius ~= nil and SpringIsSphereInView(x, y, z, radius * 1.2) then
          -- draw on factory and other units with pending orders
          local r, g, b, a = SpringGetTeamColor(shareCommandInfo.targetTeamID)

          radius = radius * 1.2

          glPushMatrix()
          glTranslate(x, y, z)
          glScale(radius, radius, radius)
          drawUnitHighlight(r, g, b)
          glPopMatrix()
        end
      end
    end
  end
end

local iconScale = 10
local iconOffset = 10
function widget:DrawScreenEffects()
  if SpringIsGUIHidden() then
    return
  end

  local alt, control, meta, shift = SpringGetModKeyState()
  local showUnits
  if (shift and meta) then
    -- when show all orders (gui_show_orders.lua), show all units
    showUnits = nil
  else
    -- otherwise, just selected units
    showUnits = SpringGetSelectedUnits()
  end

  for unitID, shareCommandInfo in pairs(shareCommandCache) do
    -- draw on unit ending location
    if (showUnits == nil or contains(showUnits, unitID)) and shareCommandInfo.orderPosition ~= nil then
      local r, g, b, a = SpringGetTeamColor(shareCommandInfo.targetTeamID)
      local ox, oy, oz = unpack(shareCommandInfo.orderPosition, 1, 3)
      local x, y = SpringWorldToScreenCoords(ox, oy + 3, oz)

      glPushMatrix()
      glTranslate(x, y + iconOffset, 0)
      glScale(iconScale, iconScale, iconScale)
      drawShareIcon(r, g, b)
      glPopMatrix()
    end
  end
end

local HIGHLIGHT_UNITS_OPTIONS = { "always", "selected", "never" }
local OPTION_SPECS = {
  {
    configVariable = "highlightFactories",
    name = "Highlight factories",
    description = "Highlight factories that have a 'Share Unit' command queued",
    type = "select",
    options = HIGHLIGHT_UNITS_OPTIONS,
  },
  {
    configVariable = "highlightUnits",
    name = "Highlight units",
    description = "Highlight units that have a 'Share Unit' command queued",
    type = "select",
    options = HIGHLIGHT_UNITS_OPTIONS,
  },
}

local function getOptionId(optionSpec)
  return "factory_share__" .. optionSpec.configVariable
end

local function getWidgetName()
  return "Factory Share Command"
end

local function getOptionValue(optionSpec)
  if optionSpec.type == "slider" then
    return config[optionSpec.configVariable]
  elseif optionSpec.type == "bool" then
    return config[optionSpec.configVariable]
  elseif optionSpec.type == "select" then
    -- we have text, we need index
    for i, v in ipairs(optionSpec.options) do
      if config[optionSpec.configVariable] == v then
        return i
      end
    end
  end
end

local function setOptionValue(optionSpec, value)
  if optionSpec.type == "slider" then
    config[optionSpec.configVariable] = value
  elseif optionSpec.type == "bool" then
    config[optionSpec.configVariable] = value
  elseif optionSpec.type == "select" then
    -- we have index, we need text
    config[optionSpec.configVariable] = optionSpec.options[value]
  end
end

local function createOnChange(optionSpec)
  return function(i, value, force)
    setOptionValue(optionSpec, value)
  end
end

local function addOptionFromSpec(optionSpec)
  local option = table.copy(optionSpec)
  option.configVariable = nil
  option.enabled = nil
  option.id = getOptionId(optionSpec)
  option.widgetname = getWidgetName()
  option.value = getOptionValue(optionSpec)
  option.onchange = createOnChange(optionSpec)
  WG['options'].addOption(option)
end

function widget:Initialize()
  rebuildShareCommandCache()

  for _, optionSpec in ipairs(OPTION_SPECS) do
    addOptionFromSpec(optionSpec)
  end

  SpringI18N.load({
    en = {
      ["ui.orderMenu.factoryshare"] = "Share Unit",
      ["ui.orderMenu.factoryshare_tooltip"] = "Target any of a player's units with this command, and when the " ..
        "command is executed, the commanded unit will be shared to the player.",
    }
  })
end

function widget:Shutdown()
  drawShareIcon.invalidate()
  drawUnitHighlight.invalidate()

  if WG['options'] ~= nil then
    for _, option in ipairs(OPTION_SPECS) do
      WG['options'].removeOption(getOptionId(option))
    end
  end
end

function widget:GetConfigData()
  local result = {}
  for _, option in ipairs(OPTION_SPECS) do
    result[option.configVariable] = getOptionValue(option)
  end
  return result
end

function widget:SetConfigData(data)
  for _, option in ipairs(OPTION_SPECS) do
    local configVariable = option.configVariable
    if data[configVariable] ~= nil then
      setOptionValue(option, data[configVariable])
    end
  end
end

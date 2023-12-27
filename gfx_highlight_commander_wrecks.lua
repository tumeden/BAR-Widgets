function widget:GetInfo()
  return {
    name = "Highlight Commander Wrecks",
    desc = "Show a vertical beam on each dead commander that can be resurrected",
    author = "citrine",
    date = "2023",
    license = "GNU GPL, v2 or later",
    version = 3,
    layer = 0,
    enabled = false
  }
end

-- user configuration
-- ==================

local config = {
  useTeamColor = false,
}

-- engine call optimizations
-- =========================

local SpringGetCameraState = Spring.GetCameraState
local SpringGetAllFeatures = Spring.GetAllFeatures
local SpringGetFeatureResurrect = Spring.GetFeatureResurrect
local SpringGetFeatureResources = Spring.GetFeatureResources
local SpringGetFeaturePosition = Spring.GetFeaturePosition
local SpringGetGroundHeight = Spring.GetGroundHeight
local SpringGetFeatureTeam = Spring.GetFeatureTeam
local SpringGetTeamColor = Spring.GetTeamColor

local glColor = gl.Color
local glLineWidth = gl.LineWidth
local glDeleteList = gl.DeleteList
local glCreateList = gl.CreateList
local glCallList = gl.CallList
local glBeginEnd = gl.BeginEnd
local glVertex = gl.Vertex

-- util
-- ====

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

-- widget code
-- ===========
local highlightUnitNames = {}

local function shouldHighlight(unitName)
  return highlightUnitNames[unitName] or false
end

local function getCameraDistance()
  local cameraState = SpringGetCameraState()
  return cameraState.height or cameraState.dist or cameraState.py or 3500
end

local DEFAULT_COLOR = { 0.9, 0.5, 1, 0.8 }
local function drawFeatureHighlight(x, z, scale, color)
  local yg = SpringGetGroundHeight(x, z)

  glLineWidth(8 * scale)
  glBeginEnd(GL.LINES, function()
    glColor(color[1], color[2], color[3], color[4])
    glVertex(x, yg, z)
    glColor(color[1], color[2], color[3], 0)
    glVertex(x, yg + 1500, z)
  end)
end

local drawComLines = glListCache(function()
  local cameraDistance = getCameraDistance()
  local scale = 1800 / cameraDistance

  for _, featureID in ipairs(SpringGetAllFeatures()) do
    local resUnitName = SpringGetFeatureResurrect(featureID)
    if resUnitName ~= nil and shouldHighlight(resUnitName) then
      local m, dm, e, de, rl, rt = SpringGetFeatureResources(featureID)
      if m > 0 then
        local x, y, z = SpringGetFeaturePosition(featureID)

        local color = DEFAULT_COLOR
        if config.useTeamColor then
          local featureTeamID = SpringGetFeatureTeam(featureID)

          if featureTeamID ~= nil then
            local r, g, b = SpringGetTeamColor(featureTeamID)
            color = { r, g, b, 0.9 }
          end
        end
        drawFeatureHighlight(x, z, scale, color)
      end
    end
  end
end)

local prevCameraDistance = nil
function widget:DrawWorld()
  local cameraDistance = getCameraDistance()
  if cameraDistance ~= prevCameraDistance then
    drawComLines.invalidate()
    prevCameraDistance = cameraDistance
  end

  drawComLines()
end

function widget:GameFrame(frame)
  if frame % 33 == 0 then
    drawComLines.invalidate()
  end
end

local OPTION_SPECS = {
  {
    configVariable = "useTeamColor",
    name = "Use Player Color",
    description = "Use the player's color for the beam, instead of the default color (default matches resurrect order color)",
    type = "bool",
  },
}

local function getOptionId(optionSpec)
  return "highlight_commander_wrecks__" .. optionSpec.configVariable
end

local function getWidgetName()
  return "Highlight Commander Wrecks"
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

  drawComLines.invalidate()
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
  for _, optionSpec in ipairs(OPTION_SPECS) do
    addOptionFromSpec(optionSpec)
  end

  highlightUnitNames = {}
  for _, unitDef in pairs(UnitDefs) do
    if unitDef.customParams.iscommander then
      highlightUnitNames[unitDef.name] = true
    end
  end
end

function widget:Shutdown()
  drawComLines.invalidate()

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
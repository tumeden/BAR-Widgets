-- /////////////////////////////////////////// GetInfo Function
function widget:GetInfo()
  return {
    name      = "SCV",
    desc      = "RezBots Resurrect, Collect resources, and heal injured units. alt+c to open UI",
    author    = "Tumeden",
    date      = "2024",
    version   = "v1.09",
    license   = "GNU GPL, v2 or later",
    layer     = 0,
    enabled   = true
  }
end



-- /////////////////////////////////////////// ---- /////////////////////////////////////////// ---- /////////////////////////////////////////// 
-- /////////////////////////////////////////// ---                Main Code                     ---- /////////////////////////////////////////// 
-- /////////////////////////////////////////// ----  Do not edit things past this line          ---- ///////////////////////////////////////////



-- /////////////////////////////////////////// Important things :))
local widgetEnabled = true
local unitsMovingToSafety = {}
local resurrectingUnits = {}  -- table to keep track of units currently resurrecting
local unitsToCollect = {}  -- table to keep track of units and their collection state
local healingUnits = {}  -- table to keep track of healing units
local unitLastPosition = {} -- Track the last position of each unit
local targetedFeatures = {}  -- Table to keep track of targeted features
local maxUnitsPerFeature = 4  -- Maximum units allowed to target the same feature
local healingTargets = {}  -- Track which units are being healed and by how many healers
local maxHealersPerUnit = 4  -- Maximum number of healers per unit
local healResurrectRadius = 1000 -- Set your desired heal/resurrect radius here  (default 1000)
local reclaimRadius = 1500 -- Set your desired reclaim radius here (any number works, 4000 is about half a large map)
local enemyAvoidanceRadius = 675  -- Adjust this value as needed -- Define a safe distance for enemy avoidance

-- Engine call optimizations
-- =========================
local armRectrDefID
local corNecroDefID
local spGetUnitDefID = Spring.GetUnitDefID
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spGetUnitPosition = Spring.GetUnitPosition
local spGetFeaturesInCylinder = Spring.GetFeaturesInCylinder
local spGetFeatureDefID = Spring.GetFeatureDefID
local spGetMyTeamID = Spring.GetMyTeamID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitsInCylinder = Spring.GetUnitsInCylinder
local spGetUnitIsDead = Spring.GetUnitIsDead
local spValidUnitID = Spring.ValidUnitID
local spGetTeamResources = Spring.GetTeamResources
local spGetFeaturePosition = Spring.GetFeaturePosition
local spGetUnitCommands = Spring.GetUnitCommands

-- Command Definitions
local CMD_MOVE = CMD.MOVE
local CMD_RESURRECT = CMD.RESURRECT
local CMD_RECLAIM = CMD.RECLAIM

-- Mathematical and Table Functions
local sqrt = math.sqrt
local pow = math.pow
local mathMax = math.max
local mathMin = math.min
local mathAbs = math.abs
local mathSqrt = math.sqrt
local mathPi = math.pi
local mathCos = math.cos
local mathSin = math.sin
local mathFloor = math.floor
local tblInsert = table.insert
local tblRemove = table.remove
local tblSort = table.sort
local strFormat = string.format
local strSub = string.sub

-- Utility functions
local findNearestEnemy = findNearestEnemy
local getFeatureResources = getFeatureResources

-- OpenGL functions
local glVertex = gl.Vertex
local glBeginEnd = gl.BeginEnd





-- /////////////////////////////////////////// -- /////////////////////////////////////////// --
-- /////////////////////////////////////////// -- /////////////////////////////////////////// --
-- ////////////////////////////////////////- UI CODE -////////////////////////////////////// --
-- /////////////////////////////////////////// -- /////////////////////////////////////////// --
-- /////////////////////////////////////////// -- /////////////////////////////////////////// --


-- /////////////////////////////////////////// UI Variables
-- UI Constants and Variables
local activeSlider = nil
local windowSize = { width = 300, height = 400 }
local vsx, vsy = Spring.GetViewGeometry() -- Screen dimensions
local windowPos = { x = (vsx - windowSize.width) / 2, y = (vsy - windowSize.height) / 2 } -- Center the window

local checkboxes = {
  healing = { x = windowPos.x + 30, y = windowPos.y + 50, size = 20, state = false, label = "Healing" },
  resurrecting = { x = windowPos.x + 30, y = windowPos.y + 80, size = 20, state = false, label = "Resurrect" },
  collecting = { x = windowPos.x + 30, y = windowPos.y + 110, size = 20, state = false, label = "Resource Collection" },
  excludeBuildings = { x = windowPos.x + 30, y = windowPos.y + 140, size = 20, state = false, label = "Exclude Buildings" },
  
}

local sliders = {
  healResurrectRadius = { x = windowPos.x + 50, y = windowPos.y + 200, width = 200, value = healResurrectRadius, min = 0, max = 2000, label = "Heal/Resurrect Radius" },
  reclaimRadius = { x = windowPos.x + 50, y = windowPos.y + 230, width = 200, value = reclaimRadius, min = 0, max = 5000, label = "Resource Collection Radius" },
  enemyAvoidanceRadius = { x = windowPos.x + 50, y = windowPos.y + 290, width = 200, value = enemyAvoidanceRadius, min = 0, max = 2000, label = "Maintain Safe Distance" },
}


-- Define UI elements relative to the window
local button = { x = windowPos.x + 50, y = windowPos.y + 50, width = 100, height = 30, text = "Toggle Widget", state = widgetEnabled }
local slider = { x = windowPos.x + 50, y = windowPos.y + 100, width = 200, value = healResurrectRadius, min = 100, max = 2000 }

-- Utility function for point inside rectangle
local function isInsideRect(x, y, rect)
    return x >= rect.x and x <= (rect.x + rect.width) and y >= rect.y and y <= (rect.y + rect.height)
end



-- /////////////////////////////////////////// KeyPress Function Modification
local ESCAPE_KEY = 27 -- Escape key is usually 27 in ASCII

function widget:KeyPress(key, mods, isRepeat)
    if key == 0x0063 and mods.alt then -- Alt+C to toggle UI
        showUI = not showUI
        return true
    end

    if key == ESCAPE_KEY then -- Directly check the ASCII value for the Escape key
        showUI = false
        return true
    end

    return false
end



-- /////////////////////////////////////////// Drawing the UI
function widget:DrawScreen()
  if showUI then
    -- Style configuration
    local mainBgColor = {0, 0, 0, 0.8}
    local statsBgColor = {0.05, 0.05, 0.05, 0.85}
    local borderColor = {0.7, 0.7, 0.7, 0.5}
    local labelColor = {0.9, 0.9, 0.9, 1}
    local valueColor = {1, 1, 0, 1}
    local fontSize = 14
    local lineHeight = fontSize * 1.5
    local padding = 10

-- Main box configuration
local mainBoxWidth = vsx * 0.2 -- Adjust the width to make the main box smaller
local mainBoxHeight = vsy * 0.4 -- Adjust the height to make the main box smaller
local mainBoxX = (vsx - mainBoxWidth) / 2
local mainBoxY = (vsy + mainBoxHeight) / 2


    -- Function to draw a bordered box
    local function drawBorderedBox(x1, y1, x2, y2, bgColor, borderColor)
      gl.Color(unpack(bgColor))
      gl.Rect(x1, y1, x2, y2)
      gl.Color(unpack(borderColor))
      gl.PolygonMode(GL.FRONT_AND_BACK, GL.LINE)
      gl.Rect(x1, y1, x2, y2)
      gl.PolygonMode(GL.FRONT_AND_BACK, GL.FILL)
    end

    -- Draw the main background box
    drawBorderedBox(mainBoxX, mainBoxY - mainBoxHeight, mainBoxX + mainBoxWidth, mainBoxY, mainBgColor, borderColor)


        
    -- Draw sliders
    for _, slider in pairs(sliders) do
      -- Draw the slider track
      gl.Color(0.8, 0.8, 0.8, 1) -- Light grey color for track
      gl.Rect(slider.x, slider.y, slider.x + slider.width, slider.y + 10) -- Adjust height as needed

      -- Calculate knob position based on value
      local knobX = slider.x + (slider.value - slider.min) / (slider.max - slider.min) * slider.width

      -- Draw the slider knob in green
      gl.Color(0, 1, 0, 1) -- Green color for knob
      gl.Rect(knobX - 5, slider.y - 5, knobX + 5, slider.y + 15) -- Adjust knob size as needed

      -- Draw the current value of the slider in green
      local valueText = string.format("%.1f", slider.value)  -- Format the value to one decimal place
      local textX = slider.x + slider.width + 10  -- Position the text to the right of the slider
      local textY = slider.y - 5  -- Align the text vertically with the slider
      gl.Color(0, 1, 0, 1) -- Green color for text
      gl.Text(valueText, textX, textY, 12, "o")  -- Draw the text with size 12 and outline font ("o")

      -- Draw the label above the slider
      local labelYOffset = 20  -- Increase this value to move the label higher
      gl.Color(1, 1, 1, 1) -- White color for text
      gl.Text(slider.label, slider.x, slider.y + labelYOffset, 12)
    end

    -- Draw checkboxes
    for _, box in pairs(checkboxes) do
      gl.Color(1, 1, 1, 1) -- White color for box
      gl.Rect(box.x, box.y, box.x + box.size, box.y + box.size)
      if box.state then
        gl.Color(0, 1, 0, 1) -- Green color for tick
        gl.LineWidth(2)
        glBeginEnd(GL.LINES, function()
          glVertex(box.x + 3, box.y + box.size - 3)
          glVertex(box.x + box.size - 3, box.y + 3)
        end)
        gl.LineWidth(1)
        
        -- Change label color to green for enabled checkboxes
        gl.Color(0, 1, 0, 1) -- Green color for text
      else
        -- Default label color for disabled checkboxes (white)
        gl.Color(1, 1, 1, 1) -- White color for text
      end
      
      gl.Text(box.label, box.x + box.size + 10, box.y, 12)
    end
  end
end




-- /////////////////////////////////////////// Handling UI Interactions
function widget:MousePress(x, y, button)
  if showUI then
      -- Existing button and slider interaction code...

      -- Handle slider knob interactions
      for key, slider in pairs(sliders) do
        local knobX = slider.x + (slider.value - slider.min) / (slider.max - slider.min) * slider.width
        if x >= knobX - 5 and x <= knobX + 5 and y >= slider.y - 5 and y <= slider.y + 15 then
            activeSlider = slider  -- Set the active slider
            return true  -- Indicate that the mouse press has been handled
        end
      end
      -- Handle checkbox interactions
      for key, box in pairs(checkboxes) do
          if isInsideRect(x, y, { x = box.x, y = box.y, width = box.size, height = box.size }) then
              box.state = not box.state
              -- Implement the logic based on the checkbox state
              if key == "healing" then
                  -- Logic for enabling/disabling healing
              elseif key == "resurrecting" then
                  -- Logic for enabling/disabling resurrecting
              elseif key == "collecting" then
                  -- Logic for enabling/disabling collecting
              end
              return true
          end
      end
  end
  return false
end


function widget:MouseMove(x, y, dx, dy, button)
  if activeSlider then
      -- Calculate new value based on mouse x position
      local newValue = ((x - activeSlider.x) / activeSlider.width) * (activeSlider.max - activeSlider.min) + activeSlider.min
      newValue = math.max(math.min(newValue, activeSlider.max), activeSlider.min)  -- Clamp value
      activeSlider.value = newValue  -- Update slider value

      -- Update corresponding variable
      if activeSlider == sliders.healResurrectRadius then
          healResurrectRadius = newValue
      elseif activeSlider == sliders.reclaimRadius then
          reclaimRadius = newValue
      elseif activeSlider == sliders.enemyAvoidanceRadius then
          enemyAvoidanceRadius = newValue
      end
  end
end


function widget:MouseRelease(x, y, button)
  activeSlider = nil  -- Clear the active slider
end

-- /////////////////////////////////////////// ViewResize
function widget:ViewResize(newX, newY)
  vsx, vsy = newX, newY
  windowPos.x = (vsx - windowSize.width) / 2
  windowPos.y = (vsy - windowSize.height) / 2
  -- Update positions of UI elements
  button.x = windowPos.x + 50
  button.y = windowPos.y + 50
  slider.x = windowPos.x + 50
  slider.y = windowPos.y + 100
end

-- /////////////////////////////////////////// -- /////////////////////////////////////////// --
-- /////////////////////////////////////////// -- /////////////////////////////////////////// --
-- ////////////////////////////////////////- END UI CODE -////////////////////////////////////// --
-- /////////////////////////////////////////// -- /////////////////////////////////////////// --
-- /////////////////////////////////////////// -- /////////////////////////////////////////// --



-- /////////////////////////////////////////// Initialize Function
function widget:Initialize()
  
  local isSpectator = Spring.GetSpectatingState()
  if isSpectator then
    Spring.Echo("You are a spectator. Widget is disabled.")
    widgetHandler:RemoveWidget(self)
    return
  end

  -- Define rezbots unit definition IDs
  -- These are now local to the widget but outside of the Initialize function
  -- to be accessible to the whole widget file.
  if UnitDefNames and UnitDefNames.armrectr and UnitDefNames.cornecro then
      armRectrDefID = UnitDefNames.armrectr.id
      corNecroDefID = UnitDefNames.cornecro.id
  else
      -- Handle the case where UnitDefNames are not available or units are undefined
      Spring.Echo("Rezbot UnitDefIDs could not be determined")
      widgetHandler:RemoveWidget()
      return
  end

  -- You can add any additional initialization code here if needed

end
-- ///////////////////////////////////////////  isMyResbot Function 
-- Updated isMyResbot function
  function isMyResbot(unitID, unitDefID)
    local myTeamID = Spring.GetMyTeamID()
    local unitTeamID = Spring.GetUnitTeam(unitID)

    -- Check if unit is a RezBot
    local isRezBot = unitTeamID == myTeamID and (unitDefID == armRectrDefID or unitDefID == corNecroDefID)
    
    -- Check if unit is valid and exists
    if not Spring.ValidUnitID(unitID) or Spring.GetUnitIsDead(unitID) then
        return false -- Invalid or dead units are not considered RezBots
    end

    -- Check if the unit is fully built
    local _, _, _, _, buildProgress = Spring.GetUnitHealth(unitID)
    if buildProgress < 1 then
        return false -- Units still being built are not considered RezBots
    end

    return isRezBot
end



-- A table to check if a unit definition name corresponds to a building
-- This was necessary because Dead units and dead buildings are all considered 'corpses,heaps'
-- There is no way to differentiate between a dead unit and dead building without referencing their name.
local buildingNames = {
  armamb = true,
  armamd = true,
  armanni = true,
  armbeamer = true,
  armbrtha = true,
  armcir = true,
  armclaw = true,
  armemp = true,
  armferret = true,
  armflak = true,
  armguard = true,
  armhlt = true,
  armjuno = true,
  armllt = true,
  armmercury = true,
  armpb = true,
  armrl = true,
  armshockwave = true,
  armsilo = true,
  armvulc = true,
  corbhmth = true,
  corbuzz = true,
  cordoom = true,
  corerad = true,
  corexp = true,
  corflak = true,
  corfmd = true,
  corhllt = true,
  corhlt = true,
  corint = true,
  corjuno = true,
  corllt = true,
  cormadsam = true,
  cormaw = true,
  cormexp = true,
  corpun = true,
  corrl = true,
  corscreamer = true,
  corsilo = true,
  cortoast = true,
  cortron = true,
  corvipe = true,
  armadvsol = true,
  armafus = true,
  armageo = true,
  armamex = true,
  armckfus = true,
  armestor = true,
  armfus = true,
  armgeo = true,
  armgmm = true,
  armmakr = true,
  armmex = true,
  armmmkr = true,
  armmoho = true,
  armmstor = true,
  armsolar = true,
  armwin = true,
  coradvsol = true,
  corafus = true,
  corageo = true,
  corestor = true,
  corfus = true,
  corgeo = true,
  cormakr = true,
  cormex = true,
  cormmkr = true,
  cormoho = true,
  cormstor = true,
  corsolar = true,
  corwin = true,
  armaap = true,
  armalab = true,
  armap = true,
  armavp = true,
  armhp = true,
  armlab = true,
  armshltx = true,
  armvp = true,
  coraap = true,
  coralab = true,
  corap = true,
  coravp = true,
  corgant = true,
  corhp = true,
  corlab = true,
  corvp = true,
  armarad = true,
  armasp = true,
  armdf = true,
  armdrag = true,
  armeyes = true,
  armfort = true,
  armgate = true,
  armjamt = true,
  armmine1 = true,
  armmine2 = true,
  armmine3 = true,
  armnanotc = true,
  armnanotct2 = true,
  armrad = true,
  armsd = true,
  armtarg = true,
  armveil = true,
  corarad = true,
  corasp = true,
  cordrag = true,
  coreyes = true,
  corfort = true,
  corgate = true,
  corjamt = true,
  cormine1 = true,
  cormine2 = true,
  cormine3 = true,
  cormine4 = true,
  cornanotc = true,
  cornanotct2 = true,
  corrad = true,
  corsd = true,
  corshroud = true,
  cortarg = true,
  armatl = true,
  armdl = true,
  armfflak = true,
  armfhlt = true,
  armfrock = true,
  armfrt = true,
  armgplat = true,
  armkraken = true,
  armptl = true,
  armtl = true,
  coratl = true,
  cordl = true,
  corenaa = true,
  corfdoom = true,
  corfhlt = true,
  corfrock = true,
  corfrt = true,
  corgplat = true,
  corptl = true,
  cortl = true,
  armfmkr = true,
  armtide = true,
  armuwadves = true,
  armuwadvms = true,
  armuwageo = true,
  armuwes = true,
  armuwfus = true,
  armuwgeo = true,
  armuwmex = true,
  armuwmme = true,
  armuwmmm = true,
  armuwms = true,
  corfmkr = true,
  cortide = true,
  coruwadves = true,
  coruwadvms = true,
  coruwageo = true,
  coruwes = true,
  coruwfus = true,
  coruwgeo = true,
  coruwmex = true,
  coruwmme = true,
  coruwmmm = true,
  coruwms = true,
  armamsub = true,
  armasy = true,
  armfhp = true,
  armplat = true,
  armshltxuw = true,
  armsy = true,
  coramsub = true,
  corasy = true,
  corfhp = true,
  corgantuw = true,
  corplat = true,
  corsy = true,
  armason = true,
  armfasp = true,
  armfatf = true,
  armfdrag = true,
  armfgate = true,
  armfmine3 = true,
  armfrad = true,
  armnanotcplat = true,
  armsonar = true,
  corason = true,
  corfasp = true,
  corfatf = true,
  corfdrag = true,
  corfgate = true,
  corfmine3 = true,
  corfrad = true,
  cornanotcplat = true,
  corsonar = true,
  -- Add more building names as needed
}

-- Function to check if a unit or feature is a building or building wreckage
function isBuilding(id)
  -- First, check if it's a unit and a building based on unit definition name
  local unitDefID = spGetUnitDefID(id)
  if unitDefID then
      local unitDef = UnitDefs[unitDefID]
      if unitDef and buildingNames[unitDef.name] then
          return true
      end
  end

  -- If not a unit, check if it's a feature and a building wreckage
  local featureDefID = spGetFeatureDefID(id)
  if featureDefID then
      local featureDef = FeatureDefs[featureDefID]
      -- Check if the feature is reclaimable and has the 'fromunit' custom parameter
      if featureDef and featureDef.reclaimable and featureDef.customParams and featureDef.customParams.fromunit then
          -- Use the 'fromunit' parameter to check against the building names
          return buildingNames[featureDef.customParams.fromunit] == true
      end
  end

  return false -- Not a building or building wreckage
end




-- ///////////////////////////////////////////  processUnits Function
function processUnits(units)
  for unitID, unitData in pairs(units) do
      if isMyResbot(unitID, spGetUnitDefID(unitID)) then  -- Use isMyResbot to check if the unit is a Resbot

          -- Resurrecting Logic
          if checkboxes.resurrecting.state and unitData.taskStatus ~= "in_progress" then
              performResurrection(unitID, unitData)
              if resurrectingUnits[unitID] then return end
          end

          -- Collecting Logic
          if checkboxes.collecting.state and unitData.taskStatus ~= "in_progress" then
              local featureCollected = performCollection(unitID, unitData)
              if featureCollected then return end
          end

          -- Healing Logic
          if checkboxes.healing.state and unitData.taskStatus ~= "in_progress" then
              performHealing(unitID, unitData)
          end
      end
  end
end



-- ///////////////////////////////////////////  UnitCreated Function
function widget:UnitCreated(unitID, unitDefID, unitTeam)
  if isMyResbot(unitID, unitDefID) then  -- Use isMyResbot to check if the unit is a Resbot
    unitsToCollect[unitID] = {
      featureCount = 0,
      lastReclaimedFrame = 0
    }
    processUnits({[unitID] = unitsToCollect[unitID]})
  end
end



-- ///////////////////////////////////////////  UnitDestroyed Function
function widget:FeatureDestroyed(featureID, allyTeam)
  for unitID, data in pairs(unitsToCollect) do
    local unitDefID = spGetUnitDefID(unitID)
    if isMyResbot(unitID, unitDefID) then  -- Use isMyResbot to check if the unit is a Resbot
      if data.featureID == featureID then
        data.featureID = nil
        data.lastReclaimedFrame = Spring.GetGameFrame()
        data.taskStatus = "completed"  -- Marking the task as completed
        processUnits(unitsToCollect)
        break
      end
    end
  end
  targetedFeatures[featureID] = nil  -- Clear the target as the feature is destroyed
end



-- ///////////////////////////////////////////  FeatureDestroyed Function
function widget:FeatureDestroyed(featureID, allyTeam)
  for unitID, data in pairs(unitsToCollect) do
    if data.featureID == featureID then
      data.featureID = nil
      data.lastReclaimedFrame = Spring.GetGameFrame()
      data.taskStatus = "completed"  -- Marking the task as completed
      processUnits(unitsToCollect)
      break
    end
  end
  targetedFeatures[featureID] = nil  -- Clear the target as the feature is destroyed
end



-- /////////////////////////////////////////// GameFrame Function
function widget:GameFrame(currentFrame)
  local stuckCheckInterval = 1000
  local resourceCheckInterval = 300  -- Interval to check and reassign tasks based on resource status
  local actionInterval = 60

  -- Check units moving to safety
  for unitID, _ in pairs(unitsMovingToSafety) do
      if not findNearestEnemy(unitID, enemyAvoidanceRadius) then
          -- No enemy nearby, set the unit to idle
          if unitsToCollect[unitID] then
              unitsToCollect[unitID].taskStatus = "idle"
          end
          unitsMovingToSafety[unitID] = nil
      end
  end

  if currentFrame % actionInterval == 0 then
      -- Process all units for enemy avoidance and other tasks
      for unitID, _ in pairs(unitsToCollect) do
          local unitDefID = spGetUnitDefID(unitID)
          if isMyResbot(unitID, unitDefID) then
              if Spring.ValidUnitID(unitID) and not Spring.GetUnitIsDead(unitID) then
                  maintainSafeDistanceFromEnemy(unitID, enemyAvoidanceRadius)
                  processUnits({[unitID] = unitsToCollect[unitID]})
              end
          end
      end
  end

  if currentFrame % stuckCheckInterval == 0 then
      for unitID, _ in pairs(unitsToCollect) do
          local unitDefID = spGetUnitDefID(unitID)
          if isMyResbot(unitID, unitDefID) then
              handleStuckUnits(unitID, UnitDefs[unitDefID])
          end
      end
  end

  if currentFrame % resourceCheckInterval == 0 then
      local resourceNeed = assessResourceNeeds()
      if resourceNeed ~= "full" then
          for unitID, unitData in pairs(unitsToCollect) do
              if unitData.taskStatus == "idle" or unitData.taskStatus == "completed" then
                  processUnits({[unitID] = unitData})
              end
          end
      end
  end
end



-- ///////////////////////////////////////////  findNearestDamagedFriendly Function
function findNearestDamagedFriendly(unitID, searchRadius)
  local myTeamID = spGetMyTeamID() -- Retrieve your team ID
  local x, y, z = spGetUnitPosition(unitID)
  local unitsInRadius = Spring.GetUnitsInCylinder(x, z, searchRadius)

  local minDistSq = searchRadius * searchRadius
  local nearestDamagedUnit = nil
  for _, otherUnitID in ipairs(unitsInRadius) do
    if otherUnitID ~= unitID then
      local unitDefID = spGetUnitDefID(otherUnitID)
      local unitDef = UnitDefs[unitDefID]

      if unitDef and not unitDef.isAirUnit then -- Check if the unit is not an air unit
        local unitTeam = Spring.GetUnitTeam(otherUnitID)
        if unitTeam == myTeamID then -- Check if the unit belongs to your team
          local health, maxHealth, _, _, buildProgress = Spring.GetUnitHealth(otherUnitID)
          if health and maxHealth and health < maxHealth and buildProgress == 1 then
            local distSq = Spring.GetUnitSeparation(unitID, otherUnitID, true)
            if distSq < minDistSq then
              minDistSq = distSq
              nearestDamagedUnit = otherUnitID
            end
          end
        end
      end
    end
  end

  return nearestDamagedUnit, math.sqrt(minDistSq)
end



-- ///////////////////////////////////////////  findNearestEnemy Function
-- Function to find the nearest enemy and its type
function findNearestEnemy(unitID, searchRadius)
  local x, y, z = spGetUnitPosition(unitID)
  if not x or not z then return nil end  -- Validate unit position
  local unitsInRadius = Spring.GetUnitsInCylinder(x, z, searchRadius, Spring.ENEMY_UNITS)
  

  local minDistSq = searchRadius * searchRadius
  local nearestEnemy, isAirUnit = nil, false

  for _, enemyID in ipairs(unitsInRadius) do
    local enemyDefID = spGetUnitDefID(enemyID)
    local enemyDef = UnitDefs[enemyDefID]
    if enemyDef then
      local ex, ey, ez = spGetUnitPosition(enemyID)
      local distSq = (x - ex)^2 + (z - ez)^2
      if distSq < minDistSq then
        minDistSq = distSq
        nearestEnemy = enemyID
        isAirUnit = enemyDef.isAirUnit
      end
    end
  end

  return nearestEnemy, math.sqrt(minDistSq), isAirUnit
end



-- ///////////////////////////////////////////  maintainSafeDistanceFromEnemy Function
function maintainSafeDistanceFromEnemy(unitID, avoidanceRadius)
  local nearestEnemy, distance, isAirUnit = findNearestEnemy(unitID, avoidanceRadius)
  if nearestEnemy and distance < avoidanceRadius then
      -- Reduce the avoidance radius for air units
      local effectiveAvoidanceRadius = isAirUnit and (avoidanceRadius * 0.25) or avoidanceRadius

      if distance < effectiveAvoidanceRadius then
          local ux, uy, uz = spGetUnitPosition(unitID)
          local ex, ey, ez = spGetUnitPosition(nearestEnemy)

          -- Calculate a direction vector away from the enemy
          local dx, dz = ux - ex, uz - ez
          local magnitude = math.sqrt(dx * dx + dz * dz)

          -- Calculate a safe destination
          local safeDistance = effectiveAvoidanceRadius
          local safeX = ux + (dx / magnitude * safeDistance)
          local safeZ = uz + (dz / magnitude * safeDistance)
          local safeY = Spring.GetGroundHeight(safeX, safeZ)

          -- Issue a move order to the safe destination
          spGiveOrderToUnit(unitID, CMD.MOVE, {safeX, safeY, safeZ}, {})
          
          -- Track the unit as moving to safety
          unitsMovingToSafety[unitID] = true
          return true -- Indicate that the unit is avoiding an enemy
      end
  else
      -- If no enemy is near, remove the unit from tracking
      unitsMovingToSafety[unitID] = nil
      return false -- No enemy avoidance needed
  end
end





-- ///////////////////////////////////////////  assessResourceNeeds Function
function assessResourceNeeds()
  local myTeamID = Spring.GetMyTeamID()
  local currentMetal, storageMetal = Spring.GetTeamResources(myTeamID, "metal")
  local currentEnergy, storageEnergy = Spring.GetTeamResources(myTeamID, "energy")

  local metalRatio = currentMetal / storageMetal
  local energyRatio = currentEnergy / storageEnergy

  if metalRatio >= 0.75 and energyRatio >= 0.75 then
      return "full"
  elseif metalRatio < energyRatio then
      return "metal"
  else
      return "energy"
  end
end




function getFeatureResources(featureID)
  local featureDefID = spGetFeatureDefID(featureID)
  local featureDef = FeatureDefs[featureDefID]
  return featureDef.metal, featureDef.energy
end



-- /////////////////////////////////////////// calculateResourceScore Function
function calculateResourceScore(featureMetal, featureEnergy, distance, resourceNeed)
  local weightDistance = 1  -- Base weight for distance
  local penaltyNotNeeded = 10000  -- Large penalty if the resource is not needed

  local score = distance * weightDistance
  if resourceNeed == "metal" and featureMetal <= 0 then
      score = score + penaltyNotNeeded
  elseif resourceNeed == "energy" and featureEnergy <= 0 then
      score = score + penaltyNotNeeded
  end

  return score
end




-- /////////////////////////////////////////// findReclaimableFeature Function
function findReclaimableFeature(unitID, x, z, searchRadius, resourceNeed)
  local featuresInRadius = spGetFeaturesInCylinder(x, z, searchRadius)
  local bestFeature = nil
  local bestScore = math.huge

  for _, featureID in ipairs(featuresInRadius) do
      local featureDefID = spGetFeatureDefID(featureID)
      local featureDef = FeatureDefs[featureDefID]
      local featureMetal, featureEnergy = getFeatureResources(featureID)

      if featureDef and featureDef.reclaimable then
          local featureX, _, featureZ = Spring.GetFeaturePosition(featureID)
          local distanceToFeature = ((featureX - x)^2 + (featureZ - z)^2)^0.5
          local score = calculateResourceScore(featureMetal, featureEnergy, distanceToFeature, resourceNeed)

          if score < bestScore and (not targetedFeatures[featureID] or targetedFeatures[featureID] < maxUnitsPerFeature) then
              bestScore = score
              bestFeature = featureID
          end
      end
  end

  return bestFeature
end



-- Healing Function
function performHealing(unitID, unitData)
  local nearestDamagedUnit, distance = findNearestDamagedFriendly(unitID, healResurrectRadius)
  if nearestDamagedUnit and distance < healResurrectRadius then
      healingTargets[nearestDamagedUnit] = healingTargets[nearestDamagedUnit] or 0
      if healingTargets[nearestDamagedUnit] < maxHealersPerUnit and not healingUnits[unitID] then
          Spring.GiveOrderToUnit(unitID, CMD.REPAIR, {nearestDamagedUnit}, {})
          healingUnits[unitID] = nearestDamagedUnit
          healingTargets[nearestDamagedUnit] = healingTargets[nearestDamagedUnit] + 1
          unitData.taskType = "healing"
          unitData.taskStatus = "in_progress"
        else
          -- Explicitly mark the unit as idle if no damaged unit is found
          unitData.taskStatus = "idle"
      end
  end
end



-- Collection Function
function performCollection(unitID, unitData)
  local resourceNeed = assessResourceNeeds()
  if resourceNeed ~= "full" then
      local x, y, z = spGetUnitPosition(unitID)
      local featureID = findReclaimableFeature(unitID, x, z, reclaimRadius, resourceNeed)
      if featureID and Spring.ValidFeatureID(featureID) then
          spGiveOrderToUnit(unitID, CMD_RECLAIM, {featureID + Game.maxUnits}, {})
          unitData.featureCount = 1
          unitData.lastReclaimedFrame = Spring.GetGameFrame()
          targetedFeatures[featureID] = (targetedFeatures[featureID] or 0) + 1
          unitData.taskType = "reclaiming"
          unitData.taskStatus = "in_progress"
          return true
      end
  end
  return false
end




-- Resurrection Function
function performResurrection(unitID, unitData)
  local resurrectableFeatures = resurrectNearbyDeadUnits(unitID, healResurrectRadius)
  if #resurrectableFeatures > 0 then
      for i, featureID in ipairs(resurrectableFeatures) do
          local wreckageDefID = Spring.GetFeatureDefID(featureID)
          local feature = FeatureDefs[wreckageDefID]

          -- Exclude buildings if checkbox is checked
          if not (checkboxes.excludeBuildings.state and isBuilding(featureID)) then
              if feature.customParams["category"] == "corpses" then
                  if Spring.ValidFeatureID(featureID) then
                      spGiveOrderToUnit(unitID, CMD.RESURRECT, {featureID + Game.maxUnits}, {})
                      unitData.taskType = "resurrecting"
                      unitData.taskStatus = "in_progress"
                      resurrectingUnits[unitID] = true
                      return -- Exit after issuing the first valid order
                  end
              end
          end
      end
  end

  -- No features to resurrect, mark as idle to reassign
  unitData.taskStatus = "idle"
end



-- /////////////////////////////////////////// resurrectNearbyDeadUnits Function
local maxFeaturesToConsider = 10 -- Maximum number of features to consider

-- Function to resurrect nearby dead units, excluding buildings if specified
function resurrectNearbyDeadUnits(unitID, healResurrectRadius)
  local x, y, z = spGetUnitPosition(unitID)
  if not x or not z then return {} end

  local allFeatures = Spring.GetFeaturesInCylinder(x, z, healResurrectRadius)
  local nearestFeatures = {}

  for _, featureID in ipairs(allFeatures) do
      local featureDefID = spGetFeatureDefID(featureID)
      local featureDef = FeatureDefs[featureDefID]

      -- Check if the feature is a building and if it should be excluded
      if featureDef and featureDef.reclaimable and featureDef.resurrectable and 
         (not checkboxes.excludeBuildings.state or not isBuilding(featureID)) then
          local fx, fy, fz = spGetFeaturePosition(featureID)
          local distanceSq = (x - fx)^2 + (z - fz)^2

          if #nearestFeatures < maxFeaturesToConsider then
              nearestFeatures[#nearestFeatures + 1] = {id = featureID, distanceSq = distanceSq}
          else
              -- Replace the farthest feature if the current one is nearer
              local farthestIndex, farthestDistanceSq = 1, nearestFeatures[1].distanceSq
              for i, featureData in ipairs(nearestFeatures) do
                  if featureData.distanceSq > farthestDistanceSq then
                      farthestIndex, farthestDistanceSq = i, featureData.distanceSq
                  end
              end
              if distanceSq < farthestDistanceSq then
                  nearestFeatures[farthestIndex] = {id = featureID, distanceSq = distanceSq}
              end
          end
      end
  end

  -- Sort the nearest features by distance
  table.sort(nearestFeatures, function(a, b) return a.distanceSq < b.distanceSq end)

  -- Extract feature IDs from the table
  local featureIDs = {}
  for _, featureData in ipairs(nearestFeatures) do
      table.insert(featureIDs, featureData.id)
  end

  return featureIDs
end



-- ///////////////////////////////////////////  UnitIdle Function
function widget:UnitIdle(unitID)
  local unitDefID = spGetUnitDefID(unitID)
  if not unitDefID then return end  -- Check if unitDefID is valid

  -- Get the unit definition using unitDefID
  local unitDef = UnitDefs[unitDefID]
  if not unitDef then return end -- Check if the unitDef is valid

  -- Check if the unit is a Resbot
  if not isMyResbot(unitID, unitDefID) then return end

  -- Initialize unitData if it does not exist for this unit
  local unitData = unitsToCollect[unitID]
  if not unitData then
      unitData = {
          featureCount = 0,
          lastReclaimedFrame = 0,
          taskStatus = "idle",
          featureID = nil  -- Make sure to initialize all fields that will be used
      }
      unitsToCollect[unitID] = unitData
  else
      unitData.taskStatus = "idle"
  end

  -- Re-queue the unit for tasks based on the checkbox states
  if (unitDef.canReclaim and checkboxes.collecting.state) or
     (unitDef.canResurrect and checkboxes.resurrecting.state) or
     (unitDef.canRepair and checkboxes.healing.state) then
      processUnits({[unitID] = unitData})
  end

  -- Manage targeted features and healing units
  if unitData.featureID then
      targetedFeatures[unitData.featureID] = (targetedFeatures[unitData.featureID] or 0) - 1
      if targetedFeatures[unitData.featureID] <= 0 then
          targetedFeatures[unitData.featureID] = nil
      end
      unitData.featureID = nil  -- Reset featureID since the unit is idle now
  end

  if healingUnits[unitID] then
      local healedUnitID = healingUnits[unitID]
      healingTargets[healedUnitID] = (healingTargets[healedUnitID] or 0) - 1
      if healingTargets[healedUnitID] <= 0 then
          healingTargets[healedUnitID] = nil
      end
      healingUnits[unitID] = nil
  end

  if resurrectingUnits[unitID] then
      resurrectingUnits[unitID] = nil
  end
end



-- ///////////////////////////////////////////  isUnitStuck Function
local lastStuckCheck = {}
local checkInterval = 500  -- Number of game frames to wait between checks

function isUnitStuck(unitID)
  local currentFrame = Spring.GetGameFrame()
  if lastStuckCheck[unitID] and (currentFrame - lastStuckCheck[unitID]) < checkInterval then
    return false  -- Skip check if within the cooldown period
  end

  lastStuckCheck[unitID] = currentFrame

  local minMoveDistance = 2  -- Define the minimum move distance, adjust as needed
  local x, y, z = spGetUnitPosition(unitID)
  local lastPos = unitLastPosition[unitID] or {x = x, y = y, z = z}
  local stuck = (math.abs(lastPos.x - x)^2 + math.abs(lastPos.z - z)^2) < minMoveDistance^2
  unitLastPosition[unitID] = {x = x, y = y, z = z}
  return stuck
end



-- ///////////////////////////////////////////  handleStuckUnits Function
function handleStuckUnits(unitID, unitDef)
  -- Check if the unitDef is nil, and if so, retrieve it
  if not unitDef then
      local unitDefID = spGetUnitDefID(unitID)
      unitDef = UnitDefs[unitDefID]
  end

  if isMyResbot(unitID, unitDefID) then  -- Use isMyResbot to check if the unit is a Resbot
    if isUnitStuck(unitID) then
          -- Directly reassign task to the unit
          unitsToCollect[unitID] = {
              featureCount = 0,
              lastReclaimedFrame = 0,
              taskStatus = "idle"  -- Mark as idle so it can be reassigned
          }
          processUnits({[unitID] = unitsToCollect[unitID]})
      end
  end
end
-- /////////////////////////////////////////// GetInfo Function
function widget:GetInfo()
  return {
    name      = "SCV",
    desc      = "RezBots Resurrect, Collect resources, and heal injured units. alt+c to open UI",
    author    = "Tumeden",
    date      = "2024",
    version   = "v1.04",
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
local resurrectingUnits = {}  -- table to keep track of units currently resurrecting
local unitsToCollect = {}  -- table to keep track of units and their collection state
local lastAvoidanceTime = {} -- Table to track the last avoidance time for each unit
local healingUnits = {}  -- table to keep track of healing units
local unitLastPosition = {} -- Track the last position of each unit
local targetedFeatures = {}  -- Table to keep track of targeted features
local maxUnitsPerFeature = 4  -- Maximum units allowed to target the same feature
local healingTargets = {}  -- Track which units are being healed and by how many healers
local maxHealersPerUnit = 4  -- Maximum number of healers per unit
local healResurrectRadius = 1000 -- Set your desired heal/resurrect radius here  (default 1000,  anything larger will cause significant lag)
local reclaimRadius = 1500 -- Set your desired reclaim radius here (any number works, 4000 is about half a large map)
local retreatRadius = 425  -- The detection area around the SCV unit, which causes it to retreat.
local enemyAvoidanceRadius = 925  -- Adjust this value as needed -- Define a safe distance for enemy avoidance
local avoidanceCooldown = 30 -- Cooldown in game frames, 30 Default.

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
  retreatRadius = { x = windowPos.x + 50, y = windowPos.y + 260, width = 200, value = retreatRadius, min = 0, max = 2000, label = "Retreat Distance" },
  enemyAvoidanceRadius = { x = windowPos.x + 50, y = windowPos.y + 290, width = 200, value = enemyAvoidanceRadius, min = 0, max = 2000, label = "Enemy Avoidance Radius" },
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
      elseif activeSlider == sliders.retreatRadius then
          retreatRadius = newValue
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


-- Function to check if a unit is a building
function isBuilding(unitID)
  local unitDefID = Spring.GetUnitDefID(unitID)
  if not unitDefID then return false end  -- Check if unitDefID is valid

  local unitDef = UnitDefs[unitDefID]
  if not unitDef then return false end  -- Check if unitDef is valid

  -- Check if the unit is a building
  return unitDef.isBuilding or unitDef.isImmobile or false
end


-- ///////////////////////////////////////////  UnitCreated Function
function widget:UnitCreated(unitID, unitDefID, unitTeam)
  if unitDefID == armRectrDefID or unitDefID == corNecroDefID then
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
    if unitDefID == armRectrDefID or unitDefID == corNecroDefID then
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
  local stuckCheckInterval = 3000
  local actionInterval = 60
  local unitsPerFrame = 5

  if currentFrame % stuckCheckInterval == 0 then
      for unitID, _ in pairs(unitsToCollect) do
          local unitDefID = spGetUnitDefID(unitID)
          if unitDefID == armRectrDefID or unitDefID == corNecroDefID then
              local unitDef = UnitDefs[unitDefID]
              if unitDef and (unitDef.canReclaim and unitDef.canResurrect) and Spring.ValidUnitID(unitID) and not Spring.GetUnitIsDead(unitID) then
                  handleStuckUnits(unitID, unitDef)
              end
          end
      end
  end

  if currentFrame % actionInterval == 0 then
      local processedCount = 0
      for unitID, _ in pairs(unitsToCollect) do
          if processedCount >= unitsPerFrame then break end
          local unitDefID = spGetUnitDefID(unitID)
          if unitDefID == armRectrDefID or unitDefID == corNecroDefID then
              if Spring.ValidUnitID(unitID) and not Spring.GetUnitIsDead(unitID) then
                  checkAndRetreatIfNeeded(unitID, retreatRadius)
                  processUnits({[unitID] = unitsToCollect[unitID]})
                  processedCount = processedCount + 1
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

-- ///////////////////////////////////////////  avoidEnemy Function
function avoidEnemy(unitID, enemyID)
  local currentTime = Spring.GetGameFrame()

  -- Retrieve unitDefID for the unit
  local unitDefID = spGetUnitDefID(unitID)

  -- Check if the unit is a RezBot
  if unitDefID == armRectrDefID or unitDefID == corNecroDefID then
    -- Check if the unit is still in cooldown period
    if lastAvoidanceTime[unitID] and (currentTime - lastAvoidanceTime[unitID]) < avoidanceCooldown then
      return -- Skip avoidance if still in cooldown
    end

    local ux, uy, uz = spGetUnitPosition(unitID)
    local ex, ey, ez = spGetUnitPosition(enemyID)

    -- Calculate a direction vector away from the enemy
    local dx, dz = ux - ex, uz - ez
    local magnitude = math.sqrt(dx * dx + dz * dz)

    -- Adjusted safe distance calculation
    local safeDistanceMultiplier = 0.5  -- Retreat half the distance of the avoidance radius
    local safeDistance = enemyAvoidanceRadius * safeDistanceMultiplier

    -- Calculate a safe destination
    local safeX = ux + (dx / magnitude * safeDistance)
    local safeZ = uz + (dz / magnitude * safeDistance)
    local safeY = Spring.GetGroundHeight(safeX, safeZ)

    -- Issue a move order to the safe destination
    spGiveOrderToUnit(unitID, CMD.MOVE, {safeX, safeY, safeZ}, {})

    -- Update the last avoidance time for this unit
    lastAvoidanceTime[unitID] = currentTime
  end
end


-- ///////////////////////////////////////////  assessResourceNeeds Function
function assessResourceNeeds()
  local myTeamID = Spring.GetMyTeamID()
  local currentMetal, storageMetal = Spring.GetTeamResources(myTeamID, "metal")
  local currentEnergy, storageEnergy = Spring.GetTeamResources(myTeamID, "energy")

  local metalFull = currentMetal >= storageMetal * 0.75  -- 75% full
  local energyFull = currentEnergy >= storageEnergy * 0.75  -- 75% full

  if metalFull and energyFull then
    return "none"
  elseif metalFull then
    return "energy"
  elseif energyFull then
    return "metal"
  else
    return "proximity" -- Neither resource is full, focus on proximity
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

  -- Calculate base score using distance
  local score = distance * weightDistance

  -- Add penalty if the resource is not needed
  if (resourceNeed == "metal" and featureMetal <= 0) or (resourceNeed == "energy" and featureEnergy <= 0) then
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
      end
  end
end

-- Collection Function
function performCollection(unitID, unitData)
  local resourceNeed = assessResourceNeeds()
  if resourceNeed ~= "none" then
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

  -- No features to resurrect, mark as idle to reassign
  unitData.taskStatus = "idle"
end



-- ///////////////////////////////////////////  processUnits Function
function processUnits(units)
  for unitID, unitData in pairs(units) do
      local unitDefID = spGetUnitDefID(unitID)
      if unitDefID == armRectrDefID or unitDefID == corNecroDefID then

              -- Check if unit is valid and exists
      if not Spring.ValidUnitID(unitID) or Spring.GetUnitIsDead(unitID) then
        return -- Skip invalid or dead units
    end

    -- Skip if the unit is currently engaged in a task
    if unitData.taskStatus == "in_progress" then
        return
    end

    -- Check if the unit is fully built
    local _, _, _, _, buildProgress = Spring.GetUnitHealth(unitID)
    if buildProgress < 1 then
        -- Skip this unit as it's still being built
        return
    end

          -- Avoid enemies if necessary
          local nearestEnemy, distance = findNearestEnemy(unitID, enemyAvoidanceRadius)
          if nearestEnemy and distance < enemyAvoidanceRadius then
              avoidEnemy(unitID, nearestEnemy)
              unitData.taskType = "avoidingEnemy"
              unitData.taskStatus = "in_progress"
              return
          end

          -- Resurrecting Logic
          if checkboxes.resurrecting.state then
              performResurrection(unitID, unitData)
              if resurrectingUnits[unitID] then return end
          end

          -- Collecting Logic
          if checkboxes.collecting.state then
              local featureCollected = performCollection(unitID, unitData)
              if featureCollected then return end
          end

          -- Healing Logic
          if checkboxes.healing.state then
              performHealing(unitID, unitData)
          end
      end
  end
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



-- ///////////////////////////////////////////  checkAndRetreatIfNeeded Function
function checkAndRetreatIfNeeded(unitID, retreatRadius)
  local unitDefID = spGetUnitDefID(unitID)
  local nearestEnemy, distance = findNearestEnemy(unitID, retreatRadius)

  -- Only execute retreat logic if the unit is a rezbot
  if unitDefID == armRectrDefID or unitDefID == corNecroDefID then
    if nearestEnemy and distance < retreatRadius then
      -- Issue the move order only if the unit should retreat
      avoidEnemy(unitID, nearestEnemy, distance)
    end
  end
end





-- ///////////////////////////////////////////  UnitIdle Function
function widget:UnitIdle(unitID)
  local unitDefID = spGetUnitDefID(unitID)
  if not unitDefID then return end  -- Check if unitDefID is valid
  local unitDef = UnitDefs[unitDefID]
  if not unitDef then return end  -- Check if unitDef is valid

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
      -- Spring.Echo("UnitIdle: Initialized unitsToCollect entry for unitID:", unitID)
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

  -- Clean up any state related to healing, resurrecting, or collecting
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

  -- Additional cleanup or re-queue logic can go here, if needed
end





-- ///////////////////////////////////////////  isUnitStuck Function
local lastStuckCheck = {}
local checkInterval = 1000  -- Number of game frames to wait between checks

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

  if unitDefID == armRectrDefID or unitDefID == corNecroDefID then
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





-- /////////////////////////////////////////// GetInfo Function
function widget:GetInfo()
  return {
    name      = "SCV",
    desc      = "RezBots Resurrect, Collect resources, and heal injured units.",
    author    = "Tumeden",
    date      = "2024",
    version   = "v4.9",
    license   = "GNU GPL, v2 or later",
    layer     = 0,
    enabled   = true
  }
end


-- ///////////////////////////////////////////  Adjustable variables, to suit the widget users preference

local healResurrectRadius = 1000 -- Set your desired heal/resurrect radius here  (default 1000,  anything larger will cause significant lag)
local reclaimRadius = 4000 -- Set your desired reclaim radius here (any number works, 4000 is about half a large map)
local retreatRadius = 800  -- The detection area around the SCV unit, which causes it to retreat.
local enemyAvoidanceRadius = 675  -- Adjust this value as needed -- Define a safe distance for enemy avoidance
local closeHealingThreshold = 300 -- Units within this range will prioritize healing



-- /////////////////////////////////////////// ---- /////////////////////////////////////////// ---- /////////////////////////////////////////// 
-- /////////////////////////////////////////// ---                Main Code                     ---- /////////////////////////////////////////// 
-- /////////////////////////////////////////// ----  Do not edit things past this line          ---- ///////////////////////////////////////////



-- /////////////////////////////////////////// Important things :))
local widgetEnabled = true
local optimizedPathsCache = {}
local resurrectionCache = {}
local resurrectingUnits = {}  -- table to keep track of units currently resurrecting
local unitsToCollect = {}  -- table to keep track of units and their collection state
local lastAvoidanceTime = {} -- Table to track the last avoidance time for each unit
local healingUnits = {}  -- table to keep track of healing units
local unitLastPosition = {} -- Track the last position of each unit
local targetedFeatures = {}  -- Table to keep track of targeted features
local maxUnitsPerFeature = 4  -- Maximum units allowed to target the same feature
local healingTargets = {}  -- Track which units are being healed and by how many healers
local maxHealersPerUnit = 4  -- Maximum number of healers per unit
local unitTaskStatus = {}
local CMD_RECLAIM = CMD.RECLAIM
local avoidanceCooldown = 30 -- Cooldown in game frames, 30 Default.

-- engine call optimizations
-- =========================
local spGetUnitDefID = Spring.GetUnitDefID
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spGetUnitPosition = Spring.GetUnitPosition
local spGetFeaturesInCylinder = Spring.GetFeaturesInCylinder
local spGetFeatureDefID = Spring.GetFeatureDefID
local spGetMyTeamID = Spring.GetMyTeamID
local spGetTeamResources = Spring.GetTeamResources
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




-- /////////////////////////////////////////// -- /////////////////////////////////////////// --
-- /////////////////////////////////////////// -- /////////////////////////////////////////// --
-- ////////////////////////////////////////- UI CODE -////////////////////////////////////// --
-- /////////////////////////////////////////// -- /////////////////////////////////////////// --
-- /////////////////////////////////////////// -- /////////////////////////////////////////// --


-- /////////////////////////////////////////// UI Variables
-- UI Constants and Variables
local windowSize = { width = 300, height = 400 }
local vsx, vsy = Spring.GetViewGeometry() -- Screen dimensions
local windowPos = { x = (vsx - windowSize.width) / 2, y = (vsy - windowSize.height) / 2 } -- Center the window

local checkboxes = {
  healing = { x = windowPos.x + 30, y = windowPos.y + 50, size = 20, state = true, label = "Enable Healing" },
  resurrecting = { x = windowPos.x + 30, y = windowPos.y + 80, size = 20, state = true, label = "Enable Resurrecting" },
  collecting = { x = windowPos.x + 30, y = windowPos.y + 110, size = 20, state = true, label = "Enable Collecting" },
}

-- Define UI elements relative to the window
local button = { x = windowPos.x + 50, y = windowPos.y + 50, width = 100, height = 30, text = "Toggle Widget", state = widgetEnabled }
local slider = { x = windowPos.x + 50, y = windowPos.y + 100, width = 200, value = healResurrectRadius, min = 100, max = 2000 }

-- Utility function for point inside rectangle
local function isInsideRect(x, y, rect)
    return x >= rect.x and x <= (rect.x + rect.width) and y >= rect.y and y <= (rect.y + rect.height)
end



-- /////////////////////////////////////////// KeyPress Function Modification
function widget:KeyPress(key, mods, isRepeat)
  if key == 0x0063 and mods.alt then -- 0x0063 is the key code for "c"
      showUI = not showUI
      return true
  end
  return false
end


-- /////////////////////////////////////////// Drawing the UI
function widget:DrawScreen()
  if showUI then
      -- Draw the window background
      gl.Color(0, 0, 0, 0.7)
      gl.Rect(windowPos.x, windowPos.y, windowPos.x + windowSize.width, windowPos.y + windowSize.height)

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
          end
          gl.Text(box.label, box.x + box.size + 10, box.y, 12)
      end
  end
end


-- /////////////////////////////////////////// Handling UI Interactions
function widget:MousePress(x, y, button)
  if showUI then
      -- Existing button and slider interaction code...

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
  -- Handle mouse move events, especially for dragging the slider knob
end

function widget:MouseRelease(x, y, button)
  -- Handle mouse release events if necessary
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
  local armRectrDefID, corNecroDefID

  -- Check and store the UnitDefIDs for the rezbots
  if UnitDefNames and UnitDefNames.armrectr and UnitDefNames.cornecro then
      armRectrDefID = UnitDefNames.armrectr.id
      corNecroDefID = UnitDefNames.cornecro.id
  else
      -- Handle the case where UnitDefNames are not available or units are undefined
      Spring.Echo("Rezbot UnitDefIDs could not be determined")
      widgetHandler:RemoveWidget(self)
      return
  end

  -- Store rezbots UnitDefIDs globally within the widget for later use
  self.armRectrDefID = armRectrDefID
  self.corNecroDefID = corNecroDefID
end


-- ///////////////////////////////////////////  UnitCreated Function
function widget:UnitCreated(unitID, unitDefID, unitTeam)
  -- Check if the unit is a rezbot
  if unitDefID ~= self.armRectrDefID and unitDefID ~= self.corNecroDefID then
    -- Skip processing for non-rezbots
    return
end

  local unitDef = UnitDefs[unitDefID]
      -- Initialize unit to collect resources
      unitsToCollect[unitID] = {
          featureCount = 0,
          lastReclaimedFrame = 0
      }

      processUnits({[unitID] = unitsToCollect[unitID]})
end


-- ///////////////////////////////////////////  UnitDestroyed Function
function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
  -- Check if the unit is a rezbot
  if unitDefID == self.armRectrDefID or unitDefID == self.corNecroDefID then
      unitsToCollect[unitID] = nil

      local units = Spring.GetTeamUnits(Spring.GetMyTeamID())
      for _, uID in ipairs(units) do
          local uDefID = spGetUnitDefID(uID)
          local uDef = UnitDefs[uDefID]
          local unitCommands = Spring.GetUnitCommands(uID, 1)

          if uID ~= unitID and uDefID == self.armRectrDefID or uDefID == self.corNecroDefID and (not unitCommands or #unitCommands == 0) then
              unitsToCollect[uID] = { featureCount = 0, lastReclaimedFrame = 0 }
              processUnits({[uID] = unitsToCollect[uID]})
              break
          end
      end
  end
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
  -- Interval for checking stuck units
  local stuckCheckInterval = 3000  -- Number of game frames to wait between checks

  -- Interval for avoidance and other actions
  local actionInterval = 60  -- Check every 60 frames (approximately 2 seconds at 30 FPS)

  -- Handle stuck units
  if currentFrame % stuckCheckInterval == 0 then
      for unitID, _ in pairs(unitsToCollect) do
          local unitDefID = spGetUnitDefID(unitID)
          local unitDef = UnitDefs[unitDefID]
          if unitDef and (unitDef.canReclaim and unitDef.canResurrect) and Spring.ValidUnitID(unitID) and not Spring.GetUnitIsDead(unitID) then
              handleStuckUnits(unitID, unitDef)
          end
      end
  end

  -- Regular actions performed at specified intervals
  if currentFrame % actionInterval == 0 then
      if widgetEnabled then
          for unitID, _ in pairs(unitsToCollect) do
              -- Check if unit is valid and exists
              if Spring.ValidUnitID(unitID) and not Spring.GetUnitIsDead(unitID) then
                  checkAndRetreatIfNeeded(unitID, retreatRadius)

                  -- Process units for tasks like collecting, healing, and resurrecting
                  processUnits({[unitID] = unitsToCollect[unitID]})
              end
          end
      end
  end
end





-- ///////////////////////////////////////////  avoidEnemy Function
function avoidEnemy(unitID, enemyID)
  local currentTime = Spring.GetGameFrame()

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



-- ///////////////////////////////////////////  processUnits Function
-- /////////////////////////////////////////// processUnits Function
function processUnits(units)
  for unitID, unitData in pairs(units) do
      -- Check if unit is valid and exists
      if not Spring.ValidUnitID(unitID) or Spring.GetUnitIsDead(unitID) then
          return -- Skip invalid or dead units
      end

      local unitDefID = spGetUnitDefID(unitID)
      -- Check if the unit is a commander
      if unitDefID == UnitDefNames.armcom.id or unitDefID == UnitDefNames.corcom.id then
          -- Skip processing for commanders
          return
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

      -- Check if the unit is already tasked with resurrecting
      if resurrectingUnits[unitID] then
          return -- Skip this unit as it's already resurrecting something
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
            local resurrectableFeatures = resurrectNearbyDeadUnits(unitID, healResurrectRadius)
            if #resurrectableFeatures > 0 then
                local orders = generateOrders(resurrectableFeatures, false, nil)
                for _, order in ipairs(orders) do
                    if Spring.ValidFeatureID(order[2] - Game.maxUnits) then
                        spGiveOrderToUnit(unitID, order[1], order[2], order[3])
                    end
                end
                unitData.taskType = "resurrecting"
                unitData.taskStatus = "in_progress"
                resurrectingUnits[unitID] = true
                return
            end
        end

        -- Collecting Logic
        if checkboxes.collecting.state then
            local resourceNeed = assessResourceNeeds()
            local featureCollected = false

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
                    featureCollected = true
                end
            end
        end

        -- Healing Logic
        if checkboxes.healing.state and not featureCollected then
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
    end
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


-- ///////////////////////////////////////////  ressurectNearbyDeadUnits Function
local resurrectionCacheTimeout = 30 * 60  -- Cache timeout in game frames (e.g., 30 seconds at 60 fps)

function resurrectNearbyDeadUnits(unitID, healResurrectRadius)
    local cache = resurrectionCache[unitID]
    local currentFrame = Spring.GetGameFrame()

    -- Check if cache is valid
    if cache and (currentFrame - cache.lastUpdate < resurrectionCacheTimeout) then
        return cache.targets  -- Return cached data
    end

    -- Update cache
    local x, y, z = spGetUnitPosition(unitID)
    local features = Spring.GetFeaturesInCylinder(x, z, healResurrectRadius)
    local filteredFeatures = filterFeatures(features)
    local orderedFeatures = orderFeatureIdsByEfficientTraversalPath(unitID, filteredFeatures, {})

    resurrectionCache[unitID] = {
        targets = orderedFeatures,
        lastUpdate = currentFrame
    }

    return orderedFeatures
end



-- ///////////////////////////////////////////  checkAndRetreatIfNeeded Function
function checkAndRetreatIfNeeded(unitID, retreatRadius)
  local nearestEnemy, distance = findNearestEnemy(unitID, retreatRadius)

  -- Check if the unit is not a commander or a construction bot before retreating
  local unitDefID = spGetUnitDefID(unitID)
  if unitDefID ~= armComDefID and unitDefID ~= corComDefID then
    local unitDef = UnitDefs[unitDefID]
    if unitDef and not unitDef.isBuilder then
      if nearestEnemy and distance < retreatRadius then
        -- Process avoidance and retreat in a unified manner
        avoidEnemy(unitID, nearestEnemy, distance)
      end
    end
  end
end





-- ///////////////////////////////////////////  UnitIdle Function
function widget:UnitIdle(unitID)
  local unitDefID = spGetUnitDefID(unitID)
  local unitDef = UnitDefs[unitDefID]

  if not unitDef then
      return -- Exit early if the unitDef is nil
  end

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

  -- Ensure the unit has the capabilities (canReclaim, canResurrect)
  if unitDef and (unitDef.canReclaim and unitDef.canResurrect) then
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








-- /////////// TESTING STUFF 



function filterFeatures(features)
  local filteredFeatures = {}

  -- Filter out trees, tombstones, etc.
  for _, featureID in ipairs(features) do
      local wreckageDefID = Spring.GetFeatureDefID(featureID)
      local feature = FeatureDefs[wreckageDefID]

      if feature.reclaimable and (feature.metal > 0) then
          table.insert(filteredFeatures, featureID)
      end
  end

  return filteredFeatures
end

function generateOrders(features, addToQueue, returnPos)
  local orders = {}

  for i, featureID in ipairs(features) do
      local wreckageDefID = Spring.GetFeatureDefID(featureID)
      local feature = FeatureDefs[wreckageDefID]

      -- feature.resurrectable is nonzero for rocks etc. Checking for "corpses" is a workaround.
      if feature.customParams["category"] == "corpses" then
          table.insert(orders, {CMD.RESURRECT, featureID + Game.maxUnits, {shift = false}})
      else -- We already filtered out non-reclaimable stuff.
          table.insert(orders, {CMD.RECLAIM, featureID + Game.maxUnits, {shift = false}})
      end

      -- Break after the first order to ensure only one task is handled at a time
      break
  end

  if returnPos then
      table.insert(orders, {CMD.MOVE, returnPos, {shift = false}})
  end

  return orders
end



-- Calculates the 2D Euclidean distance between two points
function dist2D(x1, z1, x2, z2)
  return math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2)
end

-- Computes the total distance of the path that visits all the features in the given order
function computePathDistance(order, positions)
  local distance = 0
  for i = 2, #order do
      local x1, _, z1 = unpack(positions[order[i - 1]])
      local x2, _, z2 = unpack(positions[order[i]])
      distance = distance + dist2D(x1, z1, x2, z2)
  end
  return distance
end

-- Applies the 2-opt heuristic to the given path to find a locally optimal solution
function optimizePath(path, positions)
  local improved = true
  while improved do
      improved = false
      for i = 1, #path - 2 do
          for j = i + 1, #path - 1 do
              local order = {}
              for k = 1, #path do
                  if k < i or k > j then
                      table.insert(order, path[k])
                  end
              end
              for k = j, i, -1 do
                  table.insert(order, path[k])
              end
              for k = j + 1, #path do
                  table.insert(order, path[k])
              end
              local newDist = computePathDistance(order, positions)
              local oldDist = computePathDistance(path, positions)
              if newDist < oldDist then
                  path = order
                  improved = true
              end
          end
      end
  end
  return path
end

function orderFeatureIdsByEfficientTraversalPath(unitId, featureIds, optimizedPathsCache)
  -- Ensure cache is initialized
  optimizedPathsCache = optimizedPathsCache or {}

  -- Verify featureIds contains valid IDs
  if not featureIds or #featureIds == 0 then
     -- Spring.Echo("Warning: No valid feature IDs provided to orderFeatureIdsByEfficientTraversalPath")
      return {} -- Return an empty table if no features to process
  end

  -- Get the positions of the unit and features
  local positions = {}
  positions[unitId] = {Spring.GetUnitPosition(unitId)}
  for _, id in ipairs(featureIds) do
      positions[id] = {Spring.GetFeaturePosition(id)}
  end

  -- Apply the nearest neighbor algorithm to find a suboptimal solution
  local path = {unitId}
  local visited = {[unitId] = true}
  local firstId = nil

  while #path < #featureIds + 1 do
      local bestDist = math.huge
      local bestId = nil
      for _, id in ipairs(featureIds) do
          if not visited[id] then
              local currentFeatureId = path[#path]
              local currentFeaturePos = positions[currentFeatureId]
              local nextFeaturePos = positions[id]
              if currentFeaturePos and nextFeaturePos then
                  local dist = dist2D(currentFeaturePos[1], currentFeaturePos[3], nextFeaturePos[1], nextFeaturePos[3])
                  if not bestId or dist < bestDist then
                      bestDist = dist
                      bestId = id
                  end
              end
          end
      end

      if bestId then
          if not firstId then
              firstId = bestId
          end
          table.insert(path, bestId)
          visited[bestId] = true
      else
          break -- No unvisited features left, exit loop
      end
  end

  -- Apply the 2-opt heuristic to improve the solution
  path = optimizePath(path, positions)

  -- Remove the starting unit from the path
  table.remove(path, 1)

  -- Return the ordered featureIds
  local orderedFeatureIds = {}
  for _, id in ipairs(path) do
      if id ~= unitId then -- Ensure not to add the unitId itself
          orderedFeatureIds[#orderedFeatureIds + 1] = id
      end
  end

  -- Check if firstId was found
  if not firstId then
      Spring.Echo("Warning: firstId is nil after processing features. No features were found within range or all features are invalid.")
      return {} -- Return an empty table if no valid firstId found
  end

    -- Add result to cache.
    if firstId ~= nil then
      optimizedPathsCache[firstId] = orderedFeatureIds
  end

  return orderedFeatureIds
end



-- Helper function: Applies the 2-opt heuristic to the given path to find a locally optimal solution
function optimizePath(path, positions)
  local improved = true
  while improved do
      improved = false
      for i = 1, #path - 2 do
          for j = i + 1, #path - 1 do
              local order = {}
              for k = 1, #path do
                  if k < i or k > j then
                      table.insert(order, path[k])
                  end
              end
              for k = j, i, -1 do
                  table.insert(order, path[k])
              end
              for k = j + 1, #path do
                  table.insert(order, path[k])
              end
              local newDist = computePathDistance(order, positions)
              local oldDist = computePathDistance(path, positions)
              if newDist < oldDist then
                  path = order
                  improved = true
              end
          end
      end
  end
  return path
end

-- Helper function: Computes the total distance of the path that visits all the features in the given order
function computePathDistance(order, positions)
  local distance = 0
  for i = 2, #order do
      local x1, _, z1 = unpack(positions[order[i - 1]])
      local x2, _, z2 = unpack(positions[order[i]])
      distance = distance + dist2D(x1, z1, x2, z2)
  end
  return distance
end


function resurrectNearbyDeadUnits(unitID, healResurrectRadius)
  local x, y, z = spGetUnitPosition(unitID)
  if not x or not z then return {} end

  local features = Spring.GetFeaturesInCylinder(x, z, healResurrectRadius)
  local filteredFeatures = filterFeatures(features)
  local orderedFeatures = orderFeatureIdsByEfficientTraversalPath(unitID, filteredFeatures, optimizedPathsCache)

  return orderedFeatures
end



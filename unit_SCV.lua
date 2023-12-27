-- /////////////////////////////////////////// GetInfo Function
function widget:GetInfo()
  return {
    name      = "SCV",
    desc      = "Collects resources, and heals injured units.",
    author    = "Tumeden",
    date      = "2024",
    version   = "v4.1",
    license   = "GNU GPL, v2 or later",
    layer     = 0,
    enabled   = true
  }
end

-- /////////////////////////////////////////// Important things :))
local widgetEnabled = true
local retreatingUnits = {} -- table to keep track of retreatingUnits
local unitsToCollect = {}  -- table to keep track of units and their collection state
local lastAvoidanceTime = {} -- Table to track the last avoidance time for each unit
local healingUnits = {}  -- table to keep track of healing units
local unitLastPosition = {} -- Track the last position of each unit
local repairCooldown = {}  -- Track last repair command time for each unit
local repairInProgress = {}  -- Track units with ongoing repair commands
local targetedFeatures = {}  -- Table to keep track of targeted features
local maxUnitsPerFeature = 4  -- Maximum units allowed to target the same feature
local healingTargets = {}  -- Track which units are being healed and by how many healers
local maxHealersPerUnit = 4  -- Maximum number of healers per unit
local unitTaskStatus = {}
local spGetUnitDefID = Spring.GetUnitDefID
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spGetUnitPosition = Spring.GetUnitPosition
local spGetFeaturesInCylinder = Spring.GetFeaturesInCylinder
local spGetFeatureDefID = Spring.GetFeatureDefID
local spGetMyTeamID = Spring.GetMyTeamID
local spGetTeamResources = Spring.GetTeamResources
local CMD_RECLAIM = CMD.RECLAIM
local maxUnits = 1000000
local avoidanceCooldown = 30 -- Cooldown in game frames, 30 Default.

-- ///////////////////////////////////////////  Adjustable variables, to suit the widget users preference
local healResurrectRadius = 4000 -- Set your desired heal/resurrect radius here
local reclaimRadius = 4000 -- Set your desired reclaim radius here
local retreatRadius = 800  -- The detection area around the SCV unit, which causes it to retreat.
local enemyAvoidanceRadius = 625  -- Adjust this value as needed -- Define a safe distance for enemy avoidance
local closeHealingThreshold = 300 -- Units within this range will prioritize healing


-- /////////////////////////////////////////// ---- /////////////////////////////////////////// ---- /////////////////////////////////////////// 
-- /////////////////////////////////////////// ---                Main Code                     ---- /////////////////////////////////////////// 


-- /////////////////////////////////////////// Initialize Function
function widget:Initialize()
  -- Check if the widget should be removed (e.g., in a replay or spectating state)
  if Spring.IsReplay() or Spring.GetSpectatingState() then
      widgetHandler:RemoveWidget()
      return
  end

  -- Define commander unit definition IDs
  local armComDefID, corComDefID

  -- Check and store the UnitDefIDs for the commanders
  if UnitDefNames and UnitDefNames.armcom and UnitDefNames.corcom then
      armComDefID = UnitDefNames.armcom.id
      corComDefID = UnitDefNames.corcom.id
  else
      -- Handle the case where UnitDefNames are not available or commanders are undefined
      Spring.Echo("Commander UnitDefIDs could not be determined")
      widgetHandler:RemoveWidget(self)
      return
  end

  -- Store commander UnitDefIDs globally within the widget for later use
  -- (Note: Adjust these variable names as per your widget's naming conventions)
  self.armComDefID = armComDefID
  self.corComDefID = corComDefID

  -- Additional initialization code can go here
  -- ...
end


-- ///////////////////////////////////////////  UnitCreated Function
function widget:UnitCreated(unitID, unitDefID, unitTeam)
  -- Check if the unit is a commander
  if unitDefID == UnitDefNames.armcom.id or unitDefID == UnitDefNames.corcom.id then
      -- Skip processing for commanders
      return
  end

  local unitDef = UnitDefs[unitDefID]
  if unitDef ~= nil and unitDef.canReclaim and unitDef.canResurrect then
      -- Initialize unit to collect resources
      unitsToCollect[unitID] = {
          featureCount = 0,
          lastReclaimedFrame = 0
      }

      processUnits({[unitID] = unitsToCollect[unitID]})
  end
end



-- ///////////////////////////////////////////  UnitDestroyed Function
function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
  local unitDef = UnitDefs[unitDefID]

  if unitDef.canReclaim and unitDef.canResurrect then
    unitsToCollect[unitID] = nil

    local units = Spring.GetTeamUnits(Spring.GetMyTeamID())
    for _, uID in ipairs(units) do
      local uDefID = spGetUnitDefID(uID)
      local uDef = UnitDefs[uDefID]
      local unitCommands = Spring.GetUnitCommands(uID, 1)

      if uID ~= unitID and uDef.canReclaim and (not unitCommands or #unitCommands == 0) then
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
  local stuckCheckInterval = 500  -- Number of game frames to wait between checks

  -- Interval for avoidance and other actions
  local actionInterval = 60  -- Check every 60 frames (approximately 2 seconds at 30 FPS)

  if currentFrame % stuckCheckInterval == 0 then
    -- Call handleStuckUnits for each unit here
    for unitID, _ in pairs(unitsToCollect) do
      local unitDefID = spGetUnitDefID(unitID)
      local unitDef = UnitDefs[unitDefID]
      if unitDef and (unitDef.canReclaim and unitDef.canResurrect) then
        handleStuckUnits(unitID, unitDef)
      end
    end
  end

  if currentFrame % actionInterval == 0 then
    if widgetEnabled then
      -- Replace retreatUnits with checkAndRetreatIfNeeded for each unit
      for unitID, _ in pairs(unitsToCollect) do
        checkAndRetreatIfNeeded(unitID, retreatRadius)
      end

      if not unitsToCollect then
        unitsToCollect = {}
      end

      -- Find units that can collect resources
      processUnits(unitsToCollect)
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
function processUnits(units)
  for unitID, unitData in pairs(units) do
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

      -- Check for nearby enemies and avoid if necessary
      local nearestEnemy, distance = findNearestEnemy(unitID, enemyAvoidanceRadius)
      if nearestEnemy and distance < enemyAvoidanceRadius then
          avoidEnemy(unitID, nearestEnemy)
          unitData.taskType = "avoidingEnemy"
          unitData.taskStatus = "in_progress"
          -- Skip other actions for this unit in this cycle
          return
      end

      local resourceNeed = assessResourceNeeds()
      local featureCollected = false

      -- Prioritize resource collection if needed
      if resourceNeed ~= "none" then
          local x, y, z = spGetUnitPosition(unitID)
          if not x or not z then return nil end  -- Validate unit position

          local featureID = findReclaimableFeature(unitID, x, z, reclaimRadius, resourceNeed)
          if featureID then
              spGiveOrderToUnit(unitID, CMD_RECLAIM, {featureID + Game.maxUnits}, {})
              unitData.featureCount = 1
              unitData.lastReclaimedFrame = Spring.GetGameFrame()
              targetedFeatures[featureID] = (targetedFeatures[featureID] or 0) + 1
              unitData.taskType = "reclaiming"
              unitData.taskStatus = "in_progress"
              featureCollected = true
          end
      end

      -- If no resources needed or no features found, consider healing or other tasks
      if not featureCollected then
          local nearestDamagedUnit, distance = findNearestDamagedFriendly(unitID, healResurrectRadius)
          if nearestDamagedUnit and distance < healResurrectRadius and not healingUnits[unitID] then
              healingTargets[nearestDamagedUnit] = healingTargets[nearestDamagedUnit] or 0
              if healingTargets[nearestDamagedUnit] < maxHealersPerUnit then
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



-- /////////////////////////////////////////// KeyPress Function 
function widget:KeyPress(key, mods, isRepeat)
  if key == 0x0063 and mods.alt then -- 0x0063 is the key code for "c"
    widgetEnabled = not widgetEnabled
    if widgetEnabled then
      Spring.Echo("SCV widget enabled")
    else
      Spring.Echo("SCV widget disabled")
    end
  end
  return false
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
  function resurrectNearbyDeadUnits(unitID, healResurrectRadius)
    local x, y, z = spGetUnitPosition(unitID)
    local deadUnits = Spring.GetUnitsInCylinder(x, z, healResurrectRadius, Spring.DECAYED)
  
    for _, deadUnitID in ipairs(deadUnits) do
      local unitDefID = spGetUnitDefID(deadUnitID)
      local unitDef = UnitDefs[unitDefID]
  
      if unitDef ~= nil and unitDef.canReclaim and unitDef.canResurrect then
        Spring.GiveOrderToUnit(unitID, CMD.RESURRECT, { deadUnitID }, {})
      end
    end
  end

-- ///////////////////////////////////////////  checkAndRetreatIfNeeded Function
function checkAndRetreatIfNeeded(unitID, retreatRadius)
  local nearestEnemy, distance = findNearestEnemy(unitID, retreatRadius)

  if nearestEnemy and distance < retreatRadius then
    -- Process avoidance and retreat in a unified manner
    avoidEnemy(unitID, nearestEnemy, distance)
  end
end



-- ///////////////////////////////////////////  UnitIdle Function
function widget:UnitIdle(unitID)
  local unitDefID = spGetUnitDefID(unitID)
  local unitDef = UnitDefs[unitDefID]

  if unitDef and (unitDef.canReclaim and unitDef.canResurrect) then
    local unitData = unitsToCollect[unitID]
    if not unitData then
      unitData = { featureCount = 0, lastReclaimedFrame = 0, taskType = nil, taskStatus = "idle" }
      unitsToCollect[unitID] = unitData
    else
      unitData.taskStatus = "idle"
    end

    -- Manage targeted features and healing units
    local featureID = unitData.featureID
    if featureID and targetedFeatures[featureID] then
      targetedFeatures[featureID] = math.max(targetedFeatures[featureID] - 1, 0)
    end
    local healedUnitID = healingUnits[unitID]
    if healedUnitID and healingTargets[healedUnitID] then
      healingTargets[healedUnitID] = math.max(healingTargets[healedUnitID] - 1, 0)
    end

    processUnits({[unitID] = unitData})
    retreatingUnits[unitID] = nil
    healingUnits[unitID] = nil
  end
end



-- ///////////////////////////////////////////  isUnitStuck Function
local lastStuckCheck = {}
local checkInterval = 30  -- Number of game frames to wait between checks

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



function handleStuckUnits(unitID, unitDef)
  -- Check if the unitDef is nil, and if so, retrieve it
  if not unitDef then
    local unitDefID = spGetUnitDefID(unitID)
    unitDef = UnitDefs[unitDefID]
  end

  -- Ensure the unit has the capabilities (canReclaim, canResurrect)
  if unitDef and (unitDef.canReclaim and unitDef.canResurrect) then
    if isUnitStuck(unitID) then
      Spring.GiveOrderToUnit(unitID, CMD.STOP, {}, {})

      -- Re-add the unit to the work list
      unitsToCollect[unitID] = {
        featureCount = 0,
        lastReclaimedFrame = 0
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
  local energyFull = currentEnergy >= storageEnergy * 0.90  -- 90% full

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
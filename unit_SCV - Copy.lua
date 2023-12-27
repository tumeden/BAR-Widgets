-- /////////////////////////////////////////// GetInfo Function
function widget:GetInfo()
  return {
    name      = "SCV Copy",
    desc      = "Collects resources, Enable/Disable with Alt+C",
    author    = "Tumeden",
    date      = "2023",
    version   = "v2.7",
    license   = "GNU GPL, v2 or later",
    layer     = 0,
    enabled   = true
  }
end

-- /////////////////////////////////////////// Important things :))
local widgetEnabled = true
local retreatingUnits = {} -- table to keep track of retreatingUnits
local unitsToCollect = {}  -- table to keep track of units and their collection state
local spGetUnitDefID = Spring.GetUnitDefID
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spGetUnitPosition = Spring.GetUnitPosition
local spGetFeaturesInCylinder = Spring.GetFeaturesInCylinder
local spGetFeatureDefID = Spring.GetFeatureDefID
local spGetMyTeamID = Spring.GetMyTeamID
local spGetTeamResources = Spring.GetTeamResources
local CMD_RECLAIM = CMD.RECLAIM
local maxUnits = 1000000
local repairCooldown = {}  -- Track last repair command time for each unit
local repairInProgress = {}  -- Track units with ongoing repair commands



-- ///////////////////////////////////////////  Adjustable variables, to suit the widget users preference

local createCollectRadius = 2000  -- range used when units are created/collection range
local collectionTimeout = 15  -- 15 seconds is Default - time in which a unit times out if the unit gets stuck on the way to collection.
local safetyRadius = 1000  -- The detection area for enemies around the collection target.
local retreatRadius = 1000  -- The detection area around the SCV unit, which causes it to retreat.
local retreatFraction = 0.5  -- 0.5 is Default - How far the SCV units will retreat. (0.5 means 50% of the retreatRadius) 1.0 would be same distance as retreatRadius


-- /////////////////////////////////////////// ---- /////////////////////////////////////////// ---- /////////////////////////////////////////// 
-- /////////////////////////////////////////// ---                Main Code                     ---- /////////////////////////////////////////// 


-- /////////////////////////////////////////// Initialize Function
function widget:Initialize()
  if Spring.IsReplay() or Spring.GetSpectatingState() then
    widgetHandler:RemoveWidget()
    return
  end
end

-- ///////////////////////////////////////////  UnitCreated Function
function widget:UnitCreated(unitID, unitDefID, unitTeam)
  local unitDef = UnitDefs[unitDefID]

  if unitDef.canReclaim and unitDef.canResurrect and unitDef.canHeal then
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

    -- Find another unit to collect resources
    local units = Spring.GetTeamUnits(Spring.GetMyTeamID())
    for _, uID in ipairs(units) do
      local uDefID = spGetUnitDefID(uID)
      local uDef = UnitDefs[uDefID]
      if uID ~= unitID and uDef.canReclaim then
        unitsToCollect[uID] = {
          featureCount = 0,
          lastReclaimedFrame = 0
        }
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
      processUnits(unitsToCollect)
      break
    end
  end
end

-- /////////////////////////////////////////// GameFrame Function
function widget:GameFrame(frame)
  if widgetEnabled then
    if frame % 30 == 0 then  -- Check every 30 frames (1 second at 30 FPS)
      retreatUnits(unitsToCollect, retreatRadius)

      for unitID, unitData in pairs(unitsToCollect) do
        local x, _, z = spGetUnitPosition(unitID)
        local featureID = unitData.featureID
        -- Call checkAndRetreatIfNeeded for each unit
        checkAndRetreatIfNeeded(unitID, {x = x, z = z}, retreatRadius)
      end
    end

    if not unitsToCollect then
      unitsToCollect = {}
    end

    -- Find units that can collect resources
    processUnits(unitsToCollect)
  end
end

-- /////////////////////////////////////////// processUnits Function
function processUnits(units)
  local healResurrectRadius = 500 -- Set your desired heal/resurrect radius here
  local healedTargets = {}  -- Track units already healed

  for unitID, unitData in pairs(units) do
    local unitDefID = spGetUnitDefID(unitID)
    local unitDef = UnitDefs[unitDefID]

    if unitDef.canReclaim and unitDef.canResurrect then
      local x, y, z = spGetUnitPosition(unitID)

      if unitData.featureCount == 0 then
        local featureID = findReclaimableFeature(unitID, x, z, createCollectRadius)
        if featureID then
          spGiveOrderToUnit(unitID, CMD_RECLAIM, {featureID + Game.maxUnits}, {"shift"})
          unitData.featureCount = 1
          unitData.lastReclaimedFrame = Spring.GetGameFrame()
        end
      else
        -- Check if unit has finished reclaiming feature
        if Spring.ValidFeatureID(unitData.featureID) and not Spring.GetFeatureHealth(unitData.featureID) then
          unitData.featureID = nil
          unitData.featureCount = 0
        end

        -- Check if unit is stuck
        local unitCommands = Spring.GetUnitCommands(unitID, 1000)
        if not unitCommands or #unitCommands == 0 then
          local currentFrame = Spring.GetGameFrame()
          if currentFrame - unitData.lastReclaimedFrame >= collectionTimeout then
            -- Timeout occurred, search for new feature
            unitData.featureCount = 0
            spGiveOrderToUnit(unitID, CMD.STOP, {}, {})
          else
            local newFeatureID = findReclaimableFeature(unitID, x, z, createCollectRadius)
            if newFeatureID and newFeatureID ~= unitData.featureID then
              local fx, _, fz = Spring.GetFeaturePosition(newFeatureID)
            end
          end
        else
          local healingInProgress = false
          local currentTime = Spring.GetGameFrame()

          -- Check for nearby damaged or dead units to heal or resurrect
          local unitsInRadius = Spring.GetUnitsInCylinder(x, z, healResurrectRadius, Spring.ALL_UNITS)
          for _, targetUnitID in ipairs(unitsInRadius) do
            local targetAllyTeam = Spring.GetUnitAllyTeam(targetUnitID)
            if targetAllyTeam == Spring.GetMyAllyTeamID() then
              -- Add this condition to ensure only friendly units are targeted for healing or resurrection

              if not healedTargets[targetUnitID] then  -- Prevent spamming heal command
                local targetHealth, targetMaxHealth, _, _, buildProgress = Spring.GetUnitHealth(targetUnitID)
                if targetHealth and targetMaxHealth and targetHealth < targetMaxHealth and buildProgress == 1 then
                  if not healingInProgress then
                    -- Check if the repair command cooldown has elapsed
                    if not repairCooldown[unitID] or currentTime - repairCooldown[unitID] > 60 then
                      -- Issue a heal or resurrect command based on the unit's health status
                      local command = CMD.REPAIR
                      if targetHealth <= 0 then
                        command = CMD.RESURRECT
                      end

                      -- Give the command to heal or resurrect the unit
                      Spring.GiveOrderToUnit(unitID, command, { targetUnitID }, {})

                      -- Flag the unit as already healed
                      healedTargets[targetUnitID] = true

                      -- Set the cooldown timer for the repair command
                      repairCooldown[unitID] = currentTime

                      -- Mark healing as in progress
                      healingInProgress = true
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end








-- /////////////////////////////////////////// findReclaimableFeature Function
function findReclaimableFeature(unitID, x, z, searchRadius)
  local featuresInRadius = spGetFeaturesInCylinder(x, z, searchRadius)

  -- Sort features by distance from unit
  table.sort(featuresInRadius, function(a, b)
    local ax, _, az = Spring.GetFeaturePosition(a)
    local bx, _, bz = Spring.GetFeaturePosition(b)
    return ((ax-x)^2 + (az-z)^2) < ((bx-x)^2 + (bz-z)^2)
  end)

  for _, featureID in ipairs(featuresInRadius) do
    local featureDefID = spGetFeatureDefID(featureID)
    local featureDef = FeatureDefs[featureDefID]
    if featureDef and featureDef.reclaimable then
      return featureID
    end
  end

  return nil
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

-- ///////////////////////////////////////////  findNearestEnemy Function
function findNearestEnemy(unitID, searchRadius)
  local x, y, z = spGetUnitPosition(unitID)
  local unitsInRadius = Spring.GetUnitsInCylinder(x, z, searchRadius, Spring.ENEMY_UNITS)

  local minDistSq = searchRadius * searchRadius
  local nearestEnemy = nil

  for _, enemyID in ipairs(unitsInRadius) do
    local ex, ey, ez = spGetUnitPosition(enemyID)
    local distSq = (x - ex)^2 + (z - ez)^2
    if distSq < minDistSq then
      minDistSq = distSq
      nearestEnemy = enemyID
    end
  end

  return nearestEnemy, math.sqrt(minDistSq)
end

-- ///////////////////////////////////////////  retreatingUnits Function
function retreatUnits(units, retreatRadius)
  for unitID, _ in pairs(units) do
    local unitDefID = spGetUnitDefID(unitID)
    local unitDef = UnitDefs[unitDefID]

    -- Check if the unit has the required abilities
    if unitDef.canReclaim and unitDef.canResurrect then
      local nearestEnemy, distance = findNearestEnemy(unitID, retreatRadius * retreatFraction)

      if nearestEnemy and distance < retreatRadius then
        -- Calculate a retreat direction opposite to the nearest enemy
        local x, y, z = spGetUnitPosition(unitID)
        local ex, ey, ez = spGetUnitPosition(nearestEnemy)
        local dx, dz = x - ex, z - ez
        local length = math.sqrt(dx * dx + dz * dz)
        local retreatDist = retreatRadius * retreatFraction  -- Use the retreatFraction variable instead of a hardcoded value
        local rx, rz = x + dx / length * retreatDist, z + dz / length * retreatDist
        local ry = Spring.GetGroundHeight(rx, rz)

        -- Issue a move order to the retreat position
        spGiveOrderToUnit(unitID, CMD.MOVE, {rx, ry, rz}, {})

        -- Add the unit to the retreatingUnits table
        retreatingUnits[unitID] = true

        -- Remove the unit from the unitsToCollect table so it doesn't collect resources while retreating
        unitsToCollect[unitID] = nil
      end
    end
  end
end

-- ///////////////////////////////////////////  ressurectNearbyDeadUnits Function
  function resurrectNearbyDeadUnits(unitID, healResurrectRadius)
    local x, y, z = spGetUnitPosition(unitID)
    local deadUnits = Spring.GetUnitsInCylinder(x, z, healResurrectRadius, Spring.DECAYED)
  
    for _, deadUnitID in ipairs(deadUnits) do
      local unitDefID = spGetUnitDefID(deadUnitID)
      local unitDef = UnitDefs[unitDefID]
  
      if unitDef and unitDef.canResurrect then
        Spring.GiveOrderToUnit(unitID, CMD.RESURRECT, { deadUnitID }, {})
      end
    end
  end

-- ///////////////////////////////////////////  checkAndRetreatIfNeeded Function
function checkAndRetreatIfNeeded(unitID, units, retreatRadius)
  local nearestEnemy, distance = findNearestEnemy(unitID, retreatRadius)

  if nearestEnemy and distance < retreatRadius then
    -- Unit needs to retreat, process retreat
    retreatUnits({[unitID] = units[unitID]}, retreatRadius)
  end
end


-- ///////////////////////////////////////////  UnitIdle Function
function widget:UnitIdle(unitID)
  if retreatingUnits[unitID] then
    -- Remove the unit from the retreatingUnits table
    retreatingUnits[unitID] = nil

    -- Add the unit back to the unitsToCollect table and call processUnits for this unit
    local unitDefID = spGetUnitDefID(unitID)
    unitsToCollect[unitID] = {
      featureCount = 0,
      lastReclaimedFrame = 0
    }
    processUnits({[unitID] = unitsToCollect[unitID]})
  else
    -- Check if the idle unit is a worker with the specified abilities and not already in the unitsToCollect table
    local unitDefID = spGetUnitDefID(unitID)
    local unitDef = UnitDefs[unitDefID]
    
    if unitDef.canReclaim and unitDef.canResurrect and not unitsToCollect[unitID] then
      unitsToCollect[unitID] = {
        featureCount = 0,
        lastReclaimedFrame = 0
      }
      processUnits({[unitID] = unitsToCollect[unitID]})
    end
  end
end





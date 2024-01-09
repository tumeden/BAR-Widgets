-- /////////////////////////////////////////// GetInfo Function
function widget:GetInfo()
  return {
    name      = "SCV",
    desc      = "RezBots Resurrect, Collect resources, and heal injured units. alt+c to open UI",
    author    = "Tumeden",
    date      = "2024",
    version   = "v6.5",
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
local healResurrectRadius = 1000 -- Set your desired heal/resurrect radius here  (default 1000,  anything larger can cause significant lag)
local reclaimRadius = 1500 -- Set your desired reclaim radius here (any number works, 4000 is about half a large map)
local retreatRadius = 425  -- The detection area around the SCV unit, which causes it to retreat.
local enemyAvoidanceRadius = 925  -- Adjust this value as needed -- Define a safe distance for enemy avoidance
local avoidanceCooldown = 30 -- Cooldown in game frames, 30 Default.

-- engine call optimizations
-- =========================
local armRectrDefID
local corNecroDefID
local spGetUnitDefID = Spring.GetUnitDefID
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spGetUnitPosition = Spring.GetUnitPosition
local spGetFeaturesInCylinder = Spring.GetFeaturesInCylinder
local spGetFeatureDefID = Spring.GetFeatureDefID
local spGetMyTeamID = Spring.GetMyTeamID

local spEcho = Spring.Echo
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitsInCylinder = Spring.GetUnitsInCylinder
local spGetUnitIsDead = Spring.GetUnitIsDead
local spValidUnitID = Spring.ValidUnitID
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
local spGetGroundHeight = Spring.GetGroundHeight
local spGetFeaturePosition = Spring.GetFeaturePosition
local spGetUnitCommands = Spring.GetUnitCommands
local CMD_MOVE = CMD.MOVE
local CMD_RESURRECT = CMD.RESURRECT
local CMD_RECLAIM = CMD.RECLAIM
local glText = gl.Text
local glRect = gl.Rect
local glColor = gl.Color
local glTranslate = gl.Translate
local glPushMatrix = gl.PushMatrix
local glPopMatrix = gl.PopMatrix
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

local findNearestEnemy = findNearestEnemy
local getFeatureResources = getFeatureResources



-- /////////////////////////////////////////// -- /////////////////////////////////////////// --
-- /////////////////////////////////////////// -- /////////////////////////////////////////// --
-- ////////////////////////////////////////- UI CODE -////////////////////////////////////// --
-- /////////////////////////////////////////// -- /////////////////////////////////////////// --
-- /////////////////////////////////////////// -- /////////////////////////////////////////// --

-- Function to count and display tasks
function CountTaskEngagements()
  local healingCount, resurrectingCount, collectingCount = 0, 0, 0

  for _, unitID in ipairs(healingUnits) do
    healingCount = healingCount + 1
  end
  for unitID, _ in pairs(resurrectingUnits) do
    if not healingUnits[unitID] then  -- Ensure a unit is not counted in both
      resurrectingCount = resurrectingCount + 1
    end
  end
  for unitID, data in pairs(unitsToCollect) do
    if data.taskStatus == "in_progress" and not resurrectingUnits[unitID] then  -- Again, check for double counting
      collectingCount = collectingCount + 1
    end
  end

  return healingCount, resurrectingCount, collectingCount
end


-- Function to update and display unit count
function UpdateAndDisplayUnitCount()
  local armRectrCount, corNecroCount = CountUnitTypes()
  local dominantUnitType, dominantCount = DetermineDominantUnitType(armRectrCount, corNecroCount)

  -- Display the unit count
  local displayText = "# of " .. dominantUnitType .. " (" .. dominantCount .. ")"
  gl.Color(1, 1, 1, 1) -- White color
  gl.Text(displayText, 50, 50, 12, "d") -- Adjust position and size as needed
end

function CountUnitTypes()
  local armRectrCount = 0
  local corNecroCount = 0
  local units = Spring.GetTeamUnits(Spring.GetMyTeamID())

  for _, unitID in ipairs(units) do
      local unitDefID = Spring.GetUnitDefID(unitID)
      if unitDefID == armRectrDefID then
          armRectrCount = armRectrCount + 1
      elseif unitDefID == corNecroDefID then
          corNecroCount = corNecroCount + 1
      end
  end

  return armRectrCount, corNecroCount
end

-- Function to determine the dominant unit type
function DetermineDominantUnitType(armRectrCount, corNecroCount)
  if armRectrCount > corNecroCount then
      return "Rezbot", armRectrCount
  else
      return "Rezbot", corNecroCount
  end
end


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

-- Stats box configuration
local statsBoxWidth = mainBoxWidth * 0.9
local statsBoxHeight = lineHeight * 6
local statsBoxX = mainBoxX + (mainBoxWidth - statsBoxWidth) / 2

-- Variable to adjust the stats box vertical position within the main UI box
-- Positive values move it down, negative values move it up.
local statsBoxVerticalOffset = 170  -- Adjust this value to move the stats box up or down

-- Position statsBoxY using the new offset variable
local statsBoxY = mainBoxY + mainBoxHeight - statsBoxHeight - padding - statsBoxVerticalOffset


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

    -- Draw the statistics box
    drawBorderedBox(statsBoxX, statsBoxY - statsBoxHeight, statsBoxX + statsBoxWidth, statsBoxY, statsBgColor, borderColor)

    -- Retrieve and draw stats
    local armRectrCount, corNecroCount = CountUnitTypes()
    local dominantUnitType, dominantCount = DetermineDominantUnitType(armRectrCount, corNecroCount)
    local healingCount, resurrectingCount, collectingCount = CountTaskEngagements()

    local statsTextX = statsBoxX + padding
    local statsTextY = statsBoxY - lineHeight

    -- Labels and values for stats
    local statsLabels = {
      "Workers Name:",
      "Unit Count:",
      "Healing Count:",
      "Resurrecting Count:",
      "Collecting Count:"
    }
    local statsValues = {
      dominantUnitType,
      dominantCount,
      healingCount,
      resurrectingCount,
      collectingCount
    }

    -- Drawing stats text
    for i = 1, #statsLabels do
      gl.Color(unpack(labelColor))
      gl.Text(statsLabels[i], statsTextX, statsTextY, fontSize, 'o')
      gl.Color(unpack(valueColor))
      gl.Text(statsValues[i], statsTextX + statsBoxWidth - padding, statsTextY, fontSize, 'or')
      statsTextY = statsTextY - lineHeight
    end

        
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

      -- Update corresponding global variable
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

-- ///////////////////////////////////////////  Is the game paused, or over?
local isGamePaused = false

function widget:GamePaused()
    isGamePaused = true
end

function widget:GameUnpaused()
    isGamePaused = false
end

function widget:GameOver()
  widgetHandler:RemoveWidget()
end


-- ///////////////////////////////////////////  isMyResbot Function 
function isMyResbot(unitID, unitDefID)
  local myTeamID = Spring.GetMyTeamID()
  local unitTeamID = Spring.GetUnitTeam(unitID)
  return unitTeamID == myTeamID and (unitDefID == armRectrDefID or unitDefID == corNecroDefID)
end



-- ///////////////////////////////////////////  UnitCreated Function
function widget:UnitCreated(unitID, unitDefID, unitTeam)
  if isMyResbot(unitID, unitDefID) then
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
    if isMyResbot(unitID, unitDefID) then
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



-- /////////////////////////////////////////// GameFrame Function
function widget:GameFrame(currentFrame)
  if isGamePaused then return end
  local checkInterval = 30  -- Interval for idle and task checks
  local avoidanceCheckInterval = 30  -- Interval for avoidance checks
  local stuckCheckInterval = 3000
  local actionInterval = 60
  local unitsPerFrame = 5

  -- Helper function to get sorted unit IDs
  local function getSortedUnitIDs(units)
    local unitIDs = {}
    for unitID in pairs(units) do
      table.insert(unitIDs, unitID)
    end
    table.sort(unitIDs)
    return unitIDs
  end

  -- Avoidance check
  if currentFrame % avoidanceCheckInterval == 0 then
    local sortedUnitIDs = getSortedUnitIDs(unitsToCollect)
    for _, unitID in ipairs(sortedUnitIDs) do
      local unitDefID = spGetUnitDefID(unitID)
      if isMyResbot(unitID, unitDefID) then
        if Spring.ValidUnitID(unitID) and not Spring.GetUnitIsDead(unitID) then
          local nearestEnemy, distance = findNearestEnemy(unitID, enemyAvoidanceRadius)
          if nearestEnemy and distance < enemyAvoidanceRadius then
            avoidEnemy(unitID, nearestEnemy)
            unitsToCollect[unitID].taskType = "avoidingEnemy"
            unitsToCollect[unitID].taskStatus = "in_progress"
          end
        end
      end
    end
  end

  -- Idle and task check
  if currentFrame % checkInterval == 0 then
    local sortedUnitIDs = getSortedUnitIDs(unitsToCollect)
    for _, unitID in ipairs(sortedUnitIDs) do
      if isUnitActuallyIdle(unitID, unitsToCollect[unitID]) then
        handleIdleUnit(unitID, unitsToCollect[unitID])
      end
    end
  end

  -- Stuck units check
  if currentFrame % stuckCheckInterval == 0 then
    local sortedUnitIDs = getSortedUnitIDs(unitsToCollect)
    for _, unitID in ipairs(sortedUnitIDs) do
      local unitDefID = spGetUnitDefID(unitID)
      if isMyResbot(unitID, unitDefID) then
        if Spring.ValidUnitID(unitID) and not Spring.GetUnitIsDead(unitID) then
          handleStuckUnits(unitID, UnitDefs[unitDefID])
        end
      end
    end
  end

  -- Regular action interval
  if currentFrame % actionInterval == 0 then
    local sortedUnitIDs = getSortedUnitIDs(unitsToCollect)
    local processedCount = 0
    for _, unitID in ipairs(sortedUnitIDs) do
      if processedCount >= unitsPerFrame then break end
      local unitDefID = spGetUnitDefID(unitID)
      if isMyResbot(unitID, unitDefID) then
        if Spring.ValidUnitID(unitID) and not Spring.GetUnitIsDead(unitID) then
          processUnits({[unitID] = unitsToCollect[unitID]})
          processedCount = processedCount + 1
        end
      end
    end
  end
end


function isUnitActuallyIdle(unitID, unitData)
  -- Check if the unitID is valid
  if not Spring.ValidUnitID(unitID) or Spring.GetUnitIsDead(unitID) then
      return false
  end

  -- Check if the unit is not doing anything regardless of the task status
  local currentCommands = spGetUnitCommands(unitID, 1)
  if currentCommands then
      return #currentCommands == 0 and unitData.taskStatus ~= "idle"
  else
      return false  -- Return false if currentCommands is nil
  end
end


function handleIdleUnit(unitID, unitData)
  unitData.taskStatus = "idle"
  -- Reset other task-related data for the unit
  -- ...

  -- Re-queue the unit for task assignment
  processUnits({[unitID] = unitData})
end



-- ///////////////////////////////////////////  avoidEnemy Function
function avoidEnemy(unitID, enemyID)
  local currentTime = Spring.GetGameFrame()

  -- Retrieve unitDefID for the unit
  local unitDefID = spGetUnitDefID(unitID)

  -- Check if the unit is a RezBot
  if isMyResbot(unitID, unitDefID) then
    -- Check if the unit is still in cooldown period
    if lastAvoidanceTime[unitID] and (currentTime - lastAvoidanceTime[unitID]) < avoidanceCooldown then
      return -- Skip avoidance if still in cooldown
    end

    local ux, uy, uz = spGetUnitPosition(unitID)
    local ex, ey, ez = spGetUnitPosition(enemyID)

    -- Calculate a direction vector away from the enemy
    local dx, dz = ux - ex, uz - ez
    local magnitude = math.sqrt(dx * dx + dz * dz)

    -- Normalize the direction vector
    dx, dz = dx / magnitude, dz / magnitude

    -- Use the user-defined multiplier for the distance to move away
    local safeX, safeZ = ux + dx * enemyAvoidanceRadius, uz + dz * enemyAvoidanceRadius
    local safeY = Spring.GetGroundHeight(safeX, safeZ)

    -- Issue a move order to the safe destination
    spGiveOrderToUnit(unitID, CMD.MOVE, {safeX, safeY, safeZ}, {})

    -- Update the task status and clear from the resurrectingUnits
    if resurrectingUnits[unitID] then
      resurrectingUnits[unitID] = nil -- Clear the unit from resurrecting status
      unitsToCollect[unitID].taskStatus = "idle" -- Set status to idle or another status like "retreating"
    end

    -- Update the last avoidance time for this unit
    lastAvoidanceTime[unitID] = currentTime
  end
end



-- /////////////////////////////////////////// isTargetReachable Function
function isTargetReachable(unitID, featureID)
  local unitDefID = Spring.GetUnitDefID(unitID)

  if not isMyResbot(unitID, unitDefID) then
    return false -- Unit is not a resbot, target is not reachable
  end

  local fx, fy, fz = Spring.GetFeaturePosition(featureID)
  local mx, my, mz = Spring.GetUnitPosition(unitID)
  local unitDef = UnitDefs[unitDefID]
  local moveDefID = unitDef.moveDef.id

  -- Assuming that RequestPath always returns the same result for the same input across all clients
  local path = Spring.RequestPath(moveDefID, mx, my, mz, fx, fy, fz, 0, 0, 0, 0) -- Last 4 zeros are default values for optional arguments

  return path ~= nil -- If a path exists, the target is reachable
end



-- /////////////////////////////////////////// findNearestEnemy Function
-- Function to find the nearest enemy and its type
function findNearestEnemy(unitID, searchRadius)
  local unitDefID = Spring.GetUnitDefID(unitID)

  if isMyResbot(unitID, unitDefID) then
    local x, y, z = Spring.GetUnitPosition(unitID)
    if not x or not z then return nil end  -- Validate unit position
    local unitsInRadius = Spring.GetUnitsInCylinder(x, z, searchRadius, Spring.ENEMY_UNITS)

    local minDistSq = searchRadius * searchRadius
    local nearestEnemy, isAirUnit = nil, false

    for _, enemyID in ipairs(unitsInRadius) do
      local enemyDefID = Spring.GetUnitDefID(enemyID)
      local enemyDef = UnitDefs[enemyDefID]
      if enemyDef then
        local ex, ey, ez = Spring.GetUnitPosition(enemyID)
        local distSq = (x - ex)^2 + (z - ez)^2
        if distSq < minDistSq then
          minDistSq = distSq
          nearestEnemy = enemyID
          isAirUnit = enemyDef.isAirUnit
        end
      end
    end

    return nearestEnemy, math.sqrt(minDistSq), isAirUnit
  else
    -- Handle the case where the unit is not a resbot (optional)
    return nil, nil, nil
  end
end



-- ///////////////////////////////////////////  assessResourceNeeds Function
function assessResourceNeeds()
  local myTeamID = Spring.GetMyTeamID()
  local currentMetal, storageMetal = Spring.GetTeamResources(myTeamID, "metal")
  local currentEnergy, storageEnergy = Spring.GetTeamResources(myTeamID, "energy")

  local metalFull = currentMetal >= storageMetal * 0.90  -- Considered full at 90%
  local energyFull = currentEnergy >= storageEnergy * 0.90  -- Considered full at 90%

  if metalFull and energyFull then
    return "full"
  elseif metalFull then
    return "energy"
  elseif energyFull then
    return "metal"
  else
    return "proximity" -- Neither resource is full, focus on proximity
  end
end


function handleHealing(unitID, unitData)
  local unitDefID = Spring.GetUnitDefID(unitID)

  if isMyResbot(unitID, unitDefID) then
    if checkboxes.healing.state and unitData.taskStatus ~= "in_progress" then
      local nearestDamagedUnit, distance = findNearestDamagedFriendly(unitID, healResurrectRadius)
      if nearestDamagedUnit and distance < healResurrectRadius then
          healingTargets[nearestDamagedUnit] = healingTargets[nearestDamagedUnit] or 0
          if healingTargets[nearestDamagedUnit] < maxHealersPerUnit and not healingUnits[unitID] then
              Spring.GiveOrderToUnit(unitID, CMD.REPAIR, {nearestDamagedUnit}, {})
              healingUnits[unitID] = nearestDamagedUnit
              healingTargets[nearestDamagedUnit] = healingTargets[nearestDamagedUnit] + 1
              unitData.taskType = "healing"
              unitData.taskStatus = "in_progress"
              return true
          end
      end
    end
  end
  return false
end



function handleResurrecting(unitID, unitData)
  local unitDefID = Spring.GetUnitDefID(unitID)

  if isMyResbot(unitID, unitDefID) then
    if checkboxes.resurrecting.state and unitData.taskStatus ~= "in_progress" then
        local resurrectableFeatures = resurrectNearbyDeadUnits(unitID, healResurrectRadius)

        -- Debug: Print the number of found resurrectable features
        -- Spring.Echo("Unit " .. unitID .. " found " .. #resurrectableFeatures .. " resurrectable features")

        if #resurrectableFeatures > 0 then
            local orders = generateOrders(resurrectableFeatures, false, nil, unitID)
            for _, order in ipairs(orders) do
                if Spring.ValidFeatureID(order[2] - Game.maxUnits) then
                    spGiveOrderToUnit(unitID, order[1], order[2], order[3])
                    unitData.taskType = "resurrecting"
                    unitData.taskStatus = "in_progress"

                    -- Debug: Print when a resurrection order is given
                    -- Spring.Echo("Unit " .. unitID .. " given resurrect order to feature " .. (order[2] - Game.maxUnits))
                    return true
                end
            end
        else
            -- Debug: No valid targets, mark as idle to allow transitioning to other tasks
            -- Spring.Echo("Unit " .. unitID .. " found no valid targets, marked as idle")
            unitData.taskStatus = "idle"
            return false
        end
    end
  end
  return false
end



function handleCollecting(unitID, unitData)
  local unitDefID = Spring.GetUnitDefID(unitID)

  if isMyResbot(unitID, unitDefID) then
    if checkboxes.collecting.state and unitData.taskStatus ~= "in_progress" then
      local resourceNeed = assessResourceNeeds()
      if resourceNeed ~= "full" then
          local x, y, z = spGetUnitPosition(unitID)
          local featureID = findReclaimableFeature(unitID, x, z, reclaimRadius, resourceNeed)
          if featureID and Spring.ValidFeatureID(featureID) then
              spGiveOrderToUnit(unitID, CMD_RECLAIM, {featureID + Game.maxUnits}, {})
              unitData.featureCount = 1
              unitData.lastReclaimedFrame = Spring.GetGameFrame()
              targetedFeatures[featureID] = (targetedFeatures[featureID] or 0) + 1
              unitData.taskType = "collecting"
              unitData.taskStatus = "in_progress"
              return true
          end
      end
    end
  end
  return false
end



function handleEnemyAvoidance(unitID, unitData)
  local unitDefID = Spring.GetUnitDefID(unitID)

  if isMyResbot(unitID, unitDefID) then
    local nearestEnemy, distance = findNearestEnemy(unitID, enemyAvoidanceRadius)
    if nearestEnemy and distance < enemyAvoidanceRadius then
        avoidEnemy(unitID, nearestEnemy)
        unitData.taskType = "avoidingEnemy"
        unitData.taskStatus = "in_progress"
        return true
    end
  end
  return false
end



-- /////////////////////////////////////////// processUnits Function
function processUnits(units)
  -- Extract unitIDs and sort them to ensure deterministic order
  local unitIDs = {}
  for unitID in pairs(units) do
    table.insert(unitIDs, unitID)
  end
  table.sort(unitIDs)

  -- Iterate over sorted unitIDs
  for _, unitID in ipairs(unitIDs) do
    local unitData = units[unitID]
    local unitDefID = spGetUnitDefID(unitID)

    if isMyResbot(unitID, unitDefID) then
      if not Spring.ValidUnitID(unitID) or Spring.GetUnitIsDead(unitID) then
        -- Skip invalid or dead units
      else
        local _, _, _, _, buildProgress = Spring.GetUnitHealth(unitID)
        if buildProgress < 1 then
          -- Skip units that are still being built
        else
          local taskAssigned = false

          -- Check for nearby enemies and react if necessary
          local nearestEnemy, distance = findNearestEnemy(unitID, enemyAvoidanceRadius)
          if nearestEnemy and distance < enemyAvoidanceRadius then
            avoidEnemy(unitID, nearestEnemy)
            unitData.taskType = "avoidingEnemy"
            unitData.taskStatus = "in_progress"
            taskAssigned = true
          end

          -- Continue with task assignment only if no avoidance is needed
          if not taskAssigned then
            -- Resurrecting check
            if checkboxes.resurrecting.state then
              taskAssigned = handleResurrecting(unitID, unitData)
            end

            -- Collecting check
            if not taskAssigned and checkboxes.collecting.state then
              taskAssigned = handleCollecting(unitID, unitData)
            end

            -- Healing check (lowest priority)
            if not taskAssigned and checkboxes.healing.state then
              taskAssigned = handleHealing(unitID, unitData)
            end
          end
        end
      end
    end
  end
end









-- /////////////////////////////////////////// getFeatureResources Function
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
  local unitDefID = Spring.GetUnitDefID(unitID)

  if isMyResbot(unitID, unitDefID) then
    local featuresInRadius = spGetFeaturesInCylinder(x, z, searchRadius)
    local bestFeature = nil
    local bestScore = math.huge

    for _, featureID in ipairs(featuresInRadius) do
        if isTargetReachable(unitID, featureID) then
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
    end

    return bestFeature
  else
    return nil
  end
end





-- ///////////////////////////////////////////  findNearestDamagedFriendly Function
function findNearestDamagedFriendly(unitID, searchRadius)
  local unitDefID = Spring.GetUnitDefID(unitID)

  if isMyResbot(unitID, unitDefID) then
    local myTeamID = spGetMyTeamID() -- Retrieve your team ID
    local x, y, z = spGetUnitPosition(unitID)
    local unitsInRadius = Spring.GetUnitsInCylinder(x, z, searchRadius)

    local minDistSq = searchRadius * searchRadius
    local nearestDamagedUnit = nil
    for _, otherUnitID in ipairs(unitsInRadius) do
      if otherUnitID ~= unitID then
        local otherUnitDefID = spGetUnitDefID(otherUnitID)
        local otherUnitDef = UnitDefs[otherUnitDefID]

        if otherUnitDef and not otherUnitDef.isAirUnit then -- Check if the unit is not an air unit
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
  else
    return nil, nil
  end
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
  if isMyResbot(unitID, unitDefID) then
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

  -- Use the isMyResbot function to check if the unit is one of the types we are interested in managing
  if isMyResbot(unitID, unitDefID) then

    -- Initialize unitData if it does not exist for this unit
    local unitData = unitsToCollect[unitID]
    if not unitData then
      unitData = {
        featureCount = 0,
        lastReclaimedFrame = 0,
        taskStatus = "idle",
        featureID = nil  -- Initialize all fields that will be used
      }
      unitsToCollect[unitID] = unitData
    else
      unitData.taskStatus = "idle"
      unitData.featureID = nil  -- Reset featureID since the unit is idle now
    end

    -- Clear the unit from resurrecting status if it was in the process
    if resurrectingUnits[unitID] then
      resurrectingUnits[unitID] = nil
    end

    -- Clear any healing assignment
    if healingUnits[unitID] then
      local healedUnitID = healingUnits[unitID]
      healingTargets[healedUnitID] = (healingTargets[healedUnitID] or 0) - 1
      if healingTargets[healedUnitID] <= 0 then
        healingTargets[healedUnitID] = nil
      end
      healingUnits[unitID] = nil
    end

    -- Re-queue the unit for tasks based on the current checkbox states
    processUnits({[unitID] = unitData})
  end  -- This 'end' closes the if statement
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

  if isMyResbot(unitID, unitDefID) then
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

function generateOrders(features, addToQueue, returnPos, unitID)
  local unitDefID = Spring.GetUnitDefID(unitID)

  if isMyResbot(unitID, unitDefID) then
    local orders = {}

    for i, featureID in ipairs(features) do
        if isTargetReachable(unitID, featureID) then
            local wreckageDefID = Spring.GetFeatureDefID(featureID)
            local feature = FeatureDefs[wreckageDefID]

            -- Check if feature should be resurrected and is reachable
            if feature.customParams["category"] == "corpses" and checkboxes.resurrecting.state then
                table.insert(orders, {CMD.RESURRECT, featureID + Game.maxUnits, {"shift = false"}})
                break  -- Ensures only one order is processed at a time
            end
        end
    end

    return orders
  else
    return {}
  end
end





-- Calculates the 2D Euclidean distance between two points
local function dist2D(x1, z1, x2, z2)
  return math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2)
end

-- Computes the total distance of the path that visits all the features in the given order
local function computePathDistance(order, positions)
  local distance = 0
  for i = 2, #order do
      local x1, _, z1 = unpack(positions[order[i - 1]])
      local x2, _, z2 = unpack(positions[order[i]])
      distance = distance + dist2D(x1, z1, x2, z2)
  end
  return distance
end

-- Applies the 2-opt heuristic to the given path to find a locally optimal solution
local function optimizePath(path, positions)
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
      -- Spring.Echo("Warning: firstId is nil after processing features. No features were found within range or all features are invalid.")
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



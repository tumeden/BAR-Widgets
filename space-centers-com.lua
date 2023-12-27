function widget:GetInfo()
    return {
        name         = "Space Centers Com",
        desc         = "Pressing Spacebar will center the camera on your Commander, if it's alive",
        author       = "Jazcash",
        date         = "April 2021",
        layer        = 0,
        enabled      = true
    }
end

local GetModKeyState = Spring.GetModKeyState
local Echo = Spring.Echo
local GetTeamUnitsByDefs = Spring.GetTeamUnitsByDefs
local SelectUnitArray = Spring.SelectUnitArray
local SendCommands = Spring.SendCommands
local SetCameraState = Spring.SetCameraState
local GetCameraState = Spring.GetCameraState
local GetActiveCommand = Spring.GetActiveCommand

local myTeamID = Spring.GetMyTeamID()

function widget:KeyPress(key,mods,isRepeat)
    if (isRepeat) then
        return
    end

    local alt, ctrl, meta, shift = GetModKeyState()
    local idx, cmd_id, cmd_type, cmd_name = GetActiveCommand()

    if (cmd_id and cmd_id < 0) then 
        return
    end

    if meta and not alt and not ctrl and not shift then
        local com = GetTeamUnitsByDefs(myTeamID, { UnitDefNames.armcom.id, UnitDefNames.corcom.id })[1]

        if (com) then
            local camState = GetCameraState()
            camState.dist = 1250
    
            SetCameraState(camState)
            SelectUnitArray({com})
            SendCommands("viewselection")
        end
    end
end
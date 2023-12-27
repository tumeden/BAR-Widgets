function widget:GetInfo()
    return {
        name      = "Auto Fight AI",
        desc      = "Autonomous units with resurrection and healing abilities",
        author    = "Tumeden",
        date      = "2023",
        license   = "GNU GPL, v2 or later",
        layer     = 0,
        enabled   = true
    }
end

local function PerformAction(unitID, unitPosX, unitPosZ)
    local nearbyUnits = Spring.GetUnitsInSphere(unitPosX, 0, unitPosZ, 500, Spring.ENEMY_UNITS)

    if #nearbyUnits > 0 then
        Spring.GiveOrderToUnit(unitID, CMD.FIGHT, { unitPosX, 0, unitPosZ, 500 }, { "alt" })
        Spring.GiveOrderToUnit(unitID,
            CMD.INSERT,
            {-1, CMD.FIGHT, CMD.OPT_ALT, unitPosX, 0, unitPosZ, 500},
            {}
        )
    else
        Spring.GiveOrderToUnit(unitID, CMD.FIGHT, { unitPosX, 0, unitPosZ, 500 })
    end
end

function widget:UnitIdle(unitID, unitDefID, unitTeam)
    local unitDef = UnitDefs[unitDefID]

    if unitDef and unitDef.canResurrect and unitDef.canHeal then
        local unitPosX, _, unitPosZ = Spring.GetUnitPosition(unitID)
        PerformAction(unitID, unitPosX, unitPosZ)
    end
end

function widget:GameFrame(frame)
    if frame % 600 == 0 then
        local myUnits = Spring.GetTeamUnits(Spring.GetMyTeamID())

        for _, unitID in ipairs(myUnits) do
            local unitDefID = Spring.GetUnitDefID(unitID)
            local unitDef = UnitDefs[unitDefID]

            if unitDef and unitDef.canResurrect and unitDef.canHeal then
                local unitPosX, _, unitPosZ = Spring.GetUnitPosition(unitID)
                PerformAction(unitID, unitPosX, unitPosZ)
            end
        end
    end
end

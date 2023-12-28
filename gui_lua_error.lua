function widget:GetInfo()
    return {
        name = "Lua Error (& Debug) Display",
        description = "Displays lua errors and other helpful things on-screen",
        author = "MasterBel2",
        version = 0,
        date = "March 2022",
        license = "GNU GPL, v2 or later",
        layer = -math.huge,
        handler = true
    }
end

------------------------------------------------------------------------------------------------------------
-- Imports
------------------------------------------------------------------------------------------------------------

local MasterFramework
local requiredFrameworkVersion = 33
local key

local text
local message = "<Lua Errors>"
local profileText
local textOwnerText

local breakCode = "[Lua Error] Displayed errors"

local function reversedipairsiter(t, i)
    i = i - 1
    if i ~= 0 then
        return i, t[i]
    end
end
local function reversedipairs(t)
    return reversedipairsiter, t, #t + 1
end

local lastUpdatedStats = Spring.GetTimer()
function widget:Update()
    -- local now = Spring.GetTimer()
    -- if 100 < Spring.DiffTimers(now, lastUpdatedStats) then
    --     lastUpdatedStats = now

        local statsArray = table.mapToArray(MasterFramework.stats, function(key, value)
            return "\255\050\100\255" .. key .. " - \255\255\255\255".. value
        end)
        
        table.sort(statsArray)
        -- profileText:SetString(table.joinStrings(statsArray, "\n"))

        -- local textOwnerName = "none"
        -- if widgetHandler.textOwner then
        --     textOwnerName = widgetHandler.textOwner.whInfo.basename
        -- end

        local debugInfoStrings = {}

        for _, widget in pairs(widgetHandler.widgets) do
            if widget.DebugInfo then
                local success, value = pcall(widget.DebugInfo, widget)
                if success then
                    table.insert(debugInfoStrings, MasterFramework.debugDescriptionString(widget:DebugInfo(), "Debug Info for widget \"" .. widget.whInfo.name .. "\""))
                else
                    Spring.Echo("Error in widget:DebugInfo(): " .. value)
                    widget.DebugInfo = nil
                end
            end
        end

        textOwnerText:SetString(table.joinStrings(debugInfoStrings, "\n\n"))

    -- end
end

local function MaxWidth(rect, dimension)
    local wrapper = {}
    function wrapper:Layout(availableWidth, availableHeight)
        return rect:Layout(dimension(), availableHeight)
    end
    function wrapper:Draw(...)
        rect:Draw(...)
    end
    return wrapper 
end

function widget:Initialize()
    MasterFramework = WG.MasterFramework[requiredFrameworkVersion]
    if not MasterFramework then
        Spring.Echo("[Debug Tools] Error: MasterFramework " .. requiredFrameworkVersion .. " not found! Removing self.")
        widgetHandler:RemoveWidget(self)
        return
    end

    text = MasterFramework:WrappingText(message, MasterFramework:Color(1, 0.4, 0.2, 1))
    profileText = MasterFramework:WrappingText("")
    textOwnerText = MasterFramework:WrappingText("")

    local logBegin = 1
    local buffer = Spring.GetConsoleBuffer()

    for index, line in reversedipairs(buffer) do
        if line.text == breakCode then 
            logBegin = index
            break
        end
    end
    for i = logBegin + 1, #buffer do
        self:AddConsoleLine(buffer[i].text)
    end
    local margin = MasterFramework:Dimension(0)
    local element = MasterFramework:FrameOfReference(
        0, 0.5,
        MasterFramework:PrimaryFrame(MasterFramework:MarginAroundRect(
            MasterFramework:VerticalScrollContainer(
                MaxWidth(
                    MasterFramework:VerticalStack(
                        {
                            MasterFramework:MarginAroundRect(text,  margin, margin, margin, margin, { MasterFramework:Color(0.1, 0, 0, 1) }, MasterFramework:Dimension(0), false),
                            MasterFramework:MarginAroundRect(profileText, margin, margin, margin, margin, { MasterFramework:Color(0, 0, 0.1, 1) }, MasterFramework:Dimension(0), false),
                            MasterFramework:MarginAroundRect(textOwnerText, margin, margin, margin, margin, { MasterFramework:Color(0, 0.1, 0, 1) }, MasterFramework:Dimension(0), false),
                        },
                        MasterFramework:Dimension(8),
                        0
                    ),
                    MasterFramework:Dimension(300)
                )
            ),
            margin, margin, margin, margin, 
            { MasterFramework:Color(1, 0, 0, 0) }, 
            MasterFramework:Dimension(0),
            false)
        )
    )

    key = MasterFramework:InsertElement(element, "Lua Error", MasterFramework.layerRequest.top())
end

function widget:Shutdown()
    MasterFramework:RemoveElement(key)
end

function widget:AddConsoleLine(msg)
    if msg:find("Failed to load:") == 1 or msg:find("Error in") == 1 or msg:find("###") then
        message = message .. "\n" .. msg
        text:SetString(message)
        Spring.Echo(breakCode)
    end
    return true
end

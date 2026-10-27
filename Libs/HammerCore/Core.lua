local addonName, ns = ...

-- HammerCore is vendored into each Consecrated Hammer addon and loaded into
-- that addon's private namespace.  There is deliberately no global and no
-- LibStub registration: five addons each run their own pinned copy, so
-- updating one addon can never change another's behaviour.

local HC = {}
ns.HammerCore = HC

HC.VERSION = "0.2.1"
HC.addonName = addonName

-- The one chat colour every addon uses for its name prefix.
HC.CHAT_COLOUR = "d4af37"

local DEFAULTS = {
    startupMessage = true,
    minimap = true,
    minimapAngle = 225,
    theme = "modern",
}

function HC.GetMetadata(key)
    local getter = C_AddOns and C_AddOns.GetAddOnMetadata
    local value = getter and getter(addonName, key)
    if value ~= nil then return value end
    return GetAddOnMetadata and GetAddOnMetadata(addonName, key) or nil
end

-- Global frame names must be unique across every loaded addon, so each copy
-- prefixes its own with the addon name.
function HC.FrameName(suffix)
    return addonName .. suffix
end

function HC.Print(message)
    print("|cff" .. HC.CHAT_COLOUR .. HC.name .. ":|r " .. tostring(message))
end

function HC.Command()
    return "/" .. HC.command
end

-- spec fields:
--   name, command            display name and primary slash command (no slash)
--   aliases                  extra slash commands, never advertised
--   savedVariable            the addon's SavedVariables global name
--   db                       function returning the addon's live saved table
--   icon                     texture path for the window, minimap and About
--   legacy                   { startupMessage = "oldKey", minimap = "oldKey"
--                              or { key = "hide_minimap", invert = true },
--                              minimapAngle = "oldKey", settingsPoint = "oldKey" }
--   diagnostics              function returning the copyable report text
--   status                   function returning the Troubleshooting status text
--   about                    { note, tips, action, chat?, onApply?, credit? }
--                            (see Pages.lua)
--   minimap                  { rightClick = fn, rightClickLabel = "..." }
--   toggle, lock, unlock     { run = fn, help = "..." } shared verbs
--   resetPosition            fn; resetSettings fn (defaults to a full wipe)
--   window                   { width = n, height = n }
--   railButton               { label = string|fn, run = fn, active = fn? }
--   hideInCombat             true hides settings, reports and the minimap
--                            button in combat and refuses to open settings
function HC:Init(spec)
    assert(type(spec) == "table", "HammerCore:Init needs a spec")
    assert(type(spec.name) == "string", "HammerCore:Init needs a name")
    assert(type(spec.command) == "string", "HammerCore:Init needs a command")
    assert(type(spec.db) == "function", "HammerCore:Init needs a db accessor")
    self.spec = spec
    self.name = spec.name
    self.command = spec.command:lower():gsub("^/", "")
    self.VERSION_TEXT = HC.GetMetadata("Version") or "unknown"
    if self.Commands then self.Commands:RegisterCore() end
    if self.Commands then self.Commands:RegisterSlash() end
end

-- HammerCore keeps its own state in one namespaced table inside the addon's
-- saved variables.  The first time it runs, it adopts the addon's older keys
-- and removes them, so a player's existing choices carry over.
function HC.State()
    local db = HC.spec.db()
    if type(db) ~= "table" then return nil end
    if type(db.hammerCore) ~= "table" then
        local state = {}
        -- legacy values are an old key name, or { key = "old", invert = true }
        -- for an old setting stored the other way round (hide_minimap).
        for key, legacy in pairs(HC.spec.legacy or {}) do
            local oldKey = type(legacy) == "table" and legacy.key or legacy
            if db[oldKey] ~= nil then
                local value = db[oldKey]
                if type(legacy) == "table" and legacy.invert then value = not value end
                state[key] = value
                db[oldKey] = nil
            end
        end
        db.hammerCore = state
    end
    local state = db.hammerCore
    for key, value in pairs(DEFAULTS) do
        if state[key] == nil then state[key] = value end
    end
    if type(state.minimapAngle) ~= "number" then state.minimapAngle = DEFAULTS.minimapAngle end
    if state.settingsPoint ~= nil and not HC.ValidPoint(state.settingsPoint) then state.settingsPoint = nil end
    if HC.Theme and not HC.Theme.registry[state.theme] then state.theme = DEFAULTS.theme end
    return state
end

-- The login line names the addon in the chat colour but, unlike other
-- messages, has no colon: "Name v1.2.3 loaded - type ...".
local ANCHORS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }

-- A saved position is { point, relativePoint, x, y }; anything else, including
-- NaN offsets from a bad drag, is discarded rather than handed to SetPoint.
function HC.ValidPoint(point)
    if type(point) ~= "table" then return false end
    local x, y = tonumber(point[3]), tonumber(point[4])
    return ANCHORS[point[1]] and ANCHORS[point[2]] and x and y and x == x and y == y and true or false
end

function HC.LoginMessage(coloured)
    local name = coloured and ("|cff" .. HC.CHAT_COLOUR .. HC.name .. "|r") or HC.name
    return name .. " v" .. tostring(HC.VERSION_TEXT) .. " loaded - type " .. HC.Command()
        .. " for settings, " .. HC.Command() .. " help for commands"
end

local function hideForCombat()
    if HC.Settings then HC.Settings:Hide() end
    if HC.Copy and HC.Copy.frame then HC.Copy.frame:Hide() end
    if HC.Minimap and HC.Minimap.button then HC.Minimap.button:Hide() end
end

-- Called by the addon once its saved variables are ready.
function HC:Start()
    local state = HC.State()
    if HC.spec.hideInCombat and not self.combatFrame then
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frame:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_DISABLED" then hideForCombat()
            elseif HC.Minimap then HC.Minimap:Update() end
        end)
        self.combatFrame = frame
    end
    if self.Minimap then self.Minimap:Create() end
    if self.Settings then self.Settings:CreateLauncher() end
    if state and state.startupMessage then print(HC.LoginMessage(true)) end
end

function HC.SetStartupMessage(enabled)
    local state = HC.State()
    state.startupMessage = enabled and true or false
    HC.Print("startup message " .. (state.startupMessage and "on" or "off"))
end

function HC.SetMinimap(enabled)
    local state = HC.State()
    state.minimap = enabled and true or false
    if HC.Minimap then HC.Minimap:Update() end
    HC.Print("minimap button " .. (state.minimap and "shown" or "hidden"))
end

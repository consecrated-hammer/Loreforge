local addonName, ns = ...
local HC = ns.HammerCore
local T = HC.Theme

-- One command table drives the slash handler, `help` and the Commands
-- settings page, so the three can never disagree.  Core commands behave
-- identically in every addon; each addon adds its own under named sections.

local Commands = { list = {}, byName = {}, sections = {} }
HC.Commands = Commands

local CORE, DISPLAY = "Core", "Display"

-- entry = { name = "reset position", args = "[on|off]"?, help = "...",
--           section = "Bar", run = function(args) end, hidden = true? }
-- A hidden command works but is left out of help and the Commands page.
-- A name may be two words; the longer match wins when dispatching.
function Commands:Add(entry)
    assert(type(entry.name) == "string" and type(entry.run) == "function", "command needs name and run")
    entry.name = entry.name:lower()
    entry.section = entry.section or HC.name
    assert(not self.byName[entry.name], "duplicate command: " .. entry.name)
    self.byName[entry.name] = entry
    self.list[#self.list + 1] = entry
    local known = false
    for _, section in ipairs(self.sections) do
        if section == entry.section then known = true end
    end
    if not known then self.sections[#self.sections + 1] = entry.section end
    return entry
end

-- A reference entry that is not a slash command, such as a mouse action on
-- the addon's frame.  It appears in help and on the Commands page only.
-- action = { usage = "Left-click a cell", help = "...", section = "Grid" }
function Commands:AddAction(action)
    assert(type(action.usage) == "string" and type(action.help) == "string", "action needs usage and help")
    action.section = action.section or HC.name
    action.isAction = true
    self.list[#self.list + 1] = action
    local known = false
    for _, section in ipairs(self.sections) do
        if section == action.section then known = true end
    end
    if not known then self.sections[#self.sections + 1] = action.section end
    return action
end

-- Parses "on", "off" or nothing (toggle) against the current value.
local function onOff(args, current)
    if args == "on" then return true end
    if args == "off" then return false end
    if args == "" then return not current end
    return nil
end
Commands.OnOff = onOff

function Commands:RegisterCore()
    if self.coreRegistered then return end
    self.coreRegistered = true
    local spec = HC.spec
    local function usage(entry)
        HC.Print("usage: " .. HC.Command() .. " " .. entry.name .. (entry.args and (" " .. entry.args) or ""))
    end

    self:Add({ name = "", section = CORE, help = "Open settings",
        run = function() HC.Settings:Show() end })
    self:Add({ name = "help", section = CORE, help = "List every command",
        run = function() Commands:PrintHelp() end })
    self:Add({ name = "version", section = CORE, help = "Print the loaded version",
        run = function() HC.Print(Commands.VersionText()) end })
    self:Add({ name = "about", section = CORE, help = "Open the About page",
        run = function() HC.Settings:Show("About") end })
    self:Add({ name = "debug", section = CORE, help = "Open a copyable diagnostic report",
        run = function() HC.Copy:Show(HC.name .. " diagnostics", HC.DiagnosticReport()) end })
    self:Add({ name = "startup", args = "[on|off]", section = CORE, help = "Show the startup message",
        run = function(args, entry)
            local value = onOff(args, HC.State().startupMessage)
            if value == nil then return usage(entry) end
            HC.SetStartupMessage(value)
        end })
    self:Add({ name = "minimap", args = "[on|off]", section = CORE, help = "Show the minimap button",
        run = function(args, entry)
            local value = onOff(args, HC.State().minimap)
            if value == nil then return usage(entry) end
            HC.SetMinimap(value)
        end })
    -- Hidden while Classic is switched off; see Theme.lua.
    self:Add({ name = "theme", args = "[modern|classic]", section = CORE, hidden = true,
        help = "Choose the settings theme",
        run = function(args)
            if args == "" then
                local _, key = T.Active()
                return HC.Print("theme " .. T.registry[key].label:lower())
            end
            local ok, reason = T.Set(args)
            if not ok then return HC.Print(reason) end
            HC.Print("theme " .. args .. "; /reload to apply")
        end })
    if spec.resetPosition then
        self:Add({ name = "reset position", section = CORE, help = "Move " .. HC.name .. " back to its default place",
            run = function() spec.resetPosition(); HC.Print("position reset") end })
    end
    self:Add({ name = "reset settings", section = CORE, help = "Reset every setting after a confirmation",
        run = function() HC.ConfirmResetSettings() end })
    self:Add({ name = "quiz", section = CORE, help = "Take a five-question lore quiz",
        run = function() HC.Quiz:Start() end })
    self:Add({ name = "quiz timer", args = "<3-30|off>", section = CORE, hidden = true,
        help = "Seconds per quiz question",
        run = function(args, entry)
            local state = HC.State()
            if args == "off" then
                state.quizSeconds = false
                return HC.Print("quiz timer off")
            end
            local seconds = tonumber(args)
            if not seconds or seconds < 3 or seconds > 30 then return usage(entry) end
            state.quizSeconds = math.floor(seconds)
            HC.Print("quiz timer " .. state.quizSeconds .. " seconds")
        end })

    for _, verb in ipairs({ "toggle", "lock", "unlock" }) do
        local handler = spec[verb]
        if handler then
            self:Add({ name = verb, section = DISPLAY, help = handler.help, run = handler.run })
        end
    end
end

function Commands.VersionText()
    local text = "v" .. tostring(HC.VERSION_TEXT)
    if HC.spec.clientLabel then text = text .. " (" .. tostring(HC.spec.clientLabel()) .. ")" end
    return text .. ", HammerCore " .. HC.VERSION
end

function Commands:Find(message)
    local words = {}
    for word in (message or ""):gmatch("%S+") do words[#words + 1] = word end
    if #words >= 2 then
        local pair = (words[1] .. " " .. words[2]):lower()
        if self.byName[pair] then
            return self.byName[pair], table.concat(words, " ", 3):lower()
        end
    end
    local first = (words[1] or ""):lower()
    return self.byName[first], table.concat(words, " ", 2):lower()
end

function Commands:Dispatch(message)
    local entry, args = self:Find(message)
    if not entry then
        HC.Print("unknown command. Type " .. HC.Command() .. " help for the list.")
        return false
    end
    entry.run(args, entry)
    return true
end

-- Sections in display order: Core, Display, then the addon's own.
function Commands:Sections()
    local ordered = {}
    for _, name in ipairs({ CORE, DISPLAY }) do
        for _, section in ipairs(self.sections) do
            if section == name then ordered[#ordered + 1] = name end
        end
    end
    for _, section in ipairs(self.sections) do
        if section ~= CORE and section ~= DISPLAY then ordered[#ordered + 1] = section end
    end
    local result = {}
    for _, section in ipairs(ordered) do
        local entries = {}
        for _, entry in ipairs(self.list) do
            if entry.section == section and not entry.hidden then entries[#entries + 1] = entry end
        end
        result[#result + 1] = { name = section, entries = entries }
    end
    return result
end

function Commands.Usage(entry)
    if entry.isAction then return entry.usage end
    local text = HC.Command()
    if entry.name ~= "" then text = text .. " " .. entry.name end
    if entry.args then text = text .. " " .. entry.args end
    return text
end

function Commands:PrintHelp()
    local gold = "|cff" .. HC.CHAT_COLOUR
    HC.Print("commands")
    for _, section in ipairs(self:Sections()) do
        print(T.Code("muted") .. section.name .. "|r")
        for _, entry in ipairs(section.entries) do
            print("  " .. gold .. Commands.Usage(entry) .. "|r - " .. entry.help)
        end
    end
end

function Commands:RegisterSlash()
    local key = HC.name:upper():gsub("[^%w]", "")
    local slashes = { HC.command }
    for _, alias in ipairs(HC.spec.aliases or {}) do slashes[#slashes + 1] = alias:lower():gsub("^/", "") end
    for index, slash in ipairs(slashes) do _G["SLASH_" .. key .. index] = "/" .. slash end
    SlashCmdList[key] = function(message) Commands:Dispatch(message) end
end

-- ── Reset and diagnostics ──────────────────────────────────────────────────

function HC.ConfirmResetSettings()
    local key = HC.name:upper():gsub("[^%w]", "") .. "_HAMMERCORE_RESET"
    if StaticPopupDialogs and StaticPopup_Show then
        StaticPopupDialogs[key] = StaticPopupDialogs[key] or {
            text = "Reset every " .. HC.name .. " setting and reload the interface?",
            button1 = YES or "Yes", button2 = NO or "No",
            OnAccept = function() HC.ResetSettings() end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show(key)
    end
end

-- The default reset clears the addon's saved variables and reloads, which
-- is the one reset that behaves the same for every addon.
function HC.ResetSettings()
    if HC.spec.resetSettings then return HC.spec.resetSettings() end
    if HC.spec.savedVariable then _G[HC.spec.savedVariable] = nil end
    if ReloadUI then ReloadUI() end
end

function HC.DiagnosticReport()
    local state = HC.State() or {}
    local lines = {
        HC.name .. " diagnostics",
        "Version: " .. Commands.VersionText(),
        "Startup message: " .. (state.startupMessage and "on" or "off"),
        "Minimap button: " .. (state.minimap and "shown" or "hidden"),
        "Theme: " .. tostring(state.theme),
    }
    if HC.Settings.errors then
        for name, err in pairs(HC.Settings.errors) do
            lines[#lines + 1] = "Settings page failed: " .. name .. ": " .. err
        end
    end
    if HC.spec.diagnostics then
        lines[#lines + 1] = ""
        local ok, extra = pcall(HC.spec.diagnostics)
        lines[#lines + 1] = ok and tostring(extra) or ("Diagnostics failed: " .. tostring(extra))
    end
    return table.concat(lines, "\n")
end

local addonName, ns = ...
local HC = ns.HammerCore
local T, UI = HC.Theme, HC.UI
local Profiles = HC.Profiles
local Auto = Profiles.Auto

-- The shared Profiles settings page, the compact profile selector other pages
-- put at their top, and the dialogs behind New, Rename, Delete and Reset.

local MODE_LABELS = { OFF = "Off", AUTO = "Switch automatically", ASK = "Ask first" }
local GROUP_LABELS = { ANY = "Any group", SOLO = "Solo", PARTY = "Party", RAID = "Raid" }
local INSTANCE_LABELS = { ANY = "Anywhere", NONE = "Open world", PARTY = "Dungeon", RAID = "Raid",
    PVP = "Battleground", ARENA = "Arena", SCENARIO = "Scenario" }
local SOURCE_LABELS = { INSTANCE = "Instance size", GROUP = "Group size" }

local function labels(list, names)
    local out = {}
    for index, value in ipairs(list) do out[index] = names[value] end
    return out
end

local function names() return Profiles:Names() end

-- ── Dialogs ────────────────────────────────────────────────────────────────

function Profiles:PromptNew(saveAs)
    local data = self:Data()
    local fromDefaults = not saveAs and data.newFrom == "DEFAULTS"
    HC.Dialog:Prompt({
        title = saveAs and "Save as new profile" or "New profile",
        text = fromDefaults and "Starts from the default settings."
            or ("Starts as a copy of " .. tostring(self:Loaded()) .. "."),
        accept = "Create",
        maxLetters = self.NAME_LENGTH,
        onAccept = function(text)
            local name, problem = Profiles:Create(text, saveAs and "ACTIVE" or nil)
            if not name then return problem end
        end,
    })
end

function Profiles:PromptRename()
    local current = self:Loaded()
    HC.Dialog:Prompt({
        title = "Rename profile",
        default = current,
        maxLetters = self.NAME_LENGTH,
        accept = "Rename",
        onAccept = function(text)
            local name, problem = Profiles:Rename(current, text)
            if not name then return problem end
        end,
    })
end

function Profiles:ConfirmDelete()
    local current = self:Loaded()
    if self:Count() <= 1 then return end
    HC.Dialog:Confirm({
        title = "Delete profile",
        text = "Delete the " .. current .. " profile?",
        accept = "Delete", cancel = "Keep",
        onAccept = function() Profiles:Delete(current) end,
    })
end

function Profiles:ConfirmReset()
    local current = self:Loaded()
    HC.Dialog:Confirm({
        title = "Reset profile",
        text = "Put " .. current .. " back to the defaults?",
        accept = "Reset", cancel = "Keep",
        onAccept = function() Profiles:Reset() end,
    })
end

function Profiles:ConfirmCopy(source)
    local current = self:Loaded()
    HC.Dialog:Confirm({
        title = "Copy profile",
        text = "Replace " .. current .. " with a copy of " .. source .. "?",
        accept = "Copy", cancel = "Keep",
        onAccept = function() Profiles:CopyFrom(source) end,
    })
end

-- ── The selector other pages use ───────────────────────────────────────────

-- A Profile dropdown and a Save as new button, for the top of a page whose
-- settings belong to profiles, under the page's own Profile heading: the
-- row has no title of its own, so the dropdown comes first.  Returns the row
-- and the next y.
function Profiles:Selector(parent, y, hint)
    local row, nextY, select = UI.Dropdown(parent, "Profile",
        hint or "Which profile these settings belong to. Changes save to it straight away.", y,
        names, names,
        function() return Profiles:Loaded() end,
        function(value) Profiles:Switch(value, "manual") end,
        nil, 150, 200)
    if row.Title then row.Title:SetText(""); row.Title:Hide() end
    select:ClearAllPoints()
    select:SetPoint("LEFT", UI.CELL_INSET, 0)
    local save = UI.Button(row, 130, 26)
    save:SetPoint("LEFT", select, "RIGHT", 10, 0)
    save:SetText("Save as new...")
    UI.AttachHint(save, "Save as new profile", "Copy these settings into a new profile and switch to it.")
    save:SetScript("OnClick", function() Profiles:PromptNew(true) end)
    return row, nextY
end

-- ── Page helpers ───────────────────────────────────────────────────────────

local function section(parent, columns)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(UI.CONTENT_WIDTH + UI.PAD * 2, 1)
    frame.hcColumns = columns
    frame.hcRefresh = parent.hcRefresh
    frame.hcRefreshAll = parent.hcRefreshAll
    frame.hcHeaderOwner = parent.hcHeaderOwner or parent
    return frame
end

local function share(child, parent)
    child.hcRefresh = parent.hcRefresh
    child.hcRefreshAll = parent.hcRefreshAll
    child.hcHeaderOwner = parent.hcHeaderOwner or parent
    return child
end

-- Buttons on one row, right-aligned like every other control.
local function buttonRow(parent, title, hint, y, specs)
    local row = UI.Row(parent, y, UI.CELL_H, title, hint)
    local buttons, anchor = {}, nil
    for index = #specs, 1, -1 do
        local spec = specs[index]
        local button = UI.Button(row, spec.width or 96, 26, spec.variant)
        if anchor then
            button:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
        else
            button:SetPoint("RIGHT", row, "RIGHT", -UI.CELL_INSET, 0)
        end
        button:SetText(spec.text)
        if spec.hint then UI.AttachHint(button, spec.text, spec.hint) end
        button:SetScript("OnClick", spec.run)
        buttons[index] = button
        anchor = button
    end
    return buttons, row.hcNextY
end

local function plural(count) return count == 1 and "1 player" or (count .. " players") end

-- "Party or raid", or the any label when nothing (or everything) is ticked.
function Auto.DescribeSet(field, list, names)
    if type(field) == "string" then field = { [field] = true } end
    local parts = {}
    for _, value in ipairs(list) do
        if value ~= "ANY" and type(field) == "table" and field[value] then parts[#parts + 1] = names[value] end
    end
    if #parts == 0 then return names.ANY end
    if #parts == 1 then return parts[1] end
    local last = table.remove(parts)
    return table.concat(parts, ", ") .. " or " .. last:lower()
end

function Auto.Describe(rule)
    local size = rule.min == rule.max and plural(rule.min) or (rule.min .. "-" .. rule.max .. " players")
    return Auto.DescribeSet(rule.group, Auto.GROUPS, GROUP_LABELS) .. ", " .. size .. ", "
        .. Auto.DescribeSet(rule.instance, Auto.INSTANCES, INSTANCE_LABELS):lower()
end

-- A rule's tick list: "Any" clears the set; each other choice toggles.
local function ruleChoices(rule, key, list, names, setRule)
    local items = {}
    for _, value in ipairs(list) do
        items[#items + 1] = {
            label = names[value],
            get = function()
                local field = rule()[key]
                local empty = type(field) ~= "table" or next(field) == nil
                if value == "ANY" then return empty end
                return not empty and field[value] == true
            end,
            set = function() setRule(value) end,
        }
    end
    return {
        items = items,
        summary = function() return Auto.DescribeSet(rule()[key], list, names) end,
    }
end

function Auto.DescribeContext(context)
    local where = INSTANCE_LABELS[context.instance]:lower()
    if context.instance ~= "NONE" and context.maxPlayers > 0 then
        where = where .. " (" .. context.maxPlayers .. ")"
    end
    local who = context.group == "SOLO" and "Solo" or (GROUP_LABELS[context.group] .. " of " .. context.size)
    return who .. ", " .. where
end

-- One line saying what the rules would do right now.
function Auto.Status()
    local auto, state = Auto.Settings()
    if not auto then return "" end
    local context = Auto.Context()
    local index, rule = Auto.Match(auto.rules, context)
    local text = "Now: " .. Auto.DescribeContext(context) .. ". "
    if not index then
        text = text .. "No rule matches."
    elseif rule.profile == "" then
        text = text .. "Rule " .. index .. " keeps the current profile."
    else
        text = text .. "Rule " .. index .. " picks " .. rule.profile .. "."
    end
    if auto.mode ~= "OFF" and state and state.hold then text = text .. " Held by your manual pick." end
    return text, index
end

-- ── The page ───────────────────────────────────────────────────────────────

-- spec = { name?, title?, description?, extra = function(frame, y) -> y }
-- extra adds addon-specific rows after the profile controls, such as a line
-- saying what a profile saves.
function Profiles:NewPage(spec)
    spec = spec or {}
    local function build(panel, tab)
        local sections = {}
        local function add(frame, height, visible)
            sections[#sections + 1] = { frame = frame, height = height, visible = visible }
        end
        local function data() return Profiles:Data() end
        local function auto() return data().auto end

        if tab == "profiles" then
        -- Profile -------------------------------------------------------------
        local manage = section(panel)
        local y = -8
        _, y = UI.Header(manage, "Profile", y)
        _, y = UI.Dropdown(manage, "Active profile",
            "Changes on every page save to this profile straight away.", y,
            names, names,
            function() return Profiles:Loaded() end,
            function(value) Profiles:Switch(value, "manual") end,
            nil, 150, 220)
        local buttons
        buttons, y = buttonRow(manage, "Manage", "Create, rename, delete or reset profiles.", y, {
            { text = "New...", variant = "primary", hint = "Create a profile and switch to it.",
                run = function() Profiles:PromptNew(false) end },
            { text = "Rename...", hint = "Rename the active profile.",
                run = function() Profiles:PromptRename() end },
            { text = "Delete", variant = "danger", hint = "Delete the active profile. You always keep at least one.",
                run = function() Profiles:ConfirmDelete() end },
            { text = "Reset", variant = "danger", hint = "Put the active profile back to the defaults.",
                run = function() Profiles:ConfirmReset() end },
        })
        UI.OnRefresh(manage, function() UI.SetEnabled(buttons[3], Profiles:Count() > 1) end)
        _, y = UI.Dropdown(manage, "Copy from",
            "Replace the active profile with a copy of another one.", y,
            function()
                local values, loaded = { "" }, Profiles:Loaded()
                for _, name in ipairs(Profiles:Names()) do
                    if name ~= loaded then values[#values + 1] = name end
                end
                return values
            end,
            function()
                local out, loaded = { "Choose a profile" }, Profiles:Loaded()
                for _, name in ipairs(Profiles:Names()) do
                    if name ~= loaded then out[#out + 1] = name end
                end
                return out
            end,
            function() return "" end,
            function(value) if value ~= "" then Profiles:ConfirmCopy(value) end end,
            nil, 150, 220)
        _, y = UI.Dropdown(manage, "New profiles from",
            "What New... copies. Save as new always copies the active profile.", y,
            { "ACTIVE", "DEFAULTS" }, { "Active profile", "Defaults" },
            function() return data().newFrom end,
            function(value) Profiles:SetNewFrom(value) end,
            nil, 150, 220)
        _, y = UI.Check(manage, "Per-character profile",
            "Each character remembers its own active profile. The profiles themselves are shared.", y,
            function() return data().perCharacter end,
            function(value) Profiles:SetPerCharacter(value) end)
        add(manage, -y + 4)

        -- Addon extras --------------------------------------------------------
        if spec.extra then
            local extra = section(panel)
            local bottom = spec.extra(extra, -8)
            add(extra, -(bottom or -8) + 4)
        end

        end

        if tab == "auto" then
        -- Auto-switch ---------------------------------------------------------
        local autoHead = section(panel)
        y = -8
        _, y = UI.Header(autoHead, "Auto-switch", y)
        local modeRow
        modeRow, y = UI.Dropdown(autoHead, "Mode",
            "Switch profiles by the rules below when your group or instance changes.", y,
            Auto.MODES, labels(Auto.MODES, MODE_LABELS),
            function() return auto().mode end,
            function(value) Auto:SetMode(value) end,
            nil, 150, 220)
        local status = UI.Text(autoHead, "", y - 2)
        UI.OnRefresh(autoHead, function()
            local text = Auto.Status()
            status:SetText(text)
            T.Text(status, auto().mode == "OFF" and "muted" or "text")
        end)
        y = y - 24
        _, y = UI.Text(autoHead, "First matching rule wins. Shift-click + or - to step by 5.", y)
        add(autoHead, -y + 4)

        for index = 1, Auto.MAX_RULES do
            local holder = section(panel)
            local card = share(UI.Card(holder, -2, 136, UI.CONTENT_WIDTH), holder)
            local function rule() return Auto:Rules()[index] or Auto.NewRule() end
            local function set(key) return function(value) Auto:SetRule(index, key, value) end end

            local title = UI.FontString(card, "GameFontNormal", "accent")
            title:SetPoint("TOPLEFT", 12, -12)
            title:SetText("Rule " .. index)
            local summary = UI.FontString(card, "GameFontHighlightSmall", "muted")
            summary:SetPoint("LEFT", title, "RIGHT", 10, 0)
            summary:SetPoint("RIGHT", card, "TOPRIGHT", -200, -18)
            summary:SetJustifyH("LEFT")
            if summary.SetWordWrap then summary:SetWordWrap(false) end

            local remove = UI.Button(card, 70, 22, "danger")
            remove:SetPoint("TOPRIGHT", -10, -8)
            remove:SetText("Remove")
            local down = UI.Button(card, 52, 22)
            down:SetPoint("RIGHT", remove, "LEFT", -6, 0)
            down:SetText("Down")
            local up = UI.Button(card, 52, 22)
            up:SetPoint("RIGHT", down, "LEFT", -6, 0)
            up:SetText("Up")
            UI.AttachHint(up, "Move up", "Earlier rules are checked first.")
            UI.AttachHint(down, "Move down", "Later rules are checked after this one.")
            local function changed() Profiles.RefreshSettings() end
            up:SetScript("OnClick", function() Auto:MoveRule(index, -1); changed() end)
            down:SetScript("OnClick", function() Auto:MoveRule(index, 1); changed() end)
            remove:SetScript("OnClick", function() Auto:RemoveRule(index); changed() end)

            UI.CompactSelect(card, "Profile", "The profile this rule switches to.", 12, -38, 160,
                function()
                    local values = { "" }
                    for _, name in ipairs(Profiles:Names()) do values[#values + 1] = name end
                    return values
                end,
                function()
                    local out = { "No change" }
                    for _, name in ipairs(Profiles:Names()) do out[#out + 1] = name end
                    return out
                end,
                function() return rule().profile end, set("profile"))
            UI.CompactMultiSelect(card, "Group", "Tick any mix of solo, party and raid. None ticked matches any.",
                184, -38, 160, ruleChoices(rule, "group", Auto.GROUPS, GROUP_LABELS, set("group")))
            UI.CompactMultiSelect(card, "Where",
                "Tick any mix of the open world and instance kinds. None ticked matches anywhere.",
                356, -38, 172, ruleChoices(rule, "instance", Auto.INSTANCES, INSTANCE_LABELS, set("instance")))
            UI.CompactSelect(card, "Size from",
                "Instance size uses the instance's maximum inside one, so the raid profile is ready before people arrive. Group size counts who is in the group.",
                12, -86, 160, Auto.SOURCES, labels(Auto.SOURCES, SOURCE_LABELS),
                function() return rule().source end, set("source"))
            UI.Stepper(card, "Min size", "Smallest size this rule matches.", 184, -86, 1, 40,
                function() return rule().min end, set("min"))
            UI.Stepper(card, "Max size", "Largest size this rule matches.", 296, -86, 1, 40,
                function() return rule().max end, set("max"))

            UI.OnRefresh(card, function()
                local rules = Auto:Rules()
                local current = rules[index]
                if not current then return end
                summary:SetText(Auto.Describe(current))
                UI.SetEnabled(up, index > 1)
                UI.SetEnabled(down, index < #rules)
                local _, matched = Auto.Status()
                T.Border(card, matched == index and "accent" or "edge")
            end)
            add(holder, 144, function() return index <= #Auto:Rules() end)
        end

        local ruleActions = section(panel)
        y = -4
        local empty = UI.Text(ruleActions, "No rules yet. Add one to start.", y)
        local ruleButtons = {}
        local addButton = UI.Button(ruleActions, 120, 26, "primary")
        addButton:SetText("Add rule")
        UI.AttachHint(addButton, "Add rule", "Adds a rule for the active profile at the bottom of the list.")
        addButton:SetScript("OnClick", function()
            Auto:AddRule()
            Profiles.RefreshSettings()
        end)
        local resetRules = UI.Button(ruleActions, 120, 26)
        resetRules:SetText("Reset rules")
        UI.AttachHint(resetRules, "Reset rules", "Put the rules back to the starter set.")
        resetRules:SetScript("OnClick", function()
            HC.Dialog:Confirm({ title = "Reset rules", text = "Replace your rules with the starter set?",
                accept = "Reset", cancel = "Keep",
                onAccept = function() Auto:ResetRules(); Profiles.RefreshSettings() end })
        end)
        ruleButtons[1], ruleButtons[2] = addButton, resetRules
        UI.OnRefresh(ruleActions, function()
            local count = #Auto:Rules()
            empty:SetShown(count == 0)
            local top = count == 0 and -26 or -4
            addButton:ClearAllPoints()
            addButton:SetPoint("TOPLEFT", UI.PAD, top)
            resetRules:ClearAllPoints()
            resetRules:SetPoint("LEFT", addButton, "RIGHT", 8, 0)
            UI.SetEnabled(addButton, count < Auto.MAX_RULES)
        end)
        add(ruleActions, 60)

        local when = section(panel, 2)
        y = -8
        _, y = UI.Header(when, "Check when", y)
        _, y = UI.Check(when, "Joining or leaving a group", "Includes a party turning into a raid.", y,
            function() return auto().onGroup end, function(value) Auto:Set("onGroup", value) end)
        _, y = UI.Check(when, "Entering or leaving an instance", nil, y,
            function() return auto().onInstance end, function(value) Auto:Set("onInstance", value) end)
        _, y = UI.Check(when, "Group size changes", "Someone joins or leaves.", y,
            function() return auto().onSize end, function(value) Auto:Set("onSize", value) end)
        y = UI.Flush(when, y)
        add(when, -y + 4)

        local ask = section(panel)
        ask.hcParentRow = modeRow
        y = -4
        _, y = UI.Header(ask, "Ask first", y)
        _, y = UI.Dropdown(ask, "After declining",
            "Whether a declined switch asks again at the next check.", y,
            { "STAY", "ASK" }, { "Ask when the rule changes", "Ask again next time" },
            function() return auto().afterNo end, function(value) Auto:Set("afterNo", value) end,
            nil, 150, 220)
        _, y = UI.Dropdown(ask, "In combat",
            "The switch itself always waits for combat to end.", y,
            { "NOW", "AFTER" }, { "Ask now", "Ask after combat" },
            function() return auto().combatAsk end, function(value) Auto:Set("combatAsk", value) end,
            nil, 150, 220)
        add(ask, -y + 4, function() return auto().mode == "ASK" end)

        local other = section(panel)
        y = -4
        _, y = UI.Header(other, "Other", y)
        _, y = UI.Dropdown(other, "Manual pick lasts",
            "How long a profile you pick yourself beats the rules.", y,
            { "RULE", "INSTANCE", "TOGGLE" },
            { "Until the rule changes", "Until the next instance", "Until auto-switch restarts" },
            function() return auto().manual end, function(value) Auto:Set("manual", value) end,
            nil, 150, 220)
        _, y = UI.Check(other, "Chat message on switch", "Print a line when a rule switches profiles.", y,
            function() return auto().message end, function(value) Auto:Set("message", value) end)
        _, y = UI.PageReset(other, y, function()
            Auto:ResetSettings()
            Profiles.RefreshSettings()
        end, "Reset auto-switch")
        add(other, -y + 4)
        end

        local pageBottom
        local function reflow()
            local top = -8
            for _, entry in ipairs(sections) do
                local shown = not entry.visible or entry.visible()
                entry.frame:SetShown(shown)
                if shown then
                    entry.frame:ClearAllPoints()
                    entry.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, top)
                    entry.frame:SetHeight(entry.height)
                    top = top - entry.height
                end
            end
            pageBottom = top - 8
            if panel.hcSetBottom then panel.hcSetBottom(pageBottom) end
        end
        UI.OnRefresh(panel, reflow)
        reflow()
        return pageBottom
    end
    return HC.Settings:NewPage({
        name = spec.name or "Profiles",
        title = spec.title or "Profiles",
        group = "main",
        profilesPage = true,
        description = spec.description
            or "Saved layouts you can switch between, by hand or when your group changes.",
        tabs = {
            { name = "Profiles", build = function(panel) return build(panel, "profiles") end },
            { name = "Auto-switch", build = function(panel) return build(panel, "auto") end },
        },
    })
end

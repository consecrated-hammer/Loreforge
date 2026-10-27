local addonName, ns = ...
local HC = ns.HammerCore
local T, UI = HC.Theme, HC.UI

-- The pages every addon shares.  Addons extend them through spec hooks
-- rather than replacing them:
--   spec.visibility(panel, y) -> y       extra controls under the standard two
--   spec.status() -> text                Troubleshooting status card
--   spec.troubleshooting(panel, y) -> y  extra Troubleshooting controls
--   spec.about = { tips = {...}, note = "HEADING", credit = "...",
--                  extra = function(panel, y, card) -> y }

local Pages = {}
HC.Pages = Pages

-- ── Visibility (main section) ──────────────────────────────────────────────

Pages.visibility = { name = "Visibility", group = "main", standard = true,
    description = "When things show." }
Pages.visibility.build = function(panel, y)
    -- The addon's own sections come first; the shared toggles sit under
    -- "Other" at the bottom, in the order Salve established.
    if HC.spec.visibility then y = HC.spec.visibility(panel, y) - 8 end
    _, y = UI.Header(panel, "Other", y)
    _, y = UI.Check(panel, "Show minimap button", "Show the " .. HC.name .. " button on the minimap.", y,
        function() return HC.State().minimap end,
        function(value)
            HC.State().minimap = value
            HC.Minimap:Update()
        end)
    _, y = UI.Check(panel, "Show startup message", "Print the loaded version when you log in.", y,
        function() return HC.State().startupMessage end,
        function(value) HC.State().startupMessage = value end)
    return y
end

-- Addons call this at the point in their page list where Visibility belongs.
function HC.Settings:AddVisibility()
    for _, spec in ipairs(self.queue) do
        if spec == Pages.visibility then return end
    end
    self.queue[#self.queue + 1] = Pages.visibility
end

-- ── Theme ──────────────────────────────────────────────────────────────────

local theme = { name = "Theme", group = "reference", standard = true,
    description = "How settings look." }
theme.build = function(panel, y)
    _, y = UI.Header(panel, "Settings theme", y)
    local rows = {}
    for _, key in ipairs(T.order) do
        local entry = T.registry[key]
        local row = UI.Row(panel, y, 28, nil,
            entry.available and ("Use the " .. entry.label .. " theme.") or "Coming later.")
        row.hcHintTitle = entry.label
        local radio = UI.CheckButton(row)
        radio:SetSize(14, 14)
        radio:SetPoint("LEFT", 12, 0)
        radio.Text:SetText(entry.available and entry.label or (entry.label .. " (coming later)"))
        if not entry.available then T.Text(radio.Text, "muted") end
        local function choose()
            if not entry.available then return end
            T.Set(key)
            panel.hcRefreshAll()
        end
        radio:SetScript("OnClick", choose)
        row:SetScript("OnMouseUp", choose)
        rows[#rows + 1] = { radio = radio, key = key }
        y = y - 32
    end
    local reload = UI.Button(panel, 140, 22, "primary")
    reload:SetPoint("TOPLEFT", UI.PAD, y - 4)
    reload:SetText("Reload to apply")
    reload:SetScript("OnClick", function() if ReloadUI then ReloadUI() end end)
    local builtWith = select(2, T.Active())
    UI.OnRefresh(panel, function()
        local chosen = HC.State().theme
        for _, row in ipairs(rows) do row.radio:SetChecked(row.key == chosen) end
        reload:SetShown(chosen ~= builtWith)
    end)
    return y - 34
end

-- ── Commands ───────────────────────────────────────────────────────────────

local commands = { name = "Commands", group = "reference", standard = true }
commands.build = function(panel, y)
    local gold = "|cff" .. HC.CHAT_COLOUR
    local first = true
    for _, section in ipairs(HC.Commands:Sections()) do
        if not first then y = y - 10 end
        first = false
        local heading = UI.FontString(panel, "GameFontHighlightSmall", "accent")
        heading:SetPoint("TOPLEFT", UI.PAD, y)
        heading:SetText(section.name:upper())
        y = y - 20
        for _, entry in ipairs(section.entries) do
            local row = CreateFrame("Frame", nil, panel, "BackdropTemplate")
            row:SetPoint("TOPLEFT", UI.PAD, y)
            row:SetSize(UI.CONTENT_WIDTH, 28)
            T.Surface(row, "raised", "edge")
            local usage = UI.FontString(row, "GameFontHighlightSmall")
            usage:SetPoint("LEFT", 12, 0)
            usage:SetWidth(230)
            usage:SetJustifyH("LEFT")
            if usage.SetWordWrap then usage:SetWordWrap(false) end
            usage:SetText(gold .. HC.Commands.Usage(entry) .. "|r")
            local does = UI.FontString(row, "GameFontHighlightSmall")
            does:SetPoint("LEFT", 250, 0)
            does:SetWidth(UI.CONTENT_WIDTH - 262)
            does:SetJustifyH("LEFT")
            if does.SetWordWrap then does:SetWordWrap(false) end
            does:SetText(entry.help)
            y = y - 30
        end
    end
    return y - 8
end

-- ── Troubleshooting ────────────────────────────────────────────────────────

local troubleshooting = { name = "Troubleshooting", group = "reference", standard = true,
    description = "Status and diagnostics." }
troubleshooting.build = function(panel, y)
    _, y = UI.Header(panel, "Status", y)
    local card
    card, y = UI.Card(panel, y, 112)
    T.Surface(card, "rail", "edge")
    local status = UI.FontString(card, "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", 14, -12)
    status:SetPoint("BOTTOMRIGHT", -14, 12)
    status:SetJustifyH("LEFT")
    status:SetJustifyV("TOP")
    UI.OnRefresh(panel, function()
        local lines = { "Version: " .. HC.Commands.VersionText() }
        if HC.spec.status then
            local ok, text = pcall(HC.spec.status)
            lines[#lines + 1] = ok and tostring(text) or ("Status failed: " .. tostring(text))
        end
        status:SetText(table.concat(lines, "\n"))
    end)
    local copy = UI.Button(panel, 140, 22)
    copy:SetPoint("TOPLEFT", UI.PAD, y)
    copy:SetText("Copy report")
    UI.AttachHint(copy, "Copy report", "Open a report you can paste into a bug report.")
    copy:SetScript("OnClick", function() HC.Commands:Dispatch("debug") end)
    y = y - 38
    if HC.spec.troubleshooting then y = HC.spec.troubleshooting(panel, y) end
    return y
end

-- ── About ──────────────────────────────────────────────────────────────────
-- Every About page has the same shape: the version card followed by two
-- compact rows.  The first gives the addon's rotating advice; the second
-- opens the lore quiz.  Clicking the addon icon shows a new tip and says
-- something in chat.
--   spec.about = { note = "FROM THE FORGE", tips = { ... },
--                  action = "Polish the anvil",       -- row subtext and icon hint
--                  chat = { ... }?,                   -- lines to print; else the tip
--                  onApply = function() end?,         -- e.g. a sound
--                  credit = "..."? }

local about = { name = "About", group = "reference", standard = true,
    description = "Version and credits." }
about.build = function(panel, y)
    local spec = HC.spec.about or {}
    local meta = HC.GetMetadata
    local gold = "|cff" .. HC.CHAT_COLOUR
    local card
    card, y = UI.Card(panel, y, 96)
    local logo = card:CreateTexture(nil, "ARTWORK")
    logo:SetSize(64, 64)
    logo:SetPoint("LEFT", 14, 0)
    logo:SetTexture(HC.spec.icon)
    local info = UI.FontString(card, "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", 92, -14)
    info:SetWidth(UI.CONTENT_WIDTH - 106)
    info:SetJustifyH("LEFT")
    local function field(label, value)
        return gold .. label .. "|r  " .. tostring(value or "")
    end
    info:SetText(table.concat({
        field("Version", HC.VERSION_TEXT) .. "    " .. field("Released", meta("X-ReleaseDate") or "local build"),
        field("Author", meta("Author") or "consecrated-hammer") .. "    " .. field("Licence", meta("X-License") or "GPL-3.0"),
        field("CurseForge", meta("X-CurseForge") or ""),
        field("Source", meta("X-Website") or ""),
    }, "\n"))

    if spec.tips and #spec.tips > 0 then
        local function row(headingText, subtext, iconTexture, onClick, hintTitle, hintText)
            local holder
            holder, y = UI.Card(panel, y - 6, 78)
            T.Surface(holder, "raised", "edge")

            local heading = UI.FontString(holder, "GameFontHighlight", "accent")
            heading:SetPoint("TOPLEFT", 14, -14)
            heading:SetWidth(136)
            heading:SetJustifyH("LEFT")
            heading:SetText(headingText)

            local detail = UI.FontString(holder, "GameFontHighlightSmall", "muted")
            detail:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -5)
            detail:SetWidth(136)
            detail:SetJustifyH("LEFT")
            if detail.SetWordWrap then detail:SetWordWrap(false) end
            detail:SetText(subtext)

            local icon = CreateFrame("Button", nil, holder)
            icon:SetSize(42, 42)
            icon:SetPoint("LEFT", 162, 0)
            icon:SetNormalTexture(iconTexture)
            icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            icon:SetPushedTexture(iconTexture)
            local pushed = icon.GetPushedTexture and icon:GetPushedTexture()
            if pushed then
                pushed:ClearAllPoints()
                pushed:SetPoint("TOPLEFT", 2, -2)
                pushed:SetPoint("BOTTOMRIGHT", -2, 2)
            end
            icon:SetScript("OnClick", onClick)
            UI.AttachHint(icon, hintTitle, hintText)

            local text = UI.FontString(holder, "GameFontNormal", "flavour")
            text:SetPoint("LEFT", icon, "RIGHT", 18, 0)
            text:SetPoint("RIGHT", -16, 0)
            text:SetJustifyH("LEFT")
            return icon, text
        end

        local last
        local tip
        local function show()
            local nextTip
            repeat nextTip = math.random(#spec.tips) until #spec.tips == 1 or nextTip ~= last
            last = nextTip
            tip:SetText(spec.tips[nextTip])
            return spec.tips[nextTip]
        end
        local function apply()
            local shown = show()
            local line = shown
            if spec.chat and #spec.chat > 0 then line = spec.chat[math.random(#spec.chat)] end
            HC.Print(line)
            if spec.onApply then spec.onApply() end
        end

        local icon
        icon, tip = row(spec.note or "NOTE", spec.action or "A little advice.", HC.spec.icon, apply,
            spec.action or ("Apply " .. HC.name), "Entirely necessary. Probably.")
        Pages.aboutIcon = icon
        Pages.NextTip = show
        Pages.Apply = apply

        local prompts = HC.Quiz and HC.Quiz.Prompts or { "Could you be Khadgar's next assistant?" }
        local puzzle = prompts[math.random(#prompts)]
        local quest, puzzleText = row("Puzzle time!", "Five questions of lore.",
            "Interface\\GossipFrame\\AvailableQuestIcon", function() HC.Quiz:Start() end,
            "Take the quiz", "Five questions of lore. Answer before the sand runs out.")
        puzzleText:SetText(puzzle)
        Pages.quizButton = quest
        UI.OnRefresh(panel, show)
    end
    if spec.credit then
        local credit = UI.FontString(panel, "GameFontDisableSmall", "muted")
        credit:SetPoint("TOP", panel, "TOPLEFT", UI.PAD + UI.CONTENT_WIDTH / 2, y)
        credit:SetText(spec.credit)
        y = y - 20
    end
    return y - 8
end

-- The Theme page is withheld until Classic is ready; see Theme.lua.
Pages.reference = { commands, troubleshooting, about }

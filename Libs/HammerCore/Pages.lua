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
    -- An addon with its own rightClick keeps its own setting for it.
    if HC.Minimap and HC.Minimap.RightClickMode() ~= "custom" then
        _, y = UI.Dropdown(panel, "Minimap right-click", "What right-clicking the minimap button opens.", y,
            { "menu", "settings" }, { "Menu", "Settings" },
            function() return HC.State().minimapRightClick end,
            function(value) HC.State().minimapRightClick = value end)
    end
    -- Addon rows about the minimap button, such as what right-click does.
    if HC.spec.visibilityMinimap then y = HC.spec.visibilityMinimap(panel, y) end
    _, y = UI.Check(panel, "Show startup message", "Print the loaded version when you log in.", y,
        function() return HC.State().startupMessage end,
        function(value) HC.State().startupMessage = value end)
    if HC.WhatsNew and HC.WhatsNew.Enabled() then
        _, y = UI.Check(panel, "Show what's new after updates",
            "Open a short list of new features the first time you log in after an update.", y,
            function() return HC.State().whatsNew ~= false end,
            function(value) HC.State().whatsNew = value end)
        _, y = UI.Check(panel, "Mark unread What's new",
            "Show a yellow ! beside What's new until you've opened it since the last update.", y,
            function() return HC.State().whatsNewDot ~= false end,
            function(value)
                HC.State().whatsNewDot = value
                HC.Settings:RefreshBadges()
            end)
        _, y = UI.Check(panel, "Turn-in sound",
            "Play the quest turn-in sound when opening What's new clears the !.", y,
            function() return HC.State().whatsNewSound ~= false end,
            function(value) HC.State().whatsNewSound = value end)
    end
    if HC.Welcome and HC.Welcome.Enabled() then y = HC.Welcome:AddSettings(panel, y) end
    _, y = UI.Check(panel, "Settings search", "Show a search box at the top of this window.", y,
        function() return HC.State().settingsSearch ~= false end,
        function(value)
            HC.State().settingsSearch = value
            HC.Settings:RefreshSearch()
        end)
    _, y = UI.Check(panel, "Show support links",
        "Show the Discord and Buy me a coffee links at the bottom of this window.", y,
        function() return HC.State().supportLinks ~= false end,
        function(value)
            HC.State().supportLinks = value
            HC.Settings:RefreshFooter()
        end)
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
    -- Flights addons: whether LibTaxiData is there, and where to get it.
    local flights = HC.Flights
    if HC.spec.flights and flights and flights.Estimates() then
        _, y = UI.Header(panel, "Flight times", y)
        local note = UI.FontString(panel, "GameFontHighlightSmall")
        note:SetPoint("TOPLEFT", UI.PAD, y)
        note:SetWidth(UI.CONTENT_WIDTH or 500)
        note:SetJustifyH("LEFT")
        UI.OnRefresh(panel, function()
            local learned = flights.enabled and flights:LearnedCount() or 0
            note:SetText((flights.LibraryInstalled()
                and "LibTaxiData is installed: flight times from your first flight."
                or "LibTaxiData isn't installed: flight times are learned as you fly.")
                .. " Routes learned: " .. learned .. ".")
        end)
        y = y - 22
        local get = UI.Button(panel, 160, 22)
        get:SetPoint("TOPLEFT", UI.PAD, y)
        get:SetText("Get LibTaxiData")
        UI.AttachHint(get, "LibTaxiData", "The free flight path library on CurseForge. Copy the link into your browser.")
        get:SetScript("OnClick", function()
            HC.Dialog:Link({ title = "LibTaxiData", url = flights.LIBRARY_URL, icon = "CurseForge.tga" })
        end)
        y = y - 38
    end
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
    if HC.WhatsNew and HC.WhatsNew.Enabled() then
        local whatsNew = UI.Link(card, "What's new", function() HC.Settings:Show(Pages.whatsNew.name) end,
            "GameFontHighlight")
        whatsNew:SetPoint("TOPRIGHT", -16, -16)
        UI.AttachHint(whatsNew, "What's new", "Show the highlights of recent releases.")
        Pages.whatsNewButton = whatsNew
    end

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

-- ── What's new ─────────────────────────────────────────────────────────────
-- Every release's highlights, newest first, for addons that supply
-- spec.whatsNew. Listed first under REFERENCE, with an unread "!" until the
-- player opens it after an update (see Settings:RefreshBadges).

local MONTHS = { "January", "February", "March", "April", "May", "June", "July",
    "August", "September", "October", "November", "December" }

local function longDate(date)
    local year, month, day = tostring(date or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not year then return nil end
    return tonumber(day) .. " " .. (MONTHS[tonumber(month)] or month) .. " " .. year
end
Pages.LongDate = longDate

Pages.whatsNew = { name = "What's new", group = "reference", standard = true,
    description = "Highlights from each release. The changelog has every detail." }
-- One release as a collapsible card.  The header gives the addon, version,
-- a Latest tag, the release date and how many features and fixes it has;
-- the body lists them (see WhatsNew.DrawItems).
local CARD_HEADER = 56

local function releaseCard(panel, release, newest, relayout)
    local W = HC.WhatsNew
    local width = UI.CONTENT_WIDTH
    local card = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    card:SetWidth(width)
    T.Surface(card, "raised", "edge")
    local head = CreateFrame("Button", nil, card)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(CARD_HEADER)
    local hover = T.Fill(head:CreateTexture(nil, "BACKGROUND"), "hover")
    hover:SetAllPoints()
    hover:Hide()
    local stripe = T.Fill(card:CreateTexture(nil, "ARTWORK"), "accent")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("BOTTOMLEFT")
    stripe:SetWidth(3)
    stripe:SetShown(newest)
    local icon = head:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("LEFT", 18, 0)
    icon:SetTexture(HC.spec.icon)
    local name = T.Font(UI.FontString(head, "GameFontHighlight", "text"), 15)
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, 4)
    name:SetText(HC.name .. " " .. tostring(W.Base(release.version)))
    local latest = UI.FontString(head, "GameFontNormalSmall", "accent")
    latest:SetPoint("LEFT", name, "RIGHT", 10, 0)
    latest:SetText(newest and "Latest" or "")
    local summary = UI.FontString(head, "GameFontHighlightSmall", "muted")
    summary:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -5)
    local when = longDate(release.date)
    summary:SetText(W.Summary(release) .. (when and ("     " .. when) or ""))
    local chevron = T.Icon(head:CreateTexture(nil, "ARTWORK"), "Chevron.tga", "muted")
    chevron:SetSize(14, 14)
    chevron:SetPoint("RIGHT", -18, 0)

    local body = CreateFrame("Frame", nil, card)
    body:SetPoint("TOPLEFT", 0, -CARD_HEADER)
    body:SetWidth(width)
    local rule = T.Fill(body:CreateTexture(nil, "ARTWORK"), "edge")
    rule:SetPoint("TOPLEFT", 1, 0)
    rule:SetPoint("TOPRIGHT", -1, 0)
    rule:SetHeight(1)
    local bottom = W.DrawItems(body, 16, -14, width - 32, release, {
        pageTitle = W.PageTitle,
        openPage = function(page) HC.Settings:Show(page) end,
    })
    local bodyHeight = -bottom + 6
    body:SetHeight(bodyHeight)

    W.expanded = W.expanded or {}
    local key = tostring(W.Base(release.version))
    if W.expanded[key] == nil then W.expanded[key] = newest end
    function card:Refresh()
        local open = W.expanded[key]
        body:SetShown(open)
        if chevron.SetRotation then chevron:SetRotation(open and math.pi or 0) end
        self:SetHeight(CARD_HEADER + (open and bodyHeight or 0))
    end
    head:SetScript("OnEnter", function() hover:Show(); chevron:SetVertexColor(T.Unpack("text")) end)
    head:SetScript("OnLeave", function() hover:Hide(); chevron:SetVertexColor(T.Unpack("muted")) end)
    head:SetScript("OnClick", function()
        W.expanded[key] = not W.expanded[key]
        relayout()
    end)
    card.head, card.body, card.release = head, body, release
    card:Refresh()
    return card
end

Pages.whatsNew.build = function(panel, top)
    local hint = UI.FontString(panel, "GameFontHighlightSmall", "muted")
    hint:SetPoint("TOPLEFT", UI.PAD + 2, top - 10)
    hint:SetText("Click a highlight to go straight to its setting.")
    local unread = UI.Switch(panel)
    unread:SetSize(220, 28)
    unread:SetPoint("TOPRIGHT", panel, "TOPLEFT", UI.PAD + UI.CONTENT_WIDTH + UI.CELL_INSET, top - 2)
    unread.Text:SetText("Mark unread releases")
    UI.AttachHint(unread, "Mark unread releases", "Show a yellow ! beside What's new until you've opened it since the last update.")
    unread:SetScript("OnClick", function(self)
        self:SetChecked(not self:GetChecked())
        HC.State().whatsNewDot = self:GetChecked()
        HC.Settings:RefreshBadges()
    end)
    UI.OnRefresh(panel, function() unread:SetChecked(HC.State().whatsNewDot ~= false) end)
    unread:SetChecked(HC.State().whatsNewDot ~= false)

    local cards, earlierLabel = {}, nil
    local function relayout()
        local y = top - 40
        for _, card in ipairs(cards) do
            if card.release.history and card == cards.firstHistory then
                y = y - 8
                earlierLabel:ClearAllPoints()
                earlierLabel:SetPoint("TOPLEFT", UI.PAD + 2, y)
                y = y - 22
            end
            card:Refresh()
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", UI.PAD, y)
            y = y - card:GetHeight() - 10
        end
        if panel.hcSetBottom then panel.hcSetBottom(y) end
        return y
    end
    for index, release in ipairs(HC.WhatsNew:Releases()) do
        local card = releaseCard(panel, release, index == 1, relayout)
        if release.history and not cards.firstHistory then
            cards.firstHistory = card
            earlierLabel = UI.FontString(panel, "GameFontNormalSmall", "section")
            earlierLabel:SetText("EARLIER RELEASES")
        end
        cards[#cards + 1] = card
    end
    Pages.whatsNewCards = cards
    return relayout()
end

-- The Theme page is withheld until Classic is ready; see Theme.lua.
Pages.reference = { commands, troubleshooting, about }

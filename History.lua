local _, ns = ...
local HC = ns.HammerCore
local UI, T = HC.UI, HC.Theme

-- History and Hall of Fame tabs. History lists every finished game on this
-- client: games you hosted in any channel, and Party games you joined. The
-- Hall of Fame is the saved player records, best first.

local MAX_LIST, DETAIL_ROWS, FAME_ROWS = 50, 10, 200
local MEDALS = { { 1, 0.82, 0.2 }, { 0.82, 0.84, 0.88 }, { 0.85, 0.55, 0.3 } }
ns.MEDALS = MEDALS

local function label(parent, font, role, width)
    local fs = UI.FontString(parent, font or "GameFontHighlight", role or "text")
    fs:SetJustifyH("LEFT")
    if width then fs:SetWidth(width) end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return fs
end

local function ordinal(n)
    local tail = n % 100
    if tail >= 11 and tail <= 13 then return n .. "th" end
    return n .. (({ "st", "nd", "rd" })[n % 10] or "th")
end
ns.Ordinal = ordinal

local function when(stamp)
    if type(stamp) == "number" and date then return date("%d %b %H:%M", stamp) end
    return "?"
end

local function me() return ns.Person and ns.Person("player") end

-- Shared ranks: equal totals share a place.
local function ranked(rows)
    local rank, previous = 0, nil
    for i, row in ipairs(rows) do
        if row.total ~= previous then rank, previous = i, row.total end
        row.rank = row.rank and row.rank > 0 and row.rank or rank
    end
    return rows
end

-- Hosted games and Party games, newest first, one entry per game.
function ns.HistoryEntries()
    local list, seen = {}, {}
    for _, game in ipairs(ns.db.games[ns.era] or {}) do
        if type(game) == "table" then
            if game.partyId then seen[game.partyId] = true end
            list[#list + 1] = { kind = "hosted", date = game.date, game = game }
        end
    end
    if ns.Party and ns.Party.SavedResults then
        for _, result in ipairs(ns.Party.SavedResults()) do
            if not seen[result.id] then list[#list + 1] = { kind = "party", date = result.date, result = result } end
        end
    end
    table.sort(list, function(a, b) return (tonumber(a.date) or 0) > (tonumber(b.date) or 0) end)
    while #list > MAX_LIST do table.remove(list) end
    return list
end

local function gameLength(rounds, perRound)
    rounds, perRound = tonumber(rounds), tonumber(perRound)
    if not rounds or not perRound or rounds < 1 or perRound < 1 then return 'Length not recorded' end
    if rounds == 1 then return tostring(perRound) .. (perRound == 1 and ' question' or ' questions') end
    return tostring(rounds) .. ' rounds of ' .. tostring(perRound)
end

-- What an entry shows: a title line, a detail line, and standings rows of
-- { name, total, bestStreak, mine }.
local function describe(entry)
    local self = me()
    local rows, out = {}, { rows = {} }
    if entry.kind == "hosted" then
        local g = entry.game
        for _, row in ipairs(type(g.rows) == "table" and g.rows or {}) do rows[#rows + 1] = { key = row.key, name = row.name, total = row.total or 0, bestStreak = row.bestStreak } end
        local channel = g.practice and "Practice" or (ns.Game.CHANNELS[g.channel] and ns.Game.CHANNELS[g.channel].label or "?")
        out.where = "Hosted · " .. channel
        out.length = gameLength(g.rounds, g.perRound)
        out.players = g.players or #rows
    else
        local r = entry.result
        for _, row in ipairs(r.rows or {}) do rows[#rows + 1] = { key = row.key, name = row.name, total = row.total or 0, bestStreak = row.bestStreak, rank = row.rank } end
        out.where = "Party · " .. tostring(r.host)
        out.length = gameLength(r.config and r.config.rounds, r.config and r.config.perRound)
        out.players = #rows
    end
    ranked(rows)
    for _, row in ipairs(rows) do
        row.mine = self and row.key == self.key
        if row.mine then out.place = row.rank end
        out.rows[#out.rows + 1] = row
    end
    local top = out.rows[1]
    out.winner = top and top.total > 0 and top.name or nil
    local winners = 0
    if top and top.total > 0 then
        for _, row in ipairs(out.rows) do if row.total == top.total then winners = winners + 1 end end
    end
    local outcome = winners > 1 and ('Shared win: ' .. winners .. ' players')
        or (out.winner and ('Winner: ' .. ns.DisplayName(out.winner)) or 'No correct answers')
    local names = {}
    if top and top.total > 0 then
        for _, row in ipairs(out.rows) do
            if row.total == top.total then names[#names + 1] = ns.DisplayName(row.name) end
            if row.mine then out.mine = 'You: ' .. ordinal(row.rank) .. ' of ' .. out.players .. ' · best streak ' .. (row.bestStreak or 0) end
        end
    else
        for _, row in ipairs(out.rows) do
            if row.mine then out.mine = 'You: ' .. ordinal(row.rank) .. ' of ' .. out.players .. ' · best streak ' .. (row.bestStreak or 0) end
        end
    end
    out.winnerLine = #names > 0 and ((#names > 1 and 'Shared win: ' or 'Winner: ') .. table.concat(names, ', ')) or 'No correct answers'
    out.title = when(entry.date) .. "   " .. out.where
    out.summary = (out.place and ("You: " .. ordinal(out.place)) or outcome)
        .. "  ·  " .. out.length
    return out
end

function ns.BuildHistory(host)
    local L = ns.HostLayout
    local view = CreateFrame("Frame", nil, host)
    view:SetAllPoints()
    local heading = label(view, "GameFontNormalLarge", "flavour")
    heading:SetPoint("TOPLEFT", 18, -64); heading:SetText("History")
    local sub = label(view, "GameFontHighlightSmall", "muted", L.width - 36)
    sub:SetPoint("TOPLEFT", 18, -88)
    sub:SetText("Games you hosted and Party games you joined, on this client.")
    view.empty = label(view, "GameFontHighlight", "muted", 420)
    view.empty:SetPoint("TOPLEFT", 18, -124)
    view.empty:SetText("No finished games yet. Play one and it shows up here.")

    -- The list takes a little over half the width; the detail card the rest.
    local listWidth = math.floor((L.width - 36) * 0.55)
    local detailX = 18 + listWidth + 20
    local scroll, list, setHeight = ns.ScrollArea(view, 18, -116, listWidth, L.height - 150)
    view.list = list
    view.entries = {}
    for i = 1, MAX_LIST do
        local b = UI.Button(list, listWidth, 40)
        b:SetPoint("TOPLEFT", 0, -(i - 1) * 44)
        b.Text:ClearAllPoints(); b.Text:SetPoint("TOPLEFT", 10, -7); b.Text:SetJustifyH("LEFT"); b.Text:SetWidth(listWidth - 20)
        b.sub = label(b, "GameFontHighlightSmall", "muted", listWidth - 20)
        b.sub:SetPoint("TOPLEFT", 10, -23)
        b:SetScript("OnClick", function(self) view.selected = self.index; view.Refresh() end)
        view.entries[i] = b
    end

    local detail = CreateFrame("Frame", nil, view, "BackdropTemplate")
    local detailWidth = L.width - detailX - 18
    local inner = detailWidth - 24
    detail:SetPoint("TOPLEFT", detailX, -116); detail:SetSize(detailWidth, L.height - 150)
    T.Surface(detail, "raised", "edge")
    detail.title = label(detail, "GameFontNormal", "flavour", inner)
    detail.title:SetPoint("TOPLEFT", 12, -12)
    detail.sub = label(detail, "GameFontHighlightSmall", "muted", inner)
    detail.sub:SetPoint("TOPLEFT", 12, -32)
    detail.winner = label(detail, "GameFontHighlight", "accent", inner)
    detail.winner:SetPoint("TOPLEFT", 12, -54)
    if detail.winner.SetWordWrap then detail.winner:SetWordWrap(true) end
    detail.mine = label(detail, "GameFontHighlightSmall", "text", inner)
    detail.mine:SetPoint("TOPLEFT", detail.winner, "BOTTOMLEFT", 0, -8)
    detail.rows = {}
    for i = 1, DETAIL_ROWS do
        local row = CreateFrame("Frame", nil, detail)
        row:SetSize(inner, 22); row:SetPoint("TOPLEFT", detail.mine, "BOTTOMLEFT", 0, -16 - (i - 1) * 24)
        row.name = label(row, "GameFontHighlight", "text", inner - 90); row.name:SetPoint("LEFT", 0, 0)
        row.score = label(row, "GameFontHighlightSmall", "muted", 80); row.score:SetPoint("RIGHT", 0, 0); row.score:SetJustifyH("RIGHT")
        detail.rows[i] = row
    end
    view.detail = detail

    view.Refresh = function()
        local entries = ns.HistoryEntries()
        view.empty:SetShown(#entries == 0)
        detail:SetShown(#entries > 0)
        if not view.selected or view.selected > #entries then view.selected = 1 end
        for i, b in ipairs(view.entries) do
            local entry = entries[i]
            b:SetShown(entry ~= nil)
            if entry then
                local d = describe(entry)
                b.index = i
                b:SetText(d.title); b.sub:SetText(d.summary)
                T.Border(b, i == view.selected and "selected" or "edge")
            end
        end
        setHeight(#entries * 44, true)
        local entry = entries[view.selected]
        if not entry then return end
        local d = describe(entry)
        detail.title:SetText(d.where)
        detail.sub:SetText(when(entry.date) .. "  ·  " .. d.length .. "  ·  " .. d.players .. (d.players == 1 and " player" or " players"))
        detail.winner:SetText((d.winner and "|TInterface\\Icons\\INV_Crown_01:18|t " or "") .. d.winnerLine)
        detail.mine:SetText(d.mine or "You didn't play in this game.")
        for i, row in ipairs(detail.rows) do
            local data = d.rows[i]
            row:SetShown(data ~= nil)
            if data then
                row.name:SetText(data.rank .. ".  " .. ns.DisplayName(data.name) .. (data.mine and " (you)" or ""))
                local medal = data.total > 0 and MEDALS[data.rank]
                if data.mine then T.Text(row.name, "selected")
                elseif medal then row.name:SetTextColor(medal[1], medal[2], medal[3]) else T.Text(row.name, "text") end
                row.score:SetText(data.total .. (data.total == 1 and " pt" or " pts"))
            end
        end
    end
    view:Hide()
    return view
end

function ns.BuildRecords(host)
    local L = ns.HostLayout
    local view = CreateFrame("Frame", nil, host)
    view:SetAllPoints()
    local heading = label(view, "GameFontNormalLarge", "flavour")
    heading:SetPoint("TOPLEFT", 18, -64); heading:SetText("Hall of Fame")
    view.sub = label(view, "GameFontHighlightSmall", "muted", L.width - 36)
    view.sub:SetPoint("TOPLEFT", 18, -88)
    local columns = { { "Player", 18, 320 }, { "Wins", 360, 70 }, { "Games", 450, 70 }, { "Correct", 540, 80 },
        { "Accuracy", 640, 90 }, { "Best streak", 750, 120 } }
    for _, c in ipairs(columns) do
        local h = label(view, "GameFontHighlightSmall", "muted", c[3])
        h:SetPoint("TOPLEFT", c[2], -270); h:SetText(c[1])
    end
    local _, list, setHeight = ns.ScrollArea(view, 0, -290, L.width - 30, L.height - 350)
    view.rows = {}
    local function row(i)
        if view.rows[i] then return view.rows[i] end
        local r = CreateFrame("Frame", nil, list)
        r:SetSize(L.width - 40, 22); r:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
        r.cells = {}
        for c, spec in ipairs(columns) do
            r.cells[c] = label(r, c == 1 and "GameFontHighlight" or "GameFontHighlightSmall", c == 1 and "text" or "muted", spec[3])
            r.cells[c]:SetPoint("LEFT", spec[2], 0)
        end
        view.rows[i] = r
        return r
    end
    view.empty = label(view, "GameFontHighlight", "muted", 500)
    view.empty:SetPoint("TOPLEFT", 18, -310)
    view.empty:SetText("No leaderboard yet. Host a game and everyone who plays lands here.")
    -- Quick play's personal bests, one hover each for where and when.
    view.bestsHeading = label(view, "GameFontNormal", "flavour", 300)
    view.bestsHeading:SetPoint("TOPLEFT", 18, -112)
    view.bestsHeading:SetText("Personal bests")
    view.bests = {}
    for index, mode in ipairs({ "streak", "lightning", "flight", "daily" }) do
        local cell = CreateFrame("Frame", nil, view)
        cell:SetSize(205, 88)
        cell:SetPoint("TOPLEFT", 18 + (index - 1) * 220, -138)
        T.Surface(cell, "raised", "edge")
        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetSize(24, 24); cell.icon:SetPoint("TOPLEFT", 10, -10)
        local icons = { streak = "Interface\\Icons\\Spell_Fire_Fire", lightning = "Interface\\Icons\\Spell_Nature_Lightning",
            flight = "Interface\\Icons\\Ability_Mount_Gryphon_01", daily = "Interface\\Icons\\INV_Misc_Note_06" }
        cell.icon:SetTexture(icons[mode])
        cell.text = label(cell, "GameFontHighlightSmall", "muted", 153)
        cell.text:SetPoint("TOPLEFT", 42, -10)
        cell.value = label(cell, "GameFontNormalHuge", "accent", 153)
        cell.value:SetPoint("TOPLEFT", 42, -29)
        cell.detail = label(cell, "GameFontHighlightSmall", "muted", 185)
        cell.detail:SetPoint("TOPLEFT", 10, -67)
        cell:EnableMouse(true)
        cell:SetScript("OnEnter", function(self)
            local best = ns.Quick and ns.Quick.BestLine(mode)
            if not (best and GameTooltip) then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(best.text, T.Unpack("accent"))
            for _, line in ipairs(best.detail or {}) do GameTooltip:AddLine(line, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function(self)
            if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
        cell.mode = mode
        view.bests[index] = cell
    end
    view.copy = UI.Button(view, 150, 30)
    view.copy:SetPoint("BOTTOMLEFT", 18, 18); view.copy:SetText("Copy as text")
    view.copy:SetScript("OnClick", ns.ShowRecords)
    view.leaderboardHeading = label(view, "GameFontNormal", "flavour", 300)
    view.leaderboardHeading:SetPoint("TOPLEFT", 18, -244)
    view.leaderboardHeading:SetText("Leaderboard")

    view.Refresh = function()
        local rows = {}
        for key, record in pairs(ns.db.records[ns.era]) do
            if type(record) == "table" then rows[#rows + 1] = { key = key, record = record } end
        end
        table.sort(rows, ns.RecordOrder)
        view.sub:SetText((ns.era == "classic" and "WoW Forever" or "Retail") .. " records kept on this account, from games hosted here.")
        view.empty:SetShown(#rows == 0)
        local self = me()
        local shown = math.min(#rows, FAME_ROWS)
        for i = 1, shown do
            local r, p = row(i), rows[i].record
            r:Show()
            local answered, correct = tonumber(p.answered) or 0, tonumber(p.correct) or 0
            local values = { i .. ".  " .. ns.DisplayName(p.name or rows[i].key), tostring(p.wins or 0), tostring(p.games or 0),
                tostring(correct), answered > 0 and (math.floor(correct / answered * 100 + 0.5) .. "%") or "-",
                tostring(p.bestStreak or 0) }
            for c, cell in ipairs(r.cells) do cell:SetText(values[c]) end
            local medal = (tonumber(p.wins) or 0) > 0 and MEDALS[i]
            if self and rows[i].key == self.key then T.Text(r.cells[1], "selected")
            elseif medal then r.cells[1]:SetTextColor(medal[1], medal[2], medal[3])
            else T.Text(r.cells[1], "text") end
        end
        for i = shown + 1, #view.rows do view.rows[i]:Hide() end
        setHeight(shown * 24, true)
        local names = { streak = "Best streak", lightning = "Best Lightning", flight = "Best flight", daily = "Daily streak" }
        for _, cell in ipairs(view.bests) do
            local best = ns.Quick and ns.Quick.BestLine(cell.mode)
            local bests = ns.Quick and ns.Quick.Bests()
            local record
            if ns.Quick and cell.mode == "lightning" then record = ns.Quick.LightningBest()
            elseif bests then record = bests[cell.mode] end
            local value = cell.mode == "daily" and ns.Daily and ns.Daily.Streak() or record and record.value
            cell.text:SetText(names[cell.mode])
            cell.value:SetText(value ~= nil and tostring(value) or "-")
            local detail = best and (best.short or best.detail and best.detail[1]) or "None yet"
            if cell.mode == "lightning" then detail = tostring(ns.db.qpLightning or 60) .. "s · " .. (detail or "") end
            if cell.mode == "daily" and ns.Daily then detail = "Best " .. ns.Daily.Best() end
            cell.detail:SetText(detail or "")
        end
    end
    view:Hide()
    return view
end

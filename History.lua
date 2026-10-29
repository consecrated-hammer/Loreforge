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
        out.length = tostring(g.rounds) .. " x " .. tostring(g.perRound)
        out.players = g.players or #rows
    else
        local r = entry.result
        for _, row in ipairs(r.rows or {}) do rows[#rows + 1] = { key = row.key, name = row.name, total = row.total or 0, bestStreak = row.bestStreak, rank = row.rank } end
        out.where = "Party · " .. tostring(r.host)
        out.length = r.config and (tostring(r.config.rounds) .. " x " .. tostring(r.config.perRound)) or ""
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
    out.title = when(entry.date) .. "   " .. out.where
    out.summary = (out.place and ("You: " .. ordinal(out.place)) or (out.winner and ("Winner: " .. out.winner) or "No correct answers"))
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

    local scroll, list, setHeight = ns.ScrollArea(view, 18, -116, 440, L.height - 150)
    view.list = list
    view.entries = {}
    for i = 1, MAX_LIST do
        local b = UI.Button(list, 440, 40)
        b:SetPoint("TOPLEFT", 0, -(i - 1) * 44)
        b.Text:ClearAllPoints(); b.Text:SetPoint("TOPLEFT", 10, -7); b.Text:SetJustifyH("LEFT"); b.Text:SetWidth(420)
        b.sub = label(b, "GameFontHighlightSmall", "muted", 420)
        b.sub:SetPoint("TOPLEFT", 10, -23)
        b:SetScript("OnClick", function(self) view.selected = self.index; view.Refresh() end)
        view.entries[i] = b
    end

    local detail = CreateFrame("Frame", nil, view, "BackdropTemplate")
    detail:SetPoint("TOPLEFT", 478, -116); detail:SetSize(L.width - 478 - 18, L.height - 150)
    T.Surface(detail, "raised", "edge")
    detail.title = label(detail, "GameFontNormal", "flavour", 260)
    detail.title:SetPoint("TOPLEFT", 12, -12)
    detail.sub = label(detail, "GameFontHighlightSmall", "muted", 260)
    detail.sub:SetPoint("TOPLEFT", 12, -32)
    detail.rows = {}
    for i = 1, DETAIL_ROWS do
        local row = CreateFrame("Frame", nil, detail)
        row:SetSize(260, 22); row:SetPoint("TOPLEFT", 12, -62 - (i - 1) * 24)
        row.name = label(row, "GameFontHighlight", "text", 180); row.name:SetPoint("LEFT", 0, 0)
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
        for i, row in ipairs(detail.rows) do
            local data = d.rows[i]
            row:SetShown(data ~= nil)
            if data then
                row.name:SetText(data.rank .. ".  " .. tostring(data.name) .. (data.mine and " (you)" or ""))
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
    local columns = { { "Player", 18, 250 }, { "Wins", 290, 60 }, { "Games", 360, 60 }, { "Correct", 430, 70 },
        { "Accuracy", 510, 80 }, { "Best streak", 600, 100 } }
    for _, c in ipairs(columns) do
        local h = label(view, "GameFontHighlightSmall", "muted", c[3])
        h:SetPoint("TOPLEFT", c[2], -116); h:SetText(c[1])
    end
    local _, list, setHeight = ns.ScrollArea(view, 0, -134, L.width - 30, L.height - 200)
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
    view.empty:SetPoint("TOPLEFT", 18, -150)
    view.empty:SetText("No records yet. Finish a game to start the Hall of Fame.")
    view.copy = UI.Button(view, 150, 30)
    view.copy:SetPoint("BOTTOMLEFT", 18, 18); view.copy:SetText("Copy as text")
    view.copy:SetScript("OnClick", ns.ShowRecords)
    view.clear = UI.Button(view, 150, 30, "danger")
    view.clear:SetPoint("BOTTOMRIGHT", -18, 18); view.clear:SetText("Clear records")
    view.clear:SetScript("OnClick", ns.ConfirmClearRecords)

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
            local values = { i .. ".  " .. tostring(p.name or rows[i].key), tostring(p.wins or 0), tostring(p.games or 0),
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
        view.clear:SetEnabled(#rows > 0 and not ns.game:Active())
    end
    view:Hide()
    return view
end

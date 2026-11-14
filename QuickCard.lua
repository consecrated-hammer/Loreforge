local _, ns = ...
local HC = ns.HammerCore
local UI, T = HC.UI, HC.Theme
local Quick = ns.Quick

-- The Quick play card, its slide-out Options tab and the takeoff prompt.
-- The game itself lives in QuickPlay.lua; this file only draws ns.Quick.state
-- and passes clicks back. The card has its own look settings (Artwork,
-- Animations, Card size), separate from the party window's.

local Card = {}
ns.QuickCard = Card

local ART, RIGHT_W, PAD = 250, 380, 16
local CONTENT = RIGHT_W - PAD * 2
local COL_W = math.floor((CONTENT - 8) / 2)
local OPTIONS_W = 236
local FADE = 0.35
local NO_TIMER = "These modes are always against the clock."

local function label(parent, font, role, width)
    local fs = UI.FontString(parent, font or "GameFontHighlight", role or "text")
    fs:SetJustifyH("LEFT")
    if width then fs:SetWidth(width) end
    return fs
end

local function artOn() return ns.db.qpArt ~= false end
local function animated() return ns.db.qpAnimations ~= false end

local function banterOn(s, bucket)
    local setting = ns.db.qpBanterEvery
    if s.mode == "lightning" or setting == 0 then return false end
    if bucket == "streak" or setting == 1 then return true end
    if s.banterReveal ~= s.answered then
        s.banterReveal = s.answered
        s.banterRandom = math.random(3) == 1
    end
    return s.banterRandom
end

local function feedbackParts(right, choice, answer)
    return right and "Correct!" or choice and "Not quite." or "Time's up.",
        (right and "" or "It was ") .. answer .. "."
end

local function stopEffects(f)
    if not f then return end
    ns.Flair.StopAll(f)
    if f.fading then
        f.art:SetTexture(f.artPath)
        f.art:SetAlpha(1)
        f.artNext:SetAlpha(0)
        f.fading = nil
    end
end

local function textHeight(fs, minimum)
    return math.max(minimum or 0, math.ceil(fs:GetStringHeight() or 0))
end

local function top(region, x, y)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", x, -y)
end

local function tooltip(owner, title, lines)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, T.Unpack("accent"))
    for _, line in ipairs(lines) do
        if line == "" then GameTooltip:AddLine(" ")
        elseif type(line) == "table" then GameTooltip:AddLine(line[1], line[2], line[3], line[4], true)
        else GameTooltip:AddLine(line, 1, 1, 1, true) end
    end
    GameTooltip:Show()
end

local function hideTooltip(owner)
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

local function hover(frame, fn)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self) fn(self) end)
    frame:SetScript("OnLeave", hideTooltip)
end

-- The tooltip for a mode: what it is, then its best.
local function modeTooltip(owner, mode)
    local spec = Quick.MODE[mode]
    local lines = { spec.tip }
    if mode == "flight" and not Quick.Flying() then lines[#lines + 1] = { spec.groundTip, 1, 0.35, 0.3 } end
    local best = Quick.BestLine(mode)
    if best then
        lines[#lines + 1] = ""
        lines[#lines + 1] = { best.text, T.Unpack("accent") }
        if mode == "flight" and best.short then lines[#lines + 1] = { best.short, 0.75, 0.75, 0.75 } end
    end
    tooltip(owner, spec.label, lines)
end
Card.ModeTooltip = modeTooltip

-- ── Card ───────────────────────────────────────────────────────────────────

local function savePosition(frame)
    ns.db.qpLeft, ns.db.qpTop = frame:GetLeft(), frame:GetTop()
    if Card.options then Card.PlaceOptions() end
end

local function place(frame)
    frame:ClearAllPoints()
    if type(ns.db.qpLeft) == "number" and type(ns.db.qpTop) == "number" then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ns.db.qpLeft, ns.db.qpTop)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -160)
    end
end

local function answerButton(parent, index)
    local b = ns.AnswerRow(parent, index, COL_W)
    b:SetHeight(46)
    b.Text:SetWidth(COL_W - 46)
    b.badge:Hide()
    b.lfResultInGutter = true
    b:SetScript("OnClick", function()
        if Card.Accepting() and animated() then ns.Flair.Pop(Card.frame, b) end
        Quick.Answer(index)
    end)
    return b
end

-- One frame watches combat, made with the first card or prompt.
local function watchCombat()
    if Card.events then return end
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function(_, event) Card.OnCombat(event) end)
    Card.events = events
end

local function create()
    if Card.frame then return Card.frame end
    watchCombat()
    local f = CreateFrame("Frame", "LoreforgeQuickCard", UIParent, "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    ns.WindowChrome(f, { title = "Loreforge", icon = ns.Flair.QUEST, close = function() Card.Hide() end,
        moved = savePosition })
    local inset, bar = f.inset or 1, ns.WINDOW_BAR
    f.top = inset + bar
    f.lfAnimations = function() return animated() and f:IsShown() end

    f.gear = CreateFrame("Button", nil, f.header)
    f.gear:SetSize(22, 22)
    f.gear:SetPoint("RIGHT", f.closeButton, "LEFT", -6, 0)
    f.gear.icon = f.gear:CreateTexture(nil, "ARTWORK")
    f.gear.icon:SetAllPoints()
    f.gear.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    f.gear:SetScript("OnClick", function() Card.ToggleOptions() end)
    hover(f.gear, function(self) tooltip(self, "Options", { "Mode, timer, look and flights." }) end)

    -- The painting, a second copy for cross-fades, and its caption band.
    f.art = f:CreateTexture(nil, "BORDER")
    f.art:SetSize(ART, ART)
    f.art:SetPoint("TOPLEFT", inset, -f.top)
    f.artNext = f:CreateTexture(nil, "BORDER", nil, 1)
    f.artNext:SetSize(ART, ART)
    f.artNext:SetPoint("TOPLEFT", inset, -f.top)
    f.artNext:SetAlpha(0)
    f.band = f:CreateTexture(nil, "ARTWORK")
    f.band:SetColorTexture(0, 0, 0, 0.62)
    f.band:SetPoint("BOTTOMLEFT", f.art, "BOTTOMLEFT")
    f.band:SetPoint("BOTTOMRIGHT", f.art, "BOTTOMRIGHT")
    f.band:SetHeight(58)
    f.bandEdge = T.Fill(f:CreateTexture(nil, "ARTWORK", nil, 1), "accent")
    f.bandEdge:SetHeight(1)
    f.bandEdge:SetPoint("BOTTOMLEFT", f.band, "TOPLEFT")
    f.bandEdge:SetPoint("BOTTOMRIGHT", f.band, "TOPRIGHT")
    f.bandEdge:SetAlpha(0.7)
    f.caption = label(f, "GameFontNormalLarge", "flavour", ART - 24)
    f.caption:SetPoint("BOTTOMLEFT", f.art, "BOTTOMLEFT", 12, 12)
    f.caption:SetJustifyH("LEFT")
    if f.caption.SetWordWrap then f.caption:SetWordWrap(true) end

    -- The question side.
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetSize(RIGHT_W, ART)
    f.heading = label(f.body, "GameFontNormal", "flavour", CONTENT)
    f.heading:SetJustifyH("CENTER")
    f.clock = label(f.body, "GameFontHighlight", "text", 200)
    f.clock:SetPoint("TOPLEFT", PAD, -12)
    f.streak = label(f.body, "GameFontHighlight", "muted", 140)
    f.streak:SetPoint("TOPRIGHT", -PAD, -12)
    f.streak:SetJustifyH("RIGHT")
    f.streakBadge = ns.Flair.StreakBadge(f, f.body)
    f.streakBadge:SetPoint("TOPRIGHT", -PAD, -8)
    f.question = T.Font(label(f.body, "GameFontHighlight", "text", CONTENT), 14)
    f.question:SetPoint("TOPLEFT", PAD, -36)
    if f.question.SetWordWrap then f.question:SetWordWrap(true) end
    f.answers = {}
    for index = 1, 4 do
        local b = answerButton(f.body, index)
        local column, row = (index - 1) % 2, math.floor((index - 1) / 2)
        b:SetPoint("TOPLEFT", PAD + column * (COL_W + 8), -96 - row * 52)
        f.answers[index] = b
    end
    -- Keep the full answer before its optional quip. Layout measures both;
    -- the text narrows only while the Next button shares the row.
    f.feedback = label(f.body, "GameFontHighlight", "text", CONTENT - 90)
    f.feedback:SetPoint("TOPLEFT", PAD, -198)
    if f.feedback.SetWordWrap then f.feedback:SetWordWrap(true) end
    f.feedbackProbe = label(f.body, "GameFontHighlight", "text", CONTENT - 90)
    if f.feedbackProbe.SetWordWrap then f.feedbackProbe:SetWordWrap(true) end
    f.feedbackProbe:Hide()
    f.timeoutProbe = label(f.body, "GameFontHighlight", "text", CONTENT - 90)
    if f.timeoutProbe.SetWordWrap then f.timeoutProbe:SetWordWrap(true) end
    f.timeoutProbe:Hide()
    f.quip = label(f.body, "GameFontHighlightSmall", "muted", CONTENT)
    if f.quip.SetWordWrap then f.quip:SetWordWrap(true) end
    f.next = UI.Button(f.body, 80, 22)
    f.next:SetPoint("TOPRIGHT", -PAD, -200)
    f.next:SetText("Next")
    f.next:SetScript("OnClick", function() Quick.Next() end)
    f.timer = CreateFrame("Frame", nil, f.body)
    f.timer:SetSize(CONTENT, 4)
    f.timer:SetPoint("TOPLEFT", PAD, -244)
    T.Fill(f.timer:CreateTexture(nil, "BACKGROUND"), "rail"):SetAllPoints()
    f.timer.fill = T.Fill(f.timer:CreateTexture(nil, "ARTWORK"), "selected")
    f.timer.fill:SetPoint("TOPLEFT"); f.timer.fill:SetPoint("BOTTOMLEFT")
    f.footer = label(f.body, "GameFontHighlightSmall", "muted", CONTENT)
    f.footer:SetPoint("TOPLEFT", PAD, -228)
    f.footerHover = CreateFrame("Frame", nil, f.body)
    f.footerHover:SetAllPoints(f.footer)
    hover(f.footerHover, function(self) Card.BestTooltip(self) end)

    -- Summary and countdown, over the question side.
    f.over = CreateFrame("Frame", nil, f.body)
    f.over:SetAllPoints()
    f.overTitle = label(f.over, "GameFontNormalHuge", "flavour", CONTENT)
    f.overTitle:SetPoint("TOP", 0, -40)
    f.overTitle:SetJustifyH("CENTER")
    f.overLines = label(f.over, "GameFontHighlightLarge", "text", CONTENT)
    f.overLines:SetPoint("TOP", f.overTitle, "BOTTOM", 0, -14)
    f.overLines:SetJustifyH("CENTER")
    if f.overLines.SetWordWrap then f.overLines:SetWordWrap(true) end
    f.overNote = label(f.over, "GameFontHighlightSmall", "muted", CONTENT)
    f.overNote:SetPoint("BOTTOM", 0, 64)
    f.overNote:SetJustifyH("CENTER")
    if f.overNote.SetWordWrap then f.overNote:SetWordWrap(true) end
    f.primary = UI.Button(f.over, 140, 30, "primary")
    f.primary:SetPoint("BOTTOM", -76, 22)
    f.secondary = UI.Button(f.over, 140, 30)
    f.secondary:SetPoint("BOTTOM", 76, 22)

    f:SetScript("OnUpdate", function(_, elapsed) Card.Update(elapsed) end)
    f:SetScript("OnHide", function()
        stopEffects(f)
        if Card.options then Card.options:Hide() end
        if Card.combatHidden then return end
        if Card.frame then Card.Dismiss() end
    end)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "LoreforgeQuickCard" end
    f:Hide()
    Card.frame = f
    Card.Layout()
    place(f)
    return f
end

-- Measure the actual text before placing the next region. The painting stays
-- square while longer questions grow only the reading side of the card.
function Card.Layout()
    local f = Card.frame
    if not f then return end
    local inset, art = f.inset or 1, artOn()
    if not animated() then stopEffects(f) end
    f:SetScale(Quick.SIZES[ns.db.qpSize] or 1)
    f.body:ClearAllPoints()
    f.body:SetPoint("TOPLEFT", inset + (art and ART or 0), -f.top)
    for _, region in ipairs({ f.art, f.artNext, f.band, f.bandEdge, f.caption }) do region:SetShown(art) end
    top(f.heading, PAD, 12)
    local clockY = art and 12 or (12 + textHeight(f.heading, 14) + 8)
    top(f.clock, PAD, clockY)
    f.streak:ClearAllPoints()
    f.streak:SetPoint("TOPRIGHT", -PAD, -clockY)
    f.streakBadge:ClearAllPoints()
    f.streakBadge:SetPoint("TOPRIGHT", -PAD, -(clockY - 4))
    local s = Quick.state
    local question = not s or s.phase == "question" or s.phase == "reveal"
    f.heading:SetShown(question and not art)
    local height
    if question then
        local timerY = clockY + math.max(textHeight(f.clock, 40), textHeight(f.streak, 40)) + 6
        top(f.timer, PAD, timerY)
        local questionY = timerY + 4 + 10
        top(f.question, PAD, questionY)
        local y = questionY + textHeight(f.question, 48) + 12
        for row = 0, 1 do
            local first, second = f.answers[row * 2 + 1], f.answers[row * 2 + 2]
            first:Fit(); second:Fit()
            local rowHeight = math.max(68, first:GetHeight(), second:GetHeight())
            first:SetHeight(rowHeight); second:SetHeight(rowHeight)
            top(first, PAD, y); top(second, PAD + COL_W + 8, y)
            y = y + rowHeight + 6
        end
        top(f.feedback, PAD, y + 4)
        f.next:ClearAllPoints()
        f.next:SetPoint("TOPRIGHT", -PAD, -(y + 4))
        y = y + 4 + math.max(32, textHeight(f.feedback, 32), textHeight(f.feedbackProbe, 32), textHeight(f.timeoutProbe, 32)) + 4
        top(f.quip, PAD, y)
        y = y + textHeight(f.quip, 32) + 10
        top(f.footer, PAD, y)
        y = y + textHeight(f.footer, 14) + 8
        height = math.max(ART, y + 10)
    else
        top(f.overTitle, PAD, 26)
        local y = 26 + textHeight(f.overTitle, 28) + 14
        top(f.overLines, PAD, y)
        y = y + textHeight(f.overLines, 24) + 16
        top(f.overNote, PAD, y)
        y = y + textHeight(f.overNote, 28) + 16
        local actionX = (RIGHT_W - f.primary:GetWidth() - f.secondary:GetWidth() - 12) / 2
        top(f.primary, actionX, y); top(f.secondary, actionX + f.primary:GetWidth() + 12, y)
        y = y + 30 + 14
        top(f.footer, PAD, y)
        height = math.max(ART, y + textHeight(f.footer, 14) + 14)
    end
    f.body:SetHeight(height)
    -- Keep the square painting centred beside the standard reading block.
    for _, painting in ipairs({ f.art, f.artNext }) do
        painting:ClearAllPoints()
        painting:SetPoint("TOPLEFT", inset, -(f.top + (height - ART) / 2))
    end
    f:SetSize(inset * 2 + (art and ART or 0) + RIGHT_W, f.top + height + inset)
    if Card.options then Card.PlaceOptions() end
end

local function setArt(f, key)
    local path = ns.Player.ArtPath({ art = key })
    if f.artPath == path then return end
    local first = f.artPath == nil
    f.artPath = path
    if first or not animated() or not f:IsShown() then
        f.art:SetTexture(path); f.art:SetAlpha(1); f.artNext:SetAlpha(0); f.fading = nil
        return
    end
    f.artNext:SetTexture(path)
    f.artNext:SetAlpha(0)
    f.fading = 0
end

-- The best line's tooltip: the best, then where and when.
function Card.BestTooltip(owner)
    local s = Quick.state
    local best = Quick.BestLine(s and s.mode or ns.db.qpMode)
    if not best then return end
    tooltip(owner, best.text, best.detail or {})
end

local function footerText(s)
    if s.mode == "daily" then return ns.Daily.FooterText() end
    local record = Quick.Today()
    local parts = { "Today " .. record.correct .. " / " .. record.answered }
    local best = Quick.BestLine(s.mode)
    if best and s.mode ~= "quick" then parts[#parts + 1] = best.text end
    if s.mode == "quick" then
        local streak = Quick.BestLine("streak")
        if streak then parts[#parts + 1] = streak.text end
    end
    return table.concat(parts, "  ·  ")
end

function Card.Render()
    local f = Card.frame
    if not f then return end
    local s = Quick.state
    if not s then return end
    local spec = Quick.MODE[s.mode]
    f.title:SetText("Loreforge · " .. spec.label)
    local q = s.question
    if q then
        setArt(f, q.category)
        f.caption:SetText(q.categoryLabel)
        f.heading:SetText("─  " .. q.categoryLabel .. "  ─")
    elseif not f.artPath then
        setArt(f, "mixed")
        f.caption:SetText("A bit of everything")
    end
    local question = s.phase == "question" or s.phase == "reveal"
    for _, region in ipairs({ f.question, f.feedback, f.quip, f.timer, f.clock, f.streak }) do region:SetShown(question) end
    if not question then f.streakBadge:Hide() end
    for _, b in ipairs(f.answers) do b:SetShown(question) end
    f.heading:SetShown(question and not artOn())
    local manualNext = s.phase == "reveal" and not s.revealUntil
    f.next:SetShown(manualNext)
    local roomForNext = manualNext or ((s.mode == "quick" or s.mode == "streak") and not ns.db.qpAutoNext)
    f.feedback:SetWidth(roomForNext and CONTENT - 90 or CONTENT)
    f.feedbackProbe:SetWidth(f.feedback:GetWidth())
    f.timeoutProbe:SetWidth(f.feedback:GetWidth())
    f.footer:SetShown(s.phase ~= "countdown")
    f.over:SetShown(s.phase == "over" or s.phase == "countdown")
    if question and q then
        f.question:SetText(q.text)
        local probeVerdict, probeAnswer = feedbackParts(false, true, q.choices[q.correct])
        f.feedbackProbe:SetText(probeVerdict .. " " .. probeAnswer)
        probeVerdict, probeAnswer = feedbackParts(false, nil, q.choices[q.correct])
        f.timeoutProbe:SetText(probeVerdict .. " " .. probeAnswer)
        for index, b in ipairs(f.answers) do
            b:SetText(q.choices[index])
            b:SetEnabled(s.phase == "question")
            if s.phase == "reveal" then
                if index == q.correct then b:Mark("correct")
                elseif index == s.choice then b:Mark("wrong")
                else b:Mark(nil) end
            else
                b:Mark(nil)
            end
            b.num:SetText(tostring(index))
        end
        if s.phase == "reveal" then
            local verdict, answer = feedbackParts(s.lastRight, s.choice, q.choices[q.correct])
            local bucket = ns.Flair.RevealBucket(s.choice, q.correct, s.streak)
            local quip = bucket and banterOn(s, bucket) and ns.Flair.Quip(bucket, tostring(s) .. ":" .. s.answered, s.streak) or ""
            local r, g, b = T.Unpack(s.lastRight and "accent" or "danger")
            local colour = string.format("|cff%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
            f.feedback:SetText(colour .. verdict .. "|r " .. answer)
            T.Text(f.feedback, "text")
            f.quip:SetText(quip)
            if f:IsShown() and animated() and f.animatedReveal ~= tostring(s) .. ":" .. s.answered then
                f.animatedReveal = tostring(s) .. ":" .. s.answered
                ns.Flair.Pop(f, f.answers[q.correct], true)
                if s.lastRight then ns.Flair.Sparkle(f, f.answers[q.correct])
                elseif s.choice then ns.Flair.Shake(f, f.answers[s.choice]) end
            end
        else
            f.quip:SetText("")
            f.feedback:SetText(s.landed and "Last question!" or (s.pendingMode and
                ("Next: " .. Quick.MODE[s.pendingMode].label) or ""))
            T.Text(f.feedback, "muted")
        end
        f.streakBadge:SetStreak(s.streak)
        f.streak:SetShown(not f.streakBadge:IsShown())
        f.streak:SetText(s.streak > 0 and ("Streak " .. s.streak) or "")
    end
    f.footer:SetText(footerText(s))
    if s.phase == "over" and s.summary then
        local summary = s.summary
        f.primary:SetWidth(summary.kind == "empty" and 180 or 140)
        f.secondary:SetWidth(summary.kind == "empty" and 100 or 140)
        f.overTitle:SetText(summary.title or "")
        T.Text(f.overTitle, summary.newBest and "accent" or "flavour")
        f.overLines:SetText(table.concat(summary.lines or {}, "\n"))
        f.overNote:SetText(summary.note or "")
        if summary.kind == "daily" then
            f.primary:SetText("Quick play")
            f.primary:SetScript("OnClick", function() Quick.Start("quick") end)
            f.secondary:SetText("Close")
            f.secondary:SetScript("OnClick", function() Card.Hide() end)
        elseif summary.kind == "touchdown" then
            f.primary:SetText("Keep going")
            f.primary:SetScript("OnClick", function() Quick.KeepGoing() end)
            f.secondary:SetText("Close")
            f.secondary:SetScript("OnClick", function() Card.Hide() end)
        elseif summary.kind == "empty" then
            f.primary:SetText("Categories & difficulty")
            f.primary:SetScript("OnClick", Card.OpenCategories)
            f.secondary:SetText("Close")
            f.secondary:SetScript("OnClick", Card.Hide)
        else
            f.primary:SetText("Play again")
            f.primary:SetScript("OnClick", function() Quick.Start(s.mode == "flight" and "quick" or s.mode) end)
            f.secondary:SetText("Quick play")
            f.secondary:SetScript("OnClick", function() Quick.Start("quick") end)
        end
        f.primary:Show(); f.secondary:Show()
        if f.celebratedSummary ~= summary and summary.newBest and f:IsShown() and animated()
            and ns.Flair.BounceIn and ns.Flair.BounceIn(f, f.overTitle) then
            f.celebratedSummary = summary
            ns.Flair.Sparkle(f, f.overLines)
        end
    elseif s.phase == "countdown" then
        f.overTitle:SetText(spec.label)
        f.overLines:SetText("")
        f.primary:SetText("Not now")
        f.primary:SetScript("OnClick", function() Card.Hide() end)
        f.primary:Show()
        f.secondary:Hide()
    end
    Card.Layout()
    Card.Update(0)
    if Card.options and Card.options:IsShown() then Card.RefreshOptions() end
end

local since = 0
function Card.Update(elapsed)
    local f = Card.frame
    if not f then return end
    if not animated() then stopEffects(f) end
    if f.fading then
        f.fading = f.fading + (elapsed or 0)
        local alpha = math.min(1, f.fading / FADE)
        f.artNext:SetAlpha(alpha)
        if alpha >= 1 then
            f.art:SetTexture(f.artPath); f.art:SetAlpha(1); f.artNext:SetAlpha(0); f.fading = nil
        end
    end
    since = since + (elapsed or 0)
    if elapsed and elapsed > 0 and since < 0.1 then return end
    since = 0
    Quick.Tick()
    local s = Quick.state
    if not s then return end
    if s.phase == "countdown" then
        local left = math.max(1, math.ceil((s.countdownUntil or 0) - (GetTime and GetTime() or 0)))
        f.overLines:SetText("Starting in " .. left .. "…")
    elseif s.phase == "over" and s.summary and s.summary.closeAt then
        local left = math.max(0, math.ceil(s.summary.closeAt - (GetTime and GetTime() or 0)))
        f.overNote:SetText("Closing in " .. left .. "…")
    elseif s.phase == "over" and s.summary and s.summary.kind == "daily" then
        f.overNote:SetText(ns.Daily.NextText())
    end
    f.clock:SetText(Quick.Clock())
    local fraction, left = Quick.TimerFraction()
    f.timer:SetShown(fraction ~= nil and (s.phase == "question" or s.phase == "reveal"))
    if fraction then
        f.timer.fill:SetWidth(math.max(1, CONTENT * fraction))
        ns.TimerColour(f.timer.fill, left or 0, s.mode == "flight" and 999 or s.mode == "lightning" and s.length or ns.db.qpSeconds)
    end
    ns.Flair.Pulse(f, f.timer.fill, f:IsShown() and animated() and s.phase == "question" and left ~= nil and left > 0 and left <= 5)
end

-- ── Showing and hiding ─────────────────────────────────────────────────────

function Card.IsShown() return Card.frame ~= nil and Card.frame:IsShown() end

function Card.Accepting()
    return Card.IsShown() and Quick.state ~= nil and Quick.state.phase == "question"
end

local function bringForward(f)
    -- The host and card share DIALOG strata. Match the joined-player window's
    -- relative level so opening from Play clears the host and its controls.
    if ns.hostFrame then f:SetFrameLevel(ns.hostFrame:GetFrameLevel() + 10) end
    f:Raise()
end

function Card.Show(mode, options)
    if InCombatLockdown and InCombatLockdown() then HC.Print("Quick play opens after combat."); return end
    local f = create()
    Card.HideLauncher()
    Card.HidePrompt(true)
    Card.HideDailyPrompt()
    Card.Layout()
    Quick.Start(mode or ns.db.qpMode, options)
    f:Show()
    Card.Render()
    bringForward(f)
end

-- Esc and the close button share the same dismissal path.
function Card.Dismiss()
    if Quick.Flying() then
        Quick.Pause()
        Card.ShowLauncher()
    else
        Quick.Close()
    end
end

function Card.Hide()
    if Card.frame and Card.frame:IsShown() then Card.frame:Hide()
    else Card.Dismiss() end
end

local function validLauncherPoint(point)
    return HC.ValidPoint(point) and math.abs(tonumber(point[3])) < math.huge
        and math.abs(tonumber(point[4])) < math.huge
end

local function placeLauncher(book)
    book:ClearAllPoints()
    local point = ns.db.qpFlightBookPoint
    if validLauncherPoint(point) then
        book:SetPoint(point[1], UIParent, point[2], tonumber(point[3]), tonumber(point[4]))
    else
        book:SetPoint("TOP", UIParent, "TOP", 0, -160)
    end
end

local function stopLauncherDrag(book)
    if not book.lfDragging then return end
    book:StopMovingOrSizing()
    book.lfDragging = nil
    book.lfDragged = true
    local point, relativeTo, relativePoint, x, y = book:GetPoint(1)
    if relativeTo ~= UIParent then
        point, relativePoint, x, y = "TOPLEFT", "BOTTOMLEFT", book:GetLeft(), book:GetTop()
    end
    local saved = { point, relativePoint, x, y }
    if validLauncherPoint(saved) then ns.db.qpFlightBookPoint = saved end
end

function Card.ResetLauncherPosition()
    if Card.launcher then stopLauncherDrag(Card.launcher) end
    ns.db.qpFlightBookPoint = nil
    if Card.launcher then placeLauncher(Card.launcher) end
end

function Card.HideLauncher()
    if Card.launcher then Card.launcher:Hide() end
end

function Card.ResumeQuiz()
    if not Quick.Flying() or (InCombatLockdown and InCombatLockdown()) then return end
    if not Quick.state then Card.Show("flight"); return end
    Card.HideLauncher()
    Quick.Resume()
    Card.Layout()
    Card.frame:Show()
    Card.Render()
    bringForward(Card.frame)
end

function Card.ShowLauncher()
    if not Quick.Flying() or Card.IsShown() then return end
    watchCombat()
    if not Card.launcher then
        local b = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
        b:SetSize(36, 36)
        placeLauncher(b)
        b:SetFrameStrata("DIALOG")
        b:SetMovable(true)
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnMouseDown", function(self) self.lfDragged = nil end)
        b:SetScript("OnDragStart", function(self)
            if InCombatLockdown and InCombatLockdown() then return end
            self.lfDragging = true
            self:StartMoving()
        end)
        b:SetScript("OnDragStop", stopLauncherDrag)
        b:SetScript("OnHide", stopLauncherDrag)
        b:SetScript("OnShow", function(self) self.lfDragged = nil end)
        b:SetClampedToScreen(true)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
        hover(b, function(self)
            tooltip(self, "Loreforge", { "Resume your quiz or start a new one.", "Drag to move." })
        end)
        b:SetScript("OnClick", function(self)
            if self.lfDragged or self.lfDragging then self.lfDragged = nil; return end
            HC.Menu:Open({
                { text = "Resume quiz", disabled = not Quick.state,
                    func = function() Card.ResumeQuiz() end },
                { text = "New quiz", func = function() Card.Show("flight") end },
            }, self, 160)
        end)
        Card.launcher = b
    end
    if not (InCombatLockdown and InCombatLockdown()) then
        if not Card.launcher:IsShown() and not Card.launcher.lfDragging then placeLauncher(Card.launcher) end
        Card.launcher:Show()
    end
end

function Card.Toggle()
    if Card.IsShown() then Card.Hide() else Card.Show() end
end

-- Combat hides the card and the prompt; both come back after.
function Card.OnCombat(event)
    if event == "PLAYER_REGEN_DISABLED" then
        Card.HideLauncher()
        if Card.IsShown() then
            Card.combatHidden = true
            Quick.Pause()
            Card.frame:Hide()
            if Card.options then Card.options:Hide() end
        end
        if Card.prompt and Card.prompt:IsShown() then Card.promptAfterCombat = true; Card.prompt:Hide() end
        if Card.dailyPrompt and Card.dailyPrompt:IsShown() then Card.dailyAfterCombat = true; Card.dailyPrompt:Hide() end
    elseif Card.combatHidden then
        Card.combatHidden = nil
        if Quick.state then
            Quick.Resume()
            Card.frame:Show()
            Card.Render()
            bringForward(Card.frame)
        end
    end
    if event == "PLAYER_REGEN_ENABLED" and Card.launcher and Quick.Flying() and not Card.IsShown() then
        Card.ShowLauncher()
    end
    if event == "PLAYER_REGEN_ENABLED" and Card.promptAfterCombat then
        Card.promptAfterCombat = nil
        if Quick.Flying() and not Card.IsShown() then Card.Prompt() end
    end
    if event == "PLAYER_REGEN_ENABLED" and Card.dailyAfterCombat then
        Card.dailyAfterCombat = nil
        if ns.Daily.CanOffer(nil, true) then Card.DailyPrompt(ns.Daily.Today()) end
    end
end

-- ── Options tab ────────────────────────────────────────────────────────────

local function check(parent, text, y, get, set)
    local b = UI.Switch(parent)
    b:SetSize(OPTIONS_W - 28, 24)
    b:SetPoint("TOPLEFT", 14, y)
    b.Text:SetText(text)
    b:SetScript("OnClick", function(self)
        self:SetChecked(not self:GetChecked())
        set(self:GetChecked())
        Card.Layout()
        Card.Render()
    end)
    b.Refresh = function(self) self:SetChecked(get()) end
    return b
end

local function section(parent, text, y)
    local fs = label(parent, "GameFontNormalSmall", "accent", OPTIONS_W - 28)
    fs:SetPoint("TOPLEFT", 14, y)
    fs:SetText(text)
    return fs
end

local function modeRow(parent, mode, y)
    local spec = Quick.MODE[mode]
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(OPTIONS_W - 20, 34)
    row:SetPoint("TOPLEFT", 10, y)
    row.dot = T.Fill(row:CreateTexture(nil, "ARTWORK"), "selected")
    row.dot:SetSize(8, 8)
    row.dot:SetPoint("TOPLEFT", 6, -7)
    row.ring = T.Fill(row:CreateTexture(nil, "BORDER"), "edge")
    row.ring:SetSize(12, 12)
    row.ring:SetPoint("CENTER", row.dot, "CENTER")
    row.title = label(row, "GameFontHighlight", "text", OPTIONS_W - 50)
    row.title:SetPoint("TOPLEFT", 22, -3)
    row.title:SetText(spec.label)
    row.line = label(row, "GameFontHighlightSmall", "muted", OPTIONS_W - 50)
    row.line:SetPoint("TOPLEFT", 22, -18)
    row:SetScript("OnClick", function() if Quick.SetMode(mode) then Card.RefreshOptions() end end)
    row:SetScript("OnEnter", function(self) modeTooltip(self, mode) end)
    row:SetScript("OnLeave", hideTooltip)
    row.Refresh = function(self)
        local s = Quick.state
        local current = (s and (s.pendingMode or s.mode)) or ns.db.qpMode
        local grounded = mode == "flight" and not Quick.Flying()
        self.dot:SetShown(current == mode)
        self.line:SetText(grounded and spec.ground or spec.line)
        self:SetAlpha(grounded and 0.45 or 1)
        self:SetEnabled(not grounded)
    end
    return row
end

-- Both the card and settings page use the same existing timer-switch rules.
function Card.SetRelaxed(value)
    ns.db.qpRelaxed = value == true
    local s = Quick.state
    if s and s.phase == "question" and Quick.Timed(s.mode) == false then s.questionDeadline = nil end
    Card.Render()
    Card.RefreshOptions()
end

-- The timer: [ Against the clock | Relaxed ], the current one lit.
local function timerSwitch(parent, y)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(OPTIONS_W - 28, 24)
    holder:SetPoint("TOPLEFT", 14, y)
    local half = math.floor((OPTIONS_W - 28) / 2)
    local function part(text, relaxed, x)
        local b = UI.Button(holder, half, 24)
        b:SetPoint("LEFT", x, 0)
        b:SetText(text)
        b:SetScript("OnClick", function()
            Card.SetRelaxed(relaxed)
        end)
        b:HookScript("OnLeave", function() holder.Refresh() end)
        b.relaxed = relaxed
        return b
    end
    holder.clock = part("Against the clock", false, 0)
    holder.relaxed = part("Relaxed", true, half)
    hover(holder, function(self)
        local s = Quick.state
        local mode = s and s.mode or ns.db.qpMode
        if mode == "lightning" or mode == "flight" then tooltip(self, "Timer", { NO_TIMER }) end
    end)
    holder.Refresh = function()
        local s = Quick.state
        local mode = s and s.mode or ns.db.qpMode
        local fixed = mode == "lightning" or mode == "flight"
        for _, b in ipairs({ holder.clock, holder.relaxed }) do
            local lit = fixed and not b.relaxed or not fixed and (b.relaxed == (ns.db.qpRelaxed == true))
            b:SetEnabled(not fixed)
            b:SetAlpha(fixed and 0.5 or 1)
            if b.SetBackdropColor then
                b:SetBackdropColor(T.Unpack(lit and "menuActive" or "raised"))
                T.Border(b, lit and "accent" or "edge")
            end
            T.Text(b.Text, lit and "text" or "muted")
        end
    end
    for _, b in ipairs({ holder.clock, holder.relaxed }) do
        b:HookScript("OnEnter", function(self)
            local s = Quick.state
            local mode = s and s.mode or ns.db.qpMode
            if mode == "lightning" or mode == "flight" then tooltip(self, "Timer", { NO_TIMER }) end
        end)
    end
    return holder
end

local function menuButton(parent, y, text, items)
    local b = UI.SelectButton(parent, OPTIONS_W - 28, 24)
    b:SetPoint("TOPLEFT", 14, y)
    b:SetScript("OnClick", function(self) HC.Menu:Open(items(), self, OPTIONS_W - 28) end)
    b.Refresh = function(self) self:SetText(text()) end
    return b
end

function Card.PlaceOptions()
    local o, f = Card.options, Card.frame
    o:ClearAllPoints()
    local right = f.GetRight and f:GetRight()
    local screenWidth = UIParent.GetWidth and UIParent:GetWidth() or 0
    local screenScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local frameScale = f.GetEffectiveScale and f:GetEffectiveScale() or 1
    o:SetScale(1)
    local optionsScale = o.GetEffectiveScale and o:GetEffectiveScale() or frameScale
    local fitsRight = not right or screenWidth <= 0 or right * frameScale + OPTIONS_W * optionsScale <= screenWidth * screenScale
    if fitsRight then o:SetPoint("TOPLEFT", f, "TOPRIGHT", -1, 0)
    else o:SetPoint("TOPRIGHT", f, "TOPLEFT", 1, 0) end
    o:SetScale(1)
end

local function buildOptions()
    if Card.options then return Card.options end
    local f = create()
    local o = CreateFrame("Frame", "LoreforgeQuickOptions", f, "BackdropTemplate")
    o:SetSize(OPTIONS_W, 470)
    T.Surface(o, "outer", "edge")
    local body = o:CreateTexture(nil, "BACKGROUND")
    body:SetPoint("TOPLEFT", 1, -1); body:SetPoint("BOTTOMRIGHT", -1, 1)
    body:SetColorTexture(T.Unpack("content"))
    o.controls = {}
    local y = -12
    section(o, "Mode", y); y = y - 18
    for _, spec in ipairs(Quick.MODES) do
        o.controls[#o.controls + 1] = modeRow(o, spec.key, y)
        y = y - 36
    end
    y = y - 6
    section(o, "Timer", y); y = y - 18
    o.timer = timerSwitch(o, y); y = y - 34
    o.controls[#o.controls + 1] = o.timer
    section(o, "Card", y); y = y - 20
    o.controls[#o.controls + 1] = check(o, "Artwork", y, function() return artOn() end,
        function(value) ns.db.qpArt = value end); y = y - 24
    o.controls[#o.controls + 1] = check(o, "Animations", y, function() return animated() end,
        function(value) ns.db.qpAnimations = value end); y = y - 26
    o.controls[#o.controls + 1] = menuButton(o, y, function()
        local names = { SMALL = "Small", MEDIUM = "Medium", LARGE = "Large" }
        return "Card size: " .. names[ns.db.qpSize]
    end, function()
        local items = {}
        for _, size in ipairs({ { "SMALL", "Small" }, { "MEDIUM", "Medium" }, { "LARGE", "Large" } }) do
            items[#items + 1] = { text = size[2], checked = ns.db.qpSize == size[1], func = function()
                ns.db.qpSize = size[1]; Card.Layout(); Card.RefreshOptions()
            end }
        end
        return items
    end); y = y - 36
    section(o, "Flights", y); y = y - 20
    o.controls[#o.controls + 1] = menuButton(o, y, function()
        return "On flights: " .. Quick.ON_FLIGHTS_LABELS[ns.db.qpOnFlights]
    end, function()
        local items = {}
        for _, value in ipairs(Quick.ON_FLIGHTS) do
            items[#items + 1] = { text = Quick.ON_FLIGHTS_LABELS[value], checked = ns.db.qpOnFlights == value,
                func = function() ns.db.qpOnFlights = value; Card.RefreshOptions() end }
        end
        return items
    end); y = y - 30
    o.controls[#o.controls + 1] = check(o, "Close on landing", y, function() return ns.db.qpCloseOnLanding ~= false end,
        function(value) ns.db.qpCloseOnLanding = value end); y = y - 30
    o.link = UI.Link(o, "Categories & difficulty ›", function() Card.OpenCategories() end)
    o.link:SetPoint("TOPLEFT", 14, y)
    y = y - 26
    o.moreSettings = UI.Link(o, "More settings", function()
        o:Hide()
        HC.Settings:Show("Quick play", "Card")
    end)
    o.moreSettings:SetPoint("TOPLEFT", 14, y)
    y = y - 26
    o:SetHeight(-y + 6)
    o:Hide()
    Card.options = o
    Card.PlaceOptions()
    return o
end

function Card.RefreshOptions()
    local o = Card.options
    if not o then return end
    for _, control in ipairs(o.controls) do control:Refresh() end
end

function Card.ToggleOptions()
    local o = buildOptions()
    o:SetShown(not o:IsShown())
    if o:IsShown() then Card.PlaceOptions(); Card.RefreshOptions() end
end

function Card.OpenCategories()
    if ns.OpenHost then ns.OpenHost("play") end
    local setup = ns.hostFrame and ns.hostFrame.setup
    if setup and setup.SelectTab then setup.SelectTab("categories") end
end

-- ── Minimap menu ───────────────────────────────────────────────────────────
-- Loreforge's part of the minimap button's right-click menu. HammerCore puts
-- "Loreforge settings" and a line above it: Hall of Fame and the daily, a
-- line, then the Quick play modes.

function Card.DailyItem()
    if not (ns.Daily and ns.Daily.Enabled()) then return nil end
    local done = ns.Daily.Done()
    local s = Card.IsShown() and Quick.state
    return { text = done and "Daily question (done)" or "Daily question",
        checked = s and s.mode == "daily" or nil, func = function() Card.Show("daily") end }
end

function Card.MenuItems()
    local items = { { text = "Hall of Fame", func = function() ns.OpenHost("records") end } }
    local daily = Card.DailyItem()
    if daily then items[#items + 1] = daily end
    items[#items + 1] = { separator = true }
    local s = Card.IsShown() and Quick.state
    for _, spec in ipairs(Quick.MODES) do
        local mode = spec.key
        local grounded = mode == "flight" and not Quick.Flying()
        items[#items + 1] = { text = grounded and (spec.label .. " (on flights)") or spec.label,
            checked = s and (s.pendingMode or s.mode) == mode or nil, disabled = grounded or nil,
            func = function()
                if Card.IsShown() then Quick.SetMode(mode) else Card.Show(mode) end
            end }
    end
    return items
end

-- The whole minimap menu, HammerCore's items included.
function Card.Menu()
    if HC.Minimap and HC.Minimap.OpenMenu then return HC.Minimap:OpenMenu() end
    HC.Menu:Open(Card.MenuItems())
end

-- ── Takeoff prompt ─────────────────────────────────────────────────────────

local PROMPT_W = 420

local function promptButton(parent, mode, x)
    local spec = Quick.MODE[mode]
    local b = UI.Button(parent, 180, 46, mode == "quick" and "primary" or nil)
    b:SetPoint("TOPLEFT", x, -96)
    b.Text:ClearAllPoints()
    b.Text:SetPoint("TOP", 0, -8)
    b:SetText(spec.label)
    b.line = label(b, "GameFontHighlightSmall", "muted", 170)
    b.line:SetPoint("TOP", b.Text, "BOTTOM", 0, -3)
    b.line:SetJustifyH("CENTER")
    b.line:SetText(spec.line)
    b:SetScript("OnClick", function() Card.Show(mode) end)
    b:HookScript("OnEnter", function(self) modeTooltip(self, mode) end)
    b:HookScript("OnLeave", hideTooltip)
    return b
end

local function createPrompt()
    if Card.prompt then return Card.prompt end
    watchCombat()
    local p = CreateFrame("Frame", "LoreforgeQuickPrompt", UIParent, "BackdropTemplate")
    p:SetFrameStrata("DIALOG")
    p:SetClampedToScreen(true)
    p:SetMovable(true)
    p:EnableMouse(true)
    p:SetSize(PROMPT_W, 230)
    ns.WindowChrome(p, { title = "Loreforge", icon = ns.Flair.QUEST, close = function() Card.HidePrompt() end })
    p.line = label(p, "GameFontHighlightLarge", "text", PROMPT_W - 40)
    p.line:SetPoint("TOPLEFT", 20, -54)
    if p.line.SetWordWrap then p.line:SetWordWrap(true) end
    p.quick = promptButton(p, "quick", 20)
    p.flight = promptButton(p, "flight", PROMPT_W - 200)
    p.dontOffer = UI.CheckButton(p)
    p.dontOffer:SetPoint("TOPLEFT", 22, -158)
    p.dontOffer.Text:SetText("Don't offer on flights")
    p.always = UI.CheckButton(p)
    p.always:SetPoint("TOPLEFT", 22, -184)
    p.always.Text:SetText("Always start Flight challenge")
    local function refresh()
        p.dontOffer:SetChecked(ns.db.qpOnFlights == "NONE")
        p.always:SetChecked(ns.db.qpOnFlights == "START")
    end
    p.dontOffer:SetScript("OnClick", function(self)
        ns.db.qpOnFlights = self:GetChecked() and "OFFER" or "NONE"
        refresh()
    end)
    p.always:SetScript("OnClick", function(self)
        ns.db.qpOnFlights = self:GetChecked() and "OFFER" or "START"
        refresh()
    end)
    p.decline = UI.Button(p, 100, 24)
    p.decline:SetPoint("BOTTOMRIGHT", -20, 14)
    p.decline:SetText("Not now")
    p.decline:SetScript("OnClick", function() Card.HidePrompt() end)
    p:SetHeight(258)
    p.Refresh = refresh
    p:SetPoint("TOP", UIParent, "TOP", 0, -180)
    p:Hide()
    Card.prompt = p
    return p
end

function Card.Prompt()
    if InCombatLockdown and InCombatLockdown() then Card.promptAfterCombat = true; return end
    local p = createPrompt()
    p:SetScale(Quick.SIZES[ns.db.qpSize] or 1)
    p.line:SetText(Quick.PromptLine())
    p.Refresh()
    p:Show()
end

function Card.HidePrompt(silent)
    Card.promptAfterCombat = nil
    if Card.prompt then Card.prompt:Hide() end
    if not silent then Card.ShowLauncher() end
end

-- ── Daily question offer ───────────────────────────────────────────────────
-- Once a day at login (Daily.TryOffer decides when), in the takeoff prompt's
-- style: one button to play, one to say not today.

local function createDailyPrompt()
    if Card.dailyPrompt then return Card.dailyPrompt end
    watchCombat()
    local p = CreateFrame("Frame", "LoreforgeDailyPrompt", UIParent, "BackdropTemplate")
    p:SetFrameStrata("DIALOG")
    p:SetClampedToScreen(true)
    p:SetMovable(true)
    p:EnableMouse(true)
    p:SetSize(PROMPT_W, 210)
    ns.WindowChrome(p, { title = "Loreforge", icon = ns.Flair.QUEST, close = function() Card.HideDailyPrompt() end })
    p.line = label(p, "GameFontHighlightLarge", "text", PROMPT_W - 40)
    p.line:SetPoint("TOPLEFT", 20, -54)
    if p.line.SetWordWrap then p.line:SetWordWrap(true) end
    p.streak = label(p, "GameFontHighlightSmall", "muted", PROMPT_W - 40)
    p.streak:SetPoint("TOPLEFT", 20, -80)
    local spec = Quick.MODE.daily
    p.play = UI.Button(p, 180, 46, "primary")
    p.play:SetPoint("TOPLEFT", 20, -104)
    p.play.Text:ClearAllPoints()
    p.play.Text:SetPoint("TOP", 0, -8)
    p.play:SetText(spec.label)
    p.play.line = label(p.play, "GameFontHighlightSmall", "muted", 170)
    p.play.line:SetPoint("TOP", p.play.Text, "BOTTOM", 0, -3)
    p.play.line:SetJustifyH("CENTER")
    p.play.line:SetText(spec.line)
    p.play:SetScript("OnClick", function() Card.Show("daily") end)
    p.later = UI.Button(p, 180, 46)
    p.later:SetPoint("TOPLEFT", PROMPT_W - 200, -104)
    p.later:SetText("Not today")
    p.later:SetScript("OnClick", function() Card.HideDailyPrompt() end)
    p.dontOffer = UI.CheckButton(p)
    p.dontOffer:SetPoint("TOPLEFT", 22, -166)
    p.dontOffer.Text:SetText("Don't offer at login")
    p.dontOffer:SetScript("OnClick", function(self)
        -- Clicking flips it: ticked was "don't offer", so offering comes back.
        ns.db.dailyOffer = self:GetChecked() and true or false
        self:SetChecked(ns.db.dailyOffer == false)
    end)
    p:SetPoint("TOP", UIParent, "TOP", 0, -180)
    p:Hide()
    Card.dailyPrompt = p
    return p
end

function Card.DailyPrompt(today)
    if InCombatLockdown and InCombatLockdown() then Card.dailyAfterCombat = true end
    local p = createDailyPrompt()
    today = today or ns.Daily.Today()
    p:SetScale(Quick.SIZES[ns.db.qpSize] or 1)
    p.title:SetText("Loreforge · " .. ns.Daily.Label(today.number))
    local streak = ns.Daily.Streak(today)
    p.line:SetText(streak > 0 and "Today's question is ready. Keep your streak going?"
        or "Today's question is ready. Fancy it?")
    p.streak:SetText(ns.Daily.FooterText(today))
    -- Font wrapping varies by client. Place the rest of the offer below
    -- the measured text instead of reserving a fixed one-line slot.
    local y = 54 + textHeight(p.line, 20) + 8
    top(p.streak, 20, y)
    y = y + textHeight(p.streak, 14) + 16
    top(p.play, 20, y)
    top(p.later, PROMPT_W - 200, y)
    y = y + 46 + 16
    top(p.dontOffer, 22, y)
    p:SetHeight(y + math.max(20, p.dontOffer:GetHeight() or 0) + 18)
    p.dontOffer:SetChecked(ns.db.dailyOffer == false)
    if Card.dailyAfterCombat then return end
    ns.Daily.State().offered = today.number
    p:Show()
end

function Card.HideDailyPrompt()
    Card.dailyAfterCombat = nil
    if Card.dailyPrompt then Card.dailyPrompt:Hide() end
end

local addonName, ns = ...
local HC = ns.HammerCore
local T, UI = HC.Theme, HC.UI

-- A five-question lore quiz, opened from the quest icon on About or with
-- /<cmd> quiz.  Questions come from HC.QUIZ, filtered to this client's era
-- and the character's class and race.  The per-question timer is HammerCore's
-- to own: 8 seconds, changed only by the hidden /<cmd> quiz timer command.

local Quiz = { LENGTH = 5, REVEAL = 1.4, DEFAULT_SECONDS = 8 }
HC.Quiz = Quiz

Quiz.Prompts = {
    "Could you be Khadgar’s next assistant?",
    "Can you settle an argument in the Archivist’s library?",
    "Do you remember more than quest objectives?",
    "Which tavern tale did you dismiss too quickly?",
    "Has a bronze dragon already asked you this?",
    "Can you find the missing Kirin Tor footnote?",
    "Is one of these answers secretly a murloc?",
    "Will your innkeeper be impressed?",
    "How dusty is your adventurer’s handbook?",
    "Can you help a wandering scholar?",
    "Are the dragons testing a future historian?",
    "Why is there a question mark over your head?",
    "Will you lead the next campfire lore debate?",
    "Can you prove you read the dialogue?",
    "Should a goblin bet on your answer?",
    "Why is the library suddenly so quiet?",
    "How well do you know your favourite zone?",
    "Can you decipher this Titan tablet?",
    "Will this knowledge help in a raid?",
    "Are you ready for a little Azeroth trivia?",
}

local VERDICTS = {
    [0] = "Have you considered reading the quest text?",
    [1] = "A fresh recruit. Everyone starts somewhere.",
    [2] = "Promising. The librarians are cautiously optimistic.",
    [3] = "Well travelled. Your hearthstone has seen things.",
    [4] = "A seasoned adventurer. Bards may yet sing of you.",
    [5] = "Keeper of the Archives. Khadgar would approve.",
}

local VERDICT_CHOICES = {
    [0] = { VERDICTS[0], "The quest giver would like a word.",
        "You have discovered an entirely new version of history.", "Even the murloc looks concerned.",
        "The loading screen tips were trying to help.", "Your lore book appears to be upside down." },
    [1] = { VERDICTS[1], "You recognised some of the names. That counts for something.",
        "The innkeeper recommends fewer skips and more stories.", "Your journal has room for a few more notes.",
        "One foot in the library. The other is still at the auction house.", "A promising start for someone who clicked Accept immediately." },
    [2] = { VERDICTS[2], "You know enough to be dangerous at a tavern quiz.",
        "Somewhere, a quest giver feels partially heard.", "A few missing pages, but the binding is sound.",
        "The bronze dragons have requested a small correction.", "You remembered the boss. The backstory is a work in progress." },
    [3] = { VERDICTS[3], "You read the quest text. Most of it.",
        "The campfire historians have saved you a seat.", "A respectable showing. The archivist has stopped sighing.",
        "You could lead the tour, with occasional help from a map.", "Your lore book has actual bookmarks." },
    [4] = { VERDICTS[4], "The archivist would trust you with the good quill.",
        "One footnote away from showing off.", "You have clearly been listening between pulls.",
        "The tavern is checking whether you brought your own questions.", "Brann would like to compare notebooks." },
    [5] = { VERDICTS[5], "You may now correct the tour guide.",
        "The quest text has considered reading you.", "The bronze dragons are checking their notes.",
        "Please leave some trivia for the rest of the tavern.", "A perfect score. Your next quest is to touch grass in Elwynn." },
}

-- Choose once at completion so the window, local text and secure share agree.
-- Avoid the last result for this score during the current login session.
function Quiz:ChooseVerdict(score, total, random)
    local bucket = math.max(0, math.min(5, math.floor(score / math.max(1, total) * 5 + 0.5)))
    local choices = VERDICT_CHOICES[bucket]
    self.lastVerdicts = self.lastVerdicts or {}
    local previous = self.lastVerdicts[bucket]
    local index = (random or math.random)(#choices - (previous and 1 or 0))
    if previous and index >= previous then index = index + 1 end
    self.lastVerdicts[bucket] = index
    return choices[index]
end

function Quiz.VerdictChoices() return VERDICT_CHOICES end

-- Forever is the Classic world; everything else is Retail.  An addon can
-- override this with spec.era.
function Quiz.Era()
    if HC.spec.era then return HC.spec.era() end
    local label = HC.spec.clientLabel and HC.spec.clientLabel() or ""
    return tostring(label):find("Forever", 1, true) and "classic" or "retail"
end

function Quiz.Seconds()
    local state = HC.State()
    local seconds = state and state.quizSeconds
    if seconds == false then return nil end
    return tonumber(seconds) or Quiz.DEFAULT_SECONDS
end

function Quiz.Eligible(entry, era, class, race)
    local entryEra = entry.era or "both"
    if entryEra ~= "both" and entryEra ~= era then return false end
    if entry.class and entry.class ~= class then return false end
    if entry.race and entry.race ~= race then return false end
    return true
end

-- Draws a run: distinct questions, each with its choices shuffled.
function Quiz.Draw(random)
    random = random or math.random
    local era = Quiz.Era()
    local class, race
    if UnitClass then local _; _, class = UnitClass("player") end
    if UnitRace then local _; _, race = UnitRace("player") end
    local pool = {}
    for _, entry in ipairs(HC.QUIZ or {}) do
        if Quiz.Eligible(entry, era, class, race) then pool[#pool + 1] = entry end
    end
    local run = {}
    for _ = 1, math.min(Quiz.LENGTH, #pool) do
        local entry = table.remove(pool, random(#pool))
        local choices = { entry[2], entry[3], entry[4], entry[5] }
        for i = #choices, 2, -1 do
            local j = random(i)
            choices[i], choices[j] = choices[j], choices[i]
        end
        local correct
        for index, choice in ipairs(choices) do
            if choice == entry[2] then correct = index end
        end
        run[#run + 1] = { question = entry[1], choices = choices, correct = correct }
    end
    return run
end

-- ── Window ─────────────────────────────────────────────────────────────────

local WIDTH = 460
local DESTINATIONS = { "TEXT", "SAY", "PARTY" }
local DESTINATION_LABELS = { TEXT = "Text", SAY = "Say", PARTY = "Party" }

function Quiz:ResultText()
    return "Lore quiz: " .. self.score .. "/" .. #self.run .. ". " .. self.verdict
end

-- Say and Party are secure macro buttons.  Addon code calling the chat API
-- was blocked on WoW Forever even from a click, while the same line typed as
-- /run was allowed; a secure button runs "/s ..." as the player's own macro,
-- so one click posts.  The macro is armed when the share popout opens, which
-- is only possible out of combat.

-- Chat from addons and macros is refused in combat-restricted contexts
-- (Midnight's addon restrictions); Share is disabled while any is active.
local RESTRICTIONS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch" }

function Quiz.ChatRestricted()
    if InCombatLockdown and InCombatLockdown() then return true end
    local active = C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
    local types = Enum and Enum.AddOnRestrictionType
    if type(active) == "function" and types then
        for _, name in ipairs(RESTRICTIONS) do
            if types[name] ~= nil then
                local ok, on = pcall(active, types[name])
                if ok and on == true then return true end
            end
        end
    end
    return IsEncounterInProgress and IsEncounterInProgress() and true or false
end

local function inGroup() return IsInGroup and IsInGroup() and true or false end

-- A secure button styled like HammerCore's own; its macro is set later.
local function macroButton(parent, label)
    local button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate,BackdropTemplate")
    button:SetSize(98, 22)
    T.Surface(button, "raised", "edge")
    button.Text = UI.FontString(button)
    button.Text:SetAllPoints()
    button.Text:SetJustifyH("CENTER")
    button.Text:SetText(label)
    button:RegisterForClicks("LeftButtonUp")
    -- Mouse-up regardless of the player's ActionButtonUseKeyDown setting.
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("type", "macro")
    return button
end

-- Enable or disable a destination, keeping its label legible either way.
local function setUsable(button, usable)
    button:SetEnabled(usable)
    T.Text(button.Text, usable and "text" or "muted")
end

function Quiz:ArmShare()
    local frame = self.frame
    if not frame or InCombatLockdown and InCombatLockdown() then return false end
    local text = self:ResultText()
    frame.destinations.SAY:SetAttribute("macrotext", "/s " .. text)
    local party = inGroup()
    frame.destinations.PARTY:SetAttribute("macrotext", party and ("/p " .. text) or nil)
    setUsable(frame.destinations.PARTY, party)
    return true
end

-- Share is usable only when the result is showing and chat is allowed.
function Quiz:UpdateShare()
    local frame = self.frame
    if not frame then return end
    local usable = self.phase == "done" and #(self.run or {}) > 0 and not Quiz.ChatRestricted()
    setUsable(frame.share, usable)
    if not usable then frame.destinationPopup:Hide() end
    if usable and frame.destinationPopup:IsShown() then self:ArmShare() end
end

function Quiz:Publish(destination)
    if destination == "TEXT" then HC.Print(self:ResultText()) end
end

function Quiz:Create()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", HC.FrameName("Quiz"), UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, 340)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    T.Surface(frame, "outer", "edge")
    frame:Hide()

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 16, -14)
    icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    local title = UI.FontString(frame, "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    title:SetText(HC.name .. " lore quiz")
    frame.progress = UI.FontString(frame, "GameFontHighlightSmall", "muted")
    frame.progress:SetPoint("TOPRIGHT", -40, -18)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() frame:Hide() end)

    local track = T.Fill(frame:CreateTexture(nil, "BACKGROUND"), "rail")
    track:SetPoint("TOPLEFT", 16, -46)
    track:SetSize(WIDTH - 32, 4)
    frame.timer = T.Fill(frame:CreateTexture(nil, "ARTWORK"), "selected")
    frame.timer:SetPoint("TOPLEFT", track, "TOPLEFT")
    frame.timer:SetSize(WIDTH - 32, 4)
    frame.timerTrack = track

    frame.question = UI.FontString(frame, "GameFontHighlight")
    frame.question:SetPoint("TOPLEFT", 16, -64)
    frame.question:SetWidth(WIDTH - 32)
    frame.question:SetJustifyH("LEFT")

    frame.answers = {}
    for index = 1, 4 do
        local button = UI.Button(frame, WIDTH - 32, 30)
        button:SetPoint("TOPLEFT", 16, -104 - (index - 1) * 36)
        button:SetScript("OnClick", function() Quiz:Answer(index) end)
        frame.answers[index] = button
    end

    frame.feedback = UI.FontString(frame, "GameFontNormal", "flavour")
    frame.feedback:SetPoint("BOTTOM", 0, 52)
    frame.feedback:SetWidth(WIDTH - 32)

    frame.destinationPopup = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.destinationPopup:SetSize(114, 82)
    frame.destinationPopup:SetPoint("BOTTOM", frame, "BOTTOM", 0, 48)
    T.Surface(frame.destinationPopup, "raised", "edge")
    frame.destinationPopup:Hide()
    frame.destinations = {}
    for index, destination in ipairs(DESTINATIONS) do
        local button
        if destination == "TEXT" then
            button = UI.Button(frame.destinationPopup, 98, 22)
            button:SetText(DESTINATION_LABELS[destination])
            button:SetScript("OnClick", function()
                frame.destinationPopup:Hide()
                Quiz:Publish(destination)
            end)
        else
            -- The secure template owns OnClick and runs the macro; PostClick
            -- only tidies up afterwards.
            button = macroButton(frame.destinationPopup, DESTINATION_LABELS[destination])
            button:SetScript("PostClick", function() frame.destinationPopup:Hide() end)
        end
        button:SetPoint("TOP", 0, -6 - (index - 1) * 24)
        frame.destinations[destination] = button
    end

    frame.again = UI.Button(frame, 104, 24)
    frame.again:SetPoint("BOTTOMLEFT", 16, 16)
    frame.again:SetText("Again")
    frame.again:SetScript("OnClick", function() Quiz:Start() end)
    frame.share = UI.Button(frame, 130, 24, "primary")
    frame.share:SetPoint("BOTTOM", 0, 16)
    frame.share:SetText("Share result")
    frame.share:SetScript("OnClick", function()
        if frame.destinationPopup:IsShown() then
            frame.destinationPopup:Hide()
        elseif not Quiz.ChatRestricted() and Quiz:ArmShare() then
            frame.destinationPopup:Show()
        end
    end)
    frame.done = UI.Button(frame, 104, 24)
    frame.done:SetPoint("BOTTOMRIGHT", -16, 16)
    frame.done:SetText("Close")
    frame.done:SetScript("OnClick", function() frame:Hide() end)

    frame:SetScript("OnUpdate", function(_, elapsed) Quiz:Tick(elapsed) end)
    -- Combat, restriction and group changes re-check whether Share can work.
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "ADDON_RESTRICTION_STATE_CHANGED", "GROUP_ROSTER_UPDATE" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function() Quiz:UpdateShare() end)
    frame:SetScript("OnHide", function()
        Quiz.phase = nil
        frame.destinationPopup:Hide()
    end)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = frame:GetName() end
    self.frame = frame
    return frame
end

function Quiz:Start()
    local frame = self:Create()
    self.run, self.index, self.score = Quiz.Draw(), 0, 0
    frame:Show()
    frame:Raise()
    frame.again:Hide()
    frame.share:Hide()
    frame.destinationPopup:Hide()
    frame.done:Hide()
    if #self.run == 0 then
        self.phase = "done"
        frame.question:SetText("The archives are empty for this character.")
        for _, button in ipairs(frame.answers) do button:Hide() end
        return
    end
    self:Next()
end

function Quiz:Next()
    local frame = self.frame
    self.index = self.index + 1
    local item = self.run[self.index]
    if not item then return self:Finish() end
    self.phase, self.remaining, self.limit = "asking", Quiz.Seconds(), Quiz.Seconds()
    frame.progress:SetText(self.index .. " of " .. #self.run)
    frame.question:SetText(item.question)
    for index, button in ipairs(frame.answers) do
        button:SetText(item.choices[index])
        T.Border(button, "edge")
        button:SetEnabled(true)
        button:Show()
    end
    frame.feedback:SetText("")
    frame.timerTrack:SetShown(self.limit ~= nil)
    frame.timer:SetShown(self.limit ~= nil)
    frame.timer:SetWidth(WIDTH - 32)
end

-- index is the chosen answer, or nil when the timer ran out.
function Quiz:Answer(index)
    if self.phase ~= "asking" then return end
    local frame, item = self.frame, self.run[self.index]
    local right = index == item.correct
    if right then self.score = self.score + 1 end
    for _, button in ipairs(frame.answers) do button:SetEnabled(false) end
    T.Border(frame.answers[item.correct], "accent")
    if index and not right then T.Border(frame.answers[index], "danger") end
    frame.feedback:SetText(right and "Correct!" or (index and "Not quite." or "Out of time!"))
    self.phase, self.remaining = "reveal", Quiz.REVEAL
end

function Quiz:Tick(elapsed)
    if self.phase == "asking" and self.limit then
        self.remaining = self.remaining - elapsed
        local share = math.max(0, self.remaining / self.limit)
        self.frame.timer:SetWidth(math.max(1, (WIDTH - 32) * share))
        if self.remaining <= 0 then self:Answer(nil) end
    elseif self.phase == "reveal" then
        self.remaining = self.remaining - elapsed
        if self.remaining <= 0 then self:Next() end
    end
end

function Quiz:Finish()
    local frame = self.frame
    self.phase = "done"
    local state = HC.State()
    local best = math.max(tonumber(state.quizBest) or 0, self.score)
    state.quizBest = best
    local total = #self.run
    local verdict = self:ChooseVerdict(self.score, total)
    frame.progress:SetText("Best " .. best .. " of " .. total)
    frame.question:SetText(self.score .. " of " .. total .. ". " .. verdict)
    for _, button in ipairs(frame.answers) do button:Hide() end
    frame.timerTrack:Hide()
    frame.timer:Hide()
    frame.feedback:SetText("")
    frame.again:Show()
    frame.share:Show()
    frame.destinationPopup:Hide()
    frame.done:Show()
    self.verdict = verdict
    self:UpdateShare()
end

function Quiz.Verdicts() return VERDICTS end

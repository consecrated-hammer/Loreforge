local _, ns = ...
local HC = ns.HammerCore
local T = HC.Theme

-- Optional flourishes for the game windows: the storybook look, lively
-- animations, tavern banter and streak flames. Each is a setting, on by
-- default, and every helper here does nothing while its setting is off.
-- Banter is local text only: nothing in this file sends to chat or the
-- Party channel.

local Flair = {}
ns.Flair = Flair

Flair.KEYS = { storybook = "storybook", lively = "livelyAnimations", banter = "tavernBanter", streak = "streakFlair" }

function Flair.On(name)
    local key = Flair.KEYS[name]
    return key ~= nil and not (ns.db and ns.db[key] == false)
end

-- Textures shared by Retail and Forever.
Flair.STORY_FONT = "Fonts\\MORPHEUS.TTF"
Flair.BOOK = "Interface\\Icons\\INV_Misc_Book_09"
Flair.QUEST = "Interface\\GossipFrame\\AvailableQuestIcon"
Flair.STAR = "Interface\\Cooldown\\star4"
Flair.TROPHY = "Interface\\Icons\\INV_Crown_01"
Flair.NUMBERS = { "1", "2", "3", "4" }
-- Parchment tint over the window body; its alpha follows Window opacity.
Flair.PARCHMENT = { 0.62, 0.46, 0.25, 0.12 }

-- ── Storybook type ─────────────────────────────────────────────────────────

-- Sets a font string in the storybook face and colour, or back to the face
-- and colour it had before. The original font is read once, the first time.
function Flair.Typeface(fs, story, size, role, plainRole)
    if not fs then return end
    if not fs.lfFont then
        local face, height, flags = nil, nil, nil
        if fs.GetFont then face, height, flags = fs:GetFont() end
        fs.lfFont = { face or STANDARD_TEXT_FONT, height or size, flags or "" }
    end
    if story and fs.SetFont then
        local ok, set = pcall(fs.SetFont, fs, Flair.STORY_FONT, size, "")
        if not ok or set == false then fs:SetFont(fs.lfFont[1], fs.lfFont[2], fs.lfFont[3]) end
    elseif fs.SetFont and fs.lfFont[1] then
        fs:SetFont(fs.lfFont[1], fs.lfFont[2], fs.lfFont[3])
    end
    T.Text(fs, story and role or plainRole or "text")
end

-- The header bar: icon and title face. win.lfIcon is set by WindowChrome.
function Flair.ApplyChrome(win)
    if not (win and win.title) then return end
    local story = Flair.On("storybook")
    if win.lfIcon then win.lfIcon:SetShown(story) end
    win.title:ClearAllPoints()
    if story and win.lfIcon then win.title:SetPoint("LEFT", win.lfIcon, "RIGHT", 8, 0)
    else win.title:SetPoint("LEFT", 16, 0) end
    Flair.Typeface(win.title, story, 18, "accent", "text")
    if win.lfParchment then win.lfParchment:SetShown(story) end
end

-- A 1 to 4 badge on an answer button, matching the Answer 1 to 4 keys.
function Flair.AnswerBadge(b, index, role)
    local story = Flair.On("storybook")
    if not b.lfBadge and story then
        local badge = CreateFrame("Frame", nil, b, "BackdropTemplate")
        badge:SetSize(20, 20)
        badge:SetPoint("LEFT", 8, 0)
        T.Surface(badge, "field", "edge")
        badge.text = HC.UI.FontString(badge, "GameFontNormal", "accent")
        badge.text:SetPoint("CENTER", 0, 0)
        badge.text:SetText(Flair.NUMBERS[index] or tostring(index))
        b.lfBadge = badge
    end
    if b.lfBadge then
        b.lfBadge:SetShown(story)
        if story then
            T.Border(b.lfBadge, role == "muted" and "edge" or role or "edge")
            T.Text(b.lfBadge.text, role == "muted" and "muted" or "accent")
        end
    end
    return story
end

-- ── Animations ─────────────────────────────────────────────────────────────
-- AnimationGroups only, each tracked by the window that owns it so hiding the
-- window (or turning the setting off) stops every one of them.

local function track(owner, group)
    owner.lfGroups = owner.lfGroups or {}
    owner.lfGroups[#owner.lfGroups + 1] = group
    return group
end

local function step(group, kind, order, duration, smoothing)
    local a = group:CreateAnimation(kind)
    a:SetOrder(order)
    a:SetDuration(duration)
    if smoothing then a:SetSmoothing(smoothing) end
    return a
end

local function scale(a, from, to)
    if a.SetScaleFrom and a.SetScaleTo then
        a:SetScaleFrom(from, from); a:SetScaleTo(to, to)
    elseif a.SetScale then
        a:SetScale(to / from, to / from)
    end
    if a.SetOrigin then a:SetOrigin("CENTER", 0, 0) end
end

local function fade(a, from, to)
    if a.SetFromAlpha then a:SetFromAlpha(from); a:SetToAlpha(to)
    elseif a.SetChange then a:SetChange(to - from) end
end

function Flair.StopAll(owner)
    if not owner then return end
    for _, group in ipairs(owner.lfGroups or {}) do
        if group.Stop then group:Stop() end
    end
    for _, region in ipairs(owner.lfHideOnStop or {}) do region:Hide() end
    -- A stopped pulse starts again on the next call that wants it.
    for _, region in ipairs(owner.lfPulseRegions or {}) do region.lfPulsing = nil end
end

local function play(owner, group)
    if group.Stop then group:Stop() end
    group:Play()
    return true
end

-- A quick scale pulse when an answer is picked.
function Flair.Pop(owner, b)
    if not (owner and b) or not Flair.On("lively") then return false end
    if not b.lfPop then
        local g = track(owner, b:CreateAnimationGroup())
        scale(step(g, "Scale", 1, 0.07, "OUT"), 1, 1.06)
        scale(step(g, "Scale", 2, 0.12, "IN"), 1.06, 1)
        b.lfPop = g
    end
    return play(owner, b.lfPop)
end

-- A short side-to-side shake for a wrong answer; it ends where it started.
function Flair.Shake(owner, b)
    if not (owner and b) or not Flair.On("lively") then return false end
    if not b.lfShake then
        local g = track(owner, b:CreateAnimationGroup())
        for i, x in ipairs({ 6, -12, 10, -6, 2 }) do step(g, "Translation", i, 0.05):SetOffset(x, 0) end
        b.lfShake = g
    end
    return play(owner, b.lfShake)
end

-- A burst of three stars over a region, for a correct answer.
function Flair.Sparkle(owner, anchor)
    if not (owner and anchor) or not Flair.On("lively") then return false end
    local burst = owner.lfSparkle
    if not burst then
        burst = CreateFrame("Frame", nil, owner)
        burst:SetSize(1, 1)
        if burst.SetFrameLevel and owner.GetFrameLevel then burst:SetFrameLevel((owner:GetFrameLevel() or 1) + 20) end
        burst.stars, burst.groups = {}, {}
        for i, spot in ipairs({ { -0.3, 34, 0 }, { 0, 46, 0.08 }, { 0.3, 30, 0.16 } }) do
            local star = burst:CreateTexture(nil, "OVERLAY")
            star:SetTexture(Flair.STAR)
            if star.SetBlendMode then star:SetBlendMode("ADD") end
            star:SetVertexColor(T.Unpack("accent"))
            star:SetSize(spot[2], spot[2])
            star:Hide()
            star.offset = spot[1]
            local g = track(owner, star:CreateAnimationGroup())
            local grow = step(g, "Scale", 1, 0.35, "OUT"); scale(grow, 0.3, 1.4)
            if spot[3] > 0 then grow:SetStartDelay(spot[3]) end
            local spin = step(g, "Rotation", 1, 0.5); spin:SetDegrees(90)
            if spot[3] > 0 then spin:SetStartDelay(spot[3]) end
            local out = step(g, "Alpha", 1, 0.3); fade(out, 1, 0); out:SetStartDelay(0.25 + spot[3])
            g:SetScript("OnFinished", function() star:Hide() end)
            g:SetScript("OnStop", function() star:Hide() end)
            burst.stars[i], burst.groups[i] = star, g
            owner.lfHideOnStop = owner.lfHideOnStop or {}
            owner.lfHideOnStop[#owner.lfHideOnStop + 1] = star
        end
        owner.lfSparkle = burst
    end
    local width = anchor.GetWidth and anchor:GetWidth() or 0
    for i, star in ipairs(burst.stars) do
        star:ClearAllPoints()
        star:SetPoint("CENTER", anchor, "CENTER", width * star.offset, 0)
        star:Show()
        play(owner, burst.groups[i])
    end
    return true
end

-- A looping pulse while on; the timer uses it in the last five seconds.
function Flair.Pulse(owner, region, on)
    if not (owner and region) then return false end
    on = on and Flair.On("lively") or false
    if not region.lfPulse then
        if not on then return false end
        local g = track(owner, region:CreateAnimationGroup())
        g:SetLooping("BOUNCE")
        fade(step(g, "Alpha", 1, 0.45, "IN_OUT"), 1, 0.35)
        region.lfPulse = g
        owner.lfPulseRegions = owner.lfPulseRegions or {}
        owner.lfPulseRegions[#owner.lfPulseRegions + 1] = region
    end
    if on and not region.lfPulsing then
        region.lfPulsing = true
        region.lfPulse:Play()
    elseif not on and region.lfPulsing then
        region.lfPulsing = nil
        region.lfPulse:Stop()
    end
    return on
end

-- The winner's crown drops in and settles.
function Flair.BounceIn(owner, region)
    if not (owner and region) or not Flair.On("lively") then return false end
    if not region.lfBounce then
        local g = track(owner, region:CreateAnimationGroup())
        local appear = step(g, "Alpha", 1, 0.15); fade(appear, 0, 1)
        scale(step(g, "Scale", 1, 0.22, "OUT"), 0.3, 1.25)
        scale(step(g, "Scale", 2, 0.12, "IN"), 1.25, 0.92)
        scale(step(g, "Scale", 3, 0.1, "OUT"), 0.92, 1)
        region.lfBounce = g
    end
    return play(owner, region.lfBounce)
end

-- ── Streaks ────────────────────────────────────────────────────────────────

-- Tiers at 3, 5 and 10 correct in a row: icon, size and colour role.
Flair.TIERS = {
    { at = 3, icon = "Interface\\Icons\\Spell_Fire_Fire", size = 16, role = "flavour", label = "On fire" },
    { at = 5, icon = "Interface\\Icons\\Spell_Fire_Immolation", size = 20, role = "accent", label = "Blazing" },
    { at = 10, icon = "Interface\\Icons\\Spell_Fire_SoulBurn", size = 24, role = "danger", label = "Unstoppable" },
}

function Flair.StreakTier(streak)
    streak = tonumber(streak) or 0
    for i = #Flair.TIERS, 1, -1 do
        if streak >= Flair.TIERS[i].at then return i, Flair.TIERS[i] end
    end
    return 0, nil
end

-- A flame and count beside the score line. SetStreak shows it at 3 or more,
-- grows it at each tier and hides it after a miss.
function Flair.StreakBadge(owner, parent)
    local badge = CreateFrame("Frame", nil, parent)
    badge:SetSize(60, 24)
    badge.icon = badge:CreateTexture(nil, "ARTWORK")
    badge.icon:SetPoint("LEFT", 0, 0)
    if badge.icon.SetTexCoord then badge.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    badge.count = HC.UI.FontString(badge, "GameFontNormal", "flavour")
    badge.count:SetPoint("LEFT", badge.icon, "RIGHT", 4, 0)
    badge.tier = 0
    badge:Hide()
    function badge:SetStreak(streak)
        local tier, spec = Flair.StreakTier(streak)
        if not Flair.On("streak") then tier = 0 end
        local grew = tier > (self.tier or 0)
        self.tier, self.streak = tier, tonumber(streak) or 0
        self:SetShown(tier > 0)
        if tier == 0 then return 0 end
        self.icon:SetTexture(spec.icon)
        self.icon:SetSize(spec.size, spec.size)
        self.count:SetText(tostring(self.streak))
        T.Text(self.count, spec.role)
        T.Font(self.count, 10 + spec.size / 2, "OUTLINE")
        if grew then Flair.Pop(owner, self) end
        return tier
    end
    return badge
end

-- ── Tavern banter ──────────────────────────────────────────────────────────

Flair.BANTER = {
    correct = {
        "Even the barkeep knew that one.",
        "The innkeeper nods approvingly.",
        "Somewhere, a loremaster sheds a proud tear.",
        "Quest text: read. Respect: earned.",
        "Correct, and not a single peek at Wowhead.",
        "Ding! Lore level up.",
        "The Bronze Dragonflight saw that coming.",
        "A gnome in the corner applauds.",
        "Your hearthstone glows with pride.",
    },
    wrong = {
        "Bold guess. Wrong, but bold.",
        "The murlocs say it was close. Mrgle.",
        "Not quite, but the tavern admires your confidence.",
        "Chromie says that's right in another timeline.",
        "That answer has been sent to the Shadowlands.",
        "Even Leeroy had a plan. Sort of.",
        "The barkeep pours you a consolation ale.",
        "Close enough for goblin engineering.",
    },
    timeout = {
        "The hourglass got there first.",
        "Still reading the quest text?",
        "Time flies when you're AFK.",
        "The answer window shut like a dungeon door.",
        "Nozdormu would like a word about punctuality.",
        "Stopped for a snack, eh?",
        "That question wandered off, unanswered.",
        "Next time, fewer emotes and more clicks.",
    },
    streak = {
        "%d in a row! Someone fetch a bucket.",
        "%d in a row! The bards are taking notes.",
        "%d in a row! Is this a quiz or a raid boss?",
        "%d in a row! Your tabard is smouldering.",
        "%d in a row! The tavern cat is impressed.",
        "%d in a row! A Loremaster title can't be far off.",
        "%d in a row! Leave some answers for everyone else.",
        "%d in a row! Unstoppable, like a tauren charge.",
    },
    winner = {
        "Drinks are on the champion!",
        "A toast to the sharpest mind in the tavern.",
        "The bards are already writing the ballad.",
        "Victory! Please collect your imaginary trophy.",
        "The Hall of Fame makes room on the wall.",
        "The wisdom of a sage and the reflexes of a rogue.",
        "Lore rolled Need, and won.",
        "Achievement unlocked: Tavern Legend.",
    },
    tie = {
        "A tie! The barkeep refuses to pick favourites.",
        "Shared glory. Split the gold evenly, now.",
        "Even the Titans couldn't separate this lot.",
        "Too close to call. Rematch?",
        "A draw! Everyone gets the good chair.",
        "Equal honours. The bards will need a duet.",
        "Neck and neck, like kodos at the races.",
    },
    none = {
        "The questions win this time.",
        "A tough crowd, or a tough quiz?",
        "Everyone's off to read the quest text.",
        "The loremasters are, frankly, worried.",
        "Nobody scored. The tavern cat is unimpressed.",
        "Back to the books, adventurers.",
    },
}

-- One quip per bucket and moment: redraws of the same reveal keep their line,
-- and the next moment moves on to the next line in the bucket.
local turn, shown = {}, {}
function Flair.Quip(bucket, key, value)
    if not Flair.On("banter") then return "" end
    local lines = Flair.BANTER[bucket]
    if not lines or key == nil then return "" end
    key = tostring(key)
    local current = shown[bucket]
    if not (current and current.key == key) then
        if not turn[bucket] then turn[bucket] = math.random and math.random(#lines) or 1 end
        turn[bucket] = turn[bucket] % #lines + 1
        current = { key = key, line = lines[turn[bucket]] }
        shown[bucket] = current
    end
    if current.line:find("%d", 1, true) then return (current.line:format(tonumber(value) or 0)) end
    return current.line
end

-- Which bucket a reveal belongs to for this player.
function Flair.RevealBucket(choice, correct, streak)
    if not correct then return nil end
    if choice == correct then return (tonumber(streak) or 0) >= 3 and "streak" or "correct" end
    if choice then return "wrong" end
    return "timeout"
end

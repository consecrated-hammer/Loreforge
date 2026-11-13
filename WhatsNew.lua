local addonName, ns = ...

-- Highlights for HammerCore's What's new page, newest first. Every
-- CurseForge release gets an entry, fixes included; HammerCore's
-- tools/whatsnew_check.py fails the release without one. A `page` adds a
-- link to that settings page.
ns.WHATS_NEW = {
    { version = "1.4.0", date = "2026-11-13", items = {
        { title = "A little more reading room", text = "Quick play keeps ordinary answer buttons in place, with clear verdicts, tick/cross cues and familiar pops and sparkles. The painting stays square, and Options opens on the side with space.", page = "Quick play", tab = "Card" },
        { title = "Choose your next game", text = "Solo Play leads with Quick play, Daily question and Practice. Hall of Fame leads with your personal bests, and records and Party settings share Games and records.", page = "Games and records" },
        { title = "A little less tavern chatter", text = "Card banter defaults to every third reveal. Choose how often under Card; Lightning stays quiet.", page = "Quick play", tab = "Card" },
        { title = "Find your favourite settings", text = "Quick play has Play, Card, Flights and Daily question tabs. Interface separates Presentation from Windows. Search finds hidden options and individual answer bindings.", page = "Quick play", tab = "Play" },
        { title = "A clearer host table", text = "Categories stays available with the lobby open. The game summary names the selected preset, or Custom after you change its question count or answer time." },
        { title = "Pick up where you left off", text = "Dismiss a quiz during a flight and a small book lets you resume it or start a new challenge. Effects stop when hidden, and personal bests celebrate once.", page = "Quick play", tab = "Flights" },
        { title = "Keep it quiet", text = "Animations also controls the Party restore-button pulse. Card animations remain a separate switch.", page = "Interface", tab = "Presentation" },
    } },
    { version = "1.3.0", date = "2026-11-10", items = {
        { title = "Quick play", text = "A little solo quiz card for idle moments. One click, no setup, nothing in chat. Try /lf quick, right-click the minimap button, or the button on the Play tab.",
            page = "Quick play" },
        { title = "Fancy a question?", text = "Take a flight path and Loreforge offers a quiz. Flight challenge: as many as you can before you touch down.",
            page = "Quick play" },
        { title = "Daily question", text = "One question a day, one try and no timer. Keep your daily streak going with /lf daily, the Play tab or the minimap menu.",
            page = "Quick play" },
        { title = "Personal bests", text = "Best streak, best Lightning, best flight and your daily streak, on the card and in the Hall of Fame." },
        { title = "Make yourself at home", text = "A welcome window helps you choose flights and daily offers. Run /lf setup to open it again. Quick play leads the Play tab when you're solo.",
            page = "Visibility" },
        { title = "Better with LibTaxiData", text = "Install the free LibTaxiData library and Flight challenge counts down from your first flight. Without it, Loreforge learns each route as you fly.",
            kind = "improved" },
    } },
    { version = "1.1.0", date = "2026-11-09", items = {
        { title = "Stop game in the quiz window", text = "Practising solo or hosting while you play? Stop game now sits right in the quiz window.",
            kind = "fixed" },
        { title = "Shorter names", text = "Players on your realm show without the realm, so no more CAMWOWAU-sized name tags.",
            kind = "fixed" },
        { title = "Auto-advance on", text = "Questions now roll on by themselves after a short gap. Prefer to call each one? Turn off Auto-advance under Pacing & chat.",
            kind = "improved" },
        { title = "A fresh coat of paint", text = "Settings got a new look: a cleaner header, switches, icons on every heading and this What's new page.",
            kind = "improved" },
        { title = "Answer keys", text = "Bind Answer 1 to 4 right in settings, no digging through the game's Key Bindings.",
            page = "Key Bindings" },
        { title = "Support links", text = "CurseForge, Discord and Buy me a coffee sit at the bottom of the settings window. Hide them on Visibility.",
            kind = "improved", page = "Visibility" },
        { title = "Game windows", text = "The main window and the player window match the new look, solid by default. The main window is roomier, with tabs across the top and game setup split into Game, Categories and Pacing & chat. Window opacity on Interface if you like a peek through.",
            kind = "improved", page = "Interface" },
        { title = "A bit more fun", text = "Storybook titles, lively answers, tavern banter and streak flames. Tone any of it down under Flair on Interface.",
            kind = "improved", page = "Interface" },
    } },
    { version = "1.0.0", date = "2026-11-01", history = true, items = {
        "Every category now has its own painting beside the question.",
        "Themed rounds open with their art and name.",
    } },
    { version = "0.3.4", date = "2026-11-01", history = true, items = {
        { text = "What's new: this window, shown once after an update that adds something worth knowing, with news from any other Consecrated Hammer addons you use. Reopen it with /lf whatsnew or from About, or turn it off on Visibility.",
            page = "Visibility" },
        "A simpler game window: the question, four answers, a timer and your score, in the style of the lore quiz on About. Hosts playing along answer in it too.",
        "Themed rounds: an optional setup where each round sticks to one category.",
        "Mis-clicked? Change your answer any time before the countdown ends.",
    } },
    { version = "0.3.3", history = true, items = {
        "Party questions open for everyone at the same moment, with clear Ready and answer feedback.",
        "A Game complete screen shows the winner, your result and the final standings.",
    } },
}

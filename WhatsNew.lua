local addonName, ns = ...

-- Highlights for HammerCore's What's new page, newest first. Every
-- CurseForge release gets an entry, fixes included; HammerCore's
-- tools/whatsnew_check.py fails the release without one. A `page` adds a
-- link to that settings page.
ns.WHATS_NEW = {
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

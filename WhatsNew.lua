local addonName, ns = ...

-- Highlights for HammerCore's What's new window, newest first. Short,
-- player-facing lines for releases worth announcing; routine fixes stay in
-- CHANGELOG.md. A `page` adds a button that opens that settings page.
ns.WHATS_NEW = {
    { version = "0.3.4", items = {
        { text = "What's new: this window, shown once after an update that adds something worth knowing, with news from any other Consecrated Hammer addons you use. Reopen it with /lf whatsnew or from About, or turn it off on Visibility.",
            page = "Visibility" },
        "A simpler game window: the question, four answers, a timer and your score, in the style of the lore quiz on About. Hosts playing along answer in it too.",
        "Themed rounds: an optional setup where each round sticks to one category.",
        "Mis-clicked? Change your answer any time before the countdown ends.",
    } },
    { version = "0.3.3", items = {
        "Party questions open for everyone at the same moment, with clear Ready and answer feedback.",
        "A Game complete screen shows the winner, your result and the final standings.",
    } },
}

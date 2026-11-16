# Campfire Quick play

Campfire.lua observes Forever's seated campfire aura (1229739) through the
player aura API. It uses existing Loreforge Quick play, settings and question
data; no third-party question bank, UI implementation or quiz code is copied.

`qpCampfire` is a boolean under Quick play > Play, on by default for new/missing
settings while preserving saved false values, and
hidden on unsupported clients. The module registers player aura/world/combat
events only while enabled. No polling or protected gameplay actions occur.

The module owns exactly the Quick.state object created on a new campfire
visit. Standing/disable/takeoff close only that state. Combat closes a visible automatic
quiz; an already dismissed quiz remains paused, with its book hidden until combat ends. A manually replaced
quiz is not owned. Manual dismissal pauses the owned quiz and shows the draggable book for Resume quiz /
New quiz while seated. Neither choice reopens a stale visit. The book disappears on
standing, disable or takeoff. Its `qpCampfireBookPoint` is independent of the flight
book position; Quick play > Play offers Reset campfire book position.
Manual dismissal latches the visit until the aura is absent and returns. Secret/unavailable/malformed aura data is unknown, never absence.
Group games, active cards, prompts and queued/visible welcome/news take priority;
a busy visit is skipped until the player leaves and sits again. Unknown aura
intervals do not invent new visits. Explicitly re-enabling while seated may
start a new automatic quiz.

Takeoff explicitly releases campfire ownership before normal flight handling.
Card.CloseSession closes the exact owned session through its own hide path, preventing combat exit
or flight launchers from resurrecting an automatically closed session.
`tests/test_quick_play.lua` exercises these transitions with the real card and
game, alongside Retail non-support and existing flight/game regressions. Native
aura detection and rendering still require the owner’s in-client check.

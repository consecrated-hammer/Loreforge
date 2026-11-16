# Campfire Quick play

Campfire.lua observes Forever's seated campfire aura (1229739) through the
player aura API. It uses existing Loreforge Quick play, settings and question
data; no third-party question bank, UI implementation or quiz code is copied.

`qpCampfire` is a boolean under Quick play > Play, on by default for new/missing
settings while preserving saved false values, and
hidden on unsupported clients. The module registers player aura/world/combat
events only while enabled. No polling or protected gameplay actions occur.

Each eligible new visit opens a campfire offer through the shared flight-prompt
frame, with only the selected solo mode and Not now. Flight-specific buttons and
checkboxes are hidden, then restored on the next flight offer. No Quick.state or
timer exists until acceptance. Declining leaves a book with New quiz available
and Resume disabled. Starting a manual quiz cancels the pending offer.

The accept button and its tooltip retain the mode named when the offer appeared,
even if settings change before clicking. An interrupted aura probe during offer
creation leaves no pending offer; a later known seated observation can retry.

After acceptance, the module owns exactly the Quick.state object it created.
Standing/disable/takeoff close the pending offer/book and only that owned state.
Combat hides an unanswered offer and restores it only on a known seated visit.
Combat closes a visible automatic quiz; an already dismissed quiz remains
paused, with its book hidden until combat ends. A manually replaced quiz is
not owned. Manual dismissal pauses the owned quiz and shows the draggable
book for Resume quiz / New quiz while seated. Neither choice reopens a stale visit. The book disappears on
standing, disable or takeoff. Its `qpCampfireBookPoint` is independent of the flight
book position; Quick play > Play offers Reset campfire book position.
Manual dismissal latches the visit until the aura is absent and returns. Secret/unavailable/malformed aura data is unknown, never absence.
Group games, active cards, prompts and queued/visible welcome/news take priority;
a busy visit is skipped until the player leaves and sits again. Unknown aura
intervals do not invent new visits. Explicitly re-enabling while seated may
show a new offer.

Takeoff explicitly releases campfire ownership before normal flight handling.
Card.CloseSession closes the exact owned session through its own hide path, preventing combat exit
or flight launchers from resurrecting an automatically closed session.
`tests/test_quick_play.lua` exercises these transitions with the real card and
game, alongside Retail non-support and existing flight/game regressions. Native
aura detection and rendering still require the owner’s in-client check.

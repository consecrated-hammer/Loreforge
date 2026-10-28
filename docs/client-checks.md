# Loreforge client checks

Run separately on Retail and Forever. Automated tests mock the game APIs; they
cannot prove client rendering, chat permissions or server event delivery.

1. Check `/lf version`. `/lf` and minimap left-click must open Host game; `/lf settings`, minimap right-click and Settings must open general settings. Check all text fits, scrolling works, and the window can be dragged and closed.
2. In setup, use the five section jump buttons. Ready check and Results must be easy to reach. The right column contains only categories. The eligible count, inline errors and Start game remain visible. Select a wrong destination, then use **Use current group** to correct it. Guild uses **Refresh guild roster**.
3. With a player who has no addon, start two questions in host-paced mode. Notices, question lines and results should post automatically. Check that the question is followed by four individually numbered lines in a short burst. The answer timer starts only after the last option is confirmed. Between questions, the primary action is **Ask next question** and nothing advances until clicked.
4. Repeat in auto-advance mode. Verify the gap begins after results finish, all rounds complete, records save once, and **New game** returns to setup. Switch pacing during a game and check that it takes effect at the next gap. Closing the window must not stop timers or automatic delivery.
5. Enable ready check. Verify `ready`, `Ready!`, `rdy` and `I'm ready` work during the notice and countdown in the selected channel. A wrong channel must not count. Check **Start questions now**, the ready/enrolled count and **Refresh enrolled players** before question one. New players must not join once questions have begun.
6. On Forever, test characters with surnames. Unit API names and chat sender names must refer to the same players. Own chat echoes must advance the queue; ready replies and answers must reach those players. A surname must never appear as the stored realm. On Retail, verify same-name players on different realms remain separate.
7. Try early, malformed, wrong-channel, wrong-GUID and duplicate answers. Only the first valid answer in the window counts. The displayed correct number must match the choices posted to chat. Correct players are named with running scores and streaks; a new streak best gets one callout.
8. Test Party, Raid, Instance and Guild separately, including leader chat events. Instance requires an instance group; a normal premade party in a dungeon uses Party. No setup should enrol one group's units while sending to another group.
9. Verify no blanket refusal solely from the outgoing-addon realm flag. Combat and actual messaging lockdown must pause sending. Ending the restriction must leave the game paused until **Resume game**. An interrupted question is re-announced with a fresh answer timer; a role update alone must not interrupt it.
10. If sending is refused or no echo arrives, check the reason and **Resume game**, then the click-to-send primary action and its line counter. After eight seconds, **I saw this line in chat: continue** must confirm exactly one visibly posted line. **Retry line** is for a line that did not appear. **Retry auto send** must explicitly retry automatic delivery, with no repeating failure loop.
11. Stop during final announcements. Confirm Stop game shows a warning; Cancel must leave the game active. Confirming stop must discard pending records. Completed records survive reload and reset settings. Clearing test records in general settings requires separate confirmation and preserves the other client's records.
12. Enable Game Master participation. Test chat and clickable answers, immediate highlighted Locked feedback, first-answer locking, scores and records. With participation off, host answers are ignored. While ungrouped, select Party and enable participation: the labelled local test must use no outbound API or macro in either pacing mode.
13. Check ties, zero-correct games, missed/wrong streak breaks, optional closing records and inactivity pauses. Ready-only players and bystanders must receive no records. A final silent question should finish instead of entering an inactivity pause.
14. Test category combinations, Hard, client filtering and a game larger than the selected pool. Refuse insufficient pools inline. Multi-tag questions must not repeat. Inspect staged files for packed questions and absence of readable JSONL; check Unicode text decodes correctly in game.

15. **Player UI transport probe (dev11 onward).** This decides whether the
    player UI design can go ahead. You need a second player with the same dev
    build. They type `/lf probe listen` first, which arms their client to
    answer for 10 minutes. You then type `/lf probe party` (or `raid`,
    `instance`, `guild`). After about 45 seconds you get a pass/incomplete
    line per replying client. A pass means their client got the hello, put
    the multi-message UTF-8 question back together intact, sent an answer,
    and confirmed your lock back to you. Both players then run
    `/lf probe report` and copy the report. Run it on Retail and Forever, in
    an open-world party, a premade party inside a dungeon, a queued Instance
    group, a raid and guild, and include a Forever character with a surname.
    Your own echo never counts as a pass. `/lf probe stop` cancels.

Report the version, client/build, channel, pacing, delivery state, current primary
action and any BugGrabber error. In dev7 the user reproduced an immediate
Instance restriction warning and ignored ready replies. Later host-side fixes
and mocked tests require a fresh real-client run; they do not establish success.

For the 0.1.1-beta library transport, both players must use the same new build.
The public 0.1.0-beta and dev11 probes use the old wire format. Verify the
report says prefix `LoreforgeP2`, ChatThrottleLib 32 and LibDeflate
1.0.2-release. Begin outside combat and restricted activity; zoning, roster
changes and restriction events stop the probe. Re-arm after those changes.
Capture both reports, including CTL results and actual remote acknowledgments.
A self-echo or successful send alone isn't a pass. See [transport](transport.md).

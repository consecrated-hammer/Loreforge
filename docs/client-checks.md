# Loreforge client checks

Run separately on Retail and Forever. Automated tests mock the game APIs; they
cannot prove client rendering, chat permissions or server event delivery.

1. Check `/lf version`. `/lf` and minimap left-click must open the main window on Play; the History and Hall of Fame tabs must switch views. Settings and minimap right-click open general settings, and **Back to game** returns. Escape closes the main window out of combat, and it must not reappear after the next combat. Check all text fits at 70%, 100% and 150% window size, scrolling works, and the window can be dragged.
2. In setup, try each preset and check the summary's question count and minutes. Steppers stop at their limits and respond to the mouse wheel. Category counts change with difficulty; **None** blocks the start with a banner. **Advanced options** opens and folds. Select a wrong destination: the banner explains it and **Use current group** fixes it. Guild uses **Refresh guild roster**.
3. With a player who has no addon, start two questions in host-paced mode. Notices, question lines and results should post automatically. Check that the question is followed by four separately numbered choice lines, and that **Choices on one line** enables the compact layout. The answer timer starts only after the last option is confirmed. Between questions, the primary action is **Ask next question** and nothing advances until clicked.
4. Repeat in auto-advance mode. Verify the gap begins after results finish, all rounds complete, records save once, and **New game** returns to setup. Switch pacing during a game and check that it takes effect at the next gap. Closing the window must not stop timers or automatic delivery.
5. Enable **Countdown before starting**. Verify **Start countdown** is visible without Advanced options, defaults to 30 seconds, and can be changed from 5 to 60 seconds. The first question must wait until that countdown ends unless the host starts early. Both host and joined player see the timer. Verify `ready`, `Ready!`, `rdy` and `I'm ready` work during the notice and countdown in the selected channel. A wrong channel must not count. Check **Start questions now**, the ready/enrolled count and **Refresh enrolled players** before question one. New players must not join once questions have begun.
6. On Forever, test characters with surnames. Unit API names and chat sender names must refer to the same players. Own chat echoes must advance the queue; ready replies and answers must reach those players. A surname must never appear as the stored realm. On Retail, verify same-name players on different realms remain separate.
7. Try early, malformed, wrong-channel, wrong-GUID and duplicate answers. Only the first valid answer in the window counts. The displayed correct number must match the choices posted to chat. Correct players are named with running scores and streaks; a new streak best gets one callout.
8. Test Party, Raid, Instance and Guild separately, including leader chat events. Instance requires an instance group; a normal premade party in a dungeon uses Party. No setup should enrol one group's units while sending to another group.
9. Verify no blanket refusal solely from the outgoing-addon realm flag. Combat and actual messaging lockdown must pause sending. Ending the restriction must leave the game paused until **Resume game**. An interrupted question is re-announced with a fresh answer timer; a role update alone must not interrupt it.
10. If sending is refused or no echo arrives, one banner must ask whether the line appeared. **Yes, it posted** confirms exactly one visibly posted line. **Post again** prepares the line for the manual post button and its line counter. **Retry automatic posting** must explicitly retry automatic delivery, with no repeating failure loop.
11. Stop during final announcements. Confirm Stop game shows a warning; Cancel must leave the game active. Confirming stop must discard pending records. Completed records survive reload and reset settings. Clearing test records in general settings requires separate confirmation and preserves the other client's records.
12. With **Host plays along** on, test chat, clicked and key-bound answers, immediate Locked feedback, first-answer locking, scores and records. With it off, host answers are ignored. **Practice solo**, grouped or not, must use no outbound API or macro in either pacing mode and must not be reported as interrupted after a reload.
13. Check ties, zero-correct games, missed/wrong streak breaks, optional closing records and inactivity pauses. Ready-only players and bystanders must receive no records. A final silent question should finish instead of entering an inactivity pause.
14. Reload during a live group game. Setup must report where it stopped; **Post standings** posts one line to the original channel and **Dismiss** clears it. Finished games appear in History with standings, and the Hall of Fame ranks by wins with accuracy.
15. Check sound cues with the setting on and off, and the timer bar turning amber then red.
16. Test category combinations, Hard, client filtering and a game larger than the selected pool. Refuse insufficient pools inline. Multi-tag questions must not repeat. Inspect staged files for packed questions and absence of readable JSONL; check Unicode text decodes correctly in game.

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

## Party player acceptance (new local implementation)

Use the same new build on a host and another Party member, plus one chat-only
player, first in the Retail open world and then in a premade dungeon Party
with activity restrictions inactive. The released 0.1.1-beta probe alone does not
include this interface.

1. Open host setup. Confirm no invitation appears until **Open lobby**.
2. On the other client, the invitation appears near the top of the screen.
   Decline once, then test a fresh lobby and join. The host's lobby panel must
   list the player as Joined and count down its 10 minutes; **Keep lobby open**
   resets it and changing Output asks before closing the lobby.
3. Start a two-round match. Use **I'm ready**. Confirm settings, host name,
   readiness and participant names are correct, including cross-realm names.
4. Check full question/choice wrapping and scrolling at normal and small scales.
   Buttons stay disabled during presentation and open after the chat notice.
5. Race a click against a chat answer from the same player. Only the first
   host-accepted choice locks. Retry never changes it. Let one answer time out.
6. Check the correct answer reveal, your selected answer, streak changes, both
   players' scores, chat-only participation and tied final winners.
7. Hide/restore, pause/resume, change the roster and briefly enter combat.
   Confirm old attempts cannot score and fallback/recovery messages are clear.
8. Complete the final chat announcements. Check the host and joined player's
   saved match have identical final and per-round standings. Reload the player
   and reopen history; catch-up must not duplicate the match or legacy records.
9. Stop another game during final output. It must not create a completed entry.
10. With 0.3.0-beta on both clients, check the between-question countdown in
    auto-advance, the host-paced message, the finish headline and medal
    colours, Leave confirmation and the pulsing restore button. A 0.2.0-beta
    player must still play normally against a 0.3.0-beta host.

Record client build and paired observations separately for open world and
premade dungeon Party. Only remote acknowledgements and a completed game
prove dungeon delivery; self-echoes do not. Queued Instance/Raid/Guild/Forever player
transport and UI are separate checks, with no support claim from this test.

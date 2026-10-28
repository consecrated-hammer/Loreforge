# Loreforge

**Group and guild trivia, with you at the Host game screen.**

_You have considered reading the quest text. Now make everyone else prove it._

Loreforge is in beta for Retail and WoW Forever. The game master picks Party, Raid, Instance or Guild output, categories, difficulty, rounds, answer time and manual or automatic pacing. Other players answer with a number in chat; they do not need the addon.

## What it does

- **Host-paced or auto-advance games.** Questions, choices and results post automatically in both modes. Host-paced games wait at **Ask next question** between questions; **Auto-advance questions** continues after the configured gap. Click-to-send is a fallback for clients that refuse automatic messages.
- **Game Master participation.** Enable **Game Master participates** at setup to join the scores, streaks and records. Answer in chat or click a choice at the Host game screen. When ungrouped, Party output becomes a labelled local test with no outbound chat. Local test results count toward your records.
- **Readable question blocks.** The question posts first, followed by four separate numbered answer lines in a short burst. The answer timer starts after the final option is confirmed.
- **Numbered answers.** Each player's first valid `1`, `2`, `3` or `4` locks their attempt. Correct answers earn one point; joint winners share the win.
- **Categories and difficulty.** Combine lore, geography, class and race questions with boss quotes, Hallow's End and the sillier themes. A question can have several tags but appears only once per game.
- **Round and overall scores**, plus live streaks. Wrong or missed questions break the streak; voided questions do not.
- **Ready checks.** Announce the quiz before the first question, accept optional `ready` replies and count down for 5-60 seconds. The Game Master can start sooner. Check-ins never earn points or create player records.
- **Chat recaps.** Each reveal names the correct players, their running scores and streaks of two or more. Beating a saved streak record gets a personal-best callout.
- **Inactivity pause.** Automatic games pause after three questions without replies by default. Change the limit or disable it at setup.
- **Player records.** Save games played, wins, attempts, correct answers and best streak by character and realm. Choose whether to announce them at the end.
- **The same HammerCore interface** as the other Consecrated Hammer addons: settings, controls, commands, minimap button, diagnostics and About page.

## Getting started

1. Join a party, raid, instance group or guild. Open `/lf`. For a one-player local test, select Party and enable **Game Master participates** while ungrouped.
2. Use **Game**, **Questions**, **Pacing**, **Ready** and **Results** to jump between the left-hand sections. The right column contains only question categories. Fresh settings select the current group channel; **Use current group** corrects it after a group change. For Guild, **Refresh guild roster** updates the cached players.
3. Check the eligible-player count and any message below it. Choose the game length, answer time, categories and difficulty. Enable **Auto-advance questions** if you want continuous play. Click **Start game**.
4. The starting notice posts automatically. Optional ready check-ins accept `ready`, `ready!`, `rdy` and `I'm ready`, including while the notice is being sent. The countdown begins after the notice is confirmed. **Start questions now** starts early once the notice is complete. **Refresh enrolled players** can add missing players before question one; enrolment is fixed once questions begin.
5. Each question and its numbered choices post automatically. Players answer `1` to `4` in the chosen channel. A participating Game Master can also click a choice. The selected choice highlights as **Locked**, with immediate confirmation below it. The first valid answer locks. Only answering enters a player into the scored game; bystanders and ready-only players get no record.
6. The timer closes answers and results post automatically. In host-paced mode, the primary button becomes **Ask next question**. Auto-advance games wait the configured gap and continue. Use the pacing control to switch during a game.
7. Final scores and optional player records post automatically. After all lines are confirmed, records save and the primary button becomes **New game**.

The Host game screen is draggable. Closing it does not stop the game; automatic play continues while it is hidden. `/lf host` opens it again. **Stop game** asks for confirmation before discarding unfinished results. When a game finishes, **New game** returns to setup. Pausing, entering combat or changing group membership voids an open question; resuming announces it again with a fresh timer. A role update alone does not pause the game.

## Commands

| Command | What it does |
| --- | --- |
| `/loreforge` or `/lf` | Open the Host game screen and game setup |
| `/lf host` | Open the Host game screen |
| `/lf settings` | Open general settings |
| `/lf records` | View or copy saved player records |
| `/lf quiz` | Play HammerCore's solo quiz |

Every Consecrated Hammer addon also has `help`, `version`, `about`, `debug`, `startup`, `minimap` and `reset settings`. Reset settings preserves Loreforge's player records. Records are shared by host characters on the same WoW account, with Retail and Forever stored separately.

The minimap button opens the Host game screen on left-click and general settings on right-click. A Settings button is also on the Host game screen. General settings hold visibility, diagnostics and player-record management. Clearing this client's records needs confirmation and is refused during an active game.

## Categories

The bank has 1,000 questions across General lore, Geography, Classes and mechanics, Races, Hallow's End, Boss quotes, Famous Last Words, Murlocs and Mischief, Dubious Goblin Engineering, and Things You Probably Vendored. That includes 103 boss quotes, 340 geography questions and 181 class questions. Tags overlap, so category totals exceed the bank size.

Retail can draw 861 questions and Forever 499. There are 308 hard questions across the full bank. Each client still needs enough matching questions for the host's chosen categories and game length.

Selected categories combine. **Easier**, **Hard / obscure** and **Mixed** select the difficulty. The actual client controls which questions are eligible; `classic` in the data specifically means WoW Forever. Hosted games draw from every class and race topic, while the solo quiz keeps its character-specific filters.

## Limits and client checks

- Party, Raid, Instance and Guild chat are supported. Instance means a queued instance group; being inside a dungeon with a premade party does not by itself create one. When an instance group is active, use Instance rather than a separate home Party/Raid so the roster matches the output.
- Chat is public to the selected group or guild. The host can see the question data and is the referee, and can choose whether to participate.
- Both pacing modes normally use the chat API, one line in flight, a short 0.35-second gap within each question block and two seconds between other announcements. Click-to-send fallback uses secure mouse-up macros. Neither sends during combat or actual chat lockdown. All pauses need the host to resume.
- If the API is unavailable, the client refuses output, or an echo is missing for eight seconds, the game pauses with click-to-send controls. **Resume game** resumes in that fallback. **Retry auto send** explicitly retries automatic delivery. There are no automatic retry loops. The client may still report a refused API call in its addon error UI.
- Click-to-send waits for an echo. After eight seconds, either retry a line that did not appear or use **I saw this line in chat: continue** if it is visibly present. That confirmation advances one pending line and can open the answer timer; use it only after checking the displayed line.
- Bare-number replies cannot identify which question a delayed message was intended for. Leave a gap before announcing the next question.
- Reloading ends the active game. Stopping or reloading before final announcements finish leaves saved records unchanged.
- Up to 1,000 recent player records are retained per client. Names and records stay in local SavedVariables unless the host announces or copies them.

Lua tests and staged-file checks do not prove chat permissions, rendering, event delivery or timing in either game client. See [client checks](docs/client-checks.md) before calling the build verified in game.

See [chat-bot interaction notes](docs/chat-bot-interactions.md) for the research and possible future modes.

## Development

Develop from this repository; client folders hold generated staging copies. HammerCore is vendored under `Libs/HammerCore`. Its curated question JSONL and category-file generator live in the HammerCore source repository. Change the shared source, then vendor it through HammerCore's sync tool.

Shipped category files are lightly obfuscated, including questions, choices and source links. They decode locally on load; this deters casual Lua browsing, not determined extraction. Readable JSONL stays in the maintainer source and is excluded from client staging.

The game engine in `Game.lua` has no WoW calls. `Host.lua` owns chat, identity, roster and secure UI integration; `Setup.lua` builds the Host game screen's game form; `Options.lua` owns general record management. The clock and random source are injectable for tests.

```sh
docker run --rm -v "$PWD:/r:ro" -w /r nickblah/lua:5.1-alpine sh -c 'find . -name "*.lua" -not -path "./.git/*" -print0 | xargs -0 -n1 luac -p && for test in tests/test_*.lua; do lua "$test" || exit 1; done'
python3 ../HammerCore/tools/toc_check.py .
python3 ../HammerCore/tools/check.py .
```

See [development state](docs/development-state.md) for what has and hasn't been checked in the game clients.

## Licence

Loreforge code is GPL v3, see [LICENSE.txt](LICENSE.txt). Embedded transport libraries retain their own public-domain or zlib terms; see [third-party notices](Libs/TRANSPORT-NOTICES.md). Loreforge's host engine and interface are original code. Blizzard's built-in book icon is referenced by its game path. There is no external artwork dependency.

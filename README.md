# Loreforge

**Group and guild trivia, hosted from one window.**

_You have considered reading the quest text. Now make everyone else prove it._

Loreforge is in beta for Retail and WoW Forever. The host picks Party, Raid, Instance or Guild output, categories, difficulty, game length and pacing. Other players answer with a number in chat; they don't need the addon.

## What it does

- **One main window.** `/lf` opens Loreforge with three tabs: **Play** for setup and the live game, **History** for finished games and **Hall of Fame** for saved player records.
- **Quick setup.** **Quick**, **Standard** and **Marathon** presets set the length in one click, and the summary line shows the question count, an estimated time in minutes and how many players are in the channel. Each category shows how many questions it has. The start countdown is visible in setup; pacing and chat options sit under **Advanced options**.
- **Host-paced or auto-advance games.** Questions, choices and results post automatically in both modes. Host-paced games wait at **Ask next question**; auto-advance continues after a short gap. The pacing switch changes mode mid-game.
- **The host plays along** by default, answering by click, chat or an answer key. **Practice solo** runs a private game that posts nothing to chat.
- **Separate answer lines.** The question posts first, then each numbered choice on its own line. **Choices on one line** under Advanced options enables the compact layout.
- **Numbered answers.** Each player's first valid `1`, `2`, `3` or `4` locks their attempt. Correct answers earn one point; joint winners share the win.
- **Round and overall scores**, live streaks, named recaps and personal-best callouts.
- **Ready checks**, an inactivity pause, and closing records for the top three players.
- **History and Hall of Fame.** Every finished game on this client is kept with its standings, including Party games you joined. The Hall of Fame ranks players by wins, with accuracy and best streak.
- **Sound cues and answer keys.** Optional sounds for invitations, new questions, the last five seconds, results and the finish. Bind **Answer 1** to **Answer 4** under Key Bindings > AddOns > Loreforge.
- **The same HammerCore interface** as the other Consecrated Hammer addons: settings, commands, minimap button, diagnostics and About page.

## Getting started

1. Join a party, raid, instance group or guild and open `/lf`. Ungrouped, the main button is **Practice solo**.
2. Pick a preset or set the rounds, questions and answer time yourself, then choose categories and difficulty. Fresh settings select your current group's channel. If the channel doesn't match your group, the banner says so and **Use current group** fixes it. For Guild, **Refresh guild roster** updates the cached players.
3. Click **Start game**. With Party output in Retail, the button is **Open lobby** first: players with Loreforge can join, the lobby shows who has, and **Start game** begins.
4. The start countdown defaults to 30 seconds. Set **Start countdown** from 5 to 60 seconds, or disable **Countdown before starting** to skip it. The ready check posts. Players can type `ready`, `ready!`, `rdy` or `I'm ready`. **Start questions now** starts early. **Refresh players** adds anyone who joined the group since; enrolment is fixed once questions begin.
5. Each question posts with its choices. Players answer `1` to `4` in chat. The board shows who has answered, and the timer turns amber and then red as time runs out.
6. Results post when time runs out, with the correct answer tinted. In host-paced mode, click **Ask next question** when everyone's ready.
7. Final scores post, records save and the main button becomes **New game**.

Closing the window doesn't stop the game; `/lf` opens it again. **Stop game** asks first. Pausing, combat or a group change voids an open question; resuming asks it again with a fresh timer.

If a line may not have posted, the game pauses and one banner asks whether it appeared: **Yes, it posted** continues, **Post again** prepares it for you to post by hand. **Retry automatic posting** turns automatic posting back on.

## Commands

| Command | What it does |
| --- | --- |
| `/loreforge` or `/lf` | Open Loreforge, or the Party game you joined |
| `/lf host` | Open game setup |
| `/lf records` | Open the Hall of Fame |
| `/lf history` | Open your game history |
| `/lf settings` | Open general settings |
| `/lf quiz` | Play HammerCore's solo quiz |

Every Consecrated Hammer addon also has `help`, `version`, `about`, `debug`, `startup`, `minimap` and `reset settings`. Reset settings keeps Loreforge's player records and history. Records are shared by host characters on the same WoW account, with Retail and Forever stored separately.

The minimap button opens Loreforge on left-click and general settings on right-click. Settings holds sound, window sizes, Party invitations, record clearing and the standard pages; **Back to game** returns to the main window.

## Categories

The bank has 1,000 questions across General lore, Geography, Classes and mechanics, Races, Hallow's End, Boss quotes, Famous Last Words, Murlocs and Mischief, Dubious Goblin Engineering, and Things You Probably Vendored. That includes 103 boss quotes, 340 geography questions and 181 class questions. Tags overlap, so category totals exceed the bank size.

Retail can draw 861 questions and Forever 499. There are 308 hard questions across the full bank. Each client still needs enough matching questions for the host's chosen categories and game length.

Selected categories combine. **Easier**, **Hard** and **Mixed** select the difficulty. The actual client controls which questions are eligible; `classic` in the data specifically means WoW Forever. Hosted games draw from every class and race topic, while the solo quiz keeps its character-specific filters.

## Limits and client checks

- Party, Raid, Instance and Guild chat are supported. Instance means a queued instance group; being inside a dungeon with a premade party does not by itself create one. When an instance group is active, use Instance rather than a separate home Party/Raid so the roster matches the output.
- Chat is public to the selected group or guild. The host can see the question data and is the referee, and can choose whether to participate.
- Both pacing modes normally use the chat API, one line in flight, a short 0.35-second gap within each question block and two seconds between other announcements. Click-to-send fallback uses secure mouse-up macros. Neither sends during combat or actual chat lockdown. All pauses need the host to resume.
- If the API is unavailable, the client refuses output, or an echo is missing for eight seconds, the game pauses and switches to manual posting. There are no automatic retry loops. The client may still report a refused API call in its addon error UI.
- Manual posting waits for each echo. **Yes, it posted** advances exactly one pending line and can open the answer timer; use it only after checking the line in chat.
- Bare-number replies cannot identify which question a delayed message was intended for. Leave a gap before announcing the next question.
- Reloading ends the active game. Setup then reports where it stopped and can post the standings so far. Stopping or reloading before final announcements finish leaves saved records unchanged.
- Up to 1,000 recent player records are retained per client. Names and records stay in local SavedVariables unless the host announces or copies them.

Lua tests and staged-file checks do not prove chat permissions, rendering, event delivery or timing in either game client. See [client checks](docs/client-checks.md) before calling the build verified in game.

See [chat-bot interaction notes](docs/chat-bot-interactions.md) for the research and possible future modes.

## Party player beta

With 0.2.0-beta or later on the host and addon participants, choose Party
output and **Open lobby**. Players get an invitation near the top of the
screen with **Join quiz** and **Decline**, then the host clicks **Start game**.
Use `/lf` to reopen a pending invitation. Invitations appear above the main window and also print a chat notice. `/lf debug` includes Party delivery and window errors if no prompt appears.
Joined players get clickable questions, confirmed answer locking, tinted
reveals, streaks, shared scores and a finish headline. Chat-only players can
still answer normally. `/lf play` restores a joined game and `/lf history`
opens your history.

This beta uses Retail home Parties, including premade Parties in dungeons
when combat and activity restrictions are inactive. Queued Instance groups,
raids and Forever player UI remain unsupported. The dungeon transport probe has passed; the
complete player flow still needs an in-game test. See [Party player
behaviour and protocol](docs/party-client.md).

## Development

Develop from this repository; client folders hold generated staging copies. HammerCore is vendored under `Libs/HammerCore`. Its curated question JSONL and category-file generator live in the HammerCore source repository. Change the shared source, then vendor it through HammerCore's sync tool.

Shipped category files are lightly obfuscated, including questions, choices and source links. They decode locally on load; this deters casual Lua browsing, not determined extraction. Readable JSONL stays in the maintainer source and is excluded from client staging.

The game engine in `Game.lua` has no WoW calls. `Host.lua` owns chat, identity, roster and the main window's live game; `Setup.lua` builds the Play tab's setup and lobby; `History.lua` builds the History and Hall of Fame tabs; `Player.lua` is the joined player's window; `Options.lua` holds the settings pages. The clock and random source are injectable for tests.

```sh
docker run --rm -v "$PWD:/r:ro" -w /r nickblah/lua:5.1-alpine sh -c 'find . -name "*.lua" -not -path "./.git/*" -not -path "./.scratch/*" -print0 | xargs -0 -n1 luac -p && for test in tests/test_*.lua; do lua "$test" || exit 1; done'
python3 ../HammerCore/tools/toc_check.py .
python3 ../HammerCore/tools/check.py .
```

See [development state](docs/development-state.md) for what has and hasn't been checked in the game clients.

## Licence

Loreforge code is GPL v3, see [LICENSE.txt](LICENSE.txt). Embedded transport libraries retain their own public-domain or zlib terms; see [third-party notices](Libs/TRANSPORT-NOTICES.md). Loreforge's host engine and interface are original code. Blizzard's built-in book icon is referenced by its game path. There is no external artwork dependency.

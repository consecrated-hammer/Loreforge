# Loreforge

**Trivia for your party, raid or guild.**<br>_You are not prepared! (For question seven)_

[![Retail](https://img.shields.io/badge/retail-supported-4c9a7a?style=flat-square)](https://www.curseforge.com/wow/addons/loreforge) [![WoW Forever](https://img.shields.io/badge/wow%20forever-supported-4c9a7a?style=flat-square)](https://www.curseforge.com/wow/addons/loreforge) [![Release](https://img.shields.io/github/v/release/consecrated-hammer/Loreforge?style=flat-square&color=4c9a7a&label=release)](https://github.com/consecrated-hammer/Loreforge/releases) [![License](https://img.shields.io/badge/license-GPL--3.0-4c9a7a?style=flat-square)](https://github.com/consecrated-hammer/Loreforge/blob/main/LICENSE.txt)

[![Discord](https://img.shields.io/badge/discord-join-5865F2?style=flat-square&logo=discord&logoColor=white)](https://discord.gg/z3xKxRygDc) [![GitHub](https://img.shields.io/badge/github-source-6e7681?style=flat-square&logo=github&logoColor=white)](https://github.com/consecrated-hammer/Loreforge) [![Buy Me a Coffee](https://img.shields.io/badge/buy%20me%20a%20coffee-support-FFDD00?style=flat-square&logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/consecratedhammer)

Questions, bugs or ideas? Come say hi on the [Consecrated Hammer Discord](https://discord.gg/z3xKxRygDc). Bug reports go in `#bug-reports`, or you can open a [GitHub issue](https://github.com/consecrated-hammer/Loreforge/issues).

---

Loreforge runs on Retail and WoW Forever. The host picks Party, Raid, Instance or Guild output, categories, difficulty, game length and pacing. Other players answer with a number in chat; they don't need the addon.

**Better with LibTaxiData.** Install the free
[LibTaxiData](https://www.curseforge.com/wow/addons/libtaxidata) library and
the Flight challenge counts down to landing from your very first flight.
Without it, Loreforge learns each route's time the first time you fly it and
shows "Until you land" until then. LibTaxiData has no WoW Forever release
yet, so on Forever Loreforge learns as you go. Settings > Troubleshooting
shows whether it's installed and has a **Get LibTaxiData** link.

## What it does

- **One main window.** `/lf` opens Loreforge with three tabs: **Play** for setup and the live game, **History** for finished games and **Hall of Fame** for saved player records.
- **Quick setup.** **Quick**, **Standard** and **Marathon** presets set the length in one click, and the summary line shows the question count, an estimated time in minutes and how many players are in the channel. Each category shows how many questions it has. Setup is split into **Game**, **Categories** and **Pacing & chat** tabs, and reopens on the one you used last. The Party lobby gets its own tab while it's open.
- **Host-paced or auto-advance games.** Questions, choices and results post automatically in both modes. Auto-advance (the default) continues after a short gap; host-paced games wait at **Ask next question**. The pacing switch changes mode mid-game.
- **The host plays along** by default, answering by click, chat or an answer key. **Practice solo** runs a private game that posts nothing to chat.
- **Separate answer lines.** The question posts first, then each numbered choice on its own line. **Choices on one line** on the Pacing & chat tab enables the compact layout.
- **Numbered answers.** Each player's last valid `1`, `2`, `3` or `4` before time's up counts, so a mis-click can be fixed. Correct answers earn one point; joint winners share the win.
- **Optional themed rounds**, where each round sticks to one category.
- **Live scores**, recaps every five questions in a plain game, streaks, named recaps and personal-best callouts.
- **Ready checks**, an inactivity pause, and closing records for the top three players.
- **Clear game results.** A dedicated completion view names the winner or shared win, shows your result and final standings, and keeps the last question out of the way.
- **History and Hall of Fame.** Every finished game on this client is kept with its standings, including Party games you joined. The Hall of Fame ranks players by wins, with accuracy and best streak.
- **Sound cues and answer keys.** Optional sounds for invitations, new questions, the last five seconds, results and the finish. Bind **Answer 1** to **Answer 4** under Key Bindings > AddOns > Loreforge.
- **The same HammerCore interface** as the other Consecrated Hammer addons: settings, commands, minimap button, diagnostics and About page.

## Quick play

A small solo quiz card for flights and idle moments, with no setup and
nothing posted to chat. Open it with `/lf quick`, the **Quick play** button on
the Play tab, the minimap button's right-click menu, or a key bound under Key
Bindings.

| Mode | How it works |
| --- | --- |
| Quick play | Endless questions. Timed unless Relaxed is on |
| Streak | Keep going until your first miss |
| Lightning | As many as you can in 60 seconds (30 to 180 on the settings page) |
| Flight challenge | As many as you can before you land. Only on flights |

- The question's category painting sits beside it, with the category name
  across the bottom.
- **Against the clock or Relaxed** switches the per-question timer for Quick
  play and Streak.
- The gear on the card slides out an **Options** tab: mode, timer, look
  (Artwork, Animations, Card size) and flights.
- **On flights**, Loreforge asks "Fancy a question?" when you take off. It
  can start a Flight challenge straight away instead, or stay quiet. The
  countdown to landing comes from LibTaxiData if it's installed, then from
  the real time once you've flown the route.
  Flights picked from a flight master's chat, like the druid flight out of
  Moonglade, count too; with no flight map there's no time to show, so the
  clock reads "Until you land".
- **Landing grace** gives you 10 seconds after landing to finish the open
  question (0 ends it on landing). Then it's Touchdown! with your flight
  score, and **Close on landing** closes the card. **Keep going** stays open.
  Dismiss the card while flying to leave a small book icon. Click it to resume
  the same quiz or start a new Flight challenge. Quiz timers pause while hidden;
  the flight continues. Landing removes the icon and clears the dismissed quiz.
- **Flight answer pause** sets how long each answer shows during a Flight
  challenge (3 seconds by default). Lightning keeps its quick flash.
- Personal bests (best streak, best Lightning, best flight with its route
  and date) show on the card and in the Hall of Fame.
- Quick play uses the categories and difficulty from game setup. It works
  through every matching question before repeating one.
- Everything is on the **Quick play** settings page.

## Daily question and welcome

The daily is one question a day, one try and no timer. Open `/lf daily`, use
the **Daily question** button on Play, or pick it from the minimap menu. The
server's calendar date picks the question. Everyone with the same question
bank on a client gets the same one; Retail and Forever get different picks.
Both clients' picks stay out of the running for the next 60 days.
Question-bank updates can also shift later picks through that exclusion window,
so matching daily questions assumes the same bank version.

A correct answer on consecutive days grows your daily streak; a wrong answer
or a missed day resets it. Today's answer and the best streak are shared
across characters on the same client. The card shows **Daily #N**.
After answering, it shows the
right answer, your streak and when the next question arrives. Daily question
and Offer at login are separate settings on Quick play.

The welcome window lets you choose **Ask me**, **Auto-start** or **Off** for
flights, and whether to offer the daily at login. Closing it keeps the
defaults. Updating players see the new choices once. `/lf setup` opens it
again, and **Setup on new features** controls future automatic welcomes.

## Getting started

1. Join a party, raid, instance group or guild and open `/lf`. When solo, **Quick play** leads, with **Practice solo** beside it. **Main button when solo** can put Practice solo first instead.
2. Pick a preset or set the questions, themed rounds and answer time yourself, then choose categories and difficulty. Fresh settings select your current group's channel. If the channel doesn't match your group, the banner says so and **Use current group** fixes it. For Guild, **Refresh guild roster** updates the cached players.
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
| `/lf quick` | Open or close Quick play |
| `/lf daily` | Open today's daily question or its completed result |
| `/lf setup` | Reopen the welcome choices |
| `/lf records` | Open the Hall of Fame |
| `/lf history` | Open your game history |
| `/lf settings` | Open general settings |
| `/lf quiz` | Play HammerCore's solo quiz |

Every Consecrated Hammer addon also has `help`, `version`, `about`, `debug`, `startup`, `minimap` and `reset settings`. Reset settings keeps Loreforge's player records and history. Records are shared by host characters on the same WoW account, with Retail and Forever stored separately.

The minimap button opens Loreforge on left-click. **Minimap left-click when solo** can open Quick play instead. Right-click opens the shared HammerCore menu with settings, the Hall of Fame, the daily and each Quick play mode. Settings holds search, sound, window sizes, Party invitations, record clearing and the standard pages; **Back to game** returns to the main window.

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

## Party play (beta)

On Retail, party members with Loreforge can join the game properly instead of
typing numbers. Choose Party output and click **Open lobby**. Players get an
invitation with **Join quiz** and **Decline**, and once everyone's in you click
**Start game**. Joined players get clickable answers, locked-in answers,
streaks and shared scores. Anyone without the addon still answers in chat as
usual.

It works in Retail home Parties, including premade Parties in dungeons outside
combat. Raids, queued Instance groups and WoW Forever aren't supported yet.
`/lf` reopens a pending invitation, `/lf play` gets you back into a joined game,
and `/lf debug` helps if an invitation doesn't show up.
[Party player behaviour and protocol](docs/party-client.md) has the technical
detail.

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

Loreforge code is GPL v3, see [LICENSE.txt](LICENSE.txt). Embedded transport libraries retain their own public-domain, zlib or MIT terms; see [third-party notices](Libs/TRANSPORT-NOTICES.md). Loreforge's host engine and interface are original code. Blizzard's built-in book icon is referenced by its game path. There is no external artwork dependency.

# Chat-bot interaction references

Checked 2026-10-24. These are interaction references, not code dependencies.
Loreforge's implementation is original; no external bot code was copied.

[Inquisitor's player manual](https://docs.inquisitor-trivia.me/player/) describes
named correct-answer messages, running scores, streaks, speed records and
personal statistics. It also has progressive hints, runner-up recognition and
collaborative multi-answer rounds. The useful fit here is a short social recap
with a visible streak milestone. Loreforge now announces every correct player
with their running score, streaks of two or more, and the first new streak
record in that game.

[Red's trivia documentation](https://docs.discord.red/en/stable/cog_guides/trivia.html)
provides category combinations, answer reveals, leaderboards and a timeout for
games without responses. Loreforge now has a configurable pause after consecutive
questions without replies, defaulting to three. Any valid answer, including a
wrong one, resets the inactivity count. The Game Master resumes play.

[WoW TriviaBot](https://www.curseforge.com/wow/addons/trivia-bot) documents output
selection, adjustable announcement intervals, reporting options and whispered
help commands. Its listed release is from 2019, so it is an interaction reference
rather than proof of current Retail/Forever chat APIs. Loreforge supports Party,
Raid, Instance and Guild output, host-paced or auto-advance pacing, and an adjustable
gap after all results have appeared.

Useful future options are player-requested `!score` and `!top` responses,
weekly leaderboards, fastest-correct recognition, a free-text mode with
progressive hints, and collaborative questions where the group finds several
answers. Those are research candidates, not features in this build. The current
game awards one point to each correct player within the answer window.

Automatic mode keeps one line in flight, spaces sends by at least two seconds
and waits for exact own-chat echoes. API refusal or a missing echo pauses the
game with manual controls available. Combat and restricted gameplay pause both
modes until the host resumes. These limits follow the live client's rules;
they do not establish that every client permits automated chat.

Both pacing modes now use automatic chat delivery. Host-paced games wait at
Ask next question between questions. Click-to-send is an explicit fallback for
refused sends, with visible-line confirmation available only through a host
action after eight seconds.

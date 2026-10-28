# Probe transport

The 0.1.1-beta probe uses ChatThrottleLib 32 for shared bandwidth scheduling
and LibDeflate 1.0.2-release for compression and WoW addon-channel encoding.
[Sources and licence notices](../Libs/TRANSPORT-NOTICES.md) ship with the addon.
The libraries are unmodified. AceComm isn't included because its licence's
standalone redistribution restriction raises a GPLv3 compatibility issue.
Loreforge's existing bounded framing handles the multi-message question.

`Transport.lua` retains its probe singleton and can create isolated instances.
The 0.2.0-beta [Party client](party-client.md) uses a separate instance,
prefix and rolling budgets; the limits below describe the original probe. Both players need the new build; dev11 and
the public 0.1.0-beta probe use a different wire format. Prefix `LoreforgeP2`
separates them. Silent old clients don't count as a successful test.

## Wire and receive bounds

Each existing probe protocol packet is at most 240 plaintext bytes. The wire
starts with `2D` for DEFLATE or `2R` for raw data, followed by LibDeflate's
addon-channel encoding. Compression is used only when it saves bytes. Encoded
packets must fit one 255-byte addon message; the question still uses at most
sixteen UTF-8-safe 180-byte payload chunks, with length and checksum checks.
Both host peers and listener sessions are capped at eight. These are storage
limits, not a promise that every peer can finish within one shared send budget.
The normal sample uses two question chunks; the maximum chunk count is an
input-validation bound.

Receivers must be armed. They queue at most 24 packets per run/listen window,
filter self-echoes before spending the decode budget, process one per 100ms
probe tick and discard oversized, malformed or old wire
formats. Compressed input is capped at 200 bytes before inflation. Decompressed
results over 240 bytes or with trailing compressed bytes are rejected.
**The 240-byte check is an acceptance limit, not a temporary allocation cap.**
Upstream LibDeflate constructs the output first; the small compressed-input
cap bounds possible DEFLATE expansion and the decode budget bounds repeated
work. It isn't a general-purpose large-payload transport.

## Dispatch and cancellation

Only one packet is handed to ChatThrottleLib at a time. The adapter uses
CTL v32's `Enqueue` message schema so its own dispatch function runs before
every native send, including throttle retries. That function checks the probe
generation, active window, packet deadline, combat, restrictions, chat lockdown
and the 24-wire-attempt budget. Retries count as attempts. CTL's callback
reports its normalized send result, not proof of remote receipt.

Stop, completion, zoning, roster changes and restriction events cancel the
probe and its local queues. Cancelled packets already in CTL remain there
until CTL drains them; their guarded function makes no native send. Other
addons' queues and Blizzard's global sender are untouched. CTL upgrades require
reviewing this internal schema. An unexpected shared CTL version disables this
adapter without changing the ordinary trivia game. A third-party fork that
reuses version 32 still needs compatibility testing; the version check cannot
authenticate another addon's code. Starting or arming while a cancelled CTL
packet is still draining reports that condition and asks the user to retry.
Rejected submission stops the probe with a reason instead of silently losing
a queued frame. Asynchronous native send rejections also stop it with the
reported result. An enqueue error clears pending state and disables the adapter
until reload, preventing repeated submission into a broken queue. The 45-second run deadline is a hard cutoff, so acknowledgments
arriving after it cannot turn an incomplete run into a pass.

## Checks and remaining proof

`tests/test_transport.lua` loads the real pinned libraries in two independent
Lua environments using each TOC's dependency order. It exercises UTF-8,
bidirectional delivery, compression, receive limits, malformed data, queued
cancellation, retry budgets, shared-library version checks and unrelated
traffic. `tests/test_probe.lua` covers the probe handshake and result rules.

These are offline tests. Use check 15 in [client checks](client-checks.md) for
a consenting two-player run on each client and distribution. API success,
self-echo and these tests do not prove delivery in WoW. Start with open-world
Party; test premade instances, queued Instance, Raid, Guild and Forever
separately. The Party player implementation now follows the successful paired
Retail probe. Its full-game verification remains separate.

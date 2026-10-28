# Changelog

## [Unreleased]

## [0.1.1-beta] - 2026-10-28

- The development transport probe now uses ChatThrottleLib throttling and LibDeflate compression/encoding, with a new wire prefix. Both test players need this build.
- Probe send failures now stop with a diagnostic. Probe queues stop on combat, restrictions, zoning or roster changes. Wire retries, incoming decoding, peer counts and question chunks are bounded.

Both test players need 0.1.1-beta for `/lf probe`. This updates the development
transport test; the player question UI and shared history are not implemented.
Real two-client delivery remains unverified on Retail and WoW Forever.

## [0.1.0-beta] - 2026-10-28

First public beta. Loreforge hosts trivia in group or guild chat, and only the
host needs the addon.

### Added

- Host-paced or auto-advancing trivia in Party, Raid, Instance or Guild chat.
  Players answer `1` to `4` in chat.
- Categories and difficulty drawn from HammerCore's shared question bank, with
  separate question pools for Retail and WoW Forever.
- First-answer locking, round and overall scores, shared wins, streaks and
  personal-best callouts.
- An optional ready check and countdown, an inactivity pause, and optional
  Game Master participation with clickable answers.
- Local player records for each client, with optional end-of-game
  announcements and confirmed clearing.
- A click-to-send fallback when the client refuses automatic chat output.
- HammerCore settings, minimap button, standard commands, diagnostics and
  About page.

This is a beta. Chat delivery, timing and rendering haven't been fully checked
in either game client yet.

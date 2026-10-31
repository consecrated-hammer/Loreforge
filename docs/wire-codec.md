# Party wire codec

PartyBus uses LibSerialize minor 7 for smaller packets between compatible
participants. `Codec.lua` still owns saved result text, canonical comparisons
and legacy packets. SavedVariables need no migration.

## Compatibility

Every application message advertises `wireCodec=2` when the inspected runtime
library is available. Invite, join and sync packets always use frame version 1.
Capability is learned after the existing sender/session/admission checks.
Frame version 2 is selected only for a nonempty explicit recipient set whose
members all advertised support for that session. Unknown, older or unsupported
runtime versions use frame 1. Session changes and departures invalidate support.
A downgrade cancels queued binary transfers and requeues their immutable payloads
with new packet IDs in the legacy format, preserving queue order and expiry.
A transfer never changes format midway.

All packets still broadcast on PARTY with prefix `LoreforgeM1`. Older
nonrecipients can see binary frames but discard them in their frame parser.
Neither version provides privacy, authentication or protection against a
modified host. The probe protocol is unchanged.

## Bounds and upstream library

`WireCodec.lua` performs a bounded grammar preflight before upstream decoding.
It accepts one table root, consumes all input, limits nesting to eight, each
table to 128 entries, strings to 4096 bytes and logical nodes to 8192 (including
implicit array keys). Both binary and expanded canonical sizes must fit 32 KiB.
Integers stay within ±10¹², with string keys or integer keys 1 through 1000.
Duplicate keys and mixed array/map collisions are rejected.

Backward string references are supported; table references, cycles, shared
tables, nil and floating-point encodings are rejected, except the library's
explicit negative-zero encoding. Outbound unsupported encodings fall back to
legacy packets. Malformed inbound binary is dropped without a legacy retry.
The bounded-depth preflight checks before descending, and the upstream reader
also checks every requested byte range; the decoded result is checked against
the canonical codec policy as well. Application schemas remain in Party.lua.

The adapter only uses runtime LibSerialize minor 7. LibStub can select a copy
from another addon; other minors disable binary use. This guard cannot
authenticate a modified library that reports the same minor. The bundled source and MIT
licence are unmodified and pinned in `Libs/transport-vendor.json`; both TOCs and
the packager include them. The existing LibDeflate temporary-expansion limitation
is unchanged. There is no AceComm dependency.

## Local measurement, 2026-10-31

Run `lua tools/benchmark_wire_codec.lua` from the checkout. It captures real
integration-game messages, then compares the canonical and binary encodings
through the production 160-byte framing, compression and addon-channel encoder.
Bootstrap rows are hypothetical binary comparisons; actual bootstrap sends stay
legacy. Results vary with message content and sender/packet IDs.

| Payload | Serialized bytes, legacy → binary | Frames | Native wire bytes |
| --- | --- | --- | --- |
| Question/state snapshot | 1013 → 619 | 7 → 4 | 1011 → 698 |
| Completed result | 1157 → 508 | 8 → 4 | 1056 → 594 |
| Maximum result, five players/twenty rounds | 25869 → 4791 | 162 → 30 | 16644 → 2655 |

Measured encode/decode pairs took about 0.3 → 0.9 ms for a snapshot and
3.4 → 11.2 ms for the maximum result in local Lua 5.1. These include adapter
policy checks, not rendering, scheduling or network time. Heap allocation and
native client timing have not been profiled. The benchmark verifies canonical
round-trip equality. This is packet-efficiency evidence, not proof of in-game
latency or synchronized rendering.

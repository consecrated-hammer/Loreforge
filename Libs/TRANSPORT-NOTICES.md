# Embedded transport libraries

Loreforge's own code remains GPLv3. These embedded libraries retain their
upstream terms and attribution. No Zygor source is included.

| Component | Upstream revision | Terms retained in the package |
| --- | --- | --- |
| LibStub 2 | [Ace3 ac3d122](https://github.com/WoWUIDev/Ace3/tree/ac3d1225037e0dc74e025a72342c0f7824aae147/LibStub) | Public-domain declaration and contributor credits in `LibStub/LibStub.lua`. |
| ChatThrottleLib 32 | [Ace3 ac3d122](https://github.com/WoWUIDev/Ace3/blob/ac3d1225037e0dc74e025a72342c0f7824aae147/AceComm-3.0/ChatThrottleLib.lua) | Public-domain declaration and Mikk attribution in `ChatThrottleLib/ChatThrottleLib.lua`. |
| LibDeflate 1.0.2-release | [afc3b78](https://github.com/SafeteeWoW/LibDeflate/tree/afc3b78d12fb3bcfa6b21e5332031ad3d7572e19) | zlib licence, copyright and credits in `LibDeflate/LibDeflate.lua` and `LibDeflate/LICENSE.txt`. |

All four source/notice files are unmodified upstream copies. Their SHA-256
hashes are recorded in `transport-vendor.json` and checked by
`tools/check_transport_vendor.py` in CI. These notices and the manifest ship
inside the addon; implementation docs and tests do not. The `.pkgmeta`
`plain-copy` entries preserve these upstream directories during packaging,
including LibDeflate's literal project-metadata placeholders.

AceComm and CallbackHandler are deliberately excluded. Their Ace3 licence
adds a standalone redistribution restriction, which raises a compatibility
issue with GPLv3. Including them would need a separate licensing decision;
Loreforge currently makes no Ace3 linking exception.

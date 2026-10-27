-- Lightweight obfuscation only. Both the decoder and packed data ship locally.
-- Curated readable source and provenance live in data/quiz/*.jsonl, not clients.
local _, ns = ...
local HC = ns.HammerCore
HC.QUIZ = {}

function HC.DecodeQuiz(seed, encoded)
    local bytes, state = {}, seed
    for i = 1, #encoded, 2 do
        state = (state * 73 + 41) % 65521
        bytes[#bytes + 1] = string.char((assert(tonumber(encoded:sub(i, i + 1), 16)) - state % 256) % 256)
    end
    local text, cursor, fields = table.concat(bytes), 1, {}
    for i = 1, 12 do
        local colon = assert(text:find(":", cursor, true), "invalid packed question")
        local size = assert(tonumber(text:sub(cursor, colon - 1)), "invalid packed field length")
        assert(size >= 0 and size == math.floor(size) and colon + size <= #text, "invalid packed field")
        fields[i] = text:sub(colon + 1, colon + size)
        cursor = colon + size + 1
    end
    assert(cursor == #text + 1, "trailing packed question data")
    local entry = { fields[1], fields[2], fields[3], fields[4], fields[5],
        id = fields[6], era = fields[7], difficulty = fields[8], source = fields[11], categories = {} }
    if fields[9] ~= "" then entry.class = fields[9] end
    if fields[10] ~= "" then entry.race = fields[10] end
    for category in fields[12]:gmatch("[^,]+") do entry.categories[#entry.categories + 1] = category end
    return entry
end

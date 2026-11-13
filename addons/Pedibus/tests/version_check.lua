-- Version obsolète : celui qui est en retard est prévenu une fois, le panneau dit qui doit mettre à jour.
-- Lancer depuis le dossier de l'addon : node tests/run.js tests/version_check.lua
local W = dofile("tests/wow.lua")
local FILES = W.files()
local GROUP = { "Alice", "Bob", "Cara" }
local alice, bob, cara = W.client("Alice", GROUP), W.client("Bob", GROUP), W.client("Cara", GROUP)
alice.version, bob.version, cara.version = "1.9", "1.10", "1.9" -- 1.10 est bien plus récente que 1.9
for _, c in ipairs({ alice, bob, cara }) do W.load(c, FILES) end
local function step(s) W.advance(s or 1) end
local function count(c, pattern)
    local n = 0
    for _, l in ipairs(c.out) do if l:find(pattern) then n = n + 1 end end
    return n
end
local function tagOf(c, who)
    for _, f in ipairs(c.frames) do if f.who == who and f._shown then return f.tag._text end end
end

for _, c in ipairs({ alice, bob, cara }) do W.fire(c, "PLAYER_ENTERING_WORLD") end
step(8)
assert(count(alice, "Pedibus 1%.10 est sorti %(Bob l'a%)") == 1, "Alice n'est pas prévenue de la 1.10")
assert(count(bob, "est sorti") == 0, "Bob a la plus récente : pas de message")
alice.env.SlashCmdList.PEDIBUS("debug"); step(8) -- relance un « qui a Pedibus ? »
assert(count(alice, "est sorti") == 1, "le message ne doit venir qu'une fois")

alice.env.PedibusToggle(); bob.env.PedibusToggle(); step(1)
assert(tagOf(alice, "Bob") == "v1.10 (plus récente)", "tag chez Alice : " .. tostring(tagOf(alice, "Bob")))
assert(tagOf(bob, "Alice") == "à mettre à jour", "tag chez Bob : " .. tostring(tagOf(bob, "Alice")))
assert(tagOf(alice, "Cara") == "", "même version : pas de tag")
print("version ok")

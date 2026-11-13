-- Mode démo : chaque scène figée affiche bien ce qu'on veut sur la capture.
-- Lancer depuis le dossier de l'addon : node tests/run.js tests/demo_check.lua
local W = dofile("tests/wow.lua")
local c = W.client("Moi", { "Moi" }) -- personne d'autre en vrai
local ns = {}
assert(loadfile("demo/Demo.lua", "t", c.env))("Pedibus", ns)
for _, f in ipairs(W.files()) do assert(loadfile(f, "t", ns.env))("Pedibus", ns) end -- comme setfenv en jeu
c.ns = ns
local function step(s) W.advance(s or 1) end
local function shows(text)
    for _, f in ipairs(c.frames) do
        local ok = (f._kind == "FontString" or f._kind == "Button") and f:IsVisible()
        if ok and tostring(f._text):find(text, 1, true) then return true end
    end
end
local function scene(name) c.env.SlashCmdList.PEDIBUSDEMO(name); step(3) end
assert(ns.L["Monter"] == "Board", "le mode démo devrait forcer l'anglais")
W.fire(c, "PLAYER_ENTERING_WORLD"); step(6)

scene("bus")
assert(shows("· 4 aboard") and shows("33 m"), "bus : pas 4 passagers")
scene("stop")
assert(shows("2/4 done"), "stop : pas 2/4")
step(120)
assert(shows("2/4 done"), "stop : la scène devrait rester figée")
scene("poker")
for _, t in ipairs({ "Royal flush", "Call 80", "Raise to 160", "Pot: 480", "All-in 1180", "Your turn.", "folded" }) do
    assert(shows(t), "poker : manque « " .. t .. " »")
end
scene("yams")
for _, t in ipairs({ "roll 1/3", "Brakka", "Lunara", "50", "35" }) do assert(shows(t), "yams : manque « " .. t .. " »") end
scene("c4")
assert(shows("You play yellow.") and shows("Your turn"), "c4 : pas mon tour")
scene("bubble")
assert(W.button(c, "Join") and shows("Lunara opened a game: Poker"), "pas de bulle")
scene("badge")
assert(shows("Brakka's bus") and shows("following"), "badge : pas dans le bus de Brakka")
scene("lost")
assert(W.said(c, "You're losing the bus!") and shows("You're losing the bus!"), "lost : pas d'alerte")
scene("hero")
assert(shows("aboard") and shows("Royal flush"), "hero : panneau + poker attendus")
c.env.SlashCmdList.PEDIBUSDEMO("")
print("demo ok")

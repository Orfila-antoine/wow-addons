-- Bataille navale, Puissance 4 et Yams entre deux passagers simulés.
-- Lancer depuis le dossier de l'addon : node tests/run.js tests/games_check.lua
local W = dofile("tests/wow.lua")
W.realm.Bob = "Gnomorettito" -- groupe inter-royaumes, comme en vrai
local FILES = W.files()
local GROUP = { "Alice", "Bob", "Cara" }
local alice = W.load(W.client("Alice", GROUP), FILES)
local bob = W.load(W.client("Bob", GROUP), FILES)
local cara = W.load(W.client("Cara", GROUP), FILES)
local function step(s) W.advance(s or 1) end
local function shows(c, pattern, plain)
    for _, f in ipairs(c.frames) do
        if f._kind == "FontString" and tostring(f._text):find(pattern, 1, plain) then return true end
    end
end

bob.ns.toggleGames(); cara.ns.toggleGames()

-- Bataille navale : chacun tire case par case jusqu'à la victoire ------------------------
W.button(bob, "Bataille"):Click(); W.button(cara, "Bataille"):Click()
W.button(bob, "Nouvelle bataille"):Click()
step()
W.button(cara, "Rejoindre la bataille de Bob"):Click() -- salle pleine : départ automatique
step()
W.button(bob, "Placer au hasard"):Click()
W.button(bob, "Prêt !"):Click(); W.button(cara, "Prêt !"):Click()
step()
alice.ns.toggleGames() -- Alice regarde la bataille
W.button(alice, "Bataille"):Click()
W.button(alice, "Regarder la bataille de Bob"):Click()
local function targets(c)
    local t = {}
    for _, f in ipairs(c.frames) do if f.cell and f._scripts.OnClick then t[#t + 1] = f end end
    assert(#t == 64, "64 cases de tir attendues, " .. #t)
    return t
end
local tb, tc = targets(bob), targets(cara)
local over = false
for i = 1, 64 do
    tb[i]:Click(); step()
    if shows(bob, "Victoire") then over = true; break end
    tc[i]:Click(); step()
    if shows(cara, "Victoire") then over = true; break end
end
assert(over, "la bataille ne se termine pas")
assert(shows(bob, "a gagné") or shows(cara, "a gagné"), "le perdant ne voit pas la défaite")
assert(shows(alice, "Victoire de"), "la spectatrice ne voit pas la fin de la bataille")
W.button(alice, "Ne plus regarder"):Click()
W.button(bob, "Quitter"):Click(); W.button(cara, "Quitter"):Click()

-- Puissance 4 : Bob (rouge, commence) joue colonne 1, Cara colonne 2 -> Bob aligne 4 ------
local ns4 = {}
assert(loadfile("Connect4.lua"))("Pedibus", ns4)
local g = { {}, {}, {}, {}, {}, {}, {} }
g[1][1], g[2][2], g[3][3], g[4][4] = "x", "x", "x", "x"
assert(ns4.connect4Wins(g, 4, 4), "diagonale non détectée")
g = { { "x", "x", "x" }, {}, {}, {}, {}, {}, {} }
assert(not ns4.connect4Wins(g, 1, 3), "3 pions ne gagnent pas")

-- Cara a fermé les jeux : la bulle sous le bouton Pédibus lui propose la partie de Bob.
W.button(bob, "Puissance 4"):Click()
cara.env.PedibusGames:Hide()
W.button(bob, "Nouvelle partie de Puissance 4"):Click(); step()
assert(shows(cara, "Bob ouvre une partie : Puissance 4", true), "pas de bulle chez Cara")
assert(not pcall(W.button, bob, "Rejoindre"), "l'hôte ne doit pas avoir de bulle")
W.button(cara, "Rejoindre"):Click(); step() -- salle pleine : départ automatique
assert(cara.env.PedibusGames:IsShown(), "la bulle n'ouvre pas les jeux")
assert(not pcall(W.button, alice, "Rejoindre"), "la bulle d'Alice reste après le départ")
W.button(alice, "Puissance 4"):Click()
W.button(alice, "Regarder la partie de Puissance 4 de Bob"):Click()
local function column(cl, n)
    for _, f in ipairs(cl.frames) do if f.col == n then return f end end
end
for _ = 1, 4 do
    column(bob, 1):Click(); step()
    if shows(bob, "Gagné") then break end
    column(cara, 2):Click(); step()
end
assert(shows(bob, "Gagné") and shows(cara, "Bob a gagné"), "victoire verticale non vue des deux côtés")
assert(shows(alice, "Bob a gagné"), "la spectatrice ne voit pas la victoire")
W.button(alice, "Ne plus regarder"):Click()
W.button(bob, "Quitter"):Click(); W.button(cara, "Quitter"):Click()

-- Yams : Cara quitte le groupe pendant son tour, Bob doit pouvoir continuer --------------
W.button(bob, "Yams"):Click(); W.button(cara, "Yams"):Click()
W.button(bob, "Nouvelle partie de Yams"):Click(); step()
W.button(cara, "Rejoindre la partie de Yams de Bob"):Click(); step()
W.button(bob, "Commencer"):Click(); step()
W.button(bob, "Lancer"):Click(); step()
local cell
for _, f in ipairs(bob.frames) do if f.t and f._kind == "Button" then cell = cell or f end end
cell:Click(); step() -- Bob marque « As », c'est au tour de Cara
assert(shows(bob, "Tour de Cara"))
table.remove(GROUP, 3) -- Cara s'en va
W.fire(bob, "GROUP_ROSTER_UPDATE")
W.button(bob, "Lancer"):Click() -- Bob reprend la main tout seul
assert(shows(bob, "lancer 1/3"), "Bob ne peut pas rejouer après le départ de Cara")
print("games ok")

-- Poker : évaluation des mains, pots annexes, puis parties simulées à 3 joueurs.
-- Lancer depuis le dossier de l'addon : node tests/run.js tests/poker_check.lua
local W = dofile("tests/wow.lua")
W.realm.Bob = "Gnomorettito" -- groupe inter-royaumes, comme en vrai

-- Logique pure ---------------------------------------------------------------------------
local ns = { L = setmetatable({}, { __index = function(_, k) return k end }) } -- textes en français
assert(loadfile("Poker.lua"))("Pedibus", ns)
local P = ns.poker
local S, H, D, T = 1, 2, 3, 4 -- pique, cœur, carreau, trèfle
local function c(r, s) return (s - 1) * 13 + r - 1 end
local function ev(...) return P.evaluate({ ... }) end
local function beats(a, b) return P.compare(a, b) == 1 end

local royal = ev(c(14, S), c(13, S), c(12, S), c(11, S), c(10, S), c(2, H), c(3, D))
local quads = ev(c(9, S), c(9, H), c(9, D), c(9, T), c(14, S), c(2, H), c(3, D))
local full = ev(c(9, S), c(9, H), c(9, D), c(4, T), c(4, S), c(2, H), c(3, D))
local fullTwoTrips = ev(c(9, S), c(9, H), c(9, D), c(4, T), c(4, S), c(4, H), c(3, D))
local flush = ev(c(2, H), c(5, H), c(9, H), c(11, H), c(13, H), c(3, S), c(4, D))
local wheel = ev(c(14, S), c(2, H), c(3, D), c(4, T), c(5, S), c(9, H), c(11, D))
local six = ev(c(6, S), c(2, H), c(3, D), c(4, T), c(5, S), c(9, H), c(11, D))
local pairAK = ev(c(14, S), c(14, H), c(13, D), c(4, T), c(7, S))
local pairAQ = ev(c(14, D), c(14, T), c(12, D), c(4, H), c(7, H))

assert(royal[1] == 8 and P.handName(royal) == "Quinte flush royale")
assert(quads[1] == 7 and quads[2] == 9 and quads[3] == 14)
assert(full[1] == 6 and full[2] == 9 and full[3] == 4)
assert(fullTwoTrips[1] == 6 and fullTwoTrips[2] == 9 and fullTwoTrips[3] == 4)
assert(flush[1] == 5 and wheel[1] == 4 and wheel[2] == 5 and six[2] == 6)
assert(beats(royal, quads) and beats(quads, full) and beats(full, flush) and beats(flush, six))
assert(beats(six, wheel), "quinte au 6 > quinte à l'as")
assert(beats(pairAK, pairAQ), "le kicker départage")
assert(P.handName(pairAK) == "Paire de as" and P.handName(full) == "Full aux neuf")

-- Pots annexes : A à tapis à 100 avec la meilleure main, B bat C sur le pot annexe.
local g = P.payouts({ "A", "B", "C" }, { A = 100, B = 300, C = 300 }, { A = royal, B = full, C = six })
assert(g.A == 300 and g.B == 400 and not g.C, "pot annexe mal partagé")
-- Égalité : partage, le jeton restant va au premier.
g = P.payouts({ "A", "B", "C" }, { A = 101, B = 101, C = 101 }, { A = full, B = full })
assert(g.A == 152 and g.B == 151)
-- Couché : il paie mais ne gagne rien.
g = P.payouts({ "A", "B" }, { A = 50, B = 20 }, { A = six })
assert(g.A == 70)

-- Parties simulées ------------------------------------------------------------------------
local FILES = W.files()
local GROUP = { "Alice", "Bob", "Cara", "Dan" }
local alice = W.load(W.client("Alice", GROUP), FILES)
local players = {
    W.load(W.client("Bob", GROUP), FILES),
    W.load(W.client("Cara", GROUP), FILES),
    W.load(W.client("Dan", GROUP), FILES),
}
local bob = players[1]
local function step(s) W.advance(s or 1) end
local function texts(cl) -- texte visible à l'écran (cadres masqués exclus)
    local t = {}
    for _, f in ipairs(cl.frames) do
        local p, ok = f, f._kind == "FontString"
        while ok and p do if p._shown == false then ok = false end; p = p._parent end
        if ok then t[#t + 1] = tostring(f._text) end
    end
    return table.concat(t, "\n")
end
local function visibleButton(cl, prefix)
    for _, f in ipairs(cl.frames) do
        if f._kind == "Button" and tostring(f._text):sub(1, #prefix) == prefix and f._shown ~= false then
            local p, ok = f._parent, true
            while p do if p._shown == false then ok = false end; p = p._parent end
            if ok and f:IsEnabled() then return f end
        end
    end
end
-- Jetons sur la table + pot = 3000, chez chaque joueur.
local function checkChips(cl)
    local txt = texts(cl)
    local sum = 0
    for n in txt:gmatch("(%d+) jetons") do sum = sum + tonumber(n) end
    local pot = tonumber(txt:match("Pot\n|cffffffff(%d+)")) or 0
    assert(sum + pot == 3000, ("%s : %d jetons + pot %d ~= 3000"):format(cl.name, sum, pot))
end

for _, cl in ipairs(players) do cl.ns.toggleGames(); W.button(cl, "Poker"):Click() end
W.button(bob, "Nouvelle table de poker"):Click(); step()
W.button(players[2], "Rejoindre la table de poker de Bob"):Click(); step()
W.button(players[3], "Rejoindre la table de poker de Bob"):Click(); step()
assert(W.said(bob, "%[alerte%] Cara rejoint ta partie : Poker %(2/5%)")
    and W.said(bob, "Dan rejoint ta partie : Poker %(3/5%)"), "l'hôte n'est pas prévenu des arrivées")
W.button(bob, "Commencer"):Click()
step(2)
alice.ns.toggleGames(); W.button(alice, "Poker"):Click()
W.button(alice, "Regarder la table de poker de Bob"):Click()
assert(texts(alice):find("Spectateur : cartes cachées"), "la spectatrice devrait voir le bandeau spectateur")
assert(texts(players[2]):find("Tour de") or texts(players[2]):find("À toi"), "la première main ne démarre pas")

-- 1) Tout le monde suit jusqu'à l'abattage, pendant plusieurs mains.
local showdowns = 0
for _ = 1, 400 do
    for _, cl in ipairs(players) do
        if texts(cl):find("À toi de jouer") then
            local b = visibleButton(cl, "Suivre") or visibleButton(cl, "Parole")
            assert(b, cl.name .. " : ni Suivre ni Parole")
            b:Click()
        end
    end
    step(0.5)
    if texts(bob):find("gagne") then
        for _, cl in ipairs(players) do checkChips(cl) end
        checkChips(alice)
        assert(not visibleButton(alice, "Se coucher"), "la spectatrice ne doit pas pouvoir jouer")
        showdowns = showdowns + 1
        step(7) -- main suivante
    end
    if showdowns >= 4 then break end
end
assert(showdowns >= 4, "moins de 4 mains jouées : " .. showdowns)
for _, cl in ipairs(players) do
    assert(cl.out and true)
    checkChips(cl)
end

-- 2) Tout le monde fait tapis jusqu'à ce qu'il ne reste qu'un joueur.
local over = false
for _ = 1, 600 do
    for _, cl in ipairs(players) do
        if texts(cl):find("À toi de jouer") then
            local b = visibleButton(cl, "Tapis") or visibleButton(cl, "Suivre") or visibleButton(cl, "Parole")
            b:Click()
        end
    end
    step(0.5)
    if texts(bob):find("remporte tous les jetons") then over = true; break end
end
assert(over, "la partie à tapis ne se termine pas")
for _, cl in ipairs(players) do
    assert(texts(cl):find("remporte tous les jetons"), cl.name .. " ne voit pas la fin")
end
assert(texts(alice):find("remporte tous les jetons"), "la spectatrice ne voit pas la fin")
print("poker ok")

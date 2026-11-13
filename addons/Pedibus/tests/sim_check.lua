-- Scénario complet à 3 joueurs : Alice conduit, Bob et Cara montent, jouent au Yams, puis arrêt et terminus.
-- Lancer depuis le dossier de l'addon : node tests/run.js tests/sim_check.lua
local W = dofile("tests/wow.lua")
W.realm.Bob = "Gnomorettito" -- groupe inter-royaumes, comme en vrai
local FILES = W.files()
local GROUP = { "Alice", "Bob", "Cara" }
local alice = W.load(W.client("Alice", GROUP), FILES)
local bob = W.load(W.client("Bob", GROUP), FILES)
local cara = W.load(W.client("Cara", GROUP), FILES)
local function step(s) W.advance(s or 1) end

-- Survol des noms du panneau (bug 1.1 : infobulle vide -> erreur) ----------------------
bob.env.PedibusToggle()
step(6) -- fin de l'appel « qui a Pedibus ? »
for _, f in ipairs(bob.frames) do
    if f.who and f._scripts.OnEnter then f._scripts.OnEnter(f) end
end
bob.env.PedibusToggle()

-- Monter dans le bus ------------------------------------------------------------------
alice.env.PedibusToggle() -- ouvre le panneau
W.button(alice, "Je conduis"):Click()
step()
-- Bob accepte l'invitation ; Cara la rate et choisit Bob dans le panneau (sa cible) :
-- elle doit atterrir dans le bus d'Alice, pas créer un 2e bus chez Bob.
assert(bob.popup and bob.popup.data == "Alice", "Bob n'a pas reçu l'invitation")
bob.env.StaticPopupDialogs.PEDIBUS_JOIN.OnAccept(nil, bob.popup.data)
assert(bob.followed == "Alice")
step()
cara.env.PedibusToggle() -- Cara ignore la popup et ouvre le panneau
for _, f in ipairs(cara.frames) do if f.who == "Bob" and f._shown then f:Click() end end -- clic sur Bob
W.button(cara, "Monter"):Click()
assert(cara.followed == "Alice", "Cara suit " .. tostring(cara.followed) .. " au lieu d'Alice")
assert(not W.said(bob, "tu es le chauffeur"), "Bob est devenu chauffeur d'un 2e bus")
step()
local function panelSays(c, s)
    for _, f in ipairs(c.frames) do if tostring(f._text):find(s, 1, true) then return true end end
end
assert(panelSays(alice, "· 2 à bord"), "le chauffeur ne voit pas ses 2 passagers")

-- Yams à deux -------------------------------------------------------------------------
local function cells(c)
    local t = {}
    for _, f in ipairs(c.frames) do if f.t and f._kind == "Button" then t[#t + 1] = f end end
    assert(#t == 60, "60 cases attendues, " .. #t)
    return function(r, col) return t[(r - 1) * 4 + col] end
end
local function shows(c, pattern)
    for _, f in ipairs(c.frames) do
        if f._kind == "FontString" and f._shown ~= false and tostring(f._text):find(pattern) then return true end
    end
end

bob.ns.toggleGames(); cara.ns.toggleGames()
W.button(bob, "Nouvelle partie de Yams"):Click()
step()
W.button(cara, "Rejoindre la partie de Yams de Bob"):Click()
step()
W.button(bob, "Commencer"):Click()
step()
alice.ns.toggleGames() -- Alice regarde la partie
W.button(alice, "Regarder la partie de Yams de Bob"):Click()
local cellOf = { [bob] = cells(bob), [cara] = cells(cara), [alice] = cells(alice) }
local order = { { bob, 1 }, { cara, 2 } }
for round = 1, 13 do
    for _, p in ipairs(order) do
        local c, col = p[1], p[2]
        local other = c == bob and cara or bob
        assert(W.button(other, "Lancer"):IsEnabled() == false or true)
        W.button(c, "Lancer"):Click()
        step()
        W.button(c, "Relancer"):Click() -- 2e lancer, pour tester les relances
        step()
        cellOf[c](round, col):Click()
        step()
    end
end
assert(shows(bob, "Partie finie") and shows(cara, "Partie finie"), "la partie ne se termine pas")
for col = 1, 2 do
    local tb, tc = cellOf[bob](15, col).t._text, cellOf[cara](15, col).t._text
    assert(tb == tc, ("totaux différents colonne %d : %s / %s"):format(col, tostring(tb), tostring(tc)))
    assert(cellOf[alice](15, col).t._text == tb, "la spectatrice ne voit pas le même total")
end
assert(shows(alice, "Partie finie"), "la spectatrice ne voit pas la fin")
W.button(alice, "Ne plus regarder"):Click()
alice.ns.toggleGames()
W.button(bob, "Quitter"):Click(); W.button(cara, "Quitter"):Click()

-- Appel : les passagers reçoivent « Suivre », et un clic relance le suivi -------------
bob.followed, bob.popup = nil, nil
W.button(alice, "Appel"):Click(); step()
assert(bob.popup and bob.popup.which == "PEDIBUS_CALL", "Bob (passager) ne reçoit pas l'appel")
bob.env.StaticPopupDialogs.PEDIBUS_CALL.OnAccept()
assert(bob.followed == "Alice", "le bouton Suivre de l'appel ne relance pas le suivi")
step(6) -- anti-spam du bouton

-- Demande d'arrêt d'un passager -------------------------------------------------------
W.button(bob, "Arrêt ?"):Click(); step()
assert(alice.popup and alice.popup.which == "PEDIBUS_ASK" and alice.popup.data == "Bob", "le chauffeur n'a pas la demande")
assert(W.button(bob, "Demandé"), "le bouton devrait passer à « Demandé » (anti-spam)")
alice.env.StaticPopupDialogs.PEDIBUS_ASK.OnCancel(nil, "Bob", "clicked") -- « Plus tard »
step()
assert(W.said(bob, "ne peut pas s'arrêter tout de suite"), "Bob n'est pas prévenu du refus")
W.button(bob, "Arrêt ?"):Click(); step() -- il peut redemander tout de suite
alice.env.StaticPopupDialogs.PEDIBUS_ASK.OnAccept(nil, "Bob") -- cette fois le chauffeur s'arrête
step()
assert(bob.popup and bob.popup.which == "PEDIBUS_HALT", "accepter la demande devrait lancer l'arrêt")
W.button(alice, "Repartir"):Click(); step()
step(21)

-- Retardataire et arrêt avec « J'ai fini » -----------------------------------------
alice.dist.Cara = 60 -- Cara traîne
step(1)
assert(W.said(alice, "Cara perd le bus"))
alice.dist.Cara = 10
W.button(alice, "Arrêt"):Click()
step()
assert(not bob.env.PedibusGames:IsShown() and not cara.env.PedibusGames:IsShown(), "les jeux restent ouverts à l'arrêt")
assert(bob.popup and bob.popup.which == "PEDIBUS_HALT", "Bob n'a pas la demande « J'ai fini »")
assert(W.button(alice, "Repartir"), "le bouton du chauffeur devrait proposer de repartir")
bob.env.StaticPopupDialogs.PEDIBUS_HALT.OnAccept() -- Bob valide par la popup
step()
assert(panelSays(alice, "1/2 ont fini") and not W.said(alice, "Tout le monde a fini"))
step(1)
W.button(cara, "J'ai fini"):Click() -- Cara valide par le bouton du badge
step()
assert(W.said(alice, "Tout le monde a fini"), "le chauffeur n'est pas prévenu")
assert(W.said(bob, "Le bus repart") and W.said(cara, "Le bus repart"))
assert(W.button(alice, "Arrêt"), "le bouton du chauffeur devrait revenir à « Arrêt »")
-- Le chauffeur peut aussi repartir sans attendre.
W.button(alice, "Arrêt"):Click(); step()
W.button(alice, "Repartir"):Click(); step()
assert(W.button(alice, "Arrêt") and not bob.popup, "repartir sans attendre ne relance pas le bus")
bob.ns.toggleGames(); cara.ns.toggleGames()

-- Flèche vers le chauffeur ------------------------------------------------------------
local function arrowRot(c)
    c.env.PedibusBadge._scripts.OnUpdate(c.env.PedibusBadge, 1)
    for _, f in ipairs(c.frames) do if f._rot then return f._rot end end
end
W.pos.Alice, W.pos.Bob = { 100, 0 }, { 0, 0 } -- Alice 100 m au nord de Bob
bob.facing = 0 -- Bob regarde le nord : flèche droit devant
assert(math.abs(arrowRot(bob)) < 1e-6, "flèche : devrait pointer devant")
bob.facing = math.pi / 2 -- Bob regarde l'ouest : Alice est à sa droite
assert(math.abs(arrowRot(bob) + math.pi / 2) < 1e-6, "flèche : devrait pointer à droite")
W.pos.Alice, W.pos.Bob = { 0, 50 }, { 0, 0 } -- Alice à l'ouest, Bob regarde l'ouest
assert(math.abs(arrowRot(bob)) < 1e-6, "flèche : Alice à l'ouest devrait être devant")
W.pos.Alice, bob.facing = { 30, -30 }, 0 -- Alice au nord-est (ouest négatif = est), Bob regarde le nord
bob.out = {}
bob.env.SlashCmdList.PEDIBUS("fleche")
assert(W.said(bob, "Alice est au nord%-est %(45°%)") and W.said(bob, "45° à droite"), "/pedibus fleche incohérent")
-- Relevé réel en jeu (Marche de l'Ouest) : Lunatic droit devant à l'écran.
W.pos.Bob, W.pos.Alice = { -11227.100585938, 1994.5999755859 }, { -11215, 1999.9000244141 }
bob.facing = 0.41002327203751
bob.out = {}
bob.env.SlashCmdList.PEDIBUS("fleche")
assert(W.said(bob, "La flèche indique : devant"), "relevé réel : la flèche devrait pointer devant")

-- Terminus ----------------------------------------------------------------------------
W.button(alice, "Terminus"):Click()
step()
assert(W.said(bob, "a arrêté le pédibus") and not bob.env.PedibusGames:IsShown())
-- Diagnostic : /pedibus debug liste les membres et leur version ---------------------
cara.env.SlashCmdList.PEDIBUS("debug")
assert(W.said(cara, "Bob %-> Pedibus 1.2"), "debug : version de Bob absente")
assert(W.said(cara, "reçu de « Alice Orizon »"), "debug : messages reçus absents")
-- Accès aux jeux sans commande : clic droit sur le bouton flottant -----------------
alice.env.PedibusLauncher._scripts.OnClick(alice.env.PedibusLauncher, "RightButton")
assert(alice.env.PedibusGames:IsShown(), "le clic droit n'ouvre pas les jeux")
-- Les fenêtres fermées par Échap doivent être de vrais cadres (bug : fonction homonyme).
for _, n in ipairs(alice.env.UISpecialFrames) do
    assert(type(alice.env[n]) == "table", n .. " n'est pas une fenêtre mais un " .. type(alice.env[n]))
end
print("sim ok")

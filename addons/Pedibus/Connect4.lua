-- Pédibus : Puissance 4 à deux, à la souris (7 colonnes × 6 lignes), avec spectateurs.
local _, ns = ...
if ns.env and setfenv then setfenv(1, ns.env) end -- mode démo (demo/Demo.lua) : faux groupe
local COLS, ROWS = 7, 6

-- Renvoie true si le pion posé en (c, r) aligne 4 pions du même joueur.
local function wins(grid, c, r)
    local p = grid[c][r]
    for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } }) do
        local n = 1
        for _, s in ipairs({ 1, -1 }) do
            local x, y = c + d[1] * s, r + d[2] * s
            while grid[x] and grid[x][y] == p do
                n = n + 1
                x, y = x + d[1] * s, y + d[2] * s
            end
        end
        if n >= 4 then return true end
    end
    return false
end
ns.connect4Wins = wins
if not CreateFrame then return end -- chargé hors du jeu par le test

local G, L = ns.G, ns.L
local ME, short, send = G.ME, G.short, G.send
local CELL = 30

-- Messages : C:M:id:colonne (coup joué), C:Q:id (abandon). Salle d'attente : voir G.lobby.
local games = {} -- [id] = partie suivie (la mienne ou celle d'amis)
local P          -- partie affichée : la mienne, ou celle que je regarde (P.watch)
local page = G.addTab("c4", L["Puissance 4"])
local refresh, lobby

-- players[1] (l'hôte, rouges) commence.
local function newGame(id, list)
    local g = { id = id, players = { list[1], list[2] }, grid = {}, moves = 0, turn = 1, state = "play" }
    for c = 1, COLS do g.grid[c] = {} end
    games[id] = g
    return g
end
local function other(g, name) return g.players[1] == name and g.players[2] or g.players[1] end
local function myTurn() return P and not P.watch and P.state == "play" and P.players[P.turn] == ME end

local function finish(g, winner)
    g.state, g.winner = "end", winner
    lobby.finished(g.id)
    if g == P then PlaySound(winner == ME and SOUNDKIT.READY_CHECK or SOUNDKIT.RAID_WARNING) end
end

-- Lâche un pion du joueur dont c'est le tour ; renvoie false si le coup est impossible.
local function drop(g, c, who)
    local col = g.grid[c]
    if g.state ~= "play" or not col or #col >= ROWS or g.players[g.turn] ~= who then return false end
    local r = #col + 1
    col[r] = who
    g.moves = g.moves + 1
    g.turn = 3 - g.turn
    if wins(g.grid, c, r) then finish(g, who)
    elseif g.moves >= COLS * ROWS then finish(g, nil) end
    return true
end

lobby = G.lobby({
    page = page, game = "C", name = L["Puissance 4"], max = 2, min = 2,
    new = L["Nouvelle partie de Puissance 4"], join = L["Rejoindre la partie de Puissance 4 de %s"],
    watch = L["Regarder la partie de Puissance 4 de %s"], open = L["Ta partie de Puissance 4 est ouverte (%d/%d) :\n%s"],
    intro = L["Puissance 4 à deux : clique sur une colonne pour y lâcher ton pion.\nOuvre une partie, rejoins ou regarde celle d'un ami :"],
    onStart = function(id, host, list)
        if not list[2] then return end
        P = newGame(id, list)
        PlaySound(SOUNDKIT.IG_PLAYER_INVITE)
        refresh()
    end,
    onWatchable = function(id, host, list) if list[2] then newGame(id, list) end end,
    onWatch = function(id)
        if games[id] then P = games[id]; P.watch = true; refresh() end
    end,
})

-- Grille : une colonne = un bouton, les pions sont des textures colorées.
local x0 = (G.W - COLS * CELL) / 2
local discs, colBtns = {}, {}
for c = 1, COLS do
    local b = CreateFrame("Button", nil, page)
    b:SetSize(CELL, CELL * ROWS)
    b:SetPoint("TOPLEFT", x0 + (c - 1) * CELL, -30)
    b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    b:GetHighlightTexture():SetAlpha(0.12)
    b.col = c
    b:SetScript("OnClick", function()
        if not myTurn() or ns.locked() then return end
        if not drop(P, c, ME) then return end
        send(("C:M:%s:%d"):format(P.id, c))
        refresh()
    end)
    colBtns[c] = b
    discs[c] = {}
    for r = 1, ROWS do
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetSize(CELL - 6, CELL - 6)
        t:SetPoint("BOTTOM", 0, 3 + (r - 1) * CELL)
        discs[c][r] = t
    end
end
local back = page:CreateTexture(nil, "BACKGROUND")
back:SetPoint("TOPLEFT", x0 - 3, -27)
back:SetSize(COLS * CELL + 6, ROWS * CELL + 6)
back:SetColorTexture(0.1, 0.2, 0.55, 0.9)

local info = G.text(page, nil, "TOPLEFT", 14, -40 - ROWS * CELL)
info:SetWidth(G.W - 28)
local quitBtn = G.button(page, L["Quitter"], 110, function()
    if P.watch then
        P.watch = nil
    else
        if P.state == "play" then send("C:Q:" .. P.id) end
        games[P.id] = nil
    end
    P = nil
    refresh()
end)
quitBtn:SetPoint("BOTTOMRIGHT", -12, 30)

local RED, GOLD, EMPTY = { 0.9, 0.15, 0.15 }, { 1, 0.82, 0 }, { 0.03, 0.06, 0.15 }
refresh = function()
    if not G.isCurrent("c4") then return end
    lobby.frame:SetShown(not P)
    back:SetShown(P ~= nil); info:SetShown(P ~= nil); quitBtn:SetShown(P ~= nil)
    for c = 1, COLS do colBtns[c]:SetShown(P ~= nil) end
    if not P then
        lobby.draw()
        G.status:SetText("")
        return
    end
    quitBtn:SetText(P.watch and L["Ne plus regarder"] or L["Quitter"])
    for c = 1, COLS do
        for r = 1, ROWS do
            local who = P.grid[c][r]
            local col = who == nil and EMPTY or (who == P.players[1] and RED or GOLD)
            discs[c][r]:SetColorTexture(col[1], col[2], col[3])
        end
    end
    local a, b = short(P.players[1]), short(P.players[2])
    if P.state == "end" then
        if not P.winner then info:SetText(L["Match nul : grille pleine."])
        elseif P.winner == ME then info:SetText("|cff40ff40" .. L["Gagné ! 4 pions alignés."] .. "|r")
        else info:SetText("|cffff4040" .. L["%s a gagné."]:format(short(P.winner)) .. "|r") end
    elseif P.watch then
        info:SetText("|cff999999" .. L["Spectateur"] .. "|r · " .. L["%s (rouges) contre %s (jaunes).\nTour de %s..."]:format(
            a, b, short(P.players[P.turn])))
    else
        info:SetText((P.players[1] == ME and L["Tu as les rouges."] or L["Tu as les jaunes."]) .. " "
            .. (myTurn() and ("|cffffd200" .. L["À toi : clique sur une colonne."] .. "|r")
                or L["Tour de %s..."]:format(short(other(P, ME)))))
    end
    G.status:SetText(not P.watch and ns.locked() and P.state == "play"
        and "|cffff4040" .. L["Pause : messages bloqués pendant ce combat."] .. "|r" or "")
end
G.refresh.c4 = refresh

G.handlers.C = function(sender, cmd, id, a)
    if lobby.handle(sender, cmd, id, a) then return refresh() end
    local g = games[id]
    if not g or g.state ~= "play" then return end
    if cmd == "M" then
        if drop(g, tonumber(a), sender) and g == P and myTurn() then PlaySound(SOUNDKIT.IG_PLAYER_INVITE) end
    elseif cmd == "Q" and (sender == g.players[1] or sender == g.players[2]) then
        finish(g, other(g, sender))
        if g == P then ns.say(L["%s a abandonné le Puissance 4."]:format(short(sender))) end
    end
    refresh()
end

G.roster[#G.roster + 1] = function()
    for _, g in pairs(games) do
        if g.state == "play" then
            for _, p in ipairs(g.players) do
                if p ~= ME and not ns.unitFor(p) then
                    finish(g, other(g, p))
                    if g == P then ns.say(L["%s a quitté le groupe : partie terminée."]:format(short(p))) end
                    break
                end
            end
        end
    end
end

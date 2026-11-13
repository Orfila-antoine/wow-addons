-- Pédibus : bataille navale à deux, à la souris (grilles 8×8, flotte 4-3-3-2), avec spectateurs.
local _, ns = ...
if ns.env and setfenv then setfenv(1, ns.env) end -- mode démo (demo/Demo.lua) : faux groupe
if not CreateFrame then return end
local G, L = ns.G, ns.L
local ME, short, send = G.ME, G.short, G.send

local SIZE, CELL = 8, 16
local FLEET = { 4, 3, 3, 2 }
local FLEET_CELLS = 12

-- Messages : N:R:id (prêt), N:S:id:case (tir), N:H:id:case:résultat (0 raté, 1 touché,
-- 2 coulé, 3 dernier coulé = victoire), N:Q:id (abandon). Salle d'attente : voir G.lobby.
local N -- partie en cours
-- Spectateur : on ne voit que les tirs (les flottes restent secrètes).
local watched = {} -- [id] = { players = {a, b}, shots = { [a] = {case = résultat}, [b] = {...} } }
local S            -- partie regardée
local page = G.addTab("naval", L["Bataille"])
local refresh

-- Place la flotte au hasard, sans chevauchement (les navires peuvent se toucher).
local function randomFleet()
    local board, ships = {}, {}
    for k, len in ipairs(FLEET) do
        while true do
            local horiz = math.random(2) == 1
            local x = math.random(1, horiz and SIZE - len + 1 or SIZE)
            local y = math.random(1, horiz and SIZE or SIZE - len + 1)
            local cells, free = {}, true
            for j = 0, len - 1 do
                local i = (y - 1 + (horiz and 0 or j)) * SIZE + x + (horiz and j or 0)
                if board[i] then free = false; break end
                cells[#cells + 1] = i
            end
            if free then
                for _, i in ipairs(cells) do board[i] = k end
                ships[k] = { cells = cells, hits = 0 }
                break
            end
        end
    end
    return board, ships
end

local function start(id, host, list)
    local foe = list[1] == ME and list[2] or list[1]
    if not foe then return end
    N = { id = id, host = host, foe = foe, state = "place", hitsTaken = 0,
        onMe = {}, onFoe = {}, ready = false, foeReady = false }
    N.board, N.ships = randomFleet()
    PlaySound(SOUNDKIT.IG_PLAYER_INVITE)
    refresh()
end

local lobby = G.lobby({
    page = page, game = "N", name = L["Bataille"], max = 2, min = 2, onStart = start,
    new = L["Nouvelle bataille"], join = L["Rejoindre la bataille de %s"],
    watch = L["Regarder la bataille de %s"], open = L["Ta bataille est ouverte (%d/%d) :\n%s"],
    intro = L["Bataille navale à deux, tout à la souris.\nOuvre une bataille, rejoins ou regarde celle d'un ami :"],
    onWatchable = function(id, host, list)
        if list[2] then
            watched[id] = { id = id, players = { list[1], list[2] }, shots = { [list[1]] = {}, [list[2]] = {} },
                state = "play" }
        end
    end,
    onWatch = function(id) S = watched[id]; refresh() end,
})

local function otherOf(w, name) return w.players[1] == name and w.players[2] or w.players[1] end
local function watchEnd(w, winner, why)
    w.state, w.winner, w.why = "end", winner, why
    lobby.finished(w.id)
end

local function locked() return ns.locked() end

local function begin()
    if N.ready and N.foeReady then
        N.state = "play"
        N.myTurn = N.host == ME -- l'hôte tire en premier
        if N.myTurn then PlaySound(SOUNDKIT.IG_PLAYER_INVITE) end
    end
end

local function finish(won, why)
    N.state, N.won, N.why = "end", won, why
    PlaySound(won and SOUNDKIT.READY_CHECK or SOUNDKIT.RAID_WARNING)
end

-- Grilles -----------------------------------------------------------------------------------
local COLORS = {
    sea = { 0.08, 0.16, 0.28 }, ship = { 0.5, 0.5, 0.55 }, miss = { 0.25, 0.4, 0.55 },
    hit = { 1, 0.55, 0.1 }, sunk = { 0.85, 0.15, 0.15 },
}

local function grid(x0, label, onClick)
    local title = G.text(page, "GameFontNormalSmall", "TOPLEFT", x0, -8)
    title:SetText(label)
    local cells = {}
    for i = 1, SIZE * SIZE do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(CELL - 1, CELL - 1)
        b:SetPoint("TOPLEFT", x0 + ((i - 1) % SIZE) * CELL, -24 - math.floor((i - 1) / SIZE) * CELL)
        b.tex = b:CreateTexture(nil, "BACKGROUND")
        b.tex:SetAllPoints()
        if onClick then
            b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
            b:GetHighlightTexture():SetAlpha(0.25)
            b:SetScript("OnClick", function() onClick(i) end)
        end
        b.cell = i
        cells[i] = b
    end
    return cells, title
end

local mine, mineTitle = grid(14, L["Ta flotte"])
local target, targetTitle = grid(14 + SIZE * CELL + 20, L["Tire ici"], function(i)
    if not N or N.state ~= "play" or not N.myTurn or N.onFoe[i] or locked() then return end
    N.myTurn = false
    N.onFoe[i] = "wait"
    send(("N:S:%s:%d"):format(N.id, i))
    refresh()
end)

local info = G.text(page, nil, "TOPLEFT", 14, -24 - SIZE * CELL - 10)
info:SetWidth(G.W - 28)

local shuffleBtn = G.button(page, L["Placer au hasard"], 130, function()
    if N and N.state == "place" and not N.ready then
        N.board, N.ships = randomFleet()
        refresh()
    end
end)
shuffleBtn:SetPoint("TOPLEFT", 14, -24 - SIZE * CELL - 60)
local readyBtn = G.button(page, L["Prêt !"], 90, function()
    if not N or N.ready or locked() then return end
    N.ready = true
    send("N:R:" .. N.id)
    begin()
    refresh()
end)
readyBtn:SetPoint("LEFT", shuffleBtn, "RIGHT", 8, 0)
local quitBtn = G.button(page, L["Quitter"], 110, function()
    if S then S = nil; return refresh() end -- spectateur : on arrête juste de regarder
    if N and N.state ~= "end" then send("N:Q:" .. N.id) end
    N = nil
    refresh()
end)
quitBtn:SetPoint("BOTTOMRIGHT", -12, 30)

local function shotColor(r)
    return r == 0 and COLORS.miss or r == 1 and COLORS.hit or r == 2 and COLORS.sunk or COLORS.sea
end

-- Vue spectateur : à gauche les tirs du joueur 1, à droite ceux du joueur 2.
local function drawWatch()
    local a, b = S.players[1], S.players[2]
    mineTitle:SetText(L["Tirs de %s"]:format(short(a)))
    targetTitle:SetText(L["Tirs de %s"]:format(short(b)))
    for i = 1, SIZE * SIZE do
        local c = shotColor(S.shots[a][i])
        mine[i].tex:SetColorTexture(c[1], c[2], c[3])
        c = shotColor(S.shots[b][i])
        target[i].tex:SetColorTexture(c[1], c[2], c[3])
    end
    info:SetText(S.state == "end" and ("|cffffd200" .. L["Victoire de %s."]:format(short(S.winner)) .. "|r " .. (S.why or ""))
        or ("|cff999999" .. L["Spectateur"] .. "|r · " .. L["%s contre %s. Les flottes restent secrètes."]:format(short(a), short(b))))
    quitBtn:SetText(L["Ne plus regarder"])
    G.status:SetText("")
end

refresh = function()
    if not G.isCurrent("naval") then return end
    lobby.frame:SetShown(not N and not S)
    if S and not N then
        for i = 1, SIZE * SIZE do mine[i]:Show(); target[i]:Show() end
        info:Show(); quitBtn:Show(); shuffleBtn:Hide(); readyBtn:Hide()
        return drawWatch()
    end
    mineTitle:SetText(L["Ta flotte"])
    targetTitle:SetText(L["Tire ici"])
    quitBtn:SetText(L["Quitter"])
    local show = N ~= nil
    for i = 1, SIZE * SIZE do mine[i]:SetShown(show); target[i]:SetShown(show) end
    info:SetShown(show); quitBtn:SetShown(show)
    shuffleBtn:SetShown(show and N.state == "place" and not N.ready)
    readyBtn:SetShown(show and N.state == "place" and not N.ready)
    if not N then
        lobby.draw()
        G.status:SetText("")
        return
    end

    for i = 1, SIZE * SIZE do
        local shot, k = N.onMe[i], N.board[i]
        local c = COLORS.sea
        if shot == 0 then c = COLORS.miss
        elseif shot then c = N.ships[k].hits >= #N.ships[k].cells and COLORS.sunk or COLORS.hit
        elseif k then c = COLORS.ship end
        mine[i].tex:SetColorTexture(c[1], c[2], c[3])
        local r = N.onFoe[i]
        c = r == 0 and COLORS.miss or r == 1 and COLORS.hit or r == 2 and COLORS.sunk
            or r == "wait" and COLORS.ship or COLORS.sea
        target[i].tex:SetColorTexture(c[1], c[2], c[3])
    end

    local foe = short(N.foe)
    if N.state == "place" then
        info:SetText(N.ready and L["Flotte prête. On attend %s..."]:format(foe)
            or L["Place ta flotte (bouton hasard), puis « Prêt ! »."])
    elseif N.state == "play" then
        info:SetText(N.myTurn and ("|cffffd200" .. L["À toi de tirer : clique sur la grille de droite."] .. "|r")
            or L["Tir de %s..."]:format(foe))
    else
        info:SetText(N.won and ("|cff40ff40" .. L["Victoire contre %s !"]:format(foe) .. "|r " .. (N.why or ""))
            or ("|cffff4040" .. L["%s a gagné."]:format(foe) .. "|r " .. (N.why or "")))
    end
    G.status:SetText(locked() and N.state ~= "end" and "|cffff4040" .. L["Pause : messages bloqués pendant ce combat."] .. "|r" or "")
end
G.refresh.naval = refresh

-- Partie regardée : on suit les tirs (S) et leurs résultats (H) des deux joueurs.
local function onWatched(w, sender, cmd, a, b)
    if w.state ~= "play" or not w.shots[sender] then return end
    if cmd == "H" then -- résultat envoyé par la cible, pour le tir de l'autre joueur
        local shooter, i, r = otherOf(w, sender), tonumber(a), tonumber(b)
        if not i or not r then return end
        w.shots[shooter][i] = r == 0 and 0 or (r >= 2 and 2 or 1)
        if r == 3 then watchEnd(w, shooter, L["Toute la flotte de %s est coulée."]:format(short(sender))) end
    elseif cmd == "Q" then
        watchEnd(w, otherOf(w, sender), L["%s a abandonné."]:format(short(sender)))
    end
end

G.handlers.N = function(sender, cmd, id, a, b)
    if lobby.handle(sender, cmd, id, a) then return refresh() end
    if watched[id] then onWatched(watched[id], sender, cmd, a, b); return refresh() end
    if not N or N.id ~= id or sender ~= N.foe then return end
    if cmd == "R" then
        N.foeReady = true
        begin()
    elseif cmd == "S" and N.state == "play" and not N.myTurn then
        local i = tonumber(a)
        if not i or N.onMe[i] ~= nil then return end
        local k = N.board[i]
        local r = 0
        if k then
            N.ships[k].hits = N.ships[k].hits + 1
            N.hitsTaken = N.hitsTaken + 1
            r = N.ships[k].hits >= #N.ships[k].cells and 2 or 1
            if N.hitsTaken >= FLEET_CELLS then r = 3 end
        end
        N.onMe[i] = r
        send(("N:H:%s:%d:%d"):format(N.id, i, r))
        if r == 3 then finish(false, L["Ta flotte est coulée."]) else N.myTurn = true end
    elseif cmd == "H" then
        local i, r = tonumber(a), tonumber(b)
        if not i or N.onFoe[i] ~= "wait" then return end
        N.onFoe[i] = r == 0 and 0 or (r >= 2 and 2 or 1)
        if r >= 2 then
            UIErrorsFrame:AddMessage(L["Coulé !"], 1, 0.3, 0.3)
            -- ponytail: seule la case du dernier tir passe en rouge, pas tout le navire ; à faire si ça gêne.
        end
        if r == 3 then finish(true, L["Toute sa flotte est coulée."]) end
    elseif cmd == "Q" then
        finish(true, L["%s a abandonné."]:format(short(sender)))
    end
    refresh()
end

-- Un adversaire parti du groupe = victoire par forfait.
G.roster[#G.roster + 1] = function()
    for _, w in pairs(watched) do
        for _, p in ipairs(w.players) do
            if w.state == "play" and not ns.unitFor(p) then
                watchEnd(w, otherOf(w, p), L["%s a quitté le groupe."]:format(short(p)))
            end
        end
    end
    if N and N.state ~= "end" and not ns.unitFor(N.foe) then
        finish(true, L["%s a quitté le groupe."]:format(short(N.foe)))
    end
end

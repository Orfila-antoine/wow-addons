-- Pédibus : Yams de 1 à 4 joueurs, à la souris, avec spectateurs.
local _, ns = ...
if ns.env and setfenv then setfenv(1, ns.env) end -- mode démo (demo/Demo.lua) : faux groupe

-- Calcul des points (sans API WoW, testé par tests/yams_check.lua) ---------------------------
local function yamsScore(cat, d)
    local c, sum = { 0, 0, 0, 0, 0, 0 }, 0
    for _, v in ipairs(d) do c[v] = c[v] + 1; sum = sum + v end
    if cat <= 6 then return c[cat] * cat end
    local maxc, three, two = 0, false, false
    for v = 1, 6 do
        maxc = math.max(maxc, c[v])
        if c[v] == 3 then three = true elseif c[v] == 2 then two = true end
    end
    local function run(a, n)
        for v = a, a + n - 1 do if c[v] == 0 then return false end end
        return true
    end
    if cat == 7 then return maxc >= 3 and sum or 0 end
    if cat == 8 then return maxc >= 4 and sum or 0 end
    if cat == 9 then return (three and two) and 25 or 0 end
    if cat == 10 then return (run(1, 4) or run(2, 4) or run(3, 4)) and 30 or 0 end
    if cat == 11 then return (run(1, 5) or run(2, 5)) and 40 or 0 end
    if cat == 12 then return maxc == 5 and 50 or 0 end
    return sum -- chance
end

-- ponytail: pas de prime Yams multiple ni de joker, à ajouter si les joueurs le demandent.
local function yamsTotal(sheet)
    local up, all = 0, 0
    for cat = 1, 13 do
        local v = sheet[cat] or 0
        if cat <= 6 then up = up + v end
        all = all + v
    end
    local bonus = up >= 63 and 35 or 0
    return all + bonus, bonus, up
end

ns.yamsScore, ns.yamsTotal = yamsScore, yamsTotal
if not CreateFrame then return end -- chargé hors du jeu par le test

local G, L = ns.G, ns.L
local CATS = { L["As"], L["Deux"], L["Trois"], L["Quatre"], L["Cinq"], L["Six"], L["Brelan"], L["Carré"],
    L["Full"], L["Petite suite"], L["Grande suite"], L["Yams"], L["Chance"] }
local ME, short, send, text, button, W = G.ME, G.short, G.send, G.text, G.button, G.W
local YELLOW, GREY, GREEN = G.YELLOW, G.GREY, G.GREEN

-- Messages : Y:R:id:12345:n (lancer n), Y:S:id:case:points, Y:Q:id (abandon).
-- Salle d'attente et départ : voir G.lobby (lettre Y).
local games = {} -- [id] = partie suivie (la mienne ou celle d'amis), à jour grâce aux messages
local Y          -- partie affichée : la mienne, ou celle que je regarde (Y.watch)
local yp = G.addTab("yams", L["Yams"])
local refresh, lobby

local function current(g) return g.players[g.turn] end
local function myTurn() return Y and not Y.watch and Y.state == "play" and current(Y) == ME end
local function yLocked() return Y and not Y.watch and #Y.players > 1 and ns.locked() end
local function reset(g) g.dice, g.held, g.rolls = { 0, 0, 0, 0, 0 }, {}, 0 end

local function newGame(id, host, list)
    local g = { id = id, host = host, players = list, scores = {}, turn = 1, state = "play" }
    for _, p in ipairs(list) do g.scores[p] = {} end
    reset(g)
    games[id] = g
    return g
end

local function over(g)
    for _, p in ipairs(g.players) do
        for cat = 1, 13 do if not g.scores[p][cat] then return false end end
    end
    return true
end

-- Sons seulement pour la partie affichée, pas pour celles des autres qu'on suit en silence.
local function advance(g)
    reset(g)
    if over(g) then
        g.state = "end"
        lobby.finished(g.id)
        if g == Y then PlaySound(SOUNDKIT.READY_CHECK) end
        return
    end
    g.turn = g.turn % #g.players + 1
    if g == Y and current(g) == ME then PlaySound(SOUNDKIT.IG_PLAYER_INVITE) end
end

local function drop(g, name)
    for i, p in ipairs(g.players) do
        if p == name then
            table.remove(g.players, i)
            if i < g.turn then g.turn = g.turn - 1
            elseif i == g.turn and g.state == "play" then reset(g) end -- le suivant prend la main
            if g.turn > #g.players then g.turn = 1 end
            break
        end
    end
    if #g.players == 0 then
        games[g.id] = nil
        lobby.finished(g.id)
        if Y == g then Y = nil end
    end
end

lobby = G.lobby({
    page = yp, game = "Y", name = L["Yams"], max = 4, min = 1,
    new = L["Nouvelle partie de Yams"], join = L["Rejoindre la partie de Yams de %s"],
    watch = L["Regarder la partie de Yams de %s"], open = L["Ta partie de Yams est ouverte (%d/%d) :\n%s"],
    intro = L["Yams de 1 à 4 joueurs, tout à la souris.\nLance une partie, rejoins ou regarde celle d'un ami :"],
    onStart = function(id, host, list) Y = newGame(id, host, list); refresh() end,
    onWatchable = function(id, host, list) newGame(id, host, list) end,
    onWatch = function(id)
        if games[id] then Y = games[id]; Y.watch = true; refresh() end
    end,
})

-- Dés
local dice = {}
for i = 1, 5 do
    local b = CreateFrame("Button", nil, yp, "BackdropTemplate")
    b:SetSize(44, 44)
    b:SetPoint("TOPLEFT", 14 + (i - 1) * 50, -6)
    ns.skin(b)
    b.n = b:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    b.n:SetPoint("CENTER")
    b:SetScript("OnClick", function()
        if not myTurn() or Y.rolls == 0 or Y.rolls == 3 then return end
        Y.held[i] = not Y.held[i] -- le gardé reste local : seuls les résultats partent
        refresh()
    end)
    dice[i] = b
end

local rollBtn = button(yp, L["Lancer"], 110, function()
    if not myTurn() or Y.rolls >= 3 or yLocked() then return end
    for i = 1, 5 do
        if not Y.held[i] then Y.dice[i] = math.random(6) end
    end
    Y.rolls = Y.rolls + 1
    send(("Y:R:%s:%s:%d"):format(Y.id, table.concat(Y.dice), Y.rolls))
    PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
    refresh()
end)
rollBtn:SetPoint("TOPLEFT", 14, -56)
local rollInfo = text(yp, nil, "LEFT", rollBtn, "RIGHT", 8, 0)

-- Feuille de score : 13 cases + prime + total, une colonne par joueur (4 max).
local ROW, COLX, COLW = 16, 104, 50
local sheetTop = -86
local heads, cells, labels = {}, {}, {}
for c = 1, 4 do
    heads[c] = text(yp, "GameFontNormalSmall", "TOPLEFT", COLX + (c - 1) * COLW, sheetTop)
    heads[c]:SetWidth(COLW - 2)
end
local extraRows = { L["Prime (63+)"], L["Total"] }
for r = 1, 15 do
    local y = sheetTop - r * ROW
    labels[r] = text(yp, r > 13 and "GameFontNormalSmall" or nil, "TOPLEFT", 14, y)
    labels[r]:SetText(CATS[r] or extraRows[r - 13])
    cells[r] = {}
    for c = 1, 4 do
        local b = CreateFrame("Button", nil, yp)
        b:SetSize(COLW - 4, ROW - 1)
        b:SetPoint("TOPLEFT", COLX + (c - 1) * COLW - 2, y + 2)
        b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        b:GetHighlightTexture():SetAlpha(0.1)
        b.t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.t:SetPoint("CENTER")
        b:SetScript("OnClick", function()
            if r > 13 or not myTurn() or Y.players[c] ~= ME or Y.rolls == 0 or yLocked() then return end
            if Y.scores[ME][r] then return end
            local pts = yamsScore(r, Y.dice)
            Y.scores[ME][r] = pts
            send(("Y:S:%s:%d:%d"):format(Y.id, r, pts))
            advance(Y)
            refresh()
        end)
        cells[r][c] = b
    end
end

local quitBtn = button(yp, L["Quitter"], 110, function()
    if Y.watch then
        Y.watch = nil -- la partie reste suivie : on peut revenir la regarder
    else
        if Y.state == "play" and #Y.players > 1 then send("Y:Q:" .. Y.id) end
        games[Y.id] = nil
    end
    Y = nil
    refresh()
end)
quitBtn:SetPoint("BOTTOMRIGHT", -12, 30)

refresh = function()
    if not G.isCurrent("yams") then return end
    local playing = Y ~= nil
    lobby.frame:SetShown(not playing)
    for i = 1, 5 do dice[i]:SetShown(playing) end
    rollBtn:SetShown(playing and not Y.watch); rollInfo:SetShown(playing); quitBtn:SetShown(playing)
    for c = 1, 4 do heads[c]:SetShown(playing) end
    for r = 1, 15 do
        labels[r]:SetShown(playing)
        for c = 1, 4 do cells[r][c]:SetShown(playing) end
    end
    if not playing then
        lobby.draw()
        G.status:SetText("")
        return
    end

    local me = myTurn()
    quitBtn:SetText(Y.watch and L["Ne plus regarder"] or L["Quitter"])
    for i = 1, 5 do
        local v = Y.dice[i]
        dice[i].n:SetText(v > 0 and v or "-")
        dice[i]:SetBackdropBorderColor(unpack(Y.held[i] and YELLOW or GREY))
        dice[i].n:SetTextColor(unpack(Y.held[i] and YELLOW or { 1, 1, 1 }))
    end
    rollBtn:SetEnabled(me and Y.rolls < 3 and not yLocked())
    rollBtn:SetText(Y.rolls == 0 and L["Lancer"] or L["Relancer"])
    if Y.watch then
        rollInfo:SetText("|cff999999" .. L["Spectateur"] .. "|r"
            .. (Y.state == "play" and (" · " .. L["lancer %d/3"]:format(Y.rolls)) or ""))
    else
        rollInfo:SetText(me and (Y.rolls == 0 and L["À toi !"] or L["lancer %d/3 · clic sur un dé = le garder"]:format(Y.rolls))
            or "")
    end

    for c = 1, 4 do
        local p = Y.players[c]
        heads[c]:SetText(p and short(p) or "")
        heads[c]:SetTextColor(unpack(p and p == current(Y) and Y.state == "play" and YELLOW or GREY))
        local sheet = p and Y.scores[p]
        local total, bonus = 0, 0
        if sheet then total, bonus = yamsTotal(sheet) end
        for r = 1, 15 do
            local cell, txt, col = cells[r][c], "", { 1, 1, 1 }
            if sheet then
                if r == 14 then txt = bonus > 0 and bonus or ""
                elseif r == 15 then txt, col = total, YELLOW
                elseif sheet[r] then txt = sheet[r]
                elseif me and p == ME and Y.rolls > 0 then txt, col = yamsScore(r, Y.dice), GREEN -- aperçu cliquable
                end
            end
            cell.t:SetText(txt)
            cell.t:SetTextColor(unpack(col))
        end
    end

    if Y.state == "end" then
        local best, bestScore = nil, -1
        for _, p in ipairs(Y.players) do
            local t = yamsTotal(Y.scores[p])
            if t > bestScore then best, bestScore = p, t end
        end
        G.status:SetText("|cffffd200" .. L["Partie finie : %s gagne avec %d points !"]:format(short(best), bestScore) .. "|r")
    elseif yLocked() then
        G.status:SetText("|cffff4040" .. L["Pause : messages bloqués pendant ce combat."] .. "|r")
    else
        G.status:SetText(me and L["Choisis une case verte après tes lancers."] or L["Tour de %s..."]:format(short(current(Y))))
    end
end
G.refresh.yams = refresh

G.handlers.Y = function(sender, cmd, id, a, b)
    if lobby.handle(sender, cmd, id, a) then return refresh() end
    local g = games[id]
    if not g then return end
    if cmd == "R" and g.state == "play" and sender == current(g) then
        for i = 1, 5 do g.dice[i] = tonumber(a:sub(i, i)) or 0 end
        g.rolls = tonumber(b) or 0
    elseif cmd == "S" and g.state == "play" and sender == current(g) then
        g.scores[sender][tonumber(a)] = tonumber(b)
        advance(g)
    elseif cmd == "Q" then
        drop(g, sender)
    end
    refresh()
end

-- Un joueur parti du groupe ne doit pas bloquer la partie sur son tour.
G.roster[#G.roster + 1] = function()
    for _, g in pairs(games) do
        for i = #g.players, 1, -1 do
            local p = g.players[i]
            if p ~= ME and not ns.unitFor(p) then drop(g, p) end
        end
    end
end

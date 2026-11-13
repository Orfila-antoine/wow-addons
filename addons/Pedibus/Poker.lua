-- Pédibus : Texas Hold'em de 2 à 5 joueurs, à la souris, avec des jetons (pas d'or), avec spectateurs.
-- L'hôte de la partie fait la donne et arbitre ; seul le destinataire affiche ses cartes.
-- ponytail: cartes envoyées en clair au groupe et connues de l'hôte (confiance entre amis) ;
-- un mélange à engagement cryptographique serait nécessaire pour jouer avec des inconnus.
local _, ns = ...
if ns.env and setfenv then setfenv(1, ns.env) end -- mode démo (demo/Demo.lua) : faux groupe
local L = ns.L

-- Cartes : 1..52, valeur 2..14 (14 = as), couleur 1..4.
local function rankOf(c) return (c - 1) % 13 + 2 end
local function suitOf(c) return math.floor((c - 1) / 13) + 1 end

-- Meilleure main de 5 cartes parmi 5 à 7. Renvoie un score comparable : { catégorie, départages... }
-- 8 quinte flush, 7 carré, 6 full, 5 couleur, 4 quinte, 3 brelan, 2 double paire, 1 paire, 0 carte haute.
local function straightHigh(has)
    for hi = 14, 5, -1 do
        local ok = true
        for r = hi - 4, hi do
            if not has[r == 1 and 14 or r] then ok = false; break end
        end
        if ok then return hi end
    end
end

local function evaluate(cards)
    local cnt, bySuit, has = {}, { {}, {}, {}, {} }, {}
    for _, c in ipairs(cards) do
        local r, s = rankOf(c), suitOf(c)
        cnt[r] = (cnt[r] or 0) + 1
        has[r] = true
        bySuit[s][#bySuit[s] + 1] = r
    end
    local function kickers(skip, n)
        local t = {}
        for r = 14, 2, -1 do
            if cnt[r] and not skip[r] then
                for _ = 1, cnt[r] do if #t < n then t[#t + 1] = r end end
            end
        end
        return t
    end
    local function score(cat, main, kick)
        local t = { cat }
        for _, v in ipairs(main) do t[#t + 1] = v end
        for _, v in ipairs(kick or {}) do t[#t + 1] = v end
        return t
    end

    local flush
    for s = 1, 4 do
        if #bySuit[s] >= 5 then
            local sh = {}
            for _, r in ipairs(bySuit[s]) do sh[r] = true end
            local hi = straightHigh(sh)
            if hi then return score(8, { hi }) end
            table.sort(bySuit[s], function(a, b) return a > b end)
            flush = { bySuit[s][1], bySuit[s][2], bySuit[s][3], bySuit[s][4], bySuit[s][5] }
        end
    end
    local quads, trips, pairs = nil, {}, {}
    for r = 14, 2, -1 do
        local n = cnt[r] or 0
        if n == 4 then quads = quads or r
        elseif n == 3 then trips[#trips + 1] = r
        elseif n == 2 then pairs[#pairs + 1] = r end
    end
    if quads then return score(7, { quads }, kickers({ [quads] = true }, 1)) end
    if trips[1] and (trips[2] or pairs[1]) then
        return score(6, { trips[1], math.max(trips[2] or 0, pairs[1] or 0) })
    end
    if flush then return score(5, flush) end
    local hi = straightHigh(has)
    if hi then return score(4, { hi }) end
    if trips[1] then return score(3, { trips[1] }, kickers({ [trips[1]] = true }, 2)) end
    if pairs[2] then
        return score(2, { pairs[1], pairs[2] }, kickers({ [pairs[1]] = true, [pairs[2]] = true }, 1))
    end
    if pairs[1] then return score(1, { pairs[1] }, kickers({ [pairs[1]] = true }, 3)) end
    return score(0, kickers({}, 5))
end

local function compare(a, b)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x > y and 1 or -1 end
    end
    return 0
end

-- Partage du pot avec pots annexes. order = sièges dans l'ordre (le reste d'une division va au
-- premier gagnant), contrib[n] = jetons mis dans la main, scores[n] = main des joueurs encore en jeu.
local function payouts(order, contrib, scores)
    local levels, seen = {}, {}
    for _, n in ipairs(order) do
        local c = contrib[n] or 0
        if c > 0 and not seen[c] then seen[c] = true; levels[#levels + 1] = c end
    end
    table.sort(levels)
    local gains, prev = {}, 0
    for _, lvl in ipairs(levels) do
        local pot = 0
        for _, n in ipairs(order) do
            local c = contrib[n] or 0
            pot = pot + math.max(0, math.min(c, lvl) - prev)
        end
        -- Ayants droit : encore en jeu et ont mis au moins ce palier. Personne ? Tous ceux en jeu.
        local elig = {}
        for _, n in ipairs(order) do
            if scores[n] and (contrib[n] or 0) >= lvl then elig[#elig + 1] = n end
        end
        if #elig == 0 then
            for _, n in ipairs(order) do if scores[n] then elig[#elig + 1] = n end end
        end
        local best, winners = nil, {}
        for _, n in ipairs(elig) do
            local cmp = best and compare(scores[n], best) or 1
            if cmp > 0 then best, winners = scores[n], { n }
            elseif cmp == 0 then winners[#winners + 1] = n end
        end
        local share = math.floor(pot / #winners)
        for i, n in ipairs(winners) do
            gains[n] = (gains[n] or 0) + share + (i == 1 and pot - share * #winners or 0)
        end
        prev = lvl
    end
    return gains
end

local RANKS = { "2", "3", "4", "5", "6", "7", "8", "9", "10", L["V"], L["D"], L["R"], L["A"] }
local PLURAL = { L["deux"], L["trois"], L["quatre"], L["cinq"], L["six"], L["sept"], L["huit"], L["neuf"],
    L["dix"], L["valets"], L["dames"], L["rois"], L["as"] }
local function handName(s)
    local cat, r = s[1], s[2]
    if cat == 8 then return r == 14 and L["Quinte flush royale"] or L["Quinte flush"] end
    if cat == 7 then return L["Carré de %s"]:format(PLURAL[r - 1]) end
    if cat == 6 then return L["Full aux %s"]:format(PLURAL[r - 1]) end
    if cat == 5 then return L["Couleur"] end
    if cat == 4 then return L["Quinte"] end
    if cat == 3 then return L["Brelan de %s"]:format(PLURAL[r - 1]) end
    if cat == 2 then return L["Double paire"] end
    if cat == 1 then return L["Paire de %s"]:format(PLURAL[r - 1]) end
    return L["Hauteur %s"]:format(RANKS[r - 1])
end

ns.poker = { evaluate = evaluate, compare = compare, payouts = payouts, handName = handName }
if not CreateFrame then return end -- chargé hors du jeu par le test

local G = ns.G
local ME, short, send = G.ME, G.short, G.send
local START, SB, BB = 1000, 10, 20
local SUITS = { L["Pique"], L["Cœur"], L["Carreau"], L["Trèfle"] }

-- Messages (hôte -> tous) : P:H:id:main:bouton (nouvelle main), P:B:id:main:c,c,c (tableau),
-- P:S:id:main:tour;mise;relanceMin;pot;tapis,..;mises,..;états (état de la table),
-- P:R:id:main:nom=c/c;... (cartes dévoilées), P:W:id:main:nom=gain;... (gains), P:E:id:gagnant.
-- P:C:id:main:joueur:c1,c2 (cartes d'un joueur). Joueur -> hôte : P:A:id:main:action:montant.
-- Tous : P:Q:id (abandon). États : i en jeu, f couché, a tapis, o hors de la main.
local V    -- ce que voit chaque joueur (hôte compris)
local E, H -- moteur de l'hôte : partie et main en cours
local tables = {} -- [id] = vue d'une table d'amis suivie en silence (spectateur possible)
local page = G.addTab("poker", L["Poker"])
local refresh

local function seatOf(name)
    for i, n in ipairs(V.seats) do if n == name then return i end end
end

-- Moteur de l'hôte ----------------------------------------------------------------------------
local function isHost() return V and V.host == ME end

local function nextSeat(i, pred)
    local n = #E.seats
    for k = 1, n do
        local j = (i + k - 1) % n + 1
        if pred(E.seats[j]) then return j end
    end
end

local function canAct(n) return H.inHand[n] and not H.folded[n] and not H.allin[n] end
local function alive(n) return H.inHand[n] and not H.folded[n] end
local function pot()
    local t = 0
    for _, c in pairs(H.contrib) do t = t + c end
    return t
end

local applyState, onResult
local function pushState()
    local stacks, bets, flags = {}, {}, {}
    for i, n in ipairs(E.seats) do
        stacks[i] = E.stacks[n]
        bets[i] = H.bets[n] or 0
        flags[i] = not H.inHand[n] and "o" or H.folded[n] and "f" or H.allin[n] and "a" or "i"
    end
    local packed = ("%d;%d;%d;%d;%s;%s;%s"):format(H.turn or 0, H.cur, H.minRaise, pot(),
        table.concat(stacks, ","), table.concat(bets, ","), table.concat(flags))
    send(("P:S:%s:%d:%s"):format(E.id, E.hand, packed))
    applyState(E.hand, packed)
end

local function post(n, amount)
    local a = math.min(amount, E.stacks[n])
    E.stacks[n] = E.stacks[n] - a
    H.bets[n] = (H.bets[n] or 0) + a
    H.contrib[n] = (H.contrib[n] or 0) + a
    if E.stacks[n] == 0 then H.allin[n] = true end
end

local newHand, endStreet
-- Fin de main : paie les gagnants, montre les cartes s'il y a abattage, relance une main.
local function finishHand(showdown)
    local scores = {}
    for _, n in ipairs(E.seats) do
        if alive(n) then
            local cards = { H.holes[n][1], H.holes[n][2] }
            for _, c in ipairs(H.board) do cards[#cards + 1] = c end
            scores[n] = evaluate(cards)
        end
    end
    local gains = payouts(E.seats, H.contrib, scores)
    if showdown then
        local shown = {}
        for n in pairs(scores) do shown[#shown + 1] = ("%s=%d/%d"):format(n, H.holes[n][1], H.holes[n][2]) end
        local msg = table.concat(shown, ";")
        send(("P:R:%s:%d:%s"):format(E.id, E.hand, msg))
        onResult("R", E.hand, msg)
    end
    local won = {}
    for n, g in pairs(gains) do
        E.stacks[n] = E.stacks[n] + g
        won[#won + 1] = n .. "=" .. g
    end
    H.contrib, H.bets, H.turn = {}, {}, nil
    pushState()
    local msg = table.concat(won, ";")
    send(("P:W:%s:%d:%s"):format(E.id, E.hand, msg))
    onResult("W", E.hand, msg)
    C_Timer.After(6, newHand)
end

local function advance()
    local alives, last = 0, nil
    for _, n in ipairs(E.seats) do if alive(n) then alives = alives + 1; last = n end end
    if alives == 1 then return finishHand(false) end
    local done = true
    for _, n in ipairs(E.seats) do
        if canAct(n) and (not H.acted[n] or (H.bets[n] or 0) < H.cur) then done = false end
    end
    if done then return endStreet() end
    H.turn = nextSeat(H.turn or E.button, canAct)
    pushState()
end

endStreet = function()
    if not E or not H then return end
    if ns.locked() then return C_Timer.After(2, endStreet) end
    H.bets, H.acted, H.cur, H.minRaise = {}, {}, 0, BB
    H.street = H.street + 1
    if H.street > 3 then return finishHand(true) end
    for _ = 1, H.street == 1 and 3 or 1 do H.board[#H.board + 1] = table.remove(H.deck) end
    local board = table.concat(H.board, ",")
    send(("P:B:%s:%d:%s"):format(E.id, E.hand, board))
    V.board = { strsplit(",", board) }
    local actors = 0
    for _, n in ipairs(E.seats) do if canAct(n) then actors = actors + 1 end end
    if actors <= 1 then
        H.turn = nil -- tout le monde à tapis : on déroule le tableau
        pushState()
        return C_Timer.After(1.5, endStreet)
    end
    H.turn = nextSeat(E.button, canAct)
    pushState()
end

newHand = function()
    if not E then return end
    if ns.locked() then return C_Timer.After(2, newHand) end
    local players = {}
    for _, n in ipairs(E.seats) do if E.stacks[n] > 0 and not E.quit[n] then players[#players + 1] = n end end
    if #players < 2 then
        local winner = players[1] or ""
        send(("P:E:%s:%s"):format(E.id, winner))
        V.state, V.winner = "end", winner
        E, H = nil, nil
        return refresh()
    end
    E.hand = E.hand + 1
    local inGame = function(n) return E.stacks[n] > 0 and not E.quit[n] end
    E.button = nextSeat(E.button, inGame)
    H = { deck = {}, holes = {}, board = {}, bets = {}, contrib = {}, folded = {}, allin = {}, inHand = {},
        acted = {}, street = 0, cur = 0, minRaise = BB }
    for i = 1, 52 do H.deck[i] = i end
    for i = 52, 2, -1 do
        local j = math.random(i)
        H.deck[i], H.deck[j] = H.deck[j], H.deck[i]
    end
    send(("P:H:%s:%d:%d"):format(E.id, E.hand, E.button))
    onResult("H", E.hand, E.button)
    for _, n in ipairs(players) do
        H.inHand[n] = true
        H.holes[n] = { table.remove(H.deck), table.remove(H.deck) }
        if n == ME then
            V.hole = H.holes[n]
        else
            send(("P:C:%s:%d:%s:%d,%d"):format(E.id, E.hand, n, H.holes[n][1], H.holes[n][2]))
        end
    end
    -- À deux, le bouton paie la petite blinde et parle en premier avant le flop.
    local sb = #players == 2 and E.button or nextSeat(E.button, inGame)
    local bb = nextSeat(sb, inGame)
    post(E.seats[sb], SB)
    post(E.seats[bb], BB)
    H.cur = math.max(H.bets[E.seats[sb]] or 0, H.bets[E.seats[bb]] or 0)
    H.turn = bb
    local actors = 0
    for _, n in ipairs(players) do if canAct(n) then actors = actors + 1 end end
    if actors == 0 then H.turn = nil; pushState(); return C_Timer.After(1.5, endStreet) end
    H.turn = nextSeat(bb, canAct)
    pushState()
end

-- Action d'un joueur, validée par l'hôte.
local function hostAct(n, act, amount)
    if not H or not H.turn or E.seats[H.turn] ~= n then return end
    local bet, stack = H.bets[n] or 0, E.stacks[n]
    if act == "f" then
        H.folded[n] = true
    elseif act == "c" then
        post(n, H.cur - bet)
    elseif act == "r" then
        amount = tonumber(amount) or 0
        if amount < H.cur + H.minRaise or amount - bet >= stack then return end -- relance trop petite / tapis
        post(n, amount - bet)
        H.minRaise, H.cur, H.acted = amount - H.cur, amount, {}
    elseif act == "a" then
        local target = bet + stack
        post(n, stack)
        if target > H.cur then
            -- ponytail: un tapis trop court pour une vraie relance rouvre quand même les enchères.
            if target - H.cur >= H.minRaise then H.minRaise = target - H.cur end
            H.cur, H.acted = target, {}
        end
    else
        return
    end
    H.acted[n] = true
    advance()
end

local function hostQuit(n)
    if not E then return end
    E.quit[n] = true
    if H and H.inHand[n] and not H.folded[n] then
        if H.turn and E.seats[H.turn] == n then return hostAct(n, "f") end
        H.folded[n] = true
        advance()
    end
end

-- Ce que voit chaque joueur ------------------------------------------------------------------
applyState = function(hand, packed)
    if hand ~= V.hand then return end
    local turn, cur, minr, p, stacks, bets, flags = strsplit(";", packed)
    V.turn, V.cur, V.minRaise, V.pot = tonumber(turn), tonumber(cur), tonumber(minr), tonumber(p)
    V.stacks, V.bets = { strsplit(",", stacks) }, { strsplit(",", bets) }
    for i = 1, #V.seats do
        V.stacks[i], V.bets[i] = tonumber(V.stacks[i]) or 0, tonumber(V.bets[i]) or 0
    end
    V.flags = flags
    V.waiting = false
    if V.turn == seatOf(ME) then PlaySound(SOUNDKIT.IG_PLAYER_INVITE) end
    refresh()
end

onResult = function(kind, hand, data)
    if kind == "H" then
        V.hand, V.button, V.board, V.shown, V.result = hand, tonumber(data), {}, {}, nil
        -- Les cartes privées peuvent arriver avant ce message : on ne garde que celles de cette main.
        if not isHost() and V.holeHand ~= hand then V.hole = nil end
    elseif hand ~= V.hand then
        return
    elseif kind == "R" then
        for n, a, b in data:gmatch("([^=;]+)=(%d+)/(%d+)") do V.shown[n] = { tonumber(a), tonumber(b) } end
    elseif kind == "W" then
        local parts = {}
        for n, g in data:gmatch("([^=;]+)=(%d+)") do
            local line = L["%s gagne %s"]:format(short(n), g)
            if V.shown[n] and #V.board == 5 then
                local cards = { V.shown[n][1], V.shown[n][2], unpack(V.board) }
                for i = 3, #cards do cards[i] = tonumber(cards[i]) end
                line = line .. " (" .. handName(evaluate(cards)) .. ")"
            end
            parts[#parts + 1] = line
        end
        V.result = table.concat(parts, "\n")
        if not tables[V.id] or V.watch then PlaySound(SOUNDKIT.READY_CHECK) end
    end
    refresh()
end

local function newView(id, host, list)
    return { id = id, host = host, seats = list, stacks = {}, bets = {}, flags = "", board = {}, shown = {},
        state = "play", hand = 0 }
end

local function start(id, host, list)
    V = newView(id, host, list)
    if host == ME then
        E = { id = id, seats = list, stacks = {}, quit = {}, button = 0, hand = 0 }
        for _, n in ipairs(list) do E.stacks[n] = START end
        C_Timer.After(1, newHand)
    end
    refresh()
end

local lobby = G.lobby({
    page = page, game = "P", name = L["Poker"], max = 5, min = 2, onStart = start,
    new = L["Nouvelle table de poker"], join = L["Rejoindre la table de poker de %s"],
    watch = L["Regarder la table de poker de %s"], open = L["Ta table de poker est ouverte (%d/%d) :\n%s"],
    intro = L["Texas Hold'em de 2 à 5 joueurs, %d jetons chacun, blindes %d/%d.\nPas d'or en jeu. Ouvre une table, rejoins ou regarde celle d'un ami :"]:format(START, SB, BB),
    -- Spectateur : plateau, jetons, mises et cartes dévoilées à l'abattage ; jamais les cartes cachées.
    onWatchable = function(id, host, list) tables[id] = newView(id, host, list) end,
    onWatch = function(id)
        if tables[id] then V = tables[id]; V.watch = true; refresh() end
    end,
})

-- Interface -----------------------------------------------------------------------------------
local seatsText = G.text(page, nil, "TOPLEFT", 14, -6)
seatsText:SetWidth(G.W - 28)
seatsText:SetSpacing(2)

local function cardWidget(x, y)
    local f = CreateFrame("Frame", nil, page, "BackdropTemplate")
    f:SetSize(40, 54)
    f:SetPoint("TOPLEFT", x, y)
    ns.skin(f)
    f.rank = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.rank:SetPoint("TOP", 0, -8)
    f.suit = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.suit:SetPoint("BOTTOM", 0, 8)
    function f:SetCard(c)
        if not c then
            self.rank:SetText("")
            self.suit:SetText("")
            self:SetBackdropColor(0.1, 0.25, 0.15, 0.9) -- dos de carte / emplacement vide
            return
        end
        c = tonumber(c)
        local red = suitOf(c) == 2 or suitOf(c) == 3
        self:SetBackdropColor(0.95, 0.95, 0.92, 1)
        self.rank:SetText(RANKS[rankOf(c) - 1])
        self.suit:SetText(SUITS[suitOf(c)])
        local col = red and { 0.8, 0.1, 0.1 } or { 0.05, 0.05, 0.05 }
        self.rank:SetTextColor(col[1], col[2], col[3])
        self.suit:SetTextColor(col[1], col[2], col[3])
    end
    return f
end

local boardCards, holeCards = {}, {}
for i = 1, 5 do boardCards[i] = cardWidget(14 + (i - 1) * 46, -92) end
local potText = G.text(page, "GameFontNormal", "TOPLEFT", 252, -100)
potText:SetWidth(G.W - 262)
local handLabel = G.text(page, "GameFontNormalSmall", "TOPLEFT", 14, -152)
handLabel:SetText(L["Ta main"])
for i = 1, 2 do holeCards[i] = cardWidget(14 + (i - 1) * 46, -166) end
local handText = G.text(page, nil, "TOPLEFT", 112, -176)
handText:SetWidth(G.W - 126)
local info = G.text(page, nil, "TOPLEFT", 14, -228)
info:SetWidth(G.W - 28)

local function act(a, amount)
    if not V or V.waiting or ns.locked() then return end
    V.waiting = true
    local hand = V.hand
    C_Timer.After(3, function() -- action refusée ou perdue : on rend la main au joueur
        if V and V.waiting and V.hand == hand then V.waiting = false; refresh() end
    end)
    if isHost() then
        hostAct(ME, a, amount)
    else
        send(("P:A:%s:%d:%s:%d"):format(V.id, V.hand, a, amount or 0))
    end
    refresh()
end

local foldBtn = G.button(page, L["Se coucher"], 96, function() act("f") end)
foldBtn:SetPoint("TOPLEFT", 14, -272)
local callBtn = G.button(page, "", 120, function() act("c") end)
callBtn:SetPoint("LEFT", foldBtn, "RIGHT", 4, 0)
local minBtn = G.button(page, "", 110, function(self) act("r", self.amount) end)
minBtn:SetPoint("TOPLEFT", 14, -298)
local potBtn = G.button(page, "", 110, function(self) act("r", self.amount) end)
potBtn:SetPoint("LEFT", minBtn, "RIGHT", 4, 0)
local allinBtn = G.button(page, "", 90, function() act("a") end)
allinBtn:SetPoint("LEFT", potBtn, "RIGHT", 4, 0)
local actionBtns = { foldBtn, callBtn, minBtn, potBtn, allinBtn }

local quitBtn = G.button(page, L["Quitter"], 110, function()
    if V and V.watch then V.watch = nil; V = nil; return refresh() end -- on arrête juste de regarder
    if V and V.state == "play" then
        send("P:Q:" .. V.id)
        if isHost() then
            send(("P:E:%s:"):format(V.id)) -- sans donneur, la table s'arrête
            E, H = nil, nil
        end
    end
    V = nil
    refresh()
end)
quitBtn:SetPoint("BOTTOMRIGHT", -12, 30)

local tableParts = { seatsText, potText, handLabel, handText, info, quitBtn }
for i = 1, 5 do tableParts[#tableParts + 1] = boardCards[i] end
for i = 1, 2 do tableParts[#tableParts + 1] = holeCards[i] end

local FLAG_TEXT = { f = "|cff999999" .. L["couché"] .. "|r", a = "|cffff9a1a" .. L["tapis"] .. "|r",
    o = "|cff666666" .. L["éliminé"] .. "|r" }
refresh = function()
    if not G.isCurrent("poker") then return end
    lobby.frame:SetShown(not V)
    for _, w in ipairs(tableParts) do w:SetShown(V ~= nil) end
    for _, b in ipairs(actionBtns) do b:Hide() end
    if not V then
        lobby.draw()
        G.status:SetText("")
        return
    end

    local me = seatOf(ME)
    local lines = {}
    for i, n in ipairs(V.seats) do
        local flag = V.flags:sub(i, i)
        local line = (i == V.button and "|cffffd200(D)|r " or "") .. L["%s : %d jetons"]:format(short(n), V.stacks[i] or START)
        if (V.bets[i] or 0) > 0 then line = line .. " · " .. L["mise %d"]:format(V.bets[i]) end
        if FLAG_TEXT[flag] then line = line .. " · " .. FLAG_TEXT[flag] end
        if i == V.turn then line = "|cffffd200> |r" .. line end
        lines[#lines + 1] = line
    end
    seatsText:SetText(table.concat(lines, "\n"))
    for i = 1, 5 do boardCards[i]:SetCard(V.board[i]) end
    for i = 1, 2 do holeCards[i]:SetCard(V.hole and V.hole[i]) end
    potText:SetText(L["Pot"] .. "\n|cffffffff" .. (V.pot or 0) .. "|r")
    if V.hole and #V.board >= 3 then
        local cards = { V.hole[1], V.hole[2] }
        for _, c in ipairs(V.board) do cards[#cards + 1] = tonumber(c) end
        handText:SetText(handName(evaluate(cards)))
    else
        handText:SetText("")
    end

    quitBtn:SetText(V.watch and L["Ne plus regarder"] or L["Quitter"])
    handLabel:SetText(V.watch and ("|cff999999" .. L["Spectateur : cartes cachées"] .. "|r") or L["Ta main"])
    if V.state == "end" then
        info:SetText(V.winner and V.winner ~= "" and ("|cffffd200" .. L["%s remporte tous les jetons !"]:format(short(V.winner)) .. "|r")
            or L["La table est fermée."])
    elseif V.result then
        info:SetText(V.result)
    elseif V.turn == me and me then
        local myBet, myStack = V.bets[me] or 0, V.stacks[me] or 0
        local toCall = math.min(V.cur - myBet, myStack)
        info:SetText("|cffffd200" .. L["À toi de jouer."] .. "|r")
        foldBtn:Show()
        callBtn:SetText(toCall > 0 and L["Suivre %d"]:format(toCall) or L["Parole"])
        callBtn:Show()
        local minTo = V.cur + V.minRaise
        if minTo - myBet < myStack then
            minBtn.amount = minTo
            minBtn:SetText(L["Relance à %d"]:format(minTo))
            minBtn:Show()
        end
        local potTo = V.cur + V.pot + toCall
        if potTo > minTo and potTo - myBet < myStack then
            potBtn.amount = potTo
            potBtn:SetText(L["Pot : %d"]:format(potTo))
            potBtn:Show()
        end
        allinBtn:SetText(L["Tapis %d"]:format(myStack))
        allinBtn:Show()
        for _, b in ipairs(actionBtns) do b:SetEnabled(not V.waiting and not ns.locked()) end
    elseif V.turn and V.turn > 0 then
        info:SetText(L["Tour de %s..."]:format(short(V.seats[V.turn])))
    else
        info:SetText(V.hand == 0 and L["Distribution des cartes..."] or "")
    end
    G.status:SetText(ns.locked() and V.state == "play" and "|cffff4040" .. L["Pause : messages bloqués pendant ce combat."] .. "|r" or "")
end
G.refresh.poker = refresh

local function onTable(sender, cmd, id, a, b, c)
    local hand = tonumber(a)
    if cmd == "A" then
        if isHost() and hand == E.hand then hostAct(sender, b, c) end
        return
    elseif cmd == "Q" then
        if isHost() then hostQuit(sender) end
        return
    end
    if sender ~= V.host then return end
    if cmd == "H" then onResult("H", hand, b)
    elseif cmd == "C" and hand >= V.hand and b == ME then
        local x, y = strsplit(",", c)
        V.hole, V.holeHand = { tonumber(x), tonumber(y) }, hand
    elseif cmd == "B" and hand == V.hand then V.board = { strsplit(",", b) }
    elseif cmd == "S" then applyState(hand, b); return
    elseif cmd == "R" or cmd == "W" then onResult(cmd, hand, b); return
    elseif cmd == "E" then
        V.state, V.winner = "end", a
        lobby.finished(id)
    end
    refresh()
end

G.handlers.P = function(sender, cmd, id, a, b, c)
    if lobby.handle(sender, cmd, id, a) then return refresh() end
    if V and V.id == id then return onTable(sender, cmd, id, a, b, c) end
    local t = tables[id]
    if not t then return end
    -- Table suivie sans être affichée : même traitement, appliqué à sa vue.
    local mine = V
    V = t
    onTable(sender, cmd, id, a, b, c)
    V = mine
    refresh()
end

G.roster[#G.roster + 1] = function()
    for id, t in pairs(tables) do
        if t.state == "play" and not ns.unitFor(t.host) then
            t.state, t.winner = "end", ""
            lobby.finished(id)
        end
    end
    if not V or V.state ~= "play" or V.watch then return end
    if not isHost() and not ns.unitFor(V.host) then
        V.state, V.winner = "end", ""
        ns.say(L["Le donneur a quitté le groupe : la table de poker est fermée."])
        return
    end
    if isHost() then
        for _, n in ipairs(E.seats) do
            if n ~= ME and not E.quit[n] and not ns.unitFor(n) then hostQuit(n) end
        end
    end
end

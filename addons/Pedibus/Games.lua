-- Pédibus : fenêtre des mini-jeux à la souris, salle d'attente commune et mode spectateur.
-- Tout passe par des clics : le passager en /follow n'a que la souris.
local _, ns = ...
if ns.env and setfenv then setfenv(1, ns.env) end -- mode démo (demo/Demo.lua) : faux groupe
local L = ns.L
-- Outils -----------------------------------------------------------------------------
local ME = ns.charName(UnitName("player"))
local G -- boîte à outils partagée, remplie plus bas
local YELLOW, GREY, GREEN, RED = { 1, 0.82, 0 }, { 0.55, 0.55, 0.55 }, { 0.25, 0.8, 0.35 }, { 1, 0.25, 0.25 }

local function short(name) return (ns.charName(name) or "?"):sub(1, 7) end
local function send(msg) ns.send("G:" .. msg, true) end

local function button(parent, label, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

local function text(parent, font, ...)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetPoint(...)
    fs:SetJustifyH("LEFT")
    return fs
end

-- Fenêtre des jeux ----------------------------------------------------------------------
local W, H = 340, 440
local win = CreateFrame("Frame", "PedibusGames", UIParent, "BackdropTemplate")
win:SetSize(W, H)
win:SetPoint("LEFT", 60, 0)
ns.skin(win)
ns.draggable(win)
win:Hide()
tinsert(UISpecialFrames, "PedibusGames")
text(win, "GameFontNormal", "TOPLEFT", 12, -10):SetText(L["Jeux du bus"])
local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
close:SetSize(22, 22)
close:SetPoint("TOPRIGHT", -2, -2)

local pages, tabs, refresh = {}, {}, {}
local current = "yams"
local function showTab(key)
    current = key
    for k, p in pairs(pages) do p:SetShown(k == key) end
    for k, t in pairs(tabs) do if k == key then t:LockHighlight() else t:UnlockHighlight() end end
    refresh[key]()
end
local nTabs = 0
-- Ajoute un onglet de jeu ; le jeu doit définir refresh[key].
local function addTab(key, label)
    nTabs = nTabs + 1
    tabs[key] = button(win, label, 76, function() showTab(key) end)
    tabs[key]:SetPoint("TOPLEFT", 12 + (nTabs - 1) * 79, -30)
    pages[key] = CreateFrame("Frame", nil, win)
    pages[key].key = key
    pages[key]:SetPoint("TOPLEFT", 0, -58)
    pages[key]:SetPoint("BOTTOMRIGHT")
    return pages[key]
end
-- Bandeau d'état commun (pause, tour de qui...)
local status = text(win, "GameFontNormalSmall", "BOTTOMLEFT", 12, 12)
status:SetWidth(W - 24)
-- Arrêt / terminus : on range les jeux pour que le passager voie où il arrive -------------
local function pause(msg)
    PlaySound(SOUNDKIT.RAID_WARNING)
    UIErrorsFrame:AddMessage(msg, YELLOW[1], YELLOW[2], YELLOW[3])
    if win:IsShown() then
        win:Hide()
        ns.say(msg .. " " .. L["Les jeux sont en pause : rouvre-les avec le bouton dé du badge."])
    end
end

-- Boîte à outils pour les jeux (Yams.lua, Naval.lua, Connect4.lua, Poker.lua) ---------------
G = {
    ME = ME, W = W, win = win, status = status, refresh = refresh, addTab = addTab,
    button = button, text = text, short = short, send = send,
    YELLOW = YELLOW, GREY = GREY, GREEN = GREEN, RED = RED,
    handlers = {}, -- [lettre du jeu] = function(expéditeur, cmd, a, b, c, d)
    roster = {},   -- fonctions appelées quand le groupe change
}
function G.isCurrent(key) return win:IsShown() and current == key end
function G.open(key) -- ouvre la fenêtre des jeux sur cet onglet
    current = key
    if win:IsShown() then showTab(key) else win:Show() end
end
ns.G = G

-- Bulle sous le bouton Pédibus : quelqu'un ouvre une partie, un clic pour la rejoindre ---------
local bubble = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
bubble:SetSize(230, 54)
bubble:SetPoint("TOP", ns.launcher, "BOTTOM", 0, -6) -- suit le bouton quand on le déplace
bubble:SetFrameStrata("DIALOG")
ns.skin(bubble)
bubble:Hide()
local bubbleText = text(bubble, nil, "TOPLEFT", 10, -9)
bubbleText:SetWidth(190)
local function withdraw(id) -- id nil : fermer quoi qu'il arrive
    if not id or (bubble.offer and bubble.offer.id == id) then
        bubble.offer = nil
        bubble:Hide()
    end
end
button(bubble, L["Rejoindre"], 100, function()
    local b = bubble.offer
    withdraw()
    if b then b.room.join(b.id, b.host); G.open(b.key) end
end):SetPoint("BOTTOMLEFT", 8, 7)
local bubbleClose = CreateFrame("Button", nil, bubble, "UIPanelCloseButton")
bubbleClose:SetSize(20, 20)
bubbleClose:SetPoint("TOPRIGHT", -1, -1)
bubbleClose:SetScript("OnClick", function() withdraw() end)
local function offer(room, o, id, host)
    bubble.offer = { room = room, key = o.page.key, id = id, host = host }
    bubbleText:SetText(L["%s ouvre une partie : %s"]:format(short(host), o.name))
    bubble:Show()
    PlaySound(SOUNDKIT.TELL_MESSAGE)
    C_Timer.After(60, function() withdraw(id) end)
end

-- Salle d'attente commune : invitation, inscrits, départ, et parties à regarder.
-- Messages : <jeu>:I:id (invite), J:id (rejoint), L:id (part), X:id (annulée), G:id:a,b (départ).
-- o = { page, game, name, max, min, intro, onStart(id, hôte, liste),
--       new, join, watch, open (textes : bouton, « rejoindre %s », « regarder %s », « ouverte (%d/%d) :\n%s »),
--       onWatchable(id, hôte, liste) (partie lancée sans moi), onWatch(id) (je la regarde) }
-- Spectateur : aucun message en plus, chaque Pedibus reçoit déjà ceux du groupe.
-- ponytail: on ne peut regarder que les parties lancées depuis son dernier /reload.
function G.lobby(o)
    local room = { invites = {}, running = {} } -- running[id] = { host, list } : parties sans moi
    local f = CreateFrame("Frame", nil, o.page)
    f:SetAllPoints()
    room.frame = f
    local info = text(f, nil, "TOPLEFT", 14, -10)
    info:SetWidth(W - 28)
    local newBtn = button(f, o.new, 150, function()
        room.cur = { id = tostring(math.random(1000, 9999)), host = ME, joined = {}, state = "lobby" }
        send(o.game .. ":I:" .. room.cur.id)
        room.draw()
    end)
    newBtn:SetPoint("TOPLEFT", 14, -80)
    local goBtn = button(f, L["Commencer"], 110, function() room.start() end)
    goBtn:SetPoint("TOPLEFT", 14, -80)
    local cancelBtn = button(f, L["Annuler"], 90, function()
        send(o.game .. (room.cur.host == ME and ":X:" or ":L:") .. room.cur.id)
        room.cur = nil
        room.draw()
    end)
    cancelBtn:SetPoint("LEFT", goBtn, "RIGHT", 8, 0)
    local joins, watches = {}, {}

    function room.join(id, host)
        room.cur = { id = id, host = host, state = "wait" }
        send(o.game .. ":J:" .. id)
        room.draw()
    end

    function room.start()
        local list = { ME }
        for n in pairs(room.cur.joined) do if #list < o.max then list[#list + 1] = n end end
        send(("%s:G:%s:%s"):format(o.game, room.cur.id, table.concat(list, ",")))
        local id = room.cur.id
        room.cur = nil
        o.onStart(id, ME, list)
    end

    function room.draw()
        for _, b in ipairs(joins) do b:Hide() end
        for _, b in ipairs(watches) do b:Hide() end
        newBtn:SetShown(not room.cur)
        goBtn:SetShown(room.cur ~= nil and room.cur.state == "lobby")
        cancelBtn:SetShown(room.cur ~= nil)
        if not room.cur then
            info:SetText(o.intro)
            local i = 0
            for id, host in pairs(room.invites) do
                i = i + 1
                if not joins[i] then
                    joins[i] = button(f, "", W - 28, function(self) room.join(self.id, self.host) end)
                    joins[i]:SetPoint("TOPLEFT", 14, -120 - (i - 1) * 26)
                end
                joins[i].id, joins[i].host = id, host
                joins[i]:SetText(o.join:format(short(host)))
                joins[i]:Show()
            end
            for id, r in pairs(room.running) do
                i = i + 1
                local k = #watches + 1
                for j, b in ipairs(watches) do if not b:IsShown() then k = j; break end end
                if not watches[k] then
                    watches[k] = button(f, "", W - 28, function(self) o.onWatch(self.id) end)
                end
                local b = watches[k]
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", 14, -120 - (i - 1) * 26)
                b.id = id
                b:SetText(o.watch:format(short(r.host)))
                b:Show()
            end
        elseif room.cur.state == "lobby" then
            local names = { short(ME) }
            for n in pairs(room.cur.joined) do names[#names + 1] = short(n) end
            info:SetText(o.open:format(#names, o.max, table.concat(names, ", ")))
            goBtn:SetEnabled(#names >= (o.min or 1))
        else
            info:SetText(L["En attente du départ de %s..."]:format(short(room.cur.host)))
        end
    end

    -- Renvoie true si le message concernait la salle d'attente.
    function room.handle(sender, cmd, id, a)
        if cmd == "I" then
            room.invites[id] = sender
            -- Bulle, sauf si on attend déjà une partie de ce jeu ou si son onglet est sous les yeux.
            if not room.cur and not G.isCurrent(o.page.key) then offer(room, o, id, sender) end
        elseif cmd == "X" then
            room.invites[id] = nil
            withdraw(id)
            if room.cur and room.cur.id == id then room.cur = nil end
        elseif cmd == "J" then
            if room.cur and room.cur.id == id and room.cur.host == ME and not room.cur.joined[sender] then
                room.cur.joined[sender] = true
                local n = 1
                for _ in pairs(room.cur.joined) do n = n + 1 end
                if n >= o.max then
                    room.start() -- complet : on part tout de suite
                else -- l'hôte est prévenu même fenêtre fermée
                    PlaySound(SOUNDKIT.IG_PLAYER_INVITE)
                    UIErrorsFrame:AddMessage(L["%s rejoint ta partie : %s (%d/%d)"]:format(short(sender), o.name, n, o.max),
                        unpack(YELLOW))
                end
            end
        elseif cmd == "L" then
            if room.cur and room.cur.id == id and room.cur.joined then room.cur.joined[sender] = nil end
        elseif cmd == "G" then
            room.invites[id] = nil
            withdraw(id)
            local list, mine = {}, false
            for n in a:gmatch("[^,]+") do
                list[#list + 1] = n
                if n == ME then mine = true end
            end
            if room.cur and room.cur.id == id then room.cur = nil end
            if mine then
                o.onStart(id, sender, list)
            elseif o.onWatchable then
                room.running[id] = { host = sender, list = list }
                o.onWatchable(id, sender, list)
            end
        else
            return false
        end
        return true
    end

    -- Partie terminée : plus proposée aux spectateurs.
    function room.finished(id) room.running[id] = nil end

    G.roster[#G.roster + 1] = function()
        for id, host in pairs(room.invites) do
            if not ns.unitFor(host) then room.invites[id] = nil; withdraw(id) end
        end
        for id, r in pairs(room.running) do
            local anyone = false
            for _, n in ipairs(r.list) do if ns.unitFor(n) then anyone = true end end
            if not anyone then room.running[id] = nil end
        end
        if room.cur and room.cur.host ~= ME and not ns.unitFor(room.cur.host) then room.cur = nil end
        if room.cur and room.cur.joined then
            for n in pairs(room.cur.joined) do if not ns.unitFor(n) then room.cur.joined[n] = nil end end
        end
    end
    return room
end

-- Réseau ----------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:SetScript("OnEvent", function(_, event, prefix, msg, _, sender)
    if event == "GROUP_ROSTER_UPDATE" then
        for _, fn in ipairs(G.roster) do fn() end
        refresh[current]()
        return
    end
    if prefix ~= ns.PREFIX then return end
    local name = ns.charName(sender)
    if name == ME then return end
    local game, rest = msg:match("^G:(%a):(.*)$")
    if game and G.handlers[game] then
        G.handlers[game](name, rest:match("^(%a):?([^:]*):?([^:]*):?([^:]*):?([^:]*)"))
    end
end)

-- Rafraîchit les comptes à rebours et la pause combat.
C_Timer.NewTicker(1, function() if win:IsShown() then refresh[current]() end end)

win:SetScript("OnShow", function() showTab(current) end)
ns.pauseGames = pause -- appelé par Pedibus.lua au terminus
function ns.toggleGames() win:SetShown(not win:IsShown()) end

-- Pédibus, mode démo (jamais publié) : scènes figées pour les captures d'écran, interface en anglais.
-- Installé par : python tools/install.py --demo   (retour normal : python tools/install.py)
-- 4 faux membres de groupe ; seul le code de Pedibus les voit (ns.env), pas le reste de l'UI.
-- Chaque /pbdemo <scène> pose un état et n'y touche plus : rien ne bouge tant que tu ne cliques pas.
local ADDON, ns = ...
local REAL = getfenv and getfenv(1) or _ENV -- _G en jeu ; l'environnement du faux client en test
local later = REAL.C_Timer.After

local FAKES = {
    { name = "Brakka", class = "WARRIOR", dist = 6, pos = { 12, -4 } },
    { name = "Lunara", class = "PRIEST", dist = 14, pos = { -8, 10 } },
    { name = "Thornik", class = "HUNTER", dist = 27, pos = { 20, 15 } },
    { name = "Mirelle", class = "MAGE", dist = 33, pos = { -25, -18 } },
}
local BRAKKA, LUNARA, THORNIK = FAKES[1], FAKES[2], FAKES[3]
local byUnit = {}
for i, f in ipairs(FAKES) do f.unit = "party" .. i; byUnit[f.unit] = f end
local function fake(u) return u and byUnit[u] end
local function me() return ns.charName(REAL.UnitName("player")) end

-- Cadres créés par Pedibus : on leur livre les messages et événements des faux joueurs.
local frames = {}
local function inject(event, ...)
    for _, fr in ipairs(frames) do
        if fr:IsEventRegistered(event) then
            local h = fr:GetScript("OnEvent")
            if h then h(fr, event, ...) end
        end
    end
end
local function from(f, msg) inject("CHAT_MSG_ADDON", "PEDIBUS", msg, "PARTY", f.name) end
local function button(label, visibleOnly) -- bouton de Pedibus par son texte (Click marche même caché)
    for _, fr in ipairs(frames) do
        if fr.GetText and fr.Click and fr:GetText() == label and (not visibleOnly or fr:IsVisible()) then
            return fr
        end
    end
end

-- API vues par Pedibus ------------------------------------------------------------------------
local dice = {} -- prochains math.random forcés (dés du Yams)
local VERSION = REAL.C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"
local function heard(msg) -- les faux joueurs répondent comme de vrais Pedibus
    if msg:match("^HELLO:") then
        for i, f in ipairs(FAKES) do later(0.2 * i, function() from(f, "HI:" .. VERSION) end) end
    elseif msg == "START" then
        for i, f in ipairs(FAKES) do later(0.3 * i, function() from(f, "JOIN:" .. me()) end) end
    end
end
local F = {
    GetLocale = function() return "enUS" end,
    IsInGroup = function() return true end,
    IsInRaid = function() return false end,
    GetNumSubgroupMembers = function() return #FAKES end,
    GetNumGroupMembers = function() return #FAKES + 1 end,
    UnitName = function(u) local f = fake(u); if f then return f.name end return REAL.UnitName(u) end,
    GetUnitName = function(u, ...) local f = fake(u); if f then return f.name end return REAL.GetUnitName(u, ...) end,
    UnitIsUnit = function(a, b)
        local fa, fb = fake(a), fake(b)
        if fa or fb then return fa == fb end
        return REAL.UnitIsUnit(a, b)
    end,
    UnitExists = function(u) return fake(u) and true or REAL.UnitExists(u) end,
    UnitClass = function(u) local f = fake(u); if f then return f.class, f.class end return REAL.UnitClass(u) end,
    UnitIsConnected = function(u) if fake(u) then return true end return REAL.UnitIsConnected(u) end,
    UnitIsDeadOrGhost = function(u) if fake(u) then return false end return REAL.UnitIsDeadOrGhost(u) end,
    UnitDistanceSquared = function(u)
        local f = fake(u)
        if f then return f.dist * f.dist, true end
        return REAL.UnitDistanceSquared(u)
    end,
    UnitInRange = function(u) local f = fake(u); if f then return f.dist < 40, true end return REAL.UnitInRange(u) end,
    UnitPosition = function(u) -- autour de ma vraie position : la flèche du badge marche
        local f = fake(u)
        if not f then return REAL.UnitPosition(u) end
        local y, x, z, inst = REAL.UnitPosition("player")
        if y then return y + f.pos[1], x + f.pos[2], z, inst end
    end,
    FollowUnit = function(u)
        if not fake(u) then return REAL.FollowUnit(u) end
        inject("AUTOFOLLOW_BEGIN", fake(u).name)
    end,
    CreateFrame = function(...)
        local fr = REAL.CreateFrame(...)
        frames[#frames + 1] = fr
        return fr
    end,
    C_ChatInfo = setmetatable({ SendAddonMessage = function(_, msg) heard(msg) end }, { __index = REAL.C_ChatInfo }),
    math = setmetatable({ random = function(...)
        if #dice > 0 then return table.remove(dice, 1) end
        return REAL.math.random(...)
    end }, { __index = REAL.math }),
}
-- Lu par la 1re ligne de chaque fichier de Pedibus (setfenv) ; les globales créées vont dans _G.
ns.env = setmetatable({}, {
    __index = function(_, k)
        local v = F[k]
        if v ~= nil then return v end
        return REAL[k]
    end,
    __newindex = REAL,
})

-- Scènes ------------------------------------------------------------------------------------------
local function id() return tostring(REAL.math.random(1000, 9999)) end
local function stopDriving()
    local b = button(ns.L["Terminus"], true)
    if b then b:Click() end
end

local SCENES = {}
-- Panneau du chauffeur : 4 passagers à bord, distances vertes et une jaune.
function SCENES.bus()
    if not button(ns.L["Terminus"], true) then button(ns.L["Je conduis"]):Click() end
end

-- Arrêt : 2 passagers sur 4 ont fini.
function SCENES.stop()
    SCENES.bus()
    later(2, function()
        REAL.StaticPopupDialogs.PEDIBUS_ASK.OnAccept() -- même chemin que le bouton Arrêt
        from(BRAKKA, "READY")
        from(LUNARA, "READY")
    end)
end

-- Poker : quinte flush royale en main, Brakka mise 80, à toi de jouer.
function SCENES.poker()
    local t, m = id(), me()
    from(BRAKKA, ("G:P:G:%s:Brakka,Lunara,%s,Thornik"):format(t, m))
    from(BRAKKA, ("G:P:H:%s:7:4"):format(t)) -- main n°7, Thornik au bouton
    from(BRAKKA, ("G:P:C:%s:7:%s:26,25"):format(t, m)) -- As et Roi de cœur
    from(BRAKKA, ("G:P:B:%s:7:24,23,22,42"):format(t)) -- Dame, Valet, 10 de cœur, 4 de trèfle
    -- tour;mise;relanceMin;pot;tapis;mises;états : Brakka mise 80, Lunara couchée, total 4000 jetons.
    from(BRAKKA, ("G:P:S:%s:7:3;80;80;320;1040,860,1180,600;80,0,0,0;ifii"):format(t))
    ns.G.open("poker")
end

-- Yams : 10 tours joués, prime acquise, et un Yams de six sur la table (case verte à 50).
function SCENES.yams()
    local t, m = id(), me()
    from(BRAKKA, ("G:Y:G:%s:Brakka,Lunara,%s"):format(t, m))
    local cells = {}
    for _, fr in ipairs(frames) do if fr.t then cells[#cells + 1] = fr end end -- feuille, ligne par ligne
    local roll = button(ns.L["Lancer"]) or button(ns.L["Relancer"])
    local B = { 2, 6, 6, 8, 20, 18, 22, 0, 25, 30, 40 }
    local LU = { 3, 4, 12, 16, 10, 12, 19, 17, 0, 30, 0 }
    local MINE = { { 1, 1, 1, 4, 5 }, { 2, 2, 2, 6, 3 }, { 3, 3, 3, 1, 5 }, { 4, 4, 4, 2, 6 }, { 5, 5, 5, 1, 3 },
        { 6, 6, 6, 6, 2 }, { 6, 6, 6, 5, 3 }, { 4, 4, 4, 4, 6 }, { 3, 3, 5, 5, 5 }, { 1, 2, 3, 4, 6 } }
    for r = 1, 11 do
        from(BRAKKA, ("G:Y:S:%s:%d:%d"):format(t, r, B[r]))
        from(LUNARA, ("G:Y:S:%s:%d:%d"):format(t, r, LU[r]))
        dice = { unpack(MINE[r] or { 6, 6, 6, 6, 6 }) }
        roll:Click()
        if r <= 10 then cells[(r - 1) * 4 + 3]:Click() end -- ma colonne : la 3e
    end
    ns.G.open("yams")
end

-- Puissance 4 : partie bien entamée, à toi (jaunes) de jouer.
function SCENES.c4()
    local t = id()
    from(BRAKKA, ("G:C:G:%s:Brakka,%s"):format(t, me()))
    local cols = {}
    for _, fr in ipairs(frames) do if fr.col then cols[fr.col] = fr end end
    local moves = { 4, 4, 5, 3, 3, 5, 6, 2, 2, 6, 4, 4, 1 } -- Brakka, moi, Brakka... sans gagnant
    for i, c in ipairs(moves) do
        if i % 2 == 1 then from(BRAKKA, ("G:C:M:%s:%d"):format(t, c)) else cols[c]:Click() end
    end
    ns.G.open("c4")
end

-- Bulle sous le bouton Pédibus : Lunara ouvre une table de poker.
function SCENES.bubble()
    ns.G.win:Hide()
    from(LUNARA, "G:P:I:" .. id())
end

-- Badge passager : dans le bus de Brakka, suivi actif, flèche vers lui.
function SCENES.badge()
    stopDriving()
    BRAKKA.dist = 6
    if ns.getDriver() ~= "Brakka" then
        from(BRAKKA, "START")
        from(LUNARA, "JOIN:Brakka")
        from(THORNIK, "JOIN:Brakka")
        REAL.StaticPopupDialogs.PEDIBUS_JOIN.OnAccept(nil, "Brakka")
        REAL.StaticPopup_Hide("PEDIBUS_JOIN")
    end
    inject("AUTOFOLLOW_BEGIN", "Brakka")
end

-- Badge rouge : tu perds le bus.
function SCENES.lost()
    SCENES.badge()
    BRAKKA.dist = 60
    inject("AUTOFOLLOW_END")
end

-- Vue d'ensemble : panneau du chauffeur + table de poker.
function SCENES.hero() SCENES.bus(); SCENES.poker() end

local function say(m) REAL.print("|cffff9a1aPedibus DEMO|r " .. m) end
REAL.SLASH_PEDIBUSDEMO1 = "/pbdemo"
REAL.SlashCmdList.PEDIBUSDEMO = function(arg)
    local scene = SCENES[(arg or ""):lower()]
    if scene then return scene() end
    say("scènes figées : /pbdemo hero | bus | stop | poker | yams | c4 | bubble | badge | lost")
    say("une scène bizarre après une autre ? /reload puis relance-la.")
end
later(5, function() say("actif (interface en anglais). /pbdemo pour la liste des scènes.") end)

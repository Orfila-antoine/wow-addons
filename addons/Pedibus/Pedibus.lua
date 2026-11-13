-- Pédibus : bouton flottant -> choisis ton chauffeur -> L["Monter"] (rejoint son bus et le suit).
local ADDON, ns = ...
if ns.env and setfenv then setfenv(1, ns.env) end -- mode démo (demo/Demo.lua) : faux groupe
local L = ns.L -- traductions (Locales.lua) : le texte français sert de clé
local MYVER    = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"
local PREFIX   = "PEDIBUS"
local MAX_DIST = 40 -- mètres (yards) avant l'alerte "perd le bus"
local MARGIN   = 5  -- revenir sous MAX_DIST - MARGIN pour lever l'alerte (pas de bips en boucle à la limite)
local MUSIC    = "Interface\\AddOns\\Pedibus\\pedibus.ogg" -- mets ta musique ici
local LINK     = "https://www.curseforge.com/wow/addons/pedibus"
local ICON     = "Interface\\Icons\\Ability_Rogue_Sprint"
local BAR      = "Interface\\TargetingFrame\\UI-StatusBar"

local GREEN  = { 0.25, 0.80, 0.35 }
local YELLOW = { 1.00, 0.82, 0.00 }
local AMBER  = { 1.00, 0.60, 0.10 }
local RED    = { 1.00, 0.25, 0.25 }
local GREY   = { 0.55, 0.55, 0.55 }
local EDGE   = { 0.45, 0.45, 0.50 }

local driving    = false -- je suis le chauffeur
local passengers = {}    -- [nom] = { far = bool } (côté chauffeur)
local driver            -- nom de mon chauffeur (côté passager)
local driverFar  = false
local following  = false -- suivi automatique actif
local drivers    = {}    -- [nom] = true : chauffeurs annoncés dans le groupe
local riders     = {}    -- [passager] = son chauffeur, vu passer dans les JOIN du groupe
local halted     = false -- arrêt en cours (chauffeur : on attend les « fini » ; passager : bus à l'arrêt)
local readySent  = false -- passager : j'ai déjà dit « fini » pour cet arrêt
local versions   = {}    -- [nom] = version de Pedibus annoncée
local chosen            -- membre sélectionné dans le panneau
local helloAt    = -100  -- moment du dernier appel "qui a Pedibus ?"
local linkReadyAt = 0    -- anti-spam du bouton L["Envoyer le lien"]
local warnedVer         -- plus récente version déjà signalée (une fois par version)
local heard      = {}    -- [expéditeur brut] = 4 derniers messages reçus (diagnostic)
local ticker

-- Déclarées plus bas, utilisées par les boutons.
local refreshPicker, joinBus, primary, startDriving, stopDriving, leave, update

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

-- Outils ----------------------------------------------------------------------
local function say(msg) print("|cffffd200" .. L["Pédibus :"] .. "|r " .. msg) end

-- Nom du personnage seul. Sur Forever le nom complet est « Nom Royaume » (avec une espace),
-- ailleurs « Nom-Royaume » ; un nom de personnage n'a ni espace ni tiret.
-- ponytail: deux homonymes de royaumes différents dans un même groupe seraient confondus.
local function charName(full) return full and full:match("^[^%s%-]+") end
local function unitName(u) return charName(GetUnitName(u, true)) end
local ME = charName(UnitName("player"))

local function groupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    return IsInRaid() and "RAID" or "PARTY"
end

-- Combat de boss, clé mythique, JcJ : le jeu bloque les messages entre joueurs.
local function locked()
    return C_ChatInfo.InChatMessagingLockdown ~= nil and C_ChatInfo.InChatMessagingLockdown()
end

local function send(msg, silent)
    if not IsInGroup() then return end
    if locked() then
        if not silent then say(L["Messages bloqués par le jeu pendant ce combat : réessaie juste après."]) end
        return
    end
    C_ChatInfo.SendAddonMessage(PREFIX, msg, groupChannel())
end

-- Tokens d'unité des autres membres du groupe (party1, raid3...).
local function groupUnits()
    local t, prefix, n = {}, "party", GetNumSubgroupMembers()
    if IsInRaid() then prefix, n = "raid", GetNumGroupMembers() end
    for i = 1, n do
        local u = prefix .. i
        if not UnitIsUnit(u, "player") then t[#t + 1] = u end
    end
    return t
end

local function unitFor(name)
    for _, u in ipairs(groupUnits()) do
        if unitName(u) == name then return u end
    end
end

-- Distance en mètres, nil si le jeu la cache (donjon, valeur protégée...).
local function distance(unit)
    local ok, d = pcall(function()
        local d2, checked = UnitDistanceSquared(unit)
        if checked then return math.sqrt(d2) end
    end)
    return ok and d or nil
end

-- Repli en instance : le jeu dit seulement si le membre est à portée (~40 m) ou non.
local function inRange(unit)
    local ok, r = pcall(function()
        local near, checked = UnitInRange(unit)
        if checked then return near and true or false end
    end)
    if ok then return r end
end

local function isFar(d, wasFar)
    return d > (wasFar and MAX_DIST - MARGIN or MAX_DIST)
end

-- Mesure un membre : trop loin ?, texte, couleur, distance (nil en mode portée).
-- ponytail: en mode portée pas de marge anti-rebond, à ajouter si l'alerte clignote à la limite.
local function sense(unit, wasFar)
    local d = distance(unit)
    if d then
        local far = isFar(d, wasFar)
        local color = far and RED or (d > MAX_DIST * 0.7 and YELLOW or GREEN)
        return far, math.floor(d) .. " m", color, d
    end
    local near = inRange(unit)
    if near == nil then return false, L["inconnue"], GREY end
    return not near, near and L["à portée"] or L["hors de portée"], near and GREEN or RED
end

local function playMusic()
    if not PlaySoundFile(MUSIC, "Master") then PlaySound(SOUNDKIT.READY_CHECK, "Master") end
end

local function alert(msg)
    PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    UIErrorsFrame:AddMessage(msg, RED[1], RED[2], RED[3])
end

local function followKey()
    local key = GetBindingKey("PEDIBUS_FOLLOW")
    return key and GetBindingText(key)
end

-- Qui a Pedibus ? ---------------------------------------------------------------
-- Vrai si la version a est plus récente que b, nombre par nombre ("1.10" > "1.9").
-- "+dev.abc" (build local) est ignoré ; à numéro égal, la finale passe avant la bêta ("1.4.0" > "1.4.0-beta.1").
local function parseVersion(v)
    local core, pre = tostring(v):match("^[^+]*"):match("^([^-]*)%-?(.*)$")
    local t = {}
    for n in core:gmatch("%d+") do t[#t + 1] = tonumber(n) end
    return t, pre ~= ""
end
local function newer(a, b)
    local x, xpre = parseVersion(a)
    local y, ypre = parseVersion(b)
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p > q end
    end
    return ypre and not xpre
end

-- "ok" même version, "old" autre version, "pending" réponse attendue, "none" pas d'addon.
local function memberState(name)
    local v = versions[name]
    if v then return v == MYVER and "ok" or "old" end
    if GetTime() < helloAt + 3.5 then return "pending" end
    return "none"
end

local function hasUnknown()
    for _, u in ipairs(groupUnits()) do
        if not versions[unitName(u)] then return true end
    end
end

-- Demande "qui a Pedibus ?" (regroupé sur 2 s, au plus toutes les 15 s).
local function hello()
    if not IsInGroup() or not hasUnknown() or GetTime() < helloAt + 15 then return end
    helloAt = GetTime() + 2
    C_Timer.After(2, function()
        helloAt = GetTime()
        send("HELLO:" .. MYVER, true)
        refreshPicker()
        C_Timer.After(3.6, refreshPicker) -- fin de l'attente : les silencieux passent en L["pas de réponse"]
    end)
end

local hiPending = false
local function hi()
    if hiPending then return end
    hiPending = true
    C_Timer.After(1 + math.random(), function()
        hiPending = false
        send("HI:" .. MYVER, true)
    end)
end

local function sendLink()
    if not IsInGroup() then return end
    if locked() then return say(L["Chat bloqué par le jeu pendant ce combat : réessaie juste après."]) end
    local sendChat = C_ChatInfo.SendChatMessage or SendChatMessage -- déplacée dans C_ChatInfo sur les clients récents
    sendChat(L["Pédibus : installe l'addon pour monter dans mon bus -> %s"]:format(LINK), groupChannel())
    linkReadyAt = GetTime() + 10
    C_Timer.After(10, function() refreshPicker() end)
end

-- Briques d'interface (look infobulle Blizzard) -------------------------------
local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function skin(f)
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(0.05, 0.05, 0.07, 0.88)
    f:SetBackdropBorderColor(unpack(EDGE))
end

local function draggable(f)
    f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
end

-- Partagé avec Games.lua.
ns.PREFIX, ns.send, ns.say, ns.locked = PREFIX, send, say, locked
ns.groupUnits, ns.unitFor, ns.skin, ns.draggable = groupUnits, unitFor, skin, draggable
ns.getDriver = function() return driver end
ns.charName = charName

-- Frame nommé + déplaçable : WoW mémorise tout seul la position entre les sessions.
local function panel(name, w, h, ...)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetPoint(...)
    skin(f)
    draggable(f)
    f:Hide()
    return f
end

local function tooltip(widget, text)
    widget:SetScript("OnEnter", function(self)
        local t = text
        if type(text) == "function" then t = text() end -- peut renvoyer nil : pas d'infobulle
        if not t then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(t, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", GameTooltip_Hide)
end

local function busIcon(parent)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(16, 16)
    t:SetTexture(ICON)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- coupe la bordure de l'icône
    return t
end

local function title(parent, icon, text)
    icon:SetPoint("TOPLEFT", 10, -9)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    fs:SetText(text)
    return fs
end

local function button(parent, label, tip, onClick, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 112, 22)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    tooltip(b, tip)
    return b
end

local function hint(parent, w)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", 12, -34)
    fs:SetWidth(w - 24)
    fs:SetJustifyH("LEFT")
    return fs
end

-- Bouton flottant ---------------------------------------------------------------
local launcher = CreateFrame("Button", "PedibusLauncher", UIParent, "BackdropTemplate")
launcher:SetSize(38, 38)
launcher:SetPoint("CENTER", -420, 160)
skin(launcher)
draggable(launcher)
local lIcon = launcher:CreateTexture(nil, "ARTWORK")
lIcon:SetPoint("TOPLEFT", 4, -4); lIcon:SetPoint("BOTTOMRIGHT", -4, 4)
lIcon:SetTexture(ICON); lIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
launcher:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
launcher:GetHighlightTexture():ClearAllPoints()
launcher:GetHighlightTexture():SetPoint("TOPLEFT", 4, -4)
launcher:GetHighlightTexture():SetPoint("BOTTOMRIGHT", -4, 4)
-- Un glisser ne doit pas compter comme un clic au relâchement.
launcher:SetScript("OnDragStart", function(self) self.dragging = true; self:StartMoving() end)
launcher:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    C_Timer.After(0, function() self.dragging = false end)
end)
ns.launcher = launcher -- Games.lua y accroche la bulle « une partie s'ouvre »
tooltip(launcher, L["|cffffd200Pédibus|r\nClic : choisir son chauffeur\nClic droit : jeux du bus\nGlisser : déplacer le bouton"])

-- Panneau de choix du chauffeur ---------------------------------------------------
local PW = 240
local picker = CreateFrame("Frame", "PedibusPicker", UIParent, "BackdropTemplate")
picker:SetSize(PW, 120)
picker:SetPoint("TOPLEFT", launcher, "TOPRIGHT", 6, 0) -- suit le bouton flottant
picker:SetClampedToScreen(true)
picker:EnableMouse(true)
skin(picker)
picker:Hide()
tinsert(UISpecialFrames, "PedibusPicker") -- Échap le ferme

title(picker, busIcon(picker), L["Choisis ton chauffeur"])
local pClose = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
pClose:SetSize(22, 22)
pClose:SetPoint("TOPRIGHT", -2, -2)
-- Dé à côté de la croix : ouvre les jeux, même hors du bus.
local pGames = CreateFrame("Button", nil, picker)
pGames:SetSize(20, 20)
pGames:SetPoint("RIGHT", pClose, "LEFT", 0, 0)
pGames:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Up")
pGames:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Highlight", "ADD")
pGames:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Down")
pGames:SetScript("OnClick", function() ns.toggleGames() end)
tooltip(pGames, L["Jeux du bus : Yams, Bataille navale, Puissance 4, Poker."])
local pEmpty = hint(picker, PW)

local choices = {}
local function getChoice(i)
    if choices[i] then return choices[i] end
    local b = CreateFrame("Button", nil, picker)
    b:SetSize(PW - 20, 18)
    b:SetPoint("TOPLEFT", 10, -32 - (i - 1) * 20)
    b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    b:GetHighlightTexture():SetAlpha(0.08)
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints()
    b.sel:SetColorTexture(YELLOW[1], YELLOW[2], YELLOW[3], 0.18)
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.name:SetPoint("LEFT", 4, 0)
    b.tag = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.tag:SetPoint("RIGHT", -4, 0)
    b:SetScript("OnClick", function(self) chosen = self.who; refreshPicker() end)
    b:SetScript("OnDoubleClick", function(self) primary(self.who) end) -- raccourci du bouton principal
    tooltip(b, function() return b.tip end)
    choices[i] = b
    return b
end

local driveBtn = button(picker, L["Je conduis"], function()
    return driving and L["Arrête ton bus pour tout le monde."] or L["Lance ton propre bus et invite le groupe."]
end, function()
    if driving then stopDriving() else startDriving() end
end, 107)
driveBtn:SetPoint("BOTTOMLEFT", 10, 10)

local joinBtn = button(picker, L["Monter"], function()
    if chosen and memberState(chosen) == "none" then
        return L["Colle le lien de l'addon dans le chat du groupe."]
    end
    return L["Monte dans le bus choisi et suis le chauffeur.\n|cff999999Double-clic sur un nom : pareil.|r"]
end, function() primary(chosen) end, 107)
joinBtn:SetPoint("BOTTOMRIGHT", -10, 10)

refreshPicker = function()
    if not picker:IsShown() then return end
    local list = {}
    for _, u in ipairs(groupUnits()) do
        list[#list + 1] = { name = unitName(u), class = select(2, UnitClass(u)) }
    end
    -- Les chauffeurs d'abord, puis ceux qui ont l'addon, puis par nom.
    local function rank(e)
        if e.name == driver or drivers[e.name] then return 0 end
        return memberState(e.name) == "none" and 2 or 1
    end
    table.sort(list, function(a, b)
        if rank(a) ~= rank(b) then return rank(a) < rank(b) end
        return a.name < b.name
    end)

    local found = false
    for i, e in ipairs(list) do
        local b = getChoice(i)
        local st = memberState(e.name)
        local c = e.class and RAID_CLASS_COLORS[e.class]
        b.who = e.name
        b.name:SetText(e.name)
        if c and st ~= "none" then b.name:SetTextColor(c.r, c.g, c.b) else b.name:SetTextColor(unpack(GREY)) end

        local tag, col, tip = "", YELLOW, nil
        if e.name == driver then tag = L["ton bus"]
        elseif drivers[e.name] then tag = L["conduit"]
        elseif riders[e.name] then
            tag, col = L["bus de %s"]:format(riders[e.name]), GREY
            tip = L["%s est passager. « Monter » te met dans le bus de %s."]:format(e.name, riders[e.name])
        elseif st == "pending" then tag, col = "...", GREY
        elseif st == "none" then
            tag, col = L["pas de réponse"], GREY
            tip = L["%s ne répond pas : pas de Pedibus, ou la vieille version 1.0 qui ne répond pas.\nSélectionne-le puis « Envoyer le lien » pour qu'il prenne la dernière."]:format(e.name)
        end
        if st == "old" then
            local v = versions[e.name]
            if newer(v, MYVER) then
                if tag == "" then tag, col = L["v%s (plus récente)"]:format(v), AMBER end
                tip = L["%s a la version %s, plus récente que la tienne (%s).\nMets Pedibus à jour sur CurseForge."]:format(e.name, v, MYVER)
            else
                if tag == "" then tag, col = L["à mettre à jour"], AMBER end
                tip = L["%s a la version %s, plus ancienne que la tienne (%s).\nDemande-lui de mettre Pedibus à jour."]:format(e.name, v, MYVER)
            end
        end
        b.tag:SetText(tag)
        b.tag:SetTextColor(unpack(col))
        b.tip = tip
        b.sel:SetShown(e.name == chosen)
        found = found or e.name == chosen
        b:Show()
    end
    for i = #list + 1, #choices do choices[i]:Hide() end
    if not found then chosen = nil end

    pEmpty:SetShown(#list == 0)
    pEmpty:SetText(IsInGroup() and L["Personne d'autre dans le groupe pour l'instant."]
        or L["Rejoins un groupe : tes amis apparaîtront ici."])
    driveBtn:SetText(driving and L["Terminus"] or L["Je conduis"])
    driveBtn:SetEnabled(IsInGroup())

    local st = chosen and memberState(chosen)
    if st == "none" then
        joinBtn:SetText(L["Envoyer le lien"])
        joinBtn:SetEnabled(GetTime() >= linkReadyAt)
    else
        joinBtn:SetText(chosen and chosen == driver and L["Suivre"] or L["Monter"])
        joinBtn:SetEnabled(chosen ~= nil and not driving and st ~= "pending")
    end
    picker:SetHeight(32 + (#list > 0 and #list * 20 or 30) + 38)
end

picker:SetScript("OnShow", function()
    -- Pré-sélectionne ta cible si c'est un membre du groupe, sinon ton chauffeur actuel.
    if not chosen then
        if UnitExists("target") and not UnitIsUnit("target", "player")
            and (UnitInParty("target") or UnitInRaid("target")) then
            chosen = unitName("target")
        else
            chosen = driver
        end
    end
    hello()
    refreshPicker()
end)

launcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
launcher:SetScript("OnClick", function(self, mouse)
    if self.dragging then return end
    if mouse == "RightButton" then ns.toggleGames() else picker:SetShown(not picker:IsShown()) end
end)

-- Panneau du chauffeur ----------------------------------------------------------
local W = 250
local driverFrame = panel("PedibusDriverFrame", W, 100, "RIGHT", -80, 140)

local dTitle = title(driverFrame, busIcon(driverFrame), "Pédibus")
local dCount = driverFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
dCount:SetPoint("LEFT", dTitle, "RIGHT", 6, 0)
local dEmpty = hint(driverFrame, W)
dEmpty:SetText(L["Personne à bord pour l'instant.\nAppel renvoie l'invitation au groupe."])

local rows = {}
local function getRow(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, driverFrame)
    r:SetSize(W - 24, 16)
    r:SetPoint("TOPLEFT", 12, -32 - (i - 1) * 20)
    r.check = r:CreateTexture(nil, "ARTWORK") -- prêt / en attente pendant un arrêt
    r.check:SetSize(14, 14)
    r.check:SetPoint("LEFT")
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", 18, 0)
    r.name:SetWidth(64); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
    r.dist = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.dist:SetPoint("RIGHT")
    r.dist:SetWidth(80); r.dist:SetJustifyH("RIGHT")
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetPoint("LEFT", r.name, "RIGHT", 6, 0)
    r.bar:SetPoint("RIGHT", r.dist, "LEFT", -6, 0)
    r.bar:SetHeight(10)
    r.bar:SetStatusBarTexture(BAR)
    r.bar:SetMinMaxValues(0, 1)
    local bg = r.bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.08)
    rows[i] = r
    return r
end

local function fillRow(r, e)
    local c = e.class and RAID_CLASS_COLORS[e.class]
    r.name:SetText(e.name)
    if c and e.state == "ok" then r.name:SetTextColor(c.r, c.g, c.b) else r.name:SetTextColor(unpack(GREY)) end
    r.bar:SetShown(e.d ~= nil) -- pas de barre en mode portée (instance)
    if e.d then
        r.bar:SetValue(math.min(e.d / MAX_DIST, 1))
        r.bar:SetStatusBarColor(unpack(e.color))
    end
    r.dist:SetText(e.label)
    r.dist:SetTextColor(unpack(e.color))
    r.check:SetShown(halted)
    r.check:SetTexture(e.ready and "Interface\\RaidFrame\\ReadyCheck-Ready" or "Interface\\RaidFrame\\ReadyCheck-Waiting")
    r:Show()
end

local callBtn = button(driverFrame, L["Appel"], L["Fait l'appel : les passagers reçoivent un bouton pour reprendre le suivi, les autres membres une nouvelle invitation."],
    function(self)
        if locked() then return say(L["Messages bloqués par le jeu pendant ce combat : réessaie juste après."]) end
        send("START")
        self:Disable() -- anti-spam : réactivé après 5 s
        C_Timer.After(5, function() self:Enable() end)
    end)
callBtn:SetPoint("BOTTOMLEFT", 10, 10)
callBtn:SetWidth(72)
local resume
-- Chauffeur : annonce un arrêt (bouton Arrêt, ou demande d'un passager acceptée).
local function haltBus()
    if halted or not driving then return end
    if locked() then return say(L["Messages bloqués par le jeu pendant ce combat : réessaie juste après."]) end
    halted = true
    for _, p in pairs(passengers) do p.ready = false end
    send("HALT")
    update()
end
local stopBtn = button(driverFrame, L["Arrêt"], function()
    return halted and L["Repartir sans attendre ceux qui n'ont pas fini."]
        or L["Annonce un arrêt : chaque passager clique « J'ai fini » et tu es prévenu quand tout le monde a fini."]
end, function()
    if halted then return resume() end
    haltBus()
end, 72)
stopBtn:SetPoint("BOTTOM", 0, 10)
button(driverFrame, L["Terminus"], L["Arrête le pédibus pour tout le monde."], function() stopDriving() end, 72)
    :SetPoint("BOTTOMRIGHT", -10, 10)

-- Badge du passager -------------------------------------------------------------
local badge = panel("PedibusBadge", 200, 28, "TOP", 0, -100)

local bIcon = busIcon(badge)
bIcon:SetPoint("LEFT", 8, 0)
-- Flèche vers le chauffeur, à la place de l'icône du bus quand le jeu donne les positions.
local arrow = badge:CreateTexture(nil, "OVERLAY")
arrow:SetSize(20, 20)
arrow:SetPoint("CENTER", bIcon, "CENTER")
arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
arrow:Hide()
badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontNormal")
badge.text:SetPoint("LEFT", bIcon, "RIGHT", 6, 0)
badge.dist = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
badge.dist:SetPoint("LEFT", badge.text, "RIGHT", 8, 0)
tooltip(badge, function()
    return L["Tu es dans le pédibus de %s.\nReste à moins de %d m du chauffeur.\nLa flèche montre où il est (hors instance).\n|cff999999Glisser pour déplacer.|r"]:format(driver or "?", MAX_DIST)
end)

local leaveBtn = CreateFrame("Button", nil, badge, "UIPanelCloseButton")
leaveBtn:SetSize(22, 22)
leaveBtn:SetPoint("RIGHT", -2, 0)
leaveBtn:SetScript("OnClick", function() leave() end)
tooltip(leaveBtn, L["Descendre du bus"])

local gamesBtn = CreateFrame("Button", nil, badge)
gamesBtn:SetSize(20, 20)
gamesBtn:SetPoint("RIGHT", leaveBtn, "LEFT", -2, 0)
gamesBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Up")
gamesBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Highlight", "ADD")
gamesBtn:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Down")
gamesBtn:SetScript("OnClick", function() ns.toggleGames() end)
tooltip(gamesBtn, L["Jeux du bus : Yams, Bataille navale, Puissance 4 et Poker, tout à la souris."])

local followBtn = button(badge, L["Suivre"], function()
    local key = followKey()
    if key then return L["Recommence à suivre le chauffeur.\nRaccourci : %s"]:format(key) end
    return L["Recommence à suivre le chauffeur.\n|cff999999Astuce : assigne une touche dans Échap > Options > Raccourcis > AddOns > Pédibus.|r"]
end, function() PedibusFollow() end, 58)
followBtn:SetHeight(20)
followBtn:SetPoint("RIGHT", gamesBtn, "LEFT", -2, 0)

local sendReady
local readyBtn = button(badge, L["J'ai fini"], L["Préviens le chauffeur que tu as fini à cet arrêt."],
    function() sendReady() end, 70)
readyBtn:SetHeight(20)
readyBtn:Hide()

local ASK_COOLDOWN = 20 -- secondes entre deux demandes d'arrêt
local askedAt = -100
local function askStop()
    if halted or not driver or GetTime() < askedAt + ASK_COOLDOWN then return end
    if locked() then return say(L["Messages bloqués par le jeu pendant ce combat : réessaie juste après."]) end
    askedAt = GetTime()
    send("ASK")
    C_Timer.After(ASK_COOLDOWN, function() update() end)
    update()
end
local askBtn = button(badge, L["Arrêt ?"], L["Demande au chauffeur de s'arrêter (pause, quête, vendeur...)."],
    function() askStop() end, 64)
askBtn:SetHeight(20)

-- Lueur rouge qui pulse quand on traîne : l'état se voit sans lire.
local glow = badge:CreateTexture(nil, "ARTWORK", nil, -8)
glow:SetPoint("TOPLEFT", 3, -3)
glow:SetPoint("BOTTOMRIGHT", -3, 3)
glow:SetColorTexture(RED[1], RED[2], RED[3], 0.35)
glow:Hide()
local pulse = glow:CreateAnimationGroup()
pulse:SetLooping("BOUNCE")
local fade = pulse:CreateAnimation("Alpha")
fade:SetFromAlpha(0.15); fade:SetToAlpha(1); fade:SetDuration(0.6); fade:SetSmoothing("OUT")

local function setBadge(far, label, color)
    badge.text:SetText(far and L["Tu perds le bus !"] or L["Bus de %s"]:format(driver))
    badge.text:SetTextColor(unpack(far and RED or YELLOW))
    badge.dist:SetText(label .. (following and (" |cff999999· " .. L["suivi"] .. "|r")
        or (" |cffff9a1a· " .. L["sans suivi"] .. "|r")))
    badge.dist:SetTextColor(unpack(color))
    -- Rouge = trop loin, ambre = suivi coupé, gris = tout va bien.
    badge:SetBackdropBorderColor(unpack(far and RED or (following and EDGE or AMBER)))
    glow:SetShown(far)
    if far and not pulse:IsPlaying() then pulse:Play() elseif not far then pulse:Stop() end
    followBtn:SetShown(not following)
    if not following then
        local key = followKey()
        followBtn:SetText(key and L["Suivre (%s)"]:format(key) or L["Suivre"])
        followBtn:SetWidth(followBtn:GetFontString():GetStringWidth() + 24)
    end
    local showReady = halted and not readySent
    readyBtn:SetShown(showReady)
    readyBtn:ClearAllPoints()
    readyBtn:SetPoint("RIGHT", following and gamesBtn or followBtn, "LEFT", -2, 0)
    local showAsk = not halted
    askBtn:SetShown(showAsk)
    askBtn:ClearAllPoints()
    askBtn:SetPoint("RIGHT", following and gamesBtn or followBtn, "LEFT", -2, 0)
    local asked = GetTime() < askedAt + ASK_COOLDOWN
    askBtn:SetEnabled(not asked)
    askBtn:SetText(asked and L["Demandé"] or L["Arrêt ?"])
    if halted and not far then
        badge.text:SetText(readySent and L["Arrêt · %s attend les autres"]:format(driver) or L["Arrêt !"])
    end
    badge:SetWidth(badge.text:GetStringWidth() + badge.dist:GetStringWidth() + 88
        + (following and 0 or followBtn:GetWidth() + 2) + (showReady and readyBtn:GetWidth() + 2 or 0)
        + (showAsk and askBtn:GetWidth() + 2 or 0))
end

-- Flèche vers le chauffeur ----------------------------------------------------------
-- Positions du monde : X vers le nord, Y vers l'ouest ; orientation 0 = nord, sens anti-horaire.
-- Renvoie l'angle de la flèche (0 = droit devant, positif = vers la gauche).
local atan2 = math.atan2 or math.atan
function ns.arrowAngle(px, py, tx, ty, facing)
    return atan2(ty - py, tx - px) - facing
end

-- Hors instance seulement : le jeu cache les positions en donjon (et peut les masquer en combat).
local function driverAngle()
    local u = driver and unitFor(driver)
    if not u then return end
    local ok, a = pcall(function()
        -- Vérifié en jeu (côte de la Marche de l'Ouest) : 1re valeur = nord, 2e = ouest.
        local px, py, _, pInst = UnitPosition("player")
        local tx, ty, _, tInst = UnitPosition(u)
        local facing = GetPlayerFacing()
        if not (px and tx and facing) or pInst ~= tInst then return end
        return ns.arrowAngle(px, py, tx, ty, facing)
    end)
    if ok then return a end
end

-- /pedibus fleche : les valeurs brutes, à comparer avec la minicarte (nord en haut).
local COMPASS = { L["nord"], L["nord-est"], L["est"], L["sud-est"], L["sud"], L["sud-ouest"], L["ouest"], L["nord-ouest"] }
local function compass(ccw) -- angle anti-horaire depuis le nord -> point cardinal
    local deg = (-math.deg(ccw)) % 360
    return COMPASS[math.floor((deg + 22.5) / 45) % 8 + 1], math.floor(deg + 0.5)
end
local function arrowDebug()
    local u = driver and unitFor(driver)
    if not u then return say(L["Tu n'es dans aucun bus."]) end
    local ok, err = pcall(function()
        local px, py, _, pInst = UnitPosition("player")
        local tx, ty, _, tInst = UnitPosition(u)
        local facing = GetPlayerFacing()
        say(L["brut : moi %s / %s, chauffeur %s / %s, orientation %s"]:format(
            tostring(px), tostring(py), tostring(tx), tostring(ty), tostring(facing)))
        if not (px and tx and facing) or pInst ~= tInst then
            return say(L["Positions cachées par le jeu ici (instance ?) : pas de flèche."])
        end
        local where, wdeg = compass(atan2(ty - py, tx - px))
        local look, ldeg = compass(facing)
        local rel = (math.deg(ns.arrowAngle(px, py, tx, ty, facing)) + 180) % 360 - 180
        say(L["%s est au %s (%d°), à %d m. Tu regardes vers le %s (%d°)."]:format(driver, where, wdeg,
            math.floor(math.sqrt((tx - px) ^ 2 + (ty - py) ^ 2)), look, ldeg))
        say(L["La flèche indique : %s."]:format(math.abs(rel) < 15 and L["devant"]
            or math.abs(rel) > 165 and L["derrière"]
            or L["%d° à %s"]:format(math.abs(math.floor(rel)), rel > 0 and L["gauche"] or L["droite"])))
    end)
    if not ok then say(L["Calcul impossible : %s"]:format(tostring(err))) end
end

local arrowElapsed = 0
badge:SetScript("OnUpdate", function(_, elapsed)
    arrowElapsed = arrowElapsed + elapsed
    if arrowElapsed < 0.05 then return end -- 20 fois par seconde suffit
    arrowElapsed = 0
    local a = driverAngle()
    arrow:SetShown(a ~= nil)
    bIcon:SetShown(a == nil)
    if a then arrow:SetRotation(a) end
end)

-- Boucle de suivi (toutes les 0,5 s) ----------------------------------------------
update = function()
    if driving then
        local list = {}
        for name, p in pairs(passengers) do
            local u = unitFor(name)
            if not u then
                passengers[name] = nil -- a quitté le groupe
            else
                local e = { name = name, class = select(2, UnitClass(u)), far = false, color = GREY, ready = p.ready }
                if not UnitIsConnected(u) then
                    e.state, e.label = "off", L["hors ligne"]
                elseif UnitIsDeadOrGhost(u) then
                    e.state, e.label = "dead", L["mort"]
                else
                    e.state = "ok"
                    e.far, e.label, e.color, e.d = sense(u, p.far)
                end
                if e.far and not p.far then
                    alert(L["%s perd le bus !"]:format(name))
                end
                p.far = e.far
                list[#list + 1] = e
            end
        end
        -- Les retardataires en haut : c'est ce que le chauffeur cherche.
        table.sort(list, function(a, b)
            if a.far ~= b.far then return a.far end
            return (a.d or -1) > (b.d or -1)
        end)
        for i, e in ipairs(list) do fillRow(getRow(i), e) end
        for i = #list + 1, #rows do rows[i]:Hide() end
        dEmpty:SetShown(#list == 0)
        local done = 0
        for _, e in ipairs(list) do if e.ready then done = done + 1 end end
        stopBtn:SetText(halted and L["Repartir"] or L["Arrêt"])
        dCount:SetText(halted and L["· arrêt, %d/%d ont fini"]:format(done, #list)
            or (#list > 0 and L["· %d à bord"]:format(#list) or ""))
        driverFrame:SetHeight(32 + (#list > 0 and #list * 20 or 30) + 38)
    end
    if driver then
        local u = unitFor(driver)
        if not u then
            driver = nil; badge:Hide()
            say(L["Le chauffeur a quitté le groupe, tu descends du bus."])
        else
            local far, label, color = sense(u, driverFar)
            if far and not driverFar then alert(L["Tu perds le bus !"]) end
            driverFar = far
            setBadge(far, label, color)
        end
    end
    -- Bordure dorée du bouton flottant = tu es dans un bus (ou tu conduis).
    launcher:SetBackdropBorderColor(unpack((driving or driver) and YELLOW or EDGE))
    if not driving and not driver and ticker then ticker:Cancel(); ticker = nil end
end

local function startTicker()
    if not ticker then ticker = C_Timer.NewTicker(0.5, update) end
    update()
end

-- Actions ---------------------------------------------------------------------------
-- Chauffeur : tout le monde a fini ? On prévient et on repart.
local function checkAllReady()
    if not halted or not driving then return end
    local n = 0
    for _, p in pairs(passengers) do
        if not p.ready then return end
        n = n + 1
    end
    if n == 0 then return end
    PlaySound(SOUNDKIT.READY_CHECK, "Master")
    UIErrorsFrame:AddMessage(L["Tout le monde a fini !"], GREEN[1], GREEN[2], GREEN[3])
    resume()
end

resume = function()
    halted = false
    send("GO")
    update()
end

-- Passager : « J'ai fini » (popup ou bouton du badge).
sendReady = function()
    if not halted or readySent or not driver then return end
    if locked() then return say(L["Messages bloqués par le jeu pendant ce combat : réessaie juste après."]) end
    readySent = true
    send("READY")
    StaticPopup_Hide("PEDIBUS_HALT")
    update()
end

leave = function()
    if not driver then return end
    send("LEAVE")
    driver, driverFar, halted = nil, false, false
    StaticPopup_Hide("PEDIBUS_HALT")
    badge:Hide()
    refreshPicker()
end

local function join(name)
    driver, driverFar = name, false
    send("JOIN:" .. name)
    playMusic()
    badge:Show()
    startTicker()
end

-- Monte dans le bus de `name` (s'il n'y est pas déjà) et lance le suivi.
-- Toujours appelé depuis un clic : FollowUnit exige une action du joueur.
joinBus = function(name)
    local u = name and unitFor(name)
    if not u or driving then return end
    if driver ~= name then
        leave()
        join(name)
    end
    FollowUnit(u)
    picker:Hide()
end

-- Action du bouton principal : monter, ou envoyer le lien à qui n'a pas l'addon.
primary = function(name)
    if not name then return end
    -- Choisir un passager = monter dans le bus de son chauffeur (pas créer un 2e bus).
    if riders[name] and riders[name] ~= ME then name = riders[name] end
    local st = memberState(name)
    if st == "none" then
        if GetTime() >= linkReadyAt then sendLink() end
        refreshPicker()
    elseif st ~= "pending" then
        joinBus(name)
    end
end

-- invite = true : popup chez tout le groupe ; false : simple annonce (quelqu'un t'a choisi).
local function becomeDriver(invite)
    driving = true
    wipe(passengers)
    send(invite and "START" or "ON")
    playMusic()
    driverFrame:Show()
    startTicker()
    refreshPicker()
end

startDriving = function()
    if not IsInGroup() then return say(L["Il faut être en groupe pour lancer le pédibus."]) end
    leave()
    becomeDriver(true)
end

stopDriving = function()
    send("STOP")
    driving, halted = false, false
    wipe(passengers)
    driverFrame:Hide()
    update()
    refreshPicker()
end

-- Appelées par les raccourcis clavier (Bindings.xml). Une touche = action du joueur,
-- donc le jeu autorise FollowUnit.
function PedibusFollow()
    local u = driver and unitFor(driver)
    if u then
        FollowUnit(u)
    elseif driver then
        say(L["Ton chauffeur n'est plus dans le groupe."])
    else
        say(L["Tu n'es dans aucun bus : ouvre le panneau Pédibus pour choisir ton chauffeur."])
    end
end

function PedibusToggle() picker:SetShown(not picker:IsShown()) end
function PedibusOpenGames() ns.toggleGames() end -- pas « PedibusGames » : c'est le nom de la fenêtre

BINDING_HEADER_PEDIBUS = "Pédibus"
BINDING_NAME_PEDIBUS_FOLLOW = L["Suivre le chauffeur"]
BINDING_NAME_PEDIBUS_TOGGLE = L["Ouvrir le panneau Pédibus"]
BINDING_NAME_PEDIBUS_GAMES = L["Ouvrir les jeux du bus"]

StaticPopupDialogs["PEDIBUS_ASK"] = {
    text = L["%s demande un arrêt.\nTu t'arrêtes ?"],
    button1 = L["Arrêt"],
    button2 = L["Plus tard"],
    OnShow = function() PlaySound(SOUNDKIT.RAID_WARNING) end,
    OnAccept = function() haltBus() end,
    OnCancel = function(_, data, reason)
        if reason == "clicked" then send("LATER:" .. data) end -- prévient le passager
    end,
    timeout = 30, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["PEDIBUS_HALT"] = {
    text = L["Arrêt ! %s attend que tout le monde ait fini.\nClique quand c'est bon pour toi."],
    button1 = L["J'ai fini"],
    button2 = L["Pas encore"],
    OnShow = function() PlaySound(SOUNDKIT.RAID_WARNING) end,
    OnAccept = function() sendReady() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Appel du chauffeur pour ses passagers : un clic relance le suivi (un clic = action du joueur).
StaticPopupDialogs["PEDIBUS_CALL"] = {
    text = L["%s fait l'appel : le bus est là !"],
    button1 = L["Suivre"],
    button2 = L["Fermer"],
    OnShow = function() PlaySound(SOUNDKIT.READY_CHECK) end,
    OnAccept = function() PedibusFollow() end,
    timeout = 30, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["PEDIBUS_JOIN"] = {
    text = L["%s lance le pédibus.\nTu montes à bord ?"],
    button1 = L["Monter"],
    button2 = L["Pas cette fois"],
    OnShow = function() PlaySound(SOUNDKIT.IG_PLAYER_INVITE) end,
    OnAccept = function(_, data) joinBus(data) end,
    timeout = 30, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Événements ------------------------------------------------------------------------
-- Messages : HELLO:<v> (qui a Pedibus ?), HI:<v> (moi !), START (invitation),
-- ON (je conduis), STOP, JOIN:<chauffeur>, LEAVE, HALT (arrêt), READY (j'ai fini), GO (on repart),
-- ASK (un passager demande un arrêt), LATER:<passager> (le chauffeur refuse pour l'instant).
local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("AUTOFOLLOW_BEGIN")
events:RegisterEvent("AUTOFOLLOW_END")
events:SetScript("OnEvent", function(_, event, prefix, msg, _, sender)
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        hello()
        return refreshPicker()
    end
    if event == "AUTOFOLLOW_BEGIN" or event == "AUTOFOLLOW_END" then
        local was = following
        following = event == "AUTOFOLLOW_BEGIN"
        if driver and was and not following then
            -- Le suivi casse dès qu'on bouge : on le signale tout de suite.
            PlaySound(SOUNDKIT.TELL_MESSAGE, "Master")
            local key = followKey()
            UIErrorsFrame:AddMessage(key and L["Suivi interrompu : appuie sur %s"]:format(key)
                or L["Suivi interrompu : clique sur Suivre"],
                AMBER[1], AMBER[2], AMBER[3])
        end
        if driver then update() end
        return
    end

    if prefix ~= PREFIX then return end
    -- Historique court pour /pedibus debug (hors jeux, trop bavards).
    if msg:sub(1, 2) ~= "G:" then
        local h = heard[sender] or {}
        h[#h + 1] = msg
        if #h > 4 then table.remove(h, 1) end
        heard[sender] = h
    end
    if msg:sub(1, 2) == "G:" then return end -- "G:" = jeux, gérés par Games.lua
    local name = charName(sender)
    if name == ME then return end

    local helloVer = msg:match("^HELLO:(.+)$")
    local hiVer = msg:match("^HI:(.+)$")
    local target = msg:match("^JOIN:(.+)$")
    -- La 1.0 ne s'annonçait pas : on la reconnaît à ses autres messages.
    versions[name] = helloVer or hiVer or versions[name] or "1.0"
    -- Un membre a une version plus récente : on le dit une fois (l'addon ne peut pas consulter CurseForge).
    if newer(versions[name], warnedVer or MYVER) then
        warnedVer = versions[name]
        say(L["Pedibus %s est sorti (%s l'a) : mets à jour sur CurseForge."]:format(warnedVer, name))
    end

    -- Qui est dans quel bus (pour tout le groupe, pas seulement le chauffeur concerné).
    if target then riders[name] = charName(target) end
    if msg == "LEAVE" or msg == "START" or msg == "ON" then riders[name] = nil end
    if msg == "STOP" then
        for p, d in pairs(riders) do if d == name then riders[p] = nil end end
    end

    if helloVer then
        hi()
    elseif msg == "START" then
        drivers[name] = true
        if driver == name then
            StaticPopup_Show("PEDIBUS_CALL", name) -- mon chauffeur fait l'appel
        elseif not driving then
            StaticPopup_Show("PEDIBUS_JOIN", name, nil, name)
        end
    elseif msg == "ON" then
        drivers[name] = true
    elseif msg == "STOP" then
        drivers[name] = nil
        StaticPopup_Hide("PEDIBUS_JOIN")
        if driver == name then
            driver, halted = nil, false
            StaticPopup_Hide("PEDIBUS_HALT")
            badge:Hide()
            ns.pauseGames(L["%s a arrêté le pédibus. Terminus !"]:format(name))
        end
    elseif target then
        if charName(target) ~= ME then return refreshPicker() end
        if not driving then
            becomeDriver(false)
            say(L["%s t'a choisi : tu es le chauffeur !"]:format(name))
        end
        passengers[name] = { far = false, ready = halted } -- monté pendant l'arrêt : déjà prêt
        update()
    elseif msg == "LEAVE" and driving and passengers[name] then
        passengers[name] = nil
        update()
        checkAllReady()
    elseif msg == "READY" and driving and halted and passengers[name] and not passengers[name].ready then
        passengers[name].ready = true
        update()
        checkAllReady()
    elseif msg == "ASK" and driving and passengers[name] and not halted then
        alert(L["%s demande un arrêt !"]:format(name))
        StaticPopup_Show("PEDIBUS_ASK", name, nil, name)
    elseif msg:match("^LATER:") and name == driver and charName(msg:sub(7)) == ME then
        askedAt = -100 -- on peut redemander tout de suite
        say(L["%s ne peut pas s'arrêter tout de suite."]:format(name))
        update()
    elseif msg == "HALT" and name == driver then
        halted, readySent = true, false
        ns.pauseGames(L["Arrêt !"])
        StaticPopup_Show("PEDIBUS_HALT", name)
        update()
    elseif msg == "GO" and name == driver and halted then
        halted = false
        StaticPopup_Hide("PEDIBUS_HALT")
        PlaySound(SOUNDKIT.READY_CHECK, "Master")
        UIErrorsFrame:AddMessage(L["Le bus repart !"], GREEN[1], GREEN[2], GREEN[3])
        update()
    end
    refreshPicker()
end)

SLASH_PEDIBUS1 = "/pedibus"
-- /pedibus debug : ce que l'addon voit du groupe, pour comprendre un « pas de réponse ».
local function debug()
    say(L["version %s, moi = %s"]:format(MYVER, tostring(ME))
        .. (locked() and L[", messages BLOQUÉS par le jeu"] or ""))
    if driving then
        local names = {}
        for n in pairs(passengers) do names[#names + 1] = n end
        say(L["je conduis, à bord : %s"]:format(#names > 0 and table.concat(names, ", ") or L["personne"]))
    end
    say(L["je suis dans le bus de : %s"]:format(driver or L["personne"]))
    local ds = {}
    for n in pairs(drivers) do ds[#ds + 1] = n end
    if #ds > 0 then say(L["chauffeurs annoncés : %s"]:format(table.concat(ds, ", "))) end
    for _, u in ipairs(groupUnits()) do
        local n = unitName(u)
        say(("%s -> %s"):format(tostring(n), versions[n] and ("Pedibus " .. versions[n]) or L["aucune réponse"]))
    end
    local any = false
    for s, m in pairs(heard) do
        any = true
        say(L["reçu de « %s » : %s"]:format(s, table.concat(m, ", ")))
    end
    if not any then say(L["Aucun message Pedibus reçu depuis le chargement."]) end
    helloAt = -100 -- relance tout de suite un appel « qui a Pedibus ? »
    hello()
end

SlashCmdList.PEDIBUS = function(arg)
    arg = arg:lower()
    if arg:match("^jeux") or arg:match("^game") then ns.toggleGames()
    elseif arg:match("^debug") then debug()
    elseif arg:match("^fl") or arg:match("^arrow") then arrowDebug()
    else PedibusToggle() end
end

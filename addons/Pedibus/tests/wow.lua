-- Faux client WoW pour tester Pedibus hors du jeu : plusieurs joueurs dans un même groupe,
-- messages d'addon livrés à tous, horloge et minuteurs pilotés par le test.
-- ponytail: imite seulement les API utilisées par Pedibus ; ajoute-en quand l'addon en appelle de nouvelles.
local M = { clock = 0, queue = {}, clients = {}, timers = {}, log = {}, realm = {},
    pos = {} } -- [nom] = { nord, ouest } ; absent = position cachée (instance)
-- Ordre de UnitPosition relevé en jeu le 07/11 : la 1re valeur est l'axe nord.
-- Royaume de chaque joueur (Forever écrit les noms complets « Nom Royaume »).
local function realmOf(n) return M.realm[n] or "Orizon" end

function M.advance(sec)
    local target = M.clock + sec
    while true do
        table.sort(M.timers, function(a, b) return a.at < b.at end)
        local t = M.timers[1]
        if not t or t.at > target then break end
        table.remove(M.timers, 1)
        M.clock = t.at
        if not t.cancelled then
            t.fn(t.handle)
            if t.every then t.at = M.clock + t.every; M.timers[#M.timers + 1] = t end
        end
        M.pump()
    end
    M.clock = target
    M.pump()
end

-- Livre les messages en attente à tous les clients (l'émetteur reçoit aussi le sien, comme en jeu).
function M.pump()
    while #M.queue > 0 do
        local m = table.remove(M.queue, 1)
        for _, c in ipairs(M.clients) do
            for _, f in ipairs(c.frames) do
                if f._events and f._events.CHAT_MSG_ADDON and f._scripts.OnEvent then
                    f._scripts.OnEvent(f, "CHAT_MSG_ADDON", m.prefix, m.msg, m.channel, m.sender)
                end
            end
        end
    end
end

local function stubObject(c, kind, parent)
    local o = { _kind = kind, _scripts = {}, _shown = kind ~= "Frame" or true, _parent = parent, _text = "" }
    c.frames[#c.frames + 1] = o
    return setmetatable(o, { __index = function(_, k)
        if not k:match("^%u") then return nil end -- champs Lua (b.t, _events...) : pas des méthodes WoW
        if k:match("^Get") or k:match("^Create") then
            return function() return stubObject(c, "Region", o) end
        end
        return function() end
    end })
end

function M.client(name, group, locale)
    local c = { name = name, frames = {}, out = {}, tips = {}, env = nil, dist = {}, locked = false, followed = nil }
    M.clients[#M.clients + 1] = c
    local function others()
        local t = {}
        for _, n in ipairs(group) do if n ~= name then t[#t + 1] = n end end
        return t
    end
    local function unitName(u)
        if u == "player" then return name end
        local i = tonumber((u or ""):match("^party(%d)$"))
        return i and others()[i]
    end
    -- GetUnitName(u, true) : royaume ajouté seulement s'il diffère du mien.
    local function fullName(u)
        local n = unitName(u)
        if n and realmOf(n) ~= realmOf(name) then return n .. " " .. realmOf(n) end
        return n
    end

    local function frame(kind, fname, parent)
        local f = stubObject(c, kind, parent)
        f._shown = true
        function f:SetScript(k, fn) self._scripts[k] = fn end
        function f:GetScript(k) return self._scripts[k] end
        function f:RegisterEvent(e) self._events = self._events or {}; self._events[e] = true end
        function f:IsEventRegistered(e) return self._events ~= nil and self._events[e] == true end
        function f:Show() if not self._shown then self._shown = true; if self._scripts.OnShow then self._scripts.OnShow(self) end end end
        function f:Hide() self._shown = false end
        function f:SetShown(v) if v then self:Show() else self:Hide() end end
        function f:IsShown() return self._shown end
        function f:IsVisible() local p = self; while p do if p._shown == false then return false end; p = p._parent end return true end
        function f:SetText(t) self._text = t end
        function f:GetText() return self._text end
        function f:SetEnabled(v) self._disabled = not v end
        function f:Enable() self._disabled = false end
        function f:Disable() self._disabled = true end
        function f:IsEnabled() return not self._disabled end
        function f:GetWidth() return 100 end
        function f:SetRotation(r) self._rot = r end
        function f:GetStringWidth() return 50 end
        function f:CreateFontString() local fs = frame("FontString", nil, self); return fs end
        function f:CreateTexture() return frame("Texture", nil, self) end
        function f:GetFontString() self._fs = self._fs or frame("FontString", nil, self); return self._fs end
        function f:Click() if self._scripts.OnClick and not self._disabled then self._scripts.OnClick(self, "LeftButton") end end
        -- Comme en jeu ici : un nom déjà pris (fonction globale...) n'est pas remplacé par le cadre.
        if fname and rawget(c.env, fname) == nil then c.env[fname] = f end
        return f
    end

    local env = setmetatable({}, { __index = _G })
    c.env = env
    env.print = function(...) local t = { ... }; c.out[#c.out + 1] = table.concat(t, " ") end
    env.unpack = table.unpack
    env.tinsert = table.insert
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.CreateFrame = function(kind, fname, parent) return frame(kind, fname, parent) end
    env.UIParent = frame("Frame")
    env.UISpecialFrames = {}
    env.UIErrorsFrame = { AddMessage = function(_, m) c.out[#c.out + 1] = "[alerte] " .. m end }
    env.GameTooltip = frame("Frame")
    function env.GameTooltip:SetText(t) -- comme en jeu : du texte, sinon erreur
        assert(type(t) == "string" or type(t) == "number", "GameTooltip:SetText reçoit un " .. type(t))
        c.tips[#c.tips + 1] = tostring(t)
    end
    env.GameTooltip_Hide = function() end
    env.SOUNDKIT = setmetatable({}, { __index = function(_, k) return k end })
    env.PlaySound = function() end
    env.PlaySoundFile = function() return false end
    env.GetTime = function() return M.clock end
    env.C_Timer = {
        After = function(s, fn) M.timers[#M.timers + 1] = { at = M.clock + s, fn = fn } end,
        NewTicker = function(s, fn)
            local h = {}
            local t = { at = M.clock + s, fn = fn, every = s, handle = h }
            h.Cancel = function() t.cancelled = true end
            M.timers[#M.timers + 1] = t
            return h
        end,
    }
    env.C_AddOns = { GetAddOnMetadata = function() return c.version or "1.2" end }
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() end,
        InChatMessagingLockdown = function() return c.locked end,
        SendAddonMessage = function(prefix, msg, channel, target)
            assert(#msg <= 255, "message trop long : " .. msg)
            M.queue[#M.queue + 1] = { prefix = prefix, msg = msg, channel = channel, sender = name .. " " .. realmOf(name),
}
        end,
        SendChatMessage = function(msg) M.log[#M.log + 1] = name .. ": " .. msg end,
    }
    env.IsInGroup = function() return #group > 1 end
    env.IsInRaid = function() return false end
    env.LE_PARTY_CATEGORY_INSTANCE = 2
    env.GetNumSubgroupMembers = function() return #group - 1 end
    env.GetNumGroupMembers = function() return #group end
    env.UnitIsUnit = function(a, b) return unitName(a) == unitName(b) end
    env.GetUnitName = function(u) return fullName(u) end
    env.UnitName = function(u) return unitName(u) end
    env.UnitExists = function(u) return unitName(u) ~= nil end
    env.UnitInParty = function(u) return unitName(u) ~= nil end
    env.UnitInRaid = function() return nil end
    env.UnitClass = function() return "Mage", "MAGE" end
    env.UnitIsConnected = function() return true end
    env.UnitIsDeadOrGhost = function() return false end
    env.UnitDistanceSquared = function(u) local d = c.dist[unitName(u)] or 10; return d * d, true end
    env.UnitInRange = function() return true, true end
    env.UnitPosition = function(u)
        local p = M.pos[unitName(u)]
        if p then return p[1], p[2], 0, 0 end -- comme en jeu : nord puis ouest
    end
    env.GetPlayerFacing = function() return c.facing or 0 end
    env.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
    env.GetBindingKey = function() return nil end
    env.FollowUnit = function(u) c.followed = unitName(u) end
    env.StaticPopupDialogs = {}
    env.StaticPopup_Show = function(which, a, b, data) c.popup = { which = which, data = data } end
    env.StaticPopup_Hide = function() c.popup = nil end
    env.Ambiguate = function(n) return n end
    env.strsplit = function(sep, s)
        local t = {}
        for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do t[#t + 1] = part end
        return table.unpack(t)
    end
    env.SlashCmdList = {}
    env.GetLocale = function() return locale or "frFR" end
    env.math = math
    return c
end

-- Envoie un événement (ex. GROUP_ROSTER_UPDATE) à tous les cadres d'un client.
function M.fire(c, event, ...)
    for _, f in ipairs(c.frames) do
        if f._events and f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
    end
end

-- Fichiers de l'addon, dans l'ordre du .toc.
function M.files()
    local t = {}
    for line in readfile("Pedibus.toc"):gmatch("[^\r\n]+") do
        line = line:gsub("%s+$", ""):gsub("\\", "/")
        if line ~= "" and not line:match("^#") then t[#t + 1] = line end
    end
    return t
end

-- Charge les fichiers du .toc dans l'environnement du client.
function M.load(c, files)
    local ns = {}
    for _, f in ipairs(files) do assert(loadfile(f, "t", c.env))("Pedibus", ns) end
    c.ns = ns
    M.pump()
    return c
end

-- Trouve un bouton visible par son texte (comme un joueur qui lit l'écran).
function M.button(c, label)
    local function visible(f)
        while f do
            if f._shown == false then return false end
            f = f._parent
        end
        return true
    end
    for _, f in ipairs(c.frames) do
        if f._kind == "Button" and f._text == label and visible(f) then return f end
    end
    error(c.name .. " : pas de bouton « " .. label .. " »")
end

function M.said(c, pattern)
    for _, l in ipairs(c.out) do if l:find(pattern) then return true end end
    return false
end

return M

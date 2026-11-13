-- Traductions : aucune clé manquante ou en trop, mêmes %s/%d et codes couleur que le français,
-- puis un trajet complet dans chaque langue (sans erreur, et sans français oublié en anglais).
-- Lancer depuis le dossier de l'addon : node tests/run.js tests/locale_check.lua
local W = dofile("tests/wow.lua")
local FILES = W.files()
local LOCALES = { "enUS", "deDE", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }

-- Clés utilisées dans le code : tous les L["..."] des fichiers hors Locales.
local keys, nKeys = {}, 0
for _, f in ipairs(FILES) do
    if not f:match("^Locales") then
        local src = readfile(f)
        for raw in src:gmatch('L%["(.-)"%]') do
            local k = load('return "' .. raw .. '"')()
            if not keys[k] then keys[k] = f; nKeys = nKeys + 1 end
        end
    end
end
assert(nKeys > 200, "trop peu de clés trouvées : " .. nKeys)

local function signature(s)
    local t = {}
    for spec in s:gmatch("%%[%-%d%.]*[sd%%]") do t[#t + 1] = spec end
    local _, c = s:gsub("|c", ""); local _, r = s:gsub("|r", "")
    return table.concat(t, " ") .. " |c" .. c .. " |r" .. r
end

local problems = {}
for _, loc in ipairs(LOCALES) do
    local env = setmetatable({ GetLocale = function() return loc end }, { __index = _G })
    local ns = {}
    for _, f in ipairs(FILES) do
        if f:match("^Locales") then assert(loadfile(f, "t", env))("Pedibus", ns) end
    end
    local T = ns.T[ns.LOCALE]
    assert(T, loc .. " : aucune table de traduction")
    for k, f in pairs(keys) do
        local v = T[k]
        if type(v) ~= "string" or v == "" then
            problems[#problems + 1] = ("%s : manque « %s » (%s)"):format(loc, k, f)
        elseif signature(v) ~= signature(k) then
            problems[#problems + 1] = ("%s : « %s » -> « %s » (%s / %s)"):format(loc, k, v, signature(k), signature(v))
        end
    end
    for k in pairs(T) do
        if not keys[k] then problems[#problems + 1] = ("%s : clé inutilisée « %s »"):format(loc, k) end
    end
end
assert(#problems == 0, "\n" .. table.concat(problems, "\n"))

-- Trajet complet dans chaque langue ---------------------------------------------------------
local FRENCH = { "é", "è", "à", "ê", "ç", "ô", "û", "Arrêt", "chauffeur", "Monter", "Suivre" } -- « » : aussi russes
for _, loc in ipairs(LOCALES) do
    W.clients, W.timers, W.queue = {}, {}, {}
    local GROUP = { "Alice", "Bob" }
    local alice = W.load(W.client("Alice", GROUP, loc), FILES)
    local bob = W.load(W.client("Bob", GROUP, loc), FILES)
    local L = alice.ns.L
    local function step(s) W.advance(s or 1) end

    alice.env.PedibusToggle(); step(6)
    W.button(alice, L["Je conduis"]):Click(); step()
    assert(bob.popup and bob.popup.which == "PEDIBUS_JOIN", loc .. " : pas d'invitation")
    bob.env.StaticPopupDialogs.PEDIBUS_JOIN.OnAccept(nil, "Alice"); step(2)
    W.button(bob, L["Arrêt ?"]):Click(); step()
    alice.env.StaticPopupDialogs.PEDIBUS_ASK.OnAccept(nil, "Bob"); step()
    bob.env.StaticPopupDialogs.PEDIBUS_HALT.OnAccept(); step()
    assert(W.said(alice, L["Tout le monde a fini !"]:gsub("%p", "%%%0")), loc .. " : arrêt incomplet")
    bob.env.SlashCmdList.PEDIBUS("debug")
    bob.env.SlashCmdList.PEDIBUS("arrow")
    -- Chaque onglet de jeu, puis une partie de Yams en solo et une table de poker à deux.
    bob.ns.toggleGames(); alice.ns.toggleGames()
    for _, tab in ipairs({ L["Bataille"], L["Puissance 4"], L["Poker"], L["Yams"] }) do
        W.button(bob, tab):Click()
    end
    W.button(bob, L["Nouvelle partie de Yams"]):Click()
    W.button(bob, L["Commencer"]):Click()
    W.button(bob, L["Lancer"]):Click()
    W.button(bob, L["Poker"]):Click(); W.button(alice, L["Poker"]):Click()
    W.button(bob, L["Nouvelle table de poker"]):Click(); step()
    W.button(alice, L["Rejoindre la table de poker de %s"]:format("Bob")):Click(); step(3)
    for _, c in ipairs({ alice, bob }) do -- survol de tout ce qui a une infobulle
        for _, f in ipairs(c.frames) do if f._scripts.OnEnter then f._scripts.OnEnter(f) end end
    end
    W.button(alice, L["Terminus"]):Click(); step()

    if loc ~= "esES" and loc ~= "esMX" and loc ~= "itIT" and loc ~= "ptBR" then -- ces langues ont des accents
        for _, c in ipairs({ alice, bob }) do
            local seen = {}
            for _, l in ipairs(c.out) do seen[#seen + 1] = l end
            for _, l in ipairs(c.tips) do seen[#seen + 1] = l end
            for _, f in ipairs(c.frames) do
                if (f._kind == "FontString" or f._kind == "Button") and f._shown ~= false then
                    seen[#seen + 1] = tostring(f._text)
                end
            end
            for _, l in ipairs(seen) do
                local clean = l:gsub("Pédibus", "") -- nom de l'addon, gardé tel quel
                for _, w in ipairs(FRENCH) do
                    assert(not clean:find(w, 1, true), ("%s : texte français oublié : %s"):format(loc, l))
                end
            end
        end
    end
end
print("locales ok (" .. nKeys .. " textes, " .. #LOCALES .. " langues)")

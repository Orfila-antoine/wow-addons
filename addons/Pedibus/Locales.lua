-- Traductions. Le texte français sert de clé : L["Monter"] donne "Monter" en français,
-- la traduction ailleurs. Chaque fichier Locales/xxXX.lua remplit ns.T[langue] pour sa langue.
-- Texte absent d'une langue : anglais, puis français. tests/locale_check.lua vérifie qu'il n'en manque aucun.
local _, ns = ...
if ns.env and setfenv then setfenv(1, ns.env) end -- mode démo (demo/Demo.lua) : faux groupe
local LOCALE = GetLocale()
if LOCALE == "esMX" then LOCALE = "esES" end
if LOCALE == "enGB" then LOCALE = "enUS" end
ns.LOCALE, ns.T = LOCALE, {}
ns.L = setmetatable({}, { __index = function(cache, fr)
    local cur, en = ns.T[LOCALE], ns.T.enUS
    local text = cur and cur[fr] or (LOCALE ~= "frFR" and en and en[fr]) or fr
    cache[fr] = text
    return text
end })

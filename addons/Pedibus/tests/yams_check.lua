-- Vérifie le calcul des points du Yams hors du jeu : lua tests/yams_check.lua
local ns = {}
assert(loadfile("Yams.lua"))("Pedibus", ns)
local s, t = ns.yamsScore, ns.yamsTotal
assert(s(1, { 1, 1, 2, 3, 1 }) == 3)
assert(s(6, { 6, 6, 2, 3, 1 }) == 12)
assert(s(7, { 4, 4, 4, 2, 1 }) == 15 and s(7, { 4, 4, 3, 2, 1 }) == 0)
assert(s(8, { 5, 5, 5, 5, 1 }) == 21 and s(8, { 5, 5, 5, 1, 1 }) == 0)
assert(s(9, { 2, 2, 3, 3, 3 }) == 25 and s(9, { 3, 3, 3, 3, 3 }) == 0)
assert(s(10, { 3, 4, 5, 6, 6 }) == 30 and s(10, { 1, 2, 4, 5, 6 }) == 0)
assert(s(11, { 2, 3, 4, 5, 6 }) == 40 and s(11, { 1, 2, 3, 4, 6 }) == 0)
assert(s(12, { 6, 6, 6, 6, 6 }) == 50 and s(12, { 6, 6, 6, 6, 5 }) == 0)
assert(s(13, { 1, 2, 3, 4, 5 }) == 15)
local sheet = { 3, 6, 9, 12, 15, 18 } -- 63 en haut -> prime
assert(select(2, t(sheet)) == 35 and t(sheet) == 98)
sheet[6] = 12
assert(select(2, t(sheet)) == 0)
print("yams ok")

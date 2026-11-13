// Lance un fichier Lua de test avec fengari (Lua 5.3 en JavaScript) : npm i fengari, puis
// node tests/run.js tests/sim_check.lua   (depuis le dossier de l'addon)
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
// readfile(chemin) : contenu brut d'un fichier (fengari n'a pas io.open).
lua.lua_pushcfunction(L, (L) => {
  const buf = require('fs').readFileSync(lua.lua_tojsstring(L, 1));
  lua.lua_pushstring(L, new Uint8Array(buf));
  return 1;
});
lua.lua_setglobal(L, to_luastring('readfile'));
let failed = false;
for (const f of process.argv.slice(2)) {
  if (lauxlib.luaL_dofile(L, to_luastring(f)) !== 0) {
    console.log('ÉCHEC ' + f + ' : ' + lua.lua_tojsstring(L, -1));
    lua.lua_settop(L, 0);
    failed = true;
  }
}
process.exit(failed ? 1 : 0);

# Copie Pedibus dans le dossier AddOns de WoW Forever.
#   python tools/install.py          version normale (celle du zip)
#   python tools/install.py --demo   + mode démo : 4 faux membres de groupe, interface en anglais
import os, shutil, sys

SRC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DST = r"F:\Wow\World of Warcraft\_forever_\Interface\AddOns\Pedibus"
demo = "--demo" in sys.argv

toc = open(os.path.join(SRC, "Pedibus.toc"), encoding="utf-8").read()
files = [l.strip().replace("\\", "/") for l in toc.splitlines() if l.strip() and not l.startswith("#")]
os.makedirs(os.path.join(DST, "Locales"), exist_ok=True)
for f in files + ["Bindings.xml"]:
    shutil.copyfile(os.path.join(SRC, f), os.path.join(DST, f))

demo_file = os.path.join(DST, "Demo.lua")
if demo:
    shutil.copyfile(os.path.join(SRC, "demo", "Demo.lua"), demo_file)
    assert "\nLocales.lua\n" in toc
    toc = toc.replace("\nLocales.lua\n", "\nDemo.lua\nLocales.lua\n")  # avant tout le reste
    toc = toc.replace("## Title: Pedibus\n", "## Title: Pedibus |cffff9a1a(DEMO)|r\n")
elif os.path.exists(demo_file):
    os.remove(demo_file)
with open(os.path.join(DST, "Pedibus.toc"), "w", encoding="utf-8", newline="\n") as out:
    out.write(toc)
print("installé" + (" en mode DÉMO" if demo else "") + " :", DST)

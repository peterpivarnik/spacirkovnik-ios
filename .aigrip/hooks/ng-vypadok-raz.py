#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Výpadková veta raz za výpadok na človeka (kus Z261116-31a7d4, 16. 11. 2026).

PREČO: PS 16. 11. videl tú istú vetu („Teraz neviem spätne overiť to, čo som zapísal bez pýtania…“) v sedeniach na serveri
znova a znova, hoci sama hovorí, že od neho nič netreba. Háčik ng-vypadok.sh ju dával KAŽDÉMU štartu sedenia, kým výpadok
trval — 16. 11. ráno PS za 70 minút sedemkrát (ps-domov, bpw, am-ps, ADM, produkt-dailychecks, mpai dvakrát). Pokyn
„ak si ju v tomto sedení už povedal, neopakuj“ platil len v jednom sedení; nové sedenie o predošlom nevie.

PRAVIDLO: človek počuje každú vetu raz za výpadok — znova až vtedy, keď výpadok skončí a vráti sa (veta dostane nový čas
„od“), alebo keď sa zmení, čo od neho treba (iná veta je iný text, povie sa). Výpadok rozpozná čas „od“ zo súboru
vypadok-od.json vedľa vypadok.txt (zapisuje ho vykreslenie, ng-vypadkove-vety.zapis_od); keď ten súbor chýba (Mac PS — sonda
nesie len vypadok.txt), je výpadkom súvislý čas, keď háčik vetu videl: povedaná veta sa zabudne, keď ju háčik pri štarte
sedenia nájde preč.

POVEDANÁ = veta, ktorú háčik dal sedeniu človeka, a človek v tom sedení potom napísal (prvá odpoveď partnera ju niesla —
podľa toho istého meria doručenie ng-hooky-ludia.py). Sedenie, ktoré človek otvoril a nič do neho nenapísal, vetu
nespotrebuje: ďalšie sedenie ju dostane. Preto sa pri výstupe len ZAPÍŠE ponuka (veta · od · zápis sedenia · posun
v ňom) a vybaví sa pri najbližšom behu háčika — pozrie do zápisu sedenia, či človek po ponuke napísal. Sedenie bez človeka
(claude -p, vstup „sdk…“ — rovnako ako ho vynecháva meranie) ponuku nezapíše. Sedenia spustené naraz (do SUBEZNE
sekúnd — obnova okna VS Code obnoví všetky naraz) dostanú vetu len v prvom; keď človek napíše len do iného, ponuka
ostane nevybavená a vetu dostane jeho ďalšie sedenie (oneskorenie, nie ticho). Zvyšok: sedenie otvorené neskôr, no skôr,
než človek napísal do toho, ktoré vetu dostalo, ju dostane tiež (háčik pri štarte nevie, kam človek napíše).

Stav človeka: ~/.aigrip-ng/vypadok-povedane.json (NG_VYPADOK_POVEDANE pre skúšku) — v jeho vlastnom domove; háčik u kolegu
do domova PS nepíše a naopak. Bez vstupu háčika (ručný beh, skúška bez sedenia) sa stav len číta, nič sa nezapíše.

  ng-vypadok-raz.py <vypadok.txt>   (vstup háčika SessionStart na stdin) → na výstup to, čo má sedenie dostať; kód 0.
  Pri prázdnom súbore (výpadok skončil) háčik pomocníka volá tiež, keď človek má stav — povedané sa tým zabudne.
  Kód 3 = neviem rozhodnúť (pokazený stav, neznámy tvar) — háčik potom vypíše celý súbor ako doteraz: radšej veta
  navyše než ticho. Pri neznámom tvare súboru (bez pokynu „NG: povedz človeku“) sa súbor vypíše celý.

Kópia tohto súboru ide v balíku vedľa háčika (balik.hooky) — na Macu PS nie je spoločné miesto stroja. Preto nič
neimportuje zo stroja; pokyn() musí byť zhodný s ng-vypadkove-vety.pokyn() (stráži červený test „vypadok-raz“).
"""
import os, io, re, sys, json, time, datetime

POKYN = 'NG: povedz človeku'
OD_MENO = 'vypadok-od.json'
PONUKA_NAJDLHSIE = 2 * 86400      # ponuka, po ktorej človek do dvoch dní nenapísal, zanikne (sedenie ostalo bez neho)
CITAJ_NAJVIAC = 8 * 1024 * 1024   # zo zápisu sedenia za ponukou sa číta najviac toľko — hľadá sa len prvá správa človeka
PRERUSENIE = '[Request interrupted'
SUBEZNE = 120   # sedenia spustené naraz (obnova okna VS Code: ps-domov a bpw 16. 11. 6:06:07 a 6:06:08) — vetu dostane prvé


def pokyn(n):
    """Prvý riadok pre partnera — zhodný s ng-vypadkove-vety.pokyn() (podľa neho meria doručenie ng-hooky-ludia.py)."""
    jedna = n == 1
    return ('NG: povedz človeku na začiatku odpovede doslova ' + ('túto vetu' if jedna else 'tieto vety')
            + ' a nič technické k ' + ('nej' if jedna else 'nim') + ' nepridávaj; ak si ' + ('ju' if jedna else 'ich')
            + ' v tomto sedení už povedal, neopakuj:')


def vety_z_textu(t):
    """Vety pre človeka zo súboru vypadok.txt → [veta]; None = neznámy tvar (súbor sa potom vypíše celý)."""
    ls = str(t or '').split('\n')
    if not ls or not ls[0].startswith(POKYN):
        return None
    v = []
    for x in ls[1:]:
        if not x.strip():
            continue
        if not x[:1].isspace():
            return None
        v.append(x.strip())
    return v or None


def text(vety):
    return '\n'.join([pokyn(len(vety))] + ['   ' + v for v in vety]) + '\n' if vety else ''


def nacitaj_od(cesta_v):
    """{veta: od} zo súboru vedľa vypadok.txt; {} keď chýba alebo sa nedá prečítať (výpadok sa rozpozná bez neho)."""
    try:
        d = json.load(io.open(os.path.join(os.path.dirname(os.path.abspath(cesta_v)), OD_MENO), encoding='utf-8'))
        return {str(k): str(v) for k, v in (d.get('vety') or {}).items() if v}
    except Exception:
        return {}


def _ludska(e):
    """Správa človeka (nie výsledok nástroja, nie pomocná správa, nie zastavenie ťahu) — ako ng-hooky-ludia._ludska."""
    if e.get('type') != 'user' or e.get('isSidechain') or e.get('isMeta'):
        return False
    c = (e.get('message') or {}).get('content')
    if isinstance(c, str):
        return bool(c.strip()) and not c.lstrip().startswith(('<command-', '<local-command', 'Caveat:', PRERUSENIE))
    if isinstance(c, list):
        typy = {x.get('type') for x in c if isinstance(x, dict)}
        if 'tool_result' in typy or not typy & {'text', 'image'}:
            return False
        return 'image' in typy or not all(str(x.get('text') or '').lstrip().startswith(PRERUSENIE)
                                          for x in c if isinstance(x, dict) and x.get('type') == 'text')
    return False


def _cas(s):
    try:
        return datetime.datetime.fromisoformat(str(s).replace('Z', '+00:00')).timestamp()
    except Exception:
        return None


def napisal_po(prepis, posun, kedy):
    """Napísal človek do zápisu sedenia po ponuke? True / False; None = zápis sa nedá prečítať."""
    try:
        with open(prepis, 'rb') as f:
            f.seek(max(0, int(posun or 0)))
            zvysok = b''; precital = 0
            while precital < CITAJ_NAJVIAC:
                kus = f.read(262144)
                if not kus:
                    break
                precital += len(kus)
                riadky = (zvysok + kus).split(b'\n'); zvysok = riadky.pop()
                for l in riadky:
                    if b'"user"' not in l:
                        continue
                    try:
                        e = json.loads(l.decode('utf-8', 'replace'))
                    except Exception:
                        continue
                    t = _cas(e.get('timestamp'))
                    if _ludska(e) and (t is None or t >= kedy - 5):
                        return True
            return False
    except OSError:
        return None


def _zamok(cesta):
    try:
        import fcntl
        f = open(cesta + '.zamok', 'a')
        fcntl.flock(f, fcntl.LOCK_EX)
        return f
    except Exception:
        return None


def _rovnaky_vypadok(zaznam_od, od):
    """Je povedaná veta z toho istého výpadku? Čas „od“ známy na oboch stranách = musí sedieť; keď ho niektorá strana
    nemá (súbor od chýbal pri povedaní alebo teraz), rozhoduje súvislosť — veta je od povedania stále v súbore."""
    return not zaznam_od or not od or zaznam_od == od


def rozhodni(vety, od, stav, sedenie, now):
    """Čisté jadro (bez súborov): (vety pre toto sedenie, nový stav). sedenie = {'prepis','posun','id','clovek'} alebo None."""
    teraz = [(v, od.get(v)) for v in vety]
    pov = [z for z in (stav.get('povedane') or []) if isinstance(z, dict)]
    pon = [z for z in (stav.get('ponuky') or []) if isinstance(z, dict)]
    platne = lambda z: any(z.get('veta') == v and _rovnaky_vypadok(z.get('od'), o) for v, o in teraz)
    # 1) ponuky: vybaviť (človek napísal = povedaná), alebo zahodiť (výpadok skončil, stará), alebo nechať čakať
    nove_pon = []
    for z in pon:
        if not platne(z):
            continue
        n = napisal_po(z.get('prepis'), z.get('posun'), float(z.get('kedy') or 0)) if z.get('prepis') else None
        if n:
            pov.append(dict(veta=z.get('veta'), od=z.get('od'), kedy=z.get('kedy'), prepis=z.get('prepis')))
        elif now - float(z.get('kedy') or 0) <= PONUKA_NAJDLHSIE:
            nove_pon.append(z)
    # 2) povedané: len tie, ktorých výpadok trvá (veta zmizla alebo má nový čas „od“ = výpadok skončil)
    pov = [z for z in pov if platne(z)]
    # 3) čo toto sedenie dostane: každá veta, ktorú človek v jej výpadku ešte nepočul
    von = [v for v, o in teraz if not any(z.get('veta') == v and _rovnaky_vypadok(z.get('od'), o) for z in pov)]
    # sedenia spustené naraz: vetu, ktorú pred chvíľou dostalo iné sedenie a človek doň ešte nenapísal, toto nedostane
    sub = [z for z in nove_pon if now - float(z.get('kedy') or 0) <= SUBEZNE
           and not (sedenie and z.get('prepis') == sedenie.get('prepis'))]
    von = [v for v in von if not any(z.get('veta') == v and _rovnaky_vypadok(z.get('od'), od.get(v)) for z in sub)]
    if sedenie and sedenie.get('clovek') and sedenie.get('prepis'):
        nove_pon = [z for z in nove_pon if not (z.get('prepis') == sedenie['prepis'] and z.get('veta') in von)]
        for v in von:
            nove_pon.append(dict(veta=v, od=od.get(v), kedy=now, prepis=sedenie['prepis'],
                                 posun=sedenie.get('posun') or 0, sedenie=sedenie.get('id')))
    return von, dict(povedane=pov[-50:], ponuky=nove_pon[-50:])


def hlavny(argv, vstup, env, now=None):
    """(výstup, kód) — kód 3 = háčik vypíše celý súbor sám. NG_VYPADOK_TERAZ (epocha) len pre červený test."""
    try:
        now = now or float(env.get('NG_VYPADOK_TERAZ') or 0) or time.time()
    except ValueError:
        now = time.time()
    if len(argv) < 2:
        return '', 3
    cesta_v = argv[1]
    try:
        obsah = io.open(cesta_v, encoding='utf-8').read()
    except Exception:
        return '', 3
    # prázdny súbor = pre človeka všetko beží: povedané sa zabudne (keď sa výpadok vráti, počuje ho znova aj bez času „od“)
    vety = [] if not obsah.strip() else vety_z_textu(obsah)
    if vety is None:
        return obsah, 0   # neznámy tvar — vypíše sa celý ako doteraz
    sedenie = None
    try:
        d = json.loads(vstup) if vstup and vstup.strip() else None
    except Exception:
        d = None
    if isinstance(d, dict) and d.get('transcript_path'):
        p = str(d['transcript_path'])
        try:
            posun = os.path.getsize(p)
        except OSError:
            posun = 0
        if str(d.get('source') or 'startup') == 'startup':
            posun = 0   # nové sedenie: všetko v zápise je až po háčiku
        sedenie = dict(prepis=p, posun=posun, id=d.get('session_id'),
                       clovek=not str(env.get('CLAUDE_CODE_ENTRYPOINT') or '').startswith('sdk'))
    cesta_s = env.get('NG_VYPADOK_POVEDANE') or os.path.join(env.get('HOME') or os.path.expanduser('~'), '.aigrip-ng',
                                                             'vypadok-povedane.json')
    zapisat = sedenie is not None
    z = None
    if zapisat:
        try:
            os.makedirs(os.path.dirname(cesta_s), exist_ok=True)
        except OSError:
            return '', 3
        z = _zamok(cesta_s)
    try:
        try:
            stav = json.load(io.open(cesta_s, encoding='utf-8'))
            if not isinstance(stav, dict):
                return '', 3
        except FileNotFoundError:
            stav = {}
        except Exception:
            return '', 3   # pokazený stav — radšej celý súbor než ticho
        von, novy = rozhodni(vety, nacitaj_od(cesta_v), stav, sedenie, now)
        if zapisat and novy != stav:
            t = cesta_s + '.tmp.%d' % os.getpid()
            with io.open(t, 'w', encoding='utf-8') as f:
                json.dump(novy, f, ensure_ascii=False)
            os.replace(t, cesta_s)
        return text(von), 0
    finally:
        if z:
            z.close()


if __name__ == '__main__':
    try:
        vstup = '' if sys.stdin.isatty() else sys.stdin.read()
    except Exception:
        vstup = ''
    try:
        von, kod = hlavny(sys.argv, vstup, os.environ)
    except Exception:
        von, kod = '', 3
    if von:
        sys.stdout.write(von); sys.stdout.flush()
    sys.exit(kod)

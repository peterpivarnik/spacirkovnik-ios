#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Ťuk na kartu poistky (PS 19. 11. 2026, STAVBA 4.1172 b, kľúč AIG-R261119-3d2f0e: „4.1172 — b, f, h“).

Prečo: poistka (ng-kotva.sh) pustí nevratný krok len na slová, ktoré človek napísal v sedení. Z auta (hlasový asistent)
ich napísať nevie a zhrnutie asistenta ani jeho „áno“ súhlasom s presným krokom nie je (Hetzner 19. 11. 12:45). Pri (b)
platí ako napísané áno ťuk na kartu, ktorú zostavil stroj zo zastaveného príkazu — komu, kópia, predmet, prílohy, celý text.

Ten istý modul používajú obe strany, preto sa odtlačok a karta rátajú rovnako:
  · kotva v izbe partnera (ng-kotva.sh): pri zastavení zapíše čakajúcu kartu do ~/.aigrip-ng/tuky/caka.jsonl; pri
    opakovaní toho istého príkazu prepočíta odtlačok a pustí ho, keď k nemu je platný ťuk;
  · služba ťukov mimo izby (aig-admin-api ako root, riadiace centrum): kartu zostaví znova zo samotného príkazu
    a súborov (záznamu v izbe neverí), ukáže ju prihlásenému človeku a ťuk zapíše do TUKY (root, 0644).

Čo karta smie byť (len pomenovaný nástroj, ktorý vie stroj na karte opísať celý): `python3 ~/.config/aigrip/graph_mail.py
send --to … --subject … --body-file … [--cc …] [--bcc …] [--attach …]… [--bez-podpisu]` — nástroj na presnej ceste a
s presným odtlačkom obsahu, všetky slová doslovné (žiadne $, `, ;, |, &, <, >, zátvorky, nový riadok), voľby celé
(skratky argparse nie). Čokoľvek iné ostáva na napísané slovo — aj vlastný kód partnera.

Odtlačok = sha256 z: verzie, id sedenia, priečinka, nástroja a jeho odtlačku, všetkých volieb a odtlačku obsahu textu
a každej prílohy. Keď partner po karte zmení text alebo prílohu, odtlačok nesedí a ťuk neplatí.
Ťuk platí raz (pouzite.jsonl), pre to isté sedenie a do OKNO_S po ťuku; ťuk musí prísť do OKNO_S po zastavení (to stráži
služba ťukov podľa svojich hodín).

  ng-tuk.py kotva <stopa.jsonl> <cwd> <domov> <podagent 0|1>  < príkaz   → „pusti\\t<id>“ · „karta\\t<id>“ · „nie\\t<dôvod>“
  ng-tuk.py karta <cwd> <domov>                                  < príkaz   → JSON karty alebo „nie\\t<dôvod>“ (skúška)
"""
import hashlib
import html
import json
import os
import re
import secrets
import shlex
import stat
import sys
import time

VERZIA = 1
OKNO_S = 10 * 60
TUKY = '/var/lib/aig-admin-api/centrum-tuky.jsonl'          # píše len aig-admin-api (root)
CAKA_REL = '.aigrip-ng/tuky/caka.jsonl'                    # čakajúce karty (píše kotva v izbe)
POUZITE_REL = '.aigrip-ng/tuky/pouzite.jsonl'              # použité ťuky (píše kotva v izbe)
NASTROJE = {
    'graph_mail': {
        'cesta': '.config/aigrip/graph_mail.py',
        'odtlacky': frozenset({
            '6aaf420731f4195b8a5a4adc4343ed5da607dea1d3a94ff8758047bdd67cf31b',   # 19. 11. 2026 (s podpríkazom oznac)
        }),
        'akcie': {'send'},
    },
}
# 20. 11. 2026 (STAVBA 4.1494 a, PS: „4.1494: (a)“ — koncept poistka-a-hlasovy-asistent časť 10 bod 3; mení 4.1172 b):
# karta aj na POMENOVANÉ NASADENIE NA SERVER — skript na presnej ceste v domove človeka, spustený doslovne
# `bash <skript> --naostro` (nič pred ním, nič za ním). Odtlačok viaže obsah skriptu aj každého súboru, ktorý nasadenie
# inštaluje alebo spúšťa (viazane — aj skúšky, ktoré nasadenie púšťa: čo sa spustí a nie je viazané, mohol by partner
# po karte zmeniť); keď sa po karte zmení čo i len jeden, ťuk ani hlasové áno neplatia. Karta ukáže hlavičku
# skriptu (čo urobí, ako sa vráti) a zoznam viazaných súborov. Zoznam je v tomto module dvakrát: v izbe (poistka) aj
# v /opt/aig-admin-api/ng_tuk.py (služba ťukov, root). Ťuk sa zapíše len podľa kópie služby — nové nasadenie na karte teda
# pribudne až nasadením tohto modulu na slovo PS, nie zápisom partnera do repa.
_CENTRUM = 'projects/aigrip/work/cloud-workspace/browser-access/centrum/'
# nasad-tuky.sh tu nie je: nasadzuje stránku centra z projektu, kde ležia aj nenasadené zmeny iných sedení.
NASADENIA = {
    'nasad-tuky-hlas': {
        'nazov': 'nasadenie hlasového áno ku karte poistky',
        'cesta': _CENTRUM + 'nasad-tuky-hlas.sh',
        'viazane': [_CENTRUM + x for x in ('aig_tuky.py', 'zaplata_server_tuky_hlas.py', 'skuska-tuky.py', 'tuk-pripomienka.py', 'skuska-tuk-pripomienka.py',
                                           'aig-tuk-pripomienka.service', 'aig-tuk-pripomienka.path',
                                           'aig-tuk-pripomienka.timer')] + ['projects/aigrip/.aigrip/scripts/ng-tuk.py'],
    },
}
VOLBY_NASADENIA = ('--naostro',)
BASH = re.compile(r'^(?:/usr/bin/|/bin/)?bash$')
MAX_HLAVICKA = 6000
INTERPRETER = re.compile(r'^(?:/usr/bin/|/usr/local/bin/)?python3(?:\.[0-9]+)?$')
MIMO_UVODZOVIEK = set(';&|<>(){}[]*?$`\\!')   # operátory, rozvinutie, vzory — mimo úvodzoviek krok nie je doslovný
V_DVOJITYCH = set('$`\\!')                    # v "…" shell ešte rozvíja
VOLBY_SEND = {'--to': 'to', '--subject': 'subject', '--body-file': 'body_file', '--cc': 'cc', '--bcc': 'bcc',
              '--attach': 'attach', '--bez-podpisu': 'bez_podpisu'}
MAX_SUBOR = 3 * 1024 * 1024 + 1      # graph_mail.py berie prílohy do 3 MB
FIRMA = ('aspecta.sk', 'gr8it.cloud', 'gr8it.sk')
NASTAVENIA_REL = '.aig-workspace/pouzivatel.json'   # prepínač „tuk_karta“ (nastavenia aig); chýba = len PREDVOLENE
PREDVOLENE = ('pstrocka',)                          # PS 4.1172 b: tebe zapnutý, kolegom vypnutý, kým si ho nezapnú   # adresy vo firme — mimo nich asistent číta celú adresu


def doslovny(prikaz):
    """Časť príkazu pred komentárom (# potvrdené: …, # rozhodnutie: …), keď je celá doslovná: jeden jednoduchý príkaz,
    bez premenných, náhrad, presmerovaní, vzorov a rozvinutia zátvoriek, bez nového riadku. Inak None. Vlnovka len na
    začiatku slova pred „/“. Úvodzovky sa sledujú ako v shelli (v '…' je všetko doslovné, v "…" nie $ ` \\ !)."""
    if not isinstance(prikaz, str) or '\n' in prikaz.rstrip('\n') or '\r' in prikaz:
        return None
    q = None
    zac_slova = True
    for i, c in enumerate(prikaz.rstrip('\n')):
        if q == "'":
            if c == "'":
                q = None
            zac_slova = False
            continue
        if q == '"':
            if c == '"':
                q = None
            elif c in V_DVOJITYCH:
                return None
            zac_slova = False
            continue
        if c in "'\"":
            q = c
            zac_slova = False
            continue
        if c in ' \t':
            zac_slova = True
            continue
        if c == '#' and zac_slova:
            return prikaz[:i]
        if c in MIMO_UVODZOVIEK:
            return None
        if c == '~' and not (zac_slova and prikaz[i + 1:i + 2] == '/'):
            return None
        zac_slova = False
    return None if q else prikaz.rstrip('\n')


def rozober(prikaz, cwd, domov):
    """Príkaz → krok (dict) alebo (None, dôvod). Len doslovný tvar pomenovaného nástroja."""
    telo = doslovny(prikaz)
    if telo is None:
        return None, 'príkaz nie je doslovný (premenné, viac príkazov, presmerovanie, vzory)'
    try:
        slova = shlex.split(telo)
    except ValueError:
        return None, 'príkaz sa nedá rozložiť'
    if not slova:
        return None, 'prázdny príkaz'
    if BASH.match(slova[0]):
        return _rozober_nasadenie(slova, cwd, domov)
    k = 0
    if INTERPRETER.match(slova[0]):
        k = 1
        while k < len(slova) and slova[k] in ('-I', '-u', '-B', '-E', '-s', '-S'):
            k += 1
    if k >= len(slova):
        return None, 'chýba nástroj'
    cesta = slova[k]
    if cesta.startswith('~/'):
        cesta = os.path.join(domov, cesta[2:])
    elif not cesta.startswith('/'):
        cesta = os.path.join(cwd, cesta)
    cesta = os.path.normpath(cesta)
    nastroj = None
    for meno, n in NASTROJE.items():
        if cesta == os.path.join(domov, n['cesta']):
            nastroj = meno
    if not nastroj:
        return None, 'nie je to pomenovaný nástroj, ktorý vie karta opísať'
    if os.path.islink(cesta):
        return None, 'nástroj je odkaz'
    try:
        with open(cesta, 'rb') as f:
            h = hashlib.sha256(f.read()).hexdigest()
    except OSError:
        return None, 'nástroj sa nedá prečítať'
    if h not in NASTROJE[nastroj]['odtlacky']:
        return None, 'nástroj sa zmenil (odtlačok nesedí) — karta by ho nemusela opísať celý'
    if k + 1 >= len(slova) or slova[k + 1] not in NASTROJE[nastroj]['akcie']:
        return None, 'podpríkaz nie je na kartu'
    krok = {'nastroj': nastroj, 'nastroj_odtlacok': h, 'akcia': slova[k + 1], 'to': '', 'subject': '',
            'body_file': '', 'cc': '', 'bcc': '', 'attach': [], 'bez_podpisu': False}
    j = k + 2
    while j < len(slova):
        x = slova[j]
        meno, rovne, hod = x.partition('=')
        if meno not in VOLBY_SEND:
            return None, f'voľba {meno!r} nie je na kartu'
        kl = VOLBY_SEND[meno]
        if kl == 'bez_podpisu':
            if rovne:
                return None, '--bez-podpisu nemá hodnotu'
            krok['bez_podpisu'] = True
            j += 1
            continue
        if not rovne:
            if j + 1 >= len(slova):
                return None, f'{meno} bez hodnoty'
            hod = slova[j + 1]
            j += 2
        else:
            j += 1
        if kl == 'attach':
            krok['attach'].append(hod)
        elif krok[kl]:                       # argparse by vzal poslednú hodnotu — na karte by chýbala prvá
            return None, f'{meno} dvakrát'
        else:
            krok[kl] = hod
    if not krok['to'] or not krok['subject'] or not krok['body_file']:
        return None, 'chýba adresát, predmet alebo text'
    def _abs(p):
        p = os.path.join(domov, p[2:]) if p.startswith('~/') else p
        return os.path.normpath(p if p.startswith('/') else os.path.join(cwd, p))
    krok['body_file'] = _abs(krok['body_file'])
    krok['attach'] = [_abs(p) for p in krok['attach']]
    return krok, ''


def _rozober_nasadenie(slova, cwd, domov):
    """`bash <skript> --naostro` → krok nasadenia alebo (None, dôvod). Len skript zo zoznamu NASADENIA, bez ďalších volieb."""
    if len(slova) != 3 or slova[2] not in VOLBY_NASADENIA:
        return None, 'nasadenie na kartu je len v tvare „bash <skript> --naostro“'
    cesta = slova[1]
    if cesta.startswith('~/'):
        cesta = os.path.join(domov, cesta[2:])
    elif not cesta.startswith('/'):
        cesta = os.path.join(cwd, cesta)
    cesta = os.path.normpath(cesta)
    for meno, n in NASADENIA.items():
        if cesta == os.path.normpath(os.path.join(domov, n['cesta'])):
            if os.path.islink(cesta):
                return None, 'skript nasadenia je odkaz'
            return {'druh': 'nasadenie', 'nasadenie': meno, 'cesta': cesta, 'volby': [slova[2]],
                    'viazane': [os.path.normpath(os.path.join(domov, v)) for v in n['viazane']]}, ''
    return None, 'nie je to pomenované nasadenie, ktoré vie karta opísať'


def _hlavicka(b):
    """Úvodný komentár skriptu (bez shebangu) — čo nasadenie urobí a ako sa vráti; to číta človek na karte."""
    out = []
    for i, l in enumerate(b.decode('utf-8', 'replace').splitlines()):
        if i == 0 and l.startswith('#!'):
            continue
        if not l.startswith('#'):
            break
        out.append(l[1:][1:] if l[1:2] == ' ' else l[1:])
    t = '\n'.join(out).strip()
    return t if len(t) <= MAX_HLAVICKA else t[:MAX_HLAVICKA] + ' …'


def _obsah(p, uid=None, domov=None):
    """Obsah súboru, ktorý krok posiela. Služba ťukov beží ako root (uid = človek): súbor musí patriť človeku a ležať
    v jeho domove alebo v /tmp — inak by karta ukázala cudzí súbor (/etc/…) tomu, kto ju otvorí."""
    if uid is not None:
        r = os.path.realpath(p)
        if not (r.startswith(os.path.realpath(domov) + '/') or r.startswith('/tmp/')):
            raise OSError('súbor nie je v domove človeka ani v /tmp')
        p = r
    fd = os.open(p, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, 'O_NONBLOCK', 0))
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_size > MAX_SUBOR:
            raise OSError('nie je bežný súbor alebo je priveľký')
        if uid is not None and st.st_uid != uid:
            raise OSError('súbor nepatrí človeku')
        with os.fdopen(fd, 'rb') as f:
            fd = None
            return f.read(MAX_SUBOR + 1)
    finally:
        if fd is not None:
            os.close(fd)


def odtlacok(krok, stopa_id, cwd, uid=None, domov=None):
    """(odtlačok, obsahy) — obsahy = {'text': bajty, 'prilohy': [(meno, bajty)]} pre kartu."""
    if krok.get('druh') == 'nasadenie':
        skript = _obsah(krok['cesta'], uid, domov)
        viazane = [(p, _obsah(p, uid, domov)) for p in krok['viazane']]
        zaklad = {'v': VERZIA, 'stopa': stopa_id, 'cwd': cwd, 'krok': {k: v for k, v in krok.items()},
                  'skript': hashlib.sha256(skript).hexdigest(),
                  'viazane': [[p, hashlib.sha256(b).hexdigest()] for p, b in viazane]}
        h = hashlib.sha256(json.dumps(zaklad, sort_keys=True, ensure_ascii=False).encode('utf-8')).hexdigest()
        return h, {'skript': skript, 'viazane': viazane}
    text = _obsah(krok['body_file'], uid, domov)
    prilohy = [(os.path.basename(p), _obsah(p, uid, domov)) for p in krok['attach']]
    zaklad = {'v': VERZIA, 'stopa': stopa_id, 'cwd': cwd,
              'krok': {k: v for k, v in krok.items()},
              'text': hashlib.sha256(text).hexdigest(),
              'prilohy': [hashlib.sha256(b).hexdigest() for _, b in prilohy]}
    h = hashlib.sha256(json.dumps(zaklad, sort_keys=True, ensure_ascii=False).encode('utf-8')).hexdigest()
    return h, {'text': text, 'prilohy': prilohy}


def _adresy(s):
    return [a.strip() for a in (s or '').split(',') if a.strip()]


def karta(krok, obsahy):
    if krok.get('druh') == 'nasadenie':
        n = NASADENIA[krok['nasadenie']]
        hl = _hlavicka(obsahy['skript'])
        return {'druh': 'nasadenie', 'nazov': n['nazov'], 'prikaz': 'bash ~/%s %s' % (n['cesta'], ' '.join(krok['volby'])),
                'popis': hl, 'text': hl,
                'subory': [{'meno': os.path.relpath(p, os.path.dirname(krok['cesta'])), 'velkost': len(b)}
                           for p, b in obsahy['viazane']],
                'komu': [], 'kopia': [], 'skryta': [], 'prilohy': [], 'mimo_firmy': [], 'nevratne': True}
    t = obsahy['text'].decode('utf-8', 'replace')
    if re.search(r'<(html|body|div|p|br|table)\b', t, re.I):
        t = re.sub(r'(?is)<(script|style)\b.*?</\1>', '', t)
        t = re.sub(r'(?i)<br\s*/?>|</p>|</div>|</tr>|</h[1-6]>', '\n', t)
        t = html.unescape(re.sub(r'<[^>]+>', '', t))
        t = re.sub(r'\n{3,}', '\n\n', t).strip()
    komu = _adresy(krok['to'])
    vsetci = komu + _adresy(krok['cc']) + _adresy(krok['bcc'])
    return {'nastroj': f"{krok['nastroj']} {krok['akcia']}", 'komu': komu, 'kopia': _adresy(krok['cc']),
            'skryta': _adresy(krok['bcc']), 'predmet': krok['subject'], 'text': t,
            'podpis': not krok['bez_podpisu'],
            'prilohy': [{'meno': m, 'velkost': len(b)} for m, b in obsahy['prilohy']],
            'mimo_firmy': [a for a in vsetci if not a.lower().rsplit('@', 1)[-1].endswith(FIRMA)],
            'nevratne': True}


def _riadky(p):
    try:
        with open(p, encoding='utf-8') as f:
            for l in f:
                try:
                    o = json.loads(l)
                except ValueError:
                    continue
                if isinstance(o, dict):
                    yield o
    except OSError:
        return


def _tuky_doveryhodne(p):
    """Súbor ťukov musí patriť rootovi a nikto iný doň nesmie písať (ani jeho priečinok) — inak ho nečítame vôbec."""
    try:
        for x in (p, os.path.dirname(p)):
            st = os.stat(x)
            if st.st_uid != 0 or st.st_mode & 0o022:
                return False
        return True
    except OSError:
        return False


def platny_tuk(h, stopa_id, domov, teraz=None):
    teraz = teraz or time.time()
    tuky = os.environ.get('NG_TUK_TUKY') if os.environ.get('NG_KOTVA_SUCHO') == '1' else None
    tuky = tuky or TUKY
    if tuky == TUKY and not _tuky_doveryhodne(tuky):
        return None
    pouzite = {o.get('id') for o in _riadky(os.path.join(domov, POUZITE_REL))}
    for o in _riadky(tuky):
        if o.get('odtlacok') == h and o.get('stopa') == stopa_id and o.get('id') not in pouzite:
            try:
                ep = float(o.get('epoch'))
            except (TypeError, ValueError):
                continue
            if 0 <= teraz - ep <= OKNO_S:
                return o
    return None


def _pripis(p, o):
    os.makedirs(os.path.dirname(p), mode=0o700, exist_ok=True)
    with open(p, 'a', encoding='utf-8') as f:
        f.write(json.dumps(o, ensure_ascii=False, separators=(',', ':')) + '\n')


def zapnute(domov):
    """Prepínač človeka. Vypnutý = ako pred 4.1172 b (ani karta, ani ťuk). Partner ho vie prepnúť aj zapnúť — bez
    skutočného ťuku za prihlásením tým nič neprejde; vypnutím z telefónu sa všetko vráti hneď."""
    try:
        with open(os.path.join(domov, NASTAVENIA_REL), encoding='utf-8') as f:
            v = json.load(f).get('tuk_karta')
        if isinstance(v, bool):
            return v
    except (OSError, ValueError, AttributeError):
        pass
    return os.path.basename(os.path.normpath(domov)) in PREDVOLENE


def sluzba_nasadena():
    t = os.environ.get('NG_TUK_TUKY') if os.environ.get('NG_KOTVA_SUCHO') == '1' else None
    return os.path.exists(t or TUKY)


def kotva(stopa, cwd, domov, podagent, prikaz):
    """Volá ng-kotva.sh pri zastavení kroku: pustiť ťukom, ponúknuť kartu, alebo nič."""
    if podagent in ('1', 'true'):
        return 'nie\tpodagent nepotvrdzuje nič'
    if not zapnute(domov):
        return 'nie\tťuk na kartu má človek vypnutý'
    if not sluzba_nasadena():
        return 'nie\tslužba ťukov nie je nasadená'
    krok, preco = rozober(prikaz, cwd, domov)
    if not krok:
        return 'nie\t' + preco
    # 20. 11. 2026 (4.1494 a): karta mailu len pri zastavení pošty, karta nasadenia len pri zastavení sudo/služby (kanál
    # povie poistka v NG_TUK_KANAL) — súhlas k nasadeniu nesmie pustiť krok, ktorý poistka zastavila pre iný dôvod
    kanal = os.environ.get('NG_TUK_KANAL', 'posta')
    if (krok.get('druh') == 'nasadenie') != (kanal == 'sudo'):
        return 'nie\tkarta k tomuto druhu zastavenia nepatrí'
    stopa_id = os.path.basename(stopa or '')
    if stopa_id.endswith('.jsonl'):
        stopa_id = stopa_id[:-6]
    if not stopa_id:
        return 'nie\tbez stopy sedenia'
    try:
        h, obsahy = odtlacok(krok, stopa_id, cwd)
    except OSError as e:
        return 'nie\tsúbor kroku sa nedá prečítať (%s)' % e
    t = platny_tuk(h, stopa_id, domov)
    if t:
        if os.environ.get('NG_KOTVA_SUCHO') != '1':
            _pripis(os.path.join(domov, POUZITE_REL), {'id': t.get('id'), 'ts': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
                                                         'odtlacok': h, 'stopa': stopa_id})
        return 'pusti\t%s' % t.get('id')
    idk = 'k' + secrets.token_hex(6)
    zaznam = {'id': idk, 'ts': time.strftime('%Y-%m-%dT%H:%M:%S%z'), 'epoch': time.time(), 'stopa': stopa_id,
              'cwd': cwd, 'prikaz': prikaz, 'odtlacok': h,
              'platne_do': time.strftime('%Y-%m-%dT%H:%M:%S%z', time.localtime(time.time() + OKNO_S)),
              'karta': karta(krok, obsahy)}
    if os.environ.get('NG_KOTVA_SUCHO') != '1':
        _pripis(os.path.join(domov, CAKA_REL), zaznam)
    return 'karta\t%s' % idk


def main():
    a = sys.argv[1:]
    prikaz = sys.stdin.read()
    if a[:1] == ['kotva'] and len(a) == 5:
        print(kotva(a[1], a[2], a[3], a[4], prikaz))
        return
    if a[:1] == ['karta'] and len(a) == 3:
        krok, preco = rozober(prikaz, a[1], a[2])
        if not krok:
            print('nie\t' + preco)
            return
        h, ob = odtlacok(krok, 'skuska', a[1])
        print(json.dumps({'odtlacok': h, 'karta': karta(krok, ob)}, ensure_ascii=False, indent=1))
        return
    print(__doc__)
    sys.exit(2)


if __name__ == '__main__':
    main()

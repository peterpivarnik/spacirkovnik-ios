#!/usr/bin/env bash
# Kotva veľkého dosahu ako kód (FD-9 v2, prvok 7; K-6, R44, R53; oponentúra FD-9 #1–#3, #20).
#
# Primitívum: PreToolUse `deny` — platí vo všetkých režimoch nástroja vrátane bypass (na rozdiel od `ask`,
# ktoré sa v bypass neukáže a v prehliadači s vypnutým displejom sa mení na zaseknutie, D-225).
#
# Čo je NEOBNOVITEĽNÝ KANÁL (uzavretý zoznam — nie klasifikácia každého príkazu):
#   1. push do repozitára, ktorý nie je klon toho, kto sedí (cwd mimo jeho domova), alebo push --force / --mirror
#   2. odoslanie mailu alebo správy (poštové skripty, Exchange/Graph sendMail, Teams webhook, crit-notify)
#   3. zápis do cudzieho systému: gh api s POST/PUT/PATCH/DELETE, gh issue/pr create|comment|close|delete, gh repo delete,
#      az … create|delete|update|set|add|remove, curl -X POST/PUT/PATCH/DELETE na graph/sharepoint/atlassian
#   4. zmazanie mimo gitu a mimo vlastných projektov (~/projects/<projekt>) a /tmp (rm -r…), prepis histórie gitu
#   5. zásah do domova iného používateľa (/home/<niekto iný>/…) alebo systémové služby (systemctl bez --user, sudo)
# Nový kanál mimo zoznamu = fail-safe len na kanál (dopíše sa sem), nie na každý neznámy príkaz.
# 2. 10. (úloha K): kanál 2 a 3 (aj nasadenie, súbor von, prepis či zmazanie na GitHube) platí aj vo vnútri skriptu, ktorý
# príkaz spúšťa (bash/sh/source/./x, python3/node, aj v cykle cez projekty) — rozbor skript prečíta (ng-kotva-analyza.py).
#
# Rozhodnutie o kanáli robí ng-kotva-analyza.py (24. 9., nálezy KOTVA-1…9, NG-S3): príkaz rozloží ako shell — próza,
# adresa, telo heredocu a text v úvodzovkách nie sú príkaz; obaly (timeout, time, nice, nohup, env, xargs, sudo …) sa
# odbalia. Keď rozbor nezbehne, kotva použije núdzové pravidlá nižšie (len jasne nevratné vzory, nikdy nie všetko).
#
# Tvar „jedného kliku": hook vráti deny s jednou vetou; partner položí otázku v texte; človek odpovie jednou vetou;
# partner zopakuje príkaz s potvrdzovacím znakom `# potvrdené: <veta človeka>` → hook pustí a zapíše do auditu.
# Nič nečaká na klik s časovým limitom. Bounded, bez siete (L-231).
#
# Oprava po nezávislom overení (24. 9.):
#  · vstup sa číta jedným jq; bez jq (alebo pri poškodenom JSON) ho prečíta python3; keď ani to nejde, núdzové pravidlá
#    sa použijú na surový text vstupu — chýbajúce jq už neznamená „pustiť všetko“ (predtým prázdny TOOL = exit 0);
#    zastavenie aj riadok auditu vypíše kotva aj bez jq,
#  · skúšobné premenné (NG_KOTVA_SUCHO, NG_KOTVA_OVER, NG_KOTVA_NASADENIE, NG_KOTVA_MARKETING, NG_KOTVA_LOG, NG_KOTVA_AUDIT_PS) platia len pre
#    skúšobný vstup (červený test, prehrávka) — živý vstup od Claude Code nesie hook_event_name a tie premenné ignoruje,
#    aby sa kotva nedala vypnúť cez „env“ v nastaveniach; suchý beh je len NG_KOTVA_SUCHO=1 (nie „0“, „nie“) a overenie
#    potvrdenia (M1) sa dá vypnúť len v ňom (NG_KOTVA_OVER=0),
#  · núdzové pravidlá: neznáma alebo nečitateľná poloha prepínača NASADENIE = najprísnejšia; zápis do domova iného
#    používateľa (presmerovanie alebo cieľ cp/mv/tee … v jeho domove).
# Otázka PS 4.40 (25. 9.): prepínač MARKETING v analyzátore (Sender, Google Tag Manager, Google Ads, Meta, Power Automate),
#  predvolene 'vypnute'; núdzové pravidlá čítajú tú istú konštantu (nasucho NG_KOTVA_MARKETING), neznáma = najprísnejšia.
set -u
AIG=/home/pstrocka/projects/aigrip
KESA=""   # vyrovnávačka prekladu rozboru; prázdne = ~/.cache/ng-kotva (skúšobný strom ju presmeruje k sebe)
IN=$(cat 2>/dev/null || true)
[ -n "$IN" ] || exit 0
for _b17 in "${BASH_SOURCE[0]%/*}/ng-straz-beh.sh" "${BASH_SOURCE[0]%/*}/../scripts/ng-straz-beh.sh" /opt/aigrip-ng/scripts/ng-straz-beh.sh; do [ -f "$_b17" ] && { . "$_b17" && ng_beh_stopa ng-kotva; break; }; done 2>/dev/null   # B17 (časť 3): stopa behu — ng-straz-beh.sh
JQ=0; command -v jq >/dev/null 2>&1 && JQ=1
# Časový limit aj bez GNU coreutils (K2, 3. 10.): na Macu príkaz `timeout` nie je (Homebrew coreutils ho dáva ako
# `gtimeout`) — kotva tam nikdy nespustila rozbor ani overenie potvrdenia: rozhodovali len núdzové pravidlá (prepustili
# graph_mail.py send, zápis do Exchange cez exo-rest.py, odoslanie z kódu cez Graph) a každé potvrdenie zlyhalo.
# Poradie: timeout → gtimeout → strážca v pythone (proces v novej skupine; po limite zabije celú skupinu, kód 124 ako
# timeout). Bez python3 nezbehne ani rozbor — kotva potom použije núdzové pravidlá ako doteraz.
s_limitom() {  # s_limitom <sekundy> <príkaz> [argumenty …]
  if command -v timeout >/dev/null 2>&1; then timeout "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$@"
  else python3 -c 'import os, signal, subprocess, sys
try:
    p = subprocess.Popen(sys.argv[2:], start_new_session=True)
except OSError:
    sys.exit(127)
try:
    r = p.wait(timeout=float(sys.argv[1]))
except subprocess.TimeoutExpired:
    try:
        os.killpg(p.pid, signal.SIGKILL)
    except OSError:
        pass
    p.wait()
    sys.exit(124)
sys.exit(r if r >= 0 else 128 - r)' "$@"
  fi
}
TOOL=""; CMD=""; CWD=""; STOPA=""; AGENT=""; UDALOST=""; ZN_VSTUP=""; SUROVY=""
if [ "$JQ" = 1 ]; then
  { IFS= read -r -d '' TOOL; IFS= read -r -d '' CMD; IFS= read -r -d '' CWD; IFS= read -r -d '' STOPA
    IFS= read -r -d '' AGENT; IFS= read -r -d '' UDALOST; IFS= read -r -d '' ZN_VSTUP; } < <(printf '%s' "$IN" | jq -j \
    '[.tool_name, .tool_input.command, .cwd, .transcript_path, (.agent_id // .agent_type), .hook_event_name]
     | map(if . == null then "" elif type == "string" then . else tostring end | gsub("\u0000"; ""))
     | join("\u0000") + "\u0000ok\u0000"' 2>/dev/null)
fi
if [ "$ZN_VSTUP" != ok ]; then     # bez jq, alebo jq vstup neprečítalo
  TOOL=""; CMD=""; CWD=""; STOPA=""; AGENT=""; UDALOST=""; ZN_VSTUP=""
  { IFS= read -r -d '' TOOL; IFS= read -r -d '' CMD; IFS= read -r -d '' CWD; IFS= read -r -d '' STOPA
    IFS= read -r -d '' AGENT; IFS= read -r -d '' UDALOST; IFS= read -r -d '' ZN_VSTUP; } < <(printf '%s' "$IN" | s_limitom 5 python3 -c '
import json, sys
d = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace"))
ti = d.get("tool_input") if isinstance(d.get("tool_input"), dict) else {}
v = [d.get("tool_name"), ti.get("command"), d.get("cwd"), d.get("transcript_path"), d.get("agent_id") or d.get("agent_type"),
     d.get("hook_event_name")]
sys.stdout.write("\0".join("" if x is None else str(x).replace("\0", "") for x in v) + "\0ok\0")' 2>/dev/null)
fi
if [ "$ZN_VSTUP" != ok ]; then     # vstup sa nedá prečítať vôbec: núdzové pravidlá na surový text (nie „pustiť všetko“)
  printf '%s' "$IN" | grep -Eq '"tool_name"[[:space:]]*:[[:space:]]*"Bash"' || exit 0
  TOOL=Bash; CMD="$IN"; SUROVY=1
  CWD=$(printf '%s' "$IN" | sed -nE 's/.*"cwd"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -1)
  STOPA=$(printf '%s' "$IN" | sed -nE 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -1)
  UDALOST=$(printf '%s' "$IN" | sed -nE 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -1)
fi
[ "$TOOL" = "Bash" ] || exit 0
# odkiaľ príkaz prišiel (M5 v STAVBA 4.27): stopa sedenia a či ide o podagenta — do auditu, aby sa dalo zistiť,
# či hook vie podagenta rozoznať (22. 9. večer)
PODAGENT=0; case "$STOPA" in */subagents/*) PODAGENT=1;; esac; [ -n "$AGENT" ] && PODAGENT=1
[ -n "$CMD" ] || exit 0
# živý vstup (hook_event_name od Claude Code): skúšobné premenné neplatia — kotva sa nedá vypnúť nastavením prostredia
if [ -n "$UDALOST" ]; then unset NG_KOTVA_SUCHO NG_KOTVA_OVER NG_KOTVA_NASADENIE NG_KOTVA_MARKETING NG_KOTVA_CUDZIA NG_KOTVA_LOG NG_KOTVA_AUDIT_PS NG_KOTVA_CAKA; fi
# 16. 11. 2026 (kus Z261116-60e8ae, PS: „ak na moje slovo niečo čaká, musí to byť pomenované a referencované“): značka
# „# rozhodnutie: <číslo položky a voľba alebo kľúč> — <čo to je po ľudsky>“ na konci posledného riadku príkazu (pred
# „# potvrdené:“ alebo za ním) hovorí, že krok už má rozhodnutie človeka a chýbajú len jeho slová. Kotva ju nečíta pri
# rozhodovaní (nič sa nepustí ani nezastaví inak); pri zastavení a pustení zapíše udalosť do zoznamu čakajúcich potvrdení
# (ng-kotva-caka.py), ktorý ukazuje stav a časť 4. Značka v úvodzovkách či za presmerovaním sa neberie (grep na
# ňu by inak vec zatvoril) — povolené sú len znaky bežnej vety.
ZNACKA=""
case "$CMD" in *rozhodnutie:*)
  ZNACKA=$(printf '%s\n' "$CMD" | tail -n 1 | sed -nE 's/^.*[[:space:]]#[[:space:]]*rozhodnutie:[[:space:]]*([^#]*[^#[:space:]])[[:space:]]*(#[[:space:]]*(potvrdené|ohlásenie|ohlasenie)[^#]*)*$/\1/p' | head -1 | cut -c1-200)
  case "$ZNACKA" in *[\'\"\`\;\|\&\<\>\$\\]*) ZNACKA="" ;; esac
  printf '%s' "$ZNACKA" | grep -Eq '^[[:space:]]*([0-9]+\.[0-9]+|AIG-[A-Z][0-9]{6}-[0-9a-f]{6})' || ZNACKA="" ;;
esac
zapis_caka() {  # zapis_caka <zastavene|pustene> — len so značkou; v suchom behu nič; chyba zápisu sa nevypisuje
  [ -n "$ZNACKA" ] && [ -z "$SUCHO" ] || return 0
  local f="${NG_KOTVA_CAKA:-}" p="${CLAUDE_PROJECT_DIR:-}" t
  if [ -z "$f" ]; then
    if [ -n "$p" ] && [ -f "$p/STAVBA.md" ] && [ -d "$p/.aigrip/ng" ]; then f="$p/.aigrip/ng/kotva-caka.jsonl"
    else f="${LOG%/*}/kotva-caka.jsonl"; fi
  fi
  t=$(date +%Y-%m-%dT%H:%M:%S)
  { mkdir -p "${f%/*}" && printf '{"ts":%s,"udalost":%s,"znacka":%s,"kanal":%s,"sedenie":%s,"stroj":%s,"kto":%s,"zdroj":"kotva","podagent":%d}\n' \
      "$(jesc "$t")" "$(jesc "$1")" "$(jesc "$ZNACKA")" "$(jesc "${kanal:-}")" "$(jesc "$(basename "$STOPA" .jsonl 2>/dev/null | cut -c1-40)")" \
      "$(jesc "$(hostname 2>/dev/null)")" "$(jesc "${USER:-${DOMOV##*/}}")" "$PODAGENT" >> "$f"; } 2>/dev/null || true
}
SUCHO=""; [ "${NG_KOTVA_SUCHO:-}" = 1 ] && SUCHO=1   # 1 = červený test alebo prehrávka: rozhodnúť, do auditu nič (22. 9.)
DOMOV="${HOME:-/home/pstrocka}"
case "$0" in */*) TU="${0%/*}";; *) TU=.;; esac

# Audit: NG_KOTVA_LOG (skúšobný audit, červený test M1) · audit PS, keď je zapisovateľný · inak vlastný audit v domove toho,
# kto sedí. U kolegu audit PS zapisovateľný nie je (/home/pstrocka 750): zastavenia ani potvrdenia sa nezapisovali a každé
# volanie nechalo v stope „Permission denied“ (NG-S6, 1 023×); overenie potvrdenia nevidelo zastavenie (KOTVA-4).
PSLOG="${NG_KOTVA_AUDIT_PS:-$AIG/.aigrip/ng/kotva-audit.jsonl}"
if [ -n "${NG_KOTVA_LOG:-}" ]; then LOG="$NG_KOTVA_LOG"
elif [ -w "$PSLOG" ] || { [ ! -e "$PSLOG" ] && [ -w "${PSLOG%/*}" ]; }; then LOG="$PSLOG"
else LOG="$DOMOV/.aigrip-ng/kotva-audit.jsonl"; fi
zapis_audit() {  # zapis_audit <json> — v suchom behu nič; chyba zápisu sa nevypisuje do stopy
  [ -n "$SUCHO" ] && return 0
  { mkdir -p "${LOG%/*}" && printf '%s\n' "$1" >> "$LOG"; } 2>/dev/null || true
}
# 16. 11. 2026 (kus Z261115-d53f02): pri každom pustení riadok do stopy háčikov — sedenie, čas pustenia a výsledok
# vlastnej kontroly kotvy (tretí riadok ng-kotva-over.py: trieda a časy zastavenia, odpovede či pokynu). Prepisy sedení
# kolegov stroj často nemá (zber berie len projekty v novom spôsobe, nie osobné ani iné klony), stopu háčikov áno
# (ng-stopy-kolegov.sh) — meranie sľubu 3.08 tak vie, čo kotva pri pustení sama zistila, a porovnať to s jej auditom.
# Bez slov človeka a bez príkazu (tie sú v audite). Miesto vedľa auditu: u PS aigrip/.aigrip/ng/hook-stopy.jsonl,
# u kolegu ~/.aigrip-ng/hook-stopy.jsonl, v skúške pieskovisko jej auditu (NG_HOOK_STOPY presmeruje ako ng-hook-stopa.sh).
# V suchom behu nič; chyba zápisu sa nevypisuje a na rozhodnutí kotvy nič nemení (zapisuje sa až po zápise auditu).
zapis_stopu_pustenia() {  # zapis_stopu_pustenia <tretí riadok overovača>
  [ -n "$SUCHO" ] && return 0
  local k=${1:-} f="${NG_HOOK_STOPY:-${LOG%/*}/hook-stopy.jsonl}" t proj
  case "$k" in '{"v":1,"'*'}') ;; *) k=null ;; esac
  case "$k" in *[[:cntrl:]]*) k=null ;; esac
  t=$(date +%Y-%m-%dT%H:%M:%S%z 2>/dev/null) || t=''
  [ "${#t}" = 24 ] && t="${t:0:22}:${t:22}"
  [ -n "$t" ] || t="$TS"
  proj=${CLAUDE_PROJECT_DIR:-${CWD:-$PWD}}; proj=${proj%/}; proj=${proj##*/}
  { printf '{"ts":%s,"projekt":%s,"hook":"ng-kotva-pustenie","sid":%s,"pustene":%s,"kanal":%s,"podagent":%d,"kto":%s,"kontrola":%s}\n' \
      "$(jesc "$t")" "$(jesc "$proj")" "$(jesc "$ST")" "$(jesc "$TS")" "$(jesc "$kanal")" "$PODAGENT" \
      "$(jesc "${USER:-${DOMOV##*/}}")" "$k" >> "$f"; } 2>/dev/null || true
}
jesc() {  # jesc <text> — reťazec JSON bez jq
  local x=$1
  x=${x//\\/\\\\}; x=${x//\"/\\\"}; x=${x//$'\n'/\\n}; x=${x//$'\r'/\\r}; x=${x//$'\t'/\\t}; x=${x//[[:cntrl:]]/}
  printf '"%s"' "$x"
}
odmietni() {  # odmietni <dôvod> — rozhodnutie deny pre Claude Code (s jq aj bez neho)
  if [ "$JQ" = 1 ]; then
    jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$(jesc "$1")"
  fi
}
audit_riadok() {  # audit_riadok <výsledok> [<potvrdené>] [<čím overenie prešlo/neprešlo>] — riadok auditu
  # 8. 11. 2026 (námietka nezávislého behu c9b772dc4904): tretí parameter = druhý riadok overovača („odpoveď
  # 20:55:04 po zastavení 20:50:36“ · „slová človeka, ale nie ako odpoveď na zastavenie“). Bez neho sa nedalo
  # rozobrať, prečo kotva ten istý príkaz s tým istým slovom raz odmietla a o 15 s pustila. Kľúč je voliteľný,
  # staré riadky ostávajú platné a nič sa nepustí ani nezastaví inak.
  if [ "$JQ" = 1 ] && [ $# -ge 3 ] && [ -n "$3" ]; then
    jq -nc --arg ts "$TS" --arg k "$kanal" --arg v "$2" --arg c "$PRIKAZ" --arg vy "$1" --arg st "$ST" --arg ag "$AGENT" --argjson pa "$PODAGENT" --arg d "$3" \
      '{ts:$ts, kanal:$k, potvrdene:$v, prikaz:$c, vysledok:$vy, stopa:$st, agent:$ag, podagent:$pa, cim:$d}'
  elif [ "$JQ" = 1 ] && [ $# -ge 2 ]; then
    jq -nc --arg ts "$TS" --arg k "$kanal" --arg v "$2" --arg c "$PRIKAZ" --arg vy "$1" --arg st "$ST" --arg ag "$AGENT" --argjson pa "$PODAGENT" \
      '{ts:$ts, kanal:$k, potvrdene:$v, prikaz:$c, vysledok:$vy, stopa:$st, agent:$ag, podagent:$pa}'
  elif [ "$JQ" = 1 ]; then
    jq -nc --arg ts "$TS" --arg k "$kanal" --arg c "$PRIKAZ" --arg vy "$1" --arg st "$ST" --arg ag "$AGENT" --argjson pa "$PODAGENT" \
      '{ts:$ts, kanal:$k, prikaz:$c, vysledok:$vy, stopa:$st, agent:$ag, podagent:$pa}'
  elif [ $# -ge 3 ] && [ -n "$3" ]; then
    printf '{"ts":%s,"kanal":%s,"potvrdene":%s,"prikaz":%s,"vysledok":%s,"stopa":%s,"agent":%s,"podagent":%d,"cim":%s}' "$(jesc "$TS")" \
      "$(jesc "$kanal")" "$(jesc "$2")" "$(jesc "$PRIKAZ")" "$(jesc "$1")" "$(jesc "$ST")" "$(jesc "$AGENT")" "$PODAGENT" "$(jesc "$3")"
  elif [ $# -ge 2 ]; then
    printf '{"ts":%s,"kanal":%s,"potvrdene":%s,"prikaz":%s,"vysledok":%s,"stopa":%s,"agent":%s,"podagent":%d}' "$(jesc "$TS")" \
      "$(jesc "$kanal")" "$(jesc "$2")" "$(jesc "$PRIKAZ")" "$(jesc "$1")" "$(jesc "$ST")" "$(jesc "$AGENT")" "$PODAGENT"
  else
    printf '{"ts":%s,"kanal":%s,"prikaz":%s,"vysledok":%s,"stopa":%s,"agent":%s,"podagent":%d}' "$(jesc "$TS")" \
      "$(jesc "$kanal")" "$(jesc "$PRIKAZ")" "$(jesc "$1")" "$(jesc "$ST")" "$(jesc "$AGENT")" "$PODAGENT"
  fi
}

# Text kanála „nedočítaný skript“ — ten istý ako K_SKRIPT v ng-kotva-analyza.py (16. 11. 2026, kus Z261116-623bb7:
# bez „chyba rozboru“, ktorá sa čítala ako porucha platformy). Podľa začiatku ho triedi aj vetva konektorov nižšie.
K_NEDOC="skript, ktorý príkaz spúšťa, kotva nedočítala (veľký súbor, priveľa súborov, vnorení alebo času, kód, ktorý nevie rozobrať) — nevie, či v ňom nie je neobnoviteľný krok"
# núdzové pravidlá, keď rozbor nezbehne (chýba python alebo skript, časový limit): len jasne nevratné vzory
nudzove() {
  local c="$CMD" k="" B='(^|[;&|(`"'"'"'[:space:]])'
  # 3. 10. (overenie kola 1: rozbor veľkého skriptu háčik zabil po 5 s a tieto pravidlá skript nečítali — príkaz prešiel):
  # príkaz, ktorý spúšťa súbor skriptu (shell, source/., python, node, make, npm …, ./x, cesta/x), zastaví ako nedočítaný
  # skript — kotva nevie, čo v ňom je. Najnižšia priorita: kanál z pravidiel nižšie ho prebije.
  # 3. 10. (kolo 4, súbeh s K2): len keď python3 je a rozbor zlyhal alebo nestihol — bez python3 rozbor nezbehne nikdy,
  # skripty sa nečítajú a rozhodujú pravidlá nižšie (K2, ako pred úlohou K). Nie kontrola syntaxe (bash -n), kód v príkaze
  # (bash -c, python3 -c/-m/-, node -e/-p), make -n, „.“ ako argument (sudo grep -c . súbor).
  local sk=""
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$c" | grep -Eq "${B}(bash|sh|zsh|dash|ksh|mksh)([[:space:]]+-[A-Zabd-mo-z]*)*[[:space:]]+[^-[:space:];&|<>]" && sk=1
    printf '%s' "$c" | grep -Eq "(^|[;&|(\`])[[:space:]]*(source|\.)[[:space:]]+[^-[:space:];&|<>]" && sk=1
    printf '%s' "$c" | grep -Eq "${B}(python[0-9.]*|node|nodejs|deno|bun|bunx|npx|pnpx|tsx|ts-node|uv|poetry|pipenv|pdm)([[:space:]]+-[A-Zabdf-lnoq-z]*)*[[:space:]]+[^-[:space:];&|<>]" && sk=1
    printf '%s' "$c" | grep -Eq "${B}(npm|pnpm|yarn)([[:space:]]|\$)" && sk=1
    printf '%s' "$c" | grep -Eq "${B}(make|gmake)([[:space:]]|\$)" \
      && ! printf '%s' "$c" | grep -Eq "${B}(make|gmake)[[:space:]]+(-[A-Za-z]*n|--dry-run|--just-print|--recon)" && sk=1
    printf '%s' "$c" | grep -Eq "(^|[;&|(\`]|&&|\|\|)[[:space:]]*[\"']?(\./|\.\./|~/|\\\$|/home/|/tmp/|/opt/|[A-Za-z0-9_.-]+/)" && sk=1
  fi
  [ -n "$sk" ] && k="$K_NEDOC"
  if printf '%s' "$c" | grep -Eq "${B}git( -C [^ ]+)? push"; then
    case "$CWD" in "$DOMOV"/*|"") ;; *) k="push do repozitára mimo tvojich klonov ($CWD)";; esac
  fi
  # 21. 11. 2026 (hlásenie S8, kus Z261121-eda4a7): push na výslovnú adresu (https://…, ssh://…, git@…), ktorá nie je
  # adresou origin repozitára — porovnané bez prihlasovacích údajov, .git a lomky na konci, github.com a alias github-*
  # bez rozdielu veľkosti písmen, ssh tvar = https tvar
  local adr_push adr_o adr_n
  adr_push=$(printf '%s' "$c" | grep -oE "${B}git( -C [^ ]+)? push[^;&|]*" \
    | grep -oE "(https?|ssh|git)://[^[:space:]\"';&|]+|[A-Za-z0-9._-]+@[A-Za-z0-9._-]+:[^[:space:]\"';&|]+" | head -1)
  if [ -n "$adr_push" ]; then
    _s8_norm() { printf '%s' "$1" | sed -E 's#^[A-Za-z][A-Za-z0-9+.-]*://([^/@]*@)?([^/]*)#\2#; s#^[^/@:]*@([^/:]+):#\1/#; s#/+$##; s#\.git$##; s#/+$##' \
      | sed -E 's#^github-[^/]*/#github.com/#I; s#^github\.com(:22)?/#github.com/#I' \
      | awk '{ if (tolower(substr($0,1,11))=="github.com/") print tolower($0); else print }'; }
    adr_o=$(git -C "${CWD:-.}" remote get-url origin 2>/dev/null)
    adr_n=$(_s8_norm "$adr_push")
    if [ -z "$adr_o" ] || [ "$adr_n" != "$(_s8_norm "$adr_o")" ]; then
      k="push do iného repozitára, než je domov projektu ($(printf '%s' "$adr_push" | sed -E 's#://[^/@]*@#://#'))"
    fi
  fi
  printf '%s' "$c" | grep -Eq "${B}git( -C [^ ]+)? push[^;&|]*(--force|--mirror| -f( |$)| \\+)" && k="prepis histórie na GitHube (push --force / --mirror)"
  printf '%s' "$c" | grep -Eq "${B}git -C /home/[a-z][^ ]* push" && ! printf '%s' "$c" | grep -Eq "git -C $DOMOV(/| )" && k="push v cudzom repozitári"
  # zápis do domova iného používateľa: presmerovanie alebo cieľ (posledný argument) cp/mv/tee … v jeho domove (24. 9.)
  local cudzi
  cudzi=$(printf '%s' "$c" | grep -oE "(>>?|&>>?)[[:space:]]*[\"']?/home/[^/[:space:]\"';&|]+|${B}(cp|mv|rsync|install|ln|tee|touch|mkdir|chmod|chown|chgrp|truncate|rm|rmdir)[[:space:]][^;&|]*[[:space:]][\"']?/home/[^/[:space:]\"';&|]+[^[:space:];&|]*[\"']?[[:space:]]*(\$|[;&|])" \
    | sed -E "s#.*(/home/[^/[:space:]\"';&|]+).*#\\1#" | grep -vxF "$DOMOV" | head -1)
  [ -n "$cudzi" ] && k="zásah do domova iného používateľa"
  # 3. 10. (K2): domov iného používateľa ako v rozbore — cieľ v tvare ~meno (cp x ~ptoth/…), skript spustený z jeho domova
  # (python3 /home/<iný>/x.py; skripty stroja volané starou cestou cez domov PS nie) a nástroj, ktorý vo vnútri pracuje pod
  # menom iného používateľa (sudo -u, runuser — súbor skriptu sa len prečíta), spustený naostro (--naostro, --apply,
  # DRY_RUN=0 …; NASTROJ_OSTRO v rozbore)
  cudzi=$(printf '%s' "$c" | grep -oE "(>>?|&>>?)[[:space:]]*[\"']?~[a-z_][a-z0-9_.-]*|${B}(cp|mv|rsync|install|ln|tee|touch|mkdir|chmod|chown|chgrp|truncate|rm|rmdir)[[:space:]][^;&|]*[[:space:]][\"']?~[a-z_][a-z0-9_.-]*[^[:space:];&|]*[\"']?[[:space:]]*(\$|[;&|])" \
    | sed -E 's#.*~([a-z_][a-z0-9_.-]*).*#\1#' | grep -vxF "${DOMOV##*/}" | head -1)
  [ -n "$cudzi" ] && k="zásah do domova iného používateľa"
  cudzi=$(printf '%s' "$c" | grep -oE "((^|[;&|(\`[:space:]])(python[0-9.]*|bash|sh|zsh|node|perl|ruby|php)|(^|[;&|(\`])[[:space:]]*(source|\\.))[[:space:]]+(-[^[:space:]]+[[:space:]]+)*[\"']?/home/[^/[:space:]\"';&|]+/[^[:space:];&|\"']*" \
    | grep -v '/home/pstrocka/projects/aigrip/\.aigrip/scripts/ng-' | sed -E "s#.*(/home/[^/[:space:]\"';&|]+)/.*#\\1#" | grep -vxF "$DOMOV" | head -1)
  [ -n "$cudzi" ] && k="zásah do domova iného používateľa"
  if printf '%s' "$c" | grep -Eq -e "(^|[[:space:]])--(naostro|ostro|apply|execute|live|commit)([[:space:]=]|\$)|(^|[^A-Za-z0-9_])DRY_RUN=0([^0-9]|\$)"; then
    local sk
    while IFS= read -r sk; do
      case "$sk" in /*) ;; "~/"*) sk="$DOMOV/${sk#\~/}";; *) sk="${CWD:-.}/$sk";; esac
      [ -f "$sk" ] || continue
      if head -c 262144 "$sk" 2>/dev/null | grep -Eq -e "(sudo|runuser)([[:space:]]+-[a-zA-Z-]+)*[[:space:]]+(-[a-zA-Z]*u|--user)([[:space:]=]|\$)|['\"](sudo|runuser)['\"][[:space:]]*,"; then
        k="zásah do domova iného používateľa"
      elif head -c 262144 "$sk" 2>/dev/null | grep -Eq -e "(^|[[:space:];&|(])sudo[[:space:]]"; then
        k="systémová služba alebo sudo (zápis, skript alebo služba; čítanie cez sudo prejde)"
      fi
    done < <(printf '%s' "$c" | grep -oE "[^[:space:];&|<>\"'\`=]+\\.(sh|bash|py)" | head -5)
  fi
  printf '%s' "$c" | grep -Eiq "${B}(sendmail|git send-email)[[:space:]]|exo-rest\\.py[^;&|]*sendmail|${B}(bash|sh|sudo)[[:space:]]+[^;&|]*aig-crit-notify" && k="odoslanie mailu alebo správy"
  # 3. 10. (K2): pošta ako v rozbore aj bez neho — na stroji bez `timeout` rozhodovali len tieto pravidlá a prepustili
  # graph_mail.py send, zápis do Exchange cez exo-rest.py aj odoslanie z kódu cez Graph sendMail či webhook Teams.
  #  · poštový nástroj podľa mena (…mail… — graph_mail.py, send_mail.sh) spustený s pokynom odoslať (send, reply, forward,
  #    --send …; POSTA_NASTROJ a POSTA_POKYN v rozbore) — meno hneď na mieste príkazu alebo za interpretrom
  printf '%s' "$c" | grep -Eiq -e "(^|[;&|(\`]|\\\$\\(|(python[0-9.]*|bash|sh|zsh|node|perl|ruby|php|pwsh|exec|sudo|env|nohup)[[:space:]]+(-[^[:space:]]+[[:space:]]+)*)[[:space:]]*[\"']?[^[:space:];&|<>\"'\`=]*mail[^[:space:];&|<>\"'\`/=]*[\"']?[[:space:]]+([^;&|]*[[:space:]])?-{0,2}(send|send-draft|senddraft|reply|reply-all|forward|odosli|odošli|odoslat|odoslať)([[:space:];&|)]|\$)" \
    && k="odoslanie mailu alebo správy"
  #  · poštový program na mieste príkazu (POSTA_PROG) a poštový skript spustený priamo cestou (/usr/local/sbin/aig-crit-notify.sh)
  printf '%s' "$c" | grep -Eq -e "(^|[;&|(\`]|\\\$\\()[[:space:]]*((sudo|env|nohup|exec|xargs)[[:space:]]+(-[^[:space:]]+[[:space:]]+)*)*(mail|mailx|mutt|s-nail|ssmtp|msmtp|swaks|sendmail)([[:space:]]|\$)" \
    && k="odoslanie mailu alebo správy"
  printf '%s' "$c" | grep -Eq -e "(^|[;&|(\`]|\\\$\\()[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*[^[:space:];&|<>'\"=]*(aig-crit-notify|teams-notify|mail-send)[^[:space:];&|<>/'\"=]*([[:space:]]|\$)" \
    && k="odoslanie mailu alebo správy"
  #  · exo-rest.py (správa Exchange cez adminapi, 2. 10.): cmdlet, ktorý nie je len čítanie (čítanie = Get-*,
  #    Test-ApplicationAccessPolicy; --help), cmdlet v premennej alebo zo vstupu (xargs), nástroj načítaný ako knižnica bez
  #    doslovného cmdletu. Overenie súboru nástroja (EXO_PLATFORMA) robí len rozbor.
  if printf '%s' "$c" | grep -q 'exo-rest\.py'; then
    local ecm EXV='Add|Approve|Assert|Backup|Block|Clear|Close|Compare|Complete|Compress|Confirm|Connect|Convert|ConvertFrom|ConvertTo|Copy|Deny|Deploy|Disable|Disconnect|Dismount|Edit|Enable|Enter|Exit|Expand|Export|Find|Format|Get|Grant|Hide|Import|Initialize|Install|Invoke|Join|Limit|Lock|Merge|Mount|Move|New|Open|Optimize|Publish|Push|Receive|Redo|Register|Remove|Rename|Repair|Request|Reset|Resize|Resolve|Restart|Restore|Resume|Revoke|Save|Search|Select|Send|Set|Show|Skip|Split|Start|Stop|Submit|Suspend|Switch|Sync|Test|Undo|Uninstall|Unlock|Unprotect|Unpublish|Unregister|Update|Use|Wait|Write'
    ecm=$(printf '%s' "$c" | grep -oE "(^|[^A-Za-z0-9_-])($EXV)-[A-Z][A-Za-z0-9]*" | sed -E 's/^[^A-Za-z]//')
    if printf '%s\n' "$ecm" | grep -E . | grep -vqE '^(Get-[A-Za-z0-9]+|Test-ApplicationAccessPolicy)$' \
       || printf '%s' "$c" | grep -Eq "exo-rest\\.py[\"']?[[:space:]]+[\"']?\\\$|xargs[^;&|]*exo-rest\\.py" \
       || { printf '%s' "$c" | grep -Eq 'spec_from_file_location|SourceFileLoader|load_source|run_path|import_module|exec[[:space:]]*\(' \
            && { [ -z "$ecm" ] || printf '%s' "$c" | grep -Eq -e '(^|[^A-Za-z0-9_])(eval|exec|getattr|setattr|globals|vars|system|popen|subprocess|urllib|urlopen|Request|environ|putenv|remove|unlink|rmdir|rmtree|rename|truncate|chmod|chown|write_text|write_bytes|find_spec|import_module|run_path|CmdletName|tok|_tok|__main__|PYTHON[A-Z_]+)([^A-Za-z0-9_]|$)'; }; }; then
      k="odoslanie mailu alebo správy"
    fi
  fi
  #  · poštový nástroj podľa mena z kódu alebo cez premennú: subprocess.run(['python3', '…/graph_mail.py', 'send' …]),
  #    import graph_mail / import_module / run_path / spec_from_file_location s main() alebo send…(), GM=…/graph_mail.py;
  #    python3 $GM send (meno s podčiarnikom pri „mail“, aby to nebol štandardný modul email či mailbox)
  printf '%s' "$c" | grep -Eiq -e "mail[^'\"/[:space:]]*\\.(py|sh|bash|js|cjs|mjs|pl|rb)['\"][[:space:]]*,[[:space:]]*['\"]-{0,2}(send|send-draft|senddraft|reply|reply-all|forward)['\"]" \
    && k="odoslanie mailu alebo správy"
  if printf '%s' "$c" | grep -Eiq -e "import[[:space:]]+([A-Za-z0-9_.]*_mail|mail_|graph_mail|send_mail)|from[[:space:]]+[A-Za-z0-9_.]*(_mail|mail_)[A-Za-z0-9_.]*[[:space:]]+import|(import_module|__import__|run_module)[[:space:]]*\\([[:space:]]*['\"][A-Za-z0-9_.]*(_mail|mail_)|run_path[[:space:]]*\\([[:space:]]*['\"][^'\"]*mail[^'\"]*\\.py|spec_from_file_location[[:space:]]*\\([^)]*mail[^)]*\\.py" \
     && printf '%s' "$c" | grep -Eiq -e "(^|[^A-Za-z0-9_])main[[:space:]]*\\(|(^|[^A-Za-z0-9_])(send|send_mail|send_message|sendmail|reply|forward)[A-Za-z0-9_]*[[:space:]]*\\(|['\"](send|reply|forward)['\"]|[[:space:]](send|reply|forward)([[:space:]]|\$)"; then
    k="odoslanie mailu alebo správy"
  fi
  local mv
  while IFS= read -r mv; do
    [ -n "$mv" ] && printf '%s' "$c" | grep -Eiq -e "\\\$\\{?$mv\\}?[\"']?[[:space:]]+([^;&|]*[[:space:]])?-{0,2}(send|send-draft|senddraft|reply|reply-all|forward|odosli|odošli|odoslat|odoslať)([[:space:];&|)]|\$)" \
      && k="odoslanie mailu alebo správy"
  done < <(printf '%s' "$c" | grep -oE "(^|[^A-Za-z0-9_])[A-Za-z_][A-Za-z0-9_]*=[\"']?[^[:space:];&|\"']*[Mm][Aa][Ii][Ll][^[:space:];&|\"'/]*\\.(py|sh|bash|js|cjs|mjs|pl|rb)" | sed -E 's/^[^A-Za-z_]//; s/=.*//' | head -5)
  #  · odoslanie z kódu alebo na adresu (Graph …/sendMail, webhook Teams, Send-MailMessage, .sendmail / .send_message)
  #    spolu s interpretrom alebo sieťovým klientom; poštový skript spustený z kódu cez shell (subprocess.run(['bash', N …]),
  #    execSync('bash ' + N …)) pri mene aig-crit-notify, teams-notify, mail-send v príkaze
  if printf '%s' "$c" | grep -Eiq -e "/sendMail([^A-Za-z0-9_]|\$)|webhook\\.office\\.com|hooks\\.office\\.com|Send-MailMessage|[.'\"](sendmail|send_message)([^A-Za-z0-9_]|\$)" \
     && printf '%s' "$c" | grep -Eiq -e "${B}(python[0-9.]*|node|nodejs|deno|bun|perl|ruby|php|pwsh|powershell|curl|wget|http|https)([[:space:]]|\$)|Invoke-(RestMethod|WebRequest)"; then
    k="odoslanie mailu alebo správy"
  fi
  printf '%s' "$c" | grep -Eq 'aig-crit-notify|teams-notify|mail-send' \
    && printf '%s' "$c" | grep -Eq -e "(run|call|Popen|check_call|check_output|system|popen|execSync|execFileSync|execFile|exec|spawnSync|spawn)[[:space:]]*\\([[:space:]]*\\[?[[:space:]]*['\"\`]((/usr)?/bin/)?(bash|sh)([[:space:]'\"\`]|\$)|(run|call|Popen|check_call|check_output|system|popen|execSync|execFileSync|execFile|exec|spawnSync|spawn)[[:space:]]*\\([[:space:]]*\\[?[[:space:]]*['\"\`]((/usr)?/bin/)?((bash|sh)[[:space:]]+)?[^'\"\`[:space:]]*(aig-crit-notify|teams-notify|mail-send)" \
    && k="odoslanie mailu alebo správy"
  printf '%s' "$c" | grep -Eq 'gh api[^;&|]*(-X|--method)[ =]?(POST|PUT|PATCH|DELETE)|gh (issue|pr) (create|comment|close|delete|edit)|gh repo (delete|rename|archive)' && k="zápis na GitHub cez API (issue, PR, release, repo)"
  # 3. 10. (K2): GitHub ako v rozbore — release, ďalšie zápisy do issue a PR (aj s -R pred podpríkazom), gh api s poľom
  # (-f/-F/--field/--input bez -X = POST; graphql len s mutation; výslovné -X GET je čítanie)
  printf '%s' "$c" | grep -Eq -e "${B}gh (release (create|delete|edit|upload|delete-asset)|(issue|pr)( (-R|--repo)[ =][^ ]+)? (create|comment|close|delete|edit|merge|reopen|review|lock|unlock|transfer))( |\$)" \
    && k="zápis na GitHub cez API (issue, PR, release, repo)"
  if printf '%s' "$c" | grep -Eq -e "${B}gh api[^;&|]*[[:space:]](-f|-F|--field|--raw-field|--input)([[:space:]=]|[^[:space:]-])" \
     && ! printf '%s' "$c" | grep -Eiq -e "${B}gh api[^;&|]*(-X|--method)[ =]?[\"']?(GET|HEAD)" \
     && { ! printf '%s' "$c" | grep -Eq -e "${B}gh api([[:space:]][^;&|]*)?[[:space:]]graphql([[:space:]]|\$)" || printf '%s' "$c" | grep -q 'mutation'; }; then
    k="zápis na GitHub cez API (issue, PR, release, repo)"
  fi
  printf '%s' "$c" | grep -Eq "${B}az [a-z-]+ ([a-z-]+ )*(create|delete|update|set|add|remove|reset)( |$)" && k="zásah do účtov alebo cloudu (az)"
  # 19. 11. 2026 (PS 4.1172 h): písanie do okna sedenia za človeka — núdzovo prísnejšie než rozbor (každý cieľ tmux)
  printf '%s' "$c" | grep -Eq -e "${B}tmux[[:space:]][^;&|]*(send|paste)|${B}screen[[:space:]][^;&|]*stuff|/run/aig-workspace/.*api/(poslat|hlas-akcia)|api/(poslat|hlas-akcia).*/run/aig-workspace/|gr8it\\.cloud/[^[:space:]]*api/(poslat|hlas-akcia)" \
    && k="písanie do okna sedenia za človeka (tmux, workspace alebo ťuk hlasového asistenta)"
  # curl / wget / httpie zápis do cudzieho systému cez API (Graph, GitHub …): klient + cudzia adresa + zápisová voľba
  if printf '%s' "$c" | grep -Eiq "${B}(curl|wget|http)[[:space:]]" \
     && printf '%s' "$c" | grep -Eiq '(graph\.microsoft|sharepoint|atlassian|outlook\.office|api\.github\.com|github\.com/repos)' \
     && printf '%s' "$c" | grep -Eiq '(-X[ =]?(POST|PUT|PATCH|DELETE)|--request[ =]?(POST|PUT|PATCH|DELETE)|--method[ =]?(POST|PUT|PATCH|DELETE)|--post-data|--post-file|--body-data|--body-file|--data|--json|--upload-file|(^|[[:space:]])-[dT]([[:space:]=]|$)|(^|[[:space:]])(POST|PUT|PATCH|DELETE)([[:space:]]|$))'; then
    k="zápis do cudzieho systému cez API"
  fi
  # K88 (PS 4.88 a, 10. 10.): odoslanie údajov na cudziu adresu — prepínač CUDZIA v analyzátore, nasucho NG_KOTVA_CUDZIA;
  # neznáma alebo nečitateľná poloha = najprísnejšia (ako NASADENIE a MARKETING). Núdzové pravidlá adresu nerozoberajú
  # ako rozbor: zastavia zápis klientom (curl, wget, httpie), keď v príkaze stojí adresa mimo vlastného servera, alebo
  # keď v ňom adresu nevidno vôbec (je v premennej, v súbore s nastaveniami -K/--config, príde cez xargs). Adresa v tele
  # (-d "…scope=https://graph…") sa neráta — berú sa len adresy na začiatku slova a za --url=. Výslovné čítanie
  # (-G, -X GET/HEAD) a žiadosť o prihlasovací token prejdú. Pravidlo je prísnejšie než rozbor (súbor s nastaveniami
  # ani vlastnú adresu v premennej nečíta) — núdzová cesta sa smie pýtať aj tam, kde by rozbor pustil.
  local cu=""
  if [ -n "$SUCHO" ] && [ -n "${NG_KOTVA_CUDZIA:-}" ]; then cu="$NG_KOTVA_CUDZIA"
  else cu=$(grep -m1 -E '^CUDZIA[[:space:]]*=' "$ANA" 2>/dev/null | sed -E "s/^CUDZIA[[:space:]]*=[[:space:]]*['\"]([^'\"]*)['\"].*/\1/"); fi
  if [ "$cu" != vypnute ] && printf '%s' "$c" | grep -Eiq "(^|[;&|(\`\"'[:space:]/])(curl|wget|http|https)[[:space:]]" \
     && printf '%s' "$c" | grep -Eq -e "(-X|--request|--method)[ =]?[\"']?(POST|PUT|PATCH|DELETE)|(^|[[:space:]])(-d|-F|-T|--data[a-z-]*|--json|--form|--form-string|--upload-file|--post-data|--post-file|--body-data|--body-file)([[:space:]=]|\$)|(^|[[:space:]])(POST|PUT|PATCH|DELETE)([[:space:]]|\$)|(^|[;&|(\`\"'[:space:]/])(curl[[:space:]][^;&|]*(-[A-Za-z]*K|--config)|wget[[:space:]][^;&|]*--config)([[:space:]=]|\$)" \
     && ! printf '%s' "$c" | grep -Eq -e "(^|[[:space:]])(-G|--get)([[:space:]]|\$)|(-X|--request|--method)[ =]?[\"']?(GET|HEAD)"; then
    local VL='(localhost|127\.[0-9]+\.[0-9]+\.[0-9]+|0\.0\.0\.0|\[::1\]|ai\.gr8it\.cloud|ai-admin\.gr8it\.cloud|bpw\.gr8it\.cloud)'
    local cudz=0 adr
    adr=$(printf '%s' "$c" | grep -oEi "(^|[[:space:]\"'\`(]|--url=|--uri=)https?://[^[:space:]\"'\`;&|)>]+" \
      | sed -E "s#^[[:space:]\"'\`(]*##; s#^--(url|uri)=##")
    if [ -n "$adr" ]; then
      printf '%s\n' "$adr" \
        | grep -Eiv '^https://(login\.microsoftonline\.com/[^/?#]+/oauth2/(v2\.0/)?(token|devicecode)|oauth2\.googleapis\.com/token|accounts\.google\.com/o/oauth2/token|www\.googleapis\.com/oauth2/v[0-9]+/token)([?#].*)?$' \
        | sed -E 's#^[A-Za-z]+://##; s#^[^/@]*@##; s#[/?#].*##; s#:[0-9]+$##' \
        | grep -Eiv "^$VL\$" | grep -Eiv '\.(local|localhost|internal)$' | grep -q . && cudz=1
    else
      cudz=1          # adresu v príkaze nevidno vôbec (premenná, súbor s nastaveniami, vstup xargs)
    fi
    [ "$cudz" = 1 ] && k="zápis do cudzieho systému cez API"
  fi
  # 3. 10. (K2): zmazanie na webe (WordPress REST) a v CRM Solvedio, zverejnenie cez WordPress REST — ako rozbor
  # (EXT_ZMAZ_CIEL, WP_ZVEREJNI); telo zo súboru (@súbor) pri WordPress núdzové pravidlá neprečítajú, preto zastavia
  if printf '%s' "$c" | grep -Eiq -e "${B}(curl|wget|http|https)[[:space:]]" \
     && printf '%s' "$c" | grep -Eiq -e '/wp-json/|[?&]rest_route=|https?://([^/?#[:space:]]*\.)?api\.solvedio\.com' \
     && { printf '%s' "$c" | grep -Eiq -e "(-X|--request|--method)[ =]?[\"']?DELETE|(^|[[:space:]])DELETE([[:space:]]|\$)" \
          || { printf '%s' "$c" | grep -Eiq -e "(-X|--request|--method)[ =]?[\"']?(POST|PUT|PATCH)|(^|[[:space:]])(-d|-F|--data[a-z-]*|--json|--form|--post-data|--post-file|--body-data|--body-file)([[:space:]=]|\$)|(^|[[:space:]])(POST|PUT|PATCH)([[:space:]]|\$)" \
               && printf '%s' "$c" | grep -Eiq -e "status[\\\\\"']*[[:space:]]*([:=]|%3a|%3d)[[:space:]]*[\\\\\"']*(publish|future)|(/wp-json/|rest_route=)[^;&|]*[[:space:]](-d|--data[a-z-]*|--json|--post-file|--body-file)[[:space:]=]*@|(-d|--data[a-z-]*|--json|--post-file|--body-file)[[:space:]=]*@[^;&|]*(/wp-json/|rest_route=)"; }; }; then
    k="zápis do cudzieho systému cez API"
  fi
  # prepínač MARKETING v analyzátore (otázka PS 4.40), rovnaké čítanie ako NASADENIE: nasucho NG_KOTVA_MARKETING; neznáma
  # alebo nečitateľná poloha = najprísnejšia ('vsetko'). Adresa služby + zápis (metóda, telo); tvrdé = zmazanie, odoslanie,
  # zverejnenie, spustenie. Len jasné vzory v texte príkazu — skript z /tmp núdzové pravidlá nečítajú.
  local mk=""
  if [ -n "$SUCHO" ] && [ -n "${NG_KOTVA_MARKETING:-}" ]; then mk="$NG_KOTVA_MARKETING"
  else mk=$(grep -m1 -E '^MARKETING[[:space:]]*=' "$ANA" 2>/dev/null | sed -E "s/^MARKETING[[:space:]]*=[[:space:]]*['\"]([^'\"]*)['\"].*/\\1/"); fi
  if [ "$mk" != vypnute ] && printf '%s' "$c" | grep -Eiq 'api\.sender\.net|tagmanager\.googleapis\.com|googleads\.googleapis\.com|graph\.facebook\.com|api\.flow\.microsoft\.com|powerplatform\.com|logic\.azure\.com(:[0-9]+)?/workflows/'; then
    local sl="" s1
    for s1 in 'Sender:api\.sender\.net' 'Google Tag Manager:tagmanager\.googleapis\.com' 'Google Ads:googleads\.googleapis\.com' \
              'Meta:graph\.facebook\.com' 'Power Automate:api\.flow\.microsoft\.com|powerplatform\.com|logic\.azure\.com(:[0-9]+)?/workflows/'; do
      printf '%s' "$c" | grep -Eiq "${s1#*:}" && sl="${sl:+$sl, }${s1%%:*}"
    done
    local zm=0 tv=0
    printf '%s' "$c" | grep -Eq "(-X|--request|--method)[ =]?['\"]?(POST|PUT|PATCH|DELETE)|(^|[[:space:]])(-d|-F|--data[a-z-]*|--json|--form|--post-data|--post-file|--body-data|--body-file)([[:space:]=]|\$)|['\"\`](POST|PUT|PATCH|DELETE)['\"\`]|\.(post|put|patch)[[:space:]]*\(|method[[:space:]]*[:=][[:space:]]*['\"\`](post|put|patch|delete)['\"\`]|(^|[[:space:]])(POST|PUT|PATCH|DELETE)([[:space:]]|\$)" && zm=1
    # čítanie aj cez POST (vyhľadávanie v Google Ads, správy, adresa spúšťača) — nie zápis, keď v príkaze nič iné nie je
    if printf '%s' "$c" | grep -Eq 'googleAds:search|:generate[A-Z]|/insights|/listCallbackUrl' \
       && ! printf '%s' "$c" | grep -Eq ':mutate|:publish|DELETE|/send|/start|/run|/invoke|api\.sender\.net|tagmanager\.googleapis'; then zm=0; fi
    printf '%s' "$c" | grep -Eiq "(-X|--request|--method)[ =]?['\"]?DELETE|['\"\`]DELETE['\"\`]|(^|[[:space:]])DELETE([[:space:]]|\$)|\.delete[[:space:]]*\(|:publish|status[\\\"'\`]*[[:space:]]*(:|=)[[:space:]]*[\\\"'\`]*(ACTIVE|ENABLED)|deleted[\\\"'\`]*[[:space:]]*(:|=)[[:space:]]*[\\\"'\`]*(1|true)|[\\\"'\`]remove[\\\"'\`]*[[:space:]]*:|state[\\\"'\`]*[[:space:]]*(:|=)[[:space:]]*[\\\"'\`]*Started|method=delete|/(send|schedule|activate|media_publish|feed|messages|run|start|invoke|resubmit)([/?'\"\`[:space:]),]|\$)" && tv=1
    if [ "$zm" = 1 ]; then
      if [ "$tv" = 1 ]; then k="zmazanie, odoslanie, zverejnenie alebo spustenie v marketingovej službe ($sl)"
      elif [ "$mk" != tvrde ]; then k="zmena v marketingovej službe ($sl)"; fi
    fi
  fi
  # scp / rsync s koncovým bodom na cudzom stroji (odchádza von): host:cesta, host::modul, rsync://, ssh://
  printf '%s' "$c" | grep -Eiq "${B}(scp|rsync)[[:space:]]" && printf '%s' "$c" | grep -Eq "(^|[[:space:]])((rsync|ssh)://|([A-Za-z0-9._-]+@)?[A-Za-z0-9._-]+::?[^[:space:]])" && k="odoslanie súboru mimo server (scp/rsync na cudzí stroj)"
  printf '%s' "$c" | grep -Eq "${B}gh (repo (create|edit|unarchive)|(secret|variable) (set|delete|remove)|gist (create|new|edit|delete|rename))( |$)" && k="zápis na GitHub cez API (issue, PR, release, repo)"
  printf '%s' "$c" | grep -Eiq "${B}az rest [^;&|]*(--method|-m)[ =]?(post|put|patch|delete)( |$)" && k="zásah do účtov alebo cloudu (az)"
  printf '%s' "$c" | grep -Eq "${B}git( -C [^ ]+)? push[^;&|]*( --delete| -d( |$)| --prune| \\+?:[^ ;&|])" && k="zmazanie vetvy alebo značky na GitHube (git push --delete)"
  # prepínač v analyzátore (PS 4.35); nasucho ho prepne NG_KOTVA_NASADENIE ako v rozbore. Neznáma alebo nečitateľná
  # hodnota (preklep, veľké písmená, diakritika, dvojité úvodzovky, chýbajúci analyzátor) = najprísnejšia poloha (24. 9.)
  local nas=""
  if [ -n "$SUCHO" ] && [ -n "${NG_KOTVA_NASADENIE:-}" ]; then nas="$NG_KOTVA_NASADENIE"
  else nas=$(grep -m1 -E '^NASADENIE[[:space:]]*=' "$ANA" 2>/dev/null | sed -E "s/^NASADENIE[[:space:]]*=[[:space:]]*['\"]([^'\"]*)['\"].*/\\1/"); fi
  case "$nas" in
    vypnute) ;;
    ostra)   printf '%s' "$c" | grep -Eiq "${B}gh (workflow run[^;&|]*(prod|live|ostr)|run rerun)" && k="nasadenie na ostrú stránku (gh workflow run)";;
    *)       printf '%s' "$c" | grep -Eq "${B}gh (workflow run|run rerun)" && k="spustenie workflow na GitHube (gh workflow run)";;
  esac
  # 3. 10. (K2): nasadenie do ostrej prevádzky inou cestou než gh workflow run (nasadenie_ine v rozbore) — vercel --prod,
  # netlify deploy --prod, firebase deploy, az webapp/functionapp deploy|up|config-zip bez slotu či aplikácie náhľadu,
  # výmena slotov do ostrého, npm/yarn/make deploy…prod, skript deploy…/nasad… s „prod“. Názov kanála je iný než v rozbore,
  # aby výnimka „skoršia veta človeka“ (KANAL_OSTRA v ng-kotva-over.py) pri núdzovom pravidle neplatila.
  if [ "$nas" != vypnute ]; then
    local nd="" seg PRD='(^|[^A-Za-z0-9])(prod|production|produkcia|produkciu|ostra|ostrá|ostru|ostrú|live)([^A-Za-z0-9]|$)' \
          NAH='(preview|prev|staging|stage|stg|test|tst|dev|qa|uat|sandbox|demo|nahlad|canary)'
    printf '%s' "$c" | grep -Eq -e "${B}vercel([[:space:]][^;&|]*)?[[:space:]](--prod|--production|--target[ =][^[:space:]]*prod)|${B}vercel[[:space:]]+promote([[:space:]]|\$)" && nd=1
    printf '%s' "$c" | grep -Eq -e "${B}(netlify|ntl)[[:space:]]+deploy([[:space:]][^;&|]*)?[[:space:]](--prod|--prod-if-unlocked|-p)([[:space:]]|\$)" && nd=1
    printf '%s' "$c" | grep -Eq -e "${B}firebase[[:space:]]+deploy([[:space:]]|\$)" && nd=1
    seg=$(printf '%s' "$c" | grep -oE -e "${B}az[[:space:]]+(webapp|functionapp)[[:space:]]+(deploy|up|deployment[[:space:]]+source[[:space:]]+config-zip|deployment[[:space:]]+slot[[:space:]]+swap)([[:space:]][^;&|]*)?")
    if [ -n "$seg" ]; then
      if printf '%s' "$seg" | grep -Eq -e 'slot[[:space:]]+swap'; then
        printf '%s' "$seg" | grep -Eiq -e "--target-slot[ =][\"']?[^[:space:]\"']*$NAH" || nd=1
      elif ! printf '%s' "$seg" | grep -Eiq -e "(--slot|[[:space:]]-s|--name|[[:space:]]-n)[ =][\"']?[^[:space:]\"'\$]*$NAH" \
           || printf '%s' "$seg" | grep -Eiq -e "(--slot|[[:space:]]-s)[ =][\"']?[^[:space:]\"']*(prod|live)"; then nd=1; fi
    fi
    seg=$(printf '%s' "$c" | grep -oiE -e "${B}(npm|pnpm|yarn|bun)[[:space:]]+((run|run-script)[[:space:]]+)?(deploy|nasad)[^;&|]*|${B}g?make[[:space:]][^;&|]*(deploy|nasad)[^;&|]*")
    [ -n "$seg" ] && printf '%s' "$seg" | grep -Eiq -e "$PRD" \
      && ! printf '%s' "$seg" | grep -Eq -e "make([[:space:]][^;&|]*)?[[:space:]](-n|--dry-run|--just-print|--recon|-q|--question)([[:space:]]|\$)" && nd=1
    seg=$(printf '%s' "$c" | grep -oE -e "(^|[;&|(\`]|\\\$\\()[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*((bash|sh|zsh|python3?|node)[[:space:]]+(-[^[:space:]]+[[:space:]]+)*)?[\"']?([^[:space:];&|<>\"']*/)?(deploy|nasad)[A-Za-z0-9_.-]*[\"']?([[:space:]][^;&|]*)?" \
      | grep -Ev -e "^[^A-Za-z]*(bash|sh|zsh)[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*-[a-zA-Z]*n[a-zA-Z]*[[:space:]]")   # bash -n = len kontrola syntaxe
    [ -n "$seg" ] && printf '%s' "$seg" | grep -Eiq -e "$PRD" && nd=1
    [ -n "$nd" ] && k="nasadenie na ostrú stránku (vercel, netlify, firebase, az webapp, skript nasadenia)"
  fi
  if printf '%s' "$c" | grep -Eq "${B}rm[[:space:]]+(-[a-zA-Z-]+[[:space:]]+)*-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+(-[a-zA-Z-]+[[:space:]]+)*[\"']?(/|~|\\\$HOME)"; then
    printf '%s' "$c" | grep -Eq "rm[[:space:]]+(-[a-zA-Z-]+[[:space:]]+)+[\"']?(/tmp/[^[:space:]]|$DOMOV/projects/[^[:space:]*]|~/projects/[^[:space:]*]|\\\$HOME/projects/[^[:space:]*])" || k="mazanie mimo projektov a mimo gitu"
  fi
  # 3. 10. (K2): find s mazaním (-delete, -exec rm …) od koreňa alebo domova, mimo projektov a /tmp — ako rm -r
  if printf '%s' "$c" | grep -Eq -e "${B}find[[:space:]]+[\"']?(/|~|\\\$HOME)[^;&|]*[[:space:]](-delete|-exec(dir)?[[:space:]]+(rm|shred|truncate|sh|bash)[[:space:]])"; then
    printf '%s' "$c" | grep -Eq -e "find[[:space:]]+[\"']?(/tmp/[^[:space:]]|$DOMOV/projects/[^[:space:]*]|~/projects/[^[:space:]*]|\\\$HOME/projects/[^[:space:]*])" || k="mazanie mimo projektov a mimo gitu"
  fi
  printf '%s' "$c" | grep -Eq 'git (filter-repo|filter-branch)' && k="prepis histórie gitu"
  printf '%s' "$c" | grep -Eq "${B}sudo[[:space:]]+(-[a-zA-Z]+[[:space:]]+|-u[[:space:]]+[^[:space:]]+[[:space:]]+)*(rm|cp|mv|chmod|chown|tee|dd|truncate|install|ln|rsync|bash|sh|python3?|systemctl[[:space:]]+(start|stop|restart|enable|disable|reload))([[:space:]]|$)" && k="systémová služba alebo sudo (zápis, skript alebo služba; čítanie cez sudo prejde)"
  # 3. 10. (K2): sudo s ďalšími zjavnými zápismi (rozbor pod sudo púšťa len čítanie) — úprava na mieste, balíky,
  # používatelia, procesy, sieť a firewall, kontajnery, find s mazaním, journalctl --vacuum, sort -o; výstup príkazu so
  # sudo do systémových priečinkov
  local SU="${B}sudo[[:space:]]+(-[a-zA-Z]+[[:space:]]+|-u[[:space:]]+[^[:space:]]+[[:space:]]+)*"
  if printf '%s' "$c" | grep -Eq -e "${SU}(sed[[:space:]]+([^;&|]*[[:space:]])?(-[a-zA-Z]*i|--in-place)|(apt|apt-get|aptitude|dnf|yum)[[:space:]]+([^;&|]*[[:space:]])?(install|reinstall|remove|purge|upgrade|dist-upgrade|full-upgrade|autoremove)|dpkg[[:space:]]+(-i|-r|-P|--install|--remove|--purge)|snap[[:space:]]+(install|remove|refresh)|pip3?[[:space:]]+(install|uninstall)|(useradd|userdel|usermod|groupadd|groupdel|groupmod|adduser|deluser|passwd|chpasswd|chage|gpasswd|visudo|kill|pkill|killall|reboot|shutdown|poweroff|halt|umount|wipefs|shred|mkfs[a-z0-9.]*|setfacl|chattr|sysctl|modprobe|rmmod|perl|node|ruby|php|zsh|dash)([[:space:]]|\$)|find([[:space:]][^;&|]*)?[[:space:]](-delete|-exec|-execdir|-ok|-okdir|-fprint|-fprint0|-fprintf|-fls)([[:space:]]|\$)|journalctl[[:space:]]([^;&|]*[[:space:]])?--(vacuum-[a-z]+|rotate|flush)|crontab([[:space:]]+-u[[:space:]]+[^[:space:]]+)*[[:space:]]+(-[a-zA-Z]*[er]|[^-[:space:];&|<>]|-([[:space:]]|\$))|sort([[:space:]][^;&|]*)?[[:space:]](-o|--output)|uniq[[:space:]]+(-[^[:space:]]+[[:space:]]+)*[^-[:space:];&|<>][^[:space:];&|<>]*[[:space:]]+[^-[:space:];&|<>]|sed[[:space:]][^;&|]*(['\"[:space:];]w[[:space:]]+/|/w[[:space:]]+/)|git[[:space:]]+([^;&|]*[[:space:]])?(-c|--config-env|--exec-path|--output)([[:space:]=]|\$)|git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(push|commit|reset|checkout|switch|clean|rm|mv|merge|rebase|pull|fetch|config|init|clone|apply|am|stash|tag|branch|gc|prune|restore|cherry-pick|revert|worktree|submodule|remote)([[:space:]]|\$)|dmesg[[:space:]]+(-[a-zA-Z]*[cCD]|--clear|--console-off)|(chroot|unshare|systemd-run|machinectl|su|runuser|doas|pkexec|swapoff|swapon|insmod|ldconfig|update-alternatives|timedatectl|hostnamectl|loginctl)([[:space:]]|\$)|ip[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(link|addr|address|route|rule|neigh|tunnel|netns)[[:space:]]+(set|add|del|delete|flush|change|replace|append)|nft[[:space:]]+(-f|add|delete|flush|insert|replace|create|destroy)|(iptables|ip6tables)([[:space:]][^;&|]*)?[[:space:]]-(A|D|I|F|X|P|R|N|Z)([[:space:]]|\$)|ufw[[:space:]]+(allow|deny|reject|limit|delete|enable|disable|reset|insert|route)|(docker|podman)[[:space:]]+(-[^[:space:]]+[[:space:]]+)*((compose|container|image|volume|network|system)[[:space:]]+)?(rm|rmi|stop|kill|run|exec|start|restart|create|build|pull|push|prune|up|down|cp|commit|tag|update)([[:space:]]|\$))" \
     || printf '%s' "$c" | grep -Eq -e "${SU}[^;&|]*[^2&>]>>?[[:space:]]*[\"']?/(etc|usr|var|opt|boot|root|srv|lib|bin|sbin)/"; then
    k="systémová služba alebo sudo (zápis, skript alebo služba; čítanie cez sudo prejde)"
  fi
  printf '%s' "$c" | grep -Eq "${B}systemctl[[:space:]]+(start|stop|restart|enable|disable|reload)([[:space:]]|$)" && ! printf '%s' "$c" | grep -q 'systemctl --user' && k="systémová služba (start/stop/restart/enable)"
  printf '%s' "$k"
}

ANA="$TU/ng-kotva-analyza.py"; [ -f "$ANA" ] || ANA="$TU/../scripts/ng-kotva-analyza.py"; [ -f "$ANA" ] || ANA=/opt/aigrip-ng/scripts/ng-kotva-analyza.py   # vedľa háčika = verzia z rozvozu (24. 9.)
VYS=""
# 2. 10. večer (nezávislé overenie: každý príkaz pomalší o preklad rozboru — dnes ~400 kB pythonu, ~60 ms): preložený rozbor
# sa drží v ~/.cache/ng-kotva toho, pod kým háčik beží (meno z passwd, nie z $HOME), podľa odtlačku obsahu — zmena rozboru
# alebo pythonu = nový preklad, starý sa po hodine zmaže. Priečinok musí patriť tomu používateľovi a nesmie byť prístupný
# iným, inak sa prekladá zakaždým ako doteraz; akákoľvek chyba vyrovnávačky = obyčajný preklad. Python beží izolovane (-I):
# priečinok príkazu ani PYTHON* premenné nemôžu podstrčiť modul rozboru.
NACITAJ='import hashlib, marshal, os, pwd, stat, sys, time
p, kesa = sys.argv[1], sys.argv[2]
with open(p, "rb") as f:
    zdroj = f.read()
kod = None
def moj(d):
    s = os.lstat(d)
    return stat.S_ISDIR(s.st_mode) and s.st_uid == os.geteuid() and not s.st_mode & 0o077
try:
    kesa = kesa or os.path.join(pwd.getpwuid(os.geteuid()).pw_dir, ".cache", "ng-kotva")
    k = os.path.join(kesa, hashlib.sha256(zdroj + sys.version.encode()).hexdigest()[:40] + ".kod")
    if os.path.isfile(k) and moj(kesa):
        with open(k, "rb") as f:
            kod = marshal.load(f)
except Exception:
    kod = None
if kod is None:
    kod = compile(zdroj, p, "exec")
    try:
        os.makedirs(kesa, mode=0o700, exist_ok=True)
        if moj(kesa):
            for x in os.listdir(kesa):
                y = os.path.join(kesa, x)
                if y != k and x.endswith(".kod") and time.time() - os.lstat(y).st_mtime > 3600:
                    os.unlink(y)
            t = "%s.%d" % (k, os.getpid())
            with open(t, "wb") as f:
                marshal.dump(kod, f)
            os.replace(t, k)
    except Exception:
        pass
# 24. 11. 2026 (STAVBA 4.1238 c): pamäť rozboru medzi behmi — priečinok <verzia>.p vedľa prekladu (0700, vlastník); verzia =
# odtlačok rozboru a pythonu, iná verzia má vlastnú pamäť. Čo sa pamätá a kedy platí, rozhoduje rozbor (PAMAT_ROZBORU).
ver = hashlib.sha256(zdroj + sys.version.encode()).hexdigest()[:40]
pdir = os.path.join(kesa, ver + ".p") if kesa else ""
def daj(m):
    try:
        if not (pdir and moj(kesa) and moj(pdir)):
            return None
        fd = os.open(os.path.join(pdir, m), os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, "rb") as f:
            s = os.fstat(fd)
            if not stat.S_ISREG(s.st_mode) or s.st_uid != os.geteuid() or s.st_size > 33554432:
                return None
            return marshal.loads(f.read())
    except Exception:
        return None
def zabal(v):
    try:
        b = marshal.dumps(v)
        return b if len(b) <= 4194304 else None
    except Exception:
        return None
def uloz(d):
    try:
        zac, ted = time.monotonic(), time.time()
        if not (pdir and moj(kesa)):
            return
        os.makedirs(pdir, mode=0o700, exist_ok=True)
        if not moj(pdir):
            return
        for x in os.listdir(kesa):
            y = os.path.join(kesa, x)
            if x.endswith(".p") and y != pdir and moj(y) and ted - os.lstat(y).st_mtime > 3600:
                for w in os.listdir(y):
                    os.unlink(os.path.join(y, w))
                os.rmdir(y)
        sub = sorted((os.lstat(os.path.join(pdir, w)).st_mtime, os.lstat(os.path.join(pdir, w)).st_size, w) for w in os.listdir(pdir))
        spolu = sum(x[1] for x in sub)
        for cas, vel, w in sub:
            if spolu <= 100663296 and ted - cas < 604800:
                break
            os.unlink(os.path.join(pdir, w))
            spolu -= vel
        for m in sorted(d, key=lambda m: m[0] != "v"):
            if time.monotonic() - zac > 1.0:
                break
            t = os.path.join(pdir, ".%s.%d" % (m, os.getpid()))
            with open(t, "wb") as f:
                marshal.dump(d[m], f)
            os.replace(t, os.path.join(pdir, m))
    except Exception:
        pass
sys.argv = [p] + sys.argv[3:]
exec(kod, {"__name__": "__main__", "__file__": p, "__builtins__": __builtins__,
           "NG_KOTVA_PAMAT": (daj, uloz, zabal, marshal.loads)})'
# 17. 10. (KTZ): rozbor dostáva 15 s na hodinách (predtým 5 s). Svoje stropy ráta v čase procesora (ROZBOR_CAS 6 s) a sám
# povie „nedočítaný“ najneskôr po 13 s na hodinách (ROZBOR_STENA); háčik ho zabije až potom — len zavesený rozbor. Pri
# záťaži servera 5 s nestačilo ani na obyčajné `python3 …/ng-stav.py` (2,8 s procesora) a núdzové pravidlá ho zastavili.
# 20. 11. 2026 (STAVBA 4.1492 b): stropy rozboru 8 / 8,5 s procesora; na hodinách ostáva 12 / 13 s a háčik 15 s.
# 19. 11. 2026 (4.1172 h): rozbor potrebuje vedieť, ktoré sedenie je toto — api/poslat inému sedeniu prejde, vlastnému nie
export NG_KOTVA_STOPA="$STOPA"
[ -n "$SUROVY" ] || VYS=$(printf '%s' "$CMD" | s_limitom 15 python3 -I -c "$NACITAJ" "$ANA" "$KESA" "$CWD" "$DOMOV" 2>/dev/null)
ZN=""; kanal=""; PRIZNAKY=""
{ IFS= read -r ZN; IFS= read -r kanal; IFS= read -r PRIZNAKY; } <<< "$VYS"
if [ "$ZN" != "kotva-analyza 1" ]; then kanal=$(nudzove); PRIZNAKY=""; fi
# 16. 11. 2026 (slovo PS k STAVBA 4.311 „a“, AIG-R261115-68d108): slovo človeka pre stráž konektorov. Volanie prehliadača
# či konektora nemá kam dať „# potvrdené:“ — partner ho dá k príkazu `python3 …/ng-mcp-potvrd.py <konektor> <cieľ>`.
# Ten má kanál toho konektora a cieľa (ten istý text, ktorý stráž konektorov zapísala pri zastavení), takže potvrdenie,
# ohlásenie aj overenie slov idú presne cestou nižšie; stráž konektorov potom pustí kroky na tom cieli pol hodiny od
# riadku „pustené“. Kanál z rozboru, ktorý v príkaze našiel niečo iné, ostáva (povolenie pre konektor potom nevznikne);
# prepíše sa len prázdny alebo „nedočítaný skript“.
if printf '%s' "$CMD" | grep -q 'ng-mcp-potvrd\.py'; then
  KONS="$TU/ng-kotva-konektor.py"; [ -f "$KONS" ] || KONS="$TU/../scripts/ng-kotva-konektor.py"; [ -f "$KONS" ] || KONS=/opt/aigrip-ng/scripts/ng-kotva-konektor.py
  KK=$(printf '%s' "$CMD" | s_limitom 5 python3 -I -B "$KONS" kanal-prikazu 2>/dev/null | head -1)
  if [ -n "$KK" ]; then
    case "$kanal" in ""|"skript, ktorý príkaz spúšťa, kotva nedočítala"*) kanal="$KK";; esac
  fi
fi

# PS 4.107 d (13. 10. 2026, záznam AIG-R261013-044de2): OHLÁSENIE BEZ SPUSTENIA. Keď sa partner chce opýtať
# VOPRED (pilotný text mu to pri veľkej veci káže), pridá k príkazu dodatok „# ohlásenie“: stráž príkaz posúdi,
# NIKDY ho nespustí a povie, čo je to za krok. Keď by ho zastavila, zapíše to ako zastavenie — práve preto potom
# platí odpoveď človeka na prvýkrát a nepýta sa druhý raz (pravidlo 4.27 sa nemení, len prestane vyrábať dvojitú
# otázku). Ohlásenie je prísnejšie než dnešok: nespustí ani to, čo by inak prešlo bez otázky. Keď je v príkaze
# ohlásenie aj „# potvrdené:“, platí ohlásenie — teda sa nespustí nič. Vypnúť = zmazať túto vetvu.
OHLAS=0
printf '%s' "$CMD" | grep -qE '#[[:space:]]*(ohlásenie|ohlasenie)' && OHLAS=1

# 16. 11. 2026 (kus Z261116-623bb7): zastavenie LEN pre nedočítaný skript (príznak rozboru, alebo núdzové pravidlá
# s jediným kanálom K_NEDOC) povie rovno, že to nie je porucha platformy a krok prejde po slove človeka. Sedenie
# JOURFIXY 16. 11. prečítalo holé „kotva nedočítala“ ako poruchu kontroly stráží, povedalo človeku, že stráže do pm-od
# pridať nemôže, kým to správca neopraví, a prácu odložilo na ráno — zastavenie kotvy pritom prekoná jedna otázka
# človeku (na pm-od bola navyše druhá zábrana, pozri nižšie). Pri zastavení s iným
# kanálom (aj „… a zároveň skript … nedočítala“) sa veta nepridáva: tam je dôvodom ten iný krok. Veta sľubuje len
# priechod kotvou: skript sám môže mať ďalšiu zábranu, ktorú slovo neprekoná (pm-od 16. 11. 21:55 — kontrola zdroja
# v rozvoze pri červenom teste kotvy, záznam AIG-P261116-8398cb); preto „cez kotvu krok prejde“, nie „krok prejde“.
NEDOC_VETA=""
case " $PRIZNAKY " in *" nedocitane "*) NEDOC_VETA=1;; esac
[ "$ZN" != "kotva-analyza 1" ] && [ "$kanal" = "$K_NEDOC" ] && NEDOC_VETA=1
[ -n "$NEDOC_VETA" ] && NEDOC_VETA="Nie je to porucha platformy, na ktorú treba čakať — kotva len nevie, čo skript urobí, a preto sa pýta. Cez kotvu krok prejde hneď, stačí slovo človeka: opýtaj sa ho teraz a prácu neodkladaj."

# kus Z261116-60e8ae: krok so značkou rozhodnutia, ktorý kotva nezastavila (napr. po zmene rozboru), sa zo zoznamu
# čakajúcich potvrdení vyberie — inak by tam visel, hoci prešiel
# 19. 11. 2026 (PS 4.1172 f): vratný úkon vo vlastnej schránke cez pomenovaný príkaz poštového nástroja (rozbor ho pustil
# s príznakom posta-vratna) — riadok v audite, aby meranie pustení poistky videlo, čo prešlo bez otázky
if [ -z "$kanal" ] && [ "$OHLAS" != 1 ]; then
  case " $PRIZNAKY " in *" posta-vratna "*)
    TS=$(date +%Y-%m-%dT%H:%M:%S); ST=$(basename "$STOPA" .jsonl 2>/dev/null | cut -c1-40)
    PRIKAZ=$(printf '%s' "$CMD" | cut -c1-300)
    kanal="úkon vo vlastnej schránke (4.1172 f)"; zapis_audit "$(audit_riadok 'bez otázky (4.1172 f)')"; kanal="" ;;
  esac
fi
if [ -z "$kanal" ] && [ "$OHLAS" != 1 ]; then zapis_caka pustene; exit 0; fi

TS=$(date +%Y-%m-%dT%H:%M:%S)
ST=$(basename "$STOPA" .jsonl 2>/dev/null | cut -c1-40)
PRIKAZ=$(printf '%s' "$CMD" | cut -c1-300)

if [ "$OHLAS" = 1 ]; then
  if [ -n "$kanal" ]; then
    zapis_audit "$(audit_riadok 'zastavené')"
    zapis_caka zastavene
    odmietni "Ohlásenie — príkaz som NESPUSTIL. Stráž by ho zastavila: $kanal.${NEDOC_VETA:+ $NEDOC_VETA} Opýtaj sa človeka jednou vetou v texte (čo sa stane · komu alebo kam · dá sa to vrátiť?) a po jeho odpovedi spusti ten istý príkaz BEZ „# ohlásenie“ a s dodatkom  # potvrdené: <jeho slová doslova>."
  else
    odmietni "Ohlásenie — príkaz som NESPUSTIL. Stráž by ho pustila bez otázky; keď ho chceš naozaj spustiť, zopakuj ho bez „# ohlásenie“."
  fi
  exit 0
fi
# 19. 11. 2026 (PS 4.1172 b, AIG-R261119-3d2f0e): ťuk na kartu poistky platí ako napísané áno — len pri kroku, ktorý
# karta opíše celý (pomenovaný nástroj, doslovný príkaz; ng-tuk.py), raz, pre to isté sedenie a do 10 minút po ťuku.
# Ťuk zapisuje len služba ťukov mimo izby (aig-admin-api ako root); kotva ho len číta a prepočíta odtlačok kroku aj
# obsahu súborov, ktoré posiela. Bez ťuku pripraví kartu (TUK=karta…), keď je služba nasadená a človek má ťuk zapnutý.
TUK=""
# 20. 11. 2026 (STAVBA 4.1494 a, bod 3; mení 4.1172 b): aj pomenované nasadenie na server (skript zo zoznamu NASADENIA
# v ng-tuk.py, doslovne `bash <skript> --naostro`) — karta len pri zastavení sudo/služby, karta mailu len pri pošte.
case "$kanal" in
  "odoslanie mailu alebo správy"*|"systémová služba alebo sudo"*)
    case "$kanal" in *" a zároveň "*) ;; *)
      NG_TUK_KANAL=posta; case "$kanal" in "systémová služba alebo sudo"*) NG_TUK_KANAL=sudo ;; esac; export NG_TUK_KANAL
      TUKS="$TU/ng-tuk.py"; [ -f "$TUKS" ] || TUKS="$TU/../scripts/ng-tuk.py"; [ -f "$TUKS" ] || TUKS=/opt/aigrip-ng/scripts/ng-tuk.py
      [ -f "$TUKS" ] && TUK=$(printf '%s' "$CMD" | s_limitom 10 python3 -I "$TUKS" kotva "$STOPA" "$CWD" "$DOMOV" "$PODAGENT" 2>/dev/null | head -1) ;;
    esac ;;
esac
case "$TUK" in
  pusti$'\t'*)
    zapis_audit "$(audit_riadok 'pustené ťukom' "" "ťuk na kartu ${TUK#pusti$'\t'} (4.1172 b)")"
    zapis_caka pustene
    exit 0 ;;
esac
if printf '%s' "$CMD" | grep -q '# potvrdené:'; then
  VETA=$(printf '%s' "$CMD" | sed -n 's/.*# potvrdené:[[:space:]]*//p' | head -1 | sed -E 's/[[:space:]]*#[[:space:]]*rozhodnutie:.*$//' | cut -c1-200)
  # M1+M3+M5 (STAVBA 4.27, verdikt PS 23. 9. 16:15 — V1): potvrdenie len slovom človeka z tohto sedenia po zastavení, do 30 min,
  # nie z podagenta. Vypnúť sa dá len nasucho (NG_KOTVA_SUCHO=1 a NG_KOTVA_OVER=0 — červený test, prehrávka); predtým
  # overenie vyplo hocičo iné než „1“ (true, yes, 0 …) aj v ostrom behu (24. 9.)
  OV=''
  if [ -z "$SUCHO" ] || [ "${NG_KOTVA_OVER:-1}" != 0 ]; then
    OVS="$TU/ng-kotva-over.py"; [ -f "$OVS" ] || OVS="$TU/../scripts/ng-kotva-over.py"; [ -f "$OVS" ] || OVS=/opt/aigrip-ng/scripts/ng-kotva-over.py
    OV=$(s_limitom 10 python3 "$OVS" "$STOPA" "$VETA" "$kanal" "$PODAGENT" "$LOG" 2>/dev/null || printf 'nie\noverenie zlyhalo')
    if [ "$(printf '%s' "$OV" | head -1)" != "ok" ]; then
      zapis_audit "$(audit_riadok 'znak neoverený' "$VETA" "$(printf '%s' "$OV" | sed -n 2p | cut -c1-200)")"
      odmietni "Potvrdenie neprešlo — $(printf '%s' "$OV" | sed -n 2p). Neobnoviteľná akcia ($kanal) potrebuje odpoveď človeka v tomto sedení po zastavení."
      exit 0
    fi
  fi
  CIM=$(printf '%s' "${OV:-}" | sed -n 2p | cut -c1-200)
  [ -n "$OV" ] || CIM='overenie nebežalo (nasucho: NG_KOTVA_SUCHO a NG_KOTVA_OVER=0)'
  zapis_audit "$(audit_riadok 'pustené' "$VETA" "$CIM")"
  zapis_caka pustene
  zapis_stopu_pustenia "$(printf '%s' "${OV:-}" | sed -n 3p)"
  exit 0
fi
zapis_audit "$(audit_riadok 'zastavené')"
zapis_caka zastavene
# cesta v premennej (rm -rf "$S"): kotva ju nevie prečítať, preto zastaví — hlásenie povie, čo s tým (nález 21. 9., falošné zastavenie v pieskovisku)
DOPLN="${NEDOC_VETA:+ $NEDOC_VETA}"
case "$TUK" in karta$'\t'*) DOPLN="$DOPLN Karta s týmto krokom (${TUK#karta$'\t'}) čaká na ťuk človeka v riadiacom centre a hlasový asistent mu ju ohlási. Keď ťukne, príde do sedenia pripomienka „(Ťuk na kartu poistky …)“ — potom zopakuj ten istý príkaz bez zmeny. Inak sa ho opýtaj ako vždy.";; esac
case " $PRIZNAKY " in *" premenna "*) DOPLN="$DOPLN Cesta je v premennej — kotva ju nevie prečítať; napíš ju doslovne (v tvojich projektoch v ~/projects alebo v /tmp prejde bez otázky).";; esac
# 2. 10. (úloha K, incident 1. 10.): neobnoviteľný krok je vo vnútri skriptu, ktorý príkaz spúšťa — „skúška“ skriptu je
# zásah, ak skript vie opravovať (account-cp L-053). Oprava po nezávislom overení (2. 10. večer): hlásenie už neradí, ktorou
# voľbou skript spustiť, aby prešiel bez otázky (taká rada viedla k obídeniu stráže); povie len, že krok je v skripte.
# 3. 10.: nedočítaný skript — text kanála to hovorí sám, veta „kotva ho prečítala“ by neplatila
case " $PRIZNAKY " in *" nedocitane "*) ;; *" skript "*) DOPLN="$DOPLN Ten krok je vo vnútri skriptu alebo kódu, ktorý príkaz spúšťa (kotva ho prečítala).";; esac
# 20. 10. 2026 (sľub 3.09): pod sudo kotva skript aj kód prečíta, ale obsah videla ako PS — pod iným menom môže
# bežať niečo iné. Vetu doplní háčik, do textu kanála nepatrí (rozišla by sa so základom a sonda by to hlásila).
case " $PRIZNAKY " in *" sudo-skript "*) DOPLN="$DOPLN Skript alebo kód som čítal ako ty; pod sudo môže bežať pod iným menom, a potom robiť aj niečo iné." ;; esac
# 5. 11. 2026 (STAVBA 4.189 (b), slovo PS): ked ide nieco von k ludom, pripomen oznacene fakty do vystupu, ktore
# nikto nepotvrdil. Meranie 3. 11.: z 30 takych faktov neobstali 2 a ten, ktory naozaj odisiel zakaznikovi, bol prave
# fakt do vystupu — dokument vsak poslal clovek sam, takze kontrola pri odchode je jedine miesto, kde ho stroj vidi.
case "$kanal" in
  *"mailu alebo správy"*|*"mimo server"*|*"ostrú stránku"*|*"marketingovej službe"*)
    FDVS="$TU/ng-fakty-do-vystupu.py"; [ -f "$FDVS" ] || FDVS="$TU/../scripts/ng-fakty-do-vystupu.py"
    [ -f "$FDVS" ] || FDVS=/opt/aigrip-ng/scripts/ng-fakty-do-vystupu.py
    if [ -f "$FDVS" ]; then
      FDV=$(s_limitom 10 python3 "$FDVS" --hook 2>/dev/null | head -1)
      [ -n "$FDV" ] && DOPLN="$DOPLN $FDV"
    fi ;;
esac
# 12. 11. 2026 (PS 19:58, záznam AIG-R261112-fa8333, zoznam podnetov workspace 281): kto má v aig zapnuté „Maily: odoslať
# na jasný pokyn bez ďalšej otázky“, toho sa partner pri jasnom pokyne nepýta — no partner v inom projekte nevie, že má
# hneď pridať slová človeka (PS to má v osobných pokynoch, kolegovia nie). Pri pošte samotnej (nie s iným kanálom
# a nie z podagenta) to preto zastavenie povie; slová overí ng-kotva-over.py (posli_zadane) presne ako doteraz.
if [ "$kanal" = "odoslanie mailu alebo správy" ] && [ "$PODAGENT" != 1 ]; then
  OVP="$TU/ng-kotva-over.py"; [ -f "$OVP" ] || OVP="$TU/../scripts/ng-kotva-over.py"; [ -f "$OVP" ] || OVP=/opt/aigrip-ng/scripts/ng-kotva-over.py
  if [ "$(s_limitom 5 python3 "$OVP" --posta-bez-otazky 2>/dev/null | head -1)" = 1 ]; then
    DOPLN="$DOPLN Človek má v aig zapnuté „Maily: odoslať na jasný pokyn bez ďalšej otázky“ — keď je jeho POSLEDNÁ správa jasný pokyn poslať tento mail (pošli · odošli · napíš mail <komu>, že …), nepýtaj sa ho: zopakuj príkaz hneď s dodatkom  # potvrdené: <jeho veta s pokynom doslova>. Keď pokyn jasný nie je, opýtaj sa ako zvyčajne."
  fi
fi
# kus Z261116-60e8ae: krok, ktorý už má rozhodnutie človeka, patrí do zoznamu čakajúcich potvrdení (stav, časť 4) —
# v projekte s dokumentom stavby to hlásenie povie; partner podagenta sa nepýta, preto mu to nehovorí
if [ "$PODAGENT" != 1 ] && [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "${CLAUDE_PROJECT_DIR}/STAVBA.md" ]; then
  if [ -n "$ZNACKA" ]; then
    DOPLN="$DOPLN Krok je v zozname krokov, ktoré čakajú len na slová človeka pre kotvu (rozhodnutie $ZNACKA) — človek ho vidí v stave a v časti 4."
  else
    DOPLN="$DOPLN Keď na tento krok už je rozhodnutie človeka a chýbajú len jeho slová, pridaj na koniec príkazu  # rozhodnutie: <číslo položky a voľba> — <čo to je po ľudsky>  — človek ho potom uvidí v stave a v časti 4 medzi krokmi, ktoré čakajú na jeho slová."
  fi
fi
odmietni "Neobnoviteľná akcia — $kanal.$DOPLN Kotva veľkého dosahu: najprv sa opýtaj človeka jednou vetou v texte (čo sa stane · komu alebo kam · dá sa to vrátiť?). Keď odpovie, zopakuj ten istý príkaz s dodatkom  # potvrdené: <jeho slová doslova>  — prejde len so slovami, ktoré človek napísal v tomto sedení po otázke (platia pol hodiny, podagent nepotvrdzuje nič)."
exit 0

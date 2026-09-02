# Texttools cheatsheet

## Twee workflows

### 1. Neovim → Pubble (één artikel)

```
Clipboard/bron kopiëren
→ Keyboard Maestro trigger → pastevim() → `Pubble Inbox/werk` → cleantext → opent in Neovim

In Neovim:
  Controlecodes bovenaan typen (zie hieronder)
  <leader>ar    herschrijven; start metadata en gevraagde extra's
  <leader>ac    kalenderdata; onvolledige items tonen wat nog ontbreekt
  <leader>an    alleen subjectieve journalistentaal minimaal neutraliseren
  <leader>af    Facebook-post genereren — verschijnt als ## Facebook sectie
  <leader>aV    overzicht van bron en losse krantversiebuffers
  <leader>aG    huidige krantversie opslaan en goedkeuren
  <leader>aw    onbewerkte-importcontrole, planning en versturen naar Pubble
```

Na volledig succes verhuist het artikel naar `Pubble Archief`; het werkbestand
verdwijnt en de open tekst wordt een niet-schrijfbare nacontrolebuffer.

### 2. pubble-batch (meerdere documenten tegelijk)

```
Documenten (en bijbehorende foto's) neerzetten in:
  ~/.texttools/pubble-inbox/pubble-batch/

Optioneel: artikel.meta aanmaken (kopieer template.meta, hernoem)

pubble-batch           # verwerkt alles, opent deck-pagina als klaar
pubble-batch --dry-run # preview zonder te versturen

Op de achtergrond:
pubble-batch > ~/Desktop/pubble-batch.log 2>&1 &
```

---

## Neovim leaders

| Leader | Actie |
|---|---|
| `<leader>ar` | Herschrijven naar krantenartikel (AI) |
| `<leader>ac` | Metadata + kalenderitem — ontbrekende velden tonen het formaat, zoals `Tijd: HH:MM` |
| `<leader>ao` | Tekstcheck; twijfelgevallen komen onder `## Suggesties` |
| `<leader>an` | Journalistiek neutraliseren; minimale ingreep, bestaande citaten en concrete waarden beschermd |
| `<leader>at` | Tussenkopjes, optionele streamer en 2 kopopties; gekozen kop wordt zo nodig vóór de lead ingevoegd |
| `<leader>af` | Facebook-post genereren — toont bewerkbare `## Facebook` sectie |
| `<leader>aV` | Overzicht van bron en afzonderlijke krantversiebuffers |
| `<leader>aG` | Huidige krantversie opslaan en expliciet goedkeuren |
| `<leader>aw` | Publicatie voorbereiden en naar Pubble versturen; waarschuwt als de artikelbody nog nauwelijks afwijkt van de import, en laat een ontbrekende `e:` eerst bevestigen |
| `<leader>ap` | Ad-hoc herschrijven — typ `***` + instructie, buffer wordt vervangen |
| `<leader>ag` | AI gesprek — typ `***` + vraag, antwoord verschijnt eronder |
| `<leader>ah` | Hiërarchisch hulpmenu voor codes, rubrieken, acties en cheatsheet |
| `<leader>kt` | Handmatig rubriektemplate kiezen, inclusief Raadspraat, Ondernemen en Kamper Kiek |
| `<leader>kp` | Rubriekplanning: reminders en planningsoverzichten |
| `<leader>ka` | Ruwe papieren agendapagina voorbereiden voor eigen tekstcontrole |

---

## Automatisch of handmatig?

- **Automatisch uit de tekst:** kalenderdetectie, een ondubbelzinnige Kamper
  Kiek met vaste naam plus nummering 1–3, en Hondenhoek bij Bert Nieuwenhuis +
  hond/honden (of `Hondenhoek` + een tweede signaal). Kamper Kiek vereist exact
  één foto; voor Hondenhoek moet Pubble Inbox leeg zijn.
- **Altijd met bevestiging:** 112-detectie. Een onzekere rubriek of conflict
  opent een keuzemenu.
- **Niet automatisch uit de tekst herkend:** Raadspraat, Ondernemen in Kampen
  en alle andere vaste rubrieken; kies die via `<leader>kt`.
- **`<leader>kp`:** leest de artikeltekst niet; toont alleen de planning voor
  Raadspraat en Ondernemen.
- Namen, partijen en foto's worden pas na je rubriekkeuze uit mappen of
  `personen.md` ingevuld.

Vaste volgorde voor rubrieken:

1. Rond kop en tekst af.
2. Maak Pubble Inbox leeg; zet voor Kamper Kiek juist exact één Kiek-foto klaar.
3. Kies met `<leader>kt` de rubriek; een zekere Kamper Kiek of Hondenhoek kan
   deze stap al automatisch hebben uitgevoerd. Template en foto's worden
   voorbereid, maar er wordt nog geen vormgevingstekst geschreven.
4. Controleer het resultaat en vul alle zichtbare `{{velden}}` in.
5. `<leader>aw` publiceert en schrijft daarna precies één actuele `.txt` naar
   de juiste weekmap. Bij een fout blijft het exportplan staan voor de retry.

Papieren agendapagina: plak alle dagen en activiteiten en druk eenmaal
`<leader>ka`. Controleer daarna de zichtbare velden en druk `<leader>aw`; kies
dan de krant. De technische controle draait automatisch vóór verzending.
`>>>titel<<<` is premium: tekst blijft exact, AI mag alleen ontbrekende metadata
uitlezen. `hele dag` mag; de printbody heeft geen lengtegrens. Gewone koppen zijn bij
voorkeur 3–4 en maximaal 5 woorden; een
herkend los slotblok wordt automatisch een aparte activiteit onder zijn
primaire datum. Een duidelijk verkeerd geplaatst item verhuist mee, secundaire
data niet. Dit maakt alleen
het printconcept `!agendapagina`.

---

## Controlecodes (bovenaan artikel typen, vóór de kop)

Werken via **Neovim** (`<leader>ar`/`<leader>aw`) én via **pubble-batch**:

```
editie: B          # of SW, ST, Z, D, K, all, overijssel, flevoland
prio: 2            # 1=moet mee  2=mag mee  3=rest(standaard)  4=nood
b: Bijschrift      # fotobijschrift
c: Naam fotograaf  # fotocredit
@John Boodschap    # alleen voor actuele Teams-ontvanger John
@all Boodschap     # voor alle Teams-meldingen van dit artikel
```

Meerdere ontvangers op één regel: `@Joop, @Saskia Boodschap`. De selectors
zijn hoofdletterongevoelig, worden niet getoond en volgen eventuele waarneming
uit `:TeamsRedactie`.

Alternatieve notatie voor bijschrift/credit (ook herkend in eerste 4 regels):
```
Bijschrift: tekst
Foto: naam fotograaf
```

---

## Speciale secties (onderaan artikel)

Worden automatisch gestript vóór publicatie:

```markdown
---

## Facebook

Jouw tekst hier. Lees het volledige artikel op onze website.
```

```markdown
---

## Kalender

Titel: Naam evenement
Datum: 2026-07-23
Tijd: 10:00
Locatie: Naam locatie

Korte omschrijving. Geen datum/tijd/locatie herhalen.
```

---

## pubble-batch .meta sidecar

Kopieer `template.meta` → hernoem naar `<artikelnaam>.meta`:

```
editie:          # e.g. B, SW
prio:            # 1-4
b:               # fotobijschrift
c:               # fotocredit
rewrite:         # x → herschrijven naar krantenstijl (AI)
calendar:        # x → kalenderitem meenemen
facebook:        # x → Facebook-post genereren (AI)
facebook_tekst:  # eigen tekst → als Facebook-post gebruiken
web:             # draft → web ongepubliceerd; werktitel krijgt NOG SITE
```

Of zet dezelfde regels **bovenaan het document zelf** (voor de kop), gevolgd door een lege regel.

---

## Edities

| Code | Krant |
|---|---|
| `B` | De Brug *(standaard)* |
| `SW` | De Swollenaer |
| `ST` | De Stadskoerier |
| `Z` | Zeewolde Actueel |
| `D` | De Drontenaar |
| `K` | Nieuwsbode de Kop |
| `all` | alle edities |
| `overijssel` | B, SW, ST, K |
| `flevoland` | D, Z |

Bij import wordt een betrouwbare dateline of duidelijke provinciale strekking
eenmalig als `e:` ingevuld. Een bestaande regel wint altijd. Na herschrijven
wordt alleen om een keuze gevraagd als de betrouwbare inhoudsdetectie door de
rewrite zelf is veranderd. Staat
bij `<leader>aw` nog geen `e:`, dan moet de afgeleide bestemming eerst worden
bevestigd; daarna blijft de regel boven het artikel staan.

Na `<leader>ar` met meerdere gekozen edities verschijnt de vraag of iedere
krant een eigen versie moet krijgen. Kies je **Ja**, dan blijft de gewone body
de niet te publiceren bron en krijgt iedere krant een eigen buffer. Sla een
edit op met `:w`, keur haar goed met `<leader>aG` en gebruik `<leader>aV` voor
het overzicht. `<leader>aw` verstuurt per krant de passende print- én webversie
en blokkeert bij ontbrekende, verouderde of nog niet goedgekeurde teksten. Kies
**Nee** om één gezamenlijke tekst te behouden.

---

## Foto's koppelen (pubble-batch)

Foto's worden automatisch gekoppeld op basis van bestandsnaam-stam:

```
artikel.docx  →  artikel.jpg, artikel2.jpg, artikel3.jpg
```

Geen letters of koppeltekens na de stam — alleen cijfers.

---

## Terugdraaien

| Tag | Moment |
|---|---|
| `v-voor-markdown-html` | vóór Markdown→HTML conversie voor webartikel |
| `v-voor-video-embed` | vóór YouTube-embed experimenten |
| `v-voor-live-video-test` | vóór live video-embed test |

```bash
git checkout <tag>
uv sync --locked
```

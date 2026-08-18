# Texttools cheatsheet

## Twee workflows

### 1. Neovim → Pubble (één artikel)

```
Clipboard/bron kopiëren
→ Keyboard Maestro trigger → pastevim() → cleantext → opent in Neovim

In Neovim:
  Controlecodes bovenaan typen (zie hieronder)
  <leader>ar    herschrijven; start metadata en gevraagde extra's
  <leader>ac    metadata + kalenderitem — verschijnt als ## Kalender sectie
  <leader>af    Facebook-post genereren — verschijnt als ## Facebook sectie
  <leader>aw    publicatieplanning controleren en versturen naar Pubble
```

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
| `<leader>ac` | Metadata + kalenderitem — toont bewerkbare `## Kalender` sectie |
| `<leader>ao` | Tekstcheck; twijfelgevallen komen onder `## Suggesties` |
| `<leader>at` | Tussenkopjes en optionele streamer |
| `<leader>af` | Facebook-post genereren — toont bewerkbare `## Facebook` sectie |
| `<leader>aw` | Publicatie voorbereiden en naar Pubble versturen |
| `<leader>ap` | Ad-hoc herschrijven — typ `***` + instructie, buffer wordt vervangen |
| `<leader>ag` | AI gesprek — typ `***` + vraag, antwoord verschijnt eronder |
| `<leader>ah` | Hiërarchisch hulpmenu voor codes, rubrieken, acties en cheatsheet |
| `<leader>kt` | Handmatig rubriektemplate kiezen, inclusief Raadspraat, Ondernemen en Kamper Kiek |
| `<leader>kp` | Rubriekplanning: reminders en planningsoverzichten |

---

## Automatisch of handmatig?

- **Automatisch uit de tekst:** alleen kalender- en 112-detectie.
- **Altijd handmatig via `<leader>kt`:** Raadspraat, Ondernemen in Kampen,
  Kamper Kiek en alle andere vaste rubrieken.
- **`<leader>kp`:** leest de artikeltekst niet; toont alleen de planning voor
  Raadspraat en Ondernemen.
- Namen, partijen en foto's worden pas na je rubriekkeuze uit mappen of
  `personen.md` ingevuld.

---

## Controlecodes (bovenaan artikel typen, vóór de kop)

Werken via **Neovim** (`<leader>ar`/`<leader>aw`) én via **pubble-batch**:

```
editie: B          # of SW, ST, Z, D, K, all, overijssel, flevoland
prio: 2            # 1=moet mee  2=mag mee  3=rest(standaard)  4=nood
b: Bijschrift      # fotobijschrift
c: Naam fotograaf  # fotocredit
```

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

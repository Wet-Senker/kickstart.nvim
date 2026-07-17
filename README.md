# kickstart.nvim — Brugmedia redactie

Neovim-configuratie voor de redactionele workflow van Brugmedia. Artikelen worden geschreven in Neovim, via AI verwerkt, en via de Pubble API gepubliceerd.

Gekoppeld aan: [texttools](https://github.com/Wet-Senker/texttools) (Python-package voor AI, metadata en Pubble-API).

---

## Workflow

```
Clipboard → pastevim() → cleantext → `=== ARTIKEL ===` + tekst → Neovim

<leader>ar    Herschrijven naar krantenartikel (AI)
              ↳ start background jobs (metadata, kalender, Facebook) op basis van controlecodes
              ↳ detecteert 112 en kalender automatisch
<leader>am    Metadata genereren (krant + web)
<leader>ac    Kalendermetadata + ## Kalender sectie
<leader>ao    Tekstcheck: spelling/grammatica + ## Suggesties
<leader>at    Tussenkopjes + optionele streamer
<leader>af    Facebook-post genereren → ## Facebook sectie
<leader>aw    Versturen naar Pubble — wacht op geregistreerde achtergrondtaken
```

---

## Leaders

| Leader | Actie |
|---|---|
| `<leader>ar` | Herschrijven naar krantenartikel (AI). Start background jobs voor metadata, kalender en/of Facebook op basis van controlecodes. Detecteert 112 en agendaberichten automatisch. |
| `<leader>am` | Metadata genereren (krant + web). |
| `<leader>ac` | Kalendermetadata + bewerkbare `## Kalender` sectie. |
| `<leader>ao` | Tekstcheck: objectieve correcties en twijfelgevallen onder `## Suggesties`. |
| `<leader>at` | Tussenkopjes en, als er nog geen eigen `>` staat, een streamer. |
| `<leader>af` | Facebook-post genereren → bewerkbare `## Facebook` sectie. Bij 112-detectie: zakelijke prompt (één feitelijke zin). |
| `<leader>aw` | Versturen naar Pubble. Een incompleet agenda-item geeft de keuze om eerst aan te vullen of alleen web/print te plaatsen. Bij gekozen eventvervolgen toont de eerste druk de teksten; de tweede publiceert alles samen. |
| `<leader>ap` | Ad-hoc herschrijven — typ `***` + instructie, buffer wordt vervangen. |
| `<leader>ag` | AI gesprek — typ `***` + vraag, antwoord verschijnt eronder. |
| `<leader>ah` | Cheatsheet: editie/prio/bijschrift/foto codes invoegen. |
| `<leader>kt` | Rubriektemplate invoegen (Raadspraat, 112, Hondenhoek, etc.). |

---

## Controlecodes

Boven `=== ARTIKEL ===` typen. `pv` plaatst die grens automatisch; de kop staat
eronder. `<leader>ah` voegt een gekozen code automatisch boven de grens in.

```
editie: B          # of SW, ST, Z, D, K, all, overijssel, flevoland
prio: 2            # 1=moet mee  2=mag mee  3=rest(standaard)  4=nood
rubriek: 112       # markeert als 112-bericht
calendar: x        # kalendermetadata ophalen bij <leader>ar of <leader>aw
facebook: x        # Facebook-post genereren bij <leader>ar
b: Bijschrift      # globaal fotobijschrift
c: Naam fotograaf  # globale fotocredit
b1: / c1:          # bijschrift/credit voor foto 1 specifiek
b2: / c2:          # bijschrift/credit voor foto 2 specifiek

=== ARTIKEL ===

Artikelkop
```

Alles boven de marker is beschermd en wordt nooit als AI-rewrite-input gebruikt.
Ook een visuele AI-selectie die de marker kruist wordt geweigerd.
Bij `<leader>aw` valideert Python iedere regel daar strikt. `f:` is geen tag;
gebruik `c:` of `Foto:`. `***` is bewust iets anders: die regel blijft voor
inline AI-prompts en gesprekken gereserveerd.

---

## Automatische detectie bij import

Bij het openen van een `.md`-bestand op `~/Desktop/`:

**112-detectie** — scoort tekst op signaalwoorden (politie, brandweer, ambulance, incident, etc.). Bij score ≥ 6 verschijnt een bevestigingsvraag. Bij "Ja": 112-template toegepast, `rubriek: 112` en `prio: 1` bovenaan gezet. Bij "Nee" blijft die keuze voor de huidige buffer staan en mag detectie na `<leader>ar` het template niet alsnog toepassen. De kop gebruikt via `pubble-places` de eerste bekende plaats uit de centrale verspreidingsgebiedentabel; zonder treffer wordt het `112:`.

**Kalenderdetectie** — scoort tekst op datum/tijd/deelname-signalen. Bij score ≥ 8: `articlemeta --calendar` gestart en `## Kalender` sectie toegevoegd (geen bevestiging nodig).

Beide checks lopen ook na `<leader>ar` op de herschreven tekst. 112 vraagt daar
alleen opnieuw om bevestiging als bij import nog geen keuze is gemaakt.

---

## 112-berichten

- Template: `112 <PLAATS>: <titel>` (of `112: <titel>`) + body + disclaimer
- `rubriek: 112` → `articleCategoryId: 24` op krant én web in Pubble
- `<leader>af` gebruikt zakelijke Facebook-prompt (één zin, geen interactie)
- `<leader>ar` op een al opgemaakte 112-buffer: herschrijft alleen titel en body, laat prefix en disclaimer intact

## Pubble-archief

Na `<leader>aw` verhuist het volledige Markdownbestand met frontmatter en alle
Pubble-ID's naar `~/Documents/Pubble Archief/<jaar>/<maand>/`. Het blijft de
bron voor hervatten en evenementvervolgen. `TEXTTOOLS_ARCHIVE_DIR` kan naar
een gesynchroniseerde cloudmap wijzen; het standaardpad mag ook een symlink
naar die cloudmap zijn. Archiveren en Telescope gebruiken dezelfde instelling.

- `<leader>pa` / `:PubbleArchief`: zoeken op artikelbestand;
- `<leader>ps` / `:PubbleArchiefZoek`: zoeken door alle artikelinhoud.

---

## Achtergrondtaken en pending_jobs

`<leader>ar` kan meerdere AI-aanroepen tegelijk starten. De teller
`vim.b[buf].pending_jobs` registreert alle bufferwijzigende AI-taken centraal.
Druk je tijdens zo'n taak op `<leader>aw`, dan wordt één verzendverzoek onthouden;
de laatste taak start het direct na haar bufferwijziging. Er is geen
driesecondenpoll meer. Controlecodes worden gestript zodra de bijbehorende taak
klaar is.

---

## Rubriek-templates (`<leader>kt`)

Gedefinieerd in `~/.config/nvim/lua/krant.lua` als `M.templates`. Elk template heeft:
- `name` — weergavenaam in het menu
- `text` — template-inhoud met `{{titel}}`, `{{body}}` etc.
- `no_export` — bij `true`: geen lezersnieuws-export, wel `prio: 1` bovenaan

De 112-disclaimer in het 112-template is de enige bron — `ai_text.lua` leest hem via `require("krant").templates`.

---

## Bestanden

| Bestand | Inhoud |
|---|---|
| `lua/ai_text.lua` | Alle leaders, AI-aanroepen, 112/kalender-detectie, pubble-send |
| `lua/krant.lua` | Rubriek-templates (`<leader>kt`), `apply_template_by_name()` |
| `lua/pubble_archive.lua` | Telescope-zoekingangen voor bestandsnaam en archiefinhoud |

---

## Installatie

Vereist: [texttools](https://github.com/Wet-Senker/texttools) geïnstalleerd in `~/workspace/texttools/.venv/`.

```bash
cd ~/.config/nvim
git pull
```

Symlink voor Raadspraat-foto's:
```bash
ln -s ~/Library/Mobile\ Documents/com~apple~CloudDocs/krant-fotos ~/krant-fotos
```

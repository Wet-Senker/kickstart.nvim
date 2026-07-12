# kickstart.nvim — Brugmedia redactie

Neovim-configuratie voor de redactionele workflow van Brugmedia. Artikelen worden geschreven in Neovim, via AI verwerkt, en via de Pubble API gepubliceerd.

Gekoppeld aan: [texttools](https://github.com/Wet-Senker/texttools) (Python-package voor AI, metadata en Pubble-API).

---

## Workflow

```
Clipboard → pastevim() → cleantext → Neovim (.md buffer op ~/Desktop/)

<leader>ar    Herschrijven naar krantenartikel (AI)
              ↳ start background jobs (metadata, kalender, Facebook) op basis van controlecodes
              ↳ detecteert 112 en kalender automatisch
<leader>am    Metadata genereren (krant + web)
<leader>ac    Kalendermetadata + ## Kalender sectie
<leader>ao    Opmaken (handmatig): spellcheck, tussenkopjes, lead bold, streamer
<leader>af    Facebook-post genereren → ## Facebook sectie
<leader>aw    Versturen naar Pubble — wacht op alle achtergrondtaken
```

---

## Leaders

| Leader | Actie |
|---|---|
| `<leader>ar` | Herschrijven naar krantenartikel (AI). Start background jobs voor metadata, kalender en/of Facebook op basis van controlecodes. Detecteert 112 en agendaberichten automatisch. |
| `<leader>am` | Metadata genereren (krant + web). |
| `<leader>ac` | Kalendermetadata + bewerkbare `## Kalender` sectie. |
| `<leader>ao` | Opmaken (handmatig): spellcheck, cleanup, tussenkopjes, lead bold, streamer, eindredactie-oordeel. |
| `<leader>af` | Facebook-post genereren → bewerkbare `## Facebook` sectie. Bij 112-detectie: zakelijke prompt (één feitelijke zin). |
| `<leader>aw` | Versturen naar Pubble (krant + web + kalender + Facebook). Wacht automatisch tot alle achtergrondtaken klaar zijn. |
| `<leader>ap` | Ad-hoc herschrijven — typ `***` + instructie, buffer wordt vervangen. |
| `<leader>ag` | AI gesprek — typ `***` + vraag, antwoord verschijnt eronder. |
| `<leader>ah` | Cheatsheet: editie/prio/bijschrift/foto codes invoegen. |
| `<leader>ak` | Verdachte tekens scannen — markeert U+FFFD en control chars rood. |
| `<leader>kt` | Rubriektemplate invoegen (Raadspraat, 112, Hondenhoek, etc.). |

---

## Controlecodes

Bovenaan het artikel typen, vóór de kop, gevolgd door een lege regel:

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
```

---

## Automatische detectie bij import

Bij het openen van een `.md`-bestand op `~/Desktop/`:

**112-detectie** — scoort tekst op signaalwoorden (politie, brandweer, ambulance, incident, etc.). Bij score ≥ 6 verschijnt een bevestigingsvraag. Bij "Ja": 112-template toegepast, `rubriek: 112` en `prio: 1` bovenaan gezet.

**Kalenderdetectie** — scoort tekst op datum/tijd/deelname-signalen. Bij score ≥ 8: `articlemeta --calendar` gestart en `## Kalender` sectie toegevoegd (geen bevestiging nodig).

Beide checks lopen ook na `<leader>ar` op de herschreven tekst.

---

## 112-berichten

- Template: `112 KAMPEN: <titel>` + body + disclaimer
- `rubriek: 112` → `articleCategoryId: 24` in Pubble
- `<leader>af` gebruikt zakelijke Facebook-prompt (één zin, geen interactie)
- `<leader>ar` op een al opgemaakte 112-buffer: herschrijft alleen titel en body, laat prefix en disclaimer intact

---

## Achtergrondtaken en pending_jobs

`<leader>ar` start meerdere AI-aanroepen tegelijk. De teller `vim.b[buf].pending_jobs` houdt bij hoeveel taken nog lopen. `<leader>aw` retried elke 3 seconden zolang `pending_jobs > 0`. Controlecodes worden gestript zodra de bijbehorende taak klaar is.

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

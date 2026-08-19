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
| `<leader>ac` | Kalendermetadata + bewerkbare `## Kalender` sectie. |
| `<leader>ao` | Tekstcheck: objectieve correcties en twijfelgevallen onder `## Suggesties`. |
| `<leader>at` | Tussenkopjes en, als er nog geen eigen `>` staat, een streamer. |
| `<leader>af` | Facebook-post genereren → bewerkbare `## Facebook` sectie. Bij 112-detectie: zakelijke prompt (één feitelijke zin). |
| `<leader>aw` | Versturen naar Pubble. Een incompleet agenda-item geeft de keuze om eerst aan te vullen of alleen web/print te plaatsen. Bij gekozen eventvervolgen toont de eerste druk de teksten; de tweede publiceert alles samen. |
| `<leader>ap` | Ad-hoc herschrijven — typ `***` + instructie, buffer wordt vervangen. |
| `<leader>ag` | AI gesprek — typ `***` + vraag, antwoord verschijnt eronder. |
| `<leader>ah` | Hiërarchisch hulpmenu: kies onder meer Edities, Rubrieken, Publicatieplanning, Acties of de volledige cheatsheet. |
| visueel `<leader>ai` | Herschrijf de selectie direct naar krantenstijl, zonder een eenkeuzemenu. |
| `<leader>kt` | Handmatig rubriektemplate kiezen, inclusief Raadspraat, Ondernemen in Kampen en Kamper Kiek. |
| `<leader>kp` | Rubriekplanning: reminders en planningsoverzichten voor Raadspraat en Ondernemen in Kampen. |
| `<leader>aq` | Annuleer alle actieve editor-AI-taken van de huidige buffer. |
| `:AICancel` | Zelfde expliciete annulering als `<leader>aq`. |

In hiërarchische keuzemenu's staan acties eerst en staat `← Terug naar …`
altijd onderaan. Escape sluit de volledige workflow. Korte persoon- en
fotokeuzes gebruiken alleen Escape om de wizard te annuleren.

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

Als `<leader>ar` een letterlijke fotocredit of een bijschrift uit de brontekst
haalt, verplaatst de nabewerking zowel `Foto:` als `Bijschrift:` automatisch
naar dit beschermde blok boven `=== ARTIKEL ===`; ze blijven nooit in de
artikelbody staan.

---

## Automatische detectie bij import

Bij het openen van een `.md`-bestand op `~/Desktop/`:

**112-detectie** — scoort tekst op signaalwoorden (politie, brandweer, ambulance, incident, etc.). Bij score ≥ 6 verschijnt een bevestigingsvraag. Bij "Ja": 112-template toegepast, `rubriek: 112` en `prio: 1` bovenaan gezet. Bij "Nee" blijft die keuze voor de huidige buffer staan en mag detectie na `<leader>ar` het template niet alsnog toepassen. De kop gebruikt via `pubble-places` de eerste bekende plaats uit de centrale verspreidingsgebiedentabel; zonder treffer wordt het `112:`.

**Kalenderdetectie** — scoort tekst op datum/tijd/deelname-signalen. Bij score ≥ 8: `articlemeta --calendar` gestart en `## Kalender` sectie toegevoegd (geen bevestiging nodig).

Beide checks lopen ook na `<leader>ar` op de herschreven tekst. 112 vraagt daar
alleen opnieuw om bevestiging als bij import nog geen keuze is gemaakt.

**Andere rubrieken worden niet automatisch herkend.** Raadspraat, Ondernemen
in Kampen, Kamper Kiek en alle overige vaste rubrieken zijn een handmatige
redactionele keuze via `<leader>kt`. `<leader>kp` leest de artikeltekst niet;
het gebruikt alleen de rotatie- en planningsgegevens van Raadspraat en
Ondernemen. Namen, partijen en foto's worden pas na de gekozen rubriek uit
mappen en configuratie ingevuld.

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

Druk in normal mode op `<leader>aq` om de actieve `aitext`-, `aichat`-,
`articlemeta`- en AI-eventtekstprocessen voor alleen de huidige buffer te stoppen. Late resultaten
worden genegeerd, `pending_jobs` loopt terug naar nul en een wachtende verzending
wordt ingetrokken. Pubble-publicaties, uploads en archivering zijn bewust niet
annuleerbaar met `<leader>aq`, omdat daar extern al state kan zijn geschreven.
Escape behoudt overal zijn normale Vim-gedrag.

De melding na het voorbereiden van evenementvervolgen en de uiteindelijke
verzendsamenvatting verschijnen als tijdelijke, niet-blokkerende notificatie.
Je hoeft ze niet met Enter te sluiten en kunt meteen verder typen of opnieuw
`<leader>aw` gebruiken.

Na een geslaagde publicatie opent de Pubble-pagina in de standaardbrowser. De
verzendflow onthoudt eerst welk macOS-programma vooraan staat en activeert dat
na het openen opnieuw, zodat de browser NeoVim niet blijvend uit focus haalt.

---

## Rubriek-templates (`<leader>kt`)

Gedefinieerd in `~/.config/nvim/lua/krant.lua`. De gewone templates staan in
`M.templates`. Raadspraat, Ondernemen in Kampen en Kamper Kiek staan bovenaan
hetzelfde menu. De eerste twee gebruiken een dynamische flow voor persoon,
foto, bijschrift en template; Kamper Kiek gebruikt de ene foto uit Pubble
Inbox. Het menu wordt altijd handmatig geopend: deze rubrieken worden niet uit
de artikeltekst geclassificeerd.

Alle vormgevingsrubrieken gebruiken dezelfde tweestapsflow:

1. `<leader>kt` vult het template in, kopieert de gekozen foto naar Pubble
   Inbox en de juiste weekmap, en registreert het exportdoel. Er wordt nog geen
   `.txt`-bestand gemaakt.
2. Na controle publiceert `<leader>aw` de actuele buffer en schrijft bij succes
   precies één definitieve vormgevingstekst. Raadspraat en Kamper Kiek gaan
   alleen naar `gemeentenieuws`, Ondernemen naar `ondernemen_in_kampen` en
   stockrubrieken naar `lezersnieuws`.

Voor Raadspraat, Ondernemen en stockrubrieken moet Pubble Inbox vooraf leeg
zijn; Kamper Kiek verwacht daar juist exact één Kiek-foto. Zo kan nooit stil een
oude of tweede foto worden gekoppeld.

De bestaande eerste tekstregel vult zowel `{{titel}}` als het historische
`{{title}}`. Andere zichtbare `{{velden}}` blokkeren `<leader>aw` totdat ze zijn
ingevuld. Een mislukte publicatie of export bewaart het plan voor een veilige
nieuwe poging.

Een gewoon template heeft:

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
| `lua/layout_export.lua` | uniform exportplan, placeholdercontrole en definitieve vormgevingstekst |
| `plugin/column_reminders.lua` | Rubriekplanning (`<leader>kp`): reminders en overzichten |
| `lua/pubble_archive.lua` | Telescope-zoekingangen voor bestandsnaam en archiefinhoud |
| `lua/texttools_paths.lua` | Gedeeld, configureerbaar pad naar de Pubble Inbox |
| `lua/texttools_commands.lua` | Gedeelde, via `TEXTTOOLS_ROOT` configureerbare paden naar texttools-CLI's |
| `lua/texttools_socket.lua` | Veilige vaste serversocket met stale-socketherstel en race-guard |

---

## Installatie

Vereist: [texttools](https://github.com/Wet-Senker/texttools) geïnstalleerd in
`~/workspace/texttools/.venv/`. Alleen bij een afwijkende checkout stel je
`TEXTTOOLS_ROOT` in; alle Lua-modules gebruiken daarna dezelfde root. De vaste
serversocket is standaard `~/.cache/nvim/main.sock` en kan voor een geïsoleerde
test of afwijkende inrichting via `TEXTTOOLS_NVIM_SOCKET` worden veranderd.

```bash
cd ~/.config/nvim
git pull
```

Symlink voor Raadspraat-foto's:
```bash
ln -s ~/Library/Mobile\ Documents/com~apple~CloudDocs/krant-fotos ~/krant-fotos
```

De Pubble Inbox staat in iCloud en wordt via een vast lokaal pad gevonden:
```bash
mkdir -p ~/.texttools
ln -s ~/Library/Mobile\ Documents/com~apple~CloudDocs/texttools/Pubble\ Inbox ~/.texttools/pubble-inbox
```

Alle workflows gebruiken standaard `~/.texttools/pubble-inbox`. Alleen voor
een bewust afwijkende inrichting stel je `TEXTTOOLS_INBOX_DIR` in. Het volledige
stappenplan staat in `INSTALLATIE_NIEUWE_MAC.md` in de texttools-repository.

---

## Tests en CI

De configuratie richt zich op Neovim 0.12.3. De headless regressietests draaien
zonder persoonlijke configuratie of plugininstallatie:

```bash
cd ~/.config/nvim
bash tests/run_headless.sh
```

GitHub Actions voert dezelfde suite uit bij iedere push naar `master` en bij
iedere pull request. De tests dekken belangrijke pure logica en contracten;
interactieve menu's, externe API's en de volledige publicatieflow blijven
handmatige integratietests.

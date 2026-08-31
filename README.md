# kickstart.nvim — Brugmedia redactie

Neovim-configuratie voor de redactionele workflow van Brugmedia. Artikelen worden geschreven in Neovim, via AI verwerkt, en via de Pubble API gepubliceerd.

Gekoppeld aan: [texttools](https://github.com/Wet-Senker/texttools) (Python-package voor AI, metadata en Pubble-API).

---

## Workflow

```
Clipboard → pastevim() → `Pubble Inbox/werk` → cleantext → `=== ARTIKEL ===` + tekst → Neovim

<leader>ar    Herschrijven naar krantenartikel (AI)
              ↳ start background jobs (metadata, kalender, Facebook) op basis van controlecodes
              ↳ detecteert 112 en kalender automatisch
<leader>ac    Kalendermetadata + ## Kalender sectie
<leader>ao    Tekstcheck: spelling/grammatica + ## Suggesties
<leader>an    Journalistiek neutraliseren met minimale wijzigingen
<leader>at    Tussenkopjes + optionele streamer + 2 kopopties
<leader>af    Facebook-post genereren → ## Facebook sectie
<leader>aV    Krantversies en reviewstatus openen
<leader>aG    Huidige krantversie opslaan en goedkeuren
<leader>aw    Versturen — waarschuwt bij een vrijwel onbewerkte import
              bij agendapagina: krant kiezen, controleren en print-only versturen
<leader>ka    Ruwe papieren agendapagina voorbereiden voor tekstcontrole
```

---

## Leaders

| Leader | Actie |
|---|---|
| `<leader>ar` | Herschrijven naar krantenartikel (AI). Vraagt bij meerdere gekozen edities of aparte krantversies gewenst zijn. Start background jobs voor metadata, kalender en/of Facebook op basis van controlecodes. Detecteert 112 en agendaberichten automatisch. |
| `<leader>ac` | Kalendermetadata + bewerkbare `## Kalender` sectie. Een herkend maar onvolledig item toont `<!-- Ontbreekt: … -->` inclusief invoerformaat, bijvoorbeeld `Tijd: HH:MM`. |
| `<leader>ao` | Tekstcheck: objectieve correcties en twijfelgevallen onder `## Suggesties`. |
| `<leader>an` | Journalistiek neutraliseren: verwijdert alleen subjectieve journalistentaal; feiten, structuur en bestaande citaten blijven behouden. |
| `<leader>at` | Tussenkopjes, een streamer (als er nog geen eigen `>` staat) en twee kopopties die de streamer aanvullen. |
| `<leader>af` | Facebook-post genereren → bewerkbare `## Facebook` sectie. Bij 112-detectie: zakelijke prompt (één feitelijke zin). |
| `<leader>aV` / `:Krantversies` | Overzicht van de gedeelde bron en alle afzonderlijke krantversiebuffers openen. |
| `<leader>aG` / `:KrantversieGoedkeuren` | Huidige krantversie terugschrijven en de exacte tekst expliciet goedkeuren. |
| `<leader>aw` | Versturen naar Pubble. Bij een import vraagt een extra safeguard om bevestiging wanneer geen volledige AI-rewrite is voltooid óf de body nog nauwelijks afwijkt. Een incompleet agenda-item geeft de keuze om eerst aan te vullen of alleen web/print te plaatsen. Bij gekozen eventvervolgen toont de eerste druk de teksten; de tweede publiceert alles samen. |
| `<leader>ap` | Ad-hoc herschrijven — typ `***` + instructie, buffer wordt vervangen. |
| `<leader>ag` | AI gesprek — typ `***` + vraag, antwoord verschijnt eronder. |
| `<leader>ah` | Hiërarchisch hulpmenu: kies onder meer Edities, Rubrieken, Publicatieplanning, Acties of de volledige cheatsheet. |
| visueel `<leader>ai` | Herschrijf de selectie direct naar krantenstijl, zonder een eenkeuzemenu. |
| `<leader>kt` | Handmatig rubriektemplate kiezen, inclusief Raadspraat, Ondernemen in Kampen en Kamper Kiek. |
| `<leader>kp` | Rubriekplanning: reminders en planningsoverzichten voor Raadspraat en Ondernemen in Kampen. |
| `<leader>ka` | Ruwe papieren agendapagina structureren en gewone items redigeren; daarna zelf de tekst controleren. |
| `<leader>aq` | Annuleer alle actieve editor-AI-taken van de huidige buffer. |
| `:AICancel` | Zelfde expliciete annulering als `<leader>aq`. |

In hiërarchische keuzemenu's staan acties eerst en staat `← Terug naar …`
altijd onderaan. Escape sluit de volledige workflow. Korte persoon- en
fotokeuzes gebruiken alleen Escape om de wizard te annuleren.

De extra waarschuwing voor een vrijwel onbewerkte import vraagt
`Toch publiceren?`: druk `j` voor ja of `n` voor nee. Nee is de veilige
standaard.

`<leader>an` is bedoeld voor een tekst die al goed is opgebouwd en alleen nog
subjectieve, promotionele of overdreven opmerkingen van de journalist bevat.
De AI maakt de kleinst mogelijke ingreep. Alleen een expliciet aan een bron
gekoppelde claim mag indirect worden toegeschreven; er worden nooit nieuwe
directe citaten gemaakt. Verandering van bestaande citaten, getallen, datums,
tijden, URL's of mailadressen wordt technisch geweigerd. Een geslaagde controle
geldt bij verzending alleen voor de exact gecontroleerde body. Bewerk je de
buffer terwijl de AI draait, dan wordt het late resultaat niet toegepast.

Voor een complete papieren agendapagina plak je alle dagen en activiteiten en
gebruik je eenmaal `<leader>ka`. Gewone items worden per activiteit geredigeerd;
`>>>titel<<<` en de bijbehorende premiumbody worden nooit herschreven. Alleen
ontbrekende datum, tijd of locatie mag AI als metadata uitlezen. Controleer de
zichtbare datum, titel, tijd, locatie en body (`hele dag` mag). Voor de
printbody geldt geen technische lengtegrens; gewone tekst wordt wel compact
geredigeerd. Gewone koppen worden zoveel mogelijk 3–4 woorden en zijn maximaal 5
woorden. Een betrouwbaar herkend los slotblok wordt automatisch als complete
activiteit opgebouwd en onder zijn primaire datum gezet. Een volledig gewoon
item met een ondubbelzinnige andere primaire datum verhuist ook; secundaire
data in de body niet. Alles blijft zichtbaar ter controle. Druk daarna
`<leader>aw`. Kies dan de krant; de technische controle
draait automatisch vóór de print-only verzending. Dit maakt uitsluitend het
printconcept `!agendapagina`; `ONTBREEKT` blokkeert verzending. Losse controle
en blokpreview blijven alleen als technische `:AgendaPagina…`-opdrachten beschikbaar.
Sterk gelijkende items op dezelfde dag verschijnen vóór verzending als
mogelijke doublures; kies na controle `Toch verzenden` of veilig `Annuleren`.
Na de gecontroleerde Pubble-opslag verschijnt de directe krantartikellink in
de melding en bovenin de agendapagina. Een bestaand artikel-ID zonder die link
wordt door `<leader>aw` veilig hersteld in plaats van opnieuw aangemaakt.

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

Bij het openen van een `.md`-bestand in `~/.texttools/pubble-inbox/werk/`:

Eén centrale, lokale herkenningsmodule leest de tekst eenmaal. Rubriek- en
kalenderdetectors doen alleen snelle patrooncontroles. De editiedetector vraagt
daarnaast asynchroon de centrale Python-resolver om de verspreidingskennis,
zodat die tabel niet ook in Lua hoeft te staan. Dit gebruikt geen AI of netwerk
en blokkeert de editor niet. Iedere detector levert concrete aanwijzingen op;
de workflow bepaalt daarna of er automatisch iets mag gebeuren of eerst
bevestiging nodig is.

Direct op `~/Desktop/` geopende Markdown blijft als legacy-import ondersteund.
Nieuwe `pv`-bestanden komen niet meer op het bureaublad.
De herkenning werkt zowel via het lokale Inbox-symlinkpad als via het echte
iCloud-pad waarnaar NeoVim dat pad bij `--remote` kan omzetten. Daarmee starten
agenda, editie, 112, rubrieken en de verzendsafeguard altijd via dezelfde
centrale importketen.

**Editiedetectie** — een bestaande `e:`/`editie:`-regel blijft altijd staan.
Zonder zo'n regel wordt een betrouwbare dateline direct ingevuld. Een exacte
provincienaam is eveneens betrouwbaar wanneer zij vroeg in het artikel staat
of meermaals voorkomt: `Overijssel` wordt `e: B, SW, ST, K`, `Flevoland` wordt
`e: D, Z`. De importcontrole draait eenmaal per buffer. Na `<leader>ar` volgt
een hercontrole. Een bestaande `e:` blijft zonder vraag leidend wanneer de
betrouwbare plaats-/regiodetectie vóór en na de rewrite gelijk is. Alleen als
de rewrite die detectie verandert, beslis je zelf welke bestemming blijft. Bij
`<leader>aw` wordt alleen gevraagd om de bestemming te bevestigen wanneer nog
geen expliciete `e:` bestaat. Na Ja wordt de regel in de buffer gezet, zodat de
vraag niet terugkomt.

Heeft de definitieve `e:` meer dan één gekozen krant, dan vraagt `<leader>ar`
of iedere krant een eigen versie moet krijgen. **Nee** behoudt één gezamenlijke
tekst. **Ja** start één veilige AI-call per editie. Iedere editie krijgt een
volledige, gelijkwaardige versie en een eigen buffer. De gewone body blijft de
gedeelde bron en wordt niet gepubliceerd. Een lokaal bronfeit mag de kop,
intro en artikelopbouw bepalen; zonder lokale haak gebruikt de versie een
eerlijke regionale invalshoek zonder plaatselijke cijfers te verzinnen.

Sla een versie op met `:w`; zij blijft dan `controleren`. Keur exact die tekst
goed met `<leader>aG`. `<leader>aV` toont de bron en alle statussen. Een edit na
goedkeuring trekt alleen die goedkeuring in. Een edit in de gedeelde bron maakt
alle varianten `verouderd` en vereist nieuwe generatie.

`<leader>aw` controleert dat iedere gekozen krant exact één geldige versie
heeft én dat alle versies na de laatste bronwijziging expliciet zijn
goedgekeurd. Voor print en web gaat alleen de passende tekst mee. Bij een
ontbrekende, dubbele, verouderde, niet-goedgekeurde of verkeerde code stopt de
verzending vóór Pubble. Staat er geen `## Editieversies`, dan blijft de
gezamenlijke tekst voor alle kranten gelden.

**112-detectie** — scoort tekst op signaalwoorden (politie, brandweer, ambulance, incident, etc.). De combinatie van minimaal één hulpdienst en één concreet incident krijgt één extra punt. Bij score ≥ 6 verschijnt een bevestigingsvraag. Bij "Ja": 112-template toegepast, `rubriek: 112` en `prio: 1` bovenaan gezet. Bij "Nee" blijft die keuze voor de huidige buffer staan en mag detectie na `<leader>ar` het template niet alsnog toepassen. De kop gebruikt via `pubble-places` de eerste bekende plaats uit de centrale verspreidingsgebiedentabel; zonder treffer wordt het `112:`.

**Kalenderdetectie** — scoort tekst op datum/tijd/deelname-signalen. Bij score ≥ 8: `articlemeta --calendar` gestart en `## Kalender` sectie toegevoegd (geen bevestiging nodig).

**Kamper-Kiekdetectie** — de letterlijke rubrieknaam levert 70 punten op en de
opeenvolgende nummers 1, 2 en 3 ieder 10. Alleen de ondubbelzinnige score 100
past de Kamper-Kiekflow automatisch toe. Die flow verwacht exact één foto in
Pubble Inbox. Ontbreekt die of staan er meerdere, dan blijft het artikel
ongewijzigd en meldt Neovim welke handeling nog nodig is. Een gedeeltelijke
match wordt via een keuzemenu voorgelegd; een gewone genummerde lijst zonder
`Kamper Kiek` scoort nul.

**Hondenhoekdetectie** — `Bert Nieuwenhuis` en een zelfstandig woord
`hond`/`honden` leveren samen score 100 op. `Hondenhoek` is eveneens een sterk
signaal en bereikt met de auteur of het hondenwoord score 100. Eén sterk
signaal zonder tweede aanwijzing opent alleen een bevestigingsmenu. Bij score
100 wordt de vaste Hondenhoek-template met stockfoto automatisch toegepast;
Pubble Inbox moet daarvoor leeg zijn. Een losse aangeleverde regel
`Hondenhoek:` wordt verwijderd, maar body en auteursregel blijven ongewijzigd.

Kalender en 112 worden ook na `<leader>ar` op de herschreven tekst beoordeeld. 112 vraagt daar
alleen opnieuw om bevestiging als bij import nog geen keuze is gemaakt.

**Andere vaste rubrieken worden niet automatisch herkend.** Raadspraat,
Ondernemen in Kampen en alle hierboven niet genoemde vaste rubrieken zijn een handmatige
redactionele keuze via `<leader>kt`. Wanneer toekomstige detectors minder dan
volledige zekerheid geven of elkaar tegenspreken, volgt eveneens een
keuzemenu; er wordt dan nooit stil een template toegepast. `<leader>kp` leest de artikeltekst niet;
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

Handmatige `pv`-artikelen staan tijdens het werk in
`~/.texttools/pubble-inbox/werk/`; `pubble-batch/` blijft uitsluitend voor de
batchroute. Na volledige publicatie wordt het werkbestand verwijderd en wordt
de zichtbare tekst een niet-schrijfbare `pubble-nacontrole://`-buffer. Daardoor
kan `:w` of `:wq` de verwijderde bron niet opnieuw aanmaken. Een mislukte
verwijdering geeft een expliciete waarschuwing met het achtergebleven pad.

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
Inbox. Raadspraat en Ondernemen worden niet automatisch geclassificeerd.
Kamper Kiek kan behalve via dit handmatige menu ook automatisch worden
toegepast wanneer de importherkenning de vaste naam plus nummering 1–3 vindt.
Hondenhoek kan automatisch worden toegepast bij twee sterke tekstsignalen en
gebruikt dan dezelfde stockrubriekflow als de handmatige keuze.

Alle vormgevingsrubrieken gebruiken dezelfde tweestapsflow:

1. Automatische zekere herkenning of `<leader>kt` vult het template in, kopieert de gekozen foto naar Pubble
   Inbox en de juiste weekmap, en registreert het exportdoel. Er wordt nog geen
   `.txt`-bestand gemaakt.
2. Na controle publiceert `<leader>aw` de actuele buffer en schrijft bij succes
   precies één definitieve vormgevingstekst. Raadspraat en Kamper Kiek gaan
   alleen naar `gemeentenieuws`, Ondernemen naar `ondernemen_in_kampen` en
   stockrubrieken naar `lezersnieuws`.

Voor Raadspraat, Ondernemen en stockrubrieken moet Pubble Inbox vooraf leeg
zijn; Kamper Kiek verwacht daar juist exact één Kiek-foto. Zo kan nooit stil een
oude of tweede foto worden gekoppeld.

Kamper Kiek mag rechtstreeks in de gebruikelijke aangeleverde vorm worden
geplakt: `De Kamper kiek op de wîêk: 1). ... 2). ...`. De speciale flow
verwijdert die aangeleverde rubriekkop, zet de vaste kop en intro erboven en
normaliseert ieder genummerd onderdeel naar een eigen regel (`1.`, `2.`,
enzovoort). De tekst van de onderdelen zelf blijft ongewijzigd.

Hondenhoek wordt doorgaans als lopende tekst met `Bert Nieuwenhuis.` onderaan
aangeleverd. De template behoudt de volledige eerste alinea en auteursregel.
Alleen een losse dubbele kop `Hondenhoek:` verdwijnt. De vaste
`hondenhoek.jpg` wordt uit de stockfotomap naar Pubble Inbox en de weekmap
gekopieerd.

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
| `lua/article_recognition.lua` | Deterministische scores, bewijsregels en beslisbeleid voor importherkenning |
| `lua/ai_text.lua` | Hoofdflow, herkenningsacties, AI-aanroepen en pubble-send |
| `lua/edition_review.lua` | Dunne NeoVim-client voor losse krantbuffers, synchronisatie en goedkeuring via het Python-contract |
| `lua/krant.lua` | Rubriek-templates (`<leader>kt`), `apply_template_by_name()` |
| `lua/layout_export.lua` | uniform exportplan, placeholdercontrole en definitieve vormgevingstekst |
| `lua/agenda_page.lua` | papieren agendapagina voorbereiden, controleren, previewen en versturen (`<leader>ka`) |
| `plugin/agenda_page.lua` | laadt de afzonderlijke agendapagina-UI |
| `plugin/column_reminders.lua` | Rubriekplanning (`<leader>kp`): reminders en overzichten |
| `lua/pubble_archive.lua` | Telescope-zoekingangen voor bestandsnaam en archiefinhoud |
| `lua/texttools_paths.lua` | Gedeelde, configureerbare paden naar de Pubble Inbox en handmatige werkmap |
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

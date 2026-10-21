# Texttools cheatsheet

## Twee workflows

### 1. Neovim → Pubble (één artikel)

```
Clipboard/bron kopiëren
→ Keyboard Maestro trigger → pastevim() → `Pubble Inbox/werk` → cleantext → opent in Neovim

In Neovim:
  Controlecodes bovenaan typen (zie hieronder)
  <leader>ar    herschrijven; start metadata en gevraagde extra's
  <leader>ad    doublurecontrole opnieuw draaien
  <leader>aa    eerder geschreven over dit onderwerp; <leader>as maakt de achtergrond
  <leader>ac    kalenderdata; onvolledige items tonen wat nog ontbreekt
  <leader>an    kop/lead waar nodig herstellen; rest minimaal neutraliseren
  <leader>af    Facebook-post genereren — verschijnt als ## Facebook sectie
  <leader>al    LinkedIn-post genereren — verschijnt als ## LinkedIn sectie
  <leader>aV    overzicht van bron en losse krantversiebuffers
  <leader>aG    huidige krantversie opslaan en goedkeuren
  <leader>aK    schone Kopie-buffer; e: aanpassen, daarna <leader>ar
  <leader>aw    importcontrole, planning, doublures en versturen
                ↳ zo nodig eerst kranttijd-/vervolgteksten controleren
  <leader>kd    actieve webartikelen per site op doublures controleren
  <leader>kl    activiteitenstrook onder de tekst tonen/sluiten
  :TexttoolsActiviteit! compact/uitgebreid; in paneel e/a/l/q
  :TexttoolsLog veilige tijdlijn met duur en uitkomst per hoofdhandeling
```

Na volledig succes verhuist het artikel naar `Pubble Archief`; het werkbestand
verdwijnt en de open tekst wordt een niet-schrijfbare nacontrolebuffer.
Uitzondering: nieuwere edits tijdens de publicatie blijven bewerkbaar en zijn
niet meegepubliceerd. `<leader>aw` opent dan alleen de gepubliceerde versie
ter vergelijking; opnieuw plaatsen is ook na heropenen geblokkeerd.
Een herstelverwijzing wordt nu vóór verzending bewaard. Verwijder die niet:
na een gesloten buffer of fout leidt `aw` naar dezelfde Pubble-status. Kan de
verwijzing niet worden opgeslagen, dan start de verzending niet.

Lopende taken staan in ondoorzichtige Fidget-meldingen met dezelfde bewegende
stippen vóór iedere taak, maximaal vijf tegelijk. Bevestigde uitkomsten blijven acht seconden staan:
`✓ Artikel herschreven`, `✗ Herschrijven mislukt` of `– Herschrijven niet toegepast`.
Alleen daadwerkelijk toegepast succes krijgt een vinkje. Een technische procesexit
zonder bevestiging krijgt geen aparte voltooiingsmelding; de diagnose blijft in het log.
Aandacht en de gebruikte redigeermethode staan als echte `Melding:`-regels boven het artikel:
alle artikelgegevens bij elkaar, dan een witregel, de meldingen en nog een witregel vóór het artikel.
Selecteer/kopieer normaal, verwijder met `dd`. Ze staan in werkbestand en undo,
maar nooit in AI-invoer of publicatie. Verwijderen heft geen controle op.
`<leader>kl` opent de historie; daar krijgen bevestigde resultaten `OK:`, ook
na een controle zonder treffers. Mogelijke doublures krijgen geen OK.
`<C-j>` naar het geopende paneel, `e` voor alle
meldingen (nogmaals voor compact), `l` voor technische diagnose en `q` om echt
te sluiten, ook tijdens werk. De taakmeldingen blijven onafhankelijk zichtbaar;
de statusbalk en de logboekkop herhalen geen actieve taken.
De losse statusbalktekst `Aandacht nodig` is eveneens verwijderd; lees de
concrete melding boven de artikelgrens. Agenda-/Facebook-/LinkedIn-teksten die
zichtbaar zijn toegevoegd krijgen geen dubbele succesmelding boven het artikel.
Ontbrekende gegevens en fouten blijven zichtbaar, evenals de methode waarmee
de artikeltekst is bewerkt (`ar`: Persberichten bewerken, `an`: behoudend,
`ap`: eigen instructie).
`a` markeert de historie als gelezen; dat verwijdert geen meldingsregels.
Een geslaagde herhaling kan alleen de fout van dezelfde actie
opruimen. Een nieuwe fout opent de historie niet vanzelf. Webresultaten
onderscheiden concept, ingepland en online volgens Pubble; er is geen extra
publieke websitecheck. De historie opent na herstart alleen op afroep;
maximaal honderd sessiemeldingen per artikel, nooit in de publicatietekst.
Noodzakelijke beslissingen gebruiken de centrale menulaag. Workflowlijsten
hebben één native vormgeving, ook de voorheen losse ja/nee- en persoonskeuzes.
Escape/q stelt een verplichte overlay uit zonder te antwoorden. Hervatten kan
met `:TexttoolsVraag` of `v` in het logboek; selectie en invoer blijven bewaard.
In invoervelden wisselt Escape alleen naar Normal (ook bij herhalen).
Ctrl-C annuleert of stelt verplichte invoer uit; `<leader>aq` stopt expliciet AI.
Zie `NOTIFICATIES.md` voor de audit en de asynchrone bediening.

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

> Links openen altijd op de achtergrond: het tabblad staat klaar, maar de browser
> springt niet naar voren. Je werkt door in Neovim en kijkt wanneer het uitkomt.

## Neovim leaders

| Leader | Actie |
|---|---|
| `<leader>ar` | **Herschrijven** — zonder onderscheidende plaats/provincie stil één algemene versie. Anders keuze tussen de voorgestelde gerichte varianten + algemene rest, één algemene versie of Annuleren. De gebiedsscan doet alleen een voorstel. Direct uit het origineel met tussenkopjes, daarna losse streamer; iedere krant krijgt een eigen reviewbuffer, ook als de artikeltekst gelijk is |
| *bij `<leader>ar`* | **Plaatsencontrole** — noemt de tekst plaatsen van kranten die niet gekozen zijn, dan vraagt hij eenmalig of die mee moeten. Alleen als de controle bij import niet gedraaid heeft (zelf geplakte tekst) of als er sindsdien een krant is bijgekomen. Een provincie alleen telt niet mee |
| `<leader>ad` | **Doublurecontrole opnieuw** — draait de controle nog eens voor dit artikel, ook als je eerder "toch verzenden" koos. Wegdrukken met `q` laat hem vanzelf terugkomen; deze toets is voor de keer dat je hem al had goedgekeurd |
| *automatisch bij import* | **Agenda-doublurecontrole** — vóór automatisch voorbereiden. `o` opent de geselecteerde versie, `m` bewaart geen doublure voor dit paar, `v` bereidt bewust toch voor, `n` gaat door met bewerken zonder agenda, `q` sluit de keuze en laat bewerken doorgaan zonder automatische agenda. Uit te zetten met `TEXTTOOLS_AGENDA_DOUBLURECHECK=0` |
| `<leader>ao` | **Tekstcheck** — alleen taalfouten (spelling/grammatica); tekst blijft verder gelijk (twijfel → `## Suggesties`) |
| `<leader>an` | **Opschonen + neutraliseren** — eerst zekere persbericht-/mailruis als volledige regels weg, daarna reclame/'u'-taal eruit + kop/lead publicatieklaar; rest zo dicht mogelijk bij origineel |
| `<leader>ac` | Altijd een bewerkbaar kalenderwerkblok, ook na afwijzen/verwijderen en bij ontbrekende gegevens. Geen automatische doublurekeuze; wel controle vóór publicatie. Ontbrekende velden blijven leeg |
| `<leader>at` | Tussenkopjes, optionele streamer en 2 kopopties; gekozen kop wordt zo nodig vóór de lead ingevoegd |
| `<leader>af` | Facebook-post genereren — toont bewerkbare `## Facebook` sectie. Zijn er krantversies, dan vraagt hij op de bron of hij er voor iedere versie een maakt, elk uit de afgeronde tekst van die versie; in een krantbuffer alleen voor die versie |
| `<leader>al` | LinkedIn-post genereren — toont bewerkbare `## LinkedIn` sectie; in een krantreview alleen voor die krant |
| `<leader>aV` | Overzicht van bron en afzonderlijke krantversiebuffers |
| `<leader>aG` | Huidige krantversie opslaan en expliciet goedkeuren |
| `<leader>aw` | Publicatie voorbereiden; vangnet voor doublures en onbewerkte import; toont zo nodig eerst `## Kranttijdsversies` en eventvervolgen. Bij een verstreken krantdeadline: overlay met reden; `w` alleen web, `t` toch krant, `a`/Escape annuleren (ook 1–3 of `j`/`k` + Enter). Vanaf twee foto's krijgt de Pubble-kop `(n foto's)`, behalve bij 112 |
| `<leader>ax` | Vormgevingstekst + foto('s) naar het Bureaublad; een met `<leader>pf` gekozen Pubble-foto wordt als origineel gedownload, anders worden de losse Inbox-foto's gebruikt |
| `<leader>ap` | Ad-hoc herschrijven — typ `***` + instructie, buffer wordt vervangen |
| `<leader>ag` | AI gesprek — typ `***` + vraag, antwoord verschijnt eronder |
| `<leader>aa` | **Archiefzoeker** — eerder geschreven over dit onderwerp, uit het hele archief. Vijf per keer, per jaar gegroepeerd; nogmaals drukken geeft de volgende vijf |
| `<leader>as` | **Achtergrond** — in de archieflijst: vat samen wat je liet staan tot `## Achtergrond` onderaan je artikel; die gaat vóór verzending weer weg |
| `<leader>ah` | Hiërarchisch hulpmenu voor codes, rubrieken, acties en cheatsheet |
| `<leader>kh` | Contextuele workflowhulp — toont de actuele status, de aanbevolen volgende stap, andere hoofdopties en wat daarna gebeurt |
| `:TexttoolsLog` | Veilige tijdlijn voor het huidige artikel; `:TexttoolsLog!` toont de laatste workflow ongeacht de buffer |
| `<leader>kt` | Handmatig rubriektemplate kiezen, inclusief Raadspraat, Ondernemen en Kamper Kiek |
| `<leader>kp` | Rubriekplanning: reminders en planningsoverzichten |
| `<leader>ka` | Ruwe papieren agendapagina voorbereiden voor eigen tekstcontrole |
| `<leader>km` | Agendapagina opnieuw meten: alinea’s tegen richtgrens 166 en geschat aantal te verwijderen agendapunten. Zonder AI en zonder opslaan |
| `<leader>kr` | Rubriekscan (read-only): online webartikelen die waarschijnlijk onder een rubriek vallen maar niet in die categorie staan. In het scherm: `Enter` details, `o` in browser (handmatig corrigeren), `m` afgehandeld, `r` afgehandelde tonen/verbergen, `q` sluiten |
| `<leader>kd` | Alle kranten of één krant intern controleren op actieve webdoublures (nooit kruislings). Geen automatische tabbladen. `Enter`: artikel in nvim; `o`: alle artikelen van deze doubluregroep, ook drie of meer; `m`: geen doublure (dit paar); `r`: beoordeelde tonen/verbergen; `q`: sluiten. Andere groepen blijven dicht. Hetzelfde geldt voor **Eigen agendadoublures** in `<leader>kg`. |

---

## Automatisch of handmatig?

- **Automatisch uit de tekst:** kalenderdetectie, een ondubbelzinnige Kamper
  Kiek met vaste naam plus nummering 1–3, en Hondenhoek bij Bert Nieuwenhuis +
  hond/honden (of `Hondenhoek` + een tweede signaal). Kamper Kiek vereist exact
  één foto; voor Hondenhoek moet Pubble Inbox leeg zijn.
- **Altijd met bevestiging:** 112-detectie en een volledige persoonsnaam uit
  de fotomap van Raadspraat of Ondernemen in Kampen. Eén persoon geeft een
  gerichte ja/nee-vraag; meerdere personen of rubrieken staan in één menu. De
  template wordt nooit stil toegepast.
- **Niet automatisch uit de tekst herkend:** alle overige vaste rubrieken;
  kies die via `<leader>kt`.
- **`<leader>kp`:** leest de artikeltekst niet; toont alleen de planning voor
  Raadspraat en Ondernemen.
- Na bevestigde naamsherkenning wordt dezelfde `<leader>kt`-actie direct met
  de gevonden persoon uitgevoerd. Namen, partijen en foto's komen uit de
  actuele fotomappen of `personen.md`.

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
`>>>titel<<<` is premium: kop blijft exact; aparte behoudende AI-taalredactie
van de body, zonder samenvatten. Bestaande tijden, locaties en adressen blijven
intact. Alleen ontbrekende metadata mag worden aangevuld. `hele dag` mag;
de printbody heeft geen lengtegrens. Gewone koppen zijn bij
voorkeur 3–4 en maximaal 5 woorden; een
herkend los slotblok wordt automatisch een aparte activiteit onder zijn
primaire datum. Een duidelijk verkeerd geplaatst item verhuist mee, secundaire
data niet. Dit maakt alleen
het printconcept `!agendapagina`.
De omvangmelding verschijnt automatisch bij import en na voorbereiding. Na
verwijderen of aanpassen geeft `<leader>km` (`:AgendaPaginaOmvang`) een actuele
schatting: bijvoorbeeld “245/166 alinea’s, 60 agendapunten; verwijder nog ongeveer
20 agendapunten”. Het is globaal: datumkoppen en scheidingsblokken tellen mee,
maar teksthoogte niet. Er wordt niets vanzelf verwijderd.

Embargo: bij de eerste import van een tekst met het losse woord `embargo` zet
het programma automatisch een duidelijke `EMBARGO:`-regel boven
`=== ARTIKEL ===`. Zolang die regel staat kan `<leader>aw` niet verzenden.
Een expliciet moment komt daarnaast als `publicatiedatum:` boven de grens en
wordt bij `<leader>aw` voorgesteld; de letterlijke zin blijft als
`embargobron:` controleerbaar. Verwijder na vrijgave de blokkaderegel én de
oorspronkelijke embargozin uit het artikel. Laat `embargobron:` gerust staan.

De doublurecontrole volgt het beleid van de Texttools-branch. Op `master`
staat voorlopig **altijd controleren** aan. De testvarianten blijven beschikbaar:
`codex/doublure-altijd` controleert ieder artikel, ook alleen De Brug;
`codex/doublure-voorwaardelijk` zodra een andere krant is gekozen, ook alleen
De Kop. Onbevestigde `SUGGESTIE`-codes zijn geen gekozen edities.
De controle start na import/editieresolutie, anders na herschrijven, anders
vóór verzenden. Ongewijzigde tekst wordt niet opnieuw gecontroleerd; na een
inhoudswijziging wel. Kandidaten waarbij je met `v` doorging of die je met `m`
afzonderlijk beoordeelde worden in dezelfde buffer niet opnieuw voorgesteld.
`q` slaat geen nieuwe algemene toestemming op; eerdere afzonderlijke
beoordelingen blijven behouden. De controle doorzoekt altijd alle zes sites, vanaf veertien
dagen geleden en onbeperkt vooruit, ongeacht status.

Mogelijke doublures: het overzicht toont soort Agenda/Web, uitgelijnde Europese
datum en volledige kop, gegroepeerd per krant. Een nieuw agenda-item staat
eenmaal apart als vergelijking. Web en agenda komen samen in één overzicht;
vroeg `n` betekent meteen verder bewerken zonder agendabericht, zonder tweede
bevestiging en zonder publicatieakkoord. Bij definitief verzenden slaat `n`
alleen agenda over en blijven webtreffers nog te beoordelen. Bestaande controles blijven gelden zolang hun
invoer niet verandert. Nieuwe/herziene kalendergegevens kunnen aanvullende
treffers geven.
Enter/dubbelklik bekijkt de beschikbare tekst
en details in NVIM, zonder een besluit of browseractie. De onderste terugregel of `q`
keert terug naar het overzicht. `o` opent alleen de gekozen siteversie in
Pubble. `m` markeert één kandidaat als geen doublure; na de laatste volgt het
vervolg. `v` negeert bewust de hele lijst en gaat door (bij
import/herschrijven: bewerken; bij verzenden: toch verzenden). `q` annuleert
vanuit het overzicht; Escape neemt geen besluit. In het detail staan
publicatiedatum, aanmaakdatum en de persoon die het artikel aanmaakte.
`n` bij een artikel-agendacontrole: geen nieuwe agenda-items voor dit hele
artikel; web/krant gaan door en bestaande berichten worden niet verwijderd.
Bij import/herschrijven sluit `q` de agenda-keuze en laat bewerken doorgaan;
er wordt geen kalenderblok toegevoegd. `<leader>ac` kan dat alsnog expliciet doen.
Bij verzending stopt `q` alleen deze verzendpoging. `v` betekent dan bewust
toch publiceren; `n` verzendt alleen web/krant, zonder agenda.

---

## Controlecodes (bovenaan artikel typen, vóór de kop)

Werken via **Neovim** (`<leader>ar`/`<leader>aw`) én via **pubble-batch**:

```
editie: B          # of SW, ST, Z, D, K, all, overijssel, flevoland (fuzzy)
prio: 2            # 1=moet mee  2=mag mee  3=rest(standaard)  4=nood  (p: ook)
rubriek: sport     # categorie (fuzzy: sp/spo/sprt→sport). r: is alias
b: Bijschrift      # fotobijschrift
c: Naam fotograaf  # fotocredit
@John Boodschap    # alleen voor actuele Teams-ontvanger John
@B Boodschap       # naar wie op dat moment editie B (De Brug) beheert
@all Boodschap     # voor alle Teams-meldingen van dit artikel
@ Boodschap        # kale @ = alle ontvangers (gelijk aan @all)
```

- **Rubriek** (`rubriek:` of `r:`, fuzzy via unieke prefix of één typfout): algemeen, sport, politiek, financieel,
  ingezonden, verenigingen, cultuur, politie, toerisme, historie, gemeente, kerk,
  nieuws, zorg en welzijn, provincie, zakelijk, 112. Prefix mag (`spo`→sport);
  alleen bij twijfel (`politi` = Politiek óf Politie) een foutmelding.
- **Naam of editie**: `@Saskia` mikt op de persoon, een editie op wie díe krant
  nú beheert (handig als het wisselt van persoon). De editie mag fuzzy, net als
  de `e:`-regel: code (`@ST`), naam(prefix) (`@stad`, `@swol`, `@br`) of
  afkorting. Alleen bij twijfel (`@s` = Swollenaer óf Stadskoerier?) volgt een
  foutmelding.
- **Meerdere ontvangers**: op één regel met komma's (`@Joop, @Saskia Boodschap`)
  óf op losse regels boven de boodschap:
  ```
  @joop
  @B
  @Saskia Controleer de kop.
  ```
- Een kale `@` zonder naam of `all` gaat naar alle edities/ontvangers.
- Selectors zijn hoofdletterongevoelig, worden niet getoond en volgen eventuele
  waarneming uit `:TeamsRedactie`.

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

Agenda-item niet gewenst? Verwijder het hele blok vanaf `## Kalender`.
De voorbereiding wordt in het werkbestand onthouden: ook na heropenen maakt
`<leader>ar` een bewust verwijderd blok niet opnieuw. De volgende artikelactie
legt `agenda: nee` vast. `<leader>ac` overrulet deze keuze, maar een onvolledig
blok wordt niet gepubliceerd. Ontbrak het blok altijd en wordt
pas bij verzenden een sterke agendakandidaat gezien, dan volgt eerst een
ja/nee-vraag.

Alleen het gecontroleerde kalenderitem plaatsen? Druk `<leader>kA`. Deze route
maakt geen krant- of webartikel, verstuurt geen socialtekst of Teams-melding en
slaat het ontvangen agenda-ID direct in het artikel op.

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

Na `<leader>ar` met meerdere gekozen edities verschijnt alleen bij een
onderscheidend gebiedssignaal een keuze over de tekststrategie. Als er
krantversies worden gemaakt, blijft de gewone body de niet te publiceren bron
en krijgt iedere krant een eigen buffer — ook wanneer meerdere buffers eerst
dezelfde algemene artikeltekst bevatten. Maak in zo'n buffer met `<leader>af`
en `<leader>al` desgewenst de socialteksten voor precies die krant. Sla een edit
op met `:w`, keur haar goed met `<leader>aG` en gebruik `<leader>aV` voor het
overzicht. `<leader>aw` verstuurt daarna alle kranten in één keer met de
passende print-, web- en socialtekst. De foto wordt eenmaal geüpload en voor de
verschillende doelen hergebruikt. De socialteksten worden in Pubble opgeslagen;
ze worden niet automatisch op Facebook of LinkedIn gepubliceerd.

In de losse reviewbuffers toont `<leader>kh` steeds de actuele fase: gewijzigd,
alleen opgeslagen, goedgekeurd, verouderd of volledig verzendklaar. Op de
gedeelde bron legt dezelfde hulp uit hoeveel krantversies nog moeten
worden goedgekeurd en dat de bron zelf niet wordt gepubliceerd.

Bij kalenderartikelen én datumgebonden artikelen zonder kalenderblok bepaalt
`<leader>aw` per krant of het evenement op de eerstvolgende verschijningsdag
nog toekomstig, inmiddels lopend of afgelopen is. `agenda: nee` schakelt alleen
het agenda-item uit en niet deze controle. Bij verschil met de webdatum kies je
of er een `## Kranttijdsversies`-tekst komt of dat het artikel niet naar die
krant gaat. Controleer een gemaakte printtekst en druk opnieuw `<leader>aw`;
de webtekst blijft ongewijzigd.

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

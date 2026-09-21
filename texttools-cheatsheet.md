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
  <leader>aw    importcontrole, planning, doublures en versturen
                ↳ zo nodig eerst kranttijd-/vervolgteksten controleren
  <leader>kd    actieve webartikelen per site op doublures controleren
  :TexttoolsLog veilige tijdlijn met duur en uitkomst per hoofdhandeling
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

> Links openen altijd op de achtergrond: het tabblad staat klaar, maar de browser
> springt niet naar voren. Je werkt door in Neovim en kijkt wanneer het uitkomt.

## Neovim leaders

| Leader | Actie |
|---|---|
| `<leader>ar` | **Herschrijven** — zonder onderscheidende plaats/provincie stil één algemene versie. Anders keuze tussen de voorgestelde gerichte varianten + algemene rest, één algemene versie of Annuleren. De gebiedsscan doet alleen een voorstel. Direct uit het origineel met tussenkopjes, daarna losse streamer; iedere krant krijgt een eigen reviewbuffer, ook als de artikeltekst gelijk is |
| *bij `<leader>ar`* | **Plaatsencontrole** — noemt de tekst plaatsen van kranten die niet gekozen zijn, dan vraagt hij eenmalig of die mee moeten. Alleen als de controle bij import niet gedraaid heeft (zelf geplakte tekst) of als er sindsdien een krant is bijgekomen. Een provincie alleen telt niet mee |
| `<leader>ad` | **Doublurecontrole opnieuw** — draait de controle nog eens voor dit artikel, ook als je eerder "toch verzenden" koos. Wegdrukken met `q` laat hem vanzelf terugkomen; deze toets is voor de keer dat je hem al had goedgekeurd |
| *automatisch bij import* | **Agenda-doublurecontrole** — staat het evenement al in de eigen online agenda, dan volgt vóór elke verwerking de vraag of er tóch een agenda-item moet komen, met de optie het bestaande item in de browser te bekijken. Nee laat alleen het agenda-item vervallen; web en print gaan door. Uit te zetten met `TEXTTOOLS_AGENDA_DOUBLURECHECK=0` |
| `<leader>ao` | **Tekstcheck** — alleen taalfouten (spelling/grammatica); tekst blijft verder gelijk (twijfel → `## Suggesties`) |
| `<leader>an` | **Opschonen + neutraliseren** — eerst zekere persbericht-/mailruis als volledige regels weg, daarna reclame/'u'-taal eruit + kop/lead publicatieklaar; rest zo dicht mogelijk bij origineel |
| `<leader>ac` | Metadata + kalenderitem — ontbrekende velden tonen het formaat, zoals `Tijd: HH:MM` |
| `<leader>at` | Tussenkopjes, optionele streamer en 2 kopopties; gekozen kop wordt zo nodig vóór de lead ingevoegd |
| `<leader>af` | Facebook-post genereren — toont bewerkbare `## Facebook` sectie. Zijn er krantversies, dan vraagt hij op de bron of hij er voor iedere versie een maakt, elk uit de afgeronde tekst van die versie; in een krantbuffer alleen voor die versie |
| `<leader>al` | LinkedIn-post genereren — toont bewerkbare `## LinkedIn` sectie; in een krantreview alleen voor die krant |
| `<leader>aV` | Overzicht van bron en afzonderlijke krantversiebuffers |
| `<leader>aG` | Huidige krantversie opslaan en expliciet goedkeuren |
| `<leader>aw` | Publicatie voorbereiden; vangnet voor doublures en onbewerkte import; toont zo nodig eerst `## Kranttijdsversies` en eventvervolgen. Bij een verstreken krantdeadline: alleen web, expliciet toch krant, of annuleren. Vanaf twee foto's krijgt de Pubble-kop `(n foto's)`, behalve bij 112 |
| `<leader>ax` | Vormgevingstekst (FOTO/FOTOBIJSCHRIFT/STREAMER + vette intro) + foto('s) naar het Bureaublad; vraagt een bestandsnaam |
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
| `<leader>kr` | Rubriekscan (read-only): online webartikelen die waarschijnlijk onder een rubriek vallen maar niet in die categorie staan. In het scherm: `Enter` details, `o` in browser (handmatig corrigeren), `m` afgehandeld, `r` afgehandelde tonen/verbergen, `q` sluiten |
| `<leader>kd` | Alle kranten of één krant intern controleren op actieve webdoublures (nooit kruislings). Overzicht opent onder de buffer; in het scherm: `Enter` artikel in nvim, `o` in browser, `m` paar markeren (geen doublure), `r` gecontroleerde tonen/verbergen, `q` sluiten |

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
`>>>titel<<<` is premium: tekst blijft exact, AI mag alleen ontbrekende metadata
uitlezen. `hele dag` mag; de printbody heeft geen lengtegrens. Gewone koppen zijn bij
voorkeur 3–4 en maximaal 5 woorden; een
herkend los slotblok wordt automatisch een aparte activiteit onder zijn
primaire datum. Een duidelijk verkeerd geplaatst item verhuist mee, secundaire
data niet. Dit maakt alleen
het printconcept `!agendapagina`.

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
inhoudswijziging wel. Kandidaten waarbij je met `v` doorging worden in dezelfde
buffer niet opnieuw voorgesteld; `q`/Escape onthoudt niets. Zij doorzoekt altijd alle zes sites, vanaf veertien
dagen geleden en onbeperkt vooruit, ongeacht status.

Mogelijke Pubble-doublure: het overzicht toont alleen koppen, gegroepeerd per
krant. Zet de cursor op een kop en druk Enter, of dubbelklik, voor de volledige
tekst en metadata van precies die krantversie. De onderste terugregel, `q` of
Escape keert terug naar het overzicht. `o` opent de gekozen siteversie in
Pubble, `v` gaat door en onthoudt de getoonde kandidaten (bij
import/herschrijven: bewerken; bij verzenden: toch verzenden) en `q`/Escape
annuleert zonder iets te onthouden. In het detail staan
publicatiedatum, aanmaakdatum en de persoon die het artikel aanmaakte.

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
`<leader>aw` onthoudt dit als `agenda: nee`. Ontbrak het blok altijd en wordt
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

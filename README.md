# kickstart.nvim — Brugmedia redactie

Neovim-configuratie voor de redactionele workflow van Brugmedia. Artikelen worden geschreven in Neovim, via AI verwerkt, en via de Pubble API gepubliceerd.

Gekoppeld aan: [texttools](https://github.com/Wet-Senker/texttools) (Python-package voor AI, metadata en Pubble-API).

Op `master` staat de doublurecontrole voorlopig op **altijd**, inclusief alleen
De Brug. Werk beide repositories bij en voer na deze update in Texttools
eenmaal `uv sync --locked` uit voor het nieuwe controlecommando. Herstart
daarna de terminal en Neovim. De twee doublure-testbranches blijven beschikbaar.

---

## Workflow

```
Clipboard → pastevim() → `Pubble Inbox/werk` → cleantext → `=== ARTIKEL ===` + tekst → Neovim

<leader>ar    Herschrijven naar krantenartikel (AI)
              ↳ start metadata/Facebook op basis van controlecodes
              ↳ start kalender pas na afronding van de doublurecontrole
              ↳ detecteert 112 en kalender automatisch
<leader>ac    Kalendermetadata + ## Kalender sectie
<leader>ao    Tekstcheck: spelling/grammatica + ## Suggesties
<leader>an    Minimaal publicatieklaar maken: kop/lead waar nodig, rest behouden
<leader>at    Tussenkopjes + optionele streamer + 2 kopopties
<leader>af    Facebook-post genereren → ## Facebook sectie
<leader>al    LinkedIn-post genereren → ## LinkedIn sectie
<leader>aV    Krantversies en reviewstatus openen
<leader>aG    Huidige krantversie opslaan en goedkeuren
<leader>aw    Versturen — vangnet voor de doublurecontrole volgens branchbeleid
              bij agendapagina: krant kiezen, controleren en print-only versturen
<leader>ka    Ruwe papieren agendapagina voorbereiden voor tekstcontrole
<leader>kd    Actieve webartikelen per site op doublures controleren
<leader>kv    Meestgelezen weekoverzicht voorbereiden en na review genereren
<leader>kf    In een meestgelezen-review één hoofdfoto per gekozen artikel downloaden
<leader>kh    Contextafhankelijke hulp voor het huidige Texttools-scherm
```

---

## Leaders

| Leader | Actie |
|---|---|
| `<leader>z` | Rustige Zen-weergave met een bredere tekstkolom, zonder regelnummers, tekens in de marge of zichtbare witruimte. Markdown loopt alleen visueel om bij woordgrenzen; het bestand krijgt geen extra regeleinden. |
| `<leader>ar` | Herschrijven naar krantenartikel (AI). Een reeds bevestigde 112-rubriek of geaccepteerde agenda krijgt in dezelfde call natuurlijke zoekintentie voor kop en lead; andere artikelen niet. Bij meerdere bestemmingen verschijnt alleen een vraag als een gevonden plaats of prominente provincie de gekozen gebieden werkelijk onderscheidt. De standaardkeuze maakt gerichte lokale of provinciale versies en één algemene voor de overige kranten; zonder onderscheidend signaal ontstaat stil één algemene versie. Bestemmingen blijven gelijk. Iedere unieke tekst komt direct uit het origineel, inclusief tussenkopjes. Een streamer maak je alleen bewust handmatig met `<leader>at`. Ook als meerdere kranten dezelfde algemene tekst krijgen, opent voor iedere krant een eigen reviewbuffer, zodat socialteksten apart kunnen worden gemaakt en goedgekeurd. Geen tussenrewrite of opmaak van de gedeelde bron. |
| `<leader>ac` | Kalendermetadata + bewerkbare `## Kalender` sectie. Tijdens een doublurecontrole wordt deze actie eenmaal uitgesteld en alleen na doorgaan hervat. Een herkend maar onvolledig item toont `<!-- Ontbreekt: … -->` inclusief invoerformaat, bijvoorbeeld `Tijd: HH:MM`. |
| `<leader>kA` | Plaats vanuit een gewone artikelbuffer uitsluitend het gecontroleerde `## Kalender`-item. Krant, websiteartikel, social en Teams worden niet verstuurd. De actie controleert eerst op doublures en schrijft ontvangen agenda-ID's direct terug, zodat opnieuw drukken geen dubbel item maakt. In een voorstel uit een bestaand websiteartikel blijft dezelfde leader dat item aan het bronartikel koppelen. |
| `<leader>ao` | Tekstcheck: objectieve correcties en twijfelgevallen onder `## Suggesties`. |
| `<leader>an` | Minimaal publicatieklaar maken in twee fasen: eerst uitsluitend zekere persbericht-/mailruis als volledige regels verwijderen, daarna kop en nieuwsgerichte lead herstellen en reclametaal, directe aanspreekvormen en lokale taalfouten minimaal neutraliseren. Daarna draait dezelfde nacontrole als bij `<leader>ar`. |
| `<leader>at` | Tussenkopjes, een streamer (als er nog geen eigen `>` staat) en twee kopopties. Een gekozen kop vervangt alleen een bestaande korte kop; bij een dateline, auteursregel of eerste alinea van meer dan tien woorden wordt zij vóór de lead ingevoegd. |
| `<leader>af` | Facebook-post genereren → bewerkbare `## Facebook` sectie. In een krantreview geldt de tekst alleen voor die krant en krijgt de AI die sitecontext. Bij 112-detectie: zakelijke prompt (één feitelijke zin). |
| `<leader>al` | LinkedIn-post genereren → bewerkbare `## LinkedIn` sectie. In een krantreview geldt de tekst alleen voor die krant. |
| `<leader>aV` / `:Krantversies` | Overzicht van de gedeelde bron en alle afzonderlijke krantversiebuffers openen. |
| `<leader>aG` / `:KrantversieGoedkeuren` | Huidige krantversie terugschrijven en de exacte tekst expliciet goedkeuren. |
| `<leader>aw` | Versturen naar Pubble. Vanuit bron of reviewbuffer is dit één centrale verzending voor alle kranten: iedere krant krijgt haar eigen artikel- en socialtekst; dezelfde foto wordt eenmaal geüpload en aan alle doelen gekoppeld. Vanaf twee meegezonden foto's eindigt de web- en krantenkop in Pubble op `(n foto's)`; 112-koppen zijn uitgezonderd. Socialtekst wordt alleen in het bijbehorende Pubble-webartikel opgeslagen, niet automatisch op Facebook of LinkedIn geplaatst. Bij een import vraagt een extra safeguard alleen om bevestiging wanneer de body nog nauwelijks afwijkt van de import. Een substantiële handmatige bewerking is dus voldoende; AI is niet verplicht. Vóór de eerste Pubble-write volgt zo nodig de doublurecontrole volgens het Python-branchbeleid, tenzij die al bij import of herschrijven is afgerond. `codex/doublure-altijd` controleert ook alleen De Brug; `codex/doublure-voorwaardelijk` controleert zodra een andere krant is gekozen, ook alleen De Kop. Een incompleet agenda-item geeft de keuze om eerst aan te vullen of alleen web/print te plaatsen. Wanneer de eerstvolgende krant in een andere evenementfase valt, toont de eerste druk alleen voor die editie een `## Kranttijdsversies`-tekst. Eventvervolgen verschijnen in dezelfde reviewstap; de tweede druk publiceert alles samen. |
| `<leader>ap` | Ad-hoc herschrijven — typ `***` + instructie, buffer wordt vervangen en krijgt daarna dezelfde nacontrole als `<leader>ar`. |
| `<leader>ag` | AI gesprek — typ `***` + vraag, antwoord verschijnt eronder. |
| `<leader>aa` | **Archiefzoeker** — zoekt het hele Pubble-archief af naar eerder verschenen artikelen over hetzelfde onderwerp, voor langlopende zaken. Je krijgt vijf verhalen per keer: koppen met datum en krant bovenin, per jaar gegroepeerd, de volledige teksten eronder. Nogmaals drukken geeft de volgende vijf. Zoeken gebeurt zonder AI. Uit te zetten met `TEXTTOOLS_ARCHIEFZOEKER=0`. |
| `<leader>as` | **Achtergrond schrijven** — in de archieflijst: vat de artikelen die je hebt laten staan samen tot één `## Achtergrond` onderaan je artikel. Die sectie is voor jou zichtbaar en gaat net als `## Kalender` vóór verzending weg. De achtergrond gaat bewust niet automatisch de herschrijfprompt in. |
| `<leader>ah` | Hiërarchisch hulpmenu: kies onder meer Edities, Rubrieken, Publicatieplanning, Acties of de volledige cheatsheet. |
| visueel `<leader>ai` | Herschrijf de selectie direct naar krantenstijl, zonder een eenkeuzemenu. |
| `<leader>kt` | Handmatig rubriektemplate kiezen, inclusief Raadspraat, Ondernemen in Kampen en Kamper Kiek. |
| `<leader>kp` | Rubriekplanning: reminders en planningsoverzichten voor Raadspraat en Ondernemen in Kampen. |
| `<leader>ka` | Ruwe papieren agendapagina structureren en gewone items redigeren; daarna zelf de tekst controleren. |
| `<leader>kg` | Agenda-onlinemenu. Bij **Websiteartikelen zonder agenda-item zoeken** maakt Enter een bewerkbaar voorstel, opent `o` het bronartikel en markeert `x` een artikel duurzaam als geen agenda nodig. Afwijzingen synchroniseren via de gedeelde Texttools-map. |
| `<leader>kd` | Actieve webartikelen van alle kranten of één gekozen krant intern op doublures controleren. Kijkt standaard veertien dagen terug, vergelijkt alleen berichten die maximaal zeven dagen uiteen staan en opent kandidaten geordend in de browser. Sites worden nooit onderling vergeleken; agenda-schaduwartikelen tellen niet mee. |
| `<leader>kv` / `:Meestgelezen` | Haalt voor één krant tien meest bekeken kandidaten uit de afgelopen zeven voltooide dagen op. Iedere keuzeregel toont kop, woorden, hits en Facebookreacties; technische dossiers zijn ingeklapt (`zo` opent, `zc` sluit). Verwijder regels met `dd`, laat maximaal vijf staan en zet eventueel `LOS:` voor een zelfstandig reactieartikel vanaf 41 reacties én met toegevoegde reactietekst. De artikelvolgorde volgt de kijkcijfers. Druk opnieuw `<leader>kv`; daarna openen gewone artikelbuffers. Vanaf 15 reacties wordt Meta eerst geprobeerd en anders de handmatige link-/plakroute aangeboden. Zonder reactietekst wordt niets over reacties geschreven. |
| buffer-lokaal `<leader>kf` / `:MeestgelezenFotos` | Downloadt direct voor alle overgebleven keuzeregels precies één hoofdfoto naar `Bureaublad/meestgelezen`; er volgt geen tweede keuzemenu en volledige galerijen worden niet opgehaald. |
| `<leader>kh` / `:ContextHelp` | Toont dynamische hulp voor de huidige workflowfase: status, aanbevolen vervolgstap, andere hoofdopties en het gevolg daarvan. Werkt onder meer bij krantversies, publicatiereview/-herstel, agenda, rubriekexport, doublurecontrole en Meestgelezen. Zonder herkende context verwijst de melding naar de algemene `<leader>ah`-hulp. |
| `<leader>aq` | Annuleer alle actieve editor-AI-taken van de huidige buffer. |
| `:AICancel` | Zelfde expliciete annulering als `<leader>aq`. |
| `:TexttoolsLog` | Toon de veilige tijdlijn van het huidige artikel: handelingen, duur, uitkomst en een eventueel onafgesloten proces. |
| `:TexttoolsLog!` | Toon de laatst gelogde Texttools-workflow, ongeacht de huidige buffer. |

In hiërarchische keuzemenu's staan acties eerst en staat `← Terug naar …`
altijd onderaan. Escape sluit de volledige workflow. Korte persoon- en
fotokeuzes gebruiken alleen Escape om de wizard te annuleren.

De extra waarschuwing voor een vrijwel onbewerkte import vraagt
`Toch publiceren?`: druk `j` voor ja of `n` voor nee. Nee is de veilige
standaard.

De doublurecontrole is een poort voor kalender-AI. Zolang een mogelijke
doublure nog in beeld staat, starten automatische kalenderanalyse, handmatig
`<leader>ac` en AI voor evenementvervolgteksten niet. Kies je **doorgaan**, dan
wordt één uitgestelde kalenderactie hervat. Kies je **annuleren**, dan vervalt
die actie en worden er geen kalender-AI-kosten gemaakt. Gewone metadata- en
Facebooktaken mogen wel parallel blijven lopen.

`<leader>an` is bedoeld voor een tekst waarvan de inhoud grotendeels goed staat,
maar die nog niet helemaal plaatsbaar is. Een lichte AI-voorfase wijst alleen
regelnummers met zekere persbericht- of mailruis aan; Python verwijdert precies
die originele regels en accepteert geen vervangende AI-tekst. Daarna blijven
een goede kop en lead staan;
een ontbrekende of ondeugdelijke kop of lead wordt gericht hersteld. De lead
brengt het nieuws direct en begint niet met een datum of tijd. Een dateline
wordt alleen toegevoegd als één plaats ondubbelzinnig centraal staat. In de
rest maakt de AI de kleinst mogelijke ingreep: subjectieve, promotionele of
overdreven journalistentaal en directe lezersaanspraak verdwijnen, zonder een
volledige rewrite. Alleen een expliciet aan een bron gekoppelde claim mag
indirect worden toegeschreven; er worden nooit nieuwe directe citaten gemaakt.
Verandering van bestaande citaten, getallen, datums, tijden, URL's of
mailadressen wordt technisch geweigerd. Een geslaagde controle geldt bij
verzending alleen voor de exact gecontroleerde body. Bewerk je de buffer terwijl
de AI draait, dan wordt het late resultaat niet toegepast.

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
EMBARGO: NIET VERSTUREN — VERWIJDER DEZE REGEL PAS NA VRIJGAVE  # automatisch bij import
publicatiedatum: 2026-09-19 11:30  # voorstel uit een expliciete embargozin
embargobron: **Let op: onder embargo tot 19 september, 11.30 uur**
b: Bijschrift      # globaal fotobijschrift
c: Naam fotograaf  # globale fotocredit
b1: / c1:          # bijschrift/credit voor foto 1 specifiek
b2: / c2:          # bijschrift/credit voor foto 2 specifiek
@John Boodschap    # alleen in Teams-bericht voor actuele ontvanger John
@all Boodschap     # in alle Teams-berichten van dit artikel

=== ARTIKEL ===

Artikelkop
```

Alles boven de marker is beschermd en wordt nooit als AI-rewrite-input gebruikt.
Ook een visuele AI-selectie die de marker kruist wordt geweigerd.
Bij `<leader>aw` valideert Python iedere regel daar strikt. `f:` is geen tag;
gebruik `c:` of `Foto:`. `***` is bewust iets anders: die regel blijft voor
inline AI-prompts en gesprekken gereserveerd.

Vindt de eerste importinspectie het losse woord `embargo` in de oorspronkelijke
artikelbody, dan verschijnt direct een waarschuwing en de bovenstaande
`EMBARGO:`-regel. Een expliciete datum en tijd uit dezelfde zin verschijnen als
`publicatiedatum:`; de planningskeuze van `<leader>aw` stelt dat exacte lokale
moment vervolgens als standaard voor. De letterlijke oorspronkelijke regel
blijft als `embargobron:` bewaard, ook nadat de blokkade is vrijgegeven. Zolang
de `EMBARGO:`-regel staat, stopt `<leader>aw` vóór AI- of Pubble-werk. Verwijder
na vrijgave zowel de oorspronkelijke embargozin onder `=== ARTIKEL ===` als de
volledige `EMBARGO:`-regel. `embargobron:` en `publicatiedatum:` mogen blijven.
Bij een onduidelijke datum verzint het programma geen voorstel.

Teams-selectors zijn hoofdletterongevoelig en mogen worden gecombineerd als
`@Joop, @Saskia Boodschap`. Ze volgen de actuele ontvanger uit
`:TeamsRedactie`, inclusief waarneming. De selector zelf verschijnt niet in
Teams; de boodschap komt na de plaatsingszin en vóór de kop. Zonder passende
regel blijft het bestaande Teams-bericht ongewijzigd.

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
`e: D, Z`. De importcontrole draait eenmaal per buffer. Na iedere volledige
herschrijving (`<leader>ar`, `<leader>an` en `<leader>ap`) volgt een hercontrole.
Een bestaande `e:` blijft zonder vraag leidend wanneer de
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

Bij een kalenderartikel, maar ook bij een datumgebonden artikel zonder
kalenderblok, vergelijkt `<leader>aw` na de webdatumkeuze de toestand op de
eerstvolgende krantdatum. `agenda: nee` voorkomt alleen het agenda-item; de
krantdeadline en tijdsvormcontrole blijven actief. Is het evenement op de
krantdatum inmiddels begonnen of afgelopen, dan vraagt NeoVim of er een aparte
kranttekst moet komen of dat het artikel niet naar die krant gaat. Kies je voor
herschrijven, dan verschijnt een `## Kranttijdsversies`-tekst voor de getroffen
krant. De website houdt de oorspronkelijke tekst. Controleer de tijdsvorm en
druk opnieuw `<leader>aw`; feiten, absolute data, tijden, getallen en citaten
mogen niet veranderen.

**112-detectie** — scoort tekst op signaalwoorden (politie, brandweer, ambulance, incident, etc.). De combinatie van minimaal één hulpdienst en één concreet incident krijgt één extra punt. Bij score ≥ 6 verschijnt een bevestigingsvraag. Bij "Ja": 112-template toegepast, `rubriek: 112` en `prio: 2` bovenaan gezet. Bij "Nee" blijft die keuze voor de huidige buffer staan en mag detectie na `<leader>ar` het template niet alsnog toepassen. De kop gebruikt via `pubble-places` de eerste bekende plaats uit de centrale verspreidingsgebiedentabel; zonder treffer wordt het `112:`.

**Krantprioriteit vóór verzending** — `<leader>aw` toont in het
publicatieplanningsmenu de automatisch gekozen prioriteit en de reden. De
deterministische volgorde is: handmatige `prio:` wint; 112 krijgt 2;
auteursregels en vaste rubrieken krijgen 1; een agenda-artikel onder 150
inhoudelijke woorden krijgt 4; een concrete plaats uit een gekozen
verspreidingsgebied geeft 3; alleen provinciebrede, landelijke of niet-lokale
inhoud geeft 4. Kies **Prioriteit aanpassen** om 1–4 te selecteren. NeoVim zet
die keuze zichtbaar als `prio:` boven `=== ARTIKEL ===` en start dezelfde
voorbereiding opnieuw.

**Kalenderdetectie** — scoort tekst op datum/tijd/deelname-signalen. Bij score
≥ 8 wordt `articlemeta --calendar` gestart en een bewerkbare `## Kalender`-
sectie toegevoegd. Wil je het agenda-item niet, verwijder dan het volledige
blok vanaf `## Kalender`. Bij `<leader>aw` wordt dat als `agenda: nee`
vastgelegd en de tijdelijke kalendercache gewist; de vroegere aparte
hoofdletter-C-weigeractie is daarom vervallen. Was er nog nooit een
Kalenderblok en ziet de
laatste lokale controle bij verzenden alsnog een sterke kandidaat, dan vraagt
Neovim eerst. Ja maakt en toont het blok; nee verzendt alleen web en print.

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

Na iedere volledige herschrijving worden ook doublures, metadata, kalender,
eventuele `facebook: x` en 112 opnieuw volgens dezelfde regels
beoordeeld. 112 vraagt alleen opnieuw om bevestiging als bij import nog geen
keuze is gemaakt. Deelacties zoals tekstcheck, een geselecteerde passage,
streamer, socialtekst of chatantwoord starten deze volledige nacontrole niet.
Een ontbrekende streamer wordt nooit automatisch gemaakt; gebruik daarvoor
bewust `<leader>at`.

Het weeknummer in een gegenereerde Pubble-werktitel is de uiterste bruikbare
krant. Na die krant kan het artikel weg; een hoger nummer kan worden
doorgeschoven en `x` heeft geen automatische deadline. Voor actueel nieuws
kiest de bestaande metadata-call 0–2 extra wekelijkse houdbaarheidscycli. Dit voegt geen
extra AI-call toe; `week:` blijft de handmatige override.

Valt de eerstvolgende verschijning van een gekozen krant na die inhoudelijke
grens, dan waarschuwt `<leader>aw` vóór verzending. Kies `Alleen website voor
te late krant(en)`, `Toch ook naar de krant` of `Annuleren`. Bij toch
doorzetten wordt het weeknummer in de krantwerktitel van die te late editie
vervangen door `z`, zodat de bewuste uitzondering direct zichtbaar is. De
werkelijke deadline blijft voor controles apart bewaard.

De lichte SEO-instructie loopt alleen mee wanneer de keuze vóór de rewrite al
vaststaat: een 112-template/`rubriek: 112`, `agenda: ja` of een zichtbare
`## Kalender`-sectie. `agenda: nee` sluit evenement-SEO uit. Een pas na de
rewrite herkend onderwerp veroorzaakt geen tweede AI-aanroep.

**Column Natuurvereniging IJsseldelta** — een auteursregel met Suzanne Beurmanjer of een afsluitend mailadres op `natuurverenigingijsseldelta.nl` geeft een voorstel. Ook bij beide signalen vraagt NeoVim altijd bevestiging. Een losse vermelding van de vereniging of haar website is onvoldoende. Na akkoord wordt het bestaande column-template toegepast; tekst en auteursregel blijven behouden. Een al toegepaste rubriekkop wordt niet opnieuw ingepakt. De nieuwe regels staan configureerbaar in de Python-core (`column_recognition.json`); per import komt er één asynchrone lokale Python-call bij, zonder AI; Raadspraat en Ondernemen gebruiken daarnaast hun eigen fotomappen.

**Rubrieknaam boven de tekst** — een losse rubrieknaam of `Rubrieknaam: Titel`
start de bijbehorende templateflow. Dit geldt voor alle huidige templates,
waaronder Raadspraat, Ondernemen in Kampen, de natuurcolumn, Hondenhoek,
Kamper Kiek, Open Hof en de andere vaste columns. Een vermelding in een
gewone tekstzin geldt niet als opdracht. Natuurvereniging en 112 behouden
hun bevestigingsvraag. Een al volledig toegepast template wordt niet herhaald.

**Persoonsherkenning** — Raadspraat en Ondernemen vergelijken de importtekst
ook met namen uit hun fotomappen. Alleen een zelfstandige auteursregel telt
als persoonsmatch; een naam in een gewone zin bepaalt de auteur niet. Zonder
expliciete rubriekkop vraagt zo'n match bevestiging. Eén passende persoon kan meteen worden ingevuld; bij een
ontbrekende of onduidelijke match kies je de persoon. Een geannuleerde keuze
wijzigt de tekst niet. `<leader>kp` blijft uitsluitend planning gebruiken.
De herkenning gebeurt in één asynchroon Python-proces per import; alleen de
twee relevante fotomappen worden bekeken, zonder AI of netwerkverkeer. Er
wordt nooit stil een persoonsrubriek toegepast. Als één persoon in beide
rubrieken voorkomt, zoals Nardus Koster, kies je expliciet de juiste rol.

**Foto bij de vormgevingstekst** — bij succesvolle verzending worden alle
geüploade foto's naast de definitieve tekst gezet, ook voor de generieke
natuurcolumn in de lezersnieuwsmap. De uploadgegevens en inhoudshash bepalen
welke foto erbij hoort, ook nadat die naar `used` is verplaatst. Bij een
ontbrekende of gewijzigde foto blijft het exportplan staan en meldt NeoVim de
fout; `<leader>aw` kan de ontbrekende stap hervatten. Dit kost alleen bij een
vormgevingsexport één extra asynchroon Python-proces plus lokale fotokopieën.

---

## 112-berichten

- Template: `112 <PLAATS>: <titel>` (of `112: <titel>`) + body + disclaimer
- `rubriek: 112` → `articleCategoryId: 24` op krant én web in Pubble; `rubriek:`/`r:` accepteert ook een unieke afkorting of één typfout (`sp`, `spo`, `sprt` → `sport`)
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

Na een geslaagde publicatie opent de Pubble-pagina direct in de
standaardbrowser. Op macOS gebeurt dat op de achtergrond: de browser krijgt
geen focus en neemt de app waarin je werkt dus niet over.

---

## Rubriek-templates (`<leader>kt`)

Gedefinieerd in `~/.config/nvim/lua/krant.lua`. De gewone templates staan in
`M.templates`. Raadspraat, Ondernemen in Kampen en Kamper Kiek staan bovenaan
hetzelfde menu. De eerste twee gebruiken een dynamische flow voor persoon,
foto, bijschrift en template; Kamper Kiek gebruikt de ene foto uit Pubble
Inbox. Een expliciete rubriekkop start de flow voor Raadspraat of Ondernemen.
Zonder zo'n kop kan een volledige naam uit de fotomap de rubriek alleen als
bevestigingskeuze voorstellen; er wordt nooit stil geclassificeerd. Een unieke
persoon wordt direct in dezelfde flow gebruikt, zonder een tweede personenmenu.
De huidige columns en gespecialiseerde rubrieken zijn voor De Brug en krijgen
daarom bij de templatebewerking zichtbaar `e: B`. Een bestaande handmatige
editiekeuze wordt niet overschreven.
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

De definitieve vormgevingstekst bevat één bijschrift, geen Facebook- of
LinkedIn-bijlagen en gewone leesbare webadressen zonder Markdown-syntaxis. Deze
opschoning gebeurt samen met de foto-export in de gedeelde Python-kern.
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
| `lua/pubble_duplicates.lua` | koppen per krant, detailweergave van de gekozen krantversie en expliciete keuze bij mogelijke Pubble-doublures |
| `lua/site_duplicates.lua` | dunne client en keuzemenu voor interne webartikel-doublures (`<leader>kd`) |
| `lua/weekly_most_read.lua` | dunne reviewclient voor het meestgelezen weekoverzicht en hoofdfoto's (`<leader>kv`, buffer-lokaal `<leader>kf`) |
| `lua/context_help.lua` | generieke bufferafhankelijke schermhulp (`<leader>kh`) |
| `lua/ordered_browser.lua` | opent gerelateerde Pubble-links in een stabiele, niet-blokkerende volgorde |
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

### Vragen en krantversies

Handmatig geopende keuzelijsten gebruiken Telescope: typ een deel van de
gewenste optie om fuzzy te zoeken en kies met Enter. Escape annuleert zo'n menu.
Automatische importvragen (agenda, 112, rubriek en persoonskeuze) blijven in de
stabiele native vraagweergave en vereisen een expliciet antwoord: Escape en
Ctrl-C zijn daar geen annulering. Invoervelden gebruiken eveneens de centrale
overlay boven de tekst. Zonder beschikbare Telescope-provider vallen handmatige
keuzelijsten automatisch terug op die overlay; gebruik daar pijltjes of `j`/`k`,
Enter of nummers 1–9. Lange uitleg kan met Ctrl-U/Ctrl-D worden gescrold.
De handmatige tekstversiekeuze van `<leader>ar` blijft asynchroon: de editor
wacht niet in een geneste invoerlus en Escape annuleert de rewrite veilig.

Goedgekeurde krantversies blijven bereikbaar via `<leader>aV` of `:Krantversies`.
Wijzigen en opslaan maakt opnieuw goedkeuren met `<leader>aG` nodig.

Maak met `<leader>ac` een agenda-item vanuit de gewenste krantversie. Controleer
het kalenderblok, sla op met `:w` en keur de versie opnieuw goed met `<leader>aG`.
Het item gaat alleen naar de site(s) van die versie. `<leader>aw` blijft de
gezamenlijke verzending vanuit het bronartikel starten. Een kalenderblok bij
de gedeelde bron blijft een gezamenlijke agenda; een eigen kalenderblok bij een
variant vervangt die gezamenlijke agenda voor die variant.

### Regressietests

De configuratie richt zich op Neovim 0.12.3. De headless regressietests draaien
zonder persoonlijke configuratie of plugininstallatie:

```bash
cd ~/.config/nvim
bash tests/run_headless.sh
```

De GitHub Actions-workflow voor deze repository is op 16 september 2026
verwijderd: de runner beschikte niet over de private Texttools-repository en
faalde daardoor op ontbrekende CLI's. Draai deze suite daarom vóór iedere push
lokaal. Herstel CI door beide repositories read-only uit te checken en Texttools
te installeren; zie de actuele prioriteiten in
`~/workspace/texttools/VERBETERPLAN.md`.

Bekend open punt op 18 september 2026: de volledige suite stopt reproduceerbaar
in `tests/duplicate_stages.lua` met `pending_jobs bleef hangen`. De nieuwe
editieresolutie/agenda-doublurerunner van de handmatige kalenderactie moet in dat
testscenario expliciet worden gestubd en de jobbalans moet daarna voor succes,
fout en annulering worden vastgezet. Verhoog niet alleen de timeout.

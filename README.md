# kickstart.nvim — Brugmedia redactie

Neovim-configuratie voor de redactionele workflow van Brugmedia. Artikelen worden geschreven in Neovim, via AI verwerkt, en via de Pubble API gepubliceerd.

Gekoppeld aan: [texttools](https://github.com/Wet-Senker/texttools) (Python-package voor AI, metadata en Pubble-API).

Op `master` staat de doublurecontrole voorlopig op **altijd**, inclusief alleen
De Brug. Werk beide repositories bij en voer na deze update in Texttools
eenmaal `uv sync --locked` uit voor het nieuwe controlecommando. Herstart
daarna de terminal en Neovim. De twee doublure-testbranches blijven beschikbaar.

---

## Workflow

Bestaande foto uit Pubble nodig? Gebruik `<leader>pf` / `:PubbleFoto`, of
**Foto zoeken** bij de fotocontrole van `<leader>aw`. Bron en Zoekwoorden
staan in een tijdelijke Vim-buffer. Kies bij Bron tussen
`Artikelfoto's`, `Beeldbank` of `Beide` (standaard). Zoekwoorden ondersteunt maximaal
vier komma-gescheiden begrippen. Een plaats wordt niet automatisch toegevoegd;
typ die desgewenst zelf erbij, bijvoorbeeld `Zoekwoorden: biljart, Kampen`.
Oude Onderwerp/Plaats-invoer blijft leesbaar, zonder een aparte plaatsbonus.
Escape gaat naar Normal-modus, gewone
bewerkingen/undo/plakken werken, Enter zoekt en Ctrl-C annuleert. De artikelbuffer
en cursorpositie blijven behouden. De resultatenlijst heeft één regel per foto
met een witregel tussen opeenvolgende resultaten.
`p` toont alle voorbeelden in een browsertab, met knoppen om van bron te wisselen,
meer resultaten te laden en **Gebruik deze foto** te kiezen. In NeoVim wisselt
`b` van bron, Enter kiest een foto, `s` wijzigt zoekwoorden, `]p` laadt meer,
`a` maakt een controleerbare AI-stockprompt; bij terugkeer met een nieuwe
Inbox-download opent het tagscherm automatisch. `i` heropent het na wegklikken;
`q` annuleert. Op macOS openen tabs op de achtergrond. De foto's worden niet
gedownload; alleen de browser kan cachen. Het oude archiefbijschrift wordt niet
overgenomen: `b:` is optioneel. Controleer na kiezen altijd de verplichte `c:` in
het artikel en verzend met een volgende `<leader>aw`. De bronfoto blijft gelijk.
Vanuit een krantversiebuffer gebruikt de fotokeuze altijd het hoofddocument:
de foto geldt voor alle edities en vervuilt nooit de kranttekst met YAML of
een extra artikelgrens. Dit geldt ook voor de AI-stockroute.
Fotozoeken blijft beschikbaar tijdens rewrite, Facebook en kalender. De
handmatige fotozoekvraag krijgt voorrang op native invoervensters met behoud
van hun drafts; een al actieve fotozoeker wordt hergebruikt. Bij overlappende
tekstwijzigingen bewaart de Python-actie `merge` de nieuwste tekst en voegt
alleen media toe (maximaal twee lokale herpogingen, geen extra AI/API).
Gelijktijdig gewijzigde media/credit en daadwerkelijke verzending blokkeren wel.
Werkt met de bijgewerkte Texttools-core (`pubble_photo_cli`).
Gecombineerde zoektermen hebben in de rangschikking voorrang als ze
in het bronartikel voorkomen; daarna tellen fototrefwoorden, bijschrift en kop.
Er is geen beeldherkenning/AI en geen automatische 112-uitsluiting. De losse
beeldbank werkt ook zonder bronartikel. Ontbreekt een veilige thumbnail, dan
toont het raster een Pubble-link. Bekend eenmalig gebruik wordt geblokkeerd;
controleer altijd context en rechten.
Alle geladen pagina's vormen één lijst met unieke foto-ID's; alternatieve
bronverwijzingen blijven bewaard. `p` toont dezelfde unieke selectie. Een
nieuwe zoekopdracht begint opnieuw; een mislukte vervolgpagina laat de vorige
resultaten intact. Geen automatische scan bij alleen dubbele resultaten en
geen extra API-/AI-calls voor ontdubbelen. Wel groeit de tijdelijke metadata
en lokale sortering zolang je meer pagina's ophaalt. Sluiten ruimt dit op.
Sinds 7 oktober stelt de fotozoeker maximaal twee onderwerpen plus bekende
woordvarianten voor (maximaal drie voorgestelde zoekwoorden). Alle zelf gekozen begrippen worden
los én in alle betekenisvolle combinaties gezocht, zonder categorie-/locatiefilter.
`Zoekwoorden: hond, Zwolle` zoekt dus `hond`, `Zwolle` en `hond Zwolle`. Specifiekere
matches komen eerst, dan bevestigde fototrefwoorden/bijschrift/kop;
enkelvoud/meervoud telt niet dubbel. `Gevonden via` toont de zoekherkomst.
`Zoekwoorden: sport, landstede, Zwolle` levert zeven routes op: alle drie samen, drie
paren en drie losse termen. De eerste pagina verdeelt maximaal 36 bronrecords
over die routes; honderden Pubble-treffers worden met `]p` vervolgd. De toets en
melding voor meer bronresultaten staan alleen in beeld als Pubble een volgende
pagina meldt.
Met `p` zie je een compact raster van drie foto's naast elkaar, of minder op
smalle schermen. Klikken vergroot/sluit het beeld; **Gebruik deze foto** kiest.
In datzelfde raster kun je van bron wisselen en meer resultaten laden.
Combinaties kosten meer netwerkcalls. Artikelfoto's gebruikt maximaal vijftien
zoekvragen, circa 36 unieke artikel-details en twaalf keyword-GETs per pagina.
Beeldbank gebruikt maximaal vijftien zoekvragen en circa 36 metadata-GETs;
`Beide` deelt hetzelfde budget over beide routes. Details worden gecachet en vier GETs lopen
tegelijk. Een oude zoekcursor vraagt opnieuw zoeken; geen extra AI-call, download,
upload of automatische publicatie. Latentie op een oude Mac moet nog worden gemeten.

De browserkeuze gebruikt een tijdelijke lokale verbinding, maximaal vijftien
minuten. Kiezen, opnieuw zoeken, `q` en afsluiten van NeoVim stoppen de verbinding.
Een gewijzigde artikelbuffer weigert een late keuze. Er wordt alleen een
bestaand beeld-ID overgenomen, nooit geüpload of automatisch gepubliceerd.
Een AI-stockimport bewaart het gecontroleerde beeld in de gedeelde werkruimte
en een duurzame verwijzing met tags in het artikel. De keuze blijft behouden
als de verzendkopie in een andere map staat. Pas de gewone verzending uploadt dit bestand met de
ingevoerde archieftags naar de algemene Pubble-stocklibrary (locatie 24) en
koppelt het nieuwe beeld-ID aan de publicatiedoelen. Een ontbrekende of gewijzigde
kopie geeft een fout; losse Inbox-foto's worden bij deze keuze niet extra
meegenomen. `:TexttoolsLog` toont importuitkomst, beeldbanklocatie en tag-aantal.
Werk beide repositories bij; bij een fout blijft Enter in de lijst beschikbaar.
`/`, `n`, `N`, `gg` en `G` blijven gewone Vim-navigatie in de resultatenlijst.
112-bronartikelen worden niet meer automatisch uitgesloten; beoordeel de
zichtbare foto's zelf. Een oude `Uitsluiten:`-regel wordt nog gelezen maar niet
meer toegepast.

```
Clipboard → pastevim() → `Pubble Inbox/werk` → cleantext → `=== ARTIKEL ===` + tekst → Neovim

<leader>ar    Herschrijven naar krantenartikel (AI)
              ↳ start metadata/Facebook op basis van controlecodes
              ↳ start kalender pas na afronding van de doublurecontrole
              ↳ detecteert 112 en kalender automatisch
<leader>ac    Kalendermetadata + ## Kalender sectie
<leader>ao    Tekstcheck: spelling/grammatica + ## Suggesties
<leader>an    Behoudend publicatieklaar: neutrale tekst, praktische info als proza
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

Het technische YAML-blok boven een artikel of agendapagina is standaard
ingeklapt tot **Technische gegevens**. Zet de cursor op die regel en druk `zo`
om het te bekijken; `zc` klapt het weer dicht. Dit werkt ook als metadata later
op de achtergrond wordt toegevoegd. `e:`, `wijk:`, fotoregels, meldingen en het
leesbare `## Kalender` blijven zichtbaar. Het bestand bevat nog steeds alle
gegevens: inklappen verandert niets aan opslaan, verzenden of herstel.
Een bewust geopende vouw blijft tijdens gewone tekstbewerking open.

**Direct plaatsen en datumcontrole:** een lege planning wordt nu als lege
datummapping doorgegeven, ook bij hervatten met `<leader>aw` na een krantreview
of `needs_date_review`. Een technische fout in die overdracht is geen
inhoudelijke datumwaarschuwing en geen gebruikersannulering: je ziet een veilige
oorzaak en `:TexttoolsLog` toont de foutcode/processtatus. Echte waarschuwingen
over verlopen aankondigingen en `vandaag`/`morgen` blijven beoordeling vragen.
Na deze update: bewaar de open artikelen en herstart NeoVim; de tijdelijke
Lua-workaround is dan niet meer nodig. Er wordt niets automatisch gepubliceerd.

Het invoerscherm **Mogelijke doublures** zet het nieuwe bericht apart en toont
bestaande treffers met Agenda/Web, krantnaam en uitgelijnde Europese datum.
Web en agenda worden vóór de beoordeling samen opgehaald en in één overzicht
getoond. Bij import/herschrijven betekent `n`: meteen verder bewerken zonder
agendabericht, zonder tweede webbevestiging. Dit is geen akkoord voor webpublicatie.
Bij definitief verzenden haalt `n` alleen de agendatreffers weg; eventuele
webtreffers blijven beoordeling vragen. Een fout in één controle verbergt de andere treffers niet.
Enter/dubbelklik bekijkt alleen tekst/details in NVIM; `o` opent de geselecteerde
treffer in Pubble. `n` bij een agendacontrole slaat agenda-aanmaak voor het hele
artikel over, maar laat web/krant doorgaan. Het verwijdert niets uit Pubble.
Bij import/herschrijven sluit `q` de agenda-keuze: bewerken gaat verder, zonder
automatisch kalenderblok of toestemming. `v` bereidt bewust toch een agenda voor.
Bij verzending stopt `q` alleen die verzendpoging; `v` bevestigt dan publicatie
ondanks de mogelijke doublure. `<leader>ac` maakt altijd een werkblok, ook na
weigeren/verwijderen of bij ontbrekende gegevens. Dat is geen publicatietoestemming.
Een actuele controle wordt hergebruikt. Veranderen later de tekst, editie of
kalendergegevens, dan kan opnieuw controle nodig zijn; een nauwkeuriger
kalendervoorstel kan ook nog nieuwe treffers opleveren. Dit is geen tweede
losse controle op dezelfde ongewijzigde invoer.
Een keuzevenster verbergt Fidget-regels tijdelijk, zonder hun resterende
achtseconden-termijn te wissen of opnieuw te starten.

De schrijfroute gebruikt sinds 21 oktober het omkeerbare profiel
`eenvoudig-20261021` in de gedeelde Python-kern: korte schrijfopdracht plus
krant-/provinciecontext, zonder extra classificatiecall. De oude route blijft
beschikbaar. Terugschakelen voor volgende opdrachten in deze sessie:
`:let $TEXTTOOLS_WRITING_PROFILE = 'behoudplan-20261021'`; weer nieuw:
`:let $TEXTTOOLS_WRITING_PROFILE = 'eenvoudig-20261021'`. Wacht eerst lopend
schrijfwerk af. De terugweg verandert geen bestaande artikeltekst of publicatie.
Details: [schrijfprofielen](/Users/nickdevries/workspace/texttools/docs/schrijfprofielen.md).

| Leader | Actie |
|---|---|
| `<leader>z` | Rustige Zen-weergave met een bredere tekstkolom, zonder regelnummers, tekens in de marge of zichtbare witruimte. Markdown loopt alleen visueel om bij woordgrenzen; het bestand krijgt geen extra regeleinden. |
| `<leader>ar` | Journalistiek herschrijven en krantgericht maken met AI. De bestaande prompt behoudt een al goede body en redigeert een ruwe bron; geen extra redactie-keuze. Bij meerdere bestemmingen volgt bij onderscheidende gebiedssignalen Gerichte varianten / Eén algemene versie met advies. Iedere unieke tekst komt direct uit het origineel; kranten met dezelfde tekst delen een reviewbuffer. Geen tussenrewrite of automatische streamer. Bevestigde 112-/agendacontext geeft natuurlijke zoekintentie in dezelfde call. Bestemmingen, bron en redactionele staart blijven beschermd. |
| `<leader>ac` | Expliciet een bewerkbaar `## Kalender`-werkblok voorbereiden, ook na weigeren/verwijderen of bij weinig gegevens. Automatische doublure-/herkenningskeuzes blokkeren deze opdracht niet. Ontbrekende velden blijven leeg; AI probeert beschikbare gegevens aan te vullen. Publicatie controleert afzonderlijk op doublures en volledigheid. |
| `<leader>kA` | Plaats vanuit een gewone artikelbuffer uitsluitend het gecontroleerde `## Kalender`-item. Krant, websiteartikel, social en Teams worden niet verstuurd. De actie controleert eerst op doublures en schrijft ontvangen agenda-ID's direct terug, zodat opnieuw drukken geen dubbel item maakt. In een voorstel uit een bestaand websiteartikel blijft dezelfde leader dat item aan het bronartikel koppelen. |
| *onderdeel van `<leader>ar`* | **Plaatsencontrole.** Wijzen plaatsen in de tekst naar kranten die nog niet gekozen zijn, dan volgt eenmalig de vraag of die mee moeten. Die vraag komt alleen wanneer de controle bij import niet heeft plaatsgevonden — een zelf getypte of geplakte buffer komt niet langs de importroute — of wanneer de tekst sindsdien naar andere kranten is gaan wijzen. Een provincie is context en levert geen voorstel op. |
| `<leader>ao` | Tekstcheck: objectieve correcties en twijfelgevallen onder `## Suggesties`. |
| `<leader>an` | Behoudend publicatieklaar maken: bronruis verwijderen, kop/lead zo nodig herstellen, schrijverssubjectiviteit en ik-/wij-/u-taal buiten citaten neutraliseren en praktische lijstjes omzetten in lopende tekst. Goede bodytekst blijft staan. Daarna dezelfde nacontrole als bij `<leader>ar`. |
| `<leader>at` | Tussenkopjes, een streamer (als er nog geen eigen `>` staat) en twee kopopties. Een gekozen kop vervangt alleen een bestaande korte kop; bij een dateline, auteursregel of eerste alinea van meer dan tien woorden wordt zij vóór de lead ingevoegd. |
| `<leader>af` | Facebook-post genereren → bewerkbare `## Facebook` sectie. Zijn er krantversies, dan hoort de tekst bij de versie en niet bij de bron: die blijft het onherschreven importbericht. Op de bron vraagt Neovim of hij voor iedere unieke versie een eigen tekst maakt, elk uit het afgeronde artikel daarvan; in een krantbuffer maakt hij alleen die ene. Een gedeelde buffer krijgt geen enkele krant als sitecontext mee. Bij 112-detectie: zakelijke prompt (één feitelijke zin). |
| `<leader>al` | LinkedIn-post genereren → bewerkbare `## LinkedIn` sectie. In een krantreview geldt de tekst alleen voor die krant. |
| `<leader>aV` / `:Krantversies` | Overzicht van de gedeelde bron en alle afzonderlijke krantversiebuffers openen. |
| `<leader>aG` / `:KrantversieGoedkeuren` | Huidige krantversie terugschrijven en de exacte tekst expliciet goedkeuren. |
| `<leader>aK` / `:ArtikelKopie` | Huidige artikeltekst als zelfstandige `Kopie-…`-buffer openen. Vul de nieuwe `e:` in en herschrijf met `<leader>ar`. Origineel blijft intact; oude metadata, Pubble-ID's, planning, fotokeuze, socialtekst, agenda en gekoppelde krantversies gaan niet mee. Kies opnieuw een foto. Ook beschikbaar onder **Acties** in `<leader>ah`. |
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
| `<leader>km` / `:AgendaPaginaOmvang` | Tel de actuele agendablokken tegen ongeveer 166 alinea’s en schat hoeveel agendapunten nog weg moeten. Alleen-lezen, zonder AI. |
| `<leader>kg` | Agenda-onlinemenu. Bij **Websiteartikelen zonder agenda-item zoeken** maakt Enter een bewerkbaar voorstel, opent `o` het bronartikel en markeert `x` een artikel duurzaam als geen agenda nodig. Afwijzingen synchroniseren via de gedeelde Texttools-map. |
| `<leader>kd` | Actieve webartikelen van alle kranten of één gekozen krant intern op doublures controleren. Kijkt standaard veertien dagen terug en vergelijkt berichten die maximaal zeven dagen uiteen staan. Geen automatische browseropening: `o` opent alle artikelen van de geselecteerde doubluregroep, ook drie of meer; andere groepen blijven dicht. `m` markeert het geselecteerde paar als geen doublure en `r` toont/verbergt eerdere beoordelingen. Sites worden nooit onderling vergeleken; agenda-schaduwartikelen tellen niet mee. |
| `<leader>kv` / `:Meestgelezen` | Haalt voor één krant tien meest bekeken kandidaten uit de afgelopen zeven voltooide dagen op. Iedere keuzeregel toont kop, woorden, hits en Facebookreacties; technische dossiers zijn ingeklapt (`zo` opent, `zc` sluit). Verwijder regels met `dd`, laat maximaal vijf staan en zet eventueel `LOS:` voor een zelfstandig reactieartikel vanaf 41 reacties én met toegevoegde reactietekst. De artikelvolgorde volgt de kijkcijfers. Druk opnieuw `<leader>kv`; daarna openen gewone artikelbuffers. Vanaf 15 reacties wordt Meta eerst geprobeerd en anders de handmatige link-/plakroute aangeboden. Zonder reactietekst wordt niets over reacties geschreven. |
| buffer-lokaal `<leader>kf` / `:MeestgelezenFotos` | Downloadt direct voor alle overgebleven keuzeregels precies één hoofdfoto naar `Bureaublad/meestgelezen`; er volgt geen tweede keuzemenu en volledige galerijen worden niet opgehaald. |
| `<leader>kh` / `:ContextHelp` | Toont dynamische hulp voor de huidige workflowfase: status, aanbevolen vervolgstap, andere hoofdopties en het gevolg daarvan. Werkt onder meer bij krantversies, publicatiereview/-herstel, agenda, rubriekexport, doublurecontrole en Meestgelezen. Zonder herkende context verwijst de melding naar de algemene `<leader>ah`-hulp. |
| `<leader>aq` | Annuleer alle actieve editor-AI-taken van de huidige buffer. |
| `:AICancel` | Zelfde expliciete annulering als `<leader>aq`. |
| `<leader>kl` / `:TexttoolsActiviteit` | Open of sluit de meldingenhistorie op afroep. Aandachtmeldingen staan bij de controleregels boven het artikel. |
| `:TexttoolsActiviteit!` | Wissel tussen de kleine strook en het uitgebreide artikel-logboek. |
| `:TexttoolsLog` | Toon de veilige tijdlijn van het huidige artikel: handelingen, duur, uitkomst en een eventueel onafgesloten proces. |
| `:TexttoolsLog!` | Toon de laatst gelogde Texttools-workflow, ongeacht de huidige buffer. |

De datum achter de krantwerktitel en vaste rubriektitels gebruikt Nederlandse
notatie: `19-10-26` voor 19 oktober 2026. Technische datumvelden blijven ISO;
een ongewijzigde herpoging houdt dezelfde bewerkdatum.

Ook rechtstreeks plaatsen met `<leader>aw`, zonder herschrijven, controleert
de volledige metadata: korte inhoudstitel en inhoudelijke houdbaarheid. Als die
ontbreekt, vraagt de gedeelde Python-kern dezelfde analyse op als na herschrijven,
zonder de artikeltekst te veranderen. Een bestaande `x` en werktitel zijn op
zichzelf niet voldoende. Vaste rubriektitels en bewuste eigen werktitels blijven
behouden. Nieuwe analyse wordt vóór de eerste CMS-create opgeslagen en bij een
ongewijzigde herpoging hergebruikt. De bewerkdatum blijft lokaal bepaald.

Meldingen hebben drie vaste bestemmingen:

De audit, het meldingenbeleid en de afweging rond een kort log onder de
artikeltekst staan in [NOTIFICATIES.md](NOTIFICATIES.md).

- **Lopend werk:** ondoorzichtige Fidget-meldingen met dezelfde bewegende stippen
  vóór iedere lopende taak. Elke actieve soort taak staat op één regel;
  gelijke taken per artikel zijn gebundeld.
  Maximaal vijf regels zijn tegelijk zichtbaar. Taken van een ander artikel
  krijgen de bronnaam. Een bevestigde uitkomst blijft nog acht seconden staan:
  `✓ Artikel herschreven`, `✗ Herschrijven mislukt` of `– Herschrijven niet toegepast`.
  Alleen een werkelijk toegepast resultaat krijgt een vinkje; een procesexit
  zonder bevestiging krijgt geen aparte voltooiingsmelding en blijft technisch gelogd. De meldingen nemen
  geen focus; tijdens een keuzescherm wijken ook deze afgeronde regels.
- **Meldingen:** waarschuwingen, fouten en niet-zichtbare bewerkingsinformatie staan als
  echte `Melding:`-regels bij `e:`, `c:` en de overige instellingen, direct boven
  `=== ARTIKEL ===` (ook boven `=== AGENDAPAGINA ===`). Selecteer/kopieer ze
  normaal. Alle artikelgegevens blijven bij elkaar; een witregel scheidt ze
  van het aaneengesloten meldingenblok, met weer een witregel vóór het artikel.
  Verwijder meldingen met `dd`. Ze staan in werkbestand en undo, maar nooit in
  AI-invoer of publicatie. Verwijderen verbergt alleen de regel, niet de
  onderliggende controle. Alleen een werkelijk probleem krijgt `LET OP`, met
  de vervolgstap. Succesvol aangemaakte agenda-/socialteksten staan al zichtbaar
  in het document en krijgen geen extra meldingsregel. Wel staat er welke
  redigeermethode is gebruikt (`ar`, `an` of `ap`). De geschiedenis van alle uitkomsten staat
  achter `<leader>kl`; die opent standaard uitgebreid en uitsluitend op afroep.
  Technische diagnose blijft via `l` / `:TexttoolsLog` bereikbaar.
- **Beslissingen:** de centrale menulaag. Workflowkeuzelijsten gebruiken één
  native vormgeving; alleen echte keuzes onderbreken het werk. Een advies zoals
  “verwijder ongeveer twintig agendapunten” blijft bij het artikel, zonder popup.

Lange samenvattingen eindigen zo nodig op `…`; het uitgeklapte logboek toont
de volledige resultaattekst. Tijdens een zwevend menu wijken de taakmeldingen,
terwijl de registratie van het achtergrondwerk doorloopt.
Waarschuwingen openen geen apart venster en nemen de cursor niet over.
Een automatische melding wordt pas ingevoegd nadat geregistreerd achtergrondwerk
klaar is en er geen keuzescherm actief is. Read-only reviews en bronnen zonder
artikelgrens houden de virtuele fallback, zonder bestandsmutatie. Gewone
Texttools-resultaten blijven in de historie, nooit als Fidget-resultaattoast.

Importadvies over meerdere plaatskoppen staat ook in dit logboek, zonder losse
Apple-/macOS-melding. De gedeelde Python-inspectie zondert agendaverzamelingen
uit. Het advies controleert alleen de actuele importtekst en splitst niets
automatisch.

Ga met `<C-j>` of de muis naar het paneel. `e` opent het uitgebreide logboek
(nogmaals `e` maakt het compact), `l` opent de technische tijdlijn en `q` sluit
echt, ook tijdens werk. De taakmeldingen blijven staan; taken worden niet
ook in de logboekkop of statusbalk herhaald. De bestaande
toets `a` markeert meldingen in de historie als gelezen, niet als opgelost;
een niet verwijderde meldingsregel van een onopgelost aandachtspunt blijft staan.
De algemene statusbalktekst `Aandacht nodig` wordt niet meer apart getoond.
Een bevestigde geslaagde herhaling ruimt uitsluitend de melding van dezelfde
actie op. Een oud resultaat kan geen nieuwere fout wissen. Meldingen zonder
actiekoppeling worden niet door willekeurige successen gewist. De geschiedenis
blijft beschikbaar. Keuzevensters en bestaande publicatiecontroles blijven leidend.

Datumgoedkeuring en alleen een gewijzigde `Melding:`-regel veroorzaken geen
herstelconflict. Werkelijke tekst-, foto- of agendawijzigingen blijven beschermd.
Een herstelbestand houdt ook de geplande lezersnieuwsexport vast. Achtergronden
en het ongewijzigde regionaliseringsonderzoek staan in
[ONDERZOEK_IJSSELDELTA.md](ONDERZOEK_IJSSELDELTA.md).

Bij teruglezen blijft dezelfde melding onder de cursor, ook wanneer het logboek
zijn limiet bereikt. De compacte/uitgebreide voorkeur blijft lokaal bewaard;
na een herstart blijft de historie dicht totdat je haar opvraagt. Andere
editor-/pluginmeldingen behouden hun eigen kanaal.

De geschiedenis volgt het bronartikel, ook vanuit foto-, archief- en
krantreviewbuffers. Ze bewaart maximaal honderd meldingen per open artikel in
de huidige NeoVim-sessie en wordt nooit aan het artikelbestand toegevoegd.
`:TexttoolsLog` blijft het duurzame, technische diagnosekanaal; open dit na een
herstart voor eerdere runs. De nieuwe weergave voegt geen AI-/netwerkcalls,
subprocessen of polling toe. Ook asynchrone Texttools-subprocessen zonder
bestaande workflowtrace worden lokaal als lopend geregistreerd; getraceerde
taken worden niet dubbel geteld. Bijwerken gebeurt via bestaande callbacks en
gebundelde redraws; alleen de weergavevoorkeur wordt bij bediening opgeslagen.

Gevalideerde resultaten verschijnen als `OK:` in de geschiedenis.
Een volledige doublurecontrole zonder treffers meldt dat expliciet, net als
de agenda-doublurecontrole en de tekst-/datumcontrole. Overgeslagen, onvolledige
en verouderde controles krijgen geen onterechte melding dat niets is gevonden.
Gevonden mogelijke doublures krijgen geen `OK:`. De Python-kern beschrijft
per editie **Concept opgeslagen**, **Ingepland voor …** of **Online gepubliceerd
volgens Pubble**, op basis van de bestaande CMS-respons, zonder extra websitecheck.
Een onbekend publicatiemoment krijgt geen onlineclaim. Bij een mislukte verzending
kan de noodrem webartikelen weer offline zetten; daarom komt dan geen positieve
webbevestiging. Een oudere kern krijgt een veilige algemene opslagmelding.
Pas na alle vervolgstappen volgt de aparte afrondingsmelding. Fouten bij media,
Teams of archivering blijven zichtbaar.

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
wordt behouden of toegevoegd: centrale plaats, anders provincie, anders REGIO. In de
rest maakt de AI de kleinst mogelijke ingreep: subjectieve, promotionele of
overdreven journalistentaal en directe lezersaanspraak verdwijnen, zonder een
volledige rewrite. Alleen een expliciet aan een bron gekoppelde claim mag
indirect worden toegeschreven; er worden nooit nieuwe directe citaten gemaakt.
Ook ik-/wij-taal van de afzender wordt buiten citaten derde persoon of zakelijk
onpersoonlijk. Praktische lijstjes (datum, locatie, aanvang, kaarten) worden
op dezelfde plek aaneengesloten tekst; openingstijd en aanvang blijven apart.
Lege promotionele zinnen/alinea's en reclamekopjes mogen verdwijnen, niet de
feitelijke kern. Goede formuleringen, alinea's, details en nuttige koppen
blijven zoveel mogelijk staan; AN kort niet standaard in. Voor alleen
objectieve taalfouten is er `<leader>ao`; voor ruimere redactie en lokale
krantvarianten `<leader>ar`. Er komt geen extra menu of AI-ronde bij.
De controle vergelijkt unieke bronwaarden, niet het aantal herhalingen;
`achttien` en `18` tellen als dezelfde waarde. Zonder controlepunten volgt de
gewone toepassing. Bij mogelijke wijzigingen van getallen, datums, tijden,
weekdagen, citaten, links of mailadressen opent een vergelijkingstab:
**Onbewerkt** links, **Bewerkt — voorstel ter controle** rechts, met gemarkeerde
verschillen en concrete controlepunten bovenaan. Rechts kun je de tekst aanpassen.
`<leader>aY` / `:ArtikelBewerkingOvernemen` neemt die versie over;
`q` / `:ArtikelBewerkingBehouden` behoudt het origineel. Escape blijft gewoon Escape.
De vergelijking kan niet publiceren en verandert de bron pas na overnemen.
Een gewijzigde/gesloten bron of nieuwere AN-aanvraag maakt een oud voorstel
ongeldig. Getalsrollen worden niet semantisch bewezen. Geen extra AI-ronde.
Na toepassen geldt de controle alleen voor de exacte body; de normale
herschrijfnacontrole volgt ook na het overnemen van een voorstel.

AR, AN en AP mogen bij duidelijke aangeleverde website-/nieuwsbronherkomst
onder de artikeltekst één gewone `Bron: bronnaam of website`-regel zetten.
Een losse informatie-/kaartverkooplink of genoemde persoon is daarvoor niet
genoeg. Bestaande bronregels blijven behouden, bij twijfel geen nieuwe regel.
Dit is publiceerbare tekst, niet een besturingstag boven `=== ARTIKEL ===`.
Geen extra AI-ronde of online zoekactie; de optionele bronregel is geen reden
om een verder goede body alsnog volledig te herschrijven.

Voor een complete papieren agendapagina plak je alle dagen en activiteiten en
gebruik je eenmaal `<leader>ka`. Gewone items worden per activiteit geredigeerd;
`>>>titel<<<` is premium: de kop blijft exact staan, de body krijgt een aparte,
behoudende journalistieke AI-taalcorrectie. Geen samenvatting of vrije
herschrijving; bestaande tijden, locaties en adressen blijven intact, ook in
de body. Alleen ontbrekende praktische velden mogen worden aangevuld.
De kern controleert concrete waarden/citaten en herkenbare locaties/adressen;
premium wordt nooit ingekort tot `Zie hierboven.` Controleer de
zichtbare datum, titel, tijd, locatie en body (`hele dag` mag). Voor de
printbody geldt geen technische lengtegrens; gewone tekst wordt wel compact
geredigeerd. Gewone koppen worden zoveel mogelijk 3–4 woorden en zijn maximaal 5
woorden. De Pubble-uitvoer verdeelt gewone koppen over maximaal twee regels
van 27 tekens en houdt herkenbare woordgroepen en naamverbindingen bijeen waar
dat past. Een betrouwbaar herkend los slotblok wordt automatisch als complete
activiteit opgebouwd en onder zijn primaire datum gezet. Een volledig gewoon
item met een ondubbelzinnige andere primaire datum verhuist ook; secundaire
data in de body niet. Alles blijft zichtbaar ter controle. Druk daarna
`<leader>aw`. Kies dan de krant; de technische controle
draait automatisch vóór de print-only verzending. Dit maakt uitsluitend het
printconcept `!agendapagina`; `ONTBREEKT` blokkeert verzending. Losse controle
en blokpreview blijven alleen als technische `:AgendaPagina…`-opdrachten beschikbaar.
Bij import en na voorbereiding verschijnt een omvangmelding in het artikel-logboek:
het aantal alinea’s/blokken, het aantal agendapunten en boven de richtgrens van
166 een schatting van het aantal nog te verwijderen punten. Tel na je eigen
wijzigingen opnieuw met `<leader>km` of `:AgendaPaginaOmvang`; opslaan is niet nodig.
De telling volgt de Pubble-opmaak: datumkoppen plus titel, tijd/plaats en tekst
per punt, met één scheidingsblok tussen punten. Ruwe importcijfers zijn voorlopig.
Dit is een globale blokschatting, geen voorspelling van teksthoogte; er wordt
niets automatisch verwijderd en de meting is geen verzendblokkade.
Sterk gelijkende items op dezelfde dag verschijnen vóór verzending als
mogelijke doublures; kies na controle `Toch verzenden` of veilig `Annuleren`.
Na de gecontroleerde Pubble-opslag verschijnt de directe krantartikellink in
de melding en bovenin de agendapagina. Een bestaand artikel-ID zonder die link
wordt door `<leader>aw` veilig hersteld in plaats van opnieuw aangemaakt.

Bij een verzendfout wordt een oudere herstelversie nooit over nieuwere
tekst-/agenda-/fotowijzigingen gezet. In zo'n conflict opent `<leader>aw` eerst
het ID-bevattende herstelbestand in een apart venster, zonder verzending.
Neem gewenste wijzigingen daarin over, behoud de Pubble-ID's en hervat vanuit
dat herstelbestand. Je oorspronkelijke werkbuffer blijft intact. `<leader>kh`
legt deze situatie uit; `:TexttoolsLog` toont de herstelreden en foutcategorie.

---

## Controlecodes

Boven `=== ARTIKEL ===` typen. `pv` plaatst die grens automatisch; de kop staat
eronder. `<leader>ah` voegt een gekozen code automatisch boven de grens in.

```
editie: B          # of SW, ST, Z, D, K, all, overijssel, flevoland
wijk: Berkum       # SW: ontbrekend = automatische controle; leeg/Heel Zwolle = hele stad
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

Voor `SW` start een ontbrekende `wijk:`-regel bij `<leader>aw` automatisch de
deterministische wijkcontrole. Zonder signaal wordt `wijk: Heel Zwolle`
zichtbaar ingevuld; bij één wijknaam of straatmatch bevestig je het voorstel
in een verplicht menu. Een lege regel en `wijk: Heel Zwolle` betekenen bewust
de hele stad. `wijk: auto` forceert de controle en vult een eenduidige match
direct in. De zichtbare regel wint van oude technische metadata en blijft na
verzending behouden. De veilige diagnose staat in `:TexttoolsLog`.
Controleer een gekozen wijk opnieuw als je later de artikellocatie wijzigt.

De controle leest de hele artikelbody, zonder te stoppen na drie straten of een
horizontale scheidingslijn. Een hobbymarkt is geen straatnaam; nul adresmatches
mogen één duidelijke wijknaam niet afkeuren. Bij een echte twijfel staan de
gevonden wijken bovenaan met bewijscontext. Het online zoekbudget is begrensd;
nog niet gecontroleerde adressen blijven zichtbaar en eigen cachetreffers
verderop blijven meetellen. Gebruik `wijk: auto` om een oude keuze te herzien.

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

De volledige Overijssel-selectie (B/SW/ST/K, ook uitgeschreven codes) kan één
gedeelde regiomelding sturen. Die vervangt alleen losse waarnemingsmeldingen
aan dezelfde ontvanger; vaste redacteuren houden hun eigen melding. Ontvanger
en tekst staan buiten Git in de gedeelde Teams-config. @none en concept blijven
alle meldingen onderdrukken; retries sturen reeds geslaagde meldingen niet dubbel.

Bij een vervanger in `:TeamsRedactie` kies je een hersteldatum (voorstel:
over één week) of `Voor onbepaalde tijd`. De datumkiezer gebruikt dezelfde
weeklijst als de online artikelplanning. Op of na de gekozen datum vraagt een
overlay of de **vorige ontvanger** teruggezet mag worden. Er gebeurt niets
zonder akkoord; bij behouden komt de vraag de volgende dag opnieuw.
Onbepaalde waarneming geeft een korte opstartmelding, eenmaal per dag per Mac.
De controle loopt ook na middernacht als Neovim open blijft. Persoonsgegevens
en de hersteldatum staan gedeeld in iCloud; de dagelijkse meldingsmarkering is
lokaal. Herstart Neovim om de opstartcontrole na een update te activeren.

Als `<leader>ar` een letterlijke fotocredit of een bijschrift uit de brontekst
haalt, verplaatst de nabewerking zowel `Foto:` als `Bijschrift:` automatisch
naar dit beschermde blok boven `=== ARTIKEL ===`; ze blijven nooit in de
artikelbody staan.

AI-stockfoto: zet de ChatGPT-download(s) in Pubble Inbox en keer terug naar
Neovim. Binnen de nog actieve AI-fotoroute opent het tagscherm automatisch voor
nieuw binnengekomen beelden, niet voor reeds aanwezige foto's. Geen download?
Dan geen leeg scherm; er wordt pas bij de volgende terugkeer opnieuw gekeken.
Na wegklikken blijft het dicht: `i` in de fotokiezer (of de browserimportknop)
opent het opnieuw. Zonder AI-route blijft `i` een handmatige importactie.
Je vult alleen tags in (minimaal één,
zonder vast maximumaantal; dubbele tags worden verwijderd);
bestanden worden ter controle getoond, uniek hernoemd en allemaal met dezelfde
tags voorbereid voor algemene beeldbank 24. Een fout houdt de tags vast en
toont een blijvend venster. Pas na opgeslagen import worden Inbox-originelen
herstelbaar weggezet. `<leader>aw` publiceert later: agenda één hoofdfoto,
web/krant/schaduw alle foto's. Geen nieuwe AI-aanroep voor de import.

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
bij onderscheidende gebiedssignalen of je **Gerichte varianten** of **Eén
algemene versie** wilt, met een kort advies. Zonder onderscheid volgt één
algemene versie. Eén AI-call per unieke tekst; kranten met dezelfde tekst
delen een reviewbuffer. De gewone body blijft bij meerdere teksten de gedeelde
bron en wordt niet gepubliceerd. Een echte lokale bijdrage kan de lokale
kop/intro dragen; een terloopse plaats krijgt geen geforceerde invalshoek.

Geen extra keuze over redactie: `<leader>an` blijft minimaal publicatieklaar
maken, `<leader>ar` journalistiek herschrijven en krantgericht maken. De
bestaande schrijfprompt beoordeelt de bron in dezelfde call. Bij een al goede
body kopieert Python de bronalinea's; kop/intro en eventueel ordening kunnen
voor de krant veranderen. Ruwe/promotionele/anderstalige tekst kan wel volledig
worden geredigeerd. Een andere lokale opening alleen is geen reden voor een
body-rewrite. Controleer de nieuwe tekst inhoudelijk. Foto's/bylines en gewone
huisstijlopmaak blijven. Een ongeldig intern plan behoudt de bron zonder tweede
schrijfcall. `<leader>aA` maakt één algemene tekst zonder editie-menu.
Geen extra classifier of auditcall; werkelijke wachttijd is nog te meten.

Sla een versie op met `:w`; bestaande goedkeuring blijft behouden. Een nog niet
goedgekeurde versie blijft `controleren`; keur haar goed met `<leader>aG`.
`<leader>aV` toont de bron en alle statussen. Correcties en toegevoegde socials
behouden het akkoord; alleen een toegepaste AI-herschrijving vraagt opnieuw
review van die variant. Een edit in de gedeelde bron maakt
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

Nieuwe metadata bewaart de volledige evenementperiode, ook zonder agenda-item:
20–22 oktober is op 21 oktober nog lopend. Een brongebonden metadatacache wordt
vóór de planning veilig met fotogegevens samengevoegd; nieuwere tekst maakt de
cache ongeldig. Het kranttijd-overzicht toont per editie krantdatum, periode en
fase. Je kunt alle getoonde edities herschrijven of web-only houden, of alleen
afgelopen edities web-only houden en de overige meteen laten herschrijven.
Reeds goedgekeurde edities worden niet opnieuw bevraagd. Oudere metadata zonder
einddatum houdt de eendagsfallback totdat metadata opnieuw wordt verzameld.

"Herschrijven voor krant" geldt tevens als toestemming voor de
aankondigingsdeadline van dezelfde gebeurtenis: na de controle van die
krantvariant volgt geen tweede "Toch ook naar de krant". De kern bewaakt bron,
datums en editie; een andere deadline of handmatige uiterste week blijft een
aparte keuze. Geldige bestaande krantvarianten werken ook na opnieuw openen.

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
blok vanaf `## Kalender`. De voorbereidingskeuze wordt in het werkbestand
bewaard: ook na heropenen maken `<leader>ar` en `<leader>aw` een bewust verwijderd
blok niet opnieuw. Bij de volgende artikelactie wordt `agenda: nee`
vastgelegd en de tijdelijke kalendercache gewist; de vroegere aparte
hoofdletter-C-weigeractie is daarom vervallen. Was er nog nooit een
Kalenderblok en ziet de
laatste lokale controle bij verzenden alsnog een sterke kandidaat, dan vraagt
Neovim eerst. Ja maakt en toont het blok; nee verzendt alleen web en print.
Herkent `<leader>ar` pas later een geschikte activiteit en is er nooit een blok
gemaakt of afgewezen, dan mag het alsnog automatisch voorbereiden, na de
agenda-doublurecontrole. `<leader>ac` kan iedere eerdere automatische keuze
overrulen, maar ontbrekende verplichte gegevens blijven publicatie blokkeren.

Bij `<leader>aw` en alleen-agenda `<leader>kA` worden agenda-items met een
enkelvoudige plaats buiten de gezamenlijke plaatsenlijst overgeslagen, met
een melding. Het hoofdartikel en overige lokale items kunnen doorgaan;
bronblokken en bestaande IDs blijven staan. Zwolle is ook bij B/ST toegestaan:
de controle gebruikt het gezamenlijke gebied, niet alleen de gekozen krant.
Lege/samengestelde plaatsen en ongeldige lokale data moeten wel worden aangevuld
of gecorrigeerd. Controleer bij een overgeslagen plaats ook de spelling.

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

Je kunt ook eerst herschrijven en daarna de `e:`-regel aanpassen of een editie
toevoegen. `<leader>aw` beoordeelt de actuele bestemmingen. Bij een voorbereid
Kalenderblok wordt de verzendcontrole eenmaal afgerond vóór de verzending
doorgaat; een al afgeronde controletaak veroorzaakt geen lus in ‘Edities bepalen’.
Een wijziging tijdens of vlak na de beoordeling stopt die poging veilig en
vraagt opnieuw `<leader>aw`. Herstart NeoVim om deze clientcorrectie te laden;
bewaar eerst je nog niet opgeslagen tekst.

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

Bij een datumgebonden aankondiging heet de krantkeuze direct **Herschrijven
voor krant [h]**. Daarmee start dezelfde kranttijdvoorbereiding en volgt geen
tweede bevestiging voor dezelfde gebeurtenis. Voor gewone houdbaarheidsgrenzen
blijft de keuze **Toch ook naar de krant [t]**. `t` werkt ook nog bij de
herschrijfkeuze; `w` kiest alleen website en Escape annuleert.

Komt de deadline pas na metadatageneratie in beeld, dan biedt `<leader>aw`
dezelfde keuze alsnog aan. De gekozen webdatum, reeds gemaakte kranttijdtekst
en eerdere beslissingen voor andere kranten blijven bewaard. Na je keuze hervat
de verzending zonder opnieuw te herschrijven.

De krantdeadlinekeuze verschijnt asynchroon boven de tekst, met de reden voor
de grens. Kies met `j`/`k` en Enter, 1–3 of `w`/`t`/`a`; Escape annuleert.
Navigatietoetsen schrijven geen herhaalde keuzeregels. Een antwoord na een
tekstwijziging stopt de verzending. Bij actueel nieuws krijgt iedere krant haar
eigen eerstvolgende wekelijkse cyclus: op 6 oktober 2026 B week 42, SW week 41.
Een zichtbare kalenderdatum corrigeert ook eerder gecachete krantwerktitels;
handmatige `week:`-keuzes en vaste `z`-rubrieken blijven behouden.

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
De losse directe actie `<leader>ax` gebruikt bij een eerdere `<leader>pf`-keuze
juist het originele Pubble-beeld en downloadt dit onder de gevraagde
vormgevingsnaam. Zonder zo'n selectie blijven de losse Pubble Inbox-foto's de
bron. De downloadroute doet drie read-only netwerkacties en geen AI- of
Pubble-write; NeoVim blijft tijdens de asynchrone export bruikbaar.

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

Heb je tijdens de voorbereiding of publicatie verder getypt, dan worden je
nieuwere tekst, agenda en fotokeuze niet als gepubliceerd gemarkeerd. Het
werkbestand blijft staan en de buffer blijft bewerkbaar, met een duidelijke
waarschuwing dat deze wijzigingen **niet** zijn meegepubliceerd. Een duurzame
blokkade voorkomt opnieuw plaatsen, ook na heropenen. `<leader>aw` biedt dan
alleen de gepubliceerde archiefversie ter vergelijking aan, in een apart
alleen-lezen venster. Verwerk gewenste correcties bewust in Pubble.

Na volledig succes bewaart `~/Documents/Pubble Archief/<jaar>/<maand>/` een
leesbare versie met titel en weblinks, zonder technische frontmatter.
Vóór volledige afronding blijft het aparte herstelbestand met Pubble-ID's de
bron voor hervatten en evenementvervolgen. `TEXTTOOLS_ARCHIVE_DIR` kan naar
een gesynchroniseerde cloudmap wijzen; het standaardpad mag ook een symlink
naar die cloudmap zijn. Archiveren en Telescope gebruiken dezelfde instelling.

- `<leader>pa` / `:PubbleArchief`: zoeken op artikelbestand;
- `<leader>ps` / `:PubbleArchiefZoek`: zoeken door alle artikelinhoud.

---

## Achtergrondtaken

Vóór de eerste verzendcall wordt een kleine herstelverwijzing naast de bron
opgeslagen. Lukt dat niet, dan wordt niets verstuurd. Na het verwijderen of
heropenen van een buffer leidt `<leader>aw` naar dezelfde bewaarde Pubble-status;
een nog lopende run kan niet vanuit een tweede buffer worden gestart. Ontbrekende
of onleesbare hersteldata geeft een blokkade, nooit stil een nieuwe verzending.
Bewaar die herstelverwijzing en het statusbestand tot de run is afgerond.

Archiveren, dateline/redactieadres en kopinspectie/-plaatsing wachten niet meer
synchroon in de editor. Documentresultaten worden alleen op de ongewijzigde
bufferrevisie toegepast. Lokale documentacties hebben 3 seconden procesbudget;
export en archivering 60 seconden. Een time-out is geen bewijs dat er niets is
geschreven: de herstelroute blijft leidend. De archiver behoudt het ID-bestand
totdat de voltooiingsmarker is opgeslagen; pas daarna volgt de opruiming.
Bij startfouten komen de betrokken verzendvlaggen vrij en blijft hervatten veilig.

`<leader>ar` kan meerdere AI-aanroepen tegelijk starten. `buffer_jobs` houdt
de bufferwijzigende taken bij met unieke tokens en herkenbare actienamen.
Een taak kan uitsluitend zichzelf afronden; een dubbele of late afronding
kan geen andere taak afmelden. `vim.b[buf].pending_jobs` blijft beschikbaar
als afgeleide compatibiliteitsteller, maar beslist niet meer over verzending.
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

Pubble-fouten tonen een HTTP-status, een vaste Nederlandse categorie en waar
beschikbaar bekende validatievelden/-codes. Vrije serverteksten en meegeëchode
artikelinhoud worden niet overgenomen. Dezelfde veilige informatie staat in
`:TexttoolsLog`. Onbekende servermeldingen blijven daarom bewust algemeen.
Werk Texttools en deze client samen bij en herstart NeoVim zodra geen taken lopen.

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

Workflowkeuzelijsten gebruiken dezelfde native overlay: kies met pijltjes,
`j`/`k`, Enter of nummers 1–9. Escape annuleert een handmatig geopend menu.
Telescope blijft beschikbaar voor echte zoekschermen zoals het archief,
maar bepaalt niet langer de vormgeving van workflowbeslissingen.
Verplichte asynchrone overlays vereisen een expliciet antwoord: Escape, Ctrl-C
of `q` bij een keuzelijst stelt de vraag uit. De handeling wacht dan op je
antwoord; `:TexttoolsVraag` of `v` in het logboek hervat haar met behoud van
invoer en selectie. Uitstellen is nooit toestemming of afwijzing. Invoervelden
gebruiken eveneens de centrale overlay boven de tekst. Escape gaat daar alleen
naar Normal, ook bij herhaald drukken; Ctrl-C annuleert of stelt verplichte
invoer uit. Escape stopt geen lopende achtergrondprocessen. Ook oude ja/nee-
en persoonskeuzes gebruiken nu die overlay via asynchrone UI-acties, zonder
blokkerende wachtlus. Alleen headless tests behouden de native antwoordinjectie.
Lange uitleg kan met Ctrl-U/Ctrl-D worden gescrold.
De handmatige tekstversiekeuze van `<leader>ar` blijft asynchroon: de editor
wacht niet in een geneste invoerlus en Escape annuleert de rewrite veilig.

Goedgekeurde krantversies blijven bereikbaar via `<leader>aV` of `:Krantversies`.
Handmatig wijzigen of socialtekst toevoegen vereist alleen :w; goedkeuring blijft
behouden. Na een nieuwe AI-herschrijving is opnieuw `<leader>aG` nodig.

Maak met `<leader>ac` een agenda-item vanuit de gewenste krantversie. Controleer
het kalenderblok en sla op met `:w`; keur met `<leader>aG` goed als dat nog niet gedaan is.
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

Installeer eerst Texttools met `uv sync --locked` in die repository. De runner
gebruikt `TEXTTOOLS_ROOT` (standaard `~/workspace/texttools`), `NVIM_BIN`
(standaard `nvim`) en `PYTHON_BIN` (standaard `python3`). Hij werkt vanuit iedere
werkdirectory, isoleert state/cache/logs per test en draait zonder API-secrets.
Python-subprocessen mogen geen externe sockets verbinden; loopback/Unix sockets
voor lokale tests blijven toegestaan. Een geblokkeerde netwerkpoging maakt de
test rood, ook wanneer de applicatie de fout opvangt. Dit is een testvangnet,
geen beveiligingssandbox voor willekeurige native programma's.

Iedere test krijgt maximaal 60 seconden, waarna ook achtergelaten subprocessen
worden gestopt. De overige tests draaien door; iedere failure geeft een rode
eindstatus. Gericht herhalen kan met:

```bash
bash tests/run_headless.sh duplicate_stages.lua edition_detection.lua
```

De volledige runner voert de snelheidsbenchmark afzonderlijk uit ná alle
functionele tests. Gericht meten:

```bash
bash tests/run_headless.sh benchmarks/article_recognition.lua
```

De herkenningsbenchmark gebruikt dezelfde invoer en grens van 5 ms als voorheen,
maar met 30 opwarmrondes en de mediaan van vijf reeksen van 200 scans. Het
bereik wordt ook afgedrukt. Draai hem zonder gelijktijdige zware tests/builds;
de runner kan belasting door andere programma's niet uitsluiten. De langere
meting voegt alleen enkele seconden testtijd toe, geen productiewerk.

De eerdere instabiliteit in die twee tests is opgelost door de onafhankelijke
agenda-/herkenningsadapters te mocken. De editie-integratie blijft de echte
Python-resolver gebruiken; de bestaande assertion-timeouts zijn niet verhoogd.

`.github/workflows/ci.yml` draait dezelfde suite op pushes naar `master` en
handmatig op `master`. Hiervoor is `TEXTTOOLS_READ_KEY` vereist: een aparte
**alleen-lezen deploy key** op `Wet-Senker/texttools`, waarvan de private helft
als Actions-secret op deze NeoVim-repository staat. De workflow meldt expliciet
een fout als die ontbreekt. Geen `pull_request_target` en geen private checkout
bij externe PR's; test zulke wijzigingen lokaal na beoordeling. Checkoutcredentials
blijven niet beschikbaar tijdens tests. Geen uploads van private broncode of logs.
Texttools-CI test op zijn beurt de huidige Python-code tegen de publieke
NeoVim-`master`, zonder extra toegangssleutel. Beide kanten installeren de
Python-dependencies uit `uv.lock` en gebruiken NeoVim 0.12.3.

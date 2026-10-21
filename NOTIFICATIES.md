# Meldingenbeleid en review — bijgewerkt 21 oktober 2026

## Eén web-/agendaoverzicht (21 oktober, actuele route)

Import/herschrijven vraagt `pubble-duplicates --with-agenda`: de gedeelde
Python-actie verzamelt de bestaande web- en agendacontroles vóór één review.
Iedere treffer houdt haar soort, krant, datum en eigen beoordelingsidentiteit.
Ook bij definitief verzenden wordt zo nodig vóór staging samen beoordeeld;
een actuele webcontrole kan met `--skip-web` worden hergebruikt. Na staging
komt nooit nog een agendakeuze die de bron/publicatiekopie uiteen laat lopen.

Vroeg `n` sluit de review meteen: verder bewerken zonder agendabericht, zonder
tweede webbevestiging. De UI-uitkomst `editing_only` verhindert dat deze keuze
webtreffers negeert of een publicatiecontrole als goedgekeurd onthoudt. Bij
definitief verzenden slaat `n` alleen agenda over; webtreffers moeten dan nog
met m/v worden beoordeeld. De blijvende agenda-keuze wordt vóór de
publicatiekopie toegepast. `m` gebruikt voor agenda de bestaande duurzame
paarsleutel en voor web de bestaande sessieuitsluiting. q/v en Escape houden
hun afgesproken contextbetekenis; geen andere AI-taken worden gestopt.
Een mislukte controle wordt met kanaalnaam in hetzelfde overzicht getoond;
treffers van het andere kanaal blijven staan. Ook na m op de laatste treffer
blijft een onvolledige controle expliciet v/q vereisen. Tags, YAML, artikel en
kalender zijn brongebonden; parallelle socialtekst en meldingen niet.
Deze vroege vereenvoudiging voegt geen AI-/netwerkcall, subproces, scan of
wachttijd toe; alleen dezelfde UI-callback handelt het gehele vroege besluit af.
Een brongebonden bewerkingsakkoord voorkomt dezelfde vroege vraag bij ar na
import. Dat akkoord telt nooit bij verzenden; gewijzigde tekst, editie of
kalender maakt het ongeldig. Expliciet ad controleert altijd opnieuw.

Geen nieuwe AI-/matchingregel, scan, dependency of publicatie-write. Twee
bestaande controles draaien begrensd parallel; samen maximaal de vier bestaande
webqueries plus één agendasite-read. Bij beide benodigde controles één
clientsubproces in plaats van twee. Daadwerkelijke latency niet live gemeten.
Ongewijzigde invoer wordt hergebruikt; een gewijzigd kalenderblok kan nog een
gerichte aanvullende agenda-review vereisen. Beide repositories moeten deze
additieve CLI-/JSON-uitbreiding ondersteunen; de oude losse CLI blijft werken.

## Artikelgegevens en meldingen gescheiden (21 oktober)

De zichtbare instellingen blijven bij elkaar in hun bestaande volgorde. Daarna
volgt één witregel, het aaneengesloten blok `Melding:`-regels, nog één witregel
en de artikelgrens. Een later toegevoegde fotocredit kan daardoor niet tussen
meldingen blijven staan. Ook opgeslagen meldingen worden bij heropenen zo
ingedeeld, zonder uit hun tekst nieuwe taak-/publicatiestatus af te leiden.
Geen extra kop/separator die door de gedeelde parser als onbekende instelling
kan worden behandeld. YAML (ook meerregelige tekst) en artikel-/staartinhoud
blijven exact behouden; de cursor volgt zijn bewerkte instelling. Meldingsankers
worden bij verplaatsing behouden, zodat oplossen en dd correct blijven werken.

Dit is clientopmaak, geen nieuwe Python-controleregel. Vergelijkingssnapshots
negeren ook lege regels in het expliciete zichtbare kopblok, zodat de afscheiding
geen vals bewerkingsconflict veroorzaakt. YAML en witruimte in artikeltekst
blijven wel deel van de revisie. Tijdens actieve taken/keuzevensters wordt niet
heringedeeld. Geen nieuwe timers, subprocessen, AI-/netwerkcalls of dependencies.
Wel een lokale lineaire inspectie van het kopblok bij meldingsrefresh; een
bron zonder sessiehistorie leest daarvoor tot de grens in blokjes van 128 regels.
De overhead is niet afzonderlijk gemeten. Artikel-/publicatiecontracten blijven
compatibel; regressies toetsen heropenen, nieuwe instellingen, cursor, ankers,
dd, bronrevisies en uitstel tijdens werk.

## Uniforme taaktekens (21 oktober)

Iedere lopende taakregel krijgt dezelfde bewegende stippen vóór de tekst,
ook bij onbekende actienamen, gebundelde taken, andere artikelen en wachtfasen.
Voorheen stond de animatie alleen bij de groepskop. De bestaande publieke
Fidget-renderhook voegt nu per actieve regel één animatieframe toe; het
groepsicoon blijft leeg. Resultaatregels behouden hun eigen vinkje/kruis/streep
en hun oorspronkelijke achtseconden-TTL. Geen nieuwe timer, taakregistratie,
AI-call, subprocess, scan of Python-contract; lokale presentatie is lineair
in het aantal aanwezige Fidget-items. Native regressies controleren uniforme
animatie, verversing zonder stapeling en lopend werk naast een resultaat.

## Geen generieke klaar-melding (21 oktober)

De neutrale terugval `○ …: proces klaar` was nog zichtbaar na technische
procesexits zonder bevestigde gebruikersuitkomst. Die krijgt nu geen losse
voltooiingsregel; de exit blijft in de bestaande technische tijdlijn staan.
Bevestigde resultaten houden hun concrete tekst en eigen teken, acht seconden
native Fidget-leestijd en dezelfde fout-/annuleringsbehandeling. Geen extra
processen, AI-calls, scans, timers of wijzigingen aan Python-/publicatieregels.
Getest met de mockbackend en de lokaal geïnstalleerde Fidget, inclusief de
late native finish die een verwijderde technische melding niet mag heropenen.

## Kalender voorbereiden is niet publiceren (21 oktober, actuele afspraak)

Deze afspraak vervangt voor agenda-keuzes de eerdere q/ac-beschrijving hieronder.
Import en herschrijven controleren mogelijke agenda-doublures vóór automatische
aanmaak. Vroeg `q` sluit de keuze, laat artikelbewerking doorgaan en onderdrukt
automatisch toevoegen; `n` legt bewust geen agenda vast, `v` bereidt toch voor.
Bij definitief verzenden betekent `q` deze verzendpoging stoppen, `n` zonder
agenda verdergaan en `v` bewust ondanks de mogelijke doublure publiceren.
Een volgende verzendpoging kan opnieuw beoordeeld worden.

`<leader>ac` is een expliciete werkopdracht: altijd een bewerkbaar kalenderblok,
ook bij weinig gegevens, na weigeren/verwijderen of tijdens een andere controle.
Er is daarbij geen extra automatische doublure-/datumkeuze. Lege velden blijven
leeg, zonder verzonnen gegevens. Verplichte ontbrekende gegevens blijven publicatie
blokkeren. Een bestaand blok wordt bij herschrijven behouden. Zonder eerder blok
of afwijzing mag latere herkenning na ar alsnog automatisch voorbereiden.

De gedeelde Python-actie `calendar_preparation` bewaart voorbereid/verwijderd/
afgewezen in versie-1-frontmatter. Verwijderen blijft dus ook na heropenen geldig.
Lua verzorgt asynchroon transport, presentatieregels en revisie-/generatiebewaking.
Kopieën van ongewijzigde meldingen behouden hun anker bij het invoegen van
frontmatter en kalendertekst; opgeloste waarschuwingen verdwijnen werkelijk.

Kosten: geen nieuwe AI-beslislaag. Als ar pas later een nooit gemaakt/geweigerd
agenda-item herkent, mag de bestaande extractie opnieuw starten (gewone
metadata + kalender, twee modelcalls). Daarnaast lokale Python-subprocessen voor
expliciet voorbereiden, veilig toepassen en zo nodig reconciliëren van kalender-
state. Ongewijzigde bronrevisies worden niet opnieuw gereconcilieerd. De laatste
verzendcontrole kan een extra agenda-/editieleesronde vereisen; geen extra writes,
timer, dependency of achtergrondscan. Latency niet afzonderlijk gemeten.

## Agenda-annulering en blijvende taakafrondingen (21 oktober, eerder besluit)

Gereproduceerd: de handmatige agenda-route en de importroute negeerden een
afgebroken beoordeling. De handmatige route kon daardoor een wachtend of later
AI-resultaat alsnog toevoegen. De controle op uitgewerkte kalendergegevens
werd bovendien pas ná het invoegen gestart. Nu wordt hetzelfde voorstel via
de bestaande Python-check beoordeeld vóór invoegen en vóór nieuwe metadata
wordt gecachet. `q` stopt deze poging, wist wachtende resultaten en een wachtende
verzending, en onderdrukt automatisch opnieuw beginnen. Late AI-, resolver- en
keuzecallbacks worden per poging ongeldig, ook na een expliciete nieuwe poging.
Andere AI-processen worden niet gestopt. Een bestaande kalendersectie blijft
bij afgebroken vervanging intact. De annuleringsmelding heeft één vervangbare
meldingssleutel en verdwijnt na een nieuwe geslaagde beoordeling.

- `v`: de getoonde mogelijke doublures bewust negeren en deze actie vervolgen.
- `q`: huidige voorbereiding afbreken; geen nieuw kalenderblok of toestemming.
  Hervatten is een nieuwe bewuste actie met `<leader>ac`.
- `n`: blijvend `agenda: nee` voor dit artikel; web/krant gaan door.

Fidget-voltooiingen werden voor ieder keuzevenster gewist, waardoor hun TTL
werd afgebroken. Ze worden nu alleen via de eigen publieke renderhooks
verborgen. Native Fidget beheert nog steeds de acht seconden vanaf voltooiing;
terugkeren verlengt die tijd niet. Ook taken die tijdens een keuze beginnen of
eindigen blijven correct geregistreerd. De spinner stopt bij klaar; de
resultaatregel blijft tot zijn eigen vervaltijd. Andere notificatiegroepen
blijven ongemoeid. Er is geen tweede voltooiingenregister of nieuwe timer.

Volledige verificatie: 146/146 NeoVim-testbestanden en 3029 Python-tests groen;
de laatste gerichte annulering-/native Fidget-tests zijn daarna herhaald.
Geen extra AI, netwerk, subprocess, scan of retry: de bestaande agenda-check
krijgt het voorgestelde document. Wel kleine lokale generatienummers en
Fidget-renderhooks; overhead niet apart gemeten. Geen live publicatie of
wijziging van het al bestaande kalenderblok uit het gemelde artikel.

## Doublurescherm verduidelijkt (21 oktober)

De venstertitel is één keer `Mogelijke doublures`. Het nieuwe agenda-item staat
eenmalig apart boven de bestaande treffers; bij meerdere nieuwe evenementen
verwijst elke treffer naar het bijbehorende nummer. De lijst toont soort
Agenda/Web, volledige krantnaam en uitgelijnde Europese datum, zonder de kop
na zes woorden af te breken. De soort komt uit de controlebron, niet uit een
internet-bewerklink: de artikel-agendacontrole leest uitsluitend kalenderitems.

Enter/dubbelklik bekijkt beschikbare berichttekst en details binnen NVIM en
beslist niets. Ontbrekende tekst wordt eerlijk gemeld met de optie Pubble te
openen. `n` slaat agenda-aanmaak voor het hele huidige artikel over; web en
krant gaan door. Dit verwijdert geen bestaand bericht. `m` blijft een expliciete
paarbeoordeling; `v` negeert de getoonde waarschuwingen en laat het vervolg door.
`o` opent in dit invoerscherm uitsluitend het geselecteerde bestaande bericht;
de afzonderlijke web-/eigen-agendascans behouden hun hele-groepbediening.

Geen nieuwe matching-/publicatieregel, AI-/netwerkcall of scan. Python levert
additief soort/krantnaam/reeds opgehaalde agendatekst en numerieke webdatums
met behoud van Amsterdamse tijdzone. Oude velden/JSON-versie blijven geldig.
Alleen bij een oude core met kale editiecodes gebruikt de client de bestaande
editiecache (eenmalig lokaal subprocess indien nog leeg).

Laatste verificatie inclusief IJsseldelta- en doublurepresentatiecorrecties:
volledige NeoVim-suite 145/145 testbestanden en Python-suite 3029 tests groen.
De laatste null-/datum-/toetscorrecties zijn daarna gericht herhaald. Inclusief echte
Fidget-integratie, Escape/actief AI-werk en asynchroon herstel. Geen live
AI-/Pubble-proef.

## Akkoord en uitvoering: aandacht boven het artikel

Nick kiest voor aandachtmeldingen bij de controleregels (`e:`, `c:` enzovoort),
direct boven de artikelgrens. Geen vaste strook aan de bovenrand van het
venster. Op nieuw verzoek zijn dit echte `Melding:`-regels: selecteerbaar,
kopieerbaar en te verwijderen met `dd`. Ze staan in het werkbestand en undo,
maar niet in AI-invoer of publicatie. De gedeelde Python-parser accepteert deze
regels uitsluitend boven de expliciete artikelgrens en kent ze geen
publicatiebetekenis toe. Verwijderen verbergt alleen de melding, niet de
onderliggende controle. Dezelfde uitkomst wordt niet steeds opnieuw ingevoegd;
een nieuwe uitkomst kan opnieuw verschijnen. De volledige historie blijft staan.

De bestaande meldingsregistratie voedt `article_notices`; daar worden geen
nieuwe validatieregels ingevoerd. Bijvoorbeeld `c:` typen is op zichzelf geen
reden voor de presentatielaag om een creditfout opgelost te verklaren: de
bijbehorende controle moet het herstel bevestigen. De weergave valideert niet
op iedere toetsaanslag en start geen automatische AI-/Python-/CMS-actie.

Zichtbaar aangemaakte kalender-/Facebook-/LinkedIn-secties krijgen geen extra
succesregel boven het artikel. De uitkomst blijft als technisch detail terugleesbaar.
Een opgeloste waarschuwing wordt opgeruimd, niet vervangen door een succesmelding.
Werkelijk ontbrekende gegevens en problemen blijven zichtbaar met een concrete
vervolgstap. Niet-zichtbare bewerkingsinformatie staat er wel: welke actie de
artikeltekst redigeerde (`ar`: Persberichten bewerken met automatische redactie,
`an`: behoudend/minimale redactie, `ap`: eigen instructie). Een volgende
toegepaste redigeermethode vervangt de vorige. `<leader>kl` opent de historie op afroep.
Automatische kalenderherkenning toont geen ontbreektmelding als er geen
evenement wordt gevonden. Alleen na een expliciete kalenderactie (`<leader>ac`
of dezelfde menuactie) wordt gemeld dat
geen kalenderitem is gevonden, met een vervolgstap. Dit onderscheid blijft
behouden bij uitstel door doublurecontrole of een gelijktijdige bewerking;
echte analysefouten en ontbrekende gegevens van een gevonden item blijven zichtbaar.
De geschiedenis opent niet
meer automatisch bij een fout of bij een volgend editorstart; oude
zichtbaarheidvoorkeuren krijgen daarvoor een compatibele versie-3-migratie.
Zonder artikelgrens en in read-only reviews blijft de veilige virtuele fallback:
geen verzonnen documentstructuur en geen mutatie van gepubliceerde inhoud.

De ankerpositie wordt bij eerste aandacht of een vervangen artikelgrens in de
buffer gezocht. Extmarks volgen de grens en elke eigen meldingsregel. Alleen
bij meldings-/kopblokwijzigingen volgt een update, niet bij iedere bodytoets.
Tijdens geregistreerd achtergrondwerk of een keuze wordt de bron niet door
automatische meldingen gewijzigd. De bestaande refresh past de regels daarna
toe; geen timer, polling of extra proces per toets. Meldingen tellen niet mee
in de inhoudsgebonden snapshots voor de agenda-doublurecache.

## Uitkomst van de inventarisatie

De verwarring kwam uit daadwerkelijke verschillen in routering en bediening.
`texttools_notify.notify` viel terug op `vim.notify`, terwijl `workflow` buiten
een geregistreerde bron eerst Fidget probeerde. Daardoor bepaalde de aanroep
en het moment van setup waar een resultaat verscheen. Planning, Teams,
editie-informatie, contextuele hulp en documentconversie hadden daarnaast
rechtstreekse `vim.notify`-aanroepen. Verplichte keuzelijsten konden niet met
Escape worden gesloten; ja/nee-vragen gebruikten een andere, synchrone route.
Een verzoek om opnieuw te verzenden na een datelinecontrole werd zelfs als
voortgang weggefilterd. Dat was een bruikbare instructie, geen procesanimatie.
De AI-stockroute gebruikte bovendien twee meldingsvensters met uitsluitend
een knop `Begrepen`. Die waarschuwingen staan nu terugleesbaar in het logboek.
De retry/terug-keuze na een mislukte import blijft een werkelijk keuzemenu.

## Vaste betekenis per oppervlak

| Inhoud | Bestemming | Bediening |
| --- | --- | --- |
| Een geregistreerde taak loopt | Fidget met bewegende stippen, ondoorzichtige achtergrond | Acht seconden resultaattekst: ✓ alleen na toegepast succes, ✗ bij fout, – bij annuleren/niet toepassen; geen standaard “afgerond” |
| Fout, waarschuwing, instructie of gebruikte redigeermethode | Echte Melding:-regels boven het artikel | Normale yy/dd; geen dubbele kalender-/socialsuccesregels; verwijderen geeft geen publicatietoestemming |
| Alle uitkomsten en adviezen | Meldingenhistorie via `<leader>kl` | Terugleesbaar op afroep; opent niet automatisch; `e` wisselt uitgebreid/compact |
| Een antwoord is nodig vóór een vervolgactie | Centrale keuzelaag | Enter kiest expliciet; handmatige menu's annuleren met Escape; verplichte overlays stellen met Escape/q uit en hervatten via `:TexttoolsVraag` of `v` in het log |
| Technische diagnose | `:TexttoolsLog` / `l` in het log | Alleen op afroep; geen technisch detail als gewone resultaatmelding |

Gewone resultaten hebben geen automatische verdwijntermijn. Fouten worden
niet door een ongerelateerde succesvolle taak opgeruimd. Gelezen markeren (`a`)
is geen domeinherstel. Een hervatte vraag behoudt bron, selectie en invoerdraft;
uitstellen roept haar vervolgcallback niet aan. De vraag blijft sessiegebonden:
een editorherstart kan geen wachtende Lua-callback hervatten. De bestaande
duurzame publicatie-/herstelstate blijft daarvan onafhankelijk.

Nieuwe meldingen gebruiken `texttools_notify`; `notify` en `workflow` hebben
dezelfde betekenis. Gebruik `kind='progress'` uitsluitend voor een reeds
geregistreerde taak, `kind='success'` voor een werkelijk bevestigd resultaat,
en `attention=true` voor een instructie die niet door de volgende gewone
melding mag verdwijnen. `buf` legt de bron expliciet vast. `bind`,
`schedule_wrap` en `system` behouden die bron over asynchrone grenzen.
Fidget krijgt uitsluitend presentatiehandles uit `task_display`.
De eerdere tekst “afgerond” is vervangen door concrete uitkomsten, bijvoorbeeld
`✓ Artikel herschreven`. Dezelfde taakregistratie bewaart de door de bestaande
callback geïnterpreteerde uitkomst. Een procesexit zonder bevestiging krijgt
geen vinkje en geen generieke voltooiingsregel; die technische exit blijft in
de bestaande tijdlijn gelogd. Dit vervangt de terugval `○ …: proces klaar`.
Gemengde bundels tonen de ongunstigste uitkomst,
nooit het succes van alleen de laatste deelnemer. Fidgets groepsvinkje staat uit;
iedere resultaatregel heeft haar eigen teken. Uitgestelde kalenderverwerking
houdt dezelfde taak-ID vast tot het resultaat geplaatst/geweigerd is, met een
wachtlabel voor doublurebeoordeling of gelijktijdige tekstbewerking.
In invoervelden is Escape
uitsluitend een wissel naar Normal; ook herhaalde Escape roept geen
annuleercallback aan. Ctrl-C annuleert of stelt verplichte invoer uit.
Actief AI-werk stoppen blijft een expliciete actie via `<leader>aq` / `:AICancel`.
De algemene aandachtsindicator in de statusbalk is verwijderd: zonder concrete
uitleg was dat een tweede, onherleidbare plek voor dezelfde waarschuwing.
De uitleg staat bij het artikel; de historie blijft op afroep beschikbaar.

## Centrale keuzes, ook voor oude beslisstappen

De audit omvat alle eigen Lua-/pluginmeldingen, de configuratie en de
importgrens met de shell. De shell heeft geen eigen `display notification`
meer voor plaatskopadvies; dat advies komt via de bestaande importinspectie.
Pluginbuildfouten en de zoxide-editoropdracht in `init.lua` blijven gewone
Neovim/editorberichten, beschikbaar via `:messages`. Externe plugins en
Neovims eigen foutmeldingen worden niet globaal onderschept.

Ook de voorheen synchrone import-/kalender-/112-/rubriekvragen, edities,
verzendbeveiliging, ontbrekende foto, kranttijd, variant-socials, agenda,
Meestgelezen, legacy review, reset, reminders en persoonskeuze lopen nu via
dezelfde overlay. Alleen headless tests behouden de injecteerbare native
bevestiging. Er is geen `vim.wait`-/slaaplus rond een interactieve vraag.

De UI-adapters `user_dialog.keymap`/`command` en de brongebonden callbacks
starten een coroutine. Een oude scalair geschreven beslisstap kan daardoor
haar volgorde behouden: bij een vraag geeft zij de editor vrij, bij een
expliciet antwoord vervolgt alleen die stap. Een werkelijk gesloten/gewijzigde
bron krijgt geen toestemming. De bestaande queue blijft de eigenaar van
open/uitgestelde vragen; een tweede actie op die bron maakt geen nieuwe
verzending of tweede vraag. Registratie is expliciet, zonder globale override
van Neovim-API's. Een vergeten interactieve adapter geeft een programmeerfout,
geen stille terugval naar een prompt onderaan.

Regressies gebruiken echte overlays met een gesimuleerd aangesloten UI,
verbieden `vim.fn.confirm` en bewijzen responsiviteit, uitstellen/hervatten,
nummerkeuze, dubbel indienen en bronrevisiecontrole. De echte `PubbleSend`- en
resetroute starten na een late keuze geen externe mutatie. De bestaande
headless suite toetst daarnaast alle afzonderlijke beslis- en foutpaden.

## Reflectie op de aparte logboekbuffer

De huidige split heeft nuttige eigenschappen: de tekst blijft altijd in beeld,
meldingen blijven staan tijdens scrollen, je kunt teruglezen en tekst kopiëren,
en de artikelinhoud/undo-/opslaggeschiedenis blijven schoon. De prijs is groot
voor een log van twee regels: een eigen buffer, vensterkop, statusregel,
focusbestemming en extra vensterhoogte. De taakanimatie kan daar nog bij komen.
Dat verklaart waarom het technisch correct kan zijn en toch druk aanvoelt.

Gewone logregels aan het artikelbestand toevoegen raad ik af. Dezelfde buffer
wordt opgeslagen, gehasht, door AI gelezen en gepubliceerd. Iedere client en
parser zou die regels dan moeten herkennen en verwijderen. Bovendien zouden
nieuwe meldingen de buffer wijzigen terwijl async acties op een bepaalde
revisie wachten; undo en eigen tekstbewerkingen gaan erdoorheen lopen.

Eerst is een kort virtueel log onder het artikel overwogen. Het uiteindelijk
gekozen ontwerp staat hierboven: belangrijke aandacht bij de instellingen
boven het artikel, de volledige geschiedenis op afroep. Dat sluit aan bij het
vaste controlemoment vóór verzenden. De virtuele regels mogen dus juist met de
tekst meescrollen; een extra vaste strook of wegklik-indicator is niet nodig.

## Kosten en compatibiliteit

Geen extra AI-, netwerk-, CMS- of subprocesscalls, geen bestandsscans in het
meldingspad en geen nieuwe polling of dependency. Uitstel/hervatten gebruikt
de bestaande eventloop en callbacks/coroutines. Per UI-callback ontstaat een
kleine tijdelijke coroutine; per vraag één lokale bronrevisie. Die overhead
is niet apart gebenchmarkt. Het sessiegeheugen voor resultaten blijft
begrensd op honderd meldingen per bron; alleen werkelijk uitgestelde vragen
bewaren een vervolgcallback. Fidgets bestaande animatie is de enige periodieke
presentatie-update tijdens werk. De huidige logboekvoorkeur, artikelbestanden
en Python-resultaatcontracten blijven bruikbaar.

Sinds 21 oktober verwerkt de technische finish zijn UI-afsluiting één eventloop-
ronde na de procescallback, zodat de geplande bufferbewerking eerst haar uitkomst
kan bevestigen. Geen wachtlus/timer/polling. Een uitgestelde clientbewerking
houdt alleen haar eigen bestaande taak vast. Succes/fout/niet-toepassen/annuleren,
gemengde parallelle taken, sluiten en uitstel zijn getest. Artikel-/sectieschrijvers
vervangen alleen het gewijzigde regelbereik: zo blijven meldingsankers bij
onveranderde kopregels bestaan en verdwijnen opgeloste waarschuwingen correct.
Dat kost lokale lineaire regelvergelijking per toegepaste bewerking, niet per toets;
geen publicatie- of herkenningsregel is veranderd. Overhead niet apart gemeten.

Verificatie van de plaatsingswijziging: 131/131 headless-NeoVim-testbestanden
groen, plus een gerichte herhaling van de vijf presentatie-/documentatietests.
De echte terminalweergave is gecontroleerd met synthetische meldingen, ook
voor buffers zonder controleregels. De vorige routeringsstap had daarnaast
186 gerichte Python-contracttests groen. De plaatsingswijziging raakt alleen
clientweergave; geen Python-/publicatiecontract gewijzigd. Geen live AI-, CMS-
of macOS-notificaties uitgevoerd.

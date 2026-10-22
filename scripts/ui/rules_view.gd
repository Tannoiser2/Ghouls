extends Control
## Le regole di Ghouls (dal regolamento Devil's Den del 1992), la lista dei volontari, gli Obiettivi
## e le scelte di questa versione digitale. Si apre dal menu o in partita.

const D = preload("res://scripts/data/gh_data.gd")

var main
var overlay := false
var left: RichTextLabel
var right: RichTextLabel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.02, 0.92 if overlay else 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.dark_style(10, 0.98))
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 70
	box.offset_right = -70
	box.offset_top = 26
	box.offset_bottom = -26
	add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	box.add_child(vb)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var t := UI.title("Le regole di Ghouls", 50)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	hb.add_child(tabs)
	var close := UI.button("Chiudi" if overlay else "Indietro", 170, 50, 21)
	close.pressed.connect(func():
		if overlay:
			queue_free()
		else:
			main.show_menu())
	hb.add_child(close)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 34)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(cols)
	left = RichTextLabel.new()
	left.bbcode_enabled = true
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	right = RichTextLabel.new()
	right.bbcode_enabled = true
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var pages := [["Regole", _rules_a(), _rules_b()], ["Combattimento", _combat(), _end()], ["Pedine e Obiettivi", _volunteers(), _objectives()], ["Versione digitale", _digital(), _credits()]]
	for i in pages.size():
		var b := UI.button(pages[i][0], 230, 46, 19)
		var k := i
		b.pressed.connect(func():
			left.text = pages[k][1]
			right.text = pages[k][2]
			left.scroll_to_line(0)
			right.scroll_to_line(0))
		tabs.add_child(b)
	left.text = pages[0][1]
	right.text = pages[0][2]


func _h(t: String) -> String:
	return "[font_size=28][color=#f5a623][b]%s[/b][/color][/font_size]\n" % t


func _rules_a() -> String:
	var s := "[i]GHOULS è un gioco da tavolo horror per 3 o 4 giocatori ambientato in una tranquilla città moderna, come la tua… Un giocatore guida le orde dei Ghouls alla conquista degli obiettivi principali della città, mentre gli altri rappresentano gli umani nella strenua difesa dell'umanità, della civiltà, della libertà, della propria squadra del cuore, dei politici onesti eccetera eccetera…[/i]\n\n"
	s += _h("Introduzione")
	s += "Il gioco si svolge in turni. In ciascun turno prima muove il giocatore Ghoul, poi muovono i giocatori Umani, infine si risolvono gli eventuali combattimenti. Il gioco termina quando i Ghouls conquistano la [b]Cattedrale[/b], simbolo ultimo della bontà e della virtù, oppure quando gli Umani riescono a trucidare i terribili Ghouls.\n\n"
	s += _h("Preparazione")
	s += "• La tessera [b]Covo[/b] va al centro del tavolo; il Ghoul pesca a caso [b]11 pedine ghoul[/b] e le mette coperte nel Covo.\n"
	s += "• Ogni Umano ha la sua tessera [b]Trasporto[/b] e 5 segnalini numerati del proprio colore.\n"
	s += "• Gli Obiettivi stanno sul tavolo, lato colorato in su.\n"
	s += "• Con 2 Umani: il giocatore alla sinistra del Ghoul pesca pedine Umani finché non ha estratto [b]4 Volontari[/b] e le distribuisce liberamente su [b]2 Obiettivi[/b]; l'altro ne sceglie uno e lascia il secondo a chi li ha preparati.\n"
	s += "• Con 3 Umani: si pesca fino a [b]6 Volontari[/b] e si preparano [b]3 Obiettivi[/b]; gli altri due scelgono in ordine, il terzo resta a chi li ha preparati.\n\n"
	s += _h("Fase del giocatore Ghoul")
	s += "Il Ghoul tira [b]due dadi[/b]: la somma è il numero di pedine ghoul che può muovere. Ogni pedina si muove di [b]una tessera[/b] lungo i tunnel comunicanti. Le pedine ghoul restano sempre coperte.\n"
	s += "Quando dei ghoul escono dalla mappa lungo un corridoio, il Ghoul pesca una nuova tessera fogna e la mette accanto, facendo in modo, per quanto possibile, che i corridoi comunichino e non sbocchino in un muro.\n"
	s += "Ogni volta che si piazza una tessera con un [b]tombino[/b] si pesca a caso una pedina [b]Locazione[/b]: la vedono [b]solo gli Umani[/b]; il Ghoul scopre dove porta il tombino solo quando decide di attraversarlo per assaltare l'Obiettivo collegato. Si può muovere da una tessera all'altra, o da una tessera attraverso il suo tombino direttamente nell'Obiettivo; non si può andare direttamente da un Obiettivo a un altro.\n\n"
	return s


func _rules_b() -> String:
	var s := _h("Fase dei giocatori Umani")
	s += "Ognuno sceglie [b]in segreto[/b] uno dei suoi segnalini numerati (1-5), poi si rivelano insieme.\n"
	s += "• Chi ha giocato il numero [b]più alto[/b] non prende parte al turno (combatte solo se attaccato).\n"
	s += "• Chi ha giocato lo [b]stesso numero[/b] di un altro salta il turno: può darsi che nessuno muova.\n"
	s += "• I segnalini giocati si mettono da parte; quando sono finiti tornano tutti disponibili.\n"
	s += "Chi ha il numero [b]più basso[/b] (e solo lui) pesca una tessera fogna e la piazza a sua scelta, collegata a una già presente. Poi pesca tante pedine Umani quanto il numero giocato e le mette scoperte sul suo Trasporto:\n"
	s += "• la [b]Folla[/b] va invece direttamente su un Obiettivo a scelta;\n"
	s += "• un [b]Rinforzo ghoul[/b] torna nel contenitore Umani e il Ghoul pesca un ghoul che mette coperto nel Covo.\n"
	s += "Poi può muovere [b]un solo gruppo[/b] di volontari che si trovino in una locazione, più i gruppi muniti di [b]Radio[/b]:\n"
	s += "• dal Trasporto a qualunque Obiettivo, da un Obiettivo al proprio Trasporto;\n"
	s += "• da un Obiettivo nelle fogne attraverso il suo tombino; nelle fogne di una tessera a turno.\n"
	s += "Ogni volontario può portare con sé una [b]Mina[/b] o un [b]Punto Vittoria[/b]; le Radio viaggiano libere. I Punti Vittoria portati in un Obiettivo vi restano per tutta la partita. È vietato passare per Obiettivi devastati.\n"
	s += "Chi porta i suoi Volontari in un Obiettivo libero da volontari altrui ne prende il [b]controllo[/b], finché, rimasto sguarnito, non lo occupa un altro. La Folla da sola non dà il controllo.\n"
	s += "Con 3 Umani, poi muove allo stesso modo chi ha il secondo numero più basso (senza tessera fogna).\n\n"
	s += _h("Tessere speciali")
	s += "• [b]Covo[/b]: punto di partenza dei ghoul e luogo dove arrivano i rinforzi. All'inizio del turno chi ha almeno un Volontario nel Covo toglie dal gioco una pedina ghoul (torna nel contenitore) e guadagna un punto.\n"
	s += "• [b]Cimitero[/b]: dopo che è stato piazzato, a inizio turno il Ghoul tira un dado: se esce un numero uguale o inferiore ai ghoul presenti nel Cimitero, se ne aggiunge un altro; con un 6 un ghoul del Cimitero ritrova la Pace Eterna e viene tolto.\n"
	return s


func _combat() -> String:
	var s := _h("Combattimento")
	s += "I combattimenti si risolvono, nell'ordine scelto dal Ghoul, in ogni locazione (Obiettivo o tessera fogna) dove ci sono insieme pedine umane e ghoul. Il Trasporto non può mai essere attaccato.\n"
	s += "Le pedine umane si dispongono scoperte, i ghoul restano coperti e si scoprono solo quando vengono impegnati.\n\n"
	s += "[b]Tiro da lontano[/b] (una volta, solo all'inizio): l'Umano assegna a ogni tiratore uno o più ghoul (più umani possono colpire lo stesso ghoul). Si somma un dado al valore [b]a distanza[/b] (numero a sinistra della pedina); il Ghoul somma un dado alla forza dei ghoul attaccati. Se l'Umano fa di più i ghoul sono eliminati, altrimenti nulla.\n\n"
	s += "[b]Corpo a corpo[/b]: l'Umano attacca con il valore [b]corpo a corpo[/b] (numero a destra) + un dado contro forza + dado dei ghoul:\n"
	s += "• Umani più alti: ghoul eliminati;\n• Ghoul più alti: umani fatti a pezzi;\n• [b]parità: gli umani diventano ghoul[/b]: si eliminano e al loro posto si pescano altrettanti ghoul, che combattono già nel successivo attacco dei Ghoul.\n"
	s += "Poi attacca il Ghoul con le stesse regole, e così via finché in quella locazione resta un solo contendente.\n\n"
	s += "[b]Mine[/b]: quando i ghoul entrano in un Obiettivo minato, la mina esplode ed elimina tanti ghoul (a caso) quanti indica.\n"
	s += "[b]Sorpresa[/b]: se fra i ghoul che attaccano c'è la pedina Sorpresa, niente tiro da lontano: i Ghoul attaccano per primi. Se invece sono gli Umani a entrare dove ci sono già ghoul, la Sorpresa non ha effetto. In entrambi i casi la pedina viene scartata.\n\n"
	s += "Ogni Umano segna un punto per ogni ghoul eliminato. I ghoul eliminati tornano nel loro contenitore; le pedine umane perse escono dal gioco.\n\n"
	s += _h("Obiettivi devastati")
	s += "Se a fine turno in un Obiettivo ci sono solo ghoul, è [b]devastato[/b]: si gira la tessera e si aggiungono i ghoul indicati sul retro. I volontari collegati a quell'Obiettivo, quando verranno pescati, escono dal gioco.\n"
	s += "I volontari combattono con [b]+1[/b] nell'Obiettivo che porta il loro nome.\n"
	return s


func _end() -> String:
	var s := _h("Fine della partita")
	s += "[b]Vincono gli Umani[/b] se tutti i ghoul sono stati annientati, oppure se occupano il Covo per [b]cinque turni consecutivi[/b]. Ogni Umano totalizza:\n"
	s += "• il valore dei propri Obiettivi intatti (somma dei Punti Vittoria × moltiplicatore) + 1 punto per ogni ghoul eliminato;\n"
	s += "• meno il valore dei propri Obiettivi devastati.\n\n"
	s += "[b]Vince il Ghoul[/b] se devasta la [b]Cattedrale[/b]: ogni Umano totalizza solo i punti negativi dei propri Obiettivi devastati.\n\n"
	s += "Il giocatore Ghoul non fa mai punti. Sarà nominato [b]«Gran Trucidatore di Ghouls»[/b] chi avrà più punti quando tutti avranno giocato a turno una partita come Ghoul.\n\n"
	s += _h("Esempio di combattimento")
	s += "Gli Umani hanno Polizia, Atleti, Automobilisti e Medici; il Ghoul 4 pedine coperte, senza Sorpresa.\n"
	s += "• Tiro da lontano: solo la Polizia spara (4) e attacca due ghoul, che si rivelano da 2 e 3 (5). Dadi 4 e 1: 8 contro 6, eliminati.\n"
	s += "• Corpo a corpo Umani: Polizia (4) e Atleti (2) contro un ghoul, Automobilisti (4) e Medici (2) contro l'altro. Il primo è da 5: 4+2+3 = 9 contro 5+4 = 9, parità: Polizia e Atleti diventano due ghoul! Il secondo è da 1 ed è eliminato.\n"
	s += "• Corpo a corpo Ghoul: il 5 attacca i Medici (5+6 = 11, inutile tirare), gli altri due gli Automobilisti (5+3 = 8 contro 4+2 = 6). Non restano umani: il combattimento è finito.\n"
	return s


func _volunteers() -> String:
	var s := _h("Lista dei volontari")
	s += "[i]A sinistra il valore a distanza (— = non spara), a destra il corpo a corpo.[/i]\n"
	s += "[table=3]"
	for k in D.VOLUNTEERS:
		var v: Array = D.VOLUNTEERS[k]
		s += "[cell]%s     [/cell][cell]%s     [/cell][cell]%d[/cell]" % [v[0], "—" if v[1] < 0 else str(v[1]), v[2]]
	s += "[/table]\n\n"
	s += _h("Pedine")
	s += "• [b]Ghoul[/b]: 20 da 1, 15 da 2, 10 da 3, 5 da 4, 3 da 5, più 5 Sorprese.\n"
	s += "• [b]Umani[/b]: 30 Volontari, 18 Folla, 31 Punti Vittoria (16 da 1, 10 da 2, 5 da 3), 11 Mine (5 da 1, 4 da 2, 2 da 3), 4 Radio, 9 Rinforzi ghoul.\n"
	s += "• 10 pedine Locazione, una per Obiettivo; 20 tessere fogna (2 per tipo, più il Covo e il Cimitero) con 10 tombini.\n"
	return s


func _objectives() -> String:
	var s := _h("Gli Obiettivi")
	for k in D.OBJ_ORDER:
		var o: Dictionary = D.OBJECTIVES[k]
		var vols := []
		for v in o["vol"]:
			vols.append(D.vol_name(v))
		s += "[b]%s[/b] ×%d — +1: %s%s\n" % [o["name"], o["mult"], ", ".join(vols), "" if o["dev"] == 0 else " — devastato: +%d ghoul" % o["dev"]]
	return s


func _digital() -> String:
	var s := _h("Comandi")
	s += "• Fogne: rotella per lo zoom, trascina per spostarti, «Centra» per rifare l'inquadratura. Passa il mouse su tessere, Obiettivi e Trasporti per i dettagli.\n"
	s += "• Le locazioni evidenziate in arancio sono quelle che puoi scegliere; in verde la partenza selezionata.\n"
	s += "• Movimenti: clicca la pila di partenza, scegli le pedine nella barra in basso, poi clicca la destinazione. Per salire in un Obiettivo clicca il tondino del tombino sulla tessera.\n"
	s += "• Combattimento: clicca uno o più attaccanti e poi il bersaglio; «Suggerisci» propone un'assegnazione.\n"
	s += "• Con più persone allo stesso schermo, quando si passa dal Ghoul agli Umani (o per i segnalini segreti) compare la schermata «Tocca a…».\n"
	s += "• Vista 3D (pulsante VISTA 3D): trascina col sinistro per ruotare, col destro per spostare, rotella per lo zoom; clic sugli edifici della città per scegliere un Obiettivo, sui tondini dei tombini per salirci.\n"
	s += "• F11: schermo intero.\n\n"
	s += _h("Gioco online")
	s += "Dal menu, «Gioca online»: chi crea la stanza dà il codice di 4 lettere agli amici; i posti liberi li gioca l'IA. Se cade la linea si rientra con lo stesso codice.\n"
	return s


func _credits() -> String:
	var s := _h("Scelte di questa versione")
	s += "• [b]Alba[/b] (regola aggiunta, si sceglie nel menu): se la Cattedrale resiste fino al turno scelto i Ghouls si ritirano e vincono gli Umani, con il punteggio normale. Nel gioco originale non c'è un limite di turni.\n"
	s += "• Se le tessere fogna sono finite e nessun ghoul può più raggiungere un Obiettivo intatto, vincono gli Umani.\n"
	s += "• Le pedine Folla valgono 0 in combattimento; le Sorprese sono pedine ghoul senza forza.\n"
	s += "• I ghoul eliminati dalle mine danno il punto a chi ha portato la mina.\n"
	s += "• Il ghoul tolto dal Covo all'inizio del turno si sceglie fra quelli di una locazione a piacere, a caso.\n"
	s += "• Quando ci sono più Umani nella stessa locazione combattono insieme; decide chi controlla l'Obiettivo (o chi ha più pedine) e il punto va al proprietario dei volontari che attaccano.\n"
	s += "• Ogni attacco ha un solo bersaglio per gruppo; chi nel corpo a corpo non riceve un bersaglio viene assegnato automaticamente.\n"
	s += "• I ghoul possono tornare dagli Obiettivi devastati alle fogne attraverso il tombino.\n\n"
	s += _h("Riconoscimenti")
	s += "[b]Ghouls[/b] — ideazione Marco Ramadori; sviluppo Stefano Ancillai e Marco Ramadori; disegni Luigi Filipponi; editing e grafica Devil's Den. Una produzione Devil's Den S.r.l., Roma, dicembre 1992. Playtesting: Associazione culturale 3d6.\n"
	s += "Caratteri: Creepster (Sideshow) e Jost (Owen Earl), licenza SIL Open Font.\n"
	return s

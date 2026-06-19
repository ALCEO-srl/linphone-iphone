## (Dario Santomaso) Compiling custom BCS version:
Before compiling, install GitHub Desktop if needed (it will help in managing the repository instead of using the command line Git). 
Clone the linphone-sdk repository (git clone https://gitlab.linphone.org/BC/public/linphone-sdk --recursive).
Then, clone the custom belle-sip and liblinphone repositories somewhere. Checkout the branch alceo/5.2. Delete the old belle-sip and liblinphone directories from the linphone-sdk folder, and copy the patched ones you just cloned.

	1. cmake --preset=ios-sdk -G Ninja -B build-ios -DENABLE_LIME_X3DH=OFF -DENABLE_LIME=OFF -DENABLE_ADVANCED_IM=OFF -DENABLE_VCARD=OFF -DENABLE_LDAP=OFF -DENABLE_ISAC=OFF -DENABLE_ILBC=OFF
 	2. cmake --build build-ios
	3. Clone https://github.com/ALCEO-srl/linphone-iphone and checkout alceo/tag/5.2.2 branch
	4. Then "cd linphone-iphone" and give the comand PODFILE_PATH=[PATH_TO_SDK] pod install  (PODFILE_PATH is something like ...linphone-sdk/build-ios)
	5. open linphone.xcworkspace with Xcode to build and run the app.




# BcsPhone iOS — Personalizzazioni rispetto a Linphone

Promemoria delle modifiche apportate al fork iOS di Linphone per adattarlo alla
piattaforma BCS. L'app si sta progressivamente allontanando dall'upstream: alcune
funzionalità di Linphone vengono sostituite con servizi BCS, altre rimosse.

> Riferimento Android: le stesse funzionalità erano già state implementate nel client
> Android (`linphone-android-…bcsws`); su iOS sono state portate adattandole a UIKit/Swift.

---

## 1. Registro chiamate remoto (BcsWs)

**Obiettivo:** sostituire il DB locale di Linphone come fonte del registro chiamate con
l'endpoint REST BCS `/callreport`. La fonte di verità è il server (l'utente può avere più
dispositivi registrati).

**Approccio (come Android):** si scaricano le voci da `/callreport` e si costruiscono
`LinphoneCallLog` **sintetici** via `core.createCallLog(...)`, dati in pasto alla UI dello
storico esistente. Il DB locale non è più usato come storage.

### File
- `BcsWs/CallReport.swift` (nuovo) — modelli REST + `BcsCallReportManager`:
  - `fetchCallLogs` — GET `/callreport` (limit 500) → costruisce i CallLog sintetici sul
    **main thread** (le API del core non sono thread-safe);
  - `postCallLog(call:)` — POST a fine chiamata (mapping `TermReason`/`TermSipReason` →
    stato chiamata, identico ad Android);
  - `clearAll` / `deleteEntry(itemId:)` — DELETE totale / singola;
  - cache di sessione + notifica `BcsCallReportDidUpdate`; l'Id BCS è conservato nel
    `refKey` del CallLog per la cancellazione.
- `BcsWs/BcsWsService.swift` (modifica) — client HTTP riusabile: auth Basic→Bearer con
  scadenza/refresh token, timeout 30s, gestione errori 400/403/404/500; metodi
  `fetchCallReport` / `addCallReport` / `clearCallReport` / `deleteCallReportItem`.
- `Classes/HistoryListTableView.m` — `loadData`/`refreshFromServer` leggono dal manager
  invece che da `linphone_core_get_call_logs`. Spinner + label di stato (caricamento /
  vuoto / errore, localizzate). Cancellazioni → server.
- `Classes/HistoryListView.m` — il cestino cancella **tutto** con conferma (no multi-select);
  rimosso il 3° filtro (conferenze).
- `Classes/HistoryDetailsView.{h,m}` + `HistoryDetailsTableView.{h,m}` — il dettaglio riceve
  il `LinphoneCallLog` direttamente (i log sintetici non hanno `call_id`); mostra tutte le
  chiamate consecutive raggruppate; pulsante "aggiungi ai contatti" nascosto.
- `Classes/LinphoneUI/UIHistoryCell.m` — tap riga e tre-puntini aprono il dettaglio.
- `Classes/Swift/CallManager.swift` — POST del record nel case `.End/.Error`.
- `Classes/LinphoneManager.{h,m}` — espone `bcsWsService`.

### Comportamenti chiave
- Tap su una voce → **apre il dettaglio** (non avvia la chiamata), come Android.
- A ogni ingresso nella view si **forza un refresh dal server** (mostrando intanto la
  cache, niente flicker) per allinearsi a chiamate fatte da altri dispositivi.
- Paginazione: singola fetch delle ultime 500 (il server mantiene max 500 voci).

---

## 2. Rubrica centralizzata (nuova tab)

**Obiettivo:** nuova scheda di ricerca sulla directory BCS (`/directory`), assente in
Linphone.

**Approccio (come Android):** fetch-all una sola volta + filtro **lato client** su tutti i
campi. Scelta deliberata: il server BCS istanzia un thread che rifà la ricerca da zero a
ogni richiesta, quindi la paginazione con `offset` lo stresserebbe e la cancellazione lato
client non fermerebbe il thread.

### File
- `BcsWs/DirectoryResponse.swift` (nuovo) — modello `BcsDirectoryItem` + `BcsDirectoryManager`
  (fetch-all con cache di sessione, `filtered(query)`, ordinamento alfabetico lato client
  sul nome visualizzato).
- `BcsWs/DirectoryView.swift` (nuovo) — UI programmatica (niente xib), composite view Swift:
  - `DirectoryListView` — campo di ricerca + lista (nome/azienda) + spinner; nessuna barra
    titolo (contenuto sotto la barra di stato).
  - `DirectoryDetailsView` — look analogo al dettaglio contatti (avatar + nome + azienda +
    elenco campi). Per l'indirizzo SIP due icone (**chiama** + **chat**), per i telefoni
    una sola (**chiama**); l'azione parte dal tap sull'icona. Chiamata via
    `Core.interpretUrl` + `CallManager.startCall`; chat via `getOrCreateOne(toOneChatRoom:)`.
- `Classes/LinphoneUI/TabBarView.{h,m}` + `Base.lproj/TabBarView.xib` — aggiunto il 5° bottone
  "Rubrica" (3° posizione, in mezzo): Storico · Contatti · **Rubrica** · Tastierino · Chat.
  Bottoni al 20% di larghezza. Layout sistemato sia in **portrait** sia in **landscape**
  (`TPMultiLayoutViewController` abbina le viste per `tag`).
- Icona: `Resources/images/footer_directory.png` (+@2x), importata da Android.

---

## 3. Rimozione permessi non necessari (galleria/foto)

**Obiettivo:** l'app non accede più a galleria e contatti del dispositivo, quindi vanno
eliminate le richieste di permesso residue (come fatto su Android).

### Foto / libreria immagini — RIMOSSA
- Richieste `requestAuthorization` neutralizzate: avvio app (`LinphoneAppDelegate.m`),
  picker (`ImagePickerView.m`), salvataggio in galleria (`ChatConversationView.m` e
  `Classes/Swift/Chat/ViewModels/ChatConversationViewModel.swift`).
- `ImagePickerView.m` — rimossa l'opzione "Libreria foto" e il gate sul permesso foto: il
  selettore offre solo **Fotocamera** e **Documento** (non toccano la galleria).
- Scrittura in galleria governata da `auto_write_to_gallery_preference=0`
  (`Resources/linphonerc-factory`): tutti i path di salvataggio la saltano.
- Avatar disabilitato: side menu (`SideMenuView.m`) → apre le **impostazioni** come il tap
  sul nome; dettaglio contatto (`ContactDetailsView.m`) → no-op. (L'avatar BCS è lavoro
  futuro tramite endpoint dedicato.)
- Chiavi rimosse dall'Info.plist: `NSPhotoLibraryUsageDescription`,
  `NSPhotoLibraryAddUsageDescription`.

### Contatti nativi — già disattivati
- `enable_native_address_book=0` (factory rc) e `requestAccessForEntityType` già commentata
  in `FastAddressBook`: nessun prompt contatti viene mai mostrato. I contatti dell'app sono
  i **buddy BCS** (LinphoneFriend da UserConf), non la rubrica di sistema.
- La chiave `NSContactsUsageDescription` è stata **mantenuta**: il binario referenzia ancora
  il framework Contacts (codice `CNContactStore` in `FastAddressBook`/`ContactDetailsView`),
  quindi tenere la usage description è più coerente/sicuro che toglierla. Il prompt è già
  disattivato, quindi l'obiettivo è raggiunto. Per rimuoverla servirebbe un passaggio
  dedicato che neutralizzi tutti gli accessi nativi residui.

### Permessi mantenuti
- Camera e microfono (servono alle videochiamate).

---

## Note tecniche / gotcha

- **Thread-safety del core**: le API del core Linphone (`createCallLog`, indirizzi,
  `linphone_address_weak_equal`, …) NON sono thread-safe → vanno chiamate sul **main thread**.
  I completion di `URLSession` girano in background: ogni costruzione di oggetti core in un
  completion di rete va wrappata in `DispatchQueue.main.async`. (Un primo crash —
  EXC_BREAKPOINT su `weak_equal` — era esattamente questo.)
- **Composite view Swift senza xib**: i view controller registrati come
  `UICompositeViewDescription` possono costruire la UI in modo programmatico (vedi
  `DirectoryView.swift`, `ChatConversationViewSwift`). Navigazione via `self.VIEW(...)`.
- **Build da CLI**: Xcode è in `/Applications` ma `xcode-select` punta ai CommandLineTools;
  compilare con
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace bcsphone.xcworkspace -scheme linphone …`
  (senza sudo).
- **File secret**: `Resources/sturn.rc` (config TURN) è in `.gitignore` e non tracciato — i
  file ignorati non vengono aggiunti nemmeno da `git add -A`.

## Limitazioni note / lavoro futuro
- Badge "chiamate perse" della tab: legge i log locali ormai vuoti, quindi non riflette i
  persi remoti.
- Avatar utente: l'endpoint BCS esiste ma non è ancora usato.
- Chiave `NSContactsUsageDescription` ancora presente (vedi sopra).
- Ramo `disable_chat_feature` di `TabBarView` (layout manuale a 3 bottoni) non considera la
  rubrica — rilevante solo con quella configurazione.

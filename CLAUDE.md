# BcsPhone iOS — Istruzioni di progetto (CLAUDE.md)

App iOS = **fork di Linphone** evoluto in modo indipendente dall'upstream per la piattaforma
**BCS**. Nel tempo alcune funzionalità di Linphone vengono sostituite con servizi BCS, altre
rimosse. Esiste un client **Android** gemello (`/Users/alceo/Documents/BcsPhone/linphone-android-alceo-release-5.2.bcsws/`)
da cui si portano le funzionalità: per nuovi port, **prima esplorare l'implementazione
Android** e replicarne i pattern adattandoli a iOS (Swift, con parti Objective-C).

Versione attuale: **5.2.5 (build 1006)** — in produzione sullo store.

---

## Funzionalità BCS già implementate

### 1. Registro chiamate remoto (sostituisce il DB locale di Linphone)
Fonte di verità = endpoint REST BCS `/callreport` (non più il DB locale). Approccio (come
Android): si costruiscono `LinphoneCallLog` **sintetici** via `core.createCallLog(...)` dai
dati REST e si danno alla UI dello storico esistente.
- Layer rete: `BcsWs/BcsWsService.swift` (auth Basic→Bearer + refresh/scadenza token, timeout 30s, gestione 400/403/404/500).
- Logica: `BcsWs/CallReport.swift` → `BcsCallReportManager`, **a pagine** (come Android, commit 126bd11ca):
  `limit=1` per il `Count`, poi pagina più recente `limit=50 offset=max(0,Count-50)`; pagine più vecchie scorrendo
  (offset −50 fino a 0). Cache per account (dedup per Id, stesse istanze `CallLog`), rilettura al massimo ogni 5 min
  (apertura / ritorno in primo piano), POST a fine chiamata messo in cima alla cache senza rileggere. Solo
  «Cancella tutto», niente cancellazione singola. Ogni log sintetico viene tolto subito dal DB locale del core
  (`createCallLog` lo salva). Vuoto senza account registrato.
- UI: `Classes/HistoryListTableView.m`, `HistoryListView.m`, `HistoryDetailsView.{h,m}`, `HistoryDetailsTableView.{h,m}`, `UIHistoryCell.m`.
- POST a fine chiamata: `Classes/Swift/CallManager.swift` (case `.End/.Error`).

### 2. Rubrica centralizzata (nuova tab)
Ricerca sulla directory BCS `/directory`, **sul server a pagine** (come Android, commit 126bd11ca):
`filter` + `limit=50` + `offset`, ordine `sortBy=asc(Name)`; pagina successiva quando mancano ~10 righe; una sola
richiesta in volo (il testo scritto nel frattempo si cerca all'arrivo, solo l'ultimo); debounce 400 ms; < 2 caratteri
= elenco senza filtro. Un risultato completo (voci = `Count`) viene ricordato e le ricerche che contengono quel filtro
si fanno in locale. Vuota senza account registrato; si azzera al cambio/disattivazione account.
- Modelli + manager: `BcsWs/DirectoryResponse.swift` (`BcsDirectoryItem`, `BcsDirectoryManager`).
- UI programmatica (niente xib): `BcsWs/DirectoryView.swift` (`DirectoryListView`, `DirectoryDetailsView`).
- Tab: `Classes/LinphoneUI/TabBarView.{h,m}` + `Base.lproj/TabBarView.xib` (5° bottone, portrait+landscape). Icona `Resources/images/footer_directory.png`.

### 3. Rimozione permessi non necessari
- **Foto/galleria**: tutte le richieste di permesso neutralizzate, accessi rimossi (read via picker, write via `auto_write_to_gallery_preference=0`), chiavi `NSPhotoLibrary*UsageDescription` rimosse dall'Info.plist. Avatar disabilitato (side menu → impostazioni; dettaglio contatto → no-op).
- **Contatti nativi**: prompt già disattivato (`enable_native_address_book=0` + `requestAccess` commentata in `FastAddressBook`). I contatti dell'app sono i **buddy BCS** (LinphoneFriend da UserConf), non la rubrica di sistema. Chiave `NSContactsUsageDescription` **mantenuta** di proposito (il binario referenzia ancora il framework Contacts).

---

## Convenzioni e vincoli

- **Layer BcsWs**: tutto il networking verso i webservice BCS passa da `BcsWs/` (un service/manager riusabile, non duplicare il codice di rete nelle schermate). Auth Bearer riutilizzando il meccanismo esistente (`BcsWsService`); non reinventare il sistema di auth.
- **Non toccare il core SIP/VoIP** di Linphone (gestione chiamate, codec, registrazione SIP).
- **Swift per il nuovo codice**; per interfacciarsi con ObjC usare i bridge header già presenti (`linphoneapp-Swift.h`). Non riscrivere in Swift parti ObjC che non si toccano.
- **Niente nuove dipendenze** (CocoaPods/SPM) senza conferma. Finora solo `URLSession`.
- **DOMAIN_ID/USER_ID/token**: leggerli dal codice esistente, non assumerli.

### ⚠️ Gotcha thread-safety (importante)
Le API del core Linphone (`createCallLog`, indirizzi, `linphone_address_weak_equal`, …) **non
sono thread-safe** → vanno chiamate sul **main thread** (quello dell'iterate). I completion di
`URLSession` girano in background: ogni uso del core in un completion di rete va wrappato in
`DispatchQueue.main.async`.

### Composite view Swift senza xib
I view controller registrati come `UICompositeViewDescription` possono costruire la UI in modo
programmatico (vedi `DirectoryView.swift`, `ChatConversationViewSwift`). Navigazione via
`self.VIEW(...)` (estensione in `Classes/Swift/Extensions/`). La `TabBarView` usa
`TPMultiLayoutViewController`, che **abbina le viste portrait/landscape per `tag`**: ogni
bottone con un dato tag deve esistere in **entrambe** le viste.

---

## Build / Test

- **Compilare con Xcode 26** (`/Applications/Xcode 26.app`, SDK iOS 26.x). Con Xcode 27 (`/Applications/Xcode.app`)
  l'app compila ma **si chiude all'avvio** su iOS 27: con l'SDK 27 Apple impone il ciclo di vita a scene (UIScene),
  che l'app non ha ancora (tutto in `LinphoneAppDelegate`). Migrazione a `SceneDelegate` = lavoro futuro, necessario
  prima che lo store richieda l'SDK 27. Xcode 27 resta installato (serve `devicectl` per iPhone con iOS 27).
- Deployment target minimo **iOS 15.0** (app, estensioni e Podfile): Xcode 26+ non accetta valori inferiori.
- `xcode-select` punta ai CommandLineTools. Compilare da CLI con:
  ```
  DEVELOPER_DIR="/Applications/Xcode 26.app/Contents/Developer" xcodebuild \
    -workspace bcsphone.xcworkspace -scheme linphone \
    -configuration Debug -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
  ```
- `pod install` (SDK locale, locale UTF-8 obbligatorio per CocoaPods con Ruby 4):
  `LANG=en_US.UTF-8 PODFILE_PATH=/Users/alceo/Documents/BcsPhone/linphone-sdk/build-ios pod install`.
  Gli errori `bitcode_strip` su belcard/lime/limetester sono innocui (framework assenti nella build SDK).
  Il post_install riscrive alcuni commenti in `project.pbxproj`: rimetterli com'erano per non sporcare il diff.
- Riferimento Android aggiornato: repo GitHub `ALCEO-srl/linphone-android`, ramo `alceo/release/5.2.A17`
  (la copia locale indicata sopra è vecchia/assente).
- SDK Linphone locale: `/Users/alceo/Documents/BcsPhone/linphone-sdk/build-ios/...`; wrapper Swift in `share/linphonesw/LinphoneWrapper.swift`.
- Pubblicazione: app + extension (`msgNotificationService`, `msgNotificationContent`) devono avere **stessa versione e stesso build** (`MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in `project.pbxproj`).
- Lingua UI: l'app gira in italiano; nuove stringhe in `Resources/it.lproj/Localizable.strings` (UTF-16) o `.strings` delle xib.

---

## Limitazioni note / lavoro futuro
- Badge "chiamate perse" della tab: legge i log locali ormai vuoti → non riflette i persi remoti.
- Avatar utente: esiste un endpoint BCS dedicato, non ancora usato.
- `NSContactsUsageDescription` ancora presente (codice Contacts nativo residuo non rimosso).
- Ramo `disable_chat_feature` di `TabBarView` (layout manuale a 3 bottoni) non considera la rubrica.

## File secret
`Resources/sturn.rc` (config TURN, password) è in `.gitignore` e non tracciato. I file
ignorati non vengono aggiunti nemmeno da `git add -A`.

---

## Flusso di lavoro per nuove funzionalità
1. **Esplorare** l'implementazione Android di riferimento (path sopra) e annotare pattern, modello dati, gestione token/paginazione/errori.
2. **Esplorare** la codebase iOS (dove agganciarsi, pattern prevalente).
3. Proporre un breve **piano** dei file da creare/modificare e attendere conferma.
4. Implementare, compilare (vedi sopra), e far testare sul dispositivo reale.

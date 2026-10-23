//
//  CallReport.swift
//  bcsphone
//
//  Porting del registro chiamate remoto BCS (equivalente Android: bcsws/CallReport.kt
//  + CoreContext.fetchCallLog/updateCallLog/clearCallLog).
//
//  La fonte di verità del registro chiamate è l'endpoint /callreport: i log locali di
//  Linphone non vengono più usati come storage. Replichiamo l'approccio Android, che
//  costruisce LinphoneCallLog "sintetici" a partire dai dati REST e li passa alla UI
//  esistente (HistoryListTableView).
//

import Foundation
import linphonesw

// MARK: - Modelli REST (mirror di bcsws/CallReport.kt)

struct BcsCallReportResponse: Codable {
    let Count: Int
    let Items: [BcsCallReportItem]
}

struct BcsCallReportItem: Codable {
    var Id: String = ""            // vuoto in POST, valorizzato dal server
    var Direction: String          // "incoming" | "outgoing"
    var Duration: Int
    var IsConnected: Bool
    var Timestamp: String          // ISO-8601 UTC
    var TermReason: String
    var TermSipReason: Int
    var Useragent: String
    var RemoteParty: BcsRemoteParty
}

struct BcsRemoteParty: Codable {
    var Uri: String
    var DisplayName: String
}

// MARK: - Manager (mirror di CoreContext.fetchCallLog/updateCallLog/clearCallLog)

// dms: the call report is read one page at a time (as on Android, commit 126bd11ca). The server keeps the last
// 500 entries of the user in ascending Timestamp order (offset 0 = oldest): first the newest page
// (limit=1 to read Count, then limit=50 offset=max(0,Count-50)), the older pages while scrolling. The entries are
// cached for the current account, newest first, without duplicates (Id); the all / missed filter works on the
// cache. The newest page is read again at most every 5 minutes (calls made or deleted from other devices).
@objc class BcsCallReportManager: NSObject {

    @objc static let shared = BcsCallReportManager()

    private static let pageSize = 50
    private static let refreshInterval: TimeInterval = 5 * 60

    // Manteniamo vivi i CallLog sintetici finché la UI li usa: i puntatori C esposti
    // a Objective-C restano validi solo se questi oggetti Swift non vengono deallocati.
    // dms: always the same instances for an entry, so that the rows already shown stay still when a page is added
    private struct Entry {
        let id: String
        let log: CallLog
    }
    private var entries: [Entry] = []          // newest first
    private var cacheAccount: String?          // account of the cached entries, nil = not loaded
    private var oldestOffset = 0               // server offset of the oldest cached entry
    private var loadTime: Date?
    // dms: one request at a time; the refresh requests arriving meanwhile wait for the running one
    private var loadingNewest = false
    private var loadingOlder = false
    private var newestWaiters: [(NSError?) -> Void] = []

    // Notifica inviata quando il registro cambia senza richieste (es. dopo una chiamata): la lista
    // storico la osserva e si ricostruisce dalla cache.
    @objc static let didUpdateNotification = Notification.Name("BcsCallReportDidUpdate")

    private var service: BcsWsService? {
        return LinphoneManager.instance().bcsWsService
    }

    private var registeredAccount: String? {
        guard let manager = LinphoneManager.instance(), manager.isBcsAccountRegistered() else { return nil }
        return manager.lastAccountIdRegistered
    }

    /// Log in cache (dal più recente), senza toccare la rete. Vuoto senza account registrato.
    @objc func cachedCallLogs() -> [NSValue] {
        guard isLoaded else { return [] }
        return entries.compactMap { entry -> NSValue? in
            guard let ptr = entry.log.getCobject else { return nil }
            return NSValue(pointer: UnsafeRawPointer(ptr))
        }
    }

    /// dms: true when the cache holds the entries of the registered account
    @objc var isLoaded: Bool {
        guard let account = registeredAccount else { return false }
        return cacheAccount == account
    }

    /// dms: true when there are older entries on the server, to be loaded while scrolling
    @objc var hasOlder: Bool {
        return isLoaded && oldestOffset > 0
    }

    // dms: cache emptied on Cleared of the registered account and on Ok of another account
    @objc func reset() {
        entries = []
        cacheAccount = nil
        oldestOffset = 0
        loadTime = nil
    }

    // MARK: Lettura registro -> LinphoneCallLog sintetici

    /// dms: reads the newest page if the cache is not loaded for the registered account, or (refreshIfOld) if it was
    /// loaded more than 5 minutes ago. Otherwise no request. The completion runs on the main thread.
    @objc(refreshIfOld:completion:) func refresh(ifOld refreshIfOld: Bool, completion: @escaping (NSError?) -> Void) {
        guard let account = registeredAccount else {
            // dms: the web service keeps the credentials, without a registered account the call report is empty
            reset()
            completion(nil)
            return
        }
        if loadingNewest {
            newestWaiters.append(completion)
            return
        }
        let old = loadTime.map { Date().timeIntervalSince($0) >= BcsCallReportManager.refreshInterval } ?? true
        guard cacheAccount != account || (refreshIfOld && old) else {
            completion(nil)
            return
        }
        guard let service = service else {
            completion(nil)
            return
        }
        loadingNewest = true
        newestWaiters.append(completion)
        // Count probe, then the newest page
        service.fetchCallReport(limit: 1, offset: 0) { [weak self] probe, error in
            guard let probe = probe else {
                DispatchQueue.main.async { self?.finishNewest(error: error) }
                return
            }
            let count = probe.Count
            let offset = max(0, count - BcsCallReportManager.pageSize)
            guard count > 0 else {
                DispatchQueue.main.async { self?.storeNewest(items: [], count: 0, offset: 0, account: account) }
                return
            }
            service.fetchCallReport(limit: BcsCallReportManager.pageSize, offset: offset) { page, error in
                DispatchQueue.main.async {
                    guard let page = page else {
                        self?.finishNewest(error: error)
                        return
                    }
                    self?.storeNewest(items: page.Items, count: page.Count, offset: offset, account: account)
                }
            }
        }
    }

    // Le API del core Linphone NON sono thread-safe: il completion di URLSession
    // gira su un thread di background, quindi costruiamo i CallLog sintetici sul
    // main thread (lo stesso su cui il core esegue iterate).
    private func storeNewest(items: [BcsCallReportItem], count: Int, offset: Int, account: String) {
        // dms: account disabled or changed while the request was running
        guard registeredAccount == account else {
            finishNewest(error: nil)
            return
        }
        // dms: the newest page replaces the cache, the older pages are loaded again while scrolling
        entries = []
        append(items)
        cacheAccount = account
        oldestOffset = offset
        loadTime = Date()
        NSLog("[BcsCallReport] \(entries.count) of \(count) calls loaded")
        finishNewest(error: nil)
    }

    private func finishNewest(error: NSError?) {
        if let error = error {
            NSLog("[BcsCallReport] Error: \(error.localizedDescription)")
        }
        loadingNewest = false
        let waiters = newestWaiters
        newestWaiters = []
        waiters.forEach { $0(error) }
    }

    /// dms: loads the previous (older) page: offset goes down by 50 until 0, one page at a time.
    /// completion(true) when entries were added.
    @objc func loadOlder(completion: @escaping (Bool) -> Void) {
        guard hasOlder, !loadingOlder, !loadingNewest, let service = service, let account = cacheAccount else {
            completion(false)
            return
        }
        loadingOlder = true
        let previousOffset = oldestOffset
        let offset = max(0, previousOffset - BcsCallReportManager.pageSize)
        // limit = gap, so the last page can be shorter than 50
        service.fetchCallReport(limit: previousOffset - offset, offset: offset) { [weak self] page, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loadingOlder = false
                guard let page = page, self.cacheAccount == account, self.isLoaded,
                      self.oldestOffset == previousOffset else {
                    if let error = error {
                        NSLog("[BcsCallReport] Failed to fetch older calls: \(error.localizedDescription)")
                    }
                    completion(false)
                    return
                }
                let before = self.entries.count
                self.append(page.Items)
                self.oldestOffset = offset
                NSLog("[BcsCallReport] \(self.entries.count - before) older calls loaded, offset=\(offset)")
                completion(self.entries.count > before)
            }
        }
    }

    /// Items in server (ascending) order, appended at the end of the cache (older), without duplicates.
    private func append(_ items: [BcsCallReportItem]) {
        var ids = Set(entries.map { $0.id })
        for item in items.reversed() {
            if !item.Id.isEmpty && ids.contains(item.Id) { continue }
            guard let log = buildSyntheticLog(from: item) else { continue }
            entries.append(Entry(id: item.Id, log: log))
            ids.insert(item.Id)
        }
    }

    // dms: call made from this phone, entry returned by the POST: on top of the cache, no request
    private func addToCache(_ item: BcsCallReportItem) {
        guard isLoaded, !entries.contains(where: { $0.id == item.Id }),
              let log = buildSyntheticLog(from: item) else { return }
        entries.insert(Entry(id: item.Id, log: log), at: 0)
        NotificationCenter.default.post(name: BcsCallReportManager.didUpdateNotification, object: nil)
    }

    private func buildSyntheticLog(from item: BcsCallReportItem) -> CallLog? {
        let core = Core.get()
        guard let identity = core.defaultAccount?.params?.identityAddress else {
            NSLog("[BcsCallReport] no default account identity, cannot build call logs")
            return nil
        }

        let dir: Call.Dir
        let from: Address
        let to: Address
        var status: Call.Status = .Success

        do {
            if item.Direction == "incoming" {
                dir = .Incoming
                from = try core.createAddress(address: item.RemoteParty.Uri)
                to = identity
                if !item.IsConnected { status = .Missed }
            } else {
                dir = .Outgoing
                from = identity
                to = try core.createAddress(address: item.RemoteParty.Uri)
            }
        } catch {
            NSLog("[BcsCallReport] Invalid entry \(item.Id): \(error)")
            return nil
        }

        // Display name del corrispondente (Android lo lascia ai contatti; qui lo
        // impostiamo se presente, la UI userà comunque la rubrica se trova un match).
        let remote = (dir == .Incoming) ? from : to
        if !item.RemoteParty.DisplayName.isEmpty {
            try? remote.setDisplayname(newValue: item.RemoteParty.DisplayName)
        }

        if status == .Success {
            status = Self.mapStatus(termReason: item.TermReason, sip: item.TermSipReason)
        }

        let startTime = Self.parseTimestamp(item.Timestamp)
        guard let log = try? core.createCallLog(
            from: from, to: to, dir: dir, duration: item.Duration,
            startTime: startTime, connectedTime: 0, status: status,
            videoEnabled: false, quality: 1.0
        ) else { return nil }
        // dms: createCallLog also stores the log in the local call history database of the core: removed at once
        // (as on Android), otherwise every read of the call report would add it again
        core.removeCallLog(callLog: log)

        // Conserviamo l'Id BCS della voce.
        log.refKey = item.Id
        return log
    }

    // Mapping TermReason/TermSipReason -> Call.Status (mirror di CoreContext.fetchCallLog).
    private static func mapStatus(termReason: String, sip: Int) -> Call.Status {
        switch termReason {
        case "normal":
            return .Success
        case "sip-reason", "local-reject", "remote-reject":
            switch sip {
            case 302: return .EarlyAborted
            case 404: return .Aborted
            case 401, 403, 407: return .EarlyAborted     // forbidden
            case 408, 480, 4887: return .Aborted         // no answer
            case 484: return .EarlyAborted               // address incomplete
            case 486, 600: return .EarlyAborted          // busy
            case 488: return .EarlyAborted               // not acceptable
            case 503: return .EarlyAborted               // server unavailable
            case 603: return .Declined                   // call rejected
            default: return .EarlyAborted
            }
        case "sip-remote-cancelled", "sip-proxy-cancelled":
            return .Aborted
        case "sip-local-cancelled":
            return .Aborted
        case "remote-bye-without-ack":
            return sip == 0 ? .Success : .EarlyAborted
        case "remote-disconnected":
            return .Success
        case "cancelled-by-forking":
            return .AcceptedElsewhere
        default:
            // internal-error, network-error, bad-address, generic-fail,
            // audio-ice-*, dialog-interrupted, local-bye-without-ack, local-timeout
            return .EarlyAborted
        }
    }

    private static func parseTimestamp(_ ts: String) -> time_t {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFractional.date(from: ts) {
            return time_t(d.timeIntervalSince1970)
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: ts) {
            return time_t(d.timeIntervalSince1970)
        }
        return time_t(Date().timeIntervalSince1970)
    }

    // MARK: Scrittura a fine chiamata (mirror di CoreContext.updateCallLog)

    /// Invia al server il record della chiamata appena terminata.
    func postCallLog(call: Call) {
        guard let service = service else { return }
        guard let remoteAddress = call.remoteAddress else { return }

        let duration = call.duration
        let direction = (call.dir == .Outgoing) ? "outgoing" : "incoming"
        let isConnected = duration > 0

        // Timestamp = inizio chiamata stimato (ora - durata), in UTC ISO-8601.
        let start = Date().addingTimeInterval(TimeInterval(-max(duration, 0)))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: start)

        var termReason = "normal"
        var termSip = 0
        let error = call.errorInfo
        let protocolCode = Int(error?.protocolCode ?? 0)
        let reason = error?.reason ?? .None
        let phrase = error?.phrase ?? ""

        if call.state == .Error {
            termSip = protocolCode
            switch reason {
            case .Busy: termReason = "remote-reject"
            case .IOError: termReason = "network-error"
            case .NotFound: termReason = "sip-reason"
            case .ServerTimeout: termReason = "network-error"
            case .AddressIncomplete: termReason = "bad-address"
            default: termReason = "sip-reason"
            }
        } else if call.state == .End {
            if call.dir == .Outgoing && reason == .Declined {
                termReason = "remote-reject"
                termSip = protocolCode
            }
            if call.dir == .Incoming && phrase == "Call completed elsewhere" {
                return // non registriamo: risposto altrove
            }
            if call.dir == .Incoming && protocolCode == 603 && reason == .Declined {
                if phrase == "Declined elsewhere" {
                    return
                } else {
                    termReason = "local-reject"
                    termSip = protocolCode
                }
            }
            if call.dir == .Incoming && protocolCode == 0 && reason == .NotAnswered {
                termReason = "sip-remote-cancelled"
                termSip = 0
            }
        }

        let item = BcsCallReportItem(
            Id: "",
            Direction: direction,
            Duration: duration,
            IsConnected: isConnected,
            Timestamp: timestamp,
            TermReason: termReason,
            TermSipReason: termSip,
            Useragent: "BcsPhone",
            RemoteParty: BcsRemoteParty(
                Uri: remoteAddress.asStringUriOnly(),
                DisplayName: remoteAddress.displayName ?? ""
            )
        )

        service.addCallReport(item: item) { [weak self] added, error in
            if let error = error {
                NSLog("[BcsCallReport] postCallLog error: \(error.localizedDescription)")
                return
            }
            NSLog("[BcsCallReport] call report added, id=\(added?.Id ?? "?")")
            // dms: the entry sent, with the Id returned by the server, goes on top of the cache: the list is
            // updated without reading the server again
            guard let id = added?.Id, !id.isEmpty else { return }
            var entry = item
            entry.Id = id
            DispatchQueue.main.async {
                self?.addToCache(entry)
            }
        }
    }

    // MARK: Cancellazione

    /// Cancella tutte le voci del registro (DELETE /callreport).
    /// dms: the cache is emptied at once (account and load time kept, as on Android); single entries are not deleted.
    @objc func clearAll(completion: @escaping (NSError?) -> Void) {
        entries = []
        oldestOffset = 0
        guard let service = service else { completion(nil); return }
        service.clearCallReport { error in
            DispatchQueue.main.async {
                completion(error)
            }
        }
    }
}

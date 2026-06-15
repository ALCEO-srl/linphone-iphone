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

@objc class BcsCallReportManager: NSObject {

    @objc static let shared = BcsCallReportManager()

    // Massimo numero di voci mantenute dal server.
    private static let fetchLimit = 500

    // Manteniamo vivi i CallLog sintetici finché la UI li usa: i puntatori C esposti
    // a Objective-C restano validi solo se questi oggetti Swift non vengono deallocati.
    private var syntheticLogs: [CallLog] = []
    // La cache è valida finché non cambia il registro (nuova chiamata, cancellazione).
    // Evita di ri-scaricare e ri-costruire i log a ogni comparsa della view (es. ritorno
    // dal dettaglio), come fa Android.
    private var cacheValid = false

    // Notifica inviata quando il registro remoto cambia (es. dopo una chiamata): la lista
    // storico la osserva per ricaricarsi dal server.
    @objc static let didUpdateNotification = Notification.Name("BcsCallReportDidUpdate")

    private var service: BcsWsService? {
        return LinphoneManager.instance().bcsWsService
    }

    private func mapToValues(_ logs: [CallLog]) -> [NSValue] {
        return logs.compactMap { log -> NSValue? in
            guard let ptr = log.getCobject else { return nil }
            return NSValue(pointer: UnsafeRawPointer(ptr))
        }
    }

    /// Restituisce i log dalla cache senza toccare la rete, oppure nil se la cache non è
    /// valida (in tal caso il chiamante deve usare fetchCallLogs).
    @objc func cachedCallLogs() -> [NSValue]? {
        guard cacheValid else { return nil }
        return mapToValues(syntheticLogs)
    }

    @objc func invalidateCache() {
        cacheValid = false
    }

    // MARK: Lettura registro -> LinphoneCallLog sintetici

    /// Scarica le ultime 500 voci e costruisce i LinphoneCallLog sintetici (come Android).
    /// Il completion restituisce un array di NSValue che incapsulano i puntatori
    /// LinphoneCallLog*, pronti per essere consumati da HistoryListTableView.
    @objc func fetchCallLogs(completion: @escaping ([NSValue]) -> Void) {
        guard let service = service else {
            completion([])
            return
        }
        service.fetchCallReport(limit: BcsCallReportManager.fetchLimit, offset: 0) { [weak self] response, error in
            if let error = error {
                NSLog("[BcsCallReport] fetchCallLogs error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion([]) }
                return
            }
            let items = response?.Items ?? []
            // Le API del core Linphone NON sono thread-safe: il completion di URLSession
            // gira su un thread di background, quindi costruiamo i CallLog sintetici sul
            // main thread (lo stesso su cui il core esegue iterate).
            DispatchQueue.main.async {
                guard let self = self else { completion([]); return }
                let logs = self.buildSyntheticLogs(from: items)
                self.syntheticLogs = logs
                self.cacheValid = true
                completion(self.mapToValues(logs))
            }
        }
    }

    private func buildSyntheticLogs(from items: [BcsCallReportItem]) -> [CallLog] {
        let core = Core.get()
        guard let identity = core.defaultAccount?.params?.identityAddress else {
            NSLog("[BcsCallReport] no default account identity, cannot build call logs")
            return []
        }

        var result: [CallLog] = []
        // Gli item arrivano ordinati per Timestamp crescente: iteriamo al contrario
        // per avere i più recenti per primi (come Android).
        for item in items.reversed() {
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
                NSLog("[BcsCallReport] invalid address \(item.RemoteParty.Uri): \(error)")
                continue
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
            ) else { continue }

            // Conserviamo l'Id BCS per la cancellazione lato server.
            log.refKey = item.Id
            result.append(log)
        }
        return result
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

        service.addCallReport(item: item) { [weak self] addedId, error in
            if let error = error {
                NSLog("[BcsCallReport] postCallLog error: \(error.localizedDescription)")
            } else {
                NSLog("[BcsCallReport] call report added, id=\(addedId ?? "?")")
                // Il registro è cambiato: invalida la cache e avvisa la lista storico.
                DispatchQueue.main.async {
                    self?.cacheValid = false
                    NotificationCenter.default.post(name: BcsCallReportManager.didUpdateNotification, object: nil)
                }
            }
        }
    }

    // MARK: Cancellazione

    /// Cancella tutte le voci del registro (DELETE /callreport).
    @objc func clearAll(completion: @escaping (NSError?) -> Void) {
        guard let service = service else { completion(nil); return }
        service.clearCallReport { [weak self] error in
            DispatchQueue.main.async {
                if error == nil { self?.cacheValid = false }
                completion(error)
            }
        }
    }

    /// Cancella una singola voce identificata dall'Id BCS (stash in refKey).
    @objc func deleteEntry(itemId: String, completion: @escaping (NSError?) -> Void) {
        guard !itemId.isEmpty, let service = service else { completion(nil); return }
        service.deleteCallReportItem(id: itemId) { [weak self] error in
            DispatchQueue.main.async {
                if error == nil { self?.cacheValid = false }
                completion(error)
            }
        }
    }
}

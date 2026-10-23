//
//  DirectoryResponse.swift
//  bcsphone
//
//  Modelli della rubrica centralizzata BCS (mirror di bcsws/DirectoryResponse.kt).
//

import Foundation

struct BcsDirectoryResponse: Codable {
    let Count: Int
    let Items: [BcsDirectoryItem]
}

@objc class BcsDirectoryItem: NSObject, Codable {
    @objc var Id: String = ""
    @objc var Uri: String = ""
    @objc var Name: String = ""
    @objc var Surname: String = ""
    @objc var DisplayName: String = ""
    @objc var Profession: String = ""
    @objc var Company: String = ""
    @objc var EmailAddress: String = ""
    @objc var MobilePhone: String = ""
    @objc var LandlinePhone: String = ""
    @objc var FaxPhone: String = ""
    @objc var Title: String = ""
    @objc var Address: String = ""
    @objc var Branch: String = ""
    @objc var Office: String = ""
    @objc var Manager: String = ""
    @objc var Assistant: String = ""
    @objc var Attr1: String = ""
    @objc var Attr2: String = ""
    @objc var Attr3: String = ""
    @objc var Attr4: String = ""
    @objc var Attr5: String = ""
    @objc var Attr6: String = ""
    @objc var Attr7: String = ""
    @objc var Attr8: String = ""
    @objc var Attr9: String = ""
    @objc var Attr10: String = ""
    @objc var AvatarImageUrl: String = ""

    // Tutti i campi sono opzionali nel JSON: decodifichiamo con default a stringa vuota.
    enum CodingKeys: String, CodingKey {
        case Id, Uri, Name, Surname, DisplayName, Profession, Company, EmailAddress
        case MobilePhone, LandlinePhone, FaxPhone, Title, Address, Branch, Office
        case Manager, Assistant
        case Attr1, Attr2, Attr3, Attr4, Attr5, Attr6, Attr7, Attr8, Attr9, Attr10
        case AvatarImageUrl
    }

    required init(from decoder: Decoder) throws {
        super.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { (try? c.decode(String.self, forKey: k)) ?? "" }
        Id = s(.Id); Uri = s(.Uri); Name = s(.Name); Surname = s(.Surname)
        DisplayName = s(.DisplayName); Profession = s(.Profession); Company = s(.Company)
        EmailAddress = s(.EmailAddress); MobilePhone = s(.MobilePhone)
        LandlinePhone = s(.LandlinePhone); FaxPhone = s(.FaxPhone); Title = s(.Title)
        Address = s(.Address); Branch = s(.Branch); Office = s(.Office)
        Manager = s(.Manager); Assistant = s(.Assistant)
        Attr1 = s(.Attr1); Attr2 = s(.Attr2); Attr3 = s(.Attr3); Attr4 = s(.Attr4)
        Attr5 = s(.Attr5); Attr6 = s(.Attr6); Attr7 = s(.Attr7); Attr8 = s(.Attr8)
        Attr9 = s(.Attr9); Attr10 = s(.Attr10); AvatarImageUrl = s(.AvatarImageUrl)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Id, forKey: .Id); try c.encode(Uri, forKey: .Uri)
        try c.encode(Name, forKey: .Name); try c.encode(Surname, forKey: .Surname)
        try c.encode(DisplayName, forKey: .DisplayName); try c.encode(Profession, forKey: .Profession)
        try c.encode(Company, forKey: .Company); try c.encode(EmailAddress, forKey: .EmailAddress)
        try c.encode(MobilePhone, forKey: .MobilePhone); try c.encode(LandlinePhone, forKey: .LandlinePhone)
        try c.encode(FaxPhone, forKey: .FaxPhone); try c.encode(Title, forKey: .Title)
        try c.encode(Address, forKey: .Address); try c.encode(Branch, forKey: .Branch)
        try c.encode(Office, forKey: .Office); try c.encode(Manager, forKey: .Manager)
        try c.encode(Assistant, forKey: .Assistant)
        try c.encode(Attr1, forKey: .Attr1); try c.encode(Attr2, forKey: .Attr2)
        try c.encode(Attr3, forKey: .Attr3); try c.encode(Attr4, forKey: .Attr4)
        try c.encode(Attr5, forKey: .Attr5); try c.encode(Attr6, forKey: .Attr6)
        try c.encode(Attr7, forKey: .Attr7); try c.encode(Attr8, forKey: .Attr8)
        try c.encode(Attr9, forKey: .Attr9); try c.encode(Attr10, forKey: .Attr10)
        try c.encode(AvatarImageUrl, forKey: .AvatarImageUrl)
    }

    /// Nome da mostrare in lista/dettaglio (mirror della logica Android).
    @objc var caption: String {
        if !DisplayName.isEmpty { return DisplayName }
        if !Name.isEmpty || !Surname.isEmpty { return "\(Name) \(Surname)".trimmingCharacters(in: .whitespaces) }
        return Uri
    }

    /// Ricerca libera su tutti i campi, case-insensitive (mirror del filtro Android).
    /// dms: same 27 fields as the Android local filter (AvatarImageUrl excluded)
    func matches(_ query: String) -> Bool {
        let fields = [Id, Uri, Name, Surname, DisplayName, Profession, Company, EmailAddress,
                      MobilePhone, LandlinePhone, FaxPhone, Title, Address, Branch, Office,
                      Manager, Assistant, Attr1, Attr2, Attr3, Attr4, Attr5, Attr6, Attr7,
                      Attr8, Attr9, Attr10]
        return fields.contains { $0.range(of: query, options: .caseInsensitive) != nil }
    }
}

// MARK: - Manager rubrica (mirror di DirectoryViewModel, Android commit 126bd11ca)

// dms: the directory is searched on the server one page at a time (filter on all the fields, pages of 50, next page
// while scrolling). One request at a time: the filter typed meanwhile is searched when the answer arrives, only the
// last one. A complete result (entries loaded = Count) is remembered with its filter: every search containing that
// filter is done locally on the remembered entries. Shown only with a registered account.
@objc class BcsDirectoryManager: NSObject {

    @objc static let shared = BcsDirectoryManager()

    static let pageSize = 50
    static let minFilterLength = 2

    /// Entries of the search shown, in the server order (alphabetical).
    private(set) var items: [BcsDirectoryItem] = []
    /// First page asked to the server and not arrived yet (spinner).
    private(set) var isLoading = false
    /// Error of the last first page, if any.
    private(set) var lastError: NSError?
    /// Called on the main thread when items / isLoading change.
    var onChange: (() -> Void)?

    private var loadedFilter = ""
    private var loadedAccount: String?        // account of the items shown, nil = nothing loaded
    private var totalCount = 0
    private var requestInFlight = false
    private var pendingFilter: String?
    private var completeFilter: String?
    private var completeItems: [BcsDirectoryItem] = []

    private var service: BcsWsService? {
        return LinphoneManager.instance().bcsWsService
    }

    private var registeredAccount: String? {
        guard let manager = LinphoneManager.instance(), manager.isBcsAccountRegistered() else { return nil }
        return manager.lastAccountIdRegistered
    }

    /// Filter used for a text typed by the user: trimmed, fewer than 2 characters = whole directory.
    static func filter(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count < minFilterLength ? "" : trimmed
    }

    private static func contains(_ filter: String, _ other: String) -> Bool {
        return other.isEmpty || filter.range(of: other, options: .caseInsensitive) != nil
    }

    // dms: called on Cleared of the registered account and on Ok of another account: what is remembered is forgotten,
    // the view repeats the current search on the server
    @objc func reset() {
        items = []
        totalCount = 0
        loadedAccount = nil
        lastError = nil
        pendingFilter = nil
        completeFilter = nil
        completeItems = []
    }

    /// Searches a filter (already normalized with filter(for:)). No request if the same search is already shown or
    /// if it can be done on a remembered complete result.
    func search(_ filter: String) {
        guard let account = registeredAccount else {
            // dms: the web service keeps the credentials, without a registered account nothing is asked
            reset()
            loadedFilter = filter
            notify()
            return
        }
        if requestInFlight {
            pendingFilter = filter
            return
        }
        if loadedAccount == account && loadedFilter == filter {
            notify()
            return
        }
        if let complete = completeFilter, BcsDirectoryManager.contains(filter, complete) {
            items = filter.isEmpty ? completeItems : completeItems.filter { $0.matches(filter) }
            totalCount = items.count
            loadedFilter = filter
            loadedAccount = account
            lastError = nil
            NSLog("[BcsDirectory] Search [\(filter)]: \(items.count) entries, filtered locally")
            notify()
            return
        }
        guard let service = service else { return }
        requestInFlight = true
        isLoading = true
        notify()
        service.fetchDirectory(filter: filter, limit: BcsDirectoryManager.pageSize, offset: 0) { [weak self] page, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.requestInFlight = false
                self.isLoading = false
                if self.registeredAccount == account {
                    self.items = page?.Items ?? []
                    self.totalCount = page?.Count ?? 0
                    self.loadedFilter = filter
                    // after an error the search is not considered loaded, so that it can be repeated
                    self.loadedAccount = (error == nil) ? account : nil
                    self.lastError = error
                    if let error = error {
                        NSLog("[BcsDirectory] Error: \(error.localizedDescription)")
                    } else {
                        NSLog("[BcsDirectory] Search [\(filter)]: \(self.items.count) of \(self.totalCount) entries")
                        self.rememberIfComplete()
                    }
                }
                self.notify()
                self.searchPending()
            }
        }
    }

    /// dms: next page (offset = entries shown) while scrolling, until all the Count entries are loaded
    func loadNextPage() {
        guard !requestInFlight, let account = registeredAccount, loadedAccount == account,
              items.count < totalCount, let service = service else { return }
        requestInFlight = true
        let filter = loadedFilter
        let offset = items.count
        service.fetchDirectory(filter: filter, limit: BcsDirectoryManager.pageSize, offset: offset) { [weak self] page, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.requestInFlight = false
                if let page = page, self.registeredAccount == account, self.loadedAccount == account,
                   self.loadedFilter == filter, self.items.count == offset {
                    // an empty page means the directory changed: stop
                    self.totalCount = page.Items.isEmpty ? self.items.count : page.Count
                    self.items += page.Items
                    NSLog("[BcsDirectory] Search [\(filter)]: \(self.items.count) of \(self.totalCount) entries")
                    self.rememberIfComplete()
                    self.notify()
                } else if let error = error {
                    NSLog("[BcsDirectory] Error: \(error.localizedDescription)")
                }
                self.searchPending()
            }
        }
    }

    // dms: the widest complete result is remembered (the one not contained in the filter already remembered)
    private func rememberIfComplete() {
        guard items.count >= totalCount else { return }
        if let complete = completeFilter, BcsDirectoryManager.contains(loadedFilter, complete) { return }
        completeFilter = loadedFilter
        completeItems = items
    }

    private func searchPending() {
        guard let filter = pendingFilter else { return }
        pendingFilter = nil
        search(filter)
    }

    private func notify() {
        onChange?()
    }
}

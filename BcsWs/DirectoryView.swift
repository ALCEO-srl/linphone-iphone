//
//  DirectoryView.swift
//  bcsphone
//
//  Rubrica centralizzata BCS (porting da Android: activities/main/directory).
//  - DirectoryListView: ricerca libera + lista risultati (fetch-all + filtro lato client).
//  - DirectoryDetailsView: dettaglio contatto con look analogo a quello dei contatti/buddy
//    (avatar + nome + azienda + elenco campi), con i numeri chiamabili.
//
//  UI programmatica (niente xib), come le altre view Swift composite del progetto.
//

import UIKit
import Foundation
import linphonesw

// MARK: - Lista rubrica

class DirectoryListView: UIViewController, UICompositeViewDelegate, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {

    static let compositeDescription = UICompositeViewDescription(
        DirectoryListView.self,
        statusBar: StatusBarView.self,
        tabBar: TabBarView.classForCoder(),
        sideMenu: SideMenuView.self,
        fullscreen: false,
        isLeftFragment: true,
        fragmentWith: DirectoryDetailsView.classForCoder())
    static func compositeViewDescription() -> UICompositeViewDescription! { return compositeDescription }
    func compositeViewDescription() -> UICompositeViewDescription! { return type(of: self).compositeDescription }

    private let searchBar = UISearchBar()
    private let tableView = UITableView()
    private let spinner = UIActivityIndicatorView(style: .gray)
    private let emptyLabel = UILabel()

    private var items: [BcsDirectoryItem] = []
    private let cellId = "DirectoryCell"

    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
        } else {
            view.backgroundColor = .white
        }
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload(force: false)
    }

    private func setupUI() {
        // Nessuna barra del titolo: il contenuto parte sotto la barra di stato.
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.delegate = self
        searchBar.placeholder = "Cerca"
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        view.addSubview(searchBar)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 60
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellId)
        view.addSubview(tableView)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        view.addSubview(spinner)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "Nessun contatto trovato"
        emptyLabel.textColor = .gray
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
        ])
    }

    private func reload(force: Bool) {
        emptyLabel.isHidden = true
        if items.isEmpty {
            spinner.startAnimating()
        }
        BcsDirectoryManager.shared.loadDirectory(force: force) { [weak self] error in
            guard let self = self else { return }
            self.spinner.stopAnimating()
            if let error = error {
                self.emptyLabel.text = error.localizedDescription
                self.emptyLabel.isHidden = false
                self.items = []
                self.tableView.reloadData()
                return
            }
            self.applyFilter(self.searchBar.text ?? "")
        }
    }

    private func applyFilter(_ query: String) {
        items = BcsDirectoryManager.shared.filtered(query)
        emptyLabel.text = "Nessun contatto trovato"
        emptyLabel.isHidden = !items.isEmpty || spinner.isAnimating
        tableView.reloadData()
    }

    // MARK: UISearchBarDelegate

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        applyFilter(searchText)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    // MARK: UITableViewDataSource / Delegate

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId) ?? UITableViewCell(style: .subtitle, reuseIdentifier: cellId)
        let item = items[indexPath.row]
        cell.textLabel?.text = item.caption
        cell.detailTextLabel?.text = item.Company
        cell.detailTextLabel?.textColor = .gray
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        searchBar.resignFirstResponder()
        let item = items[indexPath.row]
        let detail: DirectoryDetailsView = self.VIEW(DirectoryDetailsView.compositeViewDescription())
        detail.setItem(item)
        PhoneMainView.instance().changeCurrentView(DirectoryDetailsView.compositeViewDescription())
    }
}

// MARK: - Dettaglio contatto (look analogo a ContactDetailsView)

class DirectoryDetailsView: UIViewController, UICompositeViewDelegate, UITableViewDataSource, UITableViewDelegate {

    static let compositeDescription = UICompositeViewDescription(
        DirectoryDetailsView.self,
        statusBar: StatusBarView.self,
        tabBar: TabBarView.classForCoder(),
        sideMenu: SideMenuView.self,
        fullscreen: false,
        isLeftFragment: false,
        fragmentWith: DirectoryListView.classForCoder())
    static func compositeViewDescription() -> UICompositeViewDescription! { return compositeDescription }
    func compositeViewDescription() -> UICompositeViewDescription! { return type(of: self).compositeDescription }

    // Tipo di riga: semplice (nessuna azione), telefono (solo chiamata), SIP (chiamata + chat).
    private enum RowKind { case plain, phone, sip }

    // Riga del dettaglio: didascalia, valore e tipo.
    private struct Row {
        let caption: String
        let value: String
        let kind: RowKind
    }

    private let topBar = UIView()
    private let backButton = UIButton(type: .custom)
    private let avatarImage = UIImageView()
    private let nameLabel = UILabel()
    private let companyLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)

    private var item: BcsDirectoryItem?
    private var rows: [Row] = []
    private let cellId = "DirectoryDetailCell"

    @objc func setItem(_ item: BcsDirectoryItem) {
        self.item = item
        rebuildRows()
        if isViewLoaded { refreshUI() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
        } else {
            view.backgroundColor = .white
        }
        setupUI()
        refreshUI()
    }

    private func setupUI() {
        // Top bar con solo il pulsante "indietro" (come ContactDetailsView).
        topBar.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 13.0, *) {
            topBar.backgroundColor = .secondarySystemBackground
        } else {
            topBar.backgroundColor = UIColor(white: 0.95, alpha: 1.0)
        }
        view.addSubview(topBar)

        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.setImage(UIImage(named: "back_default.png"), for: .normal)
        backButton.imageView?.contentMode = .scaleAspectFit
        backButton.addTarget(self, action: #selector(onBack), for: .touchUpInside)
        topBar.addSubview(backButton)

        // Avatar + nome + azienda centrati.
        avatarImage.translatesAutoresizingMaskIntoConstraints = false
        avatarImage.contentMode = .scaleAspectFit
        avatarImage.image = UIImage(named: "avatar.png")
        view.addSubview(avatarImage)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .boldSystemFont(ofSize: 20)
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 0
        view.addSubview(nameLabel)

        companyLabel.translatesAutoresizingMaskIntoConstraints = false
        companyLabel.font = .systemFont(ofSize: 14)
        companyLabel.textColor = .gray
        companyLabel.textAlignment = .center
        view.addSubview(companyLabel)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellId)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 66),

            backButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 8),
            backButton.topAnchor.constraint(equalTo: topBar.topAnchor),
            backButton.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 60),

            avatarImage.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 10),
            avatarImage.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            avatarImage.widthAnchor.constraint(equalToConstant: 90),
            avatarImage.heightAnchor.constraint(equalToConstant: 90),

            nameLabel.topAnchor.constraint(equalTo: avatarImage.bottomAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            companyLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            companyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            companyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            tableView.topAnchor.constraint(equalTo: companyLabel.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func rebuildRows() {
        guard let item = item else { rows = []; return }
        var r: [Row] = []
        func add(_ caption: String, _ value: String, kind: RowKind = .plain) {
            if !value.isEmpty { r.append(Row(caption: caption, value: value, kind: kind)) }
        }
        add("Indirizzo SIP", item.Uri, kind: .sip)
        add("Cellulare", item.MobilePhone, kind: .phone)
        add("Telefono fisso", item.LandlinePhone, kind: .phone)
        add("Fax", item.FaxPhone)
        add("Email", item.EmailAddress)
        add("Indirizzo", item.Address)
        add("Titolo", item.Title)
        add("Professione", item.Profession)
        add("Azienda", item.Company)
        add("Filiale", item.Branch)
        add("Ufficio", item.Office)
        add("Responsabile", item.Manager)
        add("Assistente", item.Assistant)
        rows = r
    }

    private func refreshUI() {
        nameLabel.text = item?.caption ?? ""
        companyLabel.text = item?.Company ?? ""
        companyLabel.isHidden = (item?.Company.isEmpty ?? true)
        tableView.reloadData()
    }

    @objc private func onBack() {
        PhoneMainView.instance().popView(self.compositeViewDescription())
    }

    private func startCall(_ value: String) {
        guard let address = Core.get().interpretUrl(url: value, applyInternationalPrefix: true) else {
            NSLog("[BcsDirectory] impossibile interpretare l'indirizzo: \(value)")
            return
        }
        CallManager.instance().startCall(addr: address.getCobject, isSas: false, isVideo: false)
    }

    private func startChat(_ value: String) {
        guard let address = Core.get().interpretUrl(url: value, applyInternationalPrefix: true) else {
            NSLog("[BcsDirectory] impossibile interpretare l'indirizzo: \(value)")
            return
        }
        PhoneMainView.instance().getOrCreateOne(toOneChatRoom: address.getCobject, wait: self.view, isEncrypted: false)
    }

    @objc private func onCallTapped(_ sender: UIButton) {
        guard sender.tag >= 0 && sender.tag < rows.count else { return }
        startCall(rows[sender.tag].value)
    }

    @objc private func onChatTapped(_ sender: UIButton) {
        guard sender.tag >= 0 && sender.tag < rows.count else { return }
        startChat(rows[sender.tag].value)
    }

    private func makeIconButton(_ imageName: String, action: Selector, tag: Int) -> UIButton {
        let b = UIButton(type: .custom)
        b.setImage(UIImage(named: imageName), for: .normal)
        b.imageView?.contentMode = .scaleAspectFit
        b.tag = tag
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    // Costruisce le icone-azione a destra della riga: chiamata per i telefoni; chiamata +
    // chat per gli indirizzi SIP (come Android). L'azione parte dal tap sull'icona.
    private func makeActionAccessory(kind: RowKind, rowIndex: Int) -> UIView? {
        let size: CGFloat = 40
        let gap: CGFloat = 8
        switch kind {
        case .plain:
            return nil
        case .phone:
            let container = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
            let call = makeIconButton("call_start_body_default.png", action: #selector(onCallTapped(_:)), tag: rowIndex)
            call.frame = CGRect(x: 0, y: 0, width: size, height: size)
            container.addSubview(call)
            return container
        case .sip:
            let container = UIView(frame: CGRect(x: 0, y: 0, width: size * 2 + gap, height: size))
            let call = makeIconButton("call_start_body_default.png", action: #selector(onCallTapped(_:)), tag: rowIndex)
            call.frame = CGRect(x: 0, y: 0, width: size, height: size)
            let chat = makeIconButton("chat_start_body_default.png", action: #selector(onChatTapped(_:)), tag: rowIndex)
            chat.frame = CGRect(x: size + gap, y: 0, width: size, height: size)
            container.addSubview(call)
            container.addSubview(chat)
            return container
        }
    }

    // MARK: UITableViewDataSource / Delegate

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: cellId)
        let row = rows[indexPath.row]
        cell.textLabel?.text = row.value
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.text = row.caption
        cell.detailTextLabel?.textColor = .gray
        cell.selectionStyle = .none   // l'azione parte dalle icone, non dalla riga
        cell.accessoryView = makeActionAccessory(kind: row.kind, rowIndex: indexPath.row)
        return cell
    }
}

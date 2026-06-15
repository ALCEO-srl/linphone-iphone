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
}

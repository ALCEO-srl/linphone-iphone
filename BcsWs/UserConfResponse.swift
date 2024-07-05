//
//  UserConfResponse.swift
//  bcsphone
//
//  Created by alceo on 02/07/24.
//

import Foundation

// Modello per l'utente
@objc public class UserConfResponse: NSObject, Codable {
    @objc let id: String
    let presRules: PresRules
    @objc let misc: Misc
    let routingProfile: RoutingProfile
    let main: Main
    let dataHome: DataHome
    let competences: Competences
    let dataOffice: DataOffice
    
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case presRules = "PresRules"
        case misc = "Misc"
        case routingProfile = "RoutingProfile"
        case main = "Main"
        case dataHome = "DataHome"
        case competences = "Competences"
        case dataOffice = "DataOffice"
    }
}

struct PresRules: Codable {
    let blocked: [String]
    let pending: [String]
    let allowed: [String]
    enum CodingKeys: String, CodingKey {
        case blocked = "Blocked"
        case pending = "Pending"
        case allowed = "Allowed"
    }
}

@objc public class Misc: NSObject, Codable {
    let lastUploadError: Int
    let beepOnIMMessage: String
    let logUploadStatus: Int
    let enhancedBusyBehaviour: Int
    let authenticationPassword: String
    let autoAnswer: Bool
    let displayNameOnly: String
    @objc let buddies: [BuddyGroup]
    
    enum CodingKeys: String, CodingKey {
        case lastUploadError = "LastUploadError"
        case beepOnIMMessage = "BeepOnIMMessage"
        case logUploadStatus = "LogUploadStatus"
        case enhancedBusyBehaviour = "EnanchedBusyBehaviour"
        case authenticationPassword = "AuthenticationPassword"
        case autoAnswer = "AutoAnswer"
        case displayNameOnly = "DisplayNameOnly"
        case buddies = "Buddies"
    }
}

@objc public class BuddyGroup: NSObject, Codable {
    @objc let name: String
    @objc let members: [Buddy]
    
    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case members = "Members"
    }
}

@objc public class Buddy: NSObject, Codable {
    @objc let displayName: String
    @objc let uri: String
    @objc let buddy: Bool
    
    enum CodingKeys: String, CodingKey {
        case displayName = "DisplayName"
        case uri = "Uri"
        case buddy = "Buddy"
    }
}

struct RoutingProfile: Codable {
    let note: String
    let voiceMail: Bool
    let dnd: Bool
    let altPhoneURIChoice: String
    let ucfTo: String
    let ucfToEnabled: Bool
    let altPhone: String
    
    enum CodingKeys: String, CodingKey {
        case note = "Note"
        case voiceMail = "VoiceMail"
        case dnd = "DND"
        case altPhoneURIChoice = "AltPhoneURIChoice"
        case ucfTo = "UCFTo"
        case ucfToEnabled = "UCFTo-Enabled"
        case altPhone = "AltPhone"
    }
}

struct Main: Codable {
    let displayName: String
    let name: String
    let accountType: String
    let surname: String
    
    enum CodingKeys: String, CodingKey {
        case displayName = "DisplayName"
        case name = "Name"
        case accountType = "AccountType"
        case surname = "Surname"
    }
}

struct DataHome: Codable {
    let phone: String
    
    enum CodingKeys: String, CodingKey {
        case phone = "Phone"
    }
}

struct Competences: Codable {
    let notAssignedCompetences: [Competence]
    let assignedReadOnlyCompetences: [Competence]
    let assignedCompetences: [Competence]
    
    enum CodingKeys: String, CodingKey {
        case notAssignedCompetences = "NotAssignedCompetences"
        case assignedReadOnlyCompetences = "AssignedReadOnlyCompetences"
        case assignedCompetences = "AssignedCompetences"
    }
}

struct Competence: Codable {
    let id: String
    let rank: String
    
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case rank = "Rank"
    }
}

struct DataOffice: Codable {
    let assistant: String
    let officeManager: String
    let field2: String
    let phone: String
    let field6: String
    let field10: String
    let field4: String
    let field1: String
    let fax: String
    let mobile: String
    let field5: String
    let homePage: String
    let field8: String
    let mail: String
    let field9: String
    let company: String
    let office: String
    let department: String
    let icon: String
    let field7: String
    let position: String
    let field3: String
    let address: String
    
    enum CodingKeys: String, CodingKey {
        case assistant = "Assistant"
        case officeManager = "OfficeManager"
        case field2 = "Field2"
        case phone = "Phone"
        case field6 = "Field6"
        case field10 = "Field10"
        case field4 = "Field4"
        case field1 = "Field1"
        case fax = "Fax"
        case mobile = "Mobile"
        case field5 = "Field5"
        case homePage = "HomePage"
        case field8 = "Field8"
        case mail = "Mail"
        case field9 = "Field9"
        case company = "Company"
        case office = "Office"
        case department = "Department"
        case icon = "Icon"
        case field7 = "Field7"
        case position = "Position"
        case field3 = "Field3"
        case address = "Address"
    }
}

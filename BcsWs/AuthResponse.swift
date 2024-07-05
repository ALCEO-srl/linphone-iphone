//
//  AuthResponse.swift
//  
//
//  Created by alceo on 02/07/24.
//

import Foundation

/*
 {
     "access_token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJpc3MiOiJCY3NXcyIsInN1YiI6ImNodWNrQGFsY2VvLmNvbSIsImlhdCI6MTcxOTk5MTAxNiwiZXhwIjoxNzIwMDc3NDE2LCJzY29wZSI6InN1cGVydiB1c2VyIn0.UKrrOw3QSRIfur-xidXm670nQ5glRoOzm-0bac5Oez1GXArVBKbX-Yjm6AetcDqwTv9QXeuoqgXALbuoLcOPtE4yfkgTXU-hQNT7-w3v8ppjisIGrsJFHs2AgJ5FWfk1TJf3d13YWdkK7MEH_ItahicEn0KyG9CCoaWfahW5r5EZYe_EHWw23xrLwJu91Eoze6QUlZy8ZrHjzn49YnhklZoYAk-o4HWouecLSiW6lN7k_I3htGE8t51gLtyO7QhV7DXfya_V2iWaUUZ2Uob-PrXNh_9035jym4REu1KgUa3wvrXAG8dyZShDIHHg27tIuaLKV-N_9vQSPE_WPbk_ztxkXWzt2mmpwLXQvNg-JsBTViBQ8f8DKVsNpFmbFPl8UfTN_RLpRN0MrrbeNHDMymF0v1BMjw8maYrsitNq9Nxr401WYZy5P8W4-8lNsmU8-9pNnahpIMvc3JP6ZZyoIgiaHwQRF_5qUgS1uMMJXns2Il8dqRsiQ_uOINrmIZcb",
     "token_type": "Bearer",
     "expires_in": 86400
 }
 */

public struct AuthResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expireIn: Int
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expireIn = "expires_in"
    }
}

//
//  BcsWsService.swift
//  bcsphone
//
//  Created by alceo on 02/07/24.
//

import Foundation

@objc public class BcsWsService: NSObject {
    private var bearerToken: String = ""
    @objc private var user: String = ""
    @objc private var domain: String = ""
    @objc private var password: String = ""
    private let server: String
    private let port: String

    @objc init(server: String, port: String) {
        self.server = server
        self.port = port
    }
    

    @objc func setUserInfo(user: String, domain: String, password: String) {
        self.user = user
        self.domain = domain
        self.password = password
        self.bearerToken = ""
    }

    private var baseUrl: URL {
        return URL(string: "https://\(server):\(port)/\(domain)/")!
    }

    private func getUrl(for endpoint: String) -> URL {
        return baseUrl.appendingPathComponent(endpoint)
    }
    
    private func requestAuthToken(completion: @escaping (Error?) -> Void) {
        guard bearerToken.isEmpty else {
            completion(nil)
            return
        }

        let credentials = "\(user)@\(domain):\(password)"
        let base64Credentials = Data(credentials.utf8).base64EncodedString()
        let url = getUrl(for: "bcsws/v1/domains/\(domain)/authtoken")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=client_credentials".data(using: .utf8)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
              NSLog("Request failed with error: \(error.localizedDescription)")
              completion(error)
              return
            }
            guard let response = response else  {
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"]))
                return
            }
            guard let data = data else {
                completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
             
                if httpResponse.statusCode >= 300 {
                  // Leggi la risposta del server anche in caso di errore
                  let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response data"
                  NSLog("HTTP Error: \(httpResponse.statusCode). Response: \(responseBody)")
                    completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: responseBody]))
                } else {
                    do {
                        let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response data"
                        NSLog("HTTP Status: \(httpResponse.statusCode). Response: \(responseBody)")
                        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
                        self.bearerToken = authResponse.accessToken
                        NSLog(String(format: "requestAuthToken: bearerToken=%@", self.bearerToken))
                        completion(nil)
                    } catch {
                        completion(error)
                    }
                    
                }
            }
        }
        task.resume()
    }
    
    @objc public func fetchUserConf(completion: @escaping (UserConfResponse?, NSError?) -> Void) {
        requestAuthToken { error in
            if let error = error {
                completion(nil, error as NSError)
                return
            }

            let url = self.getUrl(for: "bcsws/v1/domains/\(self.domain)/users/\(self.user)")
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(self.bearerToken)", forHTTPHeaderField: "Authorization")

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(nil, error as NSError)
                    return
                }
                guard let response = response else  {
                    completion(nil, NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"]))
                    return
                }
                guard let data = data else {
                    completion(nil, NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                 
                    if httpResponse.statusCode >= 300 {
                      // Leggi la risposta del server anche in caso di errore
                      let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response data"
                      NSLog("HTTP Error: \(httpResponse.statusCode). Response: \(responseBody)")
                      completion(nil, NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: responseBody]))
                    } else {
                        do {
                            let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response data"
                            NSLog("HTTP Status: \(httpResponse.statusCode). Response: \(responseBody)")
                           
                            let userConf = try JSONDecoder().decode(UserConfResponse.self, from: data)
                            completion(userConf, nil)
                        }  catch {
                            completion(nil, error as NSError)
                        }
                        
                    }
                }
   
            }
            task.resume()
        }
    }

    /*
    @objc public func fetchDirectory(filter: String, completion: @escaping (DirectoryResponse?, Error?) -> Void) {
        requestAuthToken { error in
            if let error = error {
                completion(nil, error)
                return
            }

            let url = self.getUrl(for: "bcsws/v1/domains/\(self.domain)/directory?limit=10000&filter=\(filter)")
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(self.bearerToken)", forHTTPHeaderField: "Authorization")

            let task = URLSession.shared.dataTask(with: request) { data, _, error in
                if let error = error {
                    completion(nil, error)
                    return
                }
                guard let data = data else {
                    completion(nil, NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))
                    return
                }
                do {
                    let directoryResponse = try JSONDecoder().decode(DirectoryResponse.self, from: data)
                    completion(directoryResponse, nil)
                } catch {
                    completion(error as NSError)
                }
            }
            task.resume()
        }
    }
    */
}

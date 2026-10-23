//
//  BcsWsService.swift
//  bcsphone
//
//  Created by alceo on 02/07/24.
//

import Foundation

@objc public class BcsWsService: NSObject {
    private var bearerToken: String = ""
    private var tokenExpiry: Date = .distantPast
    private static let tokenExpiryMargin: TimeInterval = 60 // rinnova 60s prima della scadenza
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
        self.tokenExpiry = .distantPast
    }

    private var baseUrl: URL {
        return URL(string: "https://\(server):\(port)/\(domain)/")!
    }

    private func getUrl(for endpoint: String) -> URL {
        return baseUrl.appendingPathComponent(endpoint)
    }
    
    private func requestAuthToken(completion: @escaping (Error?) -> Void) {
        guard bearerToken.isEmpty || Date() >= tokenExpiry else {
            completion(nil)
            return
        }

        let credentials = "\(user)@\(domain):\(password)"
        let base64Credentials = Data(credentials.utf8).base64EncodedString()
        let url = getUrl(for: "bcsws/v1/domains/\(domain)/authtoken")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
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
                        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(authResponse.expireIn) - BcsWsService.tokenExpiryMargin)
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

    // MARK: - Richiesta autenticata generica

    private var userBasePath: String {
        return "bcsws/v1/domains/\(domain)/users/\(user)"
    }

    /// Costruisce un URL a partire dal base path con eventuali query items.
    private func buildUrl(path: String, query: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(url: baseUrl.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            return nil
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        return components.url
    }

    /// Esegue una richiesta autenticata garantendo un token valido. Gestisce gli status
    /// di errore (400/403/404/500, …) restituendo un NSError con il body del server.
    private func authedRequest(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        completion: @escaping (Data?, NSError?) -> Void
    ) {
        requestAuthToken { error in
            if let error = error {
                completion(nil, error as NSError)
                return
            }
            guard let url = self.buildUrl(path: path, query: query) else {
                completion(nil, NSError(domain: "BcsWs", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 30
            request.setValue("Bearer \(self.bearerToken)", forHTTPHeaderField: "Authorization")
            if let body = body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(nil, error as NSError)
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    completion(nil, NSError(domain: "BcsWs", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"]))
                    return
                }
                if httpResponse.statusCode >= 300 {
                    let responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "HTTP \(httpResponse.statusCode)"
                    NSLog("[BcsWs] HTTP Error \(httpResponse.statusCode) on \(method) \(path): \(responseBody)")
                    completion(nil, NSError(domain: "BcsWs", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: responseBody]))
                    return
                }
                completion(data, nil)
            }
            task.resume()
        }
    }

    // MARK: - Registro chiamate (/callreport)

    func fetchCallReport(limit: Int, offset: Int, completion: @escaping (BcsCallReportResponse?, NSError?) -> Void) {
        // dms: one log line per request, to count them
        NSLog("[BcsWs] callreport limit=\(limit) offset=\(offset)")
        let query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        authedRequest(path: "\(userBasePath)/callreport", method: "GET", query: query) { data, error in
            if let error = error { completion(nil, error); return }
            guard let data = data else {
                completion(nil, NSError(domain: "BcsWs", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))
                return
            }
            do {
                let response = try JSONDecoder().decode(BcsCallReportResponse.self, from: data)
                completion(response, nil)
            } catch {
                completion(nil, error as NSError)
            }
        }
    }

    // dms: returns the entry added by the server (with its Id), so that it can be put on top of the cache
    func addCallReport(item: BcsCallReportItem, completion: @escaping (BcsCallReportItem?, NSError?) -> Void) {
        let body: Data
        do {
            body = try JSONEncoder().encode(item)
        } catch {
            completion(nil, error as NSError)
            return
        }
        authedRequest(path: "\(userBasePath)/callreport", method: "POST", body: body) { data, error in
            if let error = error { completion(nil, error); return }
            let added = data.flatMap { try? JSONDecoder().decode(BcsCallReportItem.self, from: $0) }
            completion(added, nil)
        }
    }

    func clearCallReport(completion: @escaping (NSError?) -> Void) {
        authedRequest(path: "\(userBasePath)/callreport", method: "DELETE") { _, error in
            completion(error)
        }
    }

    func deleteCallReportItem(id: String, completion: @escaping (NSError?) -> Void) {
        authedRequest(path: "\(userBasePath)/callreport/\(id)", method: "DELETE") { _, error in
            completion(error)
        }
    }

    // MARK: - Rubrica (/directory)

    // dms: one page of the directory searched on the server (filter on all the fields, Count = total of the results).
    // Empty filter = parameter omitted. Alphabetical order from the server.
    func fetchDirectory(filter: String, limit: Int, offset: Int, completion: @escaping (BcsDirectoryResponse?, NSError?) -> Void) {
        NSLog("[BcsWs] directory filter=[\(filter)] limit=\(limit) offset=\(offset)")
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "sortBy", value: "asc(Name)")
        ]
        if !filter.isEmpty {
            query.append(URLQueryItem(name: "filter", value: filter))
        }
        authedRequest(path: "bcsws/v1/domains/\(domain)/directory", method: "GET", query: query) { data, error in
            if let error = error { completion(nil, error); return }
            guard let data = data else {
                completion(nil, NSError(domain: "BcsWs", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"]))
                return
            }
            do {
                let response = try JSONDecoder().decode(BcsDirectoryResponse.self, from: data)
                completion(response, nil)
            } catch {
                completion(nil, error as NSError)
            }
        }
    }
}

/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 `ContentKeyDelegate` is a class that implements the `AVContentKeySessionDelegate` protocol to respond to content key
 requests using FairPlay Streaming.
 */

import AVFoundation
@objc(ContentKeyDelegate)
public class ContentKeyDelegate: NSObject, AVContentKeySessionDelegate {
    
    // MARK: Types
    var currentAsset: Asset? = nil
    enum ProgramError: Error {
        case missingApplicationCertificate
        case noCKCReturnedByKSM
    }
    
    // MARK: Properties
    
    /// The directory that is used to save persistable content keys.
    lazy var contentKeyDirectory: URL = {
        guard let documentPath =
            NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
                fatalError("Unable to determine library URL")
        }
        
        let documentURL = URL(fileURLWithPath: documentPath)
        
        let contentKeyDirectory = documentURL.appendingPathComponent(".keys", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: contentKeyDirectory.path, isDirectory: nil) {
            do {
                try FileManager.default.createDirectory(at: contentKeyDirectory,
                                                    withIntermediateDirectories: false,
                                                    attributes: nil)
            } catch {
                fatalError("Unable to create directory for content keys at path: \(contentKeyDirectory.path)")
            }
        }
        
        return contentKeyDirectory
    }()
    
    /// A set containing the currently pending content key identifiers associated with persistable content key requests that have not been completed.
    var pendingPersistableContentKeyIdentifiers = Set<String>()
    
    /// A dictionary mapping content key identifiers to their associated stream name.
    var contentKeyToStreamNameMap = [String: String]()
    
    func requestApplicationCertificate() throws -> Data {
        
//        // MARK: ADAPT - You must implement this method to retrieve your FPS application certificate.
//        let applicationCertificate: Data? = nil
//
//        guard applicationCertificate != nil else {
//            throw ProgramError.missingApplicationCertificate
//        }
//
//        return applicationCertificate!
        
        // MARK: ADAPT - You must implement this method to retrieve your FPS application certificate.
        var applicationCertificate: Data? = nil

        do {
            if let certUrl = Bundle.main.path(forResource: "fairplay", ofType: "cer") {
                applicationCertificate = try Data.init(contentsOf:  URL.init(fileURLWithPath: certUrl), options: .mappedIfSafe)
            }
            
//            applicationCertificate = AssetPersistenceManager.sharedManager.delegate?.contentCertificate()
        } catch {
            print("Cannot loading FairPlay application certificate. Detail are :\(error)")
        }
        
        guard applicationCertificate != nil else {
            throw ProgramError.missingApplicationCertificate
        }
        
        return applicationCertificate!
    }
    
    func requestContentKeyFromKeySecurityModule(spcData: Data, assetID: String) throws -> Data {
        
//        // MARK: ADAPT - You must implement this method to request a CKC from your KSM.
//
//        let ckcData: Data? = nil
//
//        guard ckcData != nil else {
//            throw ProgramError.noCKCReturnedByKSM
//        }
//
//        return ckcData!
        
        var ckcData: Data? = nil
        let drmUrl = currentAsset?.stream.licenseUrl ?? ""
        let semaphore = DispatchSemaphore(value: 0)
        let postString = "spc=\(spcData.base64EncodedString())&assetId=\(assetID)"
        
        if let postData = postString.data(using: .ascii, allowLossyConversion: true), let drmServerUrl = URL(string: drmUrl) {
            var request = URLRequest(url: drmServerUrl)
            request.httpMethod = "POST"
            request.setValue(String(postData.count), forHTTPHeaderField: "Content-Length")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            if let headers = self.currentAsset?.stream.header {
                for keyItem in headers.allKeys {
                    let key = keyItem as! String
                    let value = headers.value(forKey: key) as? String
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }
            request.httpBody = postData
            
            URLSession.shared.dataTask(with: request) { (data, response, error) in
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    print("The access token was expired.")
                }else if let data = data, var responseString = String(data: data, encoding: .utf8) {
                    responseString = responseString.replacingOccurrences(of: "<ckc>", with: "").replacingOccurrences(of: "</ckc>", with: "")
                    print("the ckc content is \(responseString)")
                    ckcData = Data(base64Encoded: responseString)
                    } else {
                        print("Error encountered while fetching FairPlay license for URL: \(drmUrl), \(error?.localizedDescription ?? "Unknown error")")
                    }
                semaphore.signal()
            }.resume()
        } else {
            fatalError("Invalid post data")
        }
        
        semaphore.wait()
        guard ckcData != nil else {
            throw ProgramError.noCKCReturnedByKSM
        }
        return ckcData!
    }

    /// Preloads all the content keys associated with an Asset for persisting on disk.
    ///
    /// It is recommended you use AVContentKeySession to initiate the key loading process
    /// for online keys too. Key loading time can be a significant portion of your playback
    /// startup time because applications normally load keys when they receive an on-demand
    /// key request. You can improve the playback startup experience for your users if you
    /// load keys even before the user has picked something to play. AVContentKeySession allows
    /// you to initiate a key loading process and then use the key request you get to load the
    /// keys independent of the playback session. This is called key preloading. After loading
    /// the keys you can request playback, so during playback you don't have to load any keys,
    /// and the playback decryption can start immediately.
    ///
    /// In this sample use the Streams.plist to specify your own content key identifiers to use
    /// for loading content keys for your media. See the README document for more information.
    ///
    /// - Parameter asset: The `Asset` to preload keys for.
    func requestPersistableContentKeys(forAsset asset: Asset) {
        self.currentAsset = asset
        for identifier in asset.stream.contentKeyIDList ?? [] {
            
            guard let contentKeyIdentifierURL = URL(string: identifier) else { continue }
            guard let assetIDString = contentKeyIdentifierURL.queryParameters?["kid"] ?? contentKeyIdentifierURL.host else { continue }
            pendingPersistableContentKeyIdentifiers.insert(assetIDString)
            contentKeyToStreamNameMap[assetIDString] = asset.stream.name
            ContentKeyManager.shared.contentKeySession.processContentKeyRequest(withIdentifier: identifier, initializationData: nil, options: nil)
        }
    }
    
    /// Returns whether or not a content key should be persistable on disk.
    ///
    /// - Parameter identifier: The asset ID associated with the content key request.
    /// - Returns: `true` if the content key request should be persistable, `false` otherwise.
    func shouldRequestPersistableContentKey(withIdentifier identifier: String) -> Bool {
        return pendingPersistableContentKeyIdentifiers.contains(identifier)
    }
    
    // MARK: AVContentKeySessionDelegate Methods
    
    /*
     The following delegate callback gets called when the client initiates a key request or AVFoundation
     determines that the content is encrypted based on the playlist the client provided when it requests playback.
     */
    public func contentKeySession(_ session: AVContentKeySession, didProvide keyRequest: AVContentKeyRequest) {
        handleStreamingContentKeyRequest(keyRequest: keyRequest)
    }
    
    /*
     Provides the receiver with a new content key request representing a renewal of an existing content key.
     Will be invoked by an AVContentKeySession as the result of a call to -renewExpiringResponseDataForContentKeyRequest:.
     */
    func contentKeySession(_ session: AVContentKeySession, didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest) {
        handleStreamingContentKeyRequest(keyRequest: keyRequest)
    }
    
    
    /*
     Provides the receiver a content key request that should be retried because a previous content key request failed.
     Will be invoked by an AVContentKeySession when a content key request should be retried. The reason for failure of
     previous content key request is specified. The receiver can decide if it wants to request AVContentKeySession to
     retry this key request based on the reason. If the receiver returns YES, AVContentKeySession would restart the
     key request process. If the receiver returns NO or if it does not implement this delegate method, the content key
     request would fail and AVContentKeySession would let the receiver know through
     -contentKeySession:contentKeyRequest:didFailWithError:.
     */
    func contentKeySession(_ session: AVContentKeySession, shouldRetry keyRequest: AVContentKeyRequest,
                           reason retryReason: AVContentKeyRequestRetryReason) -> Bool {
        
        var shouldRetry = false
        
        switch retryReason {
            /*
             Indicates that the content key request should be retried because the key response was not set soon enough either
             due the initial request/response was taking too long, or a lease was expiring in the meantime.
             */
        case AVContentKeyRequestRetryReason.timedOut:
            shouldRetry = true
            
            /*
             Indicates that the content key request should be retried because a key response with expired lease was set on the
             previous content key request.
             */
        case AVContentKeyRequestRetryReason.receivedResponseWithExpiredLease:
            shouldRetry = true
            
            /*
             Indicates that the content key request should be retried because an obsolete key response was set on the previous
             content key request.
             */
        case AVContentKeyRequestRetryReason.receivedObsoleteContentKey:
            shouldRetry = true
            
        default:
            break
        }
        
        return shouldRetry
    }
    
    // Informs the receiver a content key request has failed.
    func contentKeySession(_ session: AVContentKeySession, contentKeyRequest keyRequest: AVContentKeyRequest, didFailWithError err: Error) {
        // Add your code here to handle errors.  
        var userInfo = [String: Any]()
        userInfo[Asset.Keys.identifier] = keyRequest.identifier 
//        NotificationCenter.default.post(name: .AssetDownloadFail, object: nil, userInfo: userInfo)
    }

    
    // MARK: API
    
    func handleStreamingContentKeyRequest(keyRequest: AVContentKeyRequest) {
        guard let contentKeyIdentifierString = keyRequest.identifier as? String,
            let contentKeyIdentifierURL = URL(string: contentKeyIdentifierString),
            let assetIDString = contentKeyIdentifierURL.queryParameters?["kid"] ?? contentKeyIdentifierURL.host,
            let assetIDData = assetIDString.data(using: .utf8)
            else {
                print("Failed to retrieve the assetID from the keyRequest!")
                return
        }

        let provideOnlinekey: () -> Void = { () -> Void in

            do {
                let applicationCertificate = try self.requestApplicationCertificate()

                let completionHandler = { [weak self] (spcData: Data?, error: Error?) in
                    guard let strongSelf = self else { return }
                    if let error = error {
                        keyRequest.processContentKeyResponseError(error)
                        return
                    }

                    guard let spcData = spcData else { return }

                    do {
                        // Send SPC to Key Server and obtain CKC
                        let ckcData = try strongSelf.requestContentKeyFromKeySecurityModule(spcData: spcData, assetID: assetIDString)

                        /*
                         AVContentKeyResponse is used to represent the data returned from the key server when requesting a key for
                         decrypting content.
                         */
                        let keyResponse = AVContentKeyResponse(fairPlayStreamingKeyResponseData: ckcData)

                        /*
                         Provide the content key response to make protected content available for processing.
                         */
                        keyRequest.processContentKeyResponse(keyResponse)
                    } catch {
                        keyRequest.processContentKeyResponseError(error)
                    }
                }

                keyRequest.makeStreamingContentKeyRequestData(forApp: applicationCertificate,
                                                              contentIdentifier: assetIDData,
                                                              options: [AVContentKeyRequestProtocolVersionsKey: [1]],
                                                              completionHandler: completionHandler)
            } catch {
                keyRequest.processContentKeyResponseError(error)
            }
        }

        #if os(iOS)
            /*
             When you receive an AVContentKeyRequest via -contentKeySession:didProvideContentKeyRequest:
             and you want the resulting key response to produce a key that can persist across multiple
             playback sessions, you must invoke -respondByRequestingPersistableContentKeyRequest on that
             AVContentKeyRequest in order to signal that you want to process an AVPersistableContentKeyRequest
             instead. If the underlying protocol supports persistable content keys, in response your
             delegate will receive an AVPersistableContentKeyRequest via -contentKeySession:didProvidePersistableContentKeyRequest:.
             */
            if shouldRequestPersistableContentKey(withIdentifier: assetIDString) ||
                persistableContentKeyExistsOnDisk(withContentKeyIdentifier: assetIDString) {
                
                // Request a Persistable Key Request.
                do {
                    try keyRequest.respondByRequestingPersistableContentKeyRequestAndReturnError()
                } catch {

                    /*
                    This case will occur when the client gets a key loading request from an AirPlay Session.
                    You should answer the key request using an online key from your key server.
                    */
                    provideOnlinekey()
                }
                
                return
            }
        #endif
        
        provideOnlinekey()
    }
    
    ///
    
    /*
     Provides the receiver with a new content key request that allows key persistence.
     Will be invoked by an AVContentKeyRequest as the result of a call to
     -respondByRequestingPersistableContentKeyRequest.
     */
//    func contentKeySession(_ session: AVContentKeySession, didProvide keyRequest: AVPersistableContentKeyRequest) {
//        handlePersistableContentKeyRequest(keyRequest: keyRequest)
//    }
    
    public func contentKeySession(_ session: AVContentKeySession, didProvide keyRequest: AVPersistableContentKeyRequest) {
        handlePersistableContentKeyRequest(keyRequest: keyRequest)
    }
    
    /*
     Provides the receiver with an updated persistable content key for a particular key request.
     If the content key session provides an updated persistable content key data, the previous
     key data is no longer valid and cannot be used to answer future loading requests.
     
     This scenario can occur when using the FPS "dual expiry" feature which allows you to define
     and customize two expiry windows for FPS persistent keys. The first window is the storage
     expiry window which starts as soon as the persistent key is created. The other window is a
     playback expiry window which starts when the persistent key is used to start the playback
     of the media content.
     
     Here's an example:
     
     When the user rents a movie to play offline you would create a persistent key with a CKC that
     opts in to use this feature. This persistent key is said to expire at the end of storage expiry
     window which is 30 days in this example. You would store this persistent key in your apps storage
     and use it to answer a key request later on. When the user comes back within these 30 days and
     asks you to start playback of the content, you will get a key request and would use this persistent
     key to answer the key request. At that point, you will get sent an updated persistent key which
     is set to expire at the end of playback experiment which is 24 hours in this example.
     */
    func contentKeySession(_ session: AVContentKeySession,
                           didUpdatePersistableContentKey persistableContentKey: Data,
                           forContentKeyIdentifier keyIdentifier: Any) {
        /*
         The key ID is the URI from the EXT-X-KEY tag in the playlist (e.g. "skd://key65") and the
         asset ID in this case is "key65".
         */
        guard let contentKeyIdentifierString = keyIdentifier as? String,
            let contentKeyIdentifierURL = URL(string: contentKeyIdentifierString),
            let assetIDString = contentKeyIdentifierURL.queryParameters?["kid"] ?? contentKeyIdentifierURL.host
            else {
                print("Failed to retrieve the assetID from the keyRequest!")
                return
        }
        
        do {
            deletePeristableContentKey(withContentKeyIdentifier: assetIDString)
            
            try writePersistableContentKey(contentKey: persistableContentKey, withContentKeyIdentifier: assetIDString)
        } catch {
            print("Failed to write updated persistable content key to disk: \(error.localizedDescription)")
        }
    }
    
    // MARK: API.
    
    /// Handles responding to an `AVPersistableContentKeyRequest` by determining if a key is already available for use on disk.
    /// If no key is available on disk, a persistable key is requested from the server and securely written to disk for use in the future.
    /// In both cases, the resulting content key is used as a response for the `AVPersistableContentKeyRequest`.
    ///
    /// - Parameter keyRequest: The `AVPersistableContentKeyRequest` to respond to.
    func handlePersistableContentKeyRequest(keyRequest: AVPersistableContentKeyRequest) {
        
        /*
         The key ID is the URI from the EXT-X-KEY tag in the playlist (e.g. "skd://key65") and the
         asset ID in this case is "key65".
         */
        guard let contentKeyIdentifierString = keyRequest.identifier as? String,
            let contentKeyIdentifierURL = URL(string: contentKeyIdentifierString),
            let assetIDString = contentKeyIdentifierURL.queryParameters?["kid"] ?? contentKeyIdentifierURL.host,
            let assetIDData = assetIDString.data(using: .utf8)
            else {
                print("Failed to retrieve the assetID from the keyRequest!")
                return
        }
        
        do {

            let completionHandler = { [weak self] (spcData: Data?, error: Error?) in
                guard let strongSelf = self else { return }
                if let error = error {
                    keyRequest.processContentKeyResponseError(error)
                    
                    strongSelf.pendingPersistableContentKeyIdentifiers.remove(assetIDString)
                    return
                }
                
                guard let spcData = spcData else { return }
                
                do {
                    // Send SPC to Key Server and obtain CKC
                    let ckcData = try strongSelf.requestContentKeyFromKeySecurityModule(spcData: spcData, assetID: assetIDString)
                    
                    let persistentKey = try keyRequest.persistableContentKey(fromKeyVendorResponse: ckcData, options: nil)
                    
                    try strongSelf.writePersistableContentKey(contentKey: persistentKey, withContentKeyIdentifier: assetIDString)
                    
                    /*
                     AVContentKeyResponse is used to represent the data returned from the key server when requesting a key for
                     decrypting content.
                     */
                    let keyResponse = AVContentKeyResponse(fairPlayStreamingKeyResponseData: persistentKey)
                    
                    /*
                     Provide the content key response to make protected content available for processing.
                     */
                    keyRequest.processContentKeyResponse(keyResponse)
                    
                    let assetName = strongSelf.contentKeyToStreamNameMap.removeValue(forKey: assetIDString)!
                    
                    if !strongSelf.contentKeyToStreamNameMap.values.contains(assetName) {
                        NotificationCenter.default.post(name: .DidSaveAllPersistableContentKey,
                                                        object: nil,
                                                        userInfo: ["name": assetName])
                    }
                    
                    strongSelf.pendingPersistableContentKeyIdentifiers.remove(assetIDString)
                } catch {
                    keyRequest.processContentKeyResponseError(error)
                    
                    strongSelf.pendingPersistableContentKeyIdentifiers.remove(assetIDString)
                }
            }
            
            // Check to see if we can satisfy this key request using a saved persistent key file.
            if persistableContentKeyExistsOnDisk(withContentKeyIdentifier: assetIDString) {
                
                let urlToPersistableKey = urlForPersistableContentKey(withContentKeyIdentifier: assetIDString)
                
                guard let contentKey = FileManager.default.contents(atPath: urlToPersistableKey.path) else {
                    // Error Handling.
                    
                    pendingPersistableContentKeyIdentifiers.remove(assetIDString)
                    
                    /*
                     Key requests should never be left dangling.
                     Attempt to create a new persistable key.
                     */
                    let applicationCertificate = try requestApplicationCertificate()
                    keyRequest.makeStreamingContentKeyRequestData(forApp: applicationCertificate,
                                                                  contentIdentifier: assetIDData,
                                                                  options: [AVContentKeyRequestProtocolVersionsKey: [1]],
                                                                  completionHandler: completionHandler)

                    return
                }
                
                /*
                 Create an AVContentKeyResponse from the persistent key data to use for requesting a key for
                 decrypting content.
                 */
                let keyResponse = AVContentKeyResponse(fairPlayStreamingKeyResponseData: contentKey)
                
                // Provide the content key response to make protected content available for processing.
                keyRequest.processContentKeyResponse(keyResponse)
                
                return
            }
            
            let applicationCertificate = try requestApplicationCertificate()
            
            keyRequest.makeStreamingContentKeyRequestData(forApp: applicationCertificate,
                                                          contentIdentifier: assetIDData,
                                                          options: [AVContentKeyRequestProtocolVersionsKey: [1]],
                                                          completionHandler: completionHandler)
        } catch {
            print("Failure responding to an AVPersistableContentKeyRequest when attemping to determine if key is already available for use on disk.")
        }
    }
    
    /// Deletes all the persistable content keys on disk for a specific `Asset`.
    ///
    /// - Parameter asset: The `Asset` value to remove keys for.
    func deleteAllPeristableContentKeys(forAsset asset: Asset) {
        for contentKeyIdentifier in asset.stream.contentKeyIDList ?? [] {
            let items = contentKeyIdentifier.components(separatedBy: "kid=")
            if (items.count >= 2){
                deletePeristableContentKey(withContentKeyIdentifier: items[1])
            }
            
        }
    }
    
    /// Deletes a persistable key for a given content key identifier.
    ///
    /// - Parameter contentKeyIdentifier: The host value of an `AVPersistableContentKeyRequest`. (i.e. "tweleve" in "skd://tweleve").
    func deletePeristableContentKey(withContentKeyIdentifier contentKeyIdentifier: String) {
        
        guard persistableContentKeyExistsOnDisk(withContentKeyIdentifier: contentKeyIdentifier) else { return }
        
        let contentKeyURL = urlForPersistableContentKey(withContentKeyIdentifier: contentKeyIdentifier)
        
        do {
            try FileManager.default.removeItem(at: contentKeyURL)
            
            UserDefaults.standard.removeObject(forKey: "\(contentKeyIdentifier)-Key")
        } catch {
            print("An error occured removing the persisted content key: \(error)")
        }
    }
    
    /// Returns whether or not a persistable content key exists on disk for a given content key identifier.
    ///
    /// - Parameter contentKeyIdentifier: The host value of an `AVPersistableContentKeyRequest`. (i.e. "tweleve" in "skd://tweleve").
    /// - Returns: `true` if the key exists on disk, `false` otherwise.
    func persistableContentKeyExistsOnDisk(withContentKeyIdentifier contentKeyIdentifier: String) -> Bool {
        let contentKeyURL = urlForPersistableContentKey(withContentKeyIdentifier: contentKeyIdentifier)
        
        let ret =  FileManager.default.fileExists(atPath: contentKeyURL.path)
        return ret
    }
    
    // MARK: Private APIs
    
    /// Returns the `URL` for persisting or retrieving a persistable content key.
    ///
    /// - Parameter contentKeyIdentifier: The host value of an `AVPersistableContentKeyRequest`. (i.e. "tweleve" in "skd://tweleve").
    /// - Returns: The fully resolved file URL.
    func urlForPersistableContentKey(withContentKeyIdentifier contentKeyIdentifier: String) -> URL {
        return contentKeyDirectory.appendingPathComponent("\(contentKeyIdentifier)-Key")
    }
    
    /// Writes out a persistable content key to disk.
    ///
    /// - Parameters:
    ///   - contentKey: The data representation of the persistable content key.
    ///   - contentKeyIdentifier: The host value of an `AVPersistableContentKeyRequest`. (i.e. "tweleve" in "skd://tweleve").
    /// - Throws: If an error occurs during the file write process.
    func writePersistableContentKey(contentKey: Data, withContentKeyIdentifier contentKeyIdentifier: String) throws {
        
        let fileURL = urlForPersistableContentKey(withContentKeyIdentifier: contentKeyIdentifier)
        
        try contentKey.write(to: fileURL, options: Data.WritingOptions.atomicWrite)
    }
    
    
}

extension URL {
    public var queryParameters: [String: String]? {
        guard
            let components = URLComponents(url: self, resolvingAgainstBaseURL: true),
            let queryItems = components.queryItems else { return nil }
        return queryItems.reduce(into: [String: String]()) { (result, item) in
            result[item.name] = item.value
        }
    }
}

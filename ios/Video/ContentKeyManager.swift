/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 The `ContentKeyManager` class configures the instance of `AVContentKeySession` to use for requesting content keys
 securely for playback or offline use.
 */

import AVFoundation
@objc(ContentKeyManager)
public class ContentKeyManager:NSObject {
    
    // MARK: Types.
    
    /// The singleton for `ContentKeyManager`.
    @objc public static let shared: ContentKeyManager = ContentKeyManager()
    
    // MARK: Properties.
    
    /// The instance of `AVContentKeySession` that is used for managing and preloading content keys.
    @objc public let contentKeySession: AVContentKeySession
    
    /**
     The instance of `ContentKeyDelegate` which conforms to `AVContentKeySessionDelegate` and is used to respond to content key requests from
     the `AVContentKeySession`
     */
    @objc public let contentKeyDelegate: ContentKeyDelegate
    
    /// The DispatchQueue to use for delegate callbacks.
    @objc public let contentKeyDelegateQueue = DispatchQueue(label: "com.digimed.drmvideodownloader")
    
    // MARK: Initialization.
    @objc
    private override init() {
        contentKeySession = AVContentKeySession(keySystem: .fairPlayStreaming)
        contentKeyDelegate = ContentKeyDelegate()
        contentKeySession.setDelegate(contentKeyDelegate, queue: contentKeyDelegateQueue)
    }
}

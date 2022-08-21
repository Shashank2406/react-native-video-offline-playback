/*
 Copyright (C) 2017 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 A simple class that represents an entry from the `Streams.plist` file in the main application bundle.
 */

import Foundation

@objc(Stream)
public class Stream : NSObject{
    
    // MARK: Types
    
//    enum CodingKeys: String, CodingKey {
//        case name = "name"
//        case playlistURL = "playlist_url"
//        case isProtected = "is_protected"
//        case contentKeyIDList = "content_key_id_list"
//    }
    
    // MARK: Properties
    
    /// The name of the stream.
    @objc public let name: String
    
    /// The URL pointing to the HLS stream.
    @objc public let playlistURL: String
    
    @objc public let licenseUrl: String
    
    /// A Boolen value representing if the stream uses FPS.
    @objc public let isProtected: Bool
    
    /// An array of content IDs to use for loading content keys with FPS.
    @objc public let contentKeyIDList: [String]?
    
    @objc public let header: NSDictionary?
    @objc(name:isProtected:contentKeyIDList:playlistURL:licenseUrl:header:)
    init(name:String, isProtected: Bool, contentKeyIDList:[String]?, playlistURL:String,licenseUrl: String, header: NSDictionary?) {
        self.name = name
        self.playlistURL = playlistURL
        self.isProtected = isProtected
        self.contentKeyIDList = contentKeyIDList
        self.header = header
        self.licenseUrl = licenseUrl
    }
    
    init(name: String) {
        self.name = name;
        self.playlistURL = "";
        self.licenseUrl = "";
        self.header = NSDictionary.init();
        self.isProtected = true;
        self.contentKeyIDList = nil;
    }
}

extension Stream {
    static func ==(lhs: Stream, rhs: Stream) -> Bool {
        var isEqual = (lhs.name == rhs.name) && (lhs.playlistURL == rhs.playlistURL) && (lhs.isProtected == rhs.isProtected)
        
        let lhsContentKeyIDList = lhs.contentKeyIDList ?? []
        let rhsContentKeyIDList = rhs.contentKeyIDList ?? []
        
        isEqual = isEqual && lhsContentKeyIDList.elementsEqual(rhsContentKeyIDList)
        
        return isEqual
    }
}

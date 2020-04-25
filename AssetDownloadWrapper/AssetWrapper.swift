//
//  AssetWrapper.swift
//  AssetDownloadWrapper
//
//  Created by Takuya Ohsawa on 2020/04/23.
//  Copyright © 2020 Takuya Ohsawa. All rights reserved.
//

import AVFoundation
import Foundation

public struct AssetWrapper: Equatable {
    // MARK: - public
    public let urlAsset: AVURLAsset
    public let assetTitle: String
    
    // MARK: - initializer
    public init(urlAsset: AVURLAsset, assetTitle: String) {
        self.urlAsset = urlAsset
        self.assetTitle = assetTitle
    }
}

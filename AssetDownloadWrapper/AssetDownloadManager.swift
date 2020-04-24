//
//  AssetDownloadManager.swift
//  AssetDownloadWrapper
//
//  Created by Takuya Ohsawa on 2020/04/23.
//  Copyright © 2020 Takuya Ohsawa. All rights reserved.
//

import AVFoundation
import Foundation

open class AssetDownloadManager: NSObject {
    // MARK: - public
    public func downloadStream(for asset: AssetWrapper, progressHandler: ((CGFloat) -> Void)? = nil, completion: ((Result<Data, Error>) -> Void)? = nil) {
        let preferredMediaSelection = asset.urlAsset.preferredMediaSelection
        guard let task =
            assetDownloadURLSession.aggregateAssetDownloadTask(with: asset.urlAsset,
                                                               mediaSelections: [preferredMediaSelection],
                                                               assetTitle: asset.assetTitle,
                                                               assetArtworkData: nil,
                                                               options:
                [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: 265_000]) else { return }
        
        task.taskDescription = asset.assetTitle
        task.resume()
        self.downloadHandler = completion
        self.progressHandler = progressHandler
    }
    
    public func removeAllData() {
        let dataArray = DataCacher.default.allData()
        dataArray.forEach { (data) in
            var bookmarkDataIsStale = false
            if let url = try? URL(resolvingBookmarkData: data,
                                  bookmarkDataIsStale: &bookmarkDataIsStale) {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {

                }
            }
        }
        
        DataCacher.default.cleanDiskCache()
    }
    
    public func cacheSizeString() -> String? {
        let dataArray = DataCacher.default.allData()
        let urls: [URL] = dataArray.compactMap({ data in
            var bookmarkDataIsStale = false
            if let url = try? URL(resolvingBookmarkData: data,
                                  bookmarkDataIsStale: &bookmarkDataIsStale) {
                return url
            } else {
                return nil
            }
        })
        var folderSizes: [Int64] = []
        urls.forEach { (url) in
            if let size = findSize(at: url.path) {
                folderSizes.append(size)
            }
        }
        let sum = folderSizes.reduce(0) {(num1: Int64, num2: Int64) -> Int64 in
            return num1 + num2
        }
        return ByteCountFormatter.string(fromByteCount: sum, countStyle: .file)
    }
    public static let shared = AssetDownloadManager()
    
    // MARK: - initializer
    override private init() {
        super.init()
        let backgroundConfiguration = URLSessionConfiguration.background(withIdentifier: "t-osawa-009.AssetDownloadWrapper")
        assetDownloadURLSession =
            AVAssetDownloadURLSession(configuration: backgroundConfiguration,
                                      assetDownloadDelegate: self,
                                      delegateQueue: OperationQueue.main)
        
    }
    
    // MARK: - private
    private func retrieveLocalAsset(with assetTitle: String) -> (AssetWrapper, URL)? {
        guard let data = DataCacher.default.readDataFromDisk(forKey: assetTitle) else { return nil }
        var bookmarkDataIsStale = false
        if let url = try? URL(resolvingBookmarkData: data,
                              bookmarkDataIsStale: &bookmarkDataIsStale) {
            let urlAsset = AVURLAsset(url: url)
            let asset = AssetWrapper(urlAsset: urlAsset, assetTitle: assetTitle)
            return (asset, url)
        } else {
            return nil
        }
    }
    
    /// https://gist.github.com/toshi0383/13de25b0b6ab55f33b6c80760b706867
    private func findSize(at directoryPath: String) -> Int64? {
        
        let properties: [URLResourceKey] = [.isRegularFileKey,
                                            .totalFileAllocatedSizeKey,
            /*.fileAllocatedSizeKey*/]
        
        guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: directoryPath),
                                                              includingPropertiesForKeys: properties,
                                                              options: .skipsHiddenFiles,
                                                              errorHandler: nil) else {
                                                                
                                                                return nil
        }
        
        let urls: [URL] = enumerator
            .compactMap { $0 as? URL }
            .filter { $0.absoluteString.contains(".frag") }
        
        let regularFileResources: [URLResourceValues] = urls
            .compactMap { try? $0.resourceValues(forKeys: Set(properties)) }
            .filter { $0.isRegularFile == true }
        
        let sizes: [Int64] = regularFileResources
            
            // mac上だとfileAllocatedSizeでもサイズ変わらなかった.
            .compactMap { $0.totalFileAllocatedSize! /* ?? $0.fileAllocatedSize */ }
            
            .compactMap { Int64($0) }
        
        return sizes.reduce(0, +)
    }
    
    private var assetDownloadURLSession: AVAssetDownloadURLSession!
    private var didRestorePersistenceManager = false
    private var willDownloadToUrlDictionary: [AVAggregateAssetDownloadTask: URL] = [:]
    private var downloadHandler: ((Result<Data, Error>) -> Void)?
    private var progressHandler: ((CGFloat) -> Void)?
}

// MARK: - AVAssetDownloadDelegate
extension AssetDownloadManager: AVAssetDownloadDelegate {
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let task = task as? AVAggregateAssetDownloadTask else { return }
        guard let downloadURL = willDownloadToUrlDictionary.removeValue(forKey: task) else { return }
        if let error = error as NSError? {
            switch (error.domain, error.code) {
            case (NSURLErrorDomain, NSURLErrorCancelled):
                guard let _url = retrieveLocalAsset(with: downloadURL.lastPathComponent)?.1 else {
                    downloadHandler?(.failure(error))
                    return
                }
                do {
                    try FileManager.default.removeItem(at: _url)
                    if let name = task.taskDescription {
                        DataCacher.default.clean(byKey: name)
                    }
                } catch let _error {
                    downloadHandler?(.failure(_error))
                }
            default:
                downloadHandler?(.failure(error))
            }
        } else {
            do {
                if let name = task.taskDescription {
                    let bookmark = try downloadURL.bookmarkData()
                    DataCacher.default.write(data: bookmark, forKey: name)
                    downloadHandler?(.success(bookmark))
                }
            } catch let _error {
                downloadHandler?(.failure(_error))
            }
        }
    }
    
    public func urlSession(_ session: URLSession, aggregateAssetDownloadTask: AVAggregateAssetDownloadTask,
                           willDownloadTo location: URL) {
        willDownloadToUrlDictionary[aggregateAssetDownloadTask] = location
    }
    
    public func urlSession(_ session: URLSession, aggregateAssetDownloadTask: AVAggregateAssetDownloadTask,
                           didCompleteFor mediaSelection: AVMediaSelection) {
        aggregateAssetDownloadTask.resume()
    }
    
    public func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
        var percentComplete: CGFloat = 0.0
        for value in loadedTimeRanges {
            let loadedTimeRange: CMTimeRange = value.timeRangeValue
            percentComplete +=
                CGFloat(CMTimeGetSeconds(loadedTimeRange.duration) / CMTimeGetSeconds(timeRangeExpectedToLoad.duration))
            
        }
        
        progressHandler?(percentComplete)
    }
}


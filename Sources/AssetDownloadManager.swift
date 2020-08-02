//
//  AssetDownloadManager.swift
//  AssetDownloadWrapper
//
//  Created by Takuya Ohsawa on 2020/04/23.
//  Copyright © 2020 Takuya Ohsawa. All rights reserved.
//

import AVFoundation
import Foundation

public enum AssetDownloadManagerError: Error {
    case notSupport
    case taskInitFail
}

open class AssetDownloadManager: NSObject {
    // MARK: - public
    
    public var backgroundCompletionHandler: (() -> Void)?

    public func downloadStream(for asset: AssetWrapper, options: [String : Any]? = AssetDownloadManager.options, progressHandler: ((_ asset: AssetWrapper, _ progress: CGFloat) -> Void)? = nil, completion: ((Result<AssetWrapper, Error>) -> Void)? = nil) {
        #if targetEnvironment(simulator)
        completion?(.failure(AssetDownloadManagerError.notSupport))
        #else
        let preferredMediaSelection = asset.urlAsset.preferredMediaSelection
        guard let task =
            assetDownloadURLSession.aggregateAssetDownloadTask(with: asset.urlAsset, mediaSelections: [preferredMediaSelection], assetTitle: asset.assetTitle, assetArtworkData: nil, options: options) else {
                completion?(.failure(AssetDownloadManagerError.taskInitFail))
                return
        }
        
        task.taskDescription = asset.assetTitle
        activeDownloadsDictionary[task] = asset
        task.resume()
        self.downloadHandler = completion
        self.progressHandler = progressHandler
        #endif
    }
    
    public func makeDownloadStreamAndAVPlayerItem(for asset: AssetWrapper, options: [String : Any]? = AssetDownloadManager.options, progressHandler: ((_ asset: AssetWrapper, _ progress: CGFloat) -> Void)? = nil, completion: ((Result<AssetWrapper, Error>) -> Void)? = nil) -> AVPlayerItem? {
        #if targetEnvironment(simulator)
        completion?(.failure(AssetDownloadManagerError.notSupport))
        return nil
        #else
        let preferredMediaSelection = asset.urlAsset.preferredMediaSelection
        guard let task =
            assetDownloadURLSession.aggregateAssetDownloadTask(with: asset.urlAsset,
                                                               mediaSelections: [preferredMediaSelection],
                                                               assetTitle: asset.assetTitle,
                                                               assetArtworkData: nil,
                                                               options: options) else {
                                                                completion?(.failure(AssetDownloadManagerError.taskInitFail))
                                                                return nil
        }
        
        task.taskDescription = asset.assetTitle
        activeDownloadsDictionary[task] = asset
        task.resume()
        self.downloadHandler = completion
        self.progressHandler = progressHandler
        let playerItem = AVPlayerItem(asset: task.urlAsset)
        return playerItem
        #endif
    }
    
    public func download(asset: AssetWrapper,
                         options: [String : Any]? = AssetDownloadManager.options,
                         progressHandler: DownloadProgress? = nil,
                         completion: DownloadComplete? = nil) {
        #if targetEnvironment(simulator)
        completion?(.failure(AssetDownloadManagerError.notSupport))
        #else
        
        if !activeDownloadsDictionary.contains(where: { $0.value == asset }) {
            // Start new download:
            guard let task = assetDownloadURLSession
                .makeAssetDownloadTask(
                    asset: asset.urlAsset,
                    assetTitle: asset.assetTitle,
                    assetArtworkData: nil,
                    options: options) else { return }
            
            task.taskDescription = asset.assetTitle
            activeDownloadsDictionary[task] = asset
            task.resume()
        }
        
        self.downloadHandler = completion
        self.progressHandler = progressHandler
        #endif
    }
    
    public func activeDownload(with asset: AssetWrapper,
                               progressHandler: DownloadProgress? = nil,
                               completion: DownloadComplete? = nil) -> URLSessionTask? {
        guard let task = activeDownloadsDictionary.first(where: { $0.value == asset })?.key else {
            return nil
        }
        self.downloadHandler = completion
        self.progressHandler = progressHandler
        
        return task
    }
    
    public func retrieveLocalAsset(with assetTitle: String) -> (AssetWrapper, URL)? {
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
    
    public func deleteData(_ asset: AssetWrapper, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard let localFileLocation = retrieveLocalAsset(with: asset.assetTitle)?.0.urlAsset.url else {
            return
        }
        do {
            try FileManager.default.removeItem(at: localFileLocation)
            DataCacher.default.clean(byKey: asset.assetTitle)
            completion?(.success(()))
        } catch {
            completion?(.failure(error))
        }
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
    
    public func cancelDownload(for asset: AssetWrapper) {
        var task: URLSessionTask?
        
        for (taskKey, assetVal) in activeDownloadsDictionary where asset == assetVal {
            task = taskKey
            break
        }
        
        task?.cancel()
    }
    
    public static let shared = AssetDownloadManager()
    public static let options: [String : Any] = [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: 265_000]
    
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
    private var willDownloadToUrlDictionary: [URLSessionTask: URL] = [:]
    private var activeDownloadsDictionary: [URLSessionTask: AssetWrapper] = [:]
    private var downloadHandler: DownloadComplete?
    private var progressHandler: DownloadProgress?
    
    public typealias DownloadProgress = ((_ asset: AssetWrapper, _ progress: CGFloat) -> Void)
    public typealias DownloadComplete = ((Result<AssetWrapper, Error>) -> Void)
}

// MARK: - AVAssetDownloadDelegate
extension AssetDownloadManager: AVAssetDownloadDelegate {
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let asset = activeDownloadsDictionary.removeValue(forKey: task) else { return }
        
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
                    downloadHandler?(.success(asset))
                }
            } catch let _error {
                downloadHandler?(.failure(_error))
            }
        }
    }
    
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [unowned self] in
            guard let backgroundCompletionHandler = self.backgroundCompletionHandler else {
                return
            }
            backgroundCompletionHandler()
        }
    }
    
    // MARK: - Aggregate download

    public func urlSession(_ session: URLSession, aggregateAssetDownloadTask: AVAggregateAssetDownloadTask,
                           willDownloadTo location: URL) {
        willDownloadToUrlDictionary[aggregateAssetDownloadTask] = location
    }
    
    public func urlSession(_ session: URLSession, aggregateAssetDownloadTask: AVAggregateAssetDownloadTask,
                           didCompleteFor mediaSelection: AVMediaSelection) {
        guard let asset = activeDownloadsDictionary[aggregateAssetDownloadTask] else { return }
        aggregateAssetDownloadTask.taskDescription = asset.assetTitle
        aggregateAssetDownloadTask.resume()
    }
    
    public func urlSession(_ session: URLSession, aggregateAssetDownloadTask: AVAggregateAssetDownloadTask,
                           didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue],
                           timeRangeExpectedToLoad: CMTimeRange, for mediaSelection: AVMediaSelection) {
        updateProgress(assetDownloadTask: aggregateAssetDownloadTask,
                       totalTimeRangesLoaded: loadedTimeRanges,
                       timeRangeExpectedToLoad: timeRangeExpectedToLoad)
    }
    
    // MARK: - Single Download
    
    public func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                           didFinishDownloadingTo location: URL) {
        willDownloadToUrlDictionary[assetDownloadTask] = location
    }
    
    public func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                           didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue],
                           timeRangeExpectedToLoad: CMTimeRange) {
        updateProgress(assetDownloadTask: assetDownloadTask,
                       totalTimeRangesLoaded: loadedTimeRanges,
                       timeRangeExpectedToLoad: timeRangeExpectedToLoad)
    }
    
    func updateProgress(assetDownloadTask: URLSessionTask,
                        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
                        timeRangeExpectedToLoad: CMTimeRange) {
        guard let asset = activeDownloadsDictionary[assetDownloadTask] else { return }
        var percentComplete = 0.0
        for value in loadedTimeRanges {
            let loadedTimeRange: CMTimeRange = value.timeRangeValue
            percentComplete +=
                loadedTimeRange.duration.seconds / timeRangeExpectedToLoad.duration.seconds
        }
        progressHandler?(asset, CGFloat(percentComplete))
    }
}


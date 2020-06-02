//
//  ViewController.swift
//  AssetDownloadWrapper-Sample
//
//  Created by Takuya Ohsawa on 2020/04/24.
//  Copyright © 2020 Takuya Ohsawa. All rights reserved.
//
import AVFoundation
import UIKit
import AssetDownloadWrapper
import MediaPlayer
import AVKit

class ViewController: UIViewController {
    // MARK: - private
    @IBAction private func startButtonTapped(_ sender: Any) {
        startButton.isEnabled = false
        let urlAsset = AVURLAsset(url: Self.url)
        AssetDownloadManager.shared.download(asset: .init(urlAsset: urlAsset, assetTitle: Self.name), progressHandler: { [weak self] (_, progress) in
            self?.progressLabel.text = progress.description
            self?.progressView.setProgress(.init(progress), animated: true)
        }) { [weak self] (result) in
            switch result {
            case .success(_):
                let ac = UIAlertController(title: "Success", message: nil, preferredStyle: .alert)
                ac.addAction(.init(title: "ok", style: .default, handler: nil))
                self?.present(ac, animated: true, completion: nil)
            case .failure(let error):
                let ac = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
                ac.addAction(.init(title: "ok", style: .default, handler: nil))
                self?.present(ac, animated: true, completion: nil)
            }
            self?.startButton.isEnabled = true
        }
    }
    
    @IBAction private func startMovieButtonTapped(_ sender: Any) {
        guard let arg = AssetDownloadManager.shared.retrieveLocalAsset(with: Self.name) else {
            return
        }
        let vc = AVPlayerViewController()
        let item = AVPlayerItem(asset: arg.0.urlAsset)
        player.replaceCurrentItem(with: item)
        vc.player = player
        present(vc, animated: true, completion: nil)
    }
    
    @IBAction private func startAndLoadButtonTapped(_ sender: Any) {
        let urlAsset = AVURLAsset(url: Self.url)
        let item = AssetDownloadManager.shared.makeDownloadStreamAndAVPlayerItem(for: .init(urlAsset: urlAsset, assetTitle: Self.name), progressHandler: { [weak self] (_, progress) in
            self?.progressLabel.text = progress.description
            self?.progressView.setProgress(.init(progress), animated: true)
        }) { [weak self] (result) in
            switch result {
            case .success(_):
                let ac = UIAlertController(title: "Success", message: nil, preferredStyle: .alert)
                ac.addAction(.init(title: "ok", style: .default, handler: nil))
                self?.present(ac, animated: true, completion: nil)
            case .failure(let error):
                let ac = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
                ac.addAction(.init(title: "ok", style: .default, handler: nil))
                self?.present(ac, animated: true, completion: nil)
            }
            self?.startButton.isEnabled = true
        }
        
        let vc = AVPlayerViewController()
        player.replaceCurrentItem(with: item)
        vc.player = player
        present(vc, animated: true, completion: nil)
    }
    
    private var player = AVPlayer()
    @IBOutlet private weak var progressLabel: UILabel!
    @IBOutlet private weak var startButton: UIButton!
    @IBOutlet private weak var progressView: UIProgressView!
    private static let name = "bipbop_4x3_variant"
    private static let url = URL(string: "https://mnmedias.api.telequebec.tv/m3u8/29880.m3u8")!
}


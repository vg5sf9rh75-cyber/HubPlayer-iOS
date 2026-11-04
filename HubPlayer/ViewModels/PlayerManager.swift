import Foundation
import AVKit
import SwiftUI

/// AVURLAssetHTTPHeaderFieldsKey 未在 Swift 接口中公开，需自行声明字符串常量
private let AVURLAssetHTTPHeaderFieldsKey = "AVURLAssetHTTPHeaderFieldsKey"

final class PlayerManager: ObservableObject {
    static let shared = PlayerManager()

    @Published var player: AVPlayer?
    @Published var isPresenting = false
    @Published var currentTitle: String = ""

    /// 直接播放（无需自定义头）
    func play(_ url: URL, title: String) {
        play(url, title: title, headers: [:])
    }

    /// 带自定义 HTTP 头的播放（网盘直链常需要 Referer / Cookie 才能拉流）
    func play(_ url: URL, title: String, headers: [String: String]) {
        let asset: AVURLAsset
        if headers.isEmpty {
            asset = AVURLAsset(url: url)
        } else {
            asset = AVURLAsset(url: url, options: [AVURLAssetHTTPHeaderFieldsKey: headers])
        }
        let item = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: item)
        self.player = newPlayer
        self.currentTitle = title
        self.isPresenting = true
        newPlayer.play()
    }

    func stop() {
        player?.pause()
        player = nil
        isPresenting = false
    }
}

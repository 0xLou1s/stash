import AVKit
import SwiftUI

/// Muted, looping video with no controls, for hover previews and GIFs.
struct LoopingVideoView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PlayerLayerView {
        let player = AVQueuePlayer()
        player.isMuted = true
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))

        let view = PlayerLayerView()
        view.playerLayer.player = player
        player.play()
        return view
    }

    func updateNSView(_ nsView: PlayerLayerView, context: Context) {}

    static func dismantleNSView(_ nsView: PlayerLayerView, coordinator: Coordinator) {
        nsView.playerLayer.player?.pause()
        nsView.playerLayer.player = nil
        coordinator.looper = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var looper: AVPlayerLooper?
    }
}

/// Just a video layer. It ignores the mouse, so the tile under it keeps its
/// hover state; otherwise the preview appearing ends the hover that started
/// it, and the tile flickers.
final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspectFill
        layer = playerLayer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

/// Full video player with controls, for the inspector.
struct InspectorVideo: View {
    let media: Bookmark.Media
    /// Starts playing as soon as the panel shows it.
    var autoplays = false

    var body: some View {
        ControlledPlayerView(url: media.url, autoplays: autoplays)
            .aspectRatio(media.aspectRatio, contentMode: .fit)
    }
}

/// AppKit's AVPlayerView with inline controls. SwiftUI's `VideoPlayer` isn't
/// used because it crashes on this macOS version when first shown
/// (an abort inside `_AVKit_SwiftUI`).
private struct ControlledPlayerView: NSViewRepresentable {
    let url: URL
    let autoplays: Bool

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        load(into: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        // Same view, different post: swap the video.
        if context.coordinator.url != url {
            load(into: view, coordinator: context.coordinator)
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        view.player?.pause()
        view.player = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func load(into view: AVPlayerView, coordinator: Coordinator) {
        view.player?.pause()
        let player = AVPlayer(url: url)
        view.player = player
        coordinator.url = url
        if autoplays { player.play() }
    }

    final class Coordinator {
        var url: URL?
    }
}

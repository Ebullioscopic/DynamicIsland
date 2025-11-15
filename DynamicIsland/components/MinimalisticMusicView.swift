//
//  MinimalisticMusicView.swift
//  DynamicIsland
//
//  Created for minimalistic UI mode
//  A clean, focused music player for closed notch state
//

import SwiftUI
import Defaults

// Note: lyrics display is inlined into the main minimalistic view below and is controlled by Defaults[.enableLyrics]

struct MinimalisticMusicView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var musicManager = MusicManager.shared
    @Default(.enableLyrics) var enableLyrics
    @State private var isHovering: Bool = false
    
    var body: some View {
        VStack(spacing: 2) {
            // Main content row
            HStack(spacing: 0) {
                // Left: Album Art
                albumArtView

                // Middle: Song Title, Artist and Lyrics (lyrics shown under artist when enabled)
                Rectangle()
                    .fill(.black)
                    .overlay(
                        GeometryReader { geo in
                            VStack(alignment: .center, spacing: 2) {
                                if !musicManager.songTitle.isEmpty {
                                    MarqueeText(
                                        $musicManager.songTitle,
                                        font: .system(size: 12, weight: .semibold),
                                        nsFont: .subheadline,
                                        textColor: Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                        minDuration: 0.4,
                                        frameWidth: max(0, geo.size.width - 8)
                                    )
                                }

                                // Artist name
                                if !musicManager.artistName.isEmpty {
                                    Text(musicManager.artistName)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }

                                // Lyrics under the author name (same font size as author)
                                if enableLyrics {
                                    Text(musicManager.currentLyrics)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(.white.opacity(0.8))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.horizontal, 4)
                                        .transition(.opacity)
                                        .animation(.easeInOut(duration: 0.3), value: musicManager.currentLyrics)
                                }
                            }
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                        }
                    )
                    .frame(width: vm.closedNotchSize.width)

                // Right: Music Visualizer
                visualizerView
            }

            // (lyrics are displayed inline under the artist name)
        }
        // reserve extra height when lyrics are enabled
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0) + (enableLyrics ? 22 : 0), alignment: .center)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    // MARK: - Album Art
    
    private var albumArtView: some View {
        HStack {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .background(
                    Image(nsImage: musicManager.albumArt)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                )
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18)) // Dramatically increased corner radius for minimalistic mode
                .albumArtFlip(angle: musicManager.flipAngle)
                .frame(width: max(0, vm.effectiveClosedNotchHeight - 12), height: max(0, vm.effectiveClosedNotchHeight - 12))
        }
        .frame(width: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)), height: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)))
    }
    
    // MARK: - Visualizer
    
    private var visualizerView: some View {
        HStack {
            Rectangle()
                .fill(Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor).gradient : Color.gray.gradient)
                .frame(width: 50, alignment: .center)
                .mask {
                    AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                        .frame(width: 16, height: 12)
                }
                .frame(width: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)),
                       height: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)), alignment: .center)
        }
        .frame(width: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)),
               height: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)), alignment: .center)
    }
}

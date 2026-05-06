//
//  AlbumView.swift
//  potato card
//

import SwiftUI
import UIKit

struct AlbumView: View {
    let onTransferToDevice: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedAlbum: SelectedAlbumGroup?

    private let wangWenAlbums: [AlbumItem] = [
        AlbumItem(title: "Invisible City", assetName: "wangwen_invisible_city", year: "2018"),
        AlbumItem(title: "0.7", assetName: "wangwen_0_7", year: "2012"),
        AlbumItem(title: "Eight Horses", assetName: "wangwen_eight_horses", year: "2014"),
        AlbumItem(title: "100,000 Whys", assetName: "wangwen_100000_whys", year: "2020"),
        AlbumItem(title: "Painful Clown & Ninja Tiger", assetName: "wangwen_painful_clown", year: "2022"),
        AlbumItem(title: "Sweet Home, Go!", assetName: "wangwen_sweet_home_go", year: "2016")
    ]

    private let godspeedAlbums: [AlbumItem] = [
        AlbumItem(title: "F#A#∞", assetName: "gybe_fsharp", year: "1997"),
        AlbumItem(title: "Lift Yr. Skinny Fists", assetName: "gybe_lift", year: "2000"),
        AlbumItem(title: "Yanqui U.X.O.", assetName: "gybe_yanqui", year: "2002"),
        AlbumItem(title: "'Allelujah! Don't Bend! Ascend!", assetName: "gybe_allelujah", year: "2012"),
        AlbumItem(title: "Asunder, Sweet and Other Distress", assetName: "gybe_asunder", year: "2015"),
        AlbumItem(title: "Luciferian Towers", assetName: "gybe_luciferian", year: "2017")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("专辑")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(primaryTextColor)

                Text("为墨水屏精选的后摇封面")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
            }

            artistSection(title: "惘闻", subtitle: "Wang Wen", albums: wangWenAlbums)
            artistSection(title: "黑帝", subtitle: "Godspeed You! Black Emperor", albums: godspeedAlbums)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $selectedAlbum) { group in
            AlbumImageViewer(
                albums: group.albums,
                initialIndex: group.initialIndex,
                onTransferToDevice: onTransferToDevice
            )
                .presentationDetents([.height(600), .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func artistSection(title: String, subtitle: String, albums: [AlbumItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryTextColor)

                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(albums.enumerated()), id: \.element.id) { index, album in
                        albumCard(album, albums: albums, index: index)
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.horizontal, -24)
        }
    }

    private func albumCard(_ album: AlbumItem, albums: [AlbumItem], index: Int) -> some View {
        Button {
            selectedAlbum = SelectedAlbumGroup(albums: albums, initialIndex: index)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(album.assetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 148, height: 148)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(borderColor, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.26 : 0.10), radius: 12, x: 0, y: 8)

                Text(album.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(2)

                Text(album.year)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
            }
            .frame(width: 148, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.92)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.56) : Color.black.opacity(0.50)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }
}

private struct AlbumItem: Identifiable, Equatable {
    var id: String { assetName }
    let title: String
    let assetName: String
    let year: String
}

private struct SelectedAlbumGroup: Identifiable {
    let id: String
    let albums: [AlbumItem]
    let initialIndex: Int

    init(albums: [AlbumItem], initialIndex: Int) {
        self.albums = albums
        self.initialIndex = initialIndex
        self.id = "\(albums.map(\.assetName).joined(separator: "|"))-\(initialIndex)"
    }
}

private struct AlbumImageViewer: View {
    let albums: [AlbumItem]
    let initialIndex: Int
    let onTransferToDevice: (String) -> Void
    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedIndex: Int
    @State private var transferRequest: AlbumTransferRequest?
    @State private var pendingTransferAlbum: String?
    @State private var pendingTransferImage: UIImage?
    @State private var isPreparingDirectTransfer = false

    init(albums: [AlbumItem], initialIndex: Int, onTransferToDevice: @escaping (String) -> Void) {
        self.albums = albums
        self.initialIndex = initialIndex
        self.onTransferToDevice = onTransferToDevice
        _selectedIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        let buttonTextColor = Color.white
        let buttonFillColor = colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)
        let secondaryTextColor = colorScheme == .dark ? Color.white.opacity(0.82) : Color.black.opacity(0.72)
        let primaryButtonFillColor = Color(red: 0.0, green: 0.48, blue: 1.0)

        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color.black : Color.white)
                    .ignoresSafeArea()

                albumFramedPreview

                VStack {
                    Spacer()

                    VStack(spacing: 10) {
                        transferStatusView

                        Button(action: transferSelectedAlbumDirectly) {
                            Text(isPreparingDirectTransfer ? "正在生成图片" : "传输到设备")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(buttonTextColor)
                                .padding(.horizontal, 18)
                                .frame(height: 38)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(primaryButtonFillColor)
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(primaryButtonFillColor.opacity(0.16), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isPreparingDirectTransfer || activeDevice == nil || isTransferInProgress)

                        Button(action: openManualAdjustment) {
                            Text("手动调整")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(secondaryTextColor)
                                .padding(.horizontal, 16)
                                .frame(height: 36)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(buttonFillColor.opacity(0.72))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isTransferInProgress)
                    }
                    .padding(.bottom, 10)
                    .offset(y: 20)
                }
            }
            .sheet(item: $transferRequest) { request in
                TransferSheetView(
                    sourceImage: request.image,
                    title: request.album,
                    sourceIdentifier: request.sourceIdentifier,
                    contentType: .album,
                    onTransferSucceeded: {
                        onTransferToDevice(request.album)
                        dismiss()
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .onChange(of: bleService.transferPhase) { _, phase in
                guard phase == .succeeded, let album = pendingTransferAlbum else { return }
                if let pendingTransferImage {
                    bleService.markLastTransferredImage(pendingTransferImage, contentType: .album)
                }
                onTransferToDevice(album)
                pendingTransferAlbum = nil
                pendingTransferImage = nil
                dismiss()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text(albums[selectedIndex].title)
                        .font(.system(size: 17, weight: .semibold))
                }
            }
        }
    }

    @ViewBuilder
    private var transferStatusView: some View {
        if isTransferInProgress {
            ProgressView(value: bleService.transferProgress)
                .frame(width: 150)
        } else if isPreparingDirectTransfer {
            ProgressView()
        } else if case .failed = bleService.transferPhase, let errorMessage = bleService.errorMessage {
            Text(errorMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    private func transferSelectedAlbumDirectly() {
        guard
            !isPreparingDirectTransfer,
            let device = activeDevice,
            let image = UIImage(named: albums[selectedIndex].assetName)
        else {
            return
        }

        isPreparingDirectTransfer = true
        let albumTitle = albums[selectedIndex].title
        let profile = device.profile

        Task {
            let renderedImages = await Task.detached(priority: .userInitiated) {
                let transferImage = EInkImageRenderer.renderForTransfer(
                    image: image,
                    targetSize: profile.pixelSize,
                    fitMode: .centerCrop,
                    adjustment: .default,
                    profile: profile
                )
                let displayImage = EInkImageRenderer.render(
                    image: image,
                    targetSize: profile.pixelSize,
                    fitMode: .centerCrop,
                    adjustment: .default
                )
                return (transferImage, displayImage)
            }.value

            guard !Task.isCancelled else { return }
            isPreparingDirectTransfer = false
            pendingTransferAlbum = albumTitle
            pendingTransferImage = renderedImages.1
            bleService.transfer(image: renderedImages.0, to: device)
        }
    }

    private func openManualAdjustment() {
        let album = albums[selectedIndex]
        guard let image = UIImage(named: album.assetName) else { return }
        pendingTransferAlbum = nil
        pendingTransferImage = nil
        transferRequest = AlbumTransferRequest(album: album.title, sourceIdentifier: "album:\(album.assetName)", image: image)
    }

    private func defaultTransferImage(from image: UIImage, device: BleDevice) -> UIImage {
        EInkImageRenderer.renderForTransfer(
            image: image,
            targetSize: device.profile.pixelSize,
            fitMode: .centerCrop,
            adjustment: .default,
            profile: device.profile
        )
    }

    private func defaultDisplayImage(from image: UIImage, device: BleDevice) -> UIImage {
        EInkImageRenderer.render(
            image: image,
            targetSize: device.profile.pixelSize,
            fitMode: .centerCrop,
            adjustment: .default
        )
    }

    private var activeDevice: BleDevice? {
        bleService.connectedDevice ?? bleService.selectedDevice
    }

    private var isTransferInProgress: Bool {
        bleService.transferPhase == .preparing || bleService.transferPhase == .transferring
    }

    private var albumFramedPreview: some View {
        ZStack {
            TabView(selection: $selectedIndex) {
                ForEach(Array(albums.enumerated()), id: \.offset) { index, album in
                    albumScreenImage(album)
                        .tag(index)
                }
            }
            .frame(width: 186, height: 280)
            .tabViewStyle(.page(indexDisplayMode: .never))
            .mask(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .frame(width: 186, height: 280)
            )
            .offset(y: -19)

            Image("ink_tatoo2")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220)
                .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 10)
                .allowsHitTesting(false)
        }
        .frame(width: 220, height: 352)
        .offset(y: -60)
    }

    private func albumScreenImage(_ album: AlbumItem) -> some View {
        return GeometryReader { proxy in
            Image(album.assetName)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .frame(width: 186, height: 280)
    }

}

private struct AlbumTransferRequest: Identifiable {
    let id = UUID()
    let album: String
    let sourceIdentifier: String
    let image: UIImage
}

private struct AlbumView_Previews: PreviewProvider {
    static var previews: some View {
        AlbumView(onTransferToDevice: { _ in })
            .environmentObject(BleTransferService())
    }
}

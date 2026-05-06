import SwiftUI
import UIKit

struct TransferSheetView: View {
    let sourceImage: UIImage
    let title: String
    var sourceIdentifier: String?
    var contentType: ProjectedContentType = .unknown
    var onTransferSucceeded: (() -> Void)?

    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var adjustment = EInkManualAdjustment.default
    @State private var gestureStartAdjustment: EInkManualAdjustment?
    @State private var isPreparingTransferImage = false
    private let adjustmentStore = ImageAdjustmentStore()

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        previewSection
                        adjustmentSection
                        transferSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .onChange(of: bleService.transferPhase) { _, phase in
                if phase == .succeeded {
                    persistCurrentAdjustment()
                    bleService.markLastTransferredImage(displayImage, contentType: contentType)
                    onTransferSucceeded?()
                    dismiss()
                }
            }
            .onAppear(perform: loadSavedAdjustment)
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("裁剪预览")

                Spacer()

                Text("拖动调整位置，双指缩放")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
            }

            EInkDevicePreview(
                sourceImage: sourceImage,
                adjustment: adjustment,
                renderTargetSize: renderTargetSize,
                onDragChanged: handlePreviewDrag,
                onDragEnded: finishPreviewGesture,
                onMagnifyChanged: handlePreviewMagnify,
                onMagnifyEnded: finishPreviewGesture
            )
                .frame(maxWidth: .infinity)
                .frame(height: 350)
        }
    }

    private var transferSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("传输")

            if let device = activeDevice, device.profile.isFallback {
                Text("未知型号，使用默认尺寸 \(device.profile.displaySize)。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
            }

            if case .failed = bleService.transferPhase, let errorMessage = bleService.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
            }

            if bleService.transferPhase == .transferring || bleService.transferPhase == .preparing {
                ProgressView(value: bleService.transferProgress)
                Text("\(bleService.transferPhase.title) \(Int(bleService.transferProgress * 100))%")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
            }

            Button {
                startTransfer()
            } label: {
                Label(isPreparingTransferImage ? "正在生成图片" : "传输到设备", systemImage: isPreparingTransferImage ? "clock" : "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPreparingTransferImage || activeDevice == nil || bleService.transferPhase == .transferring || bleService.transferPhase == .preparing)
        }
    }

    private var adjustmentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("手动调整")

            adjustmentSlider(title: "缩放", value: $adjustment.scale, range: 1...4)
            adjustmentSlider(title: "水平", value: $adjustment.offsetX, range: horizontalOffsetRange)
            adjustmentSlider(title: "垂直", value: $adjustment.offsetY, range: verticalOffsetRange)

            Button {
                adjustment = .default
                gestureStartAdjustment = nil
            } label: {
                Label("重置", systemImage: "arrow.counterclockwise")
            }
            .font(.system(size: 14, weight: .semibold))
        }
    }

    private func adjustmentSlider(title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(primaryTextColor)

            Slider(value: value, in: range)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(primaryTextColor)
    }

    private var displayImage: UIImage {
        EInkImageRenderer.render(
            image: sourceImage,
            targetSize: renderTargetSize,
            fitMode: .manual,
            adjustment: adjustment
        )
    }

    private var transferImage: UIImage {
        let profile = activeDevice?.profile ?? EInkDeviceProfile.fallback
        return EInkImageRenderer.renderForTransfer(
            image: sourceImage,
            targetSize: profile.pixelSize,
            fitMode: .manual,
            adjustment: adjustment,
            profile: profile
        )
    }

    private func startTransfer() {
        guard let device = activeDevice, !isPreparingTransferImage else { return }

        isPreparingTransferImage = true
        let sourceImage = sourceImage
        let adjustment = adjustment
        let profile = device.profile

        Task {
            let image = await Task.detached(priority: .userInitiated) {
                EInkImageRenderer.renderForTransfer(
                    image: sourceImage,
                    targetSize: profile.pixelSize,
                    fitMode: .manual,
                    adjustment: adjustment,
                    profile: profile
                )
            }.value

            guard !Task.isCancelled else { return }
            isPreparingTransferImage = false
            bleService.transfer(image: image, to: device)
        }
    }

    private var renderTargetSize: CGSize {
        activeDevice?.profile.pixelSize ?? EInkDeviceProfile.fallback.pixelSize
    }

    private var horizontalOffsetRange: ClosedRange<CGFloat> {
        -renderTargetSize.width...renderTargetSize.width
    }

    private var verticalOffsetRange: ClosedRange<CGFloat> {
        -renderTargetSize.height...renderTargetSize.height
    }

    private func handlePreviewDrag(_ translation: CGSize, previewScale: CGFloat) {
        let start = gestureStartAdjustment ?? adjustment
        if gestureStartAdjustment == nil {
            gestureStartAdjustment = start
        }

        let safeScale = max(previewScale, 0.001)
        adjustment.offsetX = (start.offsetX + translation.width / safeScale).clamped(to: horizontalOffsetRange)
        adjustment.offsetY = (start.offsetY + translation.height / safeScale).clamped(to: verticalOffsetRange)
    }

    private func handlePreviewMagnify(_ value: CGFloat) {
        let start = gestureStartAdjustment ?? adjustment
        if gestureStartAdjustment == nil {
            gestureStartAdjustment = start
        }

        adjustment.scale = (start.scale * value).clamped(to: 1...4)
    }

    private func finishPreviewGesture() {
        gestureStartAdjustment = nil
    }

    private func loadSavedAdjustment() {
        guard let sourceIdentifier else { return }
        adjustment = adjustmentStore.loadAdjustment(
            sourceID: sourceIdentifier,
            targetSize: renderTargetSize
        ) ?? .default
    }

    private func persistCurrentAdjustment() {
        guard let sourceIdentifier else { return }
        adjustmentStore.save(
            adjustment,
            sourceID: sourceIdentifier,
            targetSize: renderTargetSize
        )
    }

    private var activeDevice: BleDevice? {
        bleService.connectedDevice ?? bleService.selectedDevice
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.07, green: 0.07, blue: 0.08) : .white
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.92)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.48)
    }

}

private struct EInkDevicePreview: View {
    let sourceImage: UIImage
    let adjustment: EInkManualAdjustment
    let renderTargetSize: CGSize
    let onDragChanged: (CGSize, CGFloat) -> Void
    let onDragEnded: () -> Void
    let onMagnifyChanged: (CGFloat) -> Void
    let onMagnifyEnded: () -> Void

    var body: some View {
        ZStack {
            Image("ink_tatoo2")
                .resizable()
                .scaledToFit()
                .frame(width: 230, height: 310)

            deviceScreenPreview
                .frame(width: 164, height: 245)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .offset(y: -22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deviceScreenPreview: some View {
        GeometryReader { proxy in
            let drawRect = previewDrawRect(in: proxy.size)
            let previewScale = min(
                proxy.size.width / max(renderTargetSize.width, 1),
                proxy.size.height / max(renderTargetSize.height, 1)
            )

            ZStack {
                Image(uiImage: sourceImage)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: drawRect.width, height: drawRect.height)
                    .position(x: drawRect.midX, y: drawRect.midY)

                cropGrid
            }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            onDragChanged(value.translation, previewScale)
                        }
                        .onEnded { _ in
                            onDragEnded()
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            onMagnifyChanged(value)
                        }
                        .onEnded { _ in
                            onMagnifyEnded()
                        }
                )
        }
        .background(Color.white)
        .clipped()
    }

    private func previewDrawRect(in previewSize: CGSize) -> CGRect {
        let targetRect = EInkImageRenderer.drawRect(
            for: sourceImage.size,
            targetSize: renderTargetSize,
            fitMode: .manual,
            adjustment: adjustment
        )
        let scale = min(
            previewSize.width / max(renderTargetSize.width, 1),
            previewSize.height / max(renderTargetSize.height, 1)
        )
        return CGRect(
            x: targetRect.origin.x * scale,
            y: targetRect.origin.y * scale,
            width: targetRect.width * scale,
            height: targetRect.height * scale
        )
    }

    private var cropGrid: some View {
        GeometryReader { proxy in
            Path { path in
                let width = proxy.size.width
                let height = proxy.size.height
                for index in 1...2 {
                    let x = width * CGFloat(index) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))

                    let y = height * CGFloat(index) / 3
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.58), lineWidth: 0.8)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.80), lineWidth: 1.2)
            )
            .allowsHitTesting(false)
        }
    }
}

private struct TransferSheetView_Previews: PreviewProvider {
    static var previews: some View {
        TransferSheetView(
            sourceImage: UIImage(named: "tatoo1") ?? UIImage.previewFallbackImage(),
            title: "传输预览"
        )
        .environmentObject(BleTransferService())
    }
}

private extension UIImage {
    static func previewFallbackImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800))
        return renderer.image { context in
            UIColor.systemGray6.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))

            UIColor.systemGray3.setFill()
            context.fill(CGRect(x: 140, y: 180, width: 320, height: 440))
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

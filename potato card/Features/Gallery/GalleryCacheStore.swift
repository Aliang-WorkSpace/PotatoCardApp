//
//  GalleryCacheStore.swift
//  potato card
//

import Foundation
import UIKit

struct GalleryPhoto: Identifiable, Equatable {
    let id: UUID
    let imageData: Data
    let image: UIImage
    let title: String
}

enum GalleryCacheStore {
    private static let folderName = "GalleryPhotoCache"
    private static let indexFileName = "gallery-index.json"
    private static let maxStoredPixelDimension: CGFloat = 1_600
    private static let jpegCompressionQuality: CGFloat = 0.86

    static func loadPhotos() -> [GalleryPhoto] {
        let entries = loadEntries()

        return entries.compactMap { entry in
            guard
                let data = try? Data(contentsOf: cacheDirectoryURL.appendingPathComponent(entry.fileName)),
                let image = UIImage(data: data)
            else {
                return nil
            }

            return GalleryPhoto(
                id: entry.id,
                imageData: data,
                image: image,
                title: entry.title
            )
        }
    }

    static func appendPhoto(data: Data, title: String) -> GalleryPhoto? {
        guard
            let preparedData = preparedImageData(from: data),
            let image = UIImage(data: preparedData)
        else {
            return nil
        }

        do {
            try ensureCacheDirectoryExists()

            let id = UUID()
            let fileName = "\(id.uuidString).jpg"
            let fileURL = cacheDirectoryURL.appendingPathComponent(fileName)
            try preparedData.write(to: fileURL, options: .atomic)

            var entries = loadEntries()
            entries.insert(GalleryCacheEntry(id: id, fileName: fileName, title: title), at: 0)
            try saveEntries(entries)

            return GalleryPhoto(id: id, imageData: preparedData, image: image, title: title)
        } catch {
            return nil
        }
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: cacheDirectoryURL)
    }

    static func deletePhoto(id: UUID) {
        var entries = loadEntries()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }

        let entry = entries.remove(at: index)
        try? FileManager.default.removeItem(at: cacheDirectoryURL.appendingPathComponent(entry.fileName))
        try? saveEntries(entries)
    }

    private static func loadEntries() -> [GalleryCacheEntry] {
        guard
            let data = try? Data(contentsOf: indexFileURL),
            let entries = try? JSONDecoder().decode([GalleryCacheEntry].self, from: data)
        else {
            return []
        }

        return entries
    }

    private static func saveEntries(_ entries: [GalleryCacheEntry]) throws {
        try ensureCacheDirectoryExists()
        let data = try JSONEncoder().encode(entries)
        try data.write(to: indexFileURL, options: .atomic)
    }

    private static func ensureCacheDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: cacheDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private static var cacheDirectoryURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
    }

    private static var indexFileURL: URL {
        cacheDirectoryURL.appendingPathComponent(indexFileName)
    }

    private static func preparedImageData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let normalizedImage = downscaledImageIfNeeded(image)
        return normalizedImage.jpegData(compressionQuality: jpegCompressionQuality)
    }

    private static func downscaledImageIfNeeded(_ image: UIImage) -> UIImage {
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let longestSide = max(pixelSize.width, pixelSize.height)
        guard longestSide > maxStoredPixelDimension else {
            return image
        }

        let scale = maxStoredPixelDimension / longestSide
        let targetSize = CGSize(
            width: max(pixelSize.width * scale, 1),
            height: max(pixelSize.height * scale, 1)
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private struct GalleryCacheEntry: Codable {
    let id: UUID
    let fileName: String
    let title: String
}

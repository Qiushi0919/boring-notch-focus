//
//  NSItemProvider+LoadHelpers.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//


import AppKit
import Foundation
import UniformTypeIdentifiers

extension NSItemProvider {

    /// Creates the security-scoped bookmark while the item provider's sandbox
    /// extension is still valid. Finder may revoke that temporary access as
    /// soon as the load callback returns, so returning only the URL first can
    /// make bookmark creation fail immediately afterwards.
    func extractFileBookmark() async -> Data? {
        guard hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        return await loadFileBookmark(typeIdentifier: UTType.fileURL.identifier)
    }

    func extractItemBookmark() async -> Data? {
        guard hasItemConformingToTypeIdentifier(UTType.item.identifier) else { return nil }
        return await loadFileBookmark(typeIdentifier: UTType.item.identifier)
    }

    /// Loads file promises/representations used by Word and WPS. The URL
    /// supplied by NSItemProvider is normally valid only inside its callback,
    /// so it is copied to shelf-owned temporary storage before returning.
    func extractFileRepresentation() async -> URL? {
        let excludedTypes: Set<String> = [
            UTType.fileURL.identifier,
            UTType.url.identifier,
            UTType.utf8PlainText.identifier,
            UTType.plainText.identifier
        ]

        let candidates = registeredTypeIdentifiers.filter { identifier in
            guard !excludedTypes.contains(identifier),
                  let type = UTType(identifier)
            else { return false }
            return type.conforms(to: .content) || type.conforms(to: .data)
        }

        for typeIdentifier in candidates {
            if let url = await loadPersistentFileRepresentation(
                typeIdentifier: typeIdentifier
            ) {
                return url
            }
        }
        return nil
    }
    
    func extractItem() async -> URL? {
        return await loadFileURL(typeIdentifier: UTType.item.identifier)
    }

    
    /// Detects if this is a file dragged from the filesystem
    func extractFileURL() async -> URL? {
        if hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return await loadFileURL(typeIdentifier: UTType.fileURL.identifier)
        }
        return nil
    }
    
    /// Loads raw data for the given type identifier
    func loadData() async -> Data? {
        NSLog(String(describing: self.registeredTypeIdentifiers))
        guard hasItemConformingToTypeIdentifier(UTType.data.identifier) else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            loadItem(forTypeIdentifier: UTType.data.identifier, options: nil) { item, error in
                if let error = error {
                    print("Error loading data for type \(UTType.data.identifier): \(error.localizedDescription)")
                    cont.resume(returning: nil)
                    return
                }
                if let url = item as? URL, let data = try? Data(contentsOf: url) {
                    if !url.absoluteString.contains("com.apple.SwiftUI.filePromises") {
                        cont.resume(returning: nil)
                        return
                    }
                    self.suggestedName = self.suggestedName ?? url.lastPathComponent
                    
                    let fileManager = FileManager.default
                    let folderURL = url.deletingLastPathComponent()

                    do {
                        // Delete the file first
                        try fileManager.removeItem(at: url)
                        print("Deleted file: \(url.path)")

                        // Check folder contents
                        let contents = try fileManager.contentsOfDirectory(atPath: folderURL.path)
                        if contents.isEmpty {
                            try fileManager.removeItem(at: folderURL)
                            print("Folder was empty, deleted folder: \(folderURL.path)")
                        } else {
                            print("Folder not deleted — it still contains \(contents.count) item(s).")
                        }

                    } catch {
                        print("Error: \(error.localizedDescription)")
                    }
                    
                    cont.resume(returning: data)
                } else if let data = item as? Data {
                    cont.resume(returning: data)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// Attempts to extract a URL (web link) from the provider
    func extractURL() async -> URL? {
        if self.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await loadURL(typeIdentifier: UTType.url.identifier) {
                //Validate URL
                guard url.scheme != nil else { return nil }
                return url
            }
        }

        return nil
    }

    func extractText() async -> String? {
        let textTypes = [UTType.utf8PlainText.identifier, UTType.plainText.identifier]

        for typeIdentifier in textTypes where self.hasItemConformingToTypeIdentifier(typeIdentifier) {
            if let text = await loadText(typeIdentifier: typeIdentifier) {
                return text
            }
        }

        return nil
    }

    /// Loads a file URL from the provider for the given type identifier.
    func loadFileURL(typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            self.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error = error {
                    print("❌ Error loading item for type \(typeIdentifier): \(error.localizedDescription)")
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: Self.resolveFileURL(from: item))
            }
        }
    }

    private func loadFileBookmark(typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            self.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    NSLog("❌ Error loading bookmark item for type \(typeIdentifier): \(error.localizedDescription)")
                    cont.resume(returning: nil)
                    return
                }

                guard let url = Self.resolveFileURL(from: item), url.isFileURL else {
                    NSLog("❌ Item provider did not supply a usable file URL for type \(typeIdentifier)")
                    cont.resume(returning: nil)
                    return
                }

                let didStartAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    cont.resume(returning: try Bookmark(url: url).data)
                } catch {
                    NSLog("❌ Failed to bookmark dropped file \(url.path): \(error.localizedDescription)")
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func loadPersistentFileRepresentation(
        typeIdentifier: String
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            loadFileRepresentation(forTypeIdentifier: typeIdentifier) {
                representationURL,
                error in
                if let error {
                    NSLog(
                        "❌ Error loading file representation for %@: %@",
                        typeIdentifier,
                        error.localizedDescription
                    )
                    continuation.resume(returning: nil)
                    return
                }
                guard let representationURL else {
                    continuation.resume(returning: nil)
                    return
                }

                let copiedURL = TemporaryFileStorageService.shared
                    .copyFileRepresentationToTemporaryStorage(
                        from: representationURL,
                        suggestedName: self.suggestedName,
                        typeIdentifier: typeIdentifier
                    )
                continuation.resume(returning: copiedURL)
            }
        }
    }

    private static func resolveFileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let url = item as? NSURL {
            return url as URL
        }
        if let data = item as? Data {
            if let url = fileURL(from: String(data: data, encoding: .utf8)) {
                return url
            }
            return Bookmark(data: data).resolveURL()
        }
        if let string = item as? String {
            return fileURL(from: string)
        }
        if let string = item as? NSString {
            return fileURL(from: string as String)
        }
        return nil
    }

    private static func fileURL(from rawString: String?) -> URL? {
        guard let rawString else { return nil }
        let string = rawString.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard !string.isEmpty else { return nil }
        if string.hasPrefix("/") {
            return URL(fileURLWithPath: string)
        }
        return URL(string: string)
    }

    /// Loads a URL from the provider for the given type identifier.
    func loadURL(typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            self.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if error != nil {
                    cont.resume(returning: nil)
                    return
                }

                if let url = item as? URL {
                    cont.resume(returning: url)
                } else if let data = item as? Data {
                    if let string = String(data: data, encoding: .utf8) {
                        if let url = URL(string: string) {
                            cont.resume(returning: url)
                            return
                        } else if string.hasPrefix("/") {
                            cont.resume(returning: URL(fileURLWithPath: string))
                            return
                        }
                    }
                    cont.resume(returning: nil)
                } else if let string = item as? String {
                    if let url = URL(string: string) {
                        cont.resume(returning: url)
                    } else if string.hasPrefix("/") {
                        cont.resume(returning: URL(fileURLWithPath: string))
                    } else {
                        cont.resume(returning: nil)
                    }
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// Loads text from the provider for the given type identifier.
    func loadText(typeIdentifier: String) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            self.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if error != nil {
                    cont.resume(returning: nil)
                    return
                }

                if let string = item as? String {
                    cont.resume(returning: string)
                } else if let data = item as? Data,
                          let string = String(data: data, encoding: .utf8) {
                    cont.resume(returning: string)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}

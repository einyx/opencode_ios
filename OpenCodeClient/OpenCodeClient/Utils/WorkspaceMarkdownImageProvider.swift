import Foundation
import MarkdownUI
import SwiftUI

struct WorkspaceMarkdownImageProvider: ImageProvider {
    /// Cap on the base64 payload we are willing to decode into a UIImage. A
    /// multi-megabyte data URI both balloons memory during decode and gives a
    /// hostile payload a big allocation; 12 MB of base64 (~9 MB binary) is far
    /// above any legitimate inline screenshot.
    static let maxBase64ImageCharacters = 12_000_000

    let loadFileContent: @Sendable ([UInt8]) async throws -> FileContent
    let workspaceDirectory: String?

    func makeImage(url: URL?) -> some View {
        return WorkspaceMarkdownImageView(url: url, loadFileContent: loadFileContent, workspaceDirectory: workspaceDirectory)
    }

    static func imageBaseURL(markdownFilePath: String?) -> URL? {
        guard let markdownFilePath, !markdownFilePath.isEmpty else {
            return nil
        }
        let dir = PathNormalizer.normalize((markdownFilePath as NSString).deletingLastPathComponent)
        var components = URLComponents()
        components.scheme = "opencode-workspace"
        components.host = "workspace"
        components.path = "/\(dir)"
        if !components.path.hasSuffix("/") {
            components.path += "/"
        }
        let url = components.url
        return url
    }

    static func workspaceRelativePath(from url: URL?, workspaceDirectory: String? = nil) -> String? {
        guard let url else { return nil }
        if url.scheme == "opencode-workspace" {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let normalized = PathNormalizer.resolveWorkspaceRelativePath(path, workspaceDirectory: workspaceDirectory)
            return normalized.isEmpty ? nil : normalized
        }
        if url.scheme == nil {
            let normalized = PathNormalizer.resolveWorkspaceRelativePath(url.absoluteString, workspaceDirectory: workspaceDirectory)
            return normalized.isEmpty ? nil : normalized
        }
        return nil
    }

    static func decodeBase64ImageData(_ raw: String?) -> Data? {
        guard let raw, !raw.isEmpty else {
            return nil
        }
        guard raw.count <= maxBase64ImageCharacters else {
            return nil
        }
        if let data = Data(base64Encoded: raw), UIImage(data: data) != nil {
            return data
        }
        let cleaned = raw
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard cleaned.count <= maxBase64ImageCharacters else {
            return nil
        }
        guard let data = Data(base64Encoded: cleaned), UIImage(data: data) != nil else {
            return nil
        }
        return data
    }

    static func decodeDataURL(_ url: URL?) -> Data? {
        guard let raw = url?.absoluteString, raw.hasPrefix("data:") else { return nil }
        guard let comma = raw.firstIndex(of: ",") else {
            return nil
        }
        let metadata = raw[..<comma]
        let payload = String(raw[raw.index(after: comma)...])
        guard metadata.contains(";base64") else {
            return nil
        }
        return decodeBase64ImageData(payload.removingPercentEncoding ?? payload)
    }
}

struct MarkdownImagePreviewItem: Codable, Hashable, Identifiable {
    let id: UUID
    let title: String
    let imageData: Data

    init(title: String, imageData: Data) {
        self.id = UUID()
        self.title = title
        self.imageData = imageData
    }
}

struct MarkdownImagePreviewWindow: View {
    let item: MarkdownImagePreviewItem

    private var uiImage: UIImage? {
        UIImage(data: item.imageData)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let uiImage {
                    ImageView(uiImage: uiImage)
                } else {
                    ContentUnavailableView(L10n.t(.contentImageDecodeFailed), systemImage: "photo")
                }
            }
            .navigationTitle(item.title)
            #if !os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if let uiImage {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(
                            item: Image(uiImage: uiImage),
                            preview: SharePreview(item.title, image: Image(uiImage: uiImage))
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }
}

private struct WorkspaceMarkdownImageView: View {
    let url: URL?
    let loadFileContent: @Sendable ([UInt8]) async throws -> FileContent
    let workspaceDirectory: String?

    init(
        url: URL?,
        loadFileContent: @escaping @Sendable ([UInt8]) async throws -> FileContent,
        workspaceDirectory: String?
    ) {
        self.url = url
        self.loadFileContent = loadFileContent
        self.workspaceDirectory = workspaceDirectory
    }

    #if os(visionOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    @State private var imageData: Data?
    @State private var didAttemptLoad = false
    @State private var showImageSheet = false
    /// The decoded bitmap.
    ///
    /// `UIImage(data:)` decodes the whole image, and a computed property would
    /// do it again on every body pass — once per streamed delta while a
    /// message is still arriving.
    @State private var decodedUIImage: UIImage?

    private func decodeImage(_ data: Data?) {
        guard let data else {
            decodedUIImage = nil
            return
        }
        if decodedUIImage == nil {
            decodedUIImage = UIImage(data: data)
        }
    }

    private var imageDisplayName: String {
        if let path = WorkspaceMarkdownImageProvider.workspaceRelativePath(from: url, workspaceDirectory: workspaceDirectory) {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        if let url {
            return url.lastPathComponent.isEmpty ? L10n.t(.attachmentImageTitle) : url.lastPathComponent
        }
        return L10n.t(.attachmentImageTitle)
    }

    var body: some View {
        Group {
            if let uiImage = decodedUIImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        #if os(visionOS)
                        if let imageData {
                            openWindow(value: MarkdownImagePreviewItem(title: imageDisplayName, imageData: imageData))
                        }
                        #else
                        showImageSheet = true
                        #endif
                    }
            } else {
                // Remote http(s) images are intentionally not fetched: chat
                // content is model-controlled, and fetching would leak the
                // device's IP to whatever host the content names. Local
                // (workspace) and inline data: images render above; everything
                // else stays blank, matching the old failure path.
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .sheet(isPresented: $showImageSheet) {
            if let uiImage = decodedUIImage {
                NavigationStack {
                    ImageView(uiImage: uiImage)
                        .navigationTitle(imageDisplayName)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                ShareLink(
                                    item: Image(uiImage: uiImage),
                                    preview: SharePreview(imageDisplayName, image: Image(uiImage: uiImage))
                                ) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                            ToolbarItem(placement: .cancellationAction) {
                                Button(L10n.t(.appClose)) {
                                    showImageSheet = false
                                }
                            }
                        }
                }
            }
        }
        .task(id: url?.absoluteString) {
            guard !didAttemptLoad else {
                return
            }
            didAttemptLoad = true

            if let data = WorkspaceMarkdownImageProvider.decodeDataURL(url) {
                imageData = data
                decodeImage(data)
                return
            }

            if let path = WorkspaceMarkdownImageProvider.workspaceRelativePath(from: url, workspaceDirectory: workspaceDirectory) {
                let pathBytes = Array(path.utf8)
                do {
                    let content = try await loadFileContent(pathBytes)
                    let contentChars = content.content?.count ?? 0
                    if contentChars > WorkspaceMarkdownImageProvider.maxBase64ImageCharacters {
                        return
                    }
                    if let data = WorkspaceMarkdownImageProvider.decodeBase64ImageData(content.content) {
                        imageData = data
                        decodeImage(data)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
        }
    }
}

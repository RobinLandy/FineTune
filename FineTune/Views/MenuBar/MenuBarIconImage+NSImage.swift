// FineTune/Views/MenuBar/MenuBarIconImage+NSImage.swift
// AppKit bridge for MenuBarIconImage — kept separate so the value types
// file (MenuBarIconState.swift) stays AppKit-free and the Equatable
// conformances remain nonisolated under Swift 6 strict concurrency.

import AppKit

@MainActor
extension MenuBarIconImage {
    /// The status item is variable-length: icons of differing sizes resize it and shift every neighboring menu bar item.
    static let canvasSize = NSSize(width: 22, height: 18)

    func nsImage(accessibilityDescription: String = "FineTune") -> NSImage? {
        let sources: [NSImage]
        switch self {
        case .systemSymbol(let name):
            guard let source = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
            sources = [source]
        case .asset(let name):
            guard let source = NSImage(named: name) else { return nil }
            sources = [source]
        case .devicePair(let output, let input):
            guard let outputImage = NSImage(systemSymbolName: output, accessibilityDescription: nil)
                    ?? NSImage(systemSymbolName: "hifispeaker", accessibilityDescription: nil),
                  let inputImage = NSImage(systemSymbolName: input, accessibilityDescription: nil)
                    ?? NSImage(systemSymbolName: "mic", accessibilityDescription: nil) else { return nil }
            sources = [outputImage, inputImage]
        }

        let canvas = Self.canvasSize
        let size = NSSize(width: canvas.width * CGFloat(sources.count), height: canvas.height)
        let image = NSImage(size: size, flipped: false) { _ in
            for (index, source) in sources.enumerated() {
                let scale = min(1, canvas.width / source.size.width, canvas.height / source.size.height)
                let width = source.size.width * scale
                let height = source.size.height * scale
                source.draw(in: NSRect(
                    x: canvas.width * CGFloat(index) + (canvas.width - width) / 2,
                    y: (canvas.height - height) / 2,
                    width: width,
                    height: height
                ))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}

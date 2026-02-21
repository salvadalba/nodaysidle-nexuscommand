import Foundation
import Metal
import SwiftUI
import os

@MainActor @Observable
final class ShaderService {
    private static let logger = Logger(subsystem: "com.nexuscommand", category: "shader")

    private(set) var isMetalAvailable: Bool = false
    private var device: MTLDevice?
    private var library: MTLLibrary?

    func initialize() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Self.logger.warning("Metal is not available on this device")
            isMetalAvailable = false
            return
        }
        self.device = device
        isMetalAvailable = true

        // Load the default Metal library (compiled from .metal source files)
        do {
            library = try device.makeDefaultLibrary(bundle: .main)
            Self.logger.info("Metal library loaded successfully")
        } catch {
            // Try loading from the module bundle (SPM resource bundles)
            library = device.makeDefaultLibrary()
            if library != nil {
                Self.logger.info("Metal library loaded from default library")
            } else {
                Self.logger.warning("No Metal library found, using standard materials fallback")
            }
        }
    }

    // MARK: - SwiftUI Shader Accessors

    func blurShader(radius: Float) -> Shader? {
        guard isMetalAvailable else { return nil }
        return ShaderLibrary.gaussianBlur(.float(radius))
    }

    func glowShader(color: Color, intensity: Float) -> Shader? {
        guard isMetalAvailable else { return nil }
        let resolved = color.resolve(in: EnvironmentValues())
        return ShaderLibrary.glowEffect(
            .float(Float(resolved.red)),
            .float(Float(resolved.green)),
            .float(Float(resolved.blue)),
            .float(intensity)
        )
    }

    // MARK: - Metal Function Access

    func metalFunction(named name: String) -> MTLFunction? {
        library?.makeFunction(name: name)
    }
}

// MARK: - Shader View Modifiers

extension View {
    @ViewBuilder
    func nexusBlur(radius: Float, shaderService: ShaderService) -> some View {
        if shaderService.isMetalAvailable, let shader = shaderService.blurShader(radius: radius) {
            self.layerEffect(shader, maxSampleOffset: CGSize(width: CGFloat(radius * 2), height: CGFloat(radius * 2)))
        } else {
            self.background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    func nexusGlow(color: Color, intensity: Float, shaderService: ShaderService) -> some View {
        if shaderService.isMetalAvailable, let shader = shaderService.glowShader(color: color, intensity: intensity) {
            self.visualEffect { content, proxy in
                content.layerEffect(shader, maxSampleOffset: .zero)
            }
        } else {
            self.shadow(color: color.opacity(Double(intensity)), radius: 4)
        }
    }
}

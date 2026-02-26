import Foundation
import Metal
import MetalKit
import QuartzCore

/// Metal-based renderer for emulator framebuffer
class MetalRenderer: NSObject, MTKViewDelegate {
    // Metal objects
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var texture: MTLTexture?
    private let sampler: MTLSamplerState

    // Vertex buffer for fullscreen quad
    private let vertexBuffer: MTLBuffer

    // Current frame dimensions (from SystemInfo initially, updated per frame)
    private var currentWidth: Int
    private var currentHeight: Int

    // Pixel aspect ratio from SystemInfo for per-frame DAR computation
    private let pixelAspectRatio: Float

    // Callback for frame requests
    var onFrameRequest: (() -> FrameData?)?

    // View size (set from SwiftUI to ensure correct orientation)
    var viewSize: CGSize = .zero

    init?(mtkView: MTKView) {
        let info = EmulatorBridge.systemInfo
        self.currentWidth = info.screenWidth
        self.currentHeight = info.maxScreenHeight
        self.pixelAspectRatio = Float(info.pixelAspectRatio)

        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue

        // Configure view
        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        // Create shader library and pipeline
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "vertexShader"),
              let fragmentFunction = library.makeFunction(name: "fragmentShader") else {

            // If shaders aren't compiled, use simple passthrough
            guard let pipelineState = Self.createSimplePipeline(device: device) else {
                return nil
            }
            self.pipelineState = pipelineState
            self.sampler = Self.createSampler(device: device)!
            self.vertexBuffer = Self.createVertexBuffer(device: device)!
            super.init()
            return
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat

        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else {
            return nil
        }
        self.pipelineState = pipelineState

        // Create sampler for nearest-neighbor filtering (crisp pixels)
        guard let sampler = Self.createSampler(device: device) else {
            return nil
        }
        self.sampler = sampler

        // Create vertex buffer
        guard let vertexBuffer = Self.createVertexBuffer(device: device) else {
            return nil
        }
        self.vertexBuffer = vertexBuffer

        super.init()
    }

    private static func createSampler(device: MTLDevice) -> MTLSamplerState? {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .nearest
        samplerDescriptor.magFilter = .nearest
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: samplerDescriptor)
    }

    private static func createVertexBuffer(device: MTLDevice) -> MTLBuffer? {
        // Fullscreen quad vertices (position + texcoord)
        let vertices: [Float] = [
            // Position (x, y), Texcoord (u, v)
            -1.0, -1.0, 0.0, 1.0,  // Bottom-left
             1.0, -1.0, 1.0, 1.0,  // Bottom-right
            -1.0,  1.0, 0.0, 0.0,  // Top-left
             1.0,  1.0, 1.0, 0.0,  // Top-right
        ]
        return device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.size, options: .storageModeShared)
    }

    private static func createSimplePipeline(device: MTLDevice) -> MTLRenderPipelineState? {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                                      constant float4 *vertices [[buffer(0)]]) {
            float4 v = vertices[vertexID];
            VertexOut out;
            out.position = float4(v.xy, 0.0, 1.0);
            out.texCoord = v.zw;
            return out;
        }

        fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                       texture2d<float> texture [[texture(0)]],
                                       sampler textureSampler [[sampler(0)]]) {
            return texture.sample(textureSampler, in.texCoord);
        }
        """

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let vertexFunction = library.makeFunction(name: "vertexShader")
            let fragmentFunction = library.makeFunction(name: "fragmentShader")

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            return nil
        }
    }

    /// Update the texture with new framebuffer data
    func updateTexture(with data: Data, width: Int, height: Int) {
        // Recreate texture if dimensions changed
        if texture == nil || currentWidth != width || currentHeight != height {
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            textureDescriptor.usage = [.shaderRead]
            texture = device.makeTexture(descriptor: textureDescriptor)
            currentWidth = width
            currentHeight = height
        }

        // Copy pixel data to texture
        guard let texture = texture else { return }

        data.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                   size: MTLSize(width: width, height: height, depth: 1))
            texture.replace(region: region,
                           mipmapLevel: 0,
                           withBytes: baseAddress,
                           bytesPerRow: width * 4)
        }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle resize if needed
    }

    func draw(in view: MTKView) {
        // Force drawable to match view bounds on every frame
        let scale = UIScreen.main.scale
        let expectedDrawableSize = CGSize(width: view.bounds.width * scale, height: view.bounds.height * scale)
        if view.drawableSize != expectedDrawableSize {
            view.drawableSize = expectedDrawableSize
        }

        // Request frame data from emulator
        if let frame = onFrameRequest?() {
            let width = frame.stride / 4
            updateTexture(with: frame.pixels, width: width, height: frame.activeHeight)
        }

        guard let texture = texture,
              let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        // Calculate aspect-correct scaling using view bounds (always correct)
        let effectiveSize = view.bounds.size
        let viewAspect = Float(effectiveSize.width / effectiveSize.height)

        // Compute DAR per-frame from actual texture dimensions and PAR
        let textureAspect = (Float(currentWidth) / Float(currentHeight)) * pixelAspectRatio

        var scaleX: Float = 1.0
        var scaleY: Float = 1.0

        if viewAspect > textureAspect {
            // View is wider than texture - letterbox on sides
            scaleX = textureAspect / viewAspect
        } else {
            // View is taller than texture - letterbox top/bottom
            scaleY = viewAspect / textureAspect
        }

        let vertices: [Float] = [
            -scaleX, -scaleY, 0.0, 1.0,
             scaleX, -scaleY, 1.0, 1.0,
            -scaleX,  scaleY, 0.0, 0.0,
             scaleX,  scaleY, 1.0, 0.0,
        ]

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBytes(vertices, length: vertices.count * MemoryLayout<Float>.size, index: 0)
        renderEncoder.setFragmentTexture(texture, index: 0)
        renderEncoder.setFragmentSamplerState(sampler, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

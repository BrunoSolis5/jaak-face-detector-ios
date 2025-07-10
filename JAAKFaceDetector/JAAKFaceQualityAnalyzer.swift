import Vision
import AVFoundation
import UIKit
import MediaPipeTasksVision

/// Analyzes face quality for progressive recording
internal class JAAKFaceQualityAnalyzer {
    
    // MARK: - Types
    
    struct QualityMetrics {
        let sharpness: Float
        let brightness: Float
        let contrast: Float
        let faceSize: Float
        let facePosition: Float
        let stability: Float
        let overallScore: Float
        
        init(sharpness: Float, brightness: Float, contrast: Float, faceSize: Float, facePosition: Float, stability: Float) {
            self.sharpness = sharpness
            self.brightness = brightness
            self.contrast = contrast
            self.faceSize = faceSize
            self.facePosition = facePosition
            self.stability = stability
            
            // Calculate weighted overall score
            self.overallScore = (
                sharpness * 0.25 +
                brightness * 0.15 +
                contrast * 0.15 +
                faceSize * 0.20 +
                facePosition * 0.15 +
                stability * 0.10
            )
        }
    }
    
    // MARK: - Properties
    
    private var previousFacePositions: [CGPoint] = []
    private var previousBrightness: [Float] = []
    private let maxHistorySize = 10
    
    // MARK: - Public Methods
    
    /// Analyze face quality in current frame
    /// - Parameters:
    ///   - face: detected face observation
    ///   - sampleBuffer: current video frame
    /// - Returns: quality score from 0.0 to 1.0
    func analyzeQuality(detection: Detection, sampleBuffer: CMSampleBuffer) -> Float {
        let metrics = calculateQualityMetrics(detection: detection, sampleBuffer: sampleBuffer)
        return metrics.overallScore
    }
    
    /// Get detailed quality metrics
    /// - Parameters:
    ///   - face: detected face observation
    ///   - sampleBuffer: current video frame
    /// - Returns: detailed quality metrics
    func getDetailedMetrics(detection: Detection, sampleBuffer: CMSampleBuffer) -> QualityMetrics {
        return calculateQualityMetrics(detection: detection, sampleBuffer: sampleBuffer)
    }
    
    /// Reset quality analyzer history
    func reset() {
        previousFacePositions.removeAll()
        previousBrightness.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func calculateQualityMetrics(detection: Detection, sampleBuffer: CMSampleBuffer) -> QualityMetrics {
        let sharpness = analyzeSharpness(detection: detection, sampleBuffer: sampleBuffer)
        let brightness = analyzeBrightness(detection: detection, sampleBuffer: sampleBuffer)
        let contrast = analyzeContrast(detection: detection, sampleBuffer: sampleBuffer)
        let faceSize = analyzeFaceSize(detection: detection)
        let facePosition = analyzeFacePosition(detection: detection)
        let stability = analyzeStability(detection: detection)
        
        return QualityMetrics(
            sharpness: sharpness,
            brightness: brightness,
            contrast: contrast,
            faceSize: faceSize,
            facePosition: facePosition,
            stability: stability
        )
    }
    
    private func analyzeSharpness(detection: Detection, sampleBuffer: CMSampleBuffer) -> Float {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return 0.0 }
        
        // Convert face bounds to pixel coordinates
        let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
        let imageHeight = CVPixelBufferGetHeight(pixelBuffer)
        
        let faceRect = VNImageRectForNormalizedRect(
            detection.boundingBox,
            imageWidth,
            imageHeight
        )
        
        // Calculate sharpness using Laplacian variance
        let sharpness = calculateLaplacianVariance(pixelBuffer: pixelBuffer, rect: faceRect)
        
        // Normalize to 0-1 range (typical values are 0-500)
        return min(sharpness / 500.0, 1.0)
    }
    
    private func analyzeBrightness(detection: Detection, sampleBuffer: CMSampleBuffer) -> Float {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return 0.0 }
        
        let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
        let imageHeight = CVPixelBufferGetHeight(pixelBuffer)
        
        let faceRect = VNImageRectForNormalizedRect(
            detection.boundingBox,
            imageWidth,
            imageHeight
        )
        
        let brightness = calculateAverageBrightness(pixelBuffer: pixelBuffer, rect: faceRect)
        
        // Store for stability analysis
        previousBrightness.append(brightness)
        if previousBrightness.count > maxHistorySize {
            previousBrightness.removeFirst()
        }
        
        // Optimal brightness is around 0.4-0.6 range
        let optimalRange: ClosedRange<Float> = 0.4...0.6
        if optimalRange.contains(brightness) {
            return 1.0
        } else {
            let distance = min(abs(brightness - 0.4), abs(brightness - 0.6))
            return max(0.0, 1.0 - distance * 2.0)
        }
    }
    
    private func analyzeContrast(detection: Detection, sampleBuffer: CMSampleBuffer) -> Float {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return 0.0 }
        
        let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
        let imageHeight = CVPixelBufferGetHeight(pixelBuffer)
        
        let faceRect = VNImageRectForNormalizedRect(
            detection.boundingBox,
            imageWidth,
            imageHeight
        )
        
        let contrast = calculateContrast(pixelBuffer: pixelBuffer, rect: faceRect)
        
        // Normalize contrast (typical values 0-1)
        return min(contrast, 1.0)
    }
    
    private func analyzeFaceSize(detection: Detection) -> Float {
        let faceArea = Float(detection.boundingBox.width * detection.boundingBox.height)
        
        // Optimal face size is 15-30% of frame
        let optimalRange: ClosedRange<Float> = 0.15...0.30
        
        if optimalRange.contains(faceArea) {
            return 1.0
        } else if faceArea < 0.15 {
            // Too small - score based on how close to minimum
            return max(0.0, faceArea / 0.15)
        } else {
            // Too large - score decreases as it gets larger
            return max(0.0, 1.0 - (faceArea - 0.30) / 0.20)
        }
    }
    
    private func analyzeFacePosition(detection: Detection) -> Float {
        let faceCenter = CGPoint(
            x: detection.boundingBox.midX,
            y: detection.boundingBox.midY
        )
        
        let frameCenter = CGPoint(x: 0.5, y: 0.5)
        
        let distance = sqrt(
            pow(faceCenter.x - frameCenter.x, 2) +
            pow(faceCenter.y - frameCenter.y, 2)
        )
        
        // Perfect center gets 1.0, score decreases with distance
        return max(0.0, 1.0 - Float(distance) * 4.0)
    }
    
    private func analyzeStability(detection: Detection) -> Float {
        let currentCenter = CGPoint(
            x: detection.boundingBox.midX,
            y: detection.boundingBox.midY
        )
        
        previousFacePositions.append(currentCenter)
        if previousFacePositions.count > maxHistorySize {
            previousFacePositions.removeFirst()
        }
        
        guard previousFacePositions.count >= 3 else { return 0.5 }
        
        // Calculate average movement between frames
        var totalMovement: Float = 0.0
        for i in 1..<previousFacePositions.count {
            let prev = previousFacePositions[i-1]
            let curr = previousFacePositions[i]
            
            let movement = sqrt(
                pow(curr.x - prev.x, 2) +
                pow(curr.y - prev.y, 2)
            )
            
            totalMovement += Float(movement)
        }
        
        let averageMovement = totalMovement / Float(previousFacePositions.count - 1)
        
        // Less movement = higher stability score
        return max(0.0, 1.0 - averageMovement * 20.0)
    }
    
    // MARK: - Image Processing Helpers
    
    private func calculateLaplacianVariance(pixelBuffer: CVPixelBuffer, rect: CGRect) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0.0 }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        let startX = max(0, Int(rect.minX))
        let startY = max(0, Int(rect.minY))
        let endX = min(width - 1, Int(rect.maxX))
        let endY = min(height - 1, Int(rect.maxY))
        
        var variance: Float = 0.0
        var mean: Float = 0.0
        var count = 0
        
        for y in startY+1..<endY-1 {
            for x in startX+1..<endX-1 {
                let pixelPtr = baseAddress.advanced(by: y * bytesPerRow + x * 4)
                let pixel = pixelPtr.assumingMemoryBound(to: UInt8.self)
                
                // Convert to grayscale
                let gray = Float(pixel[0]) * 0.299 + Float(pixel[1]) * 0.587 + Float(pixel[2]) * 0.114
                
                // Apply Laplacian kernel
                let laplacian = -4 * gray +
                    Float(pixel.advanced(by: -bytesPerRow).pointee) + // top
                    Float(pixel.advanced(by: bytesPerRow).pointee) + // bottom
                    Float(pixel.advanced(by: -4).pointee) + // left
                    Float(pixel.advanced(by: 4).pointee) // right
                
                mean += laplacian
                variance += laplacian * laplacian
                count += 1
            }
        }
        
        if count > 0 {
            mean /= Float(count)
            variance = variance / Float(count) - mean * mean
        }
        
        return variance
    }
    
    private func calculateAverageBrightness(pixelBuffer: CVPixelBuffer, rect: CGRect) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0.0 }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        let startX = max(0, Int(rect.minX))
        let startY = max(0, Int(rect.minY))
        let endX = min(width, Int(rect.maxX))
        let endY = min(height, Int(rect.maxY))
        
        var totalBrightness: Float = 0.0
        var count = 0
        
        for y in startY..<endY {
            for x in startX..<endX {
                let pixelPtr = baseAddress.advanced(by: y * bytesPerRow + x * 4)
                let pixel = pixelPtr.assumingMemoryBound(to: UInt8.self)
                
                // Convert to grayscale brightness
                let brightness = Float(pixel[0]) * 0.299 + Float(pixel[1]) * 0.587 + Float(pixel[2]) * 0.114
                totalBrightness += brightness / 255.0
                count += 1
            }
        }
        
        return count > 0 ? totalBrightness / Float(count) : 0.0
    }
    
    private func calculateContrast(pixelBuffer: CVPixelBuffer, rect: CGRect) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0.0 }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        let startX = max(0, Int(rect.minX))
        let startY = max(0, Int(rect.minY))
        let endX = min(width, Int(rect.maxX))
        let endY = min(height, Int(rect.maxY))
        
        var minBrightness: Float = 1.0
        var maxBrightness: Float = 0.0
        
        for y in startY..<endY {
            for x in startX..<endX {
                let pixelPtr = baseAddress.advanced(by: y * bytesPerRow + x * 4)
                let pixel = pixelPtr.assumingMemoryBound(to: UInt8.self)
                
                let brightness = Float(pixel[0]) * 0.299 + Float(pixel[1]) * 0.587 + Float(pixel[2]) * 0.114
                let normalizedBrightness = brightness / 255.0
                
                minBrightness = min(minBrightness, normalizedBrightness)
                maxBrightness = max(maxBrightness, normalizedBrightness)
            }
        }
        
        return maxBrightness - minBrightness
    }
}
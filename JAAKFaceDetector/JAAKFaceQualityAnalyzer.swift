import AVFoundation
import UIKit
import MediaPipeTasksVision

/// Analyzes face quality for auto recording (simplified version)
internal class JAAKFaceQualityAnalyzer {
    
    // MARK: - Types
    
    struct QualityMetrics {
        let faceSize: Float
        let facePosition: Float
        let stability: Float
        let overallScore: Float
        
        init(faceSize: Float, facePosition: Float, stability: Float) {
            self.faceSize = faceSize
            self.facePosition = facePosition
            self.stability = stability
            
            // Calculate weighted overall score (simplified)
            self.overallScore = (
                faceSize * 0.4 +
                facePosition * 0.35 +
                stability * 0.25
            )
        }
    }
    
    // MARK: - Properties
    
    private var previousFacePositions: [CGPoint] = []
    private let maxHistorySize = 10
    
    // MARK: - Public Methods
    
    /// Analyze face quality in current frame
    /// - Parameters:
    ///   - detection: detected face from MediaPipe
    /// - Returns: quality score from 0.0 to 1.0
    func analyzeQuality(detection: Detection) -> Float {
        let metrics = calculateQualityMetrics(detection: detection)
        return metrics.overallScore
    }
    
    /// Get detailed quality metrics
    /// - Parameters:
    ///   - detection: detected face from MediaPipe
    /// - Returns: detailed quality metrics
    func getDetailedMetrics(detection: Detection) -> QualityMetrics {
        return calculateQualityMetrics(detection: detection)
    }
    
    /// Reset quality analyzer history
    func reset() {
        previousFacePositions.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func calculateQualityMetrics(detection: Detection) -> QualityMetrics {
        let faceSize = analyzeFaceSize(detection: detection)
        let facePosition = analyzeFacePosition(detection: detection)
        let stability = analyzeStability(detection: detection)
        
        return QualityMetrics(
            faceSize: faceSize,
            facePosition: facePosition,
            stability: stability
        )
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
}
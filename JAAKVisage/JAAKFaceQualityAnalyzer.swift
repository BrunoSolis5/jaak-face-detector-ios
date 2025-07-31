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
        let faceYaw: Float
        let isYawOptimal: Bool
        let overallScore: Float
        
        init(faceSize: Float, facePosition: Float, stability: Float, faceYaw: Float, isYawOptimal: Bool) {
            self.faceSize = faceSize
            self.facePosition = facePosition
            self.stability = stability
            self.faceYaw = faceYaw
            self.isYawOptimal = isYawOptimal
            
            // Calculate weighted overall score - yaw validation is critical for recording
            let yawScore: Float = isYawOptimal ? 1.0 : 0.0
            self.overallScore = (
                faceSize * 0.3 +
                facePosition * 0.25 +
                stability * 0.2 +
                yawScore * 0.25 // Yaw validation gets significant weight
            )
        }
    }
    
    // MARK: - Properties
    
    private var previousFacePositions: [CGPoint] = []
    private let maxHistorySize = 10
    
    // Yaw validation constants (matching webcomponent)
    private static let maxYawThreshold: Float = 10.0 // degrees
    
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
        let (faceYaw, isYawOptimal) = analyzeFaceYaw(detection: detection)
        
        return QualityMetrics(
            faceSize: faceSize,
            facePosition: facePosition,
            stability: stability,
            faceYaw: faceYaw,
            isYawOptimal: isYawOptimal
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
    
    private func analyzeFaceYaw(detection: Detection) -> (yaw: Float, isOptimal: Bool) {
        // Check if we have face landmarks for yaw calculation
        guard let keypoints = detection.keypoints, keypoints.count >= 6 else {
            print("⚠️ [FaceQualityAnalyzer] Not enough keypoints for yaw calculation: \(detection.keypoints?.count ?? 0)")
            return (0.0, true) // Default to optimal if no landmarks available
        }
        
        // MediaPipe face keypoint indices (standard BlazeFace model)
        // 0: right eye, 1: left eye, 2: nose tip, 3: mouth center, 4: right ear tragion, 5: left ear tragion
        let rightEye = keypoints[0]
        let leftEye = keypoints[1] 
        let noseTip = keypoints[2]
        let mouthCenter = keypoints[3]
        
        // Calculate yaw using same logic as webcomponent
        // eyesCenterX = (rightEye.x + leftEye.x) / 2
        let eyesCenterX = Float(rightEye.location.x + leftEye.location.x) / 2.0
        
        // noseMouthCenterX = (nose.x + mouth.x) / 2
        let noseMouthCenterX = Float(noseTip.location.x + mouthCenter.location.x) / 2.0
        
        // faceWidth = Math.abs(leftEye.x - rightEye.x)
        let faceWidth = abs(Float(leftEye.location.x - rightEye.location.x))
        
        // Avoid division by zero
        guard faceWidth > 0 else {
            print("⚠️ [FaceQualityAnalyzer] Face width is zero, cannot calculate yaw")
            return (0.0, true)
        }
        
        // asymmetry = (noseMouthCenterX - eyesCenterX) / faceWidth
        let asymmetry = (noseMouthCenterX - eyesCenterX) / faceWidth
        
        // yawRadians = Math.asin(Math.max(-1, Math.min(1, asymmetry * 2)))
        let clampedAsymmetry = max(-1.0, min(1.0, asymmetry * 2.0))
        let yawRadians = asin(clampedAsymmetry)
        
        // Convert to degrees: this.faceYaw = (yawRadians * 180 / Math.PI)
        let faceYaw = yawRadians * 180.0 / Float.pi
        
        // Check if yaw is within optimal range (same as webcomponent)
        let isYawOptimal = abs(faceYaw) <= Self.maxYawThreshold
        
        print("🔄 [FaceQualityAnalyzer] Yaw analysis - asymmetry: \(asymmetry), yaw: \(faceYaw)°, optimal: \(isYawOptimal)")
        
        return (faceYaw, isYawOptimal)
    }
}
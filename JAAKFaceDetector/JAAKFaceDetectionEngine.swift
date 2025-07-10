import AVFoundation
import UIKit
import MediaPipeTasksVision

/// Internal class for face detection using MediaPipe BlazeFace (same as webcomponent)
internal class JAAKFaceDetectionEngine: NSObject {
    
    // MARK: - Properties
    
    private var faceDetector: FaceDetector?
    private var lastFaceDetectionTime: Date = Date()
    private var consecutiveNoFaceFrames: Int = 0
    private let maxConsecutiveNoFaceFrames = 5
    
    weak var delegate: JAAKFaceDetectionEngineDelegate?
    
    private let configuration: JAAKFaceDetectorConfiguration
    
    // MARK: - Initialization
    
    init(configuration: JAAKFaceDetectorConfiguration) {
        self.configuration = configuration
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Load ML models for face detection
    /// - Throws: JAAKFaceDetectorError if model loading fails
    func loadModels() throws {
        // Load MediaPipe BlazeFace model from Resources
        try loadMediaPipeModel()
    }
    
    /// Process video frame for face detection
    /// - Parameter sampleBuffer: video frame to process
    func processVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard !configuration.disableFaceDetection else { return }
        guard let faceDetector = faceDetector else { return }
        
        // Store sample buffer for quality analysis
        currentSampleBuffer = sampleBuffer
        
        // Throttle face detection to optimize performance
        let now = Date()
        if now.timeIntervalSince(lastFaceDetectionTime) < getDetectionInterval() {
            return
        }
        lastFaceDetectionTime = now
        
        // Convert CMSampleBuffer to MPImage for MediaPipe
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else {
            return
        }
        
        do {
            // Create MPImage from CMSampleBuffer
            let mpImage = try MPImage(sampleBuffer: sampleBuffer)
            
            // Process with MediaPipe BlazeFace model (same as webcomponent)
            let result = try faceDetector.detect(image: mpImage)
            
            // Handle MediaPipe results
            handleMediaPipeResults(result)
            
        } catch {
            let detectorError = JAAKFaceDetectorError(
                label: "MediaPipe face detection failed",
                code: "MEDIAPIPE_DETECTION_FAILED",
                details: error
            )
            delegate?.faceDetectionEngine(self, didFailWithError: detectorError)
        }
    }
    
    /// Store sample buffer for quality analysis
    private var currentSampleBuffer: CMSampleBuffer?
    
    // MARK: - Private Methods
    
    
    private func loadMediaPipeModel() throws {
        // Load MediaPipe BlazeFace model from Resources (same as webcomponent)
        guard let modelPath = Bundle.main.path(forResource: "Models/blaze_face_short_range", ofType: "tflite") else {
            throw JAAKFaceDetectorError(
                label: "MediaPipe BlazeFace model not found in Resources",
                code: "MEDIAPIPE_MODEL_NOT_FOUND"
            )
        }
        
        do {
            // Create MediaPipe FaceDetector options
            let options = FaceDetectorOptions()
            options.baseOptions.modelAssetPath = modelPath
            options.runningMode = .video
            options.minDetectionConfidence = 0.5
            options.minSuppressionThreshold = 0.3
            
            // Initialize MediaPipe FaceDetector
            faceDetector = try FaceDetector(options: options)
            
            print("📱 MediaPipe BlazeFace model loaded from: \(modelPath)")
            print("🎯 Using same model as webcomponent")
            
        } catch {
            throw JAAKFaceDetectorError(
                label: "Failed to initialize MediaPipe FaceDetector",
                code: "MEDIAPIPE_INIT_FAILED",
                details: error
            )
        }
    }
    
    private func handleMediaPipeResults(_ result: FaceDetectorResult) {
        // Convert MediaPipe results to our format (same as webcomponent)
        if result.detections.isEmpty {
            handleNoFaceDetected()
        } else {
            // Process MediaPipe detections
            // Work directly with MediaPipe detections
            handleFaceDetected(result.detections)
            
            // Notify delegate with faces and sample buffer for quality analysis
            if let sampleBuffer = currentSampleBuffer {
                notifyFacesDetected(result.detections, sampleBuffer: sampleBuffer)
            }
        }
    }
    
    
    
    private func handleFaceDetected(_ detections: [Detection]) {
        consecutiveNoFaceFrames = 0
        
        // For now, we'll work with the first (largest) face
        guard let primaryFace = detections.first else { return }
        
        // Validate face position and size
        let isValidPosition = validateFacePosition(primaryFace)
        
        let message = JAAKFaceDetectionMessage(
            label: isValidPosition ? "Face detected in correct position" : "Face detected but repositioning needed",
            details: "Face confidence: \(primaryFace.categories.first?.score ?? 0.0)",
            faceExists: true,
            correctPosition: isValidPosition
        )
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.faceDetectionEngine(self, didDetectFace: message, boundingBox: primaryFace.boundingBox)
        }
    }
    
    private func notifyFacesDetected(_ detections: [Detection], sampleBuffer: CMSampleBuffer) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.faceDetectionEngine(self, didDetectFaces: detections, sampleBuffer: sampleBuffer)
        }
    }
    
    private func handleNoFaceDetected() {
        consecutiveNoFaceFrames += 1
        
        let message = JAAKFaceDetectionMessage(
            label: "No face detected",
            details: "Consecutive no-face frames: \(consecutiveNoFaceFrames)",
            faceExists: false,
            correctPosition: false
        )
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.faceDetectionEngine(self, didDetectFace: message, boundingBox: .zero)
        }
    }
    
    private func validateFacePosition(_ detection: Detection) -> Bool {
        // Validate face size (minimum 15% of frame area as per specification)
        let faceArea = detection.boundingBox.width * detection.boundingBox.height
        let minimumRequiredArea: CGFloat = 0.15 // 15% as specified
        
        return faceArea >= minimumRequiredArea
    }
    
    private func getDetectionInterval() -> TimeInterval {
        // Adaptive FPS based on device capabilities as per specification
        let deviceModel = UIDevice.current.model
        let fps: Int
        
        if deviceModel.contains("iPhone") {
            // Simplified device detection - in real implementation would be more sophisticated
            fps = 12 // Default for iPhone
        } else if deviceModel.contains("iPad") {
            fps = 18 // iPad Pro
        } else {
            fps = 12 // Default
        }
        
        return 1.0 / Double(fps)
    }
    
    /// Check if face tracking should trigger auto-recording
    /// - Returns: true if conditions are met for auto-recording
    func shouldTriggerAutoRecording() -> Bool {
        return consecutiveNoFaceFrames < maxConsecutiveNoFaceFrames
    }
}

// MARK: - JAAKFaceDetectionEngineDelegate

protocol JAAKFaceDetectionEngineDelegate: AnyObject {
    func faceDetectionEngine(_ engine: JAAKFaceDetectionEngine, didDetectFace message: JAAKFaceDetectionMessage, boundingBox: CGRect)
    func faceDetectionEngine(_ engine: JAAKFaceDetectionEngine, didDetectFaces detections: [Detection], sampleBuffer: CMSampleBuffer)
    func faceDetectionEngine(_ engine: JAAKFaceDetectionEngine, didFailWithError error: JAAKFaceDetectorError)
}
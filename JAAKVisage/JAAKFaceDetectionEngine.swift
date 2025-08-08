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
    private var isDetectionPaused: Bool = false
    private var qualityAnalyzer: JAAKFaceQualityAnalyzer
    
    // Stability tracking for auto-recording
    private var consecutiveValidFrames: Int = 0
    private var consecutiveInvalidFrames: Int = 0
    private let requiredStabilityFrames = 3 // Need 3 consecutive valid frames to start recording
    // NOTE: Cancellation is now immediate (no threshold needed)
    
    weak var delegate: JAAKFaceDetectionEngineDelegate?
    
    private var configuration: JAAKVisageConfiguration
    
    // MARK: - Initialization
    
    init(configuration: JAAKVisageConfiguration) {
        self.configuration = configuration
        self.qualityAnalyzer = JAAKFaceQualityAnalyzer()
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Load ML models for face detection
    /// - Throws: JAAKVisageError if model loading fails
    func loadModels() throws {
        // Load MediaPipe BlazeFace model from Resources
        try loadMediaPipeModel()
    }
    
    /// Process video frame for face detection
    /// - Parameters:
    ///   - sampleBuffer: video frame to process
    ///   - timestamp: timestamp in milliseconds (optional, will calculate if not provided)
    func processVideoFrame(_ sampleBuffer: CMSampleBuffer, timestamp: Int? = nil) {
        guard !configuration.disableFaceDetection else { return }
        guard !isDetectionPaused else { return } // Skip detection if paused for instructions
        guard let faceDetector = faceDetector else { 
            return 
        }
        
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
            
            // Use provided timestamp or calculate from sample buffer
            let timestampMs: Int
            if let providedTimestamp = timestamp {
                timestampMs = providedTimestamp
            } else {
                let sampleTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                timestampMs = Int(CMTimeGetSeconds(sampleTimestamp) * 1000)
            }
            
            // Process with MediaPipe BlazeFace model in live stream mode (same as webcomponent)
            try faceDetector.detectAsync(image: mpImage, timestampInMilliseconds: timestampMs)
            
        } catch {
            let detectorError = JAAKVisageError(
                label: "Falló la detección facial MediaPipe",
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
        let bundle = Bundle(for: JAAKFaceDetectionEngine.self)
        
        
        // Try multiple possible paths
        var modelPath: String?
        
        // Option 1: Direct in bundle
        modelPath = bundle.path(forResource: "blaze_face_short_range", ofType: "tflite")
        if modelPath == nil {
            // Option 2: In Models subdirectory
            modelPath = bundle.path(forResource: "blaze_face_short_range", ofType: "tflite", inDirectory: "Models")
        }
        if modelPath == nil {
            // Option 3: In JAAKVisage resource bundle
            modelPath = bundle.path(forResource: "blaze_face_short_range", ofType: "tflite", inDirectory: "JAAKVisage.bundle/Models")
        }
        if modelPath == nil {
            // Option 4: Try main bundle
            modelPath = Bundle.main.path(forResource: "blaze_face_short_range", ofType: "tflite")
        }
        
        guard let finalPath = modelPath else {
            throw JAAKVisageError(
                label: "Modelo MediaPipe BlazeFace no encontrado en ninguna ubicación esperada",
                code: "MEDIAPIPE_MODEL_NOT_FOUND"
            )
        }
        
        do {
            // Create MediaPipe FaceDetector options
            let options = FaceDetectorOptions()
            options.baseOptions.modelAssetPath = finalPath
            options.runningMode = .liveStream
            options.minDetectionConfidence = 0.5
            options.minSuppressionThreshold = 0.3
            
            // Set up result callback for live stream mode
            options.faceDetectorLiveStreamDelegate = self
            
            // Initialize MediaPipe FaceDetector
            faceDetector = try FaceDetector(options: options)
            
        } catch {
            throw JAAKVisageError(
                label: "Error al inicializar MediaPipe FaceDetector",
                code: "MEDIAPIPE_INIT_FAILED",
                details: error
            )
        }
    }
    
    private func handleMediaPipeResults(_ result: FaceDetectorResult) {
        // Convert MediaPipe results to our format (same as webcomponent)
        // Safely access detections array
        let detections = result.detections
        
        if detections.isEmpty {
            handleNoFaceDetected()
        } else {
            // Process MediaPipe detections with defensive checks
            // Work directly with MediaPipe detections
            handleFaceDetected(detections)
            
            // Notify delegate with faces and sample buffer for quality analysis
            if let sampleBuffer = currentSampleBuffer {
                notifyFacesDetected(detections, sampleBuffer: sampleBuffer)
            }
        }
    }
    
    
    
    private func handleFaceDetected(_ detections: [Detection]) {
        consecutiveNoFaceFrames = 0
        
        // Safely access first detection with additional checks
        guard detections.count > 0 else {
            return
        }
        
        let primaryFace = detections[0]
        
        // Safely access Detection properties with defensive checks
        var confidence: Float = 0.0
        
        // Safely access categories to get confidence
        let categories = primaryFace.categories
        
        if categories.count > 0 {
            let firstCategory = categories[0]
            confidence = firstCategory.score
        } else {
            confidence = 0.9 // Default confidence for detected faces without categories
        }
        
        // Validate face position and generate instructive message
        let (isValidPosition, instructionMessage) = validateFacePositionWithInstructions(primaryFace)
        
        // Update stability counters
        if isValidPosition {
            consecutiveValidFrames += 1
            consecutiveInvalidFrames = 0
        } else {
            consecutiveValidFrames = 0
            consecutiveInvalidFrames += 1
        }
        
        // Determine if position is stable enough for recording
        let isStableForRecording = consecutiveValidFrames >= requiredStabilityFrames
        
        print("📊 [FaceDetectionEngine] isValidPosition: \(isValidPosition), consecutiveValidFrames: \(consecutiveValidFrames)/\(requiredStabilityFrames), isStableForRecording: \(isStableForRecording)")
        // No longer need shouldCancelRecording since cancellation is immediate
        
        let message = JAAKFaceDetectionMessage(
            label: isStableForRecording ? "Perfecto" : instructionMessage,
            details: "Face confidence: \(confidence), Valid frames: \(consecutiveValidFrames), Invalid frames: \(consecutiveInvalidFrames)",
            faceExists: true,
            correctPosition: isStableForRecording // Only true when stable enough
        )
        
        // Auto-recording logic is now handled by JAAKVisage handleOptimalPosition method
        // This follows the webcomponent pattern where all recording logic is centralized
        // So we don't call shouldCancelRecording here anymore
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Normalize bounding box coordinates to 0-1 range
            let normalizedBoundingBox = self.normalizeBoundingBox(primaryFace.boundingBox)
            let orientationAdjustedSize = self.getOrientationAdjustedVideoSize()
            self.delegate?.faceDetectionEngine(self, didDetectFace: message, boundingBox: normalizedBoundingBox, videoNativeSize: orientationAdjustedSize)
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
        
        // Reset stability counters when no face is detected
        consecutiveValidFrames = 0
        consecutiveInvalidFrames = 0
        
        // Auto-recording cancellation is now handled by JAAKVisage handleOptimalPosition method
        // This follows the webcomponent pattern where all recording logic is centralized
        
        let message = JAAKFaceDetectionMessage(
            label: "Dirige tu rostro hacia la cámara",
            details: "Consecutive no-face frames: \(consecutiveNoFaceFrames)",
            faceExists: false,
            correctPosition: false
        )
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let orientationAdjustedSize = self.getOrientationAdjustedVideoSize()
            self.delegate?.faceDetectionEngine(self, didDetectFace: message, boundingBox: .zero, videoNativeSize: orientationAdjustedSize)
        }
    }
    
    private func validateFacePosition(_ detection: Detection) -> Bool {
        // Validate face size following MediaPipe's official pattern
        let boundingBox = detection.boundingBox
        
        // MediaPipe documentation says coordinates should be normalized [0.0, 1.0]
        // But we're seeing pixel coordinates - this might be the source of the Range crash
        
        // First, let's check if coordinates are normalized or pixel-based
        let isNormalized = boundingBox.width <= 1.0 && boundingBox.height <= 1.0 &&
                          boundingBox.origin.x <= 1.0 && boundingBox.origin.y <= 1.0
        
        if isNormalized {
            // Handle normalized coordinates (0.0 to 1.0)
            guard boundingBox.width > 0 && boundingBox.height > 0 &&
                  boundingBox.origin.x >= 0 && boundingBox.origin.y >= 0 &&
                  boundingBox.width <= 1.0 && boundingBox.height <= 1.0 &&
                  boundingBox.origin.x <= 1.0 && boundingBox.origin.y <= 1.0 else {
                return false
            }
            
            // For normalized coordinates, minimum 15% of frame area
            let faceArea = boundingBox.width * boundingBox.height
            let minimumFaceArea: CGFloat = 0.15 // 15% of frame area
            
            let isValidSize = faceArea >= minimumFaceArea
            
            return isValidSize
            
        } else {
            // Handle pixel coordinates
            guard boundingBox.width > 0 && boundingBox.height > 0 &&
                  boundingBox.origin.x >= 0 && boundingBox.origin.y >= 0 else {
                return false
            }
            
            // Additional safety checks for extreme values
            guard boundingBox.width < 10000 && boundingBox.height < 10000 &&
                  boundingBox.origin.x < 10000 && boundingBox.origin.y < 10000 else {
                return false
            }
            
            // For pixel coordinates, minimum 100x100 pixel face
            let faceArea = boundingBox.width * boundingBox.height
            let minimumFacePixelArea: CGFloat = 10000 // Minimum 100x100 pixel face
            
            let isValidSize = faceArea >= minimumFacePixelArea
            
            return isValidSize
        }
    }
    
    /// Validate face position and provide instructive messages
    /// - Parameter detection: MediaPipe face detection
    /// - Returns: Tuple with (isValid, instructionMessage)
    private func validateFacePositionWithInstructions(_ detection: Detection) -> (Bool, String) {
        let boundingBox = detection.boundingBox
        
        // Check if coordinates are normalized or pixel-based
        let isNormalized = boundingBox.width <= 1.0 && boundingBox.height <= 1.0 &&
                          boundingBox.origin.x <= 1.0 && boundingBox.origin.y <= 1.0
        
        // Validate basic bounds
        guard boundingBox.width > 0 && boundingBox.height > 0 &&
              boundingBox.origin.x >= 0 && boundingBox.origin.y >= 0 else {
            return (false, "Error de detección facial - por favor inténtalo de nuevo")
        }
        
        if isNormalized {
            // Handle normalized coordinates (0.0 to 1.0)
            let faceArea = boundingBox.width * boundingBox.height
            let faceWidth = boundingBox.width
            let faceHeight = boundingBox.height
            let centerX = boundingBox.origin.x + boundingBox.width / 2
            let centerY = boundingBox.origin.y + boundingBox.height / 2
            
            // Check face size
            if faceArea < 0.08 {  // Too small (less than 8% of frame)
                return (false, "Acuércate más a la cámara")
            } else if faceArea > 0.45 {  // Too large (more than 45% of frame)
                return (false, "Aléjate de la cámara")
            }
            
            // Check horizontal position
            if centerX < 0.3 {
                return (false, "Muévete hacia la derecha")
            } else if centerX > 0.7 {
                return (false, "Muévete hacia la izquierda")
            }
            
            // Check vertical position
            if centerY < 0.25 {
                return (false, "Baja un poco")
            } else if centerY > 0.75 {
                return (false, "Sube un poco")
            }
            
            // Check if face is too wide or too tall (aspect ratio)
            let aspectRatio = faceWidth / faceHeight
            if aspectRatio < 0.6 {
                return (false, "Gira tu cara hacia la cámara")
            } else if aspectRatio > 1.4 {
                return (false, "Mira directamente a la cámara")
            }
            
            // **NEW: Check face yaw (rotation in Y-axis) - matching webcomponent behavior**
            let qualityMetrics = qualityAnalyzer.getDetailedMetrics(detection: detection)
            if !qualityMetrics.isYawOptimal {
                if qualityMetrics.faceYaw > 0 {
                    return (false, "Mira más hacia la izquierda")
                } else {
                    return (false, "Mira más hacia la derecha")
                }
            }
            
            // If all checks pass, face is in good position
            return (true, "¡Posición perfecta!")
            
        } else {
            // Handle pixel coordinates - convert to relative checks
            let videoWidth = max(videoNativeWidth, 100)  // Fallback if not set
            let videoHeight = max(videoNativeHeight, 100)
            
            let relativeArea = (boundingBox.width * boundingBox.height) / (videoWidth * videoHeight)
            let relativeCenterX = (boundingBox.origin.x + boundingBox.width / 2) / videoWidth
            let relativeCenterY = (boundingBox.origin.y + boundingBox.height / 2) / videoHeight
            
            // Check face size
            if relativeArea < 0.08 {
                return (false, "Acuércate más a la cámara")
            } else if relativeArea > 0.45 {
                return (false, "Aléjate de la cámara")
            }
            
            // Check position (similar to normalized logic)
            if relativeCenterX < 0.3 {
                return (false, "Muévete hacia la derecha")
            } else if relativeCenterX > 0.7 {
                return (false, "Muévete hacia la izquierda")
            }
            
            if relativeCenterY < 0.25 {
                return (false, "Baja un poco")
            } else if relativeCenterY > 0.75 {
                return (false, "Sube un poco")
            }
            
            // **NEW: Check face yaw (rotation in Y-axis) for pixel coordinates too**
            let qualityMetrics = qualityAnalyzer.getDetailedMetrics(detection: detection)
            if !qualityMetrics.isYawOptimal {
                if qualityMetrics.faceYaw > 0 {
                    return (false, "Mira más hacia la izquierda")
                } else {
                    return (false, "Mira más hacia la derecha")
                }
            }
            
            return (true, "¡Posición perfecta!")
        }
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
    
    /// Reset video dimensions (call when camera changes)
    func resetVideoDimensions() {
        videoNativeWidth = 0
        videoNativeHeight = 0
    }
    
    /// Reset detection state for auto recording
    func resetDetectionState() {
        consecutiveNoFaceFrames = 0
        lastFaceDetectionTime = Date()
        currentSampleBuffer = nil
    }
    
    /// Transform bounding box coordinates from MediaPipe native space to display space
    /// - Parameter boundingBox: MediaPipe bounding box in native coordinates
    /// - Returns: MediaPipe bounding box (will be transformed to display coordinates in the overlay)
    private func normalizeBoundingBox(_ boundingBox: CGRect) -> CGRect {
        // Following the web implementation pattern, we don't normalize to 0-1 here
        // Instead, we pass the MediaPipe coordinates directly to the overlay
        // The overlay will handle the coordinate transformation to display space
        
        // Always refresh video native dimensions from the current sample buffer
        if let sampleBuffer = currentSampleBuffer,
           let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let nativeWidth = CVPixelBufferGetWidth(pixelBuffer)
            let nativeHeight = CVPixelBufferGetHeight(pixelBuffer)
            
            // Update dimensions if they changed (camera switch or orientation)
            let newWidth = CGFloat(nativeWidth)
            let newHeight = CGFloat(nativeHeight)
            
            if videoNativeWidth != newWidth || videoNativeHeight != newHeight {
                videoNativeWidth = newWidth
                videoNativeHeight = newHeight
            }
        }
        
        // Return the MediaPipe coordinates as-is
        return boundingBox
    }
    
    // Store video dimensions for delegate callback
    private var videoNativeWidth: CGFloat = 0
    private var videoNativeHeight: CGFloat = 0
    
    /// Get video resolution adjusted for current orientation (like native camera app)
    private func getOrientationAdjustedVideoSize() -> CGSize {
        let minDimension = min(videoNativeWidth, videoNativeHeight)
        let maxDimension = max(videoNativeWidth, videoNativeHeight)
        let currentOrientation = UIDevice.current.orientation
        
        let adjustedSize: CGSize
        switch currentOrientation {
        case .portrait, .portraitUpsideDown:
            adjustedSize = CGSize(width: minDimension, height: maxDimension)
        case .landscapeLeft, .landscapeRight:
            adjustedSize = CGSize(width: maxDimension, height: minDimension)
        default:
            adjustedSize = CGSize(width: minDimension, height: maxDimension)
        }
        
        return adjustedSize
    }
    
    /// Update configuration
    /// - Parameter newConfiguration: new face detector configuration
    func updateConfiguration(_ newConfiguration: JAAKVisageConfiguration) {
        self.configuration = newConfiguration
    }
    
    /// Reset stability counters (useful when recording starts/stops)
    func resetStabilityCounters() {
        consecutiveValidFrames = 0
        consecutiveInvalidFrames = 0
    }
}

// MARK: - FaceDetectorLiveStreamDelegate

extension JAAKFaceDetectionEngine: FaceDetectorLiveStreamDelegate {
    func faceDetector(_ faceDetector: FaceDetector, didFinishDetection result: FaceDetectorResult?, timestampInMilliseconds: Int, error: Error?) {
        
        
        if let error = error {
            let detectorError = JAAKVisageError(
                label: "Error en la detección de flujo en vivo MediaPipe",
                code: "MEDIAPIPE_LIVE_STREAM_FAILED",
                details: error
            )
            delegate?.faceDetectionEngine(self, didFailWithError: detectorError)
            return
        }
        
        guard let result = result else {
            return
        }
        
        
        // Handle MediaPipe results with defensive error handling
        handleMediaPipeResults(result)
    }
    
    // MARK: - Detection Control
    
    /// Pause face detection (for instructions)
    func pauseDetection() {
        isDetectionPaused = true
    }
    
    /// Resume face detection (after instructions)
    func resumeDetection() {
        isDetectionPaused = false
    }
}

// MARK: - JAAKFaceDetectionEngineDelegate

protocol JAAKFaceDetectionEngineDelegate: AnyObject {
    func faceDetectionEngine(_ engine: JAAKFaceDetectionEngine, didDetectFace message: JAAKFaceDetectionMessage, boundingBox: CGRect, videoNativeSize: CGSize)
    func faceDetectionEngine(_ engine: JAAKFaceDetectionEngine, didDetectFaces detections: [Detection], sampleBuffer: CMSampleBuffer)
    func faceDetectionEngine(_ engine: JAAKFaceDetectionEngine, didFailWithError error: JAAKVisageError)
    func faceDetectionEngine(_ engine: JAAKFaceDetectionEngine, shouldCancelRecording: Bool)
}

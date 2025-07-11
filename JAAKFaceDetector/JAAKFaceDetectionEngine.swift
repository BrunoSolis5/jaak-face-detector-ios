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
    /// - Parameters:
    ///   - sampleBuffer: video frame to process
    ///   - timestamp: timestamp in milliseconds (optional, will calculate if not provided)
    func processVideoFrame(_ sampleBuffer: CMSampleBuffer, timestamp: Int? = nil) {
        print("🎬 [FaceDetectionEngine] processVideoFrame called - disableFaceDetection: \(configuration.disableFaceDetection)")
        guard !configuration.disableFaceDetection else { 
            print("⏹️ [FaceDetectionEngine] Face detection disabled in configuration")
            return 
        }
        print("🎬 [FaceDetectionEngine] Face detection enabled, checking faceDetector...")
        guard let faceDetector = faceDetector else { 
            print("❌ [FaceDetectionEngine] FaceDetector is nil - models not loaded?")
            return 
        }
        
        print("🎬 [FaceDetectionEngine] Processing video frame with loaded detector...")
        
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
            
            print("⏰ [FaceDetectionEngine] Processing frame with timestamp: \(timestampMs)ms")
            
            // Process with MediaPipe BlazeFace model in live stream mode (same as webcomponent)
            try faceDetector.detectAsync(image: mpImage, timestampInMilliseconds: timestampMs)
            
            print("📤 [FaceDetectionEngine] Frame sent for async processing")
            
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
        let bundle = Bundle(for: JAAKFaceDetectionEngine.self)
        print("🔍 [FaceDetectionEngine] Bundle path: \(bundle.bundlePath)")
        print("🔍 [FaceDetectionEngine] Bundle resource URLs: \(bundle.urls(forResourcesWithExtension: "tflite", subdirectory: nil) ?? [])")
        
        // Try multiple possible paths
        var modelPath: String?
        
        // Option 1: Direct in bundle
        modelPath = bundle.path(forResource: "blaze_face_short_range", ofType: "tflite")
        if modelPath == nil {
            // Option 2: In Models subdirectory
            modelPath = bundle.path(forResource: "blaze_face_short_range", ofType: "tflite", inDirectory: "Models")
        }
        if modelPath == nil {
            // Option 3: In JAAKFaceDetector resource bundle
            modelPath = bundle.path(forResource: "blaze_face_short_range", ofType: "tflite", inDirectory: "JAAKFaceDetector.bundle/Models")
        }
        if modelPath == nil {
            // Option 4: Try main bundle
            modelPath = Bundle.main.path(forResource: "blaze_face_short_range", ofType: "tflite")
        }
        
        guard let finalPath = modelPath else {
            throw JAAKFaceDetectorError(
                label: "MediaPipe BlazeFace model not found in any expected location",
                code: "MEDIAPIPE_MODEL_NOT_FOUND"
            )
        }
        
        print("✅ [FaceDetectionEngine] Model found at: \(finalPath)")
        
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
            
            print("✅ [FaceDetectionEngine] MediaPipe BlazeFace model loaded from: \(finalPath)")
            print("✅ [FaceDetectionEngine] FaceDetector successfully initialized")
            print("🎯 [FaceDetectionEngine] Using same model as webcomponent")
            
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
        // Safely access detections array
        let detections = result.detections
        print("🔍 [FaceDetectionEngine] Processing \(detections.count) detections")
        
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
        
        print("🔍 [FaceDetectionEngine] Processing \(detections.count) face detections safely...")
        
        // Safely access first detection with additional checks
        guard detections.count > 0 else {
            print("⚠️ [FaceDetectionEngine] Detection array is empty")
            return
        }
        
        let primaryFace = detections[0] // Use array subscript instead of .first
        print("🔍 [FaceDetectionEngine] Got primary face detection object")
        
        // Safely access Detection properties with defensive checks
        var confidence: Float = 0.0
        var isValidPosition = false
        
        print("🔍 [FaceDetectionEngine] Accessing categories array...")
        
        // Safely access categories to get confidence
        // Following MediaPipe's official pattern of checking if detections exist first
        let categories = primaryFace.categories
        print("🔍 [FaceDetectionEngine] Categories count: \(categories.count)")
        
        if categories.count > 0 {
            print("🔍 [FaceDetectionEngine] Accessing first category...")
            let firstCategory = categories[0] // Use array subscript instead of .first
            confidence = firstCategory.score
            print("🔍 [FaceDetectionEngine] Face confidence: \(confidence)")
        } else {
            print("⚠️ [FaceDetectionEngine] No categories found in detection - using default confidence")
            confidence = 0.9 // Default confidence for detected faces without categories
        }
        
        print("🔍 [FaceDetectionEngine] About to validate face position...")
        
        // Validate face position and size with defensive checks
        isValidPosition = validateFacePosition(primaryFace)
        
        print("🔍 [FaceDetectionEngine] Face position validation completed: \(isValidPosition)")
        print("🔍 [FaceDetectionEngine] Creating face detection message...")
        
        let message = JAAKFaceDetectionMessage(
            label: isValidPosition ? "Face detected in correct position" : "Face detected but repositioning needed",
            details: "Face confidence: \(confidence)",
            faceExists: true,
            correctPosition: isValidPosition
        )
        
        print("✅ [FaceDetectionEngine] Message created successfully")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("🔄 [FaceDetectionEngine] About to call delegate...")
            
            // Normalize bounding box coordinates to 0-1 range
            let normalizedBoundingBox = self.normalizeBoundingBox(primaryFace.boundingBox)
            print("🔄 [FaceDetectionEngine] Normalized bounding box: \(normalizedBoundingBox)")
            print("🔄 [FaceDetectionEngine] Calling delegate with message: \(message.label)")
            let orientationAdjustedSize = self.getOrientationAdjustedVideoSize()
            print("📐 [FaceDetectionEngine] Video size for overlay: \(orientationAdjustedSize)")
            self.delegate?.faceDetectionEngine(self, didDetectFace: message, boundingBox: normalizedBoundingBox, videoNativeSize: orientationAdjustedSize)
            print("✅ [FaceDetectionEngine] Delegate call completed")
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
            let orientationAdjustedSize = self.getOrientationAdjustedVideoSize()
            self.delegate?.faceDetectionEngine(self, didDetectFace: message, boundingBox: .zero, videoNativeSize: orientationAdjustedSize)
        }
    }
    
    private func validateFacePosition(_ detection: Detection) -> Bool {
        // Validate face size following MediaPipe's official pattern
        let boundingBox = detection.boundingBox
        
        print("🔍 [FaceDetectionEngine] Bounding box received: \(boundingBox)")
        
        // MediaPipe documentation says coordinates should be normalized [0.0, 1.0]
        // But we're seeing pixel coordinates - this might be the source of the Range crash
        
        // First, let's check if coordinates are normalized or pixel-based
        let isNormalized = boundingBox.width <= 1.0 && boundingBox.height <= 1.0 &&
                          boundingBox.origin.x <= 1.0 && boundingBox.origin.y <= 1.0
        
        print("🔍 [FaceDetectionEngine] Coordinates appear to be: \(isNormalized ? "normalized" : "pixel-based")")
        
        if isNormalized {
            // Handle normalized coordinates (0.0 to 1.0)
            guard boundingBox.width > 0 && boundingBox.height > 0 &&
                  boundingBox.origin.x >= 0 && boundingBox.origin.y >= 0 &&
                  boundingBox.width <= 1.0 && boundingBox.height <= 1.0 &&
                  boundingBox.origin.x <= 1.0 && boundingBox.origin.y <= 1.0 else {
                print("⚠️ [FaceDetectionEngine] Invalid normalized bounding box values: \(boundingBox)")
                return false
            }
            
            // For normalized coordinates, minimum 15% of frame area
            let faceArea = boundingBox.width * boundingBox.height
            let minimumFaceArea: CGFloat = 0.15 // 15% of frame area
            
            let isValidSize = faceArea >= minimumFaceArea
            print("🔍 [FaceDetectionEngine] Normalized face area: \(faceArea), valid: \(isValidSize)")
            
            return isValidSize
            
        } else {
            // Handle pixel coordinates
            guard boundingBox.width > 0 && boundingBox.height > 0 &&
                  boundingBox.origin.x >= 0 && boundingBox.origin.y >= 0 else {
                print("⚠️ [FaceDetectionEngine] Invalid pixel bounding box values: \(boundingBox)")
                return false
            }
            
            // Additional safety checks for extreme values
            guard boundingBox.width < 10000 && boundingBox.height < 10000 &&
                  boundingBox.origin.x < 10000 && boundingBox.origin.y < 10000 else {
                print("⚠️ [FaceDetectionEngine] Bounding box values too large: \(boundingBox)")
                return false
            }
            
            // For pixel coordinates, minimum 100x100 pixel face
            let faceArea = boundingBox.width * boundingBox.height
            let minimumFacePixelArea: CGFloat = 10000 // Minimum 100x100 pixel face
            
            let isValidSize = faceArea >= minimumFacePixelArea
            print("🔍 [FaceDetectionEngine] Pixel face area: \(faceArea) pixels, valid: \(isValidSize)")
            
            return isValidSize
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
    
    /// Transform bounding box coordinates from MediaPipe native space to display space
    /// - Parameter boundingBox: MediaPipe bounding box in native coordinates
    /// - Returns: MediaPipe bounding box (will be transformed to display coordinates in the overlay)
    private func normalizeBoundingBox(_ boundingBox: CGRect) -> CGRect {
        // Following the web implementation pattern, we don't normalize to 0-1 here
        // Instead, we pass the MediaPipe coordinates directly to the overlay
        // The overlay will handle the coordinate transformation to display space
        
        // Get video native dimensions from the current sample buffer
        if let sampleBuffer = currentSampleBuffer,
           let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let nativeWidth = CVPixelBufferGetWidth(pixelBuffer)
            let nativeHeight = CVPixelBufferGetHeight(pixelBuffer)
            
            // Store these dimensions for delegate callback
            videoNativeWidth = CGFloat(nativeWidth)
            videoNativeHeight = CGFloat(nativeHeight)
            
            print("📐 [FaceDetectionEngine] Video native dimensions: \(nativeWidth)x\(nativeHeight)")
        }
        
        print("📐 [FaceDetectionEngine] MediaPipe box: \(boundingBox)")
        
        // Return the MediaPipe coordinates as-is
        return boundingBox
    }
    
    // Store video dimensions for delegate callback
    private var videoNativeWidth: CGFloat = 0
    private var videoNativeHeight: CGFloat = 0
    
    /// Get video resolution adjusted for current orientation (MediaPipe pattern)
    private func getOrientationAdjustedVideoSize() -> CGSize {
        let minDimension = min(videoNativeWidth, videoNativeHeight)
        let maxDimension = max(videoNativeWidth, videoNativeHeight)
        
        switch UIDevice.current.orientation {
        case .portrait, .portraitUpsideDown:
            return CGSize(width: minDimension, height: maxDimension)
        case .landscapeLeft, .landscapeRight:
            return CGSize(width: maxDimension, height: minDimension)
        default:
            return CGSize(width: minDimension, height: maxDimension)
        }
    }
}

// MARK: - FaceDetectorLiveStreamDelegate

extension JAAKFaceDetectionEngine: FaceDetectorLiveStreamDelegate {
    func faceDetector(_ faceDetector: FaceDetector, didFinishDetection result: FaceDetectorResult?, timestampInMilliseconds: Int, error: Error?) {
        print("🎯 [FaceDetectionEngine] Live stream delegate called with timestamp: \(timestampInMilliseconds)ms")
        
        if let error = error {
            print("❌ [FaceDetectionEngine] Live stream error: \(error)")
            let detectorError = JAAKFaceDetectorError(
                label: "MediaPipe live stream detection failed",
                code: "MEDIAPIPE_LIVE_STREAM_FAILED",
                details: error
            )
            delegate?.faceDetectionEngine(self, didFailWithError: detectorError)
            return
        }
        
        guard let result = result else {
            print("⚠️ [FaceDetectionEngine] No result from live stream detection")
            return
        }
        
        print("📊 [FaceDetectionEngine] Live stream detection result: \(result.detections.count) faces found")
        
        // Handle MediaPipe results with defensive error handling
        handleMediaPipeResults(result)
    }
}

// MARK: - JAAKFaceDetectionEngineDelegate

protocol JAAKFaceDetectionEngineDelegate: AnyObject {
    func faceDetectionEngine(_ engine: JAAKFaceDetectionEngine, didDetectFace message: JAAKFaceDetectionMessage, boundingBox: CGRect, videoNativeSize: CGSize)
    func faceDetectionEngine(_ engine: JAAKFaceDetectionEngine, didDetectFaces detections: [Detection], sampleBuffer: CMSampleBuffer)
    func faceDetectionEngine(_ engine: JAAKFaceDetectionEngine, didFailWithError error: JAAKFaceDetectorError)
}

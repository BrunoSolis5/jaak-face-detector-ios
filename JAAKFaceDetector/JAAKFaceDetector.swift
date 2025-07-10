import UIKit
import AVFoundation
import Vision
import CoreML
import MediaPipeTasksVision

/// Main class for JAAKFaceDetector - AI-powered face detection and recording library
public class JAAKFaceDetectorSDK: NSObject {
    
    // MARK: - Public Properties
    
    /// Delegate for receiving events from the face detector
    public weak var delegate: JAAKFaceDetectorSDKDelegate?
    
    /// Configuration for the face detector
    public var configuration: JAAKFaceDetectorConfiguration
    
    /// Current status of the face detector
    public private(set) var status: JAAKFaceDetectorStatus = .notLoaded
    
    // MARK: - Private Properties
    
    // Core components
    private var cameraManager: JAAKCameraManager?
    private var faceDetectionEngine: JAAKFaceDetectionEngine?
    private var videoRecorder: JAAKVideoRecorder?
    private var securityMonitor: JAAKSecurityMonitor?
    private var progressiveRecorder: JAAKProgressiveRecorder?
    
    // UI Components
    private var previewView: UIView?
    private var faceTrackingOverlay: JAAKFaceTrackingOverlay?
    private var recordingTimer: JAAKRecordingTimer?
    private var instructionView: JAAKInstructionView?
    private var instructionController: JAAKInstructionController?
    
    // MARK: - Initialization
    
    /// Initialize JAAKFaceDetector with configuration
    /// - Parameter configuration: Configuration object for the detector
    public init(configuration: JAAKFaceDetectorConfiguration) {
        self.configuration = configuration
        super.init()
        
        setupComponents()
    }
    
    // MARK: - Public Methods - Component Lifecycle
    
    /// Start face detection
    /// - Throws: JAAKFaceDetectorError if unable to start
    public func startDetection() throws {
        updateStatus(.loading)
        
        // Check permissions first
        try checkPermissions()
        
        do {
            // Setup camera
            guard let cameraManager = cameraManager else {
                throw JAAKFaceDetectorError(label: "Camera manager not initialized", code: "CAMERA_MANAGER_NIL")
            }
            try cameraManager.setupCaptureSession(with: configuration)
            
            // Load models
            try loadModels()
            
            // Start camera
            print("🎥 [FaceDetectorSDK] About to start camera session...")
            cameraManager.startSession()
            print("🎥 [FaceDetectorSDK] Camera session start command sent")
            
            // Start security monitoring
            securityMonitor?.startMonitoring()
            
            // Show initial instructions
            instructionController?.startInstructions()
            
            // Start progressive recording if enabled
            if configuration.progressiveAutoRecorder {
                progressiveRecorder?.startProgressiveRecording()
            }
            
            updateStatus(.running)
        } catch {
            let detectorError = JAAKFaceDetectorError(
                label: "Failed to start detection",
                code: "START_DETECTION_FAILED",
                details: error
            )
            updateStatus(.error)
            delegate?.faceDetector(self, didEncounterError: detectorError)
            throw detectorError
        }
    }
    
    /// Stop face detection
    public func stopDetection() {
        cameraManager?.stopSession()
        securityMonitor?.stopMonitoring()
        instructionController?.hideInstructions()
        progressiveRecorder?.stopProgressiveRecording()
        updateStatus(.stopped)
    }
    
    /// Restart face detection
    /// - Throws: JAAKFaceDetectorError if unable to restart
    public func restartDetection() throws {
        stopDetection()
        try startDetection()
    }
    
    /// Reset the detector
    /// - Parameter hardReset: If true, performs a complete reset including model reloading
    /// - Throws: JAAKFaceDetectorError if unable to reset
    public func resetDetector(hardReset: Bool = false) throws {
        stopDetection()
        
        if hardReset {
            setupComponents()
        }
        
        updateStatus(.notLoaded)
    }
    
    // MARK: - Public Methods - Recording Operations
    
    /// Record video with face detection
    /// - Parameter completion: Completion handler with result
    public func recordVideo(completion: @escaping (Result<JAAKFileResult, JAAKFaceDetectorError>) -> Void) {
        guard status == .running else {
            let error = JAAKFaceDetectorError(
                label: "Cannot record video - detector not running",
                code: "INVALID_STATE"
            )
            completion(.failure(error))
            return
        }
        
        guard let videoRecorder = videoRecorder, let cameraManager = cameraManager else {
            let error = JAAKFaceDetectorError(
                label: "Video recorder not available",
                code: "VIDEO_RECORDER_NIL"
            )
            completion(.failure(error))
            return
        }
        
        videoRecorder.startRecording(with: cameraManager, completion: completion)
    }
    
    /// Take a snapshot
    /// - Parameter completion: Completion handler with result
    public func takeSnapshot(completion: @escaping (Result<JAAKFileResult, JAAKFaceDetectorError>) -> Void) {
        guard status == .running else {
            let error = JAAKFaceDetectorError(
                label: "Cannot take snapshot - detector not running",
                code: "INVALID_STATE"
            )
            completion(.failure(error))
            return
        }
        
        updateStatus(.snapshotting)
        
        // TODO: Implement snapshot logic
        // This is a placeholder - actual implementation will be added in next phases
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let mockResult = JAAKFileResult(
                data: Data(),
                base64: "",
                mimeType: "image/jpeg",
                fileName: "snapshot.jpg",
                fileSize: 0
            )
            self.updateStatus(.running)
            completion(.success(mockResult))
        }
    }
    
    // MARK: - Public Methods - Stream Management
    
    /// Get camera preview layer
    /// - Returns: AVCaptureVideoPreviewLayer or nil if not available
    public func getCameraPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        guard let session = cameraManager?.getCaptureSession() else { return nil }
        return AVCaptureVideoPreviewLayer(session: session)
    }
    
    /// Get capture session
    /// - Returns: AVCaptureSession or nil if not available
    public func getCaptureSession() -> AVCaptureSession? {
        return cameraManager?.getCaptureSession()
    }
    
    /// Toggle between front and back camera
    /// - Throws: JAAKFaceDetectorError if unable to toggle
    public func toggleCamera() throws {
        guard let cameraManager = cameraManager else {
            throw JAAKFaceDetectorError(
                label: "Camera manager not available",
                code: "CAMERA_MANAGER_NIL"
            )
        }
        
        let newPosition: AVCaptureDevice.Position = (configuration.cameraPosition == .back) ? .front : .back
        configuration.cameraPosition = newPosition
        
        try cameraManager.toggleCamera(to: newPosition, configuration: configuration)
    }
    
    /// Stop video stream
    public func stopVideoStream() {
        cameraManager?.stopSession()
    }
    
    /// Start video stream
    /// - Throws: JAAKFaceDetectorError if unable to start
    public func startVideoStream() throws {
        guard let cameraManager = cameraManager else {
            throw JAAKFaceDetectorError(
                label: "Camera manager not available",
                code: "CAMERA_MANAGER_NIL"
            )
        }
        
        cameraManager.startSession()
    }
    
    // MARK: - Public Methods - Model Loading
    
    /// Load AI models for face detection
    /// - Throws: JAAKFaceDetectorError if unable to load models
    public func loadModels() throws {
        print("🔧 [FaceDetectorSDK] Starting model loading...")
        updateStatus(.loading)
        
        guard let faceDetectionEngine = faceDetectionEngine else {
            print("❌ [FaceDetectorSDK] FaceDetectionEngine is nil")
            throw JAAKFaceDetectorError(label: "Face detection engine not initialized", code: "FACE_ENGINE_NIL")
        }
        
        print("🔧 [FaceDetectorSDK] Calling faceDetectionEngine.loadModels()...")
        try faceDetectionEngine.loadModels()
        print("✅ [FaceDetectorSDK] Models loaded successfully")
        
        updateStatus(.loaded)
    }
    
    // MARK: - Public Methods - UI Components
    
    /// Create preview view for camera feed
    /// - Returns: UIView containing camera preview
    public func createPreviewView() -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        // Add camera preview layer
        if let previewLayer = getCameraPreviewLayer() {
            previewLayer.frame = view.bounds
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
        }
        
        // Add face tracking overlay
        if let faceTrackingOverlay = faceTrackingOverlay {
            faceTrackingOverlay.frame = view.bounds
            faceTrackingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(faceTrackingOverlay)
        }
        
        // Add recording timer
        if let recordingTimer = recordingTimer {
            let timerSize = recordingTimer.intrinsicContentSize
            let position = configuration.timerStyles.position
            
            recordingTimer.frame = CGRect(
                x: view.bounds.width * position.x - timerSize.width / 2,
                y: view.bounds.height * position.y - timerSize.height / 2,
                width: timerSize.width,
                height: timerSize.height
            )
            
            view.addSubview(recordingTimer)
        }
        
        // Add instruction view
        if let instructionView = instructionView {
            instructionView.frame = CGRect(
                x: 20,
                y: view.bounds.height - 200,
                width: view.bounds.width - 40,
                height: 180
            )
            instructionView.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
            view.addSubview(instructionView)
        }
        
        previewView = view
        return view
    }
    
    /// Create controls view for detector controls
    /// - Returns: UIView containing control buttons
    public func createControlsView() -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        // TODO: Add control buttons (record, snapshot, toggle camera, etc.)
        // This is a placeholder - actual implementation will be added in next phases
        
        return view
    }
    
    // MARK: - Private Methods
    
    private func setupComponents() {
        print("🔧 [FaceDetectorSDK] Setting up components...")
        
        // Initialize core components
        cameraManager = JAAKCameraManager()
        cameraManager?.delegate = self
        print("✅ [FaceDetectorSDK] CameraManager initialized")
        
        faceDetectionEngine = JAAKFaceDetectionEngine(configuration: configuration)
        faceDetectionEngine?.delegate = self
        print("✅ [FaceDetectorSDK] FaceDetectionEngine initialized")
        
        videoRecorder = JAAKVideoRecorder(configuration: configuration)
        videoRecorder?.delegate = self
        
        // Initialize security monitor
        securityMonitor = JAAKSecurityMonitor(configuration: configuration)
        securityMonitor?.delegate = self
        
        // Initialize progressive recorder
        if let videoRecorder = videoRecorder, let cameraManager = cameraManager {
            progressiveRecorder = JAAKProgressiveRecorder(
                configuration: configuration,
                videoRecorder: videoRecorder,
                cameraManager: cameraManager
            )
            progressiveRecorder?.delegate = self
        }
        
        // Initialize UI components
        if !configuration.hideFaceTracker {
            faceTrackingOverlay = JAAKFaceTrackingOverlay(configuration: configuration.faceTrackerStyles)
        }
        
        if !configuration.hideTimer {
            recordingTimer = JAAKRecordingTimer(configuration: configuration.timerStyles)
        }
        
        // Initialize instruction components
        if configuration.enableInstructions {
            print("📋 [FaceDetectorSDK] Creating instruction view (enableInstructions = true)")
            instructionView = JAAKInstructionView(configuration: configuration)
            instructionController = JAAKInstructionController(configuration: configuration, instructionView: instructionView!)
            instructionController?.delegate = self
        } else {
            print("📋 [FaceDetectorSDK] Skipping instruction view (enableInstructions = false)")
        }
    }
    
    private func checkPermissions() throws {
        // Check camera permission
        if !JAAKPermissionManager.isCameraAuthorized() {
            throw JAAKFaceDetectorError(
                label: "Camera permission not granted",
                code: "CAMERA_PERMISSION_DENIED"
            )
        }
        
        // Check microphone permission if needed
        if configuration.enableMicrophone && !JAAKPermissionManager.isMicrophoneAuthorized() {
            throw JAAKFaceDetectorError(
                label: "Microphone permission not granted",
                code: "MICROPHONE_PERMISSION_DENIED"
            )
        }
    }
    
    private func updateStatus(_ newStatus: JAAKFaceDetectorStatus) {
        status = newStatus
        
        // Notify instruction controller of status change
        instructionController?.handleStatusChange(newStatus)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.faceDetector(self, didUpdateStatus: newStatus)
        }
    }
}

// MARK: - JAAKCameraManagerDelegate

extension JAAKFaceDetectorSDK: JAAKCameraManagerDelegate {
    func cameraManager(_ manager: JAAKCameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        // Process frame for face detection
        print("📹 [FaceDetectorSDK] Received frame from camera, forwarding to face detection engine")
        faceDetectionEngine?.processVideoFrame(sampleBuffer)
    }
    
    func cameraManager(_ manager: JAAKCameraManager, didFinishRecordingTo outputURL: URL) {
        videoRecorder?.handleRecordingCompletion(outputURL)
    }
    
    func cameraManager(_ manager: JAAKCameraManager, didFailWithError error: JAAKFaceDetectorError) {
        delegate?.faceDetector(self, didEncounterError: error)
    }
}

// MARK: - JAAKFaceDetectionEngineDelegate

extension JAAKFaceDetectorSDK: JAAKFaceDetectionEngineDelegate {
    func faceDetectionEngine(_ engine: JAAKFaceDetectionEngine, didDetectFace message: JAAKFaceDetectionMessage, boundingBox: CGRect) {
        print("🎯 [FaceDetectorSDK] Face detection delegate called: \(message.label)")
        
        // Update face tracking overlay
        faceTrackingOverlay?.updateFaceFrame(boundingBox)
        faceTrackingOverlay?.setValidationState(message.correctPosition)
        
        // Handle auto-recording
        if configuration.autoRecorder && message.faceExists && message.correctPosition && status == .running {
            if let videoRecorder = videoRecorder, !videoRecorder.isRecording(), cameraManager != nil {
                recordVideo { result in
                    switch result {
                    case .success(let fileResult):
                        self.delegate?.faceDetector(self, didCaptureFile: fileResult)
                    case .failure(let error):
                        self.delegate?.faceDetector(self, didEncounterError: error)
                    }
                }
            }
        }
        
        // Update instruction controller with face detection message
        instructionController?.handleFaceDetectionMessage(message)
        
        // Forward to delegate
        delegate?.faceDetector(self, didDetectFace: message)
    }
    
    func faceDetectionEngine(_ engine: JAAKFaceDetectionEngine, didDetectFaces detections: [Detection], sampleBuffer: CMSampleBuffer) {
        // Process faces for progressive recording
        progressiveRecorder?.processFaceDetectionResults(detections, sampleBuffer: sampleBuffer)
    }
    
    func faceDetectionEngine(_ engine: JAAKFaceDetectionEngine, didFailWithError error: JAAKFaceDetectorError) {
        instructionController?.handleError(error)
        delegate?.faceDetector(self, didEncounterError: error)
    }
}

// MARK: - JAAKVideoRecorderDelegate

extension JAAKFaceDetectorSDK: JAAKVideoRecorderDelegate {
    func videoRecorder(_ recorder: JAAKVideoRecorder, didStartRecording outputURL: URL) {
        updateStatus(.recording)
        recordingTimer?.startTimer(duration: configuration.videoDuration)
    }
    
    func videoRecorder(_ recorder: JAAKVideoRecorder, didUpdateProgress progress: Float) {
        recordingTimer?.updateProgress(progress)
    }
    
    func videoRecorder(_ recorder: JAAKVideoRecorder, didFinishRecording fileResult: JAAKFileResult) {
        updateStatus(.finished)
        recordingTimer?.stopTimer()
        delegate?.faceDetector(self, didCaptureFile: fileResult)
    }
    
    func videoRecorder(_ recorder: JAAKVideoRecorder, didFailWithError error: JAAKFaceDetectorError) {
        updateStatus(.error)
        recordingTimer?.stopTimer()
        delegate?.faceDetector(self, didEncounterError: error)
    }
}

// MARK: - JAAKSecurityMonitorDelegate

extension JAAKFaceDetectorSDK: JAAKSecurityMonitorDelegate {
    func securityMonitor(_ monitor: JAAKSecurityMonitor, didDetectEvent event: JAAKSecurityEvent) {
        // Handle security events based on severity
        switch event.severity {
        case .critical, .high:
            // Stop detection for critical security issues
            stopDetection()
            
            let error = JAAKFaceDetectorError(
                label: "Security threat detected: \(event.description)",
                code: "SECURITY_THREAT",
                details: event
            )
            updateStatus(.error)
            delegate?.faceDetector(self, didEncounterError: error)
            
        case .medium:
            // Log medium severity events but continue operation
            let error = JAAKFaceDetectorError(
                label: "Security warning: \(event.description)",
                code: "SECURITY_WARNING",
                details: event
            )
            delegate?.faceDetector(self, didEncounterError: error)
            
        case .low:
            // Low severity events are informational only
            break
        }
    }
}

// MARK: - JAAKInstructionControllerDelegate

extension JAAKFaceDetectorSDK: JAAKInstructionControllerDelegate {
    func instructionController(_ controller: JAAKInstructionController, didCompleteInstructions completed: Bool) {
        // Instructions completed - user can now proceed with detection
        if completed {
            // Optional: Start auto-recording if configured
            if configuration.autoRecorder && status == .running {
                // Auto-recording logic would be handled by face detection engine
            }
        }
    }
}

// MARK: - JAAKProgressiveRecorderDelegate

extension JAAKFaceDetectorSDK: JAAKProgressiveRecorderDelegate {
    func progressiveRecorder(_ recorder: JAAKProgressiveRecorder, didStartSession session: JAAKProgressiveRecorder.RecordingSession) {
        // Progressive recording session started
        instructionController?.forceShowInstruction(.recordingStarted)
    }
    
    func progressiveRecorder(_ recorder: JAAKProgressiveRecorder, didStartAttempt attempt: JAAKProgressiveRecorder.RecordingAttempt) {
        // New recording attempt started
        updateStatus(.recording)
        recordingTimer?.startTimer(duration: configuration.videoDuration)
        
        // Show attempt-specific instruction
        let instruction = getInstructionForAttempt(attempt)
        instructionController?.forceShowInstruction(instruction)
    }
    
    func progressiveRecorder(_ recorder: JAAKProgressiveRecorder, didCompleteAttempt attempt: JAAKProgressiveRecorder.RecordingAttempt) {
        // Recording attempt completed
        updateStatus(.running)
        recordingTimer?.stopTimer()
        
        if attempt.meetsCriteria {
            // Good quality attempt
            instructionController?.forceShowInstruction(.recordingCompleted)
        } else {
            // Poor quality, will try again
            let instruction = getImprovementInstructionForAttempt(attempt)
            instructionController?.forceShowInstruction(instruction)
        }
    }
    
    func progressiveRecorder(_ recorder: JAAKProgressiveRecorder, didFailAttempt attempt: JAAKProgressiveRecorder.RecordingAttempt, error: JAAKFaceDetectorError) {
        // Recording attempt failed
        updateStatus(.error)
        recordingTimer?.stopTimer()
        instructionController?.handleError(error)
        delegate?.faceDetector(self, didEncounterError: error)
    }
    
    func progressiveRecorder(_ recorder: JAAKProgressiveRecorder, willStartNextAttempt attemptNumber: Int) {
        // Preparing for next attempt
        let message = "Preparing for attempt \(attemptNumber)..."
        instructionController?.forceShowInstruction(.error(message))
    }
    
    func progressiveRecorder(_ recorder: JAAKProgressiveRecorder, didCompleteSession session: JAAKProgressiveRecorder.RecordingSession) {
        // Progressive recording session completed
        updateStatus(.finished)
        instructionController?.forceShowInstruction(.recordingCompleted)
    }
    
    func progressiveRecorder(_ recorder: JAAKProgressiveRecorder, didProduceBestResult fileResult: JAAKFileResult, from session: JAAKProgressiveRecorder.RecordingSession) {
        // Best result from progressive recording session
        updateStatus(.finished)
        delegate?.faceDetector(self, didCaptureFile: fileResult)
    }
    
    // MARK: - Helper Methods
    
    private func getInstructionForAttempt(_ attempt: JAAKProgressiveRecorder.RecordingAttempt) -> JAAKInstructionController.InstructionTrigger {
        switch attempt.attemptNumber {
        case 1:
            return .recordingStarted
        case 2:
            return .faceDetected
        case 3:
            return .faceDetected
        default:
            return .recordingStarted
        }
    }
    
    private func getImprovementInstructionForAttempt(_ attempt: JAAKProgressiveRecorder.RecordingAttempt) -> JAAKInstructionController.InstructionTrigger {
        // Provide specific feedback based on what needs improvement
        if attempt.faceSize < 0.15 {
            return .faceTooFar
        } else if attempt.faceSize > 0.30 {
            return .faceToClose
        } else if attempt.faceConfidence < 0.8 {
            return .faceNotCentered
        } else {
            return .faceNotStill
        }
    }
}

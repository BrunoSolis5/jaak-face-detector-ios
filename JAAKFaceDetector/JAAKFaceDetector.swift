import UIKit
import AVFoundation
import MediaPipeTasksVision

/// Main class for JAAKFaceDetector - AI-powered face detection and recording library
public class JAAKFaceDetectorSDK: NSObject {
    
    // MARK: - Public Properties
    
    /// Delegate for receiving events from the face detector
    public weak var delegate: JAAKFaceDetectorSDKDelegate?
    
    /// Configuration for the face detector
    public var configuration: JAAKFaceDetectorConfiguration {
        didSet {
            // When configuration changes, update components if needed
            updateComponentsWithNewConfiguration()
        }
    }
    
    /// Current status of the face detector
    public private(set) var status: JAAKFaceDetectorStatus = .notLoaded
    
    // MARK: - Private Properties
    
    // Core components
    private var cameraManager: JAAKCameraManager?
    private var faceDetectionEngine: JAAKFaceDetectionEngine?
    private var videoRecorder: JAAKVideoRecorder?
    private var securityMonitor: JAAKSecurityMonitor?
    private var progressiveRecorder: JAAKProgressiveRecorder?
    
    // Background processing queue like MediaPipe example
    private let backgroundQueue = DispatchQueue(label: "ai.jaak.facedetector.backgroundQueue", qos: .userInitiated)
    
    // UI Components
    private var previewView: UIView?
    private var faceTrackingOverlay: JAAKFaceTrackingOverlay?
    private var recordingTimer: JAAKRecordingTimer?
    private var instructionView: JAAKInstructionView?
    private var instructionController: JAAKInstructionController?
    private var validationMessageView: JAAKValidationMessageView?
    private var helpButton: UIButton?
    
    
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
            // Setup camera only if not already set up
            guard let cameraManager = cameraManager else {
                throw JAAKFaceDetectorError(label: "Camera manager not initialized", code: "CAMERA_MANAGER_NIL")
            }
            
            // Check if session is already configured
            let captureSession = cameraManager.getCaptureSession()
            if captureSession.inputs.isEmpty {
                print("🔧 [FaceDetectorSDK] Camera session not configured, setting up...")
                try cameraManager.setupCaptureSession(with: configuration)
            } else {
                print("✅ [FaceDetectorSDK] Camera session already configured, skipping setup")
            }
            
            // Load models if not already loaded
            if status != .loaded {
                try loadModels()
            } else {
                print("✅ [FaceDetectorSDK] Models already loaded, skipping...")
            }
            
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
    
    /// Stop current video recording
    public func stopRecording() {
        guard let videoRecorder = videoRecorder, let cameraManager = cameraManager else { return }
        guard videoRecorder.isRecording() else { return }
        
        print("⏹️ [FaceDetectorSDK] Stopping video recording")
        videoRecorder.stopRecording(with: cameraManager)
        
        // Stop the timer
        recordingTimer?.stopTimer()
        
        // Reset status if we were recording
        if status == .recording {
            updateStatus(.running)
        }
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
        
        // Get current video frame from camera manager and convert to image
        guard let cameraManager = cameraManager else {
            let error = JAAKFaceDetectorError(
                label: "Camera manager not available",
                code: "CAMERA_MANAGER_NIL"
            )
            updateStatus(.running)
            completion(.failure(error))
            return
        }
        
        // Request snapshot from camera manager
        cameraManager.captureStillImage { [weak self] result in
            DispatchQueue.main.async {
                self?.updateStatus(.running)
                
                switch result {
                case .success(let imageData):
                    // Create timestamp-based filename
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyyMMdd_HHmmss"
                    let fileName = "snapshot_\(formatter.string(from: Date())).jpg"
                    
                    // Create base64 string
                    let base64String = imageData.base64EncodedString()
                    
                    let fileResult = JAAKFileResult(
                        data: imageData,
                        base64: base64String,
                        mimeType: "image/jpeg",
                        fileName: fileName,
                        fileSize: imageData.count
                    )
                    
                    print("📸 [FaceDetectorSDK] Snapshot captured: \(fileName), size: \(imageData.count) bytes")
                    completion(.success(fileResult))
                    
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Public Methods - Stream Management
    
    /// Get camera preview layer
    /// - Returns: AVCaptureVideoPreviewLayer or nil if not available
    public func getCameraPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        guard let session = cameraManager?.getCaptureSession() else { return nil }
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        
        // Configure preview layer to auto-adjust to device orientation
        previewLayer.videoGravity = .resizeAspectFill
        
        // Set initial orientation based on current device orientation
        updatePreviewLayerOrientation(previewLayer)
        
        return previewLayer
    }
    
    /// Update preview layer orientation based on device orientation
    private func updatePreviewLayerOrientation(_ previewLayer: AVCaptureVideoPreviewLayer) {
        guard let connection = previewLayer.connection, connection.isVideoOrientationSupported else { return }
        
        let currentOrientation = UIDevice.current.orientation
        let videoOrientation: AVCaptureVideoOrientation
        
        switch currentOrientation {
        case .portrait:
            videoOrientation = .portrait
        case .portraitUpsideDown:
            videoOrientation = .portraitUpsideDown
        case .landscapeLeft:
            videoOrientation = .landscapeRight  // Camera is rotated 180° relative to device
        case .landscapeRight:
            videoOrientation = .landscapeLeft   // Camera is rotated 180° relative to device
        default:
            videoOrientation = .portrait
        }
        
        connection.videoOrientation = videoOrientation
        print("🔄 [JAAKFaceDetector] Preview orientation updated to: \(videoOrientation.rawValue)")
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
        
        // Reset video dimensions and clear overlay detections when camera changes
        faceDetectionEngine?.resetVideoDimensions()
        DispatchQueue.main.async {
            self.faceTrackingOverlay?.clearDetections()
        }
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
        let view = CameraPreviewView()
        view.backgroundColor = .black
        
        // Setup camera session first to ensure preview layer can be created
        if cameraManager == nil {
            cameraManager = JAAKCameraManager()
            cameraManager?.delegate = self
        }
        
        do {
            try cameraManager?.setupCaptureSession(with: configuration)
            
            // Load models to ensure face detection is ready
            try loadModels()
            
            cameraManager?.startSession()
            print("✅ [JAAKFaceDetector] Camera session setup, models loaded, and session started for preview")
        } catch {
            print("❌ [JAAKFaceDetector] Failed to setup camera session for preview: \(error)")
        }
        
        // Add camera preview layer
        if let previewLayer = getCameraPreviewLayer() {
            // Set initial frame - will be updated in layoutSubviews
            previewLayer.frame = view.bounds
            previewLayer.videoGravity = .resizeAspect
            view.layer.addSublayer(previewLayer)
            
            print("✅ [JAAKFaceDetector] Preview layer added to view with frame: \(view.bounds)")
        } else {
            print("❌ [JAAKFaceDetector] Failed to get camera preview layer")
        }
        
        // Add face tracking overlay
        if let faceTrackingOverlay = faceTrackingOverlay {
            faceTrackingOverlay.frame = view.bounds
            faceTrackingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(faceTrackingOverlay)
            print("✅ [JAAKFaceDetector] Face tracking overlay added to view with frame: \(view.bounds)")
        } else {
            print("⚠️ [JAAKFaceDetector] Face tracking overlay is nil, not adding to view")
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
            print("✅ [JAAKFaceDetector] Recording timer added to view with frame: \(recordingTimer.frame)")
        } else {
            print("⚠️ [JAAKFaceDetector] Recording timer is nil, not adding to view")
        }
        
        // Add instruction view (for initial tutorial-style instructions)
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
        
        // Add validation message view (for positioning guidance)
        if let validationMessageView = validationMessageView {
            validationMessageView.frame = CGRect(
                x: 20,
                y: 50,
                width: view.bounds.width - 40,
                height: 50
            )
            validationMessageView.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
            view.addSubview(validationMessageView)
        }
        
        // Add help button
        if let helpButton = helpButton {
            helpButton.frame = CGRect(
                x: view.bounds.width - 60,
                y: 20,
                width: 40,
                height: 40
            )
            helpButton.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
            
            // Ensure the button is on top of other views and has proper touch handling
            view.addSubview(helpButton)
            view.bringSubviewToFront(helpButton)
            
            print("✅ [FaceDetectorSDK] Help button added at frame: \(helpButton.frame)")
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
            print("✅ [FaceDetectorSDK] Face tracking overlay created")
        } else {
            print("⚠️ [FaceDetectorSDK] Face tracking overlay hidden by configuration")
        }
        
        if !configuration.hideTimer {
            recordingTimer = JAAKRecordingTimer(configuration: configuration.timerStyles)
            print("✅ [FaceDetectorSDK] Recording timer created: \(String(describing: recordingTimer))")
        } else {
            print("⚠️ [FaceDetectorSDK] Recording timer hidden by configuration")
        }
        
        // Initialize instruction components (tutorial-style instructions)
        if configuration.enableInstructions {
            print("📋 [FaceDetectorSDK] Creating instruction view (enableInstructions = true)")
            instructionView = JAAKInstructionView(configuration: configuration)
            instructionController = JAAKInstructionController(configuration: configuration, instructionView: instructionView!)
            instructionController?.delegate = self
        } else {
            print("📋 [FaceDetectorSDK] Skipping instruction view (enableInstructions = false)")
        }
        
        // Always create validation message view (for positioning guidance)
        validationMessageView = JAAKValidationMessageView()
        print("✅ [FaceDetectorSDK] Validation message view created")
        
        // Create help button to reactivate instructions
        helpButton = HelpButton()
        helpButton?.setTitle("?", for: .normal)
        helpButton?.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        helpButton?.setTitleColor(.white, for: .normal)
        helpButton?.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        helpButton?.layer.cornerRadius = 20
        helpButton?.clipsToBounds = true
        helpButton?.isUserInteractionEnabled = true
        helpButton?.addTarget(self, action: #selector(helpButtonTapped), for: .touchUpInside)
        print("✅ [FaceDetectorSDK] Help button created")
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
        // Process frame for face detection directly (MediaPipe handles its own threading)
        print("📹 [FaceDetectorSDK] Received frame from camera, processing for face detection")
        let currentTimeMs = Date().timeIntervalSince1970 * 1000
        
        // Process on main thread to avoid Sendable issues with CMSampleBuffer
        faceDetectionEngine?.processVideoFrame(sampleBuffer, timestamp: Int(currentTimeMs))
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
    func faceDetectionEngine(_ engine: JAAKFaceDetectionEngine, didDetectFace message: JAAKFaceDetectionMessage, boundingBox: CGRect, videoNativeSize: CGSize) {
        print("🎯 [FaceDetectorSDK] Face detection delegate called: \(message.label)")
        
        // Update overlay with image dimensions
        faceTrackingOverlay?.setImageDimensions(width: videoNativeSize.width, height: videoNativeSize.height)
        
        // Update face tracking overlay following MediaPipe pattern
        if message.faceExists && !boundingBox.isEmpty {
            let confidence: Float = 0.9 // Default confidence, can be extracted from MediaPipe detection
            faceTrackingOverlay?.updateFaceDetection(
                boundingBox: boundingBox,
                isValid: message.correctPosition,
                confidence: confidence
            )
            print("👤 [FaceDetectorSDK] Face tracking overlay updated and shown")
        } else {
            // Clear detections when no face is detected
            faceTrackingOverlay?.clearDetections()
            faceTrackingOverlay?.notifyNoFaceDetected()
            print("👤 [FaceDetectorSDK] No face detected (faceExists: \(message.faceExists), boundingBox: \(boundingBox)), overlay cleared")
        }
        
        // Handle auto-recording with detailed debugging
        print("🔍 [AutoRecorder Debug] autoRecorder: \(configuration.autoRecorder), status: \(status), faceExists: \(message.faceExists), correctPosition: \(message.correctPosition)")
        
        if configuration.autoRecorder && (status == .running || status == .recording) {
            if message.faceExists && message.correctPosition {
                // Start recording if not already recording
                if let videoRecorder = videoRecorder, !videoRecorder.isRecording(), cameraManager != nil {
                    print("🎬 [FaceDetectorSDK] Auto-recording triggered - starting video recording")
                    recordVideo { result in
                        switch result {
                        case .success(let fileResult):
                            self.delegate?.faceDetector(self, didCaptureFile: fileResult)
                        case .failure(let error):
                            self.delegate?.faceDetector(self, didEncounterError: error)
                        }
                    }
                } else {
                    print("❌ [AutoRecorder Debug] Cannot start recording - videoRecorder: \(videoRecorder != nil), isRecording: \(videoRecorder?.isRecording() ?? false), cameraManager: \(cameraManager != nil)")
                }
            } else {
                // Cancel recording if face is lost during recording
                if let videoRecorder = videoRecorder, videoRecorder.isRecording() {
                    print("❌ [FaceDetectorSDK] Face lost during auto-recording - canceling recording")
                    stopRecording()
                    updateStatus(.running) // Reset status back to running (not finished)
                    
                    // Notify that recording was canceled
                    let cancelError = JAAKFaceDetectorError(
                        label: "Auto-recording canceled - face detection lost", 
                        code: "AUTO_RECORDING_CANCELED"
                    )
                    delegate?.faceDetector(self, didEncounterError: cancelError)
                }
            }
        }
        
        // Show validation message (always shown for positioning guidance)
        DispatchQueue.main.async { [weak self] in
            self?.validationMessageView?.showMessage(message.label)
        }
        
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
        print("🎬 [FaceDetectorSDK] Video recorder started, starting timer with duration: \(configuration.videoDuration)")
        updateStatus(.recording)
        recordingTimer?.startTimer(duration: configuration.videoDuration)
        print("🎬 [FaceDetectorSDK] Timer start command sent to recordingTimer: \(String(describing: recordingTimer))")
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
    
    private func updateComponentsWithNewConfiguration() {
        print("🔧 [FaceDetectorSDK] Configuration changed, updating components...")
        
        // Update UI components with new configuration
        if let recordingTimer = recordingTimer {
            recordingTimer.updateConfiguration(configuration.timerStyles)
        }
        
        if let faceTrackingOverlay = faceTrackingOverlay {
            faceTrackingOverlay.updateConfiguration(configuration.faceTrackerStyles)
        }
        
        // Update other components as needed
        faceDetectionEngine?.updateConfiguration(configuration)
        videoRecorder?.updateConfiguration(configuration)
        progressiveRecorder?.updateConfiguration(configuration)
        instructionController?.updateConfiguration(configuration)
        
        print("✅ [FaceDetectorSDK] Components updated with new configuration")
    }
    
    /// Update configuration without recreating the entire SDK
    /// - Parameter newConfiguration: The new configuration to apply
    public func updateConfiguration(_ newConfiguration: JAAKFaceDetectorConfiguration) {
        let oldConfiguration = self.configuration
        
        // Check if changes require restart
        let requiresRestart = configurationRequiresRestart(from: oldConfiguration, to: newConfiguration)
        
        if requiresRestart {
            print("🔄 [FaceDetectorSDK] Configuration changes require restart")
            let wasRunning = (status == .running)
            
            if wasRunning {
                stopDetection()
            }
            
            self.configuration = newConfiguration
            
            if wasRunning {
                do {
                    try startDetection()
                } catch {
                    delegate?.faceDetector(self, didEncounterError: error as? JAAKFaceDetectorError ?? JAAKFaceDetectorError(label: "Failed to restart after configuration update", code: "CONFIG_UPDATE_RESTART_FAILED"))
                }
            }
        } else {
            print("✅ [FaceDetectorSDK] Applying configuration changes dynamically")
            // Apply dynamic changes without restart
            self.configuration = newConfiguration
            applyDynamicConfigurationChanges(from: oldConfiguration, to: newConfiguration)
        }
    }
    
    /// Check if configuration changes require a full restart
    private func configurationRequiresRestart(from oldConfig: JAAKFaceDetectorConfiguration, to newConfig: JAAKFaceDetectorConfiguration) -> Bool {
        // These changes require restart
        return oldConfig.enableMicrophone != newConfig.enableMicrophone ||
               oldConfig.cameraPosition != newConfig.cameraPosition ||
               oldConfig.videoQuality != newConfig.videoQuality ||
               oldConfig.disableFaceDetection != newConfig.disableFaceDetection ||
               oldConfig.useOfflineModel != newConfig.useOfflineModel
    }
    
    /// Apply configuration changes that can be done dynamically
    private func applyDynamicConfigurationChanges(from oldConfig: JAAKFaceDetectorConfiguration, to newConfig: JAAKFaceDetectorConfiguration) {
        
        // Update UI components that can change dynamically
        if oldConfig.hideFaceTracker != newConfig.hideFaceTracker {
            updateFaceTrackerVisibility(hidden: newConfig.hideFaceTracker)
        }
        
        if oldConfig.hideTimer != newConfig.hideTimer {
            updateTimerVisibility(hidden: newConfig.hideTimer)
        }
        
        if oldConfig.muteFaceDetectionMessages != newConfig.muteFaceDetectionMessages {
            // This just affects internal message handling, no UI changes needed
            print("📢 [FaceDetectorSDK] Face detection messages mute status: \(newConfig.muteFaceDetectionMessages)")
        }
        
        // Update timer styles if they changed
        if !timerStylesMatch(oldConfig.timerStyles, newConfig.timerStyles) {
            recordingTimer?.updateConfiguration(newConfig.timerStyles)
        }
        
        // Update face tracker styles if they changed
        if !faceTrackerStylesMatch(oldConfig.faceTrackerStyles, newConfig.faceTrackerStyles) {
            faceTrackingOverlay?.updateConfiguration(newConfig.faceTrackerStyles)
        }
        
        // Update recording settings
        if oldConfig.videoDuration != newConfig.videoDuration ||
           oldConfig.autoRecorder != newConfig.autoRecorder ||
           oldConfig.progressiveAutoRecorder != newConfig.progressiveAutoRecorder {
            videoRecorder?.updateConfiguration(newConfig)
            progressiveRecorder?.updateConfiguration(newConfig)
        }
        
        // Update instruction settings
        if oldConfig.enableInstructions != newConfig.enableInstructions ||
           oldConfig.instructionDelay != newConfig.instructionDelay ||
           oldConfig.instructionReplayDelay != newConfig.instructionReplayDelay ||
           oldConfig.instructionsButtonText != newConfig.instructionsButtonText {
            instructionController?.updateConfiguration(newConfig)
            updateInstructionsVisibility(enabled: newConfig.enableInstructions)
        }
    }
    
    private func updateFaceTrackerVisibility(hidden: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.faceTrackingOverlay?.isHidden = hidden
            print("👤 [FaceDetectorSDK] Face tracker visibility updated: \(hidden ? "hidden" : "visible")")
        }
    }
    
    private func updateTimerVisibility(hidden: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.recordingTimer?.isHidden = hidden
            print("⏰ [FaceDetectorSDK] Timer visibility updated: \(hidden ? "hidden" : "visible")")
        }
    }
    
    private func updateInstructionsVisibility(enabled: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.instructionView?.isHidden = !enabled
            self?.helpButton?.isHidden = !enabled
            print("📋 [FaceDetectorSDK] Instructions visibility updated: \(enabled ? "enabled" : "disabled")")
        }
    }
    
    @objc private func helpButtonTapped() {
        print("❓ [FaceDetectorSDK] Help button tapped - showing instructions")
        print("❓ [Debug] Button frame: \(helpButton?.frame ?? .zero)")
        print("❓ [Debug] Button superview: \(String(describing: type(of: helpButton?.superview)))")
        instructionController?.startInstructions()
    }
    
    private func timerStylesMatch(_ style1: JAAKTimerStyles, _ style2: JAAKTimerStyles) -> Bool {
        return style1.textColor == style2.textColor &&
               style1.circleColor == style2.circleColor &&
               style1.circleEmptyColor == style2.circleEmptyColor &&
               style1.circleSuccessColor == style2.circleSuccessColor &&
               style1.size == style2.size &&
               style1.fontSize == style2.fontSize &&
               style1.position == style2.position &&
               style1.strokeWidth == style2.strokeWidth
    }
    
    private func faceTrackerStylesMatch(_ style1: JAAKFaceTrackerStyles, _ style2: JAAKFaceTrackerStyles) -> Bool {
        return style1.validColor == style2.validColor &&
               style1.invalidColor == style2.invalidColor
    }
}

// MARK: - Camera Preview View

/// Custom UIView subclass for proper camera preview layout with auto-rotation
internal class CameraPreviewView: UIView {
    
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Update all sublayers to match the new bounds
        layer.sublayers?.forEach { sublayer in
            if let previewLayer = sublayer as? AVCaptureVideoPreviewLayer {
                previewLayer.frame = bounds
                self.previewLayer = previewLayer
                
                // Update orientation when layout changes (device rotation)
                updatePreviewOrientation()
                
                print("📐 [CameraPreviewView] Updated preview layer frame to: \(bounds)")
            } else {
                // Update other sublayers as well
                sublayer.frame = bounds
            }
        }
        
        // Update all subviews
        subviews.forEach { subview in
            if subview.autoresizingMask.contains(.flexibleWidth) && subview.autoresizingMask.contains(.flexibleHeight) {
                subview.frame = bounds
            }
        }
    }
    
    private func updatePreviewOrientation() {
        guard let previewLayer = previewLayer,
              let connection = previewLayer.connection,
              connection.isVideoOrientationSupported else { return }
        
        let currentOrientation = UIDevice.current.orientation
        let videoOrientation: AVCaptureVideoOrientation
        
        switch currentOrientation {
        case .portrait:
            videoOrientation = .portrait
        case .portraitUpsideDown:
            videoOrientation = .portraitUpsideDown
        case .landscapeLeft:
            videoOrientation = .landscapeRight  // Camera is rotated 180° relative to device
        case .landscapeRight:
            videoOrientation = .landscapeLeft   // Camera is rotated 180° relative to device
        default:
            videoOrientation = .portrait
        }
        
        if connection.videoOrientation != videoOrientation {
            connection.videoOrientation = videoOrientation
            print("🔄 [CameraPreviewView] Preview orientation updated to: \(videoOrientation.rawValue)")
        }
    }
}

// MARK: - JAAKValidationMessageView

/// Simple view for displaying face position validation messages
internal class JAAKValidationMessageView: UIView {
    
    // MARK: - Properties
    
    private let messageLabel = UILabel()
    private let backgroundView = UIView()
    private var currentMessage: String = ""
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    // MARK: - Public Methods
    
    /// Show validation message
    /// - Parameter message: message text to display
    func showMessage(_ message: String) {
        guard message != currentMessage else { return }
        
        currentMessage = message
        messageLabel.text = message
        
        // Show with animation if hidden
        if isHidden || alpha == 0.0 {
            show()
        }
    }
    
    /// Hide the message
    func hideMessage() {
        currentMessage = ""
        hide()
    }
    
    // MARK: - Private Methods
    
    private func setupUI() {
        backgroundColor = .clear
        
        // Background view with better visibility
        backgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        backgroundView.layer.cornerRadius = 12
        backgroundView.layer.borderWidth = 2
        backgroundView.layer.borderColor = UIColor.orange.cgColor
        addSubview(backgroundView)
        
        // Message label with improved styling
        messageLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 2
        messageLabel.text = ""
        messageLabel.shadowColor = UIColor.black
        messageLabel.shadowOffset = CGSize(width: 1, height: 1)
        addSubview(messageLabel)
        
        // Layout
        setupLayout()
        
        // Initial state
        isHidden = true
        alpha = 0.0
    }
    
    private func setupLayout() {
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Background fills the view
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            // Message label with padding
            messageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }
    
    private func show() {
        isHidden = false
        alpha = 0.0
        transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [], animations: {
            self.alpha = 1.0
            self.transform = .identity
        })
    }
    
    private func hide() {
        UIView.animate(withDuration: 0.2) {
            self.alpha = 0.0
            self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        } completion: { _ in
            self.isHidden = true
        }
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 50)
    }
}

// MARK: - HelpButton

/// Custom button class to ensure proper touch handling
internal class HelpButton: UIButton {
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Only respond to touches within the exact button bounds
        let result = super.point(inside: point, with: event)
        if result {
            print("🎯 [HelpButton] Touch detected at point: \(point) within bounds: \(bounds)")
        }
        return result
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Ensure the button only captures touches within its bounds
        let hitView = super.hitTest(point, with: event)
        if hitView == self {
            print("🎯 [HelpButton] Hit test successful for point: \(point)")
        }
        return hitView
    }
}


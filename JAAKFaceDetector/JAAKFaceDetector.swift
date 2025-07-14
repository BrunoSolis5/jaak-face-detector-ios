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
    
    // Background processing queue like MediaPipe example
    private let backgroundQueue = DispatchQueue(label: "ai.jaak.facedetector.backgroundQueue", qos: .userInitiated)
    
    // UI Components
    private var previewView: UIView?
    private var faceTrackingOverlay: JAAKFaceTrackingOverlay?
    private var recordingTimer: JAAKRecordingTimer?
    private var instructionView: JAAKInstructionView?
    private var instructionController: JAAKInstructionController?
    private var assistanceMessageView: JAAKAssistanceMessageView?
    private var watermarkImageView: UIImageView?
    
    
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
            
            // Progressive auto recorder works automatically after recording completion
            
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
        
        // Set initial orientation based on current device orientation like native camera app
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
        
        // Update video orientation for the new camera
        cameraManager.updateVideoOrientation()
        
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
        
        // Add recording timer with responsive positioning
        if let recordingTimer = recordingTimer {
            recordingTimer.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(recordingTimer)
            
            let position = configuration.timerStyles.position
            
            // Use multiplier constraints for truly responsive positioning
            NSLayoutConstraint.activate([
                recordingTimer.centerXAnchor.constraint(equalTo: view.centerXAnchor, 
                                                       constant: (position.x - 0.5) * 200), // Offset from center
                recordingTimer.centerYAnchor.constraint(equalTo: view.centerYAnchor, 
                                                       constant: (position.y - 0.5) * 200)  // Offset from center
            ])
            
            print("✅ [JAAKFaceDetector] Recording timer added with responsive constraints at position: \(position)")
        } else {
            print("⚠️ [JAAKFaceDetector] Recording timer is nil, not adding to view")
        }
        
        
        // Add assistance message view as full-screen overlay
        if let assistanceMessageView = assistanceMessageView {
            assistanceMessageView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(assistanceMessageView)
            
            NSLayoutConstraint.activate([
                assistanceMessageView.topAnchor.constraint(equalTo: view.topAnchor),
                assistanceMessageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                assistanceMessageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                assistanceMessageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            
            print("✅ [FaceDetectorSDK] Assistance message view added as full-screen overlay")
        }
        
        // Add instruction view as full-screen overlay (includes help button) - ON TOP of assistance messages
        if let instructionView = instructionView {
            instructionView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(instructionView)
            
            NSLayoutConstraint.activate([
                instructionView.topAnchor.constraint(equalTo: view.topAnchor),
                instructionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                instructionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                instructionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            
            print("✅ [FaceDetectorSDK] Instruction view added as full-screen overlay")
        }
        
        
        previewView = view
        return view
    }
    
    // MARK: - Watermark
    
    private func loadWatermarkImage() {
        guard let watermarkImageView = watermarkImageView else { return }
        
        let urlString = "https://storage.googleapis.com/jaak-static/commons/powered-by-jaak.png"
        guard let url = URL(string: urlString) else {
            print("⚠️ [FaceDetectorSDK] Invalid watermark URL")
            return
        }
        
        // Download image asynchronously
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil, let image = UIImage(data: data) else {
                print("⚠️ [FaceDetectorSDK] Failed to load watermark image: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            DispatchQueue.main.async {
                watermarkImageView.image = image
                print("✅ [FaceDetectorSDK] Watermark image loaded successfully")
            }
        }.resume()
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
        
        
        // Initialize UI components
        // Always create face tracking overlay
        faceTrackingOverlay = JAAKFaceTrackingOverlay(configuration: configuration.faceTrackerStyles)
        print("✅ [FaceDetectorSDK] Face tracking overlay created")
        
        // Always create recording timer
        recordingTimer = JAAKRecordingTimer(configuration: configuration.timerStyles)
        print("✅ [FaceDetectorSDK] Recording timer created")
        
        // Initialize instruction components (tutorial-style instructions)
        if configuration.enableInstructions {
            print("📋 [FaceDetectorSDK] Creating instruction view (enableInstructions = true)")
            instructionView = JAAKInstructionView(configuration: configuration)
            instructionController = JAAKInstructionController(configuration: configuration, instructionView: instructionView!)
            instructionController?.delegate = self
            // The instruction controller will handle the instruction view delegate
        } else {
            print("📋 [FaceDetectorSDK] Skipping instruction view (enableInstructions = false)")
        }
        
        // Always create validation message view (for positioning guidance)
        assistanceMessageView = JAAKAssistanceMessageView(configuration: configuration)
        print("✅ [FaceDetectorSDK] Validation message view created")
        
        // Create watermark image view
        watermarkImageView = UIImageView()
        watermarkImageView?.contentMode = .scaleAspectFit
        watermarkImageView?.alpha = 0.6
        loadWatermarkImage()
        print("✅ [FaceDetectorSDK] Watermark image view created")
        
        
        // Listen for orientation change notifications from overlay
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateCaptureOrientation),
            name: NSNotification.Name("JAAKUpdateCaptureOrientation"),
            object: nil
        )
    }
    
    private func checkPermissions() throws {
        print("🔐 [FaceDetectorSDK] Checking permissions...")
        print("🔐 [FaceDetectorSDK] enableMicrophone: \(configuration.enableMicrophone)")
        print("🔐 [FaceDetectorSDK] Camera authorized: \(JAAKPermissionManager.isCameraAuthorized())")
        print("🔐 [FaceDetectorSDK] Microphone authorized: \(JAAKPermissionManager.isMicrophoneAuthorized())")
        
        // Request permissions using JAAKPermissionManager
        // This will trigger permission prompts if needed
        
        let semaphore = DispatchSemaphore(value: 0)
        var permissionError: JAAKFaceDetectorError?
        
        print("🔐 [FaceDetectorSDK] Requesting required permissions...")
        JAAKPermissionManager.requestRequiredPermissions(enableMicrophone: configuration.enableMicrophone) { granted, error in
            print("🔐 [FaceDetectorSDK] Permission request completed - granted: \(granted)")
            if let error = error {
                print("🔐 [FaceDetectorSDK] Permission error: \(error)")
            }
            
            if !granted {
                permissionError = error ?? JAAKFaceDetectorError(
                    label: "Required permissions not granted",
                    code: "PERMISSIONS_DENIED"
                )
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = permissionError {
            throw error
        }
        
        print("✅ [FaceDetectorSDK] All required permissions granted")
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
    
    
    @objc private func updateCaptureOrientation() {
        print("📱 [FaceDetectorSDK] Updating capture orientation due to device rotation")
        cameraManager?.updateVideoOrientation()
    }
}

// MARK: - JAAKCameraManagerDelegate

extension JAAKFaceDetectorSDK: JAAKCameraManagerDelegate {
    func cameraManager(_ manager: JAAKCameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        // Process frame for face detection directly (MediaPipe handles its own threading)
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
        } else {
            // Clear detections when no face is detected
            faceTrackingOverlay?.clearDetections()
            faceTrackingOverlay?.notifyNoFaceDetected()
            
        }
        
        // Handle auto-recording with detailed debugging
        
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
            self?.assistanceMessageView?.showMessage(message.label)
        }
        
        // Forward to delegate
        delegate?.faceDetector(self, didDetectFace: message)
    }
    
    func faceDetectionEngine(_ engine: JAAKFaceDetectionEngine, didDetectFaces detections: [Detection], sampleBuffer: CMSampleBuffer) {
        // Face detection results received - progressive recording is handled automatically
        // through the normal recording flow when faces are detected
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
        
        // Stop timer with progressive flag if needed
        let isProgressive = configuration.progressiveAutoRecorder
        recordingTimer?.stopTimer(isProgressive: isProgressive)
        
        // Always notify delegate about the completed recording
        delegate?.faceDetector(self, didCaptureFile: fileResult)
        
        // If progressive auto recorder is enabled, prepare for next recording
        if configuration.progressiveAutoRecorder {
            resetForNextRecording()
        }
    }
    
    /// Reset all states to prepare for next recording in progressive mode
    private func resetForNextRecording() {
        print("🔄 [FaceDetectorSDK] Progressive auto recorder enabled - preparing for next recording...")
        print("📊 [FaceDetectorSDK] Current status: \(status), autoRecorder: \(configuration.autoRecorder)")
        
        // Clear any previous face detection state that might block new recording
        faceDetectionEngine?.resetDetectionState()
        
        // Ensure status is back to running for auto-recording detection (with delay to allow UI to update)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.updateStatus(.running)
        }
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
    
    func instructionController(_ controller: JAAKInstructionController, shouldPauseDetection pause: Bool) {
        // Pause or resume face detection based on instruction state
        if pause {
            print("🎓 [FaceDetectorSDK] Pausing face detection for instructions")
            faceDetectionEngine?.pauseDetection()
        } else {
            print("🎓 [FaceDetectorSDK] Resuming face detection after instructions")
            faceDetectionEngine?.resumeDetection()
        }
    }
}


// MARK: - Configuration Updates

extension JAAKFaceDetectorSDK {
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
        // enableMicrophone is handled separately to avoid full restart
        return oldConfig.cameraPosition != newConfig.cameraPosition ||
               oldConfig.videoQuality != newConfig.videoQuality ||
               oldConfig.disableFaceDetection != newConfig.disableFaceDetection ||
               oldConfig.useOfflineModel != newConfig.useOfflineModel
    }
    
    /// Apply configuration changes that can be done dynamically
    private func applyDynamicConfigurationChanges(from oldConfig: JAAKFaceDetectorConfiguration, to newConfig: JAAKFaceDetectorConfiguration) {
        
        // Update UI components that can change dynamically
        
        // Handle microphone changes without full restart
        if oldConfig.enableMicrophone != newConfig.enableMicrophone {
            handleMicrophoneConfigurationChange(enabled: newConfig.enableMicrophone)
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
        }
        
        // Update instruction settings
        if oldConfig.enableInstructions != newConfig.enableInstructions ||
           oldConfig.instructionDelay != newConfig.instructionDelay ||
           oldConfig.instructionDuration != newConfig.instructionDuration ||
           oldConfig.instructionsButtonText != newConfig.instructionsButtonText {
            instructionController?.updateConfiguration(newConfig)
            updateInstructionsVisibility(enabled: newConfig.enableInstructions)
        }
    }
    
    private func handleMicrophoneConfigurationChange(enabled: Bool) {
        print("🎤 [FaceDetectorSDK] Microphone configuration changed to: \(enabled)")
        
        // Update the camera manager's microphone setup
        guard let cameraManager = cameraManager else {
            print("❌ [FaceDetectorSDK] Camera manager not available for microphone update")
            return
        }
        
        do {
            try cameraManager.updateMicrophoneConfiguration(enabled: enabled)
            print("✅ [FaceDetectorSDK] Microphone configuration updated successfully")
        } catch {
            print("❌ [FaceDetectorSDK] Failed to update microphone configuration: \(error)")
        }
    }
    
    private func updateInstructionsVisibility(enabled: Bool) {
        DispatchQueue.main.async { [weak self] in
            // The instruction view is always visible for the help button
            // Only hide the help button itself when instructions are disabled
            if let instructionView = self?.instructionView {
                if enabled {
                    instructionView.isHidden = false
                } else {
                    instructionView.isHidden = true
                }
            }
            print("📋 [FaceDetectorSDK] Instructions visibility updated: \(enabled ? "enabled" : "disabled")")
        }
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
                
                // Update orientation for proper video display like native camera app
                updatePreviewOrientation()
                
            } else {
                // Update other sublayers as well
                sublayer.frame = bounds
            }
        }
        
        // Update all subviews - but skip those using Auto Layout
        subviews.forEach { subview in
            if !subview.translatesAutoresizingMaskIntoConstraints {
                // Skip views using Auto Layout - they handle their own sizing
                return
            }
            
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

// MARK: - JAAKAssistanceMessageView

/// Assistance message view for displaying real-time positioning guidance
internal class JAAKAssistanceMessageView: UIView {
    
    // MARK: - Properties
    
    private let configuration: JAAKFaceDetectorConfiguration
    private var currentMessage: String = ""
    
    // UI Components
    private let backgroundView = UIView()
    private let messageLabel = UILabel()
    
    // MARK: - Initialization
    
    init(configuration: JAAKFaceDetectorConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Public Methods
    
    /// Show assistance message
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
        // Background
        backgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        backgroundView.layer.cornerRadius = 16
        addSubview(backgroundView)
        
        // Message label
        messageLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.text = ""
        messageLabel.shadowColor = UIColor.black
        messageLabel.shadowOffset = CGSize(width: 1, height: 1)
        messageLabel.adjustsFontSizeToFitWidth = true
        messageLabel.minimumScaleFactor = 0.7
        addSubview(messageLabel)
        
        // Layout
        setupLayout()
        
        // Initial state
        isHidden = true
        alpha = 0.0
        isUserInteractionEnabled = false
    }
    
    private func setupLayout() {
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Background - centered horizontally, positioned at 1/3 from bottom
            backgroundView.centerXAnchor.constraint(equalTo: centerXAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -120), // About 1/3 from bottom
            backgroundView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            backgroundView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
            backgroundView.heightAnchor.constraint(lessThanOrEqualToConstant: 80),
            backgroundView.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
            
            // Content - positioned relative to background with generous padding
            messageLabel.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 16),
            messageLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -20),
            messageLabel.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -16)
        ])
    }
    
    private func show() {
        isHidden = false
        alpha = 0.0
        backgroundView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [], animations: {
            self.alpha = 1.0
            self.backgroundView.transform = .identity
        })
    }
    
    private func hide() {
        UIView.animate(withDuration: 0.2) {
            self.alpha = 0.0
            self.backgroundView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        } completion: { _ in
            self.isHidden = true
        }
    }
}

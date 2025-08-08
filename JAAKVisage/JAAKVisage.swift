import UIKit
import AVFoundation
import MediaPipeTasksVision

/// Main class for JAAKVisage - AI-powered face detection and recording library
public class JAAKVisageSDK: NSObject {
    
    // MARK: - Public Properties
    
    /// Delegate for receiving events from the face detector
    public weak var delegate: JAAKVisageSDKDelegate?
    
    /// Configuration for the face detector
    public var configuration: JAAKVisageConfiguration {
        didSet {
            // When configuration changes, update components if needed
            updateComponentsWithNewConfiguration()
        }
    }
    
    /// Current status of the face detector
    public private(set) var status: JAAKVisageStatus = .notLoaded
    
    // Countdown properties (matching webcomponent)
    private var countdownTimer: Timer?
    private var countdown: Int = 0
    private var recordingCancelled: Bool = false
    private var wasInOptimalPosition: Bool = false
    
    // MARK: - Private Properties
    
    // Core components
    private var cameraManager: JAAKCameraManager?
    private var faceDetectionEngine: JAAKFaceDetectionEngine?
    private var videoRecorder: JAAKVideoRecorder?
    private var securityMonitor: JAAKSecurityMonitor?
    
    // Background processing queue like MediaPipe example
    private let backgroundQueue = DispatchQueue(label: "ai.jaak.visage.backgroundQueue", qos: .userInitiated)
    
    // UI Components
    private var previewView: UIView?
    private var faceTrackingOverlay: JAAKFaceTrackingOverlay?
    private var recordingTimer: JAAKRecordingTimer?
    private var instructionView: JAAKInstructionView?
    private var instructionController: JAAKInstructionController?
    private var assistanceMessageView: JAAKAssistanceMessageView?
    private var statusIndicatorView: JAAKStatusIndicatorView?
    private var watermarkImageView: UIImageView?
    
    
    // MARK: - Initialization
    
    /// Initialize JAAKVisage with configuration
    /// - Parameter configuration: Configuration object for the detector
    public init(configuration: JAAKVisageConfiguration) {
        self.configuration = configuration
        super.init()
        
        setupComponents()
    }
    
    // MARK: - Public Methods - Component Lifecycle
    
    /// Start face detection
    /// - Throws: JAAKVisageError if unable to start
    public func startDetection() throws {
        updateStatus(.loading)
        
        // Check permissions first
        do {
            try checkPermissions()
        } catch let error as JAAKVisageError where error.code == "PERMISSIONS_REQUIRED" {
            // Request permissions asynchronously and retry
            requestPermissionsAndRetryStart()
            return
        }
        
        do {
            try continueStartDetection()
        } catch {
            updateStatus(.error)
            throw error
        }
    }
    
    /// Request permissions asynchronously and retry start
    private func requestPermissionsAndRetryStart() {
        
        // Request permissions on background queue to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            JAAKPermissionManager.requestRequiredPermissions(enableMicrophone: self.configuration.enableMicrophone) { [weak self] granted, error in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    if granted {
                        do {
                            try self.continueStartDetection()
                        } catch {
                            self.updateStatus(.error)
                            let detectorError = error as? JAAKVisageError ?? JAAKVisageError(
                                label: "Failed to start after permissions granted",
                                code: "START_AFTER_PERMISSIONS_FAILED",
                                details: error
                            )
                            self.delegate?.faceDetector(self, didEncounterError: detectorError)
                        }
                    } else {
                        self.updateStatus(.error)
                        let permissionError = error ?? JAAKVisageError(
                            label: "Required permissions not granted",
                            code: "PERMISSIONS_DENIED"
                        )
                        self.delegate?.faceDetector(self, didEncounterError: permissionError)
                    }
                }
            }
        }
    }
    
    /// Continue with detection start after permissions are confirmed
    private func continueStartDetection(showInstructions: Bool = true) throws {
        // Setup camera only if not already set up
        guard let cameraManager = cameraManager else {
            throw JAAKVisageError(label: "Camera manager not initialized", code: "CAMERA_MANAGER_NIL")
        }
        
        // Check if session is already configured
        let captureSession = cameraManager.getCaptureSession()
        if captureSession.inputs.isEmpty {
            try cameraManager.setupCaptureSession(with: configuration)
        } else {
        }
        
        // Load models if not already loaded
        if status != .loaded {
            try loadModels()
        } else {
        }
        
        // Start camera
        showCustomStatus("Solicitando acceso a la cámara...")
        cameraManager.startSession()
        showCustomStatus("Cámara activa")
        
        // Start security monitoring
        securityMonitor?.startMonitoring()
        
        // Show initial instructions if requested
        if showInstructions {
            instructionController?.startInstructions()
        }
        
        // Auto recorder works automatically after recording completion
        
        updateStatus(.running)
    }
    
    /// Stop face detection
    public func stopDetection() {
        cameraManager?.stopSession()
        securityMonitor?.stopMonitoring()
        instructionController?.hideInstructions()
        updateStatus(.stopped)
    }
    
    /// Restart face detection
    /// - Throws: JAAKVisageError if unable to restart
    public func restartDetection() throws {
        // Check if instructions are currently showing to preserve state
        let shouldShowInstructions = configuration.enableInstructions
        
        // Cancel any active countdown or recording before restarting
        if countdown > 0 || isRecording() {
            cancelCountdownAndRecording()
            print("🔄 [restartDetection] Cancelled active countdown/recording before restart")
        }
        
        // Reset countdown and position state variables
        // Note: Don't reset recordingCancelled here - let the delegate handle it after discarding cancelled recording
        wasInOptimalPosition = false
        countdown = 0
        
        // Stop detection components but avoid hiding instructions to prevent flashing
        cameraManager?.stopSession()
        securityMonitor?.stopMonitoring()
        updateStatus(.stopped)
        
        // Restart detection without showing instructions immediately
        try continueStartDetection(showInstructions: false)
        
        // Show instructions with proper timing to avoid the flash
        if shouldShowInstructions {
            // Add small delay to ensure UI is ready and avoid rapid hide/show cycle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.instructionController?.startInstructions()
            }
        }
    }
    
    /// Reset the detector
    /// - Parameter hardReset: If true, performs a complete reset including model reloading
    /// - Throws: JAAKVisageError if unable to reset
    public func resetDetector(hardReset: Bool = false) throws {
        stopDetection()
        
        if hardReset {
            setupComponents()
        }
        
        updateStatus(.notLoaded)
    }
    
    // MARK: - Public Methods - Recording Operations
    
    /// Record video with face detection (manual recording - not used by auto-recorder)
    /// - Parameter completion: Completion handler with result
    public func recordVideo(completion: @escaping (Result<JAAKFileResult, JAAKVisageError>) -> Void) {
        guard status == .running || status == .faceDetected else {
            let error = JAAKVisageError(
                label: "Cannot record video - detector not running",
                code: "INVALID_STATE"
            )
            completion(.failure(error))
            return
        }
        
        guard let videoRecorder = videoRecorder, let cameraManager = cameraManager else {
            let error = JAAKVisageError(
                label: "Video recorder not available",
                code: "VIDEO_RECORDER_NIL"
            )
            completion(.failure(error))
            return
        }
        
        // For manual recording, bypass countdown and start immediately
        updateStatus(.recording)
        recordingTimer?.startTimer(duration: configuration.videoDuration)
        videoRecorder.startRecording(with: cameraManager, completion: completion)
    }
    
    /// Stop current video recording
    public func stopRecording() {
        guard let videoRecorder = videoRecorder, let cameraManager = cameraManager else { return }
        guard videoRecorder.isRecording() else { return }
        
        videoRecorder.stopRecording(with: cameraManager)
        
        // Stop the timer
        recordingTimer?.stopTimer()
        
        // Reset status if we were recording
        if status == .recording {
            updateStatus(.running)
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
    }
    
    /// Get capture session
    /// - Returns: AVCaptureSession or nil if not available
    public func getCaptureSession() -> AVCaptureSession? {
        return cameraManager?.getCaptureSession()
    }
    
    /// Toggle between front and back camera
    /// - Throws: JAAKVisageError if unable to toggle
    public func toggleCamera() throws {
        guard let cameraManager = cameraManager else {
            throw JAAKVisageError(
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
    /// - Throws: JAAKVisageError if unable to start
    public func startVideoStream() throws {
        guard let cameraManager = cameraManager else {
            throw JAAKVisageError(
                label: "Camera manager not available",
                code: "CAMERA_MANAGER_NIL"
            )
        }
        
        cameraManager.startSession()
    }
    
    // MARK: - Public Methods - Model Loading
    
    /// Load AI models for face detection
    /// - Throws: JAAKVisageError if unable to load models
    public func loadModels() throws {
        updateStatus(.loading)
        
        guard let faceDetectionEngine = faceDetectionEngine else {
            throw JAAKVisageError(label: "Face detection engine not initialized", code: "FACE_ENGINE_NIL")
        }
        
        try faceDetectionEngine.loadModels()
        
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
        } catch {
        }
        
        // Add camera preview layer
        if let previewLayer = getCameraPreviewLayer() {
            // Set initial frame - will be updated in layoutSubviews
            previewLayer.frame = view.bounds
            previewLayer.videoGravity = .resizeAspect
            view.layer.addSublayer(previewLayer)
            
        } else {
        }
        
        // Add face tracking overlay
        if let faceTrackingOverlay = faceTrackingOverlay {
            faceTrackingOverlay.frame = view.bounds
            faceTrackingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(faceTrackingOverlay)
        } else {
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
            
        } else {
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
            
        }
        
        // Add status indicator view as overlay (matching webcomponent position: top-left)
        if let statusIndicatorView = statusIndicatorView {
            statusIndicatorView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(statusIndicatorView)
            
            NSLayoutConstraint.activate([
                statusIndicatorView.topAnchor.constraint(equalTo: view.topAnchor),
                statusIndicatorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                statusIndicatorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                statusIndicatorView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            
        }
        
        // Add instruction view as full-screen overlay (includes help button) - ON TOP of all other views
        if let instructionView = instructionView {
            instructionView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(instructionView)
            
            NSLayoutConstraint.activate([
                instructionView.topAnchor.constraint(equalTo: view.topAnchor),
                instructionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                instructionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                instructionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            
        }
        
        
        previewView = view
        return view
    }
    
    // MARK: - Watermark
    
    private func loadWatermarkImage() {
        guard let watermarkImageView = watermarkImageView else { return }
        
        let urlString = "https://storage.googleapis.com/jaak-static/commons/powered-by-jaak.png"
        guard let url = URL(string: urlString) else {
            return
        }
        
        // Download image asynchronously
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil, let image = UIImage(data: data) else {
                return
            }
            
            DispatchQueue.main.async {
                watermarkImageView.image = image
            }
        }.resume()
    }
    
    /// Create controls view for detector controls
    /// - Returns: UIView containing control buttons
    public func createControlsView() -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        // TODO: Add control buttons (record, toggle camera, etc.)
        // This is a placeholder - actual implementation will be added in next phases
        
        return view
    }
    
    // MARK: - Private Methods
    
    private func setupComponents() {
        
        // Initialize core components
        cameraManager = JAAKCameraManager()
        cameraManager?.delegate = self
        
        faceDetectionEngine = JAAKFaceDetectionEngine(configuration: configuration)
        faceDetectionEngine?.delegate = self
        
        videoRecorder = JAAKVideoRecorder(configuration: configuration)
        videoRecorder?.delegate = self
        
        // Initialize security monitor
        securityMonitor = JAAKSecurityMonitor(configuration: configuration)
        securityMonitor?.delegate = self
        
        
        // Initialize UI components
        // Always create face tracking overlay
        faceTrackingOverlay = JAAKFaceTrackingOverlay(configuration: configuration.faceTrackerStyles)
        
        // Always create recording timer
        recordingTimer = JAAKRecordingTimer(configuration: configuration.timerStyles)
        
        // Initialize instruction components (tutorial-style instructions)
        if configuration.enableInstructions {
            instructionView = JAAKInstructionView(configuration: configuration)
            instructionController = JAAKInstructionController(configuration: configuration, instructionView: instructionView!)
            instructionController?.delegate = self
            // The instruction controller will handle the instruction view delegate
        } else {
        }
        
        // Always create validation message view (for positioning guidance)
        assistanceMessageView = JAAKAssistanceMessageView(configuration: configuration)
        
        // Always create status indicator view (matching webcomponent status-indicator)
        statusIndicatorView = JAAKStatusIndicatorView(configuration: configuration)
        
        // Create watermark image view
        watermarkImageView = UIImageView()
        watermarkImageView?.contentMode = .scaleAspectFit
        watermarkImageView?.alpha = 0.6
        loadWatermarkImage()
        
        
        // Listen for orientation change notifications from overlay
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateCaptureOrientation),
            name: NSNotification.Name("JAAKUpdateCaptureOrientation"),
            object: nil
        )
    }
    
    private func checkPermissions() throws {
        
        // Check if permissions are already granted
        let cameraAuthorized = JAAKPermissionManager.isCameraAuthorized()
        let microphoneAuthorized = !configuration.enableMicrophone || JAAKPermissionManager.isMicrophoneAuthorized()
        
        if cameraAuthorized && microphoneAuthorized {
            return
        }
        
        // If permissions are missing, we'll request them asynchronously later
        // For now, throw an error to indicate permissions are needed
        let missingPermissions = [
            !cameraAuthorized ? "camera" : nil,
            (configuration.enableMicrophone && !microphoneAuthorized) ? "microphone" : nil
        ].compactMap { $0 }
        
        throw JAAKVisageError(
            label: "Missing permissions: \(missingPermissions.joined(separator: ", "))",
            code: "PERMISSIONS_REQUIRED"
        )
    }
    
    private func updateStatus(_ newStatus: JAAKVisageStatus) {
        status = newStatus
        
        // Update status indicator with translated message (matching webcomponent)
        let statusMessage = getStatusMessage(for: newStatus)
        statusIndicatorView?.showStatus(statusMessage)
        
        // Notify instruction controller of status change
        instructionController?.handleStatusChange(newStatus)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.faceDetector(self, didUpdateStatus: newStatus)
        }
    }
    
    /// Get localized status message matching webcomponent messages
    private func getStatusMessage(for status: JAAKVisageStatus) -> String {
        switch status {
        case .notLoaded:
            return "Componente cargado"
        case .loading:
            return "Inicializando detección facial..."
        case .loaded:
            return "Detección facial lista"
        case .running:
            return "Detección facial activa"
        case .recording:
            return "Grabando video..."
        case .finished:
            return "Captura completada"
        case .stopped:
            return "Cámara detenida"
        case .error:
            return "Error en el componente"
        // New states matching webcomponent
        case .faceDetected:
            return "Rostro detectado - iniciando grabación"
        case .countdown:
            return "Iniciando grabación en..." // Will be updated with countdown number
        case .captureComplete:
            return "Captura completada"
        case .processingVideo:
            return "Procesando video..."
        case .videoReady:
            return "Video listo para visualización"
        }
    }
    
    /// Show custom status message (for specific camera/processing states)
    private func showCustomStatus(_ message: String) {
        statusIndicatorView?.showStatus(message)
    }
    
    // MARK: - Countdown Methods (matching webcomponent exactly)
    
    /// Start countdown before recording (exactly like webcomponent)
    private func startCountdown() {
        countdown = Int(configuration.videoDuration)
        recordingCancelled = false
        
        print("⏰ [startCountdown] Starting countdown from \(countdown)...")
        
        // Update status with countdown message
        updateStatusWithCountdown()
        
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            self.countdown -= 1
            self.updateStatusWithCountdown()
            
            if self.countdown == Int(self.configuration.videoDuration) - 1 {
                // Start recording when countdown reaches videoDuration-1 (like webcomponent)
                self.startRecordingInternal()
            }
            
            if self.countdown <= 0 {
                // Stop recording and detection if not cancelled
                if !self.recordingCancelled {
                    self.updateStatus(.captureComplete)
                    self.stopRecordingInternal()
                    self.stopFaceDetectionInternal()
                }
                self.countdownTimer?.invalidate()
                self.countdownTimer = nil
            }
        }
    }
    
    /// Update status with countdown number
    private func updateStatusWithCountdown() {
        updateStatus(.countdown)
        statusIndicatorView?.showStatus("Iniciando grabación en \(countdown)...")
    }
    
    /// Cancel countdown timer
    private func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdown = 0
    }
    
    /// Cancel countdown and recording (exactly like webcomponent)
    private func cancelCountdownAndRecording() {
        recordingCancelled = true
        
        // Cancel countdown
        cancelCountdown()
        
        // Stop and discard recording if active
        if let videoRecorder = videoRecorder, videoRecorder.isRecording() {
            videoRecorder.stopRecording(with: cameraManager!)
        }
        
        // Stop timer
        recordingTimer?.cancelTimer()
        
        // Reset position tracking for next attempt
        wasInOptimalPosition = false
        
        print("🚫 [JAAKVisage] Recording cancelled - face out of position")
    }
    
    // MARK: - Internal Recording Methods
    
    /// Start recording internally (called from countdown)
    private func startRecordingInternal() {
        guard let videoRecorder = videoRecorder, let cameraManager = cameraManager else { return }
        
        updateStatus(.recording)
        videoRecorder.startRecording(with: cameraManager) { [weak self] result in
            // Handle result in completion callback, but main flow continues through countdown
            switch result {
            case .success:
                break // Success handled by countdown completion
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.handleRecordingError(error)
                }
            }
        }
        
        // Start UI timer
        recordingTimer?.startTimer(duration: configuration.videoDuration)
    }
    
    /// Stop recording internally (called from countdown completion)
    private func stopRecordingInternal() {
        guard let videoRecorder = videoRecorder else { return }
        
        if videoRecorder.isRecording() {
            videoRecorder.stopRecording(with: cameraManager!)
        }
        
        // Stop UI timer
        recordingTimer?.stopTimer()
    }
    
    /// Stop face detection internally (like webcomponent stopFaceDetection)
    private func stopFaceDetectionInternal() {
        // Stop detection completely to prevent further auto-recording attempts
        stopDetection()
        
        // Stop camera session to prevent frozen frame and phantom detections
        cameraManager?.stopSession()
        
        // Clear the camera preview to remove frozen frame
        clearCameraPreview()
        
        // Reset optimal position tracking
        wasInOptimalPosition = false
        
        // Ensure status is set to finished, not running
        updateStatus(.finished)
    }
    
    /// Clear camera preview to remove frozen frame
    private func clearCameraPreview() {
        // Remove all preview layers to clear frozen frame
        guard let view = previewView else { return }
        
        view.layer.sublayers?.forEach { sublayer in
            if sublayer is AVCaptureVideoPreviewLayer {
                sublayer.removeFromSuperlayer()
            }
        }
        
        print("🧹 [JAAKVisage] Camera preview cleared")
    }
    
    /// Handle recording error
    private func handleRecordingError(_ error: JAAKVisageError) {
        updateStatus(.error)
        recordingTimer?.cancelTimer()
        delegate?.faceDetector(self, didEncounterError: error)
    }
    
    // MARK: - Optimal Position Handling (exactly like webcomponent)
    
    /// Handle optimal position detection (matching webcomponent handleOptimalPosition)
    private func handleOptimalPosition(message: JAAKFaceDetectionMessage) {
        let isCurrentlyOptimal = message.faceExists && message.correctPosition
        
        print("🔍 [handleOptimalPosition] faceExists: \(message.faceExists), correctPosition: \(message.correctPosition), isCurrentlyOptimal: \(isCurrentlyOptimal)")
        
        // State transitions with debouncing (simplified for iOS - exact logic from webcomponent)
        if isCurrentlyOptimal && !wasInOptimalPosition && !isRecording() && countdown == 0 {
            // Start countdown (like webcomponent)
            print("✅ [handleOptimalPosition] Starting countdown - face detected!")
            updateStatus(.faceDetected)
            instructionController?.hideInstructions() // Hide instructions like webcomponent
            startCountdown()
            wasInOptimalPosition = true
            
        } else if !isCurrentlyOptimal && wasInOptimalPosition && (countdown > 0 || isRecording()) {
            // Cancel countdown and/or recording when mask turns from green to white (correctPosition becomes false)
            print("🚫 [handleOptimalPosition] Mask turned white - canceling countdown/recording")
            updateStatus(.running)
            statusIndicatorView?.showStatus("Posición perdida - cancelando grabación")
            cancelCountdownAndRecording()
            wasInOptimalPosition = false
            
        } else if isCurrentlyOptimal && !wasInOptimalPosition {
            wasInOptimalPosition = true
        } else if !isCurrentlyOptimal && wasInOptimalPosition && !isRecording() && countdown == 0 {
            wasInOptimalPosition = false
        }
    }
    
    /// Check if currently recording
    private func isRecording() -> Bool {
        return videoRecorder?.isRecording() ?? false
    }
    
    
    @objc private func updateCaptureOrientation() {
        cameraManager?.updateVideoOrientation()
    }
}

// MARK: - JAAKCameraManagerDelegate

extension JAAKVisageSDK: JAAKCameraManagerDelegate {
    func cameraManager(_ manager: JAAKCameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        // Process frame for face detection directly (MediaPipe handles its own threading)
        let currentTimeMs = Date().timeIntervalSince1970 * 1000
        
        // Process on main thread to avoid Sendable issues with CMSampleBuffer
        faceDetectionEngine?.processVideoFrame(sampleBuffer, timestamp: Int(currentTimeMs))
    }
    
    func cameraManager(_ manager: JAAKCameraManager, didFinishRecordingTo outputURL: URL) {
        videoRecorder?.handleRecordingCompletion(outputURL)
    }
    
    func cameraManager(_ manager: JAAKCameraManager, didFailWithError error: JAAKVisageError) {
        delegate?.faceDetector(self, didEncounterError: error)
    }
}

// MARK: - JAAKFaceDetectionEngineDelegate

extension JAAKVisageSDK: JAAKFaceDetectionEngineDelegate {
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
        
        // Handle auto-recording with stability logic (exactly like webcomponent handleOptimalPosition)
        if configuration.autoRecorder {
            handleOptimalPosition(message: message)
        }
        
        // Show validation message (always shown for positioning guidance)
        DispatchQueue.main.async { [weak self] in
            self?.assistanceMessageView?.showMessage(message.label)
        }
        
        // Forward to delegate
        delegate?.faceDetector(self, didDetectFace: message)
    }
    
    func faceDetectionEngine(_ engine: JAAKFaceDetectionEngine, didDetectFaces detections: [Detection], sampleBuffer: CMSampleBuffer) {
        // Face detection results received - auto recording is handled automatically
        // through the normal recording flow when faces are detected
    }
    
    func faceDetectionEngine(_ engine: JAAKFaceDetectionEngine, didFailWithError error: JAAKVisageError) {
        instructionController?.handleError(error)
        delegate?.faceDetector(self, didEncounterError: error)
    }
    
    func faceDetectionEngine(_ engine: JAAKFaceDetectionEngine, shouldCancelRecording: Bool) {
        // This is now handled by handleOptimalPosition method following webcomponent logic
        // The webcomponent uses handleOptimalPosition to manage countdown and recording cancellation
        // So we don't need this method anymore, but keep it for compatibility
    }
}

// MARK: - JAAKVideoRecorderDelegate

extension JAAKVisageSDK: JAAKVideoRecorderDelegate {
    func videoRecorder(_ recorder: JAAKVideoRecorder, didStartRecording outputURL: URL) {
        // Note: updateStatus(.recording) and timer start are handled by startRecordingInternal()
        // to avoid duplicate recording management when using countdown system
        
        // IMPORTANT: Do NOT reset stability counters here! 
        // Resetting them would break the face detection stability that we just achieved,
        // causing immediate cancellation of the recording we just started.
    }
    
    func videoRecorder(_ recorder: JAAKVideoRecorder, didUpdateProgress progress: Float) {
        recordingTimer?.updateProgress(progress)
    }
    
    func videoRecorder(_ recorder: JAAKVideoRecorder, didFinishRecording fileResult: JAAKFileResult) {
        // Check if recording was cancelled - if so, discard the result
        if recordingCancelled {
            print("🗑️ [JAAKVisage] Discarding cancelled recording - not sending to delegate")
            updateStatus(.running) // Return to detection state
            recordingCancelled = false // Reset flag for next recording
            return
        }
        
        // Follow webcomponent flow: processing-video → video-ready
        updateStatus(.processingVideo)
        
        // Simulate processing time (like webcomponent)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateStatus(.videoReady)
            
            // Only notify delegate about completed (not cancelled) recordings
            self?.delegate?.faceDetector(self!, didCaptureFile: fileResult)
        }
    }
    
    
    func videoRecorder(_ recorder: JAAKVideoRecorder, didFailWithError error: JAAKVisageError) {
        updateStatus(.error)
        // Cancel timer immediately on error (no need for fade out animation)
        recordingTimer?.cancelTimer()
        delegate?.faceDetector(self, didEncounterError: error)
    }
}

// MARK: - JAAKSecurityMonitorDelegate

extension JAAKVisageSDK: JAAKSecurityMonitorDelegate {
    func securityMonitor(_ monitor: JAAKSecurityMonitor, didDetectEvent event: JAAKSecurityEvent) {
        // Handle security events based on severity
        switch event.severity {
        case .critical, .high:
            // Stop detection for critical security issues
            stopDetection()
            
            let error = JAAKVisageError(
                label: "Security threat detected: \(event.description)",
                code: "SECURITY_THREAT",
                details: event
            )
            updateStatus(.error)
            delegate?.faceDetector(self, didEncounterError: error)
            
        case .medium:
            // Log medium severity events but continue operation
            let error = JAAKVisageError(
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

extension JAAKVisageSDK: JAAKInstructionControllerDelegate {
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
            faceDetectionEngine?.pauseDetection()
        } else {
            faceDetectionEngine?.resumeDetection()
        }
    }
    
    func instructionController(_ controller: JAAKInstructionController, didRequestCameraList completion: @escaping ([String], String?) -> Void) {
        // Get available cameras using AVFoundation
        
        var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInTelephotoCamera]
        if #available(iOS 13.0, *) {
            deviceTypes.append(.builtInUltraWideCamera)
        }
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )
        
        let availableCameras = discoverySession.devices.map { device -> String in
            switch device.position {
            case .front:
                return "Front Camera"
            case .back:
                return "Back Camera"
            default:
                return device.localizedName
            }
        }
        
        // Remove duplicates and ensure we have at least basic cameras
        let uniqueCameras = Array(Set(availableCameras))
        let finalCameras = uniqueCameras.isEmpty ? ["Front Camera", "Back Camera"] : uniqueCameras
        
        // Determine current camera name based on configuration
        let currentCameraName: String
        switch configuration.cameraPosition {
        case .front:
            currentCameraName = "Front Camera"
        case .back:
            currentCameraName = "Back Camera"
        default:
            currentCameraName = "Back Camera" // Default fallback
        }
        
        completion(finalCameras, currentCameraName)
    }
    
    func instructionController(_ controller: JAAKInstructionController, didSelectCamera cameraName: String) {
        // Switch to selected camera
        
        do {
            // Determine camera position from name
            let targetPosition: AVCaptureDevice.Position
            if cameraName.lowercased().contains("front") {
                targetPosition = .front
            } else if cameraName.lowercased().contains("back") {
                targetPosition = .back
            } else {
                // Default to toggle behavior
                targetPosition = (configuration.cameraPosition == .front) ? .back : .front
            }
            
            // Update configuration
            var updatedConfig = configuration
            updatedConfig.cameraPosition = targetPosition
            
            // Use existing camera manager to switch camera
            try cameraManager?.toggleCamera(to: targetPosition, configuration: updatedConfig)
            
            // Update our configuration
            self.configuration = updatedConfig
            
        } catch {
        }
    }
}


// MARK: - Configuration Updates

extension JAAKVisageSDK {
    private func updateComponentsWithNewConfiguration() {
        
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
        
    }
    
    /// Update configuration without recreating the entire SDK
    /// - Parameter newConfiguration: The new configuration to apply
    public func updateConfiguration(_ newConfiguration: JAAKVisageConfiguration) {
        let oldConfiguration = self.configuration
        
        // Check if changes require restart
        let requiresRestart = configurationRequiresRestart(from: oldConfiguration, to: newConfiguration)
        
        if requiresRestart {
            let wasRunning = (status == .running)
            
            if wasRunning {
                stopDetection()
            }
            
            self.configuration = newConfiguration
            
            if wasRunning {
                do {
                    try startDetection()
                    
                    // After restart, reapply microphone configuration if needed
                    // This handles both: microphone setting changes AND camera position changes with microphone enabled
                    
                    if oldConfiguration.enableMicrophone != newConfiguration.enableMicrophone {
                        handleMicrophoneConfigurationChange(enabled: newConfiguration.enableMicrophone)
                    } else if newConfiguration.enableMicrophone && oldConfiguration.cameraPosition != newConfiguration.cameraPosition {
                        handleMicrophoneConfigurationChange(enabled: newConfiguration.enableMicrophone)
                    } else {
                    }
                } catch {
                    delegate?.faceDetector(self, didEncounterError: error as? JAAKVisageError ?? JAAKVisageError(label: "Failed to restart after configuration update", code: "CONFIG_UPDATE_RESTART_FAILED"))
                }
            }
        } else {
            // Apply dynamic changes without restart
            self.configuration = newConfiguration
            applyDynamicConfigurationChanges(from: oldConfiguration, to: newConfiguration)
        }
    }
    
    /// Check if configuration changes require a full restart
    private func configurationRequiresRestart(from oldConfig: JAAKVisageConfiguration, to newConfig: JAAKVisageConfiguration) -> Bool {
        // These changes require restart
        // enableMicrophone is handled separately to avoid full restart
        return oldConfig.cameraPosition != newConfig.cameraPosition ||
               oldConfig.videoQuality != newConfig.videoQuality ||
               oldConfig.disableFaceDetection != newConfig.disableFaceDetection ||
               oldConfig.useOfflineModel != newConfig.useOfflineModel
    }
    
    /// Apply configuration changes that can be done dynamically
    private func applyDynamicConfigurationChanges(from oldConfig: JAAKVisageConfiguration, to newConfig: JAAKVisageConfiguration) {
        
        // Update UI components that can change dynamically
        
        // Handle microphone changes without full restart
        if oldConfig.enableMicrophone != newConfig.enableMicrophone {
            handleMicrophoneConfigurationChange(enabled: newConfig.enableMicrophone)
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
           oldConfig.autoRecorder != newConfig.autoRecorder {
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
        
        // Update the camera manager's microphone setup
        guard let cameraManager = cameraManager else {
            return
        }
        
        do {
            try cameraManager.updateMicrophoneConfiguration(enabled: enabled)
        } catch {
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
        }
    }
}

// MARK: - JAAKAssistanceMessageView

/// Assistance message view for displaying real-time positioning guidance
internal class JAAKAssistanceMessageView: UIView {
    
    // MARK: - Properties
    
    private let configuration: JAAKVisageConfiguration
    private var currentMessage: String = ""
    
    // UI Components
    private let backgroundView = UIView()
    private let messageLabel = UILabel()
    
    // MARK: - Initialization
    
    init(configuration: JAAKVisageConfiguration) {
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

// MARK: - JAAKStatusIndicatorView

/// Status indicator view for displaying system status messages (matching webcomponent status-indicator)
internal class JAAKStatusIndicatorView: UIView {
    
    // MARK: - Properties
    
    private let configuration: JAAKVisageConfiguration
    private var currentMessage: String = ""
    
    // UI Components
    private let backgroundView = UIView()
    private let messageLabel = UILabel()
    
    // MARK: - Initialization
    
    init(configuration: JAAKVisageConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Public Methods
    
    /// Show status message
    /// - Parameter message: status message to display
    func showStatus(_ message: String) {
        guard message != currentMessage else { return }
        
        currentMessage = message
        messageLabel.text = message
        
        // Show with animation if hidden
        if isHidden || alpha == 0.0 {
            show()
        }
    }
    
    /// Hide the status indicator
    func hideStatus() {
        currentMessage = ""
        hide()
    }
    
    // MARK: - Private Methods
    
    private func setupUI() {
        // Exact webcomponent styling:
        // background: rgba(0, 0, 0, 0.25)
        // backdrop-filter: blur(20px)
        // border-radius: 12px
        // border: 1px solid rgba(255, 255, 255, 0.1)
        
        backgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        backgroundView.layer.cornerRadius = 12
        backgroundView.layer.borderWidth = 1.0
        backgroundView.layer.borderColor = UIColor.white.withAlphaComponent(0.1).cgColor
        backgroundView.clipsToBounds = true
        
        // Blur effect (iOS equivalent of backdrop-filter: blur(20px))
        let blurEffect: UIBlurEffect
        if #available(iOS 13.0, *) {
            blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        } else {
            blurEffect = UIBlurEffect(style: .dark)
        }
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.isUserInteractionEnabled = false
        blurView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.insertSubview(blurView, at: 0)
        
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor)
        ])
        
        addSubview(backgroundView)
        
        // Message label - exact webcomponent styling:
        // color: #ffffff
        // font-size: 12px
        // font-weight: 500
        messageLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        messageLabel.textColor = .white
        messageLabel.textAlignment = .left
        messageLabel.numberOfLines = 1
        messageLabel.text = ""
        backgroundView.addSubview(messageLabel)
        
        // Layout - exact webcomponent positioning:
        // position: absolute
        // top: 16px
        // left: 16px
        // padding: 6px 10px
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
            // Background - positioned at top-left matching webcomponent (16px from top and left)
            backgroundView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 16),
            backgroundView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            backgroundView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            
            // Message label - positioned inside background with exact webcomponent padding (6px 10px)
            messageLabel.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 6),
            messageLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 10),
            messageLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -10),
            messageLabel.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -6)
        ])
    }
    
    private func show() {
        isHidden = false
        alpha = 0.0
        backgroundView.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        
        // Fade in animation matching webcomponent
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut], animations: {
            self.alpha = 1.0
            self.backgroundView.transform = .identity
        })
    }
    
    private func hide() {
        UIView.animate(withDuration: 0.2) {
            self.alpha = 0.0
            self.backgroundView.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        } completion: { _ in
            self.isHidden = true
        }
    }
}

import AVFoundation
import UIKit

/// Internal class for managing camera configuration and capture session
internal class JAAKCameraManager: NSObject {
    
    // MARK: - Properties
    
    private let captureSession = AVCaptureSession()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?
    
    // Configuration storage
    private var currentConfiguration: JAAKFaceDetectorConfiguration?
    
    // Recording outputs - use different approaches based on microphone setting
    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private var isCurrentlyRecording = false
    private var videoDimensions: CGSize?
    private var recordingStartTime: CMTime?
    private var recordingOutputURL: URL?
    
    private let videoDataOutputQueue = DispatchQueue(label: "com.jaak.facedetector.videoqueue", qos: .userInitiated)
    
    weak var delegate: JAAKCameraManagerDelegate?
    
    // MARK: - Public Methods
    
    /// Setup capture session with given configuration
    /// - Parameter configuration: detector configuration
    /// - Throws: JAAKFaceDetectorError if setup fails
    func setupCaptureSession(with configuration: JAAKFaceDetectorConfiguration) throws {
        print("🔧 [CameraManager] Setting up capture session...")
        // Camera validation removed for simplicity
        
        // Store configuration for later use
        self.currentConfiguration = configuration
        
        captureSession.beginConfiguration()
        print("🔧 [CameraManager] Session configuration started")
        
        // Set session preset
        if captureSession.canSetSessionPreset(configuration.videoQuality) {
            captureSession.sessionPreset = configuration.videoQuality
        }
        
        // Setup camera input with validation
        try setupCameraInput(position: configuration.cameraPosition, configuration: configuration)
        
        // Setup microphone input if permissions are available (always try)
        // The enableMicrophone configuration will control whether to use it in recording
        print("🎤 [CameraManager] Checking microphone authorization...")
        print("🎤 [CameraManager] Microphone authorized: \(JAAKPermissionManager.isMicrophoneAuthorized())")
        
        if JAAKPermissionManager.isMicrophoneAuthorized() {
            do {
                try setupMicrophoneInput()
                try setupAudioOutput()
                print("✅ [CameraManager] Microphone and audio output setup successful")
            } catch {
                print("⚠️ [CameraManager] Audio setup failed: \(error)")
                // Continue without microphone - don't fail the entire setup
                audioInput = nil
                audioOutput = nil
            }
        } else {
            print("🎤 [CameraManager] Microphone not authorized, skipping audio setup")
        }
        
        // Setup video output first
        try setupVideoOutput(with: configuration)
        
        
        // Video recording will be handled by AVAssetWriter during frame processing
        
        captureSession.commitConfiguration()
        print("✅ [CameraManager] Capture session configuration completed")
        
        // Debug: Check connections
        
        for input in captureSession.inputs {
            print("📥 [CameraManager] Input: \(input)")
        }
        
        for output in captureSession.outputs {
            print("📤 [CameraManager] Output: \(output)")
            if let videoOutput = output as? AVCaptureVideoDataOutput {
                print("🎬 [CameraManager] Video output connections: \(videoOutput.connections.count)")
                for connection in videoOutput.connections {
                    print("🔗 [CameraManager] Connection: \(connection), enabled: \(connection.isEnabled), active: \(connection.isActive)")
                }
            }
        }
    }
    
    /// Start capture session
    func startSession() {
        print("🎥 [CameraManager] Starting capture session...")
        if !captureSession.isRunning {
            print("🎥 [CameraManager] Session not running, starting now...")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
                
                // Wait a moment for session to fully start, then check connections
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.checkAndActivateConnections()
                    print("✅ [CameraManager] Capture session started successfully")
                }
            }
        } else {
            print("⚠️ [CameraManager] Session already running")
        }
    }
    
    /// Check and activate connections if needed
    private func checkAndActivateConnections() {
        
        for output in captureSession.outputs {
            if let videoOutput = output as? AVCaptureVideoDataOutput {
                for connection in videoOutput.connections {
                    print("🔗 [CameraManager] Connection status: enabled=\(connection.isEnabled), active=\(connection.isActive)")
                    
                    if connection.isEnabled && !connection.isActive {
                        print("⚡ [CameraManager] Connection is enabled but not active - forcing activation...")
                        
                        // Try to force connection activation by setting video orientation
                        if connection.isVideoOrientationSupported {
                            connection.videoOrientation = getCurrentVideoOrientation()
                            print("🔧 [CameraManager] Set video orientation to force activation")
                        }
                        
                        // Wait a bit and check again
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            
                        }
                        
                        // Check connection properties
                        print("🔧 [CameraManager] Connection input ports: \(connection.inputPorts.count)")
                        if let output = connection.output {
                            print("🔧 [CameraManager] Connection has output: \(type(of: output))")
                        }
                    } else if connection.isActive {
                        print("✅ [CameraManager] Connection is active and should be sending frames")
                    } else {
                        print("❌ [CameraManager] Connection is not enabled")
                    }
                }
            }
        }
    }
    
    /// Stop capture session
    func stopSession() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }
    
    /// Toggle camera between front and back
    /// - Parameter position: new camera position
    /// - Parameter configuration: detector configuration
    /// - Throws: JAAKFaceDetectorError if toggle fails
    func toggleCamera(to position: AVCaptureDevice.Position, configuration: JAAKFaceDetectorConfiguration) throws {
        print("🔄 [CameraManager] Toggling camera to position: \(position)")
        
        // Stop any active recording since camera change may affect recording state
        if isCurrentlyRecording {
            print("🎬 [CameraManager] Stopping recording due to camera toggle")
            stopRecording()
        }
        
        // Clear any existing recording state completely
        cleanupRecording()
        
        captureSession.beginConfiguration()
        
        // Remove current video input
        if let currentVideoInput = videoInput {
            captureSession.removeInput(currentVideoInput)
        }
        
        // Add new video input with validation
        try setupCameraInput(position: position, configuration: configuration)
        
        // Update video orientation for the new camera
        updateVideoOrientation()
        
        // Update mirroring for front camera
        if let videoConnection = videoOutput?.connection(with: .video) {
            videoConnection.isVideoMirrored = (position == .front)
        }
        
        captureSession.commitConfiguration()
        
        print("✅ [CameraManager] Camera toggled successfully to position: \(position)")
    }
    
    /// Get capture session for preview layer
    /// - Returns: AVCaptureSession instance
    func getCaptureSession() -> AVCaptureSession {
        return captureSession
    }
    
    /// Start recording video
    /// - Parameter outputURL: URL where to save the video
    func startRecording(to outputURL: URL) {
        guard !isCurrentlyRecording else { return }
        
        print("🎬 [CameraManager] Starting new recording...")
        print("🎬 [CameraManager] - Microphone enabled in config: \(currentConfiguration?.enableMicrophone ?? false)")
        print("🎬 [CameraManager] - Audio input available: \(audioInput != nil)")
        print("🎬 [CameraManager] - Audio output available: \(audioOutput != nil)")
        print("🎬 [CameraManager] - Previous audioWriterInput: \(audioWriterInput != nil)")
        
        recordingOutputURL = outputURL
        isCurrentlyRecording = true
        recordingStartTime = nil
        videoDimensions = nil
        
        // AssetWriter will be setup when first frame arrives
        print("🎬 [CameraManager] Recording started, waiting for first frame to setup AVAssetWriter")
    }
    
    /// Stop recording video
    func stopRecording() {
        guard isCurrentlyRecording else { return }
        
        isCurrentlyRecording = false
        finishRecording()
    }
    
    
    /// Check if currently recording
    /// - Returns: true if recording is in progress
    func isRecording() -> Bool {
        return isCurrentlyRecording
    }
    
    /// Update microphone configuration dynamically without restarting session
    /// - Parameter enabled: whether microphone should be enabled
    func updateMicrophoneConfiguration(enabled: Bool) throws {
        print("🎤 [CameraManager] Updating microphone configuration to: \(enabled)")
        
        // If currently recording, stop it since audio configuration will change
        let wasRecording = isCurrentlyRecording
        if wasRecording {
            print("🎬 [CameraManager] Stopping active recording due to microphone configuration change")
            stopRecording()
        }
        
        // Store the current configuration for recording decisions
        currentConfiguration?.enableMicrophone = enabled
        
        if enabled {
            // Request microphone permission if needed
            let microphoneAuthorized = JAAKPermissionManager.isMicrophoneAuthorized()
            print("🎤 [CameraManager] Current microphone authorization: \(microphoneAuthorized)")
            
            if !microphoneAuthorized {
                print("🎤 [CameraManager] Requesting microphone permission asynchronously...")
                
                // Request permission asynchronously to avoid blocking UI
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    JAAKPermissionManager.requestMicrophonePermission { granted in
                        print("🎤 [CameraManager] Microphone permission result: \(granted)")
                        
                        DispatchQueue.main.async {
                            guard let self = self else { return }
                            
                            if granted {
                                print("✅ [CameraManager] Microphone permission granted, setting up audio...")
                                do {
                                    try self.setupMicrophoneAfterPermission()
                                } catch {
                                    print("❌ [CameraManager] Failed to setup microphone after permission granted: \(error)")
                                }
                            } else {
                                print("⚠️ [CameraManager] Microphone permission denied - audio will be disabled")
                            }
                        }
                    }
                }
                return // Exit early, setup will continue asynchronously
            }
            
            // Now setup microphone if we have permissions
            // Add microphone if not already present
            if audioInput == nil {
                print("🎤 [CameraManager] Adding microphone input...")
                captureSession.beginConfiguration()
                do {
                    try setupMicrophoneInput()
                    try setupAudioOutput()
                    captureSession.commitConfiguration()
                    print("✅ [CameraManager] Microphone input and output added successfully")
                } catch {
                    captureSession.commitConfiguration()
                    throw error
                }
            } else {
                print("✅ [CameraManager] Microphone already configured")
            }
        } else {
            // Remove microphone if present
            if let audioInput = audioInput {
                print("🎤 [CameraManager] Removing microphone input...")
                captureSession.beginConfiguration()
                captureSession.removeInput(audioInput)
                self.audioInput = nil
                
                if let audioOutput = audioOutput {
                    captureSession.removeOutput(audioOutput)
                    self.audioOutput = nil
                }
                captureSession.commitConfiguration()
                print("✅ [CameraManager] Microphone input and output removed successfully")
                
                // Also clear any active audio writer input since microphone is disabled
                if audioWriterInput != nil {
                    print("🎤 [CameraManager] Clearing audio writer input since microphone is disabled")
                    audioWriterInput?.markAsFinished()
                    audioWriterInput = nil
                }
            } else {
                print("✅ [CameraManager] Microphone already disabled")
            }
        }
    }
    
    /// Setup microphone after permission has been granted asynchronously
    private func setupMicrophoneAfterPermission() throws {
        print("🎤 [CameraManager] Setting up microphone after permission granted...")
        
        // Add microphone if not already present
        if audioInput == nil {
            print("🎤 [CameraManager] Adding microphone input after permission...")
            captureSession.beginConfiguration()
            do {
                try setupMicrophoneInput()
                try setupAudioOutput()
                captureSession.commitConfiguration()
                print("✅ [CameraManager] Microphone input and output added successfully after permission")
            } catch {
                captureSession.commitConfiguration()
                throw error
            }
        } else {
            print("✅ [CameraManager] Microphone already configured after permission check")
        }
    }
    
    // MARK: - Private Methods
    
    private func setupCameraInput(position: AVCaptureDevice.Position, configuration: JAAKFaceDetectorConfiguration) throws {
        print("📷 [CameraManager] Setting up camera input for position: \(position)")
        // Get camera device for specified position (validation removed)
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            print("❌ [CameraManager] No camera device found for position: \(position)")
            throw JAAKFaceDetectorError(
                label: "No camera device found for position",
                code: "NO_CAMERA_FOR_POSITION"
            )
        }
        
        print("📷 [CameraManager] Camera device found: \(camera.localizedName)")
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                videoInput = input
                print("✅ [CameraManager] Camera input added successfully")
            } else {
                print("❌ [CameraManager] Cannot add camera input to session")
                throw JAAKFaceDetectorError(
                    label: "Cannot add camera input",
                    code: "CAMERA_INPUT_FAILED"
                )
            }
        } catch {
            throw JAAKFaceDetectorError(
                label: "Failed to create camera input",
                code: "CAMERA_INPUT_CREATION_FAILED",
                details: error
            )
        }
    }
    
    private func setupMicrophoneInput() throws {
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            throw JAAKFaceDetectorError(
                label: "Microphone device not found",
                code: "MICROPHONE_DEVICE_NOT_FOUND"
            )
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: microphone)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                audioInput = input
            } else {
                throw JAAKFaceDetectorError(
                    label: "Cannot add microphone input",
                    code: "MICROPHONE_INPUT_FAILED"
                )
            }
        } catch {
            throw JAAKFaceDetectorError(
                label: "Failed to create microphone input",
                code: "MICROPHONE_INPUT_CREATION_FAILED",
                details: error
            )
        }
    }
    
    private func setupAudioOutput() throws {
        print("🎤 [CameraManager] Setting up audio output...")
        let output = AVCaptureAudioDataOutput()
        
        // Use the same queue as video for synchronization
        output.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            audioOutput = output
            print("✅ [CameraManager] Audio output added successfully")
        } else {
            throw JAAKFaceDetectorError(
                label: "Cannot add audio output",
                code: "AUDIO_OUTPUT_FAILED"
            )
        }
    }
    
    private func setupVideoOutput(with configuration: JAAKFaceDetectorConfiguration) throws {
        print("📹 [CameraManager] Setting up video output following MediaPipe pattern...")
        let output = AVCaptureVideoDataOutput()
        
        // Follow MediaPipe example exactly
        let sampleBufferQueue = DispatchQueue(label: "sampleBufferQueue")
        output.setSampleBufferDelegate(self, queue: sampleBufferQueue)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [String(kCVPixelBufferPixelFormatTypeKey): kCMPixelFormat_32BGRA]
        
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            videoOutput = output
            print("✅ [CameraManager] Video output added to session successfully")
            
            // Set video orientation based on current device orientation
            updateVideoOrientation()
            print("📱 [CameraManager] Set video orientation based on device orientation")
            
            // Handle mirroring for front camera like MediaPipe example
            if output.connection(with: .video)?.isVideoOrientationSupported == true &&
               configuration.cameraPosition == .front {
                output.connection(with: .video)?.isVideoMirrored = true
                print("🪞 [CameraManager] Set video mirroring for front camera")
            }
            
            print("🔗 [CameraManager] Video connection configured successfully")
            
        } else {
            print("❌ [CameraManager] Cannot add video output to session")
            throw JAAKFaceDetectorError(
                label: "Cannot add video output",
                code: "VIDEO_OUTPUT_FAILED"
            )
        }
    }
    
    
    private func getCameraDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        )
        return discoverySession.devices.first
    }
    
    // MARK: - Orientation Management
    
    /// Get current video orientation based on device orientation
    private func getCurrentVideoOrientation() -> AVCaptureVideoOrientation {
        let currentOrientation = UIDevice.current.orientation
        
        switch currentOrientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeRight  // Camera is rotated 180° relative to device
        case .landscapeRight:
            return .landscapeLeft   // Camera is rotated 180° relative to device
        default:
            return .portrait
        }
    }
    
    /// Update video orientation for all connections
    func updateVideoOrientation() {
        let videoOrientation = getCurrentVideoOrientation()
        
        // Update video output connection
        if let videoConnection = videoOutput?.connection(with: .video),
           videoConnection.isVideoOrientationSupported {
            videoConnection.videoOrientation = videoOrientation
        }
        
        // Update any other video connections
        for output in captureSession.outputs {
            for connection in output.connections {
                if connection.isVideoOrientationSupported && connection.isActive {
                    connection.videoOrientation = videoOrientation
                }
            }
        }
        
        print("📱 [CameraManager] Updated video orientation to: \(videoOrientation.rawValue)")
    }
    
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension JAAKCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == videoOutput {
            // Always forward video frames to delegate for face detection
            delegate?.cameraManager(self, didOutput: sampleBuffer)
            
            // Process video frame for recording if active
            if isCurrentlyRecording {
                processVideoFrame(sampleBuffer)
            }
        } else if output == audioOutput {
            // Process audio sample for recording if active AND microphone is enabled
            let microphoneEnabled = currentConfiguration?.enableMicrophone ?? false
            print("🎤 [CameraManager] Audio frame received - recording: \(isCurrentlyRecording), micEnabled: \(microphoneEnabled), audioInput exists: \(audioInput != nil)")
            
            // Only process if recording, microphone enabled, and audio input still exists
            if isCurrentlyRecording && microphoneEnabled && audioInput != nil {
                processAudioFrame(sampleBuffer)
            } else if isCurrentlyRecording {
                print("🔇 [CameraManager] Skipping audio frame - microphone disabled or input removed")
            }
        }
    }
}

// MARK: - Video Recording Methods

extension JAAKCameraManager {
    
    private func processVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let outputURL = recordingOutputURL else { return }
        
        // Setup asset writer on first frame if not done yet
        if assetWriter == nil {
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let width = CVPixelBufferGetWidth(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                videoDimensions = CGSize(width: width, height: height)
                
                do {
                    try setupAssetWriter(outputURL: outputURL)
                    print("✅ [CameraManager] AVAssetWriter setup completed")
                } catch {
                    print("❌ [CameraManager] Failed to setup AVAssetWriter: \(error)")
                    let detectorError = JAAKFaceDetectorError(
                        label: "Failed to setup video recording",
                        code: "ASSET_WRITER_SETUP_FAILED",
                        details: error
                    )
                    delegate?.cameraManager(self, didFailWithError: detectorError)
                    return
                }
            }
        }
        
        // Start recording session on first frame
        if recordingStartTime == nil {
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            recordingStartTime = presentationTime
            assetWriter?.startSession(atSourceTime: presentationTime)
            print("🎬 [CameraManager] Recording session started")
        }
        
        // Append video frame
        if let videoWriterInput = videoWriterInput,
           let pixelBufferAdaptor = pixelBufferAdaptor,
           let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
           videoWriterInput.isReadyForMoreMediaData {
            
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }
    }
    
    private func processAudioFrame(_ sampleBuffer: CMSampleBuffer) {
        // Check if microphone is currently enabled in configuration
        let microphoneEnabled = currentConfiguration?.enableMicrophone ?? false
        
        // Only append audio if microphone is enabled AND audio writer input is configured and ready
        if microphoneEnabled {
            if let audioWriterInput = audioWriterInput {
                if audioWriterInput.isReadyForMoreMediaData {
                    audioWriterInput.append(sampleBuffer)
                    print("🎤 [CameraManager] Audio frame appended successfully (microphone enabled)")
                } else {
                    print("⚠️ [CameraManager] Audio writer input not ready for more data")
                }
            } else {
                print("⚠️ [CameraManager] No audio writer input available for audio frame")
            }
        } else {
            print("🔇 [CameraManager] Skipping audio frame - microphone disabled in configuration")
        }
    }
    
    private func setupAssetWriter(outputURL: URL) throws {
        guard let dimensions = videoDimensions else {
            throw JAAKFaceDetectorError(
                label: "Video dimensions not available",
                code: "VIDEO_DIMENSIONS_UNAVAILABLE"
            )
        }
        
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        // Create asset writer
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        
        // Video input settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(dimensions.width),
            AVVideoHeightKey: Int(dimensions.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2000000
            ]
        ]
        
        // Create video writer input
        videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriterInput?.expectsMediaDataInRealTime = true
        
        // Create pixel buffer adaptor
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput!,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        
        // Add video input to asset writer
        guard let assetWriter = assetWriter,
              let videoWriterInput = videoWriterInput else {
            throw JAAKFaceDetectorError(
                label: "Asset writer or video input is nil",
                code: "ASSET_WRITER_NIL"
            )
        }
        
        if assetWriter.canAdd(videoWriterInput) {
            assetWriter.add(videoWriterInput)
        } else {
            throw JAAKFaceDetectorError(
                label: "Cannot add video input to asset writer",
                code: "VIDEO_INPUT_ADD_FAILED"
            )
        }
        
        // Setup audio writer input if microphone is enabled AND available
        // Check both current configuration AND actual audio input presence
        let shouldIncludeAudio = currentConfiguration?.enableMicrophone == true && audioInput != nil
        
        print("🎤 [CameraManager] Determining audio inclusion for recording...")
        print("🎤 [CameraManager] - enableMicrophone: \(currentConfiguration?.enableMicrophone ?? false)")
        print("🎤 [CameraManager] - audioInput available: \(audioInput != nil)")
        print("🎤 [CameraManager] - audioOutput available: \(audioOutput != nil)")
        print("🎤 [CameraManager] - shouldIncludeAudio: \(shouldIncludeAudio)")
        
        if shouldIncludeAudio {
            print("🎤 [CameraManager] Setting up audio writer input...")
            
            guard currentConfiguration != nil else {
                print("❌ [CameraManager] No current configuration available")
                return
            }
            
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64000
            ]
            
            audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioWriterInput?.expectsMediaDataInRealTime = true
            
            if let audioWriterInput = audioWriterInput, assetWriter.canAdd(audioWriterInput) {
                assetWriter.add(audioWriterInput)
                print("✅ [CameraManager] Audio writer input added to asset writer successfully")
            } else {
                print("❌ [CameraManager] Cannot add audio writer input to asset writer")
                print("❌ [CameraManager] - audioWriterInput: \(audioWriterInput != nil)")
                print("❌ [CameraManager] - assetWriter.canAdd: \(audioWriterInput != nil ? assetWriter.canAdd(audioWriterInput!) : false)")
            }
        } else {
            print("📹 [CameraManager] Recording video-only (no audio)")
            print("📹 [CameraManager] - config available: \(currentConfiguration != nil)")
            print("📹 [CameraManager] - enableMicrophone: \(currentConfiguration?.enableMicrophone ?? false)")
            print("📹 [CameraManager] - audioInput available: \(audioInput != nil)")
        }
        
        // Start writing
        if !assetWriter.startWriting() {
            throw JAAKFaceDetectorError(
                label: "Failed to start asset writer",
                code: "ASSET_WRITER_START_FAILED"
            )
        }
    }
    
    private func finishRecording() {
        guard let assetWriter = assetWriter,
              let outputURL = recordingOutputURL else { return }
        
        // Check if asset writer is in a valid state to finish writing
        guard assetWriter.status == .writing else {
            print("⚠️ [CameraManager] Cannot finish recording - assetWriter status: \(assetWriter.status.rawValue)")
            cleanupRecording()
            return
        }
        
        // Mark inputs as finished
        videoWriterInput?.markAsFinished()
        audioWriterInput?.markAsFinished()
        
        // Finish writing
        assetWriter.finishWriting { [weak self] in
            DispatchQueue.main.async {
                if assetWriter.status == .completed {
                    print("✅ [CameraManager] Video recording completed successfully")
                    self?.delegate?.cameraManager(self!, didFinishRecordingTo: outputURL)
                } else {
                    print("❌ [CameraManager] Video recording failed: \(assetWriter.error?.localizedDescription ?? "Unknown error")")
                    let error = JAAKFaceDetectorError(
                        label: "Video recording failed",
                        code: "VIDEO_RECORDING_FAILED",
                        details: assetWriter.error
                    )
                    self?.delegate?.cameraManager(self!, didFailWithError: error)
                }
                
                // Clean up
                self?.cleanupRecording()
            }
        }
    }
    
    private func cleanupRecording() {
        print("🧹 [CameraManager] Cleaning up recording state...")
        print("🧹 [CameraManager] - assetWriter: \(assetWriter != nil)")
        print("🧹 [CameraManager] - audioWriterInput: \(audioWriterInput != nil)")
        print("🧹 [CameraManager] - videoWriterInput: \(videoWriterInput != nil)")
        
        assetWriter = nil
        videoWriterInput = nil
        audioWriterInput = nil
        pixelBufferAdaptor = nil
        videoDimensions = nil
        recordingStartTime = nil
        recordingOutputURL = nil
        
        print("✅ [CameraManager] Recording state cleaned up completely")
        
        // Movie file output cleanup is handled by the delegate
    }
    
}

// MARK: - JAAKCameraManagerDelegate

protocol JAAKCameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: JAAKCameraManager, didOutput sampleBuffer: CMSampleBuffer)
    func cameraManager(_ manager: JAAKCameraManager, didFinishRecordingTo outputURL: URL)
    func cameraManager(_ manager: JAAKCameraManager, didFailWithError error: JAAKFaceDetectorError)
}

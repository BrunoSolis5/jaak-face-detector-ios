import AVFoundation
import UIKit

/// Internal class for managing camera configuration and capture session
internal class JAAKCameraManager: NSObject {
    
    // MARK: - Properties
    
    private let captureSession = AVCaptureSession()
    private var videoInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    
    // Configuration storage
    private var currentConfiguration: JAAKVisageConfiguration?
    
    // Recording outputs - video only (no audio)
    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
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
    /// - Throws: JAAKVisageError if setup fails
    func setupCaptureSession(with configuration: JAAKVisageConfiguration) throws {
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
        
        // Microphone/audio removed - videos are always recorded without audio
        
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
    /// - Throws: JAAKVisageError if toggle fails
    func toggleCamera(to position: AVCaptureDevice.Position, configuration: JAAKVisageConfiguration) throws {
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
        
        print("🎬 [CameraManager] Starting new recording (video only)...")
        
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
    
    // Microphone functionality removed - videos recorded without audio
    
    
    // MARK: - Private Methods
    
    private func setupCameraInput(position: AVCaptureDevice.Position, configuration: JAAKVisageConfiguration) throws {
        print("📷 [CameraManager] Setting up camera input for position: \(position)")
        // Get camera device for specified position (validation removed)
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            print("❌ [CameraManager] No camera device found for position: \(position)")
            throw JAAKVisageError(
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
                throw JAAKVisageError(
                    label: "Cannot add camera input",
                    code: "CAMERA_INPUT_FAILED"
                )
            }
        } catch {
            throw JAAKVisageError(
                label: "Failed to create camera input",
                code: "CAMERA_INPUT_CREATION_FAILED",
                details: error
            )
        }
    }
    
    
    
    private func setupVideoOutput(with configuration: JAAKVisageConfiguration) throws {
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
            throw JAAKVisageError(
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
        }
        // Audio processing removed - video-only recording
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
                    let detectorError = JAAKVisageError(
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
    
    
    private func setupAssetWriter(outputURL: URL) throws {
        guard let dimensions = videoDimensions else {
            throw JAAKVisageError(
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
            throw JAAKVisageError(
                label: "Asset writer or video input is nil",
                code: "ASSET_WRITER_NIL"
            )
        }
        
        if assetWriter.canAdd(videoWriterInput) {
            assetWriter.add(videoWriterInput)
        } else {
            throw JAAKVisageError(
                label: "Cannot add video input to asset writer",
                code: "VIDEO_INPUT_ADD_FAILED"
            )
        }
        
        // Audio removed - always record video-only
        print("📹 [CameraManager] Recording video-only (no audio)")
        
        // Start writing
        if !assetWriter.startWriting() {
            throw JAAKVisageError(
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
        
        // Mark video input as finished (audio removed)
        videoWriterInput?.markAsFinished()
        
        // Finish writing
        assetWriter.finishWriting { [weak self] in
            DispatchQueue.main.async {
                if assetWriter.status == .completed {
                    print("✅ [CameraManager] Video recording completed successfully")
                    self?.delegate?.cameraManager(self!, didFinishRecordingTo: outputURL)
                } else {
                    print("❌ [CameraManager] Video recording failed: \(assetWriter.error?.localizedDescription ?? "Unknown error")")
                    let error = JAAKVisageError(
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
        print("🧹 [CameraManager] - videoWriterInput: \(videoWriterInput != nil)")
        
        assetWriter = nil
        videoWriterInput = nil
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
    func cameraManager(_ manager: JAAKCameraManager, didFailWithError error: JAAKVisageError)
}

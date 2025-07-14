import AVFoundation
import UIKit

/// Internal class for managing camera configuration and capture session
internal class JAAKCameraManager: NSObject {
    
    // MARK: - Properties
    
    private let captureSession = AVCaptureSession()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    
    // AVAssetWriter for video recording (compatible with face detection)
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
        
        captureSession.beginConfiguration()
        print("🔧 [CameraManager] Session configuration started")
        
        // Set session preset
        if captureSession.canSetSessionPreset(configuration.videoQuality) {
            captureSession.sessionPreset = configuration.videoQuality
        }
        
        // Setup camera input with validation
        try setupCameraInput(position: configuration.cameraPosition, configuration: configuration)
        
        // Setup microphone input if enabled
        if configuration.enableMicrophone {
            try setupMicrophoneInput()
        }
        
        // Setup video output first
        try setupVideoOutput(with: configuration)
        
        // Video recording will be handled by AVAssetWriter during frame processing
        
        captureSession.commitConfiguration()
        print("✅ [CameraManager] Capture session configuration completed")
        
        // Debug: Check connections
        print("🔍 [CameraManager] Session inputs: \(captureSession.inputs.count)")
        print("🔍 [CameraManager] Session outputs: \(captureSession.outputs.count)")
        
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
        print("🔍 [CameraManager] Checking connections after session start...")
        
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
                            print("🔍 [CameraManager] Rechecking connection after forcing activation: active=\(connection.isActive)")
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
            if let connections = output.connections as? [AVCaptureConnection] {
                for connection in connections {
                    if connection.isVideoOrientationSupported && connection.isActive {
                        connection.videoOrientation = videoOrientation
                    }
                }
            }
        }
        
        print("📱 [CameraManager] Updated video orientation to: \(videoOrientation.rawValue)")
    }
    
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension JAAKCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Always forward to delegate for face detection
        delegate?.cameraManager(self, didOutput: sampleBuffer)
        
        // Process frame for recording if active
        if isCurrentlyRecording {
            processVideoFrame(sampleBuffer)
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
        if let videoWriterInput = videoWriterInput,
           assetWriter!.canAdd(videoWriterInput) {
            assetWriter!.add(videoWriterInput)
        } else {
            throw JAAKFaceDetectorError(
                label: "Cannot add video input to asset writer",
                code: "VIDEO_INPUT_ADD_FAILED"
            )
        }
        
        // Start writing
        if !assetWriter!.startWriting() {
            throw JAAKFaceDetectorError(
                label: "Failed to start asset writer",
                code: "ASSET_WRITER_START_FAILED"
            )
        }
    }
    
    private func finishRecording() {
        guard let assetWriter = assetWriter,
              let outputURL = recordingOutputURL else { return }
        
        // Mark inputs as finished
        videoWriterInput?.markAsFinished()
        
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
        assetWriter = nil
        videoWriterInput = nil
        audioWriterInput = nil
        pixelBufferAdaptor = nil
        videoDimensions = nil
        recordingStartTime = nil
        recordingOutputURL = nil
    }
    
    /// Capture still image from current video frame
    /// - Parameter completion: completion handler with image data or error
    func captureStillImage(completion: @escaping (Result<Data, JAAKFaceDetectorError>) -> Void) {
        print("📸 [CameraManager] Capturing still image...")
        
        guard captureSession.isRunning else {
            let error = JAAKFaceDetectorError(
                label: "Cannot capture image - camera session not running",
                code: "SESSION_NOT_RUNNING"
            )
            completion(.failure(error))
            return
        }
        
        // Create photo output if not exists
        let photoOutput = AVCapturePhotoOutput()
        
        guard captureSession.canAddOutput(photoOutput) else {
            let error = JAAKFaceDetectorError(
                label: "Cannot add photo output to session",
                code: "PHOTO_OUTPUT_FAILED"
            )
            completion(.failure(error))
            return
        }
        
        // Add photo output temporarily
        captureSession.addOutput(photoOutput)
        
        // Configure photo settings
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.isHighResolutionPhotoEnabled = true
        
        // Create delegate for photo capture
        let photoDelegate = PhotoCaptureDelegate { result in
            // Remove photo output after capture
            self.captureSession.removeOutput(photoOutput)
            completion(result)
        }
        
        // Capture photo
        photoOutput.capturePhoto(with: photoSettings, delegate: photoDelegate)
    }
}

// MARK: - PhotoCaptureDelegate

private class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<Data, JAAKFaceDetectorError>) -> Void
    
    init(completion: @escaping (Result<Data, JAAKFaceDetectorError>) -> Void) {
        self.completion = completion
        super.init()
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            let detectorError = JAAKFaceDetectorError(
                label: "Photo capture failed",
                code: "PHOTO_CAPTURE_FAILED",
                details: error
            )
            completion(.failure(detectorError))
            return
        }
        
        guard let imageData = photo.fileDataRepresentation() else {
            let error = JAAKFaceDetectorError(
                label: "Could not get image data from photo",
                code: "IMAGE_DATA_UNAVAILABLE"
            )
            completion(.failure(error))
            return
        }
        
        print("📸 [PhotoCaptureDelegate] Successfully captured photo: \(imageData.count) bytes")
        completion(.success(imageData))
    }
}

// MARK: - JAAKCameraManagerDelegate

protocol JAAKCameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: JAAKCameraManager, didOutput sampleBuffer: CMSampleBuffer)
    func cameraManager(_ manager: JAAKCameraManager, didFinishRecordingTo outputURL: URL)
    func cameraManager(_ manager: JAAKCameraManager, didFailWithError error: JAAKFaceDetectorError)
}
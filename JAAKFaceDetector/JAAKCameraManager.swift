import AVFoundation
import UIKit

/// Internal class for managing camera configuration and capture session
internal class JAAKCameraManager: NSObject {
    
    // MARK: - Properties
    
    private let captureSession = AVCaptureSession()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    
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
        
        // Setup video output
        try setupVideoOutput()
        
        // Setup movie file output for recording
        // Temporarily disabled to test if it conflicts with video data output
        // try setupMovieFileOutput()
        print("⚠️ [CameraManager] MovieFileOutput temporarily disabled for testing")
        
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
                        print("⚡ [CameraManager] Connection is enabled but not active")
                        
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
        captureSession.beginConfiguration()
        
        // Remove current video input
        if let currentVideoInput = videoInput {
            captureSession.removeInput(currentVideoInput)
        }
        
        // Add new video input with validation
        try setupCameraInput(position: position, configuration: configuration)
        
        captureSession.commitConfiguration()
    }
    
    /// Get capture session for preview layer
    /// - Returns: AVCaptureSession instance
    func getCaptureSession() -> AVCaptureSession {
        return captureSession
    }
    
    /// Start recording video
    /// - Parameter outputURL: URL where to save the video
    func startRecording(to outputURL: URL) {
        movieFileOutput?.startRecording(to: outputURL, recordingDelegate: self)
    }
    
    /// Stop recording video
    func stopRecording() {
        movieFileOutput?.stopRecording()
    }
    
    /// Check if currently recording
    /// - Returns: true if recording is in progress
    func isRecording() -> Bool {
        return movieFileOutput?.isRecording ?? false
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
    
    private func setupVideoOutput() throws {
        print("📹 [CameraManager] Setting up video output...")
        let output = AVCaptureVideoDataOutput()
        
        // Configure video settings first
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        // Set delegate immediately since we don't have MovieFileOutput conflict
        output.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        print("📹 [CameraManager] Video output configured with delegate: \(String(describing: output.sampleBufferDelegate))")
        
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            videoOutput = output
            print("✅ [CameraManager] Video output added to session successfully")
        } else {
            print("❌ [CameraManager] Cannot add video output to session")
            throw JAAKFaceDetectorError(
                label: "Cannot add video output",
                code: "VIDEO_OUTPUT_FAILED"
            )
        }
    }
    
    private func setupMovieFileOutput() throws {
        let output = AVCaptureMovieFileOutput()
        
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            movieFileOutput = output
        } else {
            throw JAAKFaceDetectorError(
                label: "Cannot add movie file output",
                code: "MOVIE_OUTPUT_FAILED"
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
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension JAAKCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("🎬🎬🎬 [CameraManager] *** FRAME RECEIVED *** Sample buffer captured, forwarding to delegate")
        delegate?.cameraManager(self, didOutput: sampleBuffer)
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension JAAKCameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            let detectorError = JAAKFaceDetectorError(
                label: "Video recording failed",
                code: "VIDEO_RECORDING_FAILED",
                details: error
            )
            delegate?.cameraManager(self, didFailWithError: detectorError)
        } else {
            delegate?.cameraManager(self, didFinishRecordingTo: outputFileURL)
        }
    }
}

// MARK: - JAAKCameraManagerDelegate

protocol JAAKCameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: JAAKCameraManager, didOutput sampleBuffer: CMSampleBuffer)
    func cameraManager(_ manager: JAAKCameraManager, didFinishRecordingTo outputURL: URL)
    func cameraManager(_ manager: JAAKCameraManager, didFailWithError error: JAAKFaceDetectorError)
}
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
    private var deviceValidator: JAAKDeviceValidator?
    
    weak var delegate: JAAKCameraManagerDelegate?
    
    // MARK: - Public Methods
    
    /// Setup capture session with given configuration
    /// - Parameter configuration: detector configuration
    /// - Throws: JAAKFaceDetectorError if setup fails
    func setupCaptureSession(with configuration: JAAKFaceDetectorConfiguration) throws {
        // Initialize device validator
        deviceValidator = JAAKDeviceValidator(configuration: configuration)
        
        // Validate that we have at least one allowed camera
        guard let validator = deviceValidator, validator.hasAllowedCameras() else {
            throw JAAKFaceDetectorError(
                label: "No allowed camera devices found",
                code: "NO_ALLOWED_CAMERAS"
            )
        }
        
        captureSession.beginConfiguration()
        
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
        try setupMovieFileOutput()
        
        captureSession.commitConfiguration()
    }
    
    /// Start capture session
    func startSession() {
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
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
        // Get validated camera device
        guard let validator = deviceValidator else {
            throw JAAKFaceDetectorError(
                label: "Device validator not initialized",
                code: "DEVICE_VALIDATOR_NIL"
            )
        }
        
        guard let camera = validator.getFirstAllowedDevice(for: position) else {
            throw JAAKFaceDetectorError(
                label: "No allowed camera device found for position",
                code: "NO_ALLOWED_CAMERA_FOR_POSITION"
            )
        }
        
        // Double-check validation result
        let validationResult = validator.validateDevice(camera)
        guard validationResult.isAllowed else {
            throw JAAKFaceDetectorError(
                label: "Camera device validation failed: \(validationResult.errorMessage ?? "Unknown reason")",
                code: "CAMERA_VALIDATION_FAILED"
            )
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                videoInput = input
            } else {
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
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            videoOutput = output
        } else {
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
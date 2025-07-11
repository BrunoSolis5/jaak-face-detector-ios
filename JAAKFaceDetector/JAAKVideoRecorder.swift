import AVFoundation
import UIKit

/// Internal class for managing video recording operations
internal class JAAKVideoRecorder: NSObject {
    
    // MARK: - Properties
    
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var isCurrentlyRecording = false
    
    private let configuration: JAAKFaceDetectorConfiguration
    weak var delegate: JAAKVideoRecorderDelegate?
    
    // MARK: - Initialization
    
    init(configuration: JAAKFaceDetectorConfiguration) {
        self.configuration = configuration
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Start recording video
    /// - Parameters:
    ///   - cameraManager: camera manager instance
    ///   - completion: completion handler with result
    func startRecording(with cameraManager: JAAKCameraManager, completion: @escaping (Result<JAAKFileResult, JAAKFaceDetectorError>) -> Void) {
        guard !isCurrentlyRecording else {
            let error = JAAKFaceDetectorError(
                label: "Recording already in progress",
                code: "RECORDING_IN_PROGRESS"
            )
            completion(.failure(error))
            return
        }
        
        // Generate unique output URL
        let outputURL = generateOutputURL()
        
        // Start recording
        cameraManager.startRecording(to: outputURL)
        isCurrentlyRecording = true
        recordingStartTime = Date()
        
        // Start timer for recording duration
        startRecordingTimer(cameraManager: cameraManager, completion: completion)
        
        // Notify delegate
        print("🎬 [VideoRecorder] Recording started, notifying delegate: \(String(describing: delegate))")
        delegate?.videoRecorder(self, didStartRecording: outputURL)
    }
    
    /// Stop recording video
    /// - Parameter cameraManager: camera manager instance
    func stopRecording(with cameraManager: JAAKCameraManager) {
        guard isCurrentlyRecording else { return }
        
        cameraManager.stopRecording()
        stopRecordingTimer()
        isCurrentlyRecording = false
        recordingStartTime = nil
    }
    
    /// Get current recording progress (0.0 to 1.0)
    /// - Returns: recording progress or 0.0 if not recording
    func getRecordingProgress() -> Float {
        guard let startTime = recordingStartTime else { return 0.0 }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let progress = Float(elapsed / configuration.videoDuration)
        
        return min(progress, 1.0)
    }
    
    /// Check if currently recording
    /// - Returns: true if recording is active
    func isRecording() -> Bool {
        return isCurrentlyRecording
    }
    
    /// Get remaining recording time
    /// - Returns: remaining time in seconds
    func getRemainingTime() -> TimeInterval {
        guard let startTime = recordingStartTime else { return 0.0 }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let remaining = configuration.videoDuration - elapsed
        
        return max(remaining, 0.0)
    }
    
    /// Take a snapshot from current camera feed
    /// - Parameters:
    ///   - sampleBuffer: current video frame
    ///   - completion: completion handler with result
    func takeSnapshot(from sampleBuffer: CMSampleBuffer, completion: @escaping (Result<JAAKFileResult, JAAKFaceDetectorError>) -> Void) {
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            let error = JAAKFaceDetectorError(
                label: "Failed to get pixel buffer from sample",
                code: "PIXEL_BUFFER_FAILED"
            )
            completion(.failure(error))
            return
        }
        
        // Convert pixel buffer to UIImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            let error = JAAKFaceDetectorError(
                label: "Failed to create CGImage from pixel buffer",
                code: "CGIMAGE_CREATION_FAILED"
            )
            completion(.failure(error))
            return
        }
        
        let image = UIImage(cgImage: cgImage)
        
        // Convert to JPEG data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            let error = JAAKFaceDetectorError(
                label: "Failed to convert image to JPEG data",
                code: "IMAGE_CONVERSION_FAILED"
            )
            completion(.failure(error))
            return
        }
        
        // Create file result
        let base64String = imageData.base64EncodedString()
        let fileName = "snapshot_\(Int(Date().timeIntervalSince1970)).jpg"
        
        let fileResult = JAAKFileResult(
            data: imageData,
            base64: base64String,
            mimeType: "image/jpeg",
            fileName: fileName,
            fileSize: imageData.count
        )
        
        completion(.success(fileResult))
    }
    
    // MARK: - Private Methods
    
    private func generateOutputURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "video_\(Int(Date().timeIntervalSince1970)).mp4"
        return documentsPath.appendingPathComponent(fileName)
    }
    
    private func startRecordingTimer(cameraManager: JAAKCameraManager, completion: @escaping (Result<JAAKFileResult, JAAKFaceDetectorError>) -> Void) {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Update progress
            let progress = self.getRecordingProgress()
            self.delegate?.videoRecorder(self, didUpdateProgress: progress)
            
            // Check if recording should stop
            if progress >= 1.0 {
                self.stopRecording(with: cameraManager)
                
                // Recording completed, we'll get the file via delegate
                // This completion will be called from the file output delegate
                self.pendingCompletion = completion
            }
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    private var pendingCompletion: ((Result<JAAKFileResult, JAAKFaceDetectorError>) -> Void)?
    
    /// Handle successful video recording completion
    /// - Parameter outputURL: URL of the recorded video file
    func handleRecordingCompletion(_ outputURL: URL) {
        // Convert video file to JAAKFileResult
        do {
            let videoData = try Data(contentsOf: outputURL)
            let base64String = videoData.base64EncodedString()
            let fileName = outputURL.lastPathComponent
            
            let fileResult = JAAKFileResult(
                data: videoData,
                base64: base64String,
                mimeType: "video/mp4",
                fileName: fileName,
                fileSize: videoData.count
            )
            
            pendingCompletion?(.success(fileResult))
            pendingCompletion = nil
            
            // Clean up temporary file
            try? FileManager.default.removeItem(at: outputURL)
            
        } catch {
            let detectorError = JAAKFaceDetectorError(
                label: "Failed to process recorded video",
                code: "VIDEO_PROCESSING_FAILED",
                details: error
            )
            pendingCompletion?(.failure(detectorError))
            pendingCompletion = nil
        }
    }
    
    /// Handle video recording error
    /// - Parameter error: the error that occurred
    func handleRecordingError(_ error: JAAKFaceDetectorError) {
        pendingCompletion?(.failure(error))
        pendingCompletion = nil
        
        isCurrentlyRecording = false
        recordingStartTime = nil
        stopRecordingTimer()
    }
}

// MARK: - JAAKVideoRecorderDelegate

protocol JAAKVideoRecorderDelegate: AnyObject {
    func videoRecorder(_ recorder: JAAKVideoRecorder, didStartRecording outputURL: URL)
    func videoRecorder(_ recorder: JAAKVideoRecorder, didUpdateProgress progress: Float)
    func videoRecorder(_ recorder: JAAKVideoRecorder, didFinishRecording fileResult: JAAKFileResult)
    func videoRecorder(_ recorder: JAAKVideoRecorder, didFailWithError error: JAAKFaceDetectorError)
}
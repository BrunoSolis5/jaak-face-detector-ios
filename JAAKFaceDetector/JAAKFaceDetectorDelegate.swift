import Foundation

/// File result structure for captured files
public struct JAAKFileResult {
    public let data: Data
    public let base64: String
    public let mimeType: String?
    public let fileName: String?
    public let fileSize: Int
    
    public init(data: Data, base64: String, mimeType: String?, fileName: String?, fileSize: Int) {
        self.data = data
        self.base64 = base64
        self.mimeType = mimeType
        self.fileName = fileName
        self.fileSize = fileSize
    }
}

/// Face detection message structure
public struct JAAKFaceDetectionMessage {
    public let label: String
    public let details: String?
    public let faceExists: Bool
    public let correctPosition: Bool
    
    public init(label: String, details: String?, faceExists: Bool, correctPosition: Bool) {
        self.label = label
        self.details = details
        self.faceExists = faceExists
        self.correctPosition = correctPosition
    }
}

/// Delegate protocol for JAAKFaceDetector events
public protocol JAAKFaceDetectorSDKDelegate: AnyObject {
    /// Called when the detector status changes
    func faceDetector(_ detector: JAAKFaceDetectorSDK, didUpdateStatus status: JAAKFaceDetectorStatus)
    
    /// Called when an error occurs
    func faceDetector(_ detector: JAAKFaceDetectorSDK, didEncounterError error: JAAKFaceDetectorError)
    
    /// Called when a file is captured (video)
    func faceDetector(_ detector: JAAKFaceDetectorSDK, didCaptureFile result: JAAKFileResult)
    
    /// Called when face detection provides feedback
    func faceDetector(_ detector: JAAKFaceDetectorSDK, didDetectFace message: JAAKFaceDetectionMessage)
}
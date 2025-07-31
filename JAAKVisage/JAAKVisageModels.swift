import Foundation

/// Status enumeration for JAAKVisage component states
public enum JAAKVisageStatus: String, CaseIterable {
    case notLoaded = "not-loaded"
    case loading = "loading"
    case loaded = "loaded"
    case recording = "recording"
    case error = "error"
    case running = "running"
    case finished = "finished"
    case stopped = "stopped"
}

/// Error types for JAAKVisage
public enum JAAKVisageErrorType: String, CaseIterable {
    case modelLoading = "model-loading"
    case cameraAccess = "camera-access"
    case faceDetection = "face-detection"
    case videoRecording = "video-recording"
    case permissionDenied = "permission-denied"
    case deviceNotSupported = "device-not-supported"
}

/// Error structure for JAAKVisage
public struct JAAKVisageError: LocalizedError {
    public let label: String
    public let code: String?
    public let details: Any?
    
    public var errorDescription: String? { 
        return label 
    }
    
    public init(label: String, code: String? = nil, details: Any? = nil) {
        self.label = label
        self.code = code
        self.details = details
    }
}
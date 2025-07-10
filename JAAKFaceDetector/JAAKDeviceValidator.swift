import AVFoundation
import UIKit

/// Security validation for camera devices
internal class JAAKDeviceValidator {
    
    // MARK: - Types
    
    enum ValidationResult {
        case allowed
        case blocked(reason: String)
        case suspicious(reason: String)
    }
    
    struct DeviceInfo {
        let uniqueID: String
        let localizedName: String
        let modelID: String
        let manufacturer: String
        let deviceType: AVCaptureDevice.DeviceType
        let position: AVCaptureDevice.Position
        let isVirtual: Bool
        let capabilities: [String]
    }
    
    // MARK: - Properties
    
    private let configuration: JAAKFaceDetectorConfiguration
    private let knownVirtualDevices: Set<String>
    private let suspiciousPatterns: [String]
    
    // MARK: - Initialization
    
    init(configuration: JAAKFaceDetectorConfiguration) {
        self.configuration = configuration
        
        // Known virtual camera software patterns
        self.knownVirtualDevices = [
            "obs",
            "virtual",
            "simulator",
            "fake",
            "cam",
            "screen",
            "desktop",
            "capture",
            "broadcast",
            "streaming",
            "software",
            "emulator"
        ]
        
        // Suspicious device name patterns
        self.suspiciousPatterns = [
            "OBS Virtual Camera",
            "ManyCam",
            "Snap Camera",
            "CamTwist",
            "Wirecast",
            "XSplit",
            "Logitech Capture",
            "NVIDIA Broadcast",
            "Elgato Stream Deck",
            "Blackmagic"
        ]
    }
    
    // MARK: - Public Methods
    
    /// Validate if a camera device is allowed
    /// - Parameter device: AVCaptureDevice to validate
    /// - Returns: ValidationResult indicating if device is allowed
    func validateDevice(_ device: AVCaptureDevice) -> ValidationResult {
        let deviceInfo = extractDeviceInfo(device)
        
        // Check whitelist first (if configured)
        if !configuration.allowedCameraDevices.isEmpty {
            if !configuration.allowedCameraDevices.contains(deviceInfo.uniqueID) {
                return .blocked(reason: "Device not in whitelist")
            }
        }
        
        // Check blacklist
        if configuration.blockedCameraDevices.contains(deviceInfo.uniqueID) {
            return .blocked(reason: "Device in blacklist")
        }
        
        // Check for virtual cameras
        if deviceInfo.isVirtual {
            return .blocked(reason: "Virtual camera detected")
        }
        
        // Check for suspicious patterns
        if let suspiciousReason = checkSuspiciousPatterns(deviceInfo) {
            return .suspicious(reason: suspiciousReason)
        }
        
        // Additional security checks
        if let securityIssue = performSecurityChecks(deviceInfo) {
            return .blocked(reason: securityIssue)
        }
        
        return .allowed
    }
    
    /// Get available device types based on iOS version
    /// - Returns: Array of available AVCaptureDevice.DeviceType
    private func getAvailableDeviceTypes() -> [AVCaptureDevice.DeviceType] {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInTelephotoCamera,
            .builtInDualCamera
        ]
        
        // Add iOS 11.1+ device types
        if #available(iOS 11.1, *) {
            deviceTypes.append(.builtInTrueDepthCamera)
        }
        
        // Add iOS 13.0+ device types
        if #available(iOS 13.0, *) {
            deviceTypes.append(.builtInUltraWideCamera)
        }
        
        // Add iOS 17.0+ device types
        if #available(iOS 17.0, *) {
            deviceTypes.append(.external)
        }
        
        return deviceTypes
    }
    
    /// Get all available camera devices with their validation status
    /// - Returns: Array of tuples with device and validation result
    func getAllDevicesWithValidation() -> [(AVCaptureDevice, ValidationResult)] {
        // Return empty array in simulator to avoid device enumeration issues
        #if targetEnvironment(simulator)
        return []
        #else
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: getAvailableDeviceTypes(),
            mediaType: .video,
            position: .unspecified
        )
        
        return discoverySession.devices.map { device in
            (device, validateDevice(device))
        }
        #endif
    }
    
    /// Get the first allowed camera device for given position
    /// - Parameter position: Camera position preference
    /// - Returns: First allowed device or nil
    func getFirstAllowedDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let devicesWithValidation = getAllDevicesWithValidation()
        
        // First try to find device with exact position
        for (device, validation) in devicesWithValidation {
            if device.position == position && validation.isAllowed {
                return device
            }
        }
        
        // If no device found with exact position, try any allowed device
        for (device, validation) in devicesWithValidation {
            if validation.isAllowed {
                return device
            }
        }
        
        return nil
    }
    
    /// Check if any allowed cameras are available
    /// - Returns: True if at least one camera is allowed
    func hasAllowedCameras() -> Bool {
        let devicesWithValidation = getAllDevicesWithValidation()
        return devicesWithValidation.contains { $0.1.isAllowed }
    }
    
    // MARK: - Private Methods
    
    private func extractDeviceInfo(_ device: AVCaptureDevice) -> DeviceInfo {
        let capabilities = device.formats.map { format in
            CMFormatDescriptionGetMediaSubType(format.formatDescription).toString()
        }
        
        // Get manufacturer with iOS version check
        let manufacturer: String
        if #available(iOS 14.0, *) {
            manufacturer = device.manufacturer
        } else {
            manufacturer = "Unknown" // Not available in iOS < 14.0
        }
        
        return DeviceInfo(
            uniqueID: device.uniqueID,
            localizedName: device.localizedName,
            modelID: device.modelID,
            manufacturer: manufacturer,
            deviceType: device.deviceType,
            position: device.position,
            isVirtual: isVirtualDevice(device),
            capabilities: capabilities
        )
    }
    
    private func isVirtualDevice(_ device: AVCaptureDevice) -> Bool {
        let deviceName = device.localizedName.lowercased()
        let modelID = device.modelID.lowercased()
        let uniqueID = device.uniqueID.lowercased()
        
        // Check against known virtual device patterns
        for pattern in knownVirtualDevices {
            if deviceName.contains(pattern) || 
               modelID.contains(pattern) || 
               uniqueID.contains(pattern) {
                return true
            }
        }
        
        // Check if device type indicates virtual camera (iOS 17.0+ only)
        if #available(iOS 17.0, *) {
            if device.deviceType == .external {
                // External devices are more likely to be virtual cameras
                return checkExternalDeviceForVirtual(device)
            }
        }
        
        return false
    }
    
    private func checkExternalDeviceForVirtual(_ device: AVCaptureDevice) -> Bool {
        let deviceName = device.localizedName.lowercased()
        
        // Check for common virtual camera software names
        let virtualSoftware = [
            "obs", "manycam", "snap", "camtwist", "wirecast", 
            "xsplit", "nvidia", "elgato", "blackmagic"
        ]
        
        return virtualSoftware.contains { software in
            deviceName.contains(software)
        }
    }
    
    private func checkSuspiciousPatterns(_ deviceInfo: DeviceInfo) -> String? {
        let deviceName = deviceInfo.localizedName
        
        for pattern in suspiciousPatterns {
            if deviceName.contains(pattern) {
                return "Suspicious device pattern: \(pattern)"
            }
        }
        
        // Check for unusual capabilities
        if deviceInfo.capabilities.isEmpty {
            return "Device has no video capabilities"
        }
        
        // Check for suspicious manufacturer
        if deviceInfo.manufacturer.lowercased().contains("virtual") ||
           deviceInfo.manufacturer.lowercased().contains("software") {
            return "Suspicious manufacturer: \(deviceInfo.manufacturer)"
        }
        
        return nil
    }
    
    private func performSecurityChecks(_ deviceInfo: DeviceInfo) -> String? {
        // Check if device has required capabilities for face detection
        let requiredCapabilities = ["420v", "420f"] // Common video formats
        let hasRequiredCapability = requiredCapabilities.contains { capability in
            deviceInfo.capabilities.contains(capability)
        }
        
        if !hasRequiredCapability && !deviceInfo.capabilities.isEmpty {
            return "Device lacks required video capabilities"
        }
        
        // Check for jailbreak/modification indicators
        if isJailbrokenEnvironment() {
            return "Device environment may be compromised"
        }
        
        return nil
    }
    
    private func isJailbrokenEnvironment() -> Bool {
        // Basic jailbreak detection
        let jailbreakPaths = [
            "/Applications/Cydia.app",
            "/usr/sbin/sshd",
            "/usr/bin/sshd",
            "/usr/libexec/sftp-server",
            "/Applications/blackra1n.app",
            "/Applications/FakeCarrier.app",
            "/Applications/Icy.app",
            "/Applications/IntelliScreen.app",
            "/Applications/MxTube.app",
            "/Applications/RockApp.app",
            "/Applications/SBSettings.app",
            "/Applications/WinterBoard.app"
        ]
        
        for path in jailbreakPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        
        return false
    }
}

// MARK: - Extensions

extension JAAKDeviceValidator.ValidationResult {
    var isAllowed: Bool {
        switch self {
        case .allowed:
            return true
        case .blocked, .suspicious:
            return false
        }
    }
    
    var errorMessage: String? {
        switch self {
        case .allowed:
            return nil
        case .blocked(let reason), .suspicious(let reason):
            return reason
        }
    }
}

extension FourCharCode {
    func toString() -> String {
        let bytes: [CChar] = [
            CChar((self >> 24) & 0xFF),
            CChar((self >> 16) & 0xFF),
            CChar((self >> 8) & 0xFF),
            CChar(self & 0xFF),
            0
        ]
        return String(cString: bytes)
    }
}
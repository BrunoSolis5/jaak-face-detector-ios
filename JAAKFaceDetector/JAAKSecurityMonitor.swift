import AVFoundation
import UIKit

/// Continuous security monitoring for camera devices
internal class JAAKSecurityMonitor {
    
    // MARK: - Properties
    
    private let configuration: JAAKFaceDetectorConfiguration
    private let deviceValidator: JAAKDeviceValidator
    private var monitoringTimer: Timer?
    private var lastValidationResults: [String: JAAKDeviceValidator.ValidationResult] = [:]
    
    weak var delegate: JAAKSecurityMonitorDelegate?
    
    // MARK: - Initialization
    
    init(configuration: JAAKFaceDetectorConfiguration) {
        self.configuration = configuration
        self.deviceValidator = JAAKDeviceValidator(configuration: configuration)
    }
    
    // MARK: - Public Methods
    
    /// Start continuous security monitoring
    /// - Parameter interval: monitoring interval in seconds
    func startMonitoring(interval: TimeInterval = 5.0) {
        stopMonitoring()
        
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.performSecurityCheck()
        }
        
        // Perform initial check
        performSecurityCheck()
    }
    
    /// Stop security monitoring
    func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
    
    /// Perform immediate security check
    func performSecurityCheck() {
        let devicesWithValidation = deviceValidator.getAllDevicesWithValidation()
        var currentResults: [String: JAAKDeviceValidator.ValidationResult] = [:]
        
        for (device, validation) in devicesWithValidation {
            currentResults[device.uniqueID] = validation
            
            // Check if validation status changed
            if let previousResult = lastValidationResults[device.uniqueID] {
                if !isSameValidationResult(previousResult, validation) {
                    handleValidationChange(device: device, 
                                         previousResult: previousResult, 
                                         currentResult: validation)
                }
            } else {
                // New device detected
                handleNewDevice(device: device, validation: validation)
            }
        }
        
        // Check for removed devices
        for (deviceID, previousResult) in lastValidationResults {
            if currentResults[deviceID] == nil {
                handleDeviceRemoved(deviceID: deviceID, previousResult: previousResult)
            }
        }
        
        lastValidationResults = currentResults
        
        // Check for security threats
        checkForSecurityThreats(devicesWithValidation)
    }
    
    /// Validate current active camera device
    /// - Parameter device: currently active camera device
    /// - Returns: validation result
    func validateActiveDevice(_ device: AVCaptureDevice) -> JAAKDeviceValidator.ValidationResult {
        return deviceValidator.validateDevice(device)
    }
    
    // MARK: - Private Methods
    
    private func isSameValidationResult(_ result1: JAAKDeviceValidator.ValidationResult, 
                                      _ result2: JAAKDeviceValidator.ValidationResult) -> Bool {
        switch (result1, result2) {
        case (.allowed, .allowed):
            return true
        case (.blocked(let reason1), .blocked(let reason2)):
            return reason1 == reason2
        case (.suspicious(let reason1), .suspicious(let reason2)):
            return reason1 == reason2
        default:
            return false
        }
    }
    
    private func handleValidationChange(device: AVCaptureDevice, 
                                      previousResult: JAAKDeviceValidator.ValidationResult, 
                                      currentResult: JAAKDeviceValidator.ValidationResult) {
        let event = JAAKSecurityEvent(
            type: .deviceValidationChanged,
            deviceID: device.uniqueID,
            deviceName: device.localizedName,
            message: "Device validation changed from \(previousResult) to \(currentResult)",
            severity: currentResult.isAllowed ? .low : .high
        )
        
        delegate?.securityMonitor(self, didDetectEvent: event)
    }
    
    private func handleNewDevice(device: AVCaptureDevice, 
                               validation: JAAKDeviceValidator.ValidationResult) {
        let event = JAAKSecurityEvent(
            type: .newDeviceDetected,
            deviceID: device.uniqueID,
            deviceName: device.localizedName,
            message: "New camera device detected: \(validation.errorMessage ?? "Allowed")",
            severity: validation.isAllowed ? .low : .high
        )
        
        delegate?.securityMonitor(self, didDetectEvent: event)
    }
    
    private func handleDeviceRemoved(deviceID: String, 
                                   previousResult: JAAKDeviceValidator.ValidationResult) {
        let event = JAAKSecurityEvent(
            type: .deviceRemoved,
            deviceID: deviceID,
            deviceName: "Unknown",
            message: "Camera device removed",
            severity: .medium
        )
        
        delegate?.securityMonitor(self, didDetectEvent: event)
    }
    
    private func checkForSecurityThreats(_ devicesWithValidation: [(AVCaptureDevice, JAAKDeviceValidator.ValidationResult)]) {
        let blockedDevices = devicesWithValidation.filter { !$0.1.isAllowed }
        
        if blockedDevices.count > 0 {
            let event = JAAKSecurityEvent(
                type: .securityThreatDetected,
                deviceID: "multiple",
                deviceName: "Multiple devices",
                message: "Found \(blockedDevices.count) blocked/suspicious camera devices",
                severity: .critical
            )
            
            delegate?.securityMonitor(self, didDetectEvent: event)
        }
        
        // Check for unusual device patterns
        checkForUnusualPatterns(devicesWithValidation)
    }
    
    private func checkForUnusualPatterns(_ devicesWithValidation: [(AVCaptureDevice, JAAKDeviceValidator.ValidationResult)]) {
        // Check for too many external devices (iOS 17.0+ only)
        if #available(iOS 17.0, *) {
            let externalDevices = devicesWithValidation.filter { $0.0.deviceType == .external }
            if externalDevices.count > 2 {
                let event = JAAKSecurityEvent(
                    type: .suspiciousActivity,
                    deviceID: "multiple",
                    deviceName: "External devices",
                    message: "Unusual number of external camera devices: \(externalDevices.count)",
                    severity: .medium
                )
                
                delegate?.securityMonitor(self, didDetectEvent: event)
            }
        }
        
        // Check for devices with similar names (potential duplicates/virtual cameras)
        checkForDuplicateDeviceNames(devicesWithValidation)
    }
    
    private func checkForDuplicateDeviceNames(_ devicesWithValidation: [(AVCaptureDevice, JAAKDeviceValidator.ValidationResult)]) {
        var deviceNames: [String: Int] = [:]
        
        for (device, _) in devicesWithValidation {
            let baseName = device.localizedName.lowercased()
            deviceNames[baseName] = (deviceNames[baseName] ?? 0) + 1
        }
        
        for (name, count) in deviceNames {
            if count > 1 {
                let event = JAAKSecurityEvent(
                    type: .suspiciousActivity,
                    deviceID: "multiple",
                    deviceName: name,
                    message: "Multiple devices with similar name: \(name) (count: \(count))",
                    severity: .medium
                )
                
                delegate?.securityMonitor(self, didDetectEvent: event)
            }
        }
    }
}

// MARK: - JAAKSecurityEvent

struct JAAKSecurityEvent {
    enum EventType {
        case deviceValidationChanged
        case newDeviceDetected
        case deviceRemoved
        case securityThreatDetected
        case suspiciousActivity
    }
    
    enum Severity {
        case low
        case medium
        case high
        case critical
    }
    
    let type: EventType
    let deviceID: String
    let deviceName: String
    let message: String
    let severity: Severity
    let timestamp: Date
    
    init(type: EventType, deviceID: String, deviceName: String, message: String, severity: Severity) {
        self.type = type
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.message = message
        self.severity = severity
        self.timestamp = Date()
    }
}

// MARK: - JAAKSecurityMonitorDelegate

protocol JAAKSecurityMonitorDelegate: AnyObject {
    func securityMonitor(_ monitor: JAAKSecurityMonitor, didDetectEvent event: JAAKSecurityEvent)
}

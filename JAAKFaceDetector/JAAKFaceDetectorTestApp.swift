//
//  JAAKFaceDetectorTestApp.swift
//  JAAKFaceDetector
//
//  Test app with comprehensive configuration UI for testing all library settings
//

import SwiftUI
import AVFoundation

@available(iOS 14.0, *)
public struct JAAKFaceDetectorTestApp: View {
    
    // MARK: - State Properties
    
    @State private var configuration = JAAKFaceDetectorConfiguration()
    @State private var isDetectionActive = false
    @State private var lastStatus: JAAKFaceDetectorStatus = .idle
    @State private var lastFaceMessage: JAAKFaceDetectionMessage?
    @State private var isRecording = false
    @State private var showingSettings = false
    @State private var capturedFiles: [JAAKFileResult] = []
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Camera Preview
                ZStack {
                    JAAKFaceDetectorView(
                        configuration: configuration,
                        delegate: TestAppDelegate(parent: self)
                    )
                    .id(configuration.hashValue) // Force recreation when config changes
                    
                    // Status Overlay
                    VStack {
                        Spacer()
                        HStack {
                            StatusIndicator(status: lastStatus, faceMessage: lastFaceMessage)
                            Spacer()
                        }
                        .padding()
                    }
                }
                .frame(height: UIScreen.main.bounds.height * 0.6)
                
                // Controls
                VStack(spacing: 16) {
                    // Primary Controls
                    HStack(spacing: 20) {
                        Button(action: toggleDetection) {
                            HStack {
                                Image(systemName: isDetectionActive ? "stop.circle.fill" : "play.circle.fill")
                                Text(isDetectionActive ? "Stop" : "Start")
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(isDetectionActive ? Color.red : Color.green)
                            .cornerRadius(20)
                        }
                        
                        Button(action: recordVideo) {
                            HStack {
                                Image(systemName: "video.circle.fill")
                                Text("Record")
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .cornerRadius(20)
                        }
                        .disabled(!isDetectionActive || isRecording)
                        
                        Button(action: takeSnapshot) {
                            HStack {
                                Image(systemName: "camera.circle.fill")
                                Text("Photo")
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.purple)
                            .cornerRadius(20)
                        }
                        .disabled(!isDetectionActive)
                    }
                    
                    // Secondary Controls
                    HStack(spacing: 20) {
                        Button(action: toggleCamera) {
                            HStack {
                                Image(systemName: "camera.rotate.fill")
                                Text("Flip")
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(16)
                        }
                        .disabled(!isDetectionActive)
                        
                        Button(action: { showingSettings.toggle() }) {
                            HStack {
                                Image(systemName: "gear.circle.fill")
                                Text("Settings")
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(16)
                        }
                        
                        Button(action: clearCapturedFiles) {
                            HStack {
                                Image(systemName: "trash.circle.fill")
                                Text("Clear (\(capturedFiles.count))")
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(16)
                        }
                        .disabled(capturedFiles.isEmpty)
                    }
                }
                .padding()
                .background(Color(UIColor.systemBackground))
            }
            .navigationTitle("JAAK Face Detector Test")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showingSettings) {
            ConfigurationView(configuration: $configuration)
        }
    }
    
    // MARK: - Actions
    
    private func toggleDetection() {
        isDetectionActive.toggle()
        // The actual start/stop will be handled by the delegate
    }
    
    private func recordVideo() {
        isRecording = true
        // The actual recording will be handled by the delegate
    }
    
    private func takeSnapshot() {
        // The actual snapshot will be handled by the delegate
    }
    
    private func toggleCamera() {
        // The actual camera toggle will be handled by the delegate
    }
    
    private func clearCapturedFiles() {
        capturedFiles.removeAll()
    }
}

// MARK: - Status Indicator

@available(iOS 14.0, *)
struct StatusIndicator: View {
    let status: JAAKFaceDetectorStatus
    let faceMessage: JAAKFaceDetectionMessage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                Text(statusText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
            }
            
            if let message = faceMessage {
                Text(messageText(for: message))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.7))
        .cornerRadius(8)
    }
    
    private var statusColor: Color {
        switch status {
        case .idle: return .gray
        case .starting: return .yellow
        case .running: return .green
        case .error: return .red
        }
    }
    
    private var statusText: String {
        switch status {
        case .idle: return "IDLE"
        case .starting: return "STARTING"
        case .running: return "RUNNING"
        case .error: return "ERROR"
        }
    }
    
    private func messageText(for message: JAAKFaceDetectionMessage) -> String {
        switch message {
        case .faceDetected: return "Face detected"
        case .faceNotDetected: return "No face detected"
        case .faceQualityGood: return "Good quality"
        case .faceQualityPoor: return "Poor quality"
        case .facePositionCorrect: return "Position correct"
        case .facePositionIncorrect: return "Position incorrect"
        case .faceAreaTooSmall: return "Face too small"
        case .faceAreaTooLarge: return "Face too large"
        case .faceAreaCorrect: return "Face size correct"
        }
    }
}

// MARK: - Configuration View

@available(iOS 14.0, *)
struct ConfigurationView: View {
    @Binding var configuration: JAAKFaceDetectorConfiguration
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List {
                // Basic Settings
                Section("Basic Settings") {
                    HStack {
                        Text("Video Duration")
                        Spacer()
                        TextField("Duration", value: $configuration.videoDuration, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 80)
                        Text("sec")
                    }
                    
                    Toggle("Enable Microphone", isOn: $configuration.enableMicrophone)
                    
                    Picker("Camera Position", selection: $configuration.cameraPosition) {
                        Text("Back").tag(AVCaptureDevice.Position.back)
                        Text("Front").tag(AVCaptureDevice.Position.front)
                    }
                    
                    Picker("Video Quality", selection: $configuration.videoQuality) {
                        Text("Low").tag(AVCaptureSession.Preset.low)
                        Text("Medium").tag(AVCaptureSession.Preset.medium)
                        Text("High").tag(AVCaptureSession.Preset.high)
                        Text("Photo").tag(AVCaptureSession.Preset.photo)
                        Text("4K").tag(AVCaptureSession.Preset.hd4K3840x2160)
                    }
                }
                
                // Face Detection Settings
                Section("Face Detection") {
                    Toggle("Disable Face Detection", isOn: $configuration.disableFaceDetection)
                    Toggle("Hide Face Tracker", isOn: $configuration.hideFaceTracker)
                    Toggle("Mute Detection Messages", isOn: $configuration.muteFaceDetectionMessages)
                    Toggle("Use Offline Model", isOn: $configuration.useOfflineModel)
                }
                
                // Auto Recording Settings
                Section("Auto Recording") {
                    Toggle("Auto Recorder", isOn: $configuration.autoRecorder)
                    Toggle("Progressive Auto Recorder", isOn: $configuration.progressiveAutoRecorder)
                }
                
                // Timer Settings
                Section("Timer") {
                    Toggle("Hide Timer", isOn: $configuration.hideTimer)
                    
                    ColorPicker("Text Color", selection: Binding(
                        get: { Color(configuration.timerStyles.textColor) },
                        set: { configuration.timerStyles.textColor = UIColor($0) }
                    ))
                    
                    ColorPicker("Circle Color", selection: Binding(
                        get: { Color(configuration.timerStyles.circleColor) },
                        set: { configuration.timerStyles.circleColor = UIColor($0) }
                    ))
                    
                    ColorPicker("Success Color", selection: Binding(
                        get: { Color(configuration.timerStyles.circleSuccessColor) },
                        set: { configuration.timerStyles.circleSuccessColor = UIColor($0) }
                    ))
                    
                    HStack {
                        Text("Size")
                        Spacer()
                        TextField("Width", value: Binding(
                            get: { configuration.timerStyles.size.width },
                            set: { width in 
                                configuration.timerStyles.size = CGSize(
                                    width: width, 
                                    height: configuration.timerStyles.size.height
                                )
                            }
                        ), format: .number)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 60)
                        
                        Text("×")
                        
                        TextField("Height", value: Binding(
                            get: { configuration.timerStyles.size.height },
                            set: { height in 
                                configuration.timerStyles.size = CGSize(
                                    width: configuration.timerStyles.size.width, 
                                    height: height
                                )
                            }
                        ), format: .number)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 60)
                    }
                    
                    HStack {
                        Text("Font Size")
                        Spacer()
                        TextField("Size", value: $configuration.timerStyles.fontSize, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 80)
                    }
                    
                    HStack {
                        Text("Stroke Width")
                        Spacer()
                        TextField("Width", value: $configuration.timerStyles.strokeWidth, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 80)
                    }
                }
                
                // Face Tracker Styles
                Section("Face Tracker") {
                    ColorPicker("Valid Color", selection: Binding(
                        get: { Color(configuration.faceTrackerStyles.validColor) },
                        set: { configuration.faceTrackerStyles.validColor = UIColor($0) }
                    ))
                    
                    ColorPicker("Invalid Color", selection: Binding(
                        get: { Color(configuration.faceTrackerStyles.invalidColor) },
                        set: { configuration.faceTrackerStyles.invalidColor = UIColor($0) }
                    ))
                }
                
                // Instructions Settings
                Section("Instructions") {
                    Toggle("Enable Instructions", isOn: $configuration.enableInstructions)
                    
                    HStack {
                        Text("Instruction Delay")
                        Spacer()
                        TextField("Delay", value: $configuration.instructionDelay, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 80)
                        Text("sec")
                    }
                    
                    HStack {
                        Text("Replay Delay")
                        Spacer()
                        TextField("Delay", value: $configuration.instructionReplayDelay, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 80)
                        Text("sec")
                    }
                    
                    HStack {
                        Text("Button Text")
                        Spacer()
                        TextField("Text", text: $configuration.instructionsButtonText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 150)
                    }
                }
                
                // Reset Section
                Section("Reset") {
                    Button("Reset to Defaults") {
                        configuration = JAAKFaceDetectorConfiguration()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Test App Delegate

@available(iOS 14.0, *)
class TestAppDelegate: JAAKFaceDetectorViewDelegate {
    weak var parent: JAAKFaceDetectorTestApp?
    
    init(parent: JAAKFaceDetectorTestApp) {
        self.parent = parent
    }
    
    func faceDetectorView(_ view: JAAKFaceDetectorView, didStartDetection success: Bool) {
        DispatchQueue.main.async {
            self.parent?.isDetectionActive = success
            if success {
                self.parent?.lastStatus = .running
            } else {
                self.parent?.lastStatus = .error
            }
        }
    }
    
    func faceDetectorView(_ view: JAAKFaceDetectorView, didStopDetection success: Bool) {
        DispatchQueue.main.async {
            self.parent?.isDetectionActive = false
            self.parent?.lastStatus = .idle
        }
    }
    
    func faceDetectorView(_ view: JAAKFaceDetectorView, didToggleCamera success: Bool) {
        // Camera toggled
    }
    
    func faceDetectorView(_ view: JAAKFaceDetectorView, didCaptureFile fileResult: JAAKFileResult) {
        DispatchQueue.main.async {
            self.parent?.capturedFiles.append(fileResult)
            self.parent?.isRecording = false
        }
    }
    
    func faceDetectorView(_ view: JAAKFaceDetectorView, didEncounterError error: Error) {
        DispatchQueue.main.async {
            self.parent?.lastStatus = .error
            self.parent?.isRecording = false
        }
    }
    
    func faceDetectorView(status: JAAKFaceDetectorStatus) {
        DispatchQueue.main.async {
            self.parent?.lastStatus = status
        }
    }
    
    func faceDetectorView(didDetectFace message: JAAKFaceDetectionMessage) {
        DispatchQueue.main.async {
            self.parent?.lastFaceMessage = message
        }
    }
}

// MARK: - Configuration Hashable Extension

extension JAAKFaceDetectorConfiguration: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(videoDuration)
        hasher.combine(enableMicrophone)
        hasher.combine(cameraPosition.rawValue)
        hasher.combine(videoQuality.rawValue)
        hasher.combine(disableFaceDetection)
        hasher.combine(hideFaceTracker)
        hasher.combine(autoRecorder)
        hasher.combine(progressiveAutoRecorder)
        hasher.combine(hideTimer)
        hasher.combine(enableInstructions)
    }
    
    public static func == (lhs: JAAKFaceDetectorConfiguration, rhs: JAAKFaceDetectorConfiguration) -> Bool {
        return lhs.videoDuration == rhs.videoDuration &&
               lhs.enableMicrophone == rhs.enableMicrophone &&
               lhs.cameraPosition == rhs.cameraPosition &&
               lhs.videoQuality == rhs.videoQuality &&
               lhs.disableFaceDetection == rhs.disableFaceDetection &&
               lhs.hideFaceTracker == rhs.hideFaceTracker &&
               lhs.autoRecorder == rhs.autoRecorder &&
               lhs.progressiveAutoRecorder == rhs.progressiveAutoRecorder &&
               lhs.hideTimer == rhs.hideTimer &&
               lhs.enableInstructions == rhs.enableInstructions
    }
}
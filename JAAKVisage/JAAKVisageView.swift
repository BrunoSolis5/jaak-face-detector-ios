//
//  JAAKVisageView.swift
//  JAAKVisage
//
//  Created by Claude on 10/07/25.
//

import SwiftUI
import UIKit
import AVFoundation

/// SwiftUI view component that encapsulates the complete face detection functionality
@available(iOS 13.0, *)
public struct JAAKVisageView: UIViewRepresentable {
    
    // MARK: - Properties
    
    /// Configuration for the face detector
    public let configuration: JAAKVisageConfiguration
    
    /// Delegate to receive face detection events
    public weak var delegate: JAAKVisageViewDelegate?
    
    /// Internal face detector instance
    private var faceDetector: JAAKVisageSDK?
    
    /// State tracking
    private var isSetup: Bool = false
    
    // MARK: - Initialization
    
    /// Initialize JAAKVisageView with configuration
    /// - Parameters:
    ///   - configuration: Configuration for face detection
    ///   - delegate: Delegate to receive events
    public init(configuration: JAAKVisageConfiguration, delegate: JAAKVisageViewDelegate? = nil) {
        self.configuration = configuration
        self.delegate = delegate
    }
    
    // MARK: - UIViewRepresentable
    
    public func makeUIView(context: Context) -> JAAKVisageUIView {
        let view = JAAKVisageUIView()
        view.backgroundColor = UIColor.black
        
        // Setup face detector
        setupFaceDetector(for: view)
        
        return view
    }
    
    public func updateUIView(_ uiView: JAAKVisageUIView, context: Context) {
        // Update only when necessary
        if !uiView.isSetup {
            setupFaceDetector(for: uiView)
        } else {
            // Check if configuration has changed and needs refresh
            if let currentDetector = uiView.faceDetector, 
               !configurationMatches(currentDetector.configuration, configuration) {
                
                // Stop current detector
                currentDetector.stopDetection()
                
                // Reset the view
                uiView.isSetup = false
                uiView.faceDetector = nil
                uiView.previewView?.removeFromSuperview()
                uiView.previewView = nil
                uiView.internalDelegate = nil
                
                // Clear existing content
                uiView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
                uiView.subviews.forEach { $0.removeFromSuperview() }
                
                // Setup with new configuration
                setupFaceDetector(for: uiView)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupFaceDetector(for view: JAAKVisageUIView) {
        guard !view.isSetup else { return }
        
        
        // Create face detector instance
        let detector = JAAKVisageSDK(configuration: configuration)
        
        // Create and store internal delegate with strong reference
        let internalDelegate = InternalDelegate(parentDelegate: delegate)
        detector.delegate = internalDelegate
        
        // Get the complete preview view from the library
        let previewView = detector.createPreviewView()
        
        // Add preview view to our container
        view.addSubview(previewView)
        previewView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Store references
        view.faceDetector = detector
        view.previewView = previewView
        view.internalDelegate = internalDelegate // Store strong reference
        view.isSetup = true
        
    }
    
    private func configurationMatches(_ config1: JAAKVisageConfiguration, _ config2: JAAKVisageConfiguration) -> Bool {
        // Only compare properties that require full recreation of the detector
        // Dynamic properties like hideTimer, etc. will be handled by updateConfiguration
        // Microphone removed from comparison
               config1.cameraPosition == config2.cameraPosition &&
               config1.videoQuality == config2.videoQuality &&
               config1.disableFaceDetection == config2.disableFaceDetection &&
               config1.useOfflineModel == config2.useOfflineModel
    }
    
    // MARK: - Public Methods
    
    // Note: These methods will be called through the SimpleFaceDetectorManager
    // which will have access to the UIView and its faceDetector instance
}

// MARK: - JAAKVisageUIView

@available(iOS 13.0, *)
public class JAAKVisageUIView: UIView {
    
    // MARK: - Properties
    
    public var faceDetector: JAAKVisageSDK?
    public var previewView: UIView?
    public var isSetup: Bool = false
    public var internalDelegate: InternalDelegate?
    
    // MARK: - Lifecycle
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        
        // Ensure preview view matches our bounds
        previewView?.frame = bounds
        
        // Also update the preview layer if it exists
        if let previewView = previewView {
            for sublayer in previewView.layer.sublayers ?? [] {
                if let previewLayer = sublayer as? AVCaptureVideoPreviewLayer {
                    previewLayer.frame = bounds
                }
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Start face detection
    @available(iOS 13.0, *)
    public func startDetection() {
        
        do {
            try faceDetector?.startDetection()
        } catch {
            
        }
    }
    
    /// Stop face detection
    @available(iOS 13.0, *)
    public func stopDetection() {
        faceDetector?.stopDetection()
    }
    
    /// Record video
    @available(iOS 13.0, *)
    public func recordVideo(completion: @escaping (Result<JAAKFileResult, JAAKVisageError>) -> Void) {
        faceDetector?.recordVideo(completion: completion)
    }
    
    
    /// Toggle between front and back camera
    @available(iOS 13.0, *)
    public func toggleCamera() throws {
        try faceDetector?.toggleCamera()
    }
    
    /// Restart the face detector
    @available(iOS 13.0, *)
    public func restartDetector() throws {
        try faceDetector?.restartDetection()
    }
}

// MARK: - Internal Delegate

@available(iOS 13.0, *)
public class InternalDelegate: JAAKVisageSDKDelegate {
    
    weak var parentDelegate: JAAKVisageViewDelegate?
    
    public init(parentDelegate: JAAKVisageViewDelegate?) {
        self.parentDelegate = parentDelegate
    }
    
    public func faceDetector(_ detector: JAAKVisageSDK, didUpdateStatus status: JAAKVisageStatus) {
        DispatchQueue.main.async { [weak self] in
            // Convert to our view-specific delegate
            self?.parentDelegate?.faceDetectorView(status: status)
        }
    }
    
    public func faceDetector(_ detector: JAAKVisageSDK, didDetectFace message: JAAKFaceDetectionMessage) {
        DispatchQueue.main.async { [weak self] in
            // Convert to our view-specific delegate
            self?.parentDelegate?.faceDetectorView(didDetectFace: message)
        }
    }
    
    public func faceDetector(_ detector: JAAKVisageSDK, didCaptureFile result: JAAKFileResult) {
        // This is handled by the public methods - no action needed
        // The actual file capture handling is done through direct method calls
    }
    
    public func faceDetector(_ detector: JAAKVisageSDK, didEncounterError error: JAAKVisageError) {
        // This is handled by the public methods - no action needed
        // Error handling is done through direct method calls
    }
}

// MARK: - JAAKVisageViewDelegate

/// Delegate protocol for JAAKVisageView events
@available(iOS 13.0, *)
public protocol JAAKVisageViewDelegate: AnyObject {
    
    /// Called when face detection starts or fails to start
    /// - Parameters:
    ///   - view: The face detector view
    ///   - success: Whether detection started successfully
    func faceDetectorView(_ view: JAAKVisageView, didStartDetection success: Bool)
    
    /// Called when face detection stops
    /// - Parameters:
    ///   - view: The face detector view
    ///   - success: Whether detection stopped successfully
    func faceDetectorView(_ view: JAAKVisageView, didStopDetection success: Bool)
    
    /// Called when camera is toggled
    /// - Parameters:
    ///   - view: The face detector view
    ///   - success: Whether camera toggle was successful
    func faceDetectorView(_ view: JAAKVisageView, didToggleCamera success: Bool)
    
    /// Called when a file is captured (video)
    /// - Parameters:
    ///   - view: The face detector view
    ///   - fileResult: The captured file result
    func faceDetectorView(_ view: JAAKVisageView, didCaptureFile fileResult: JAAKFileResult)
    
    /// Called when an error occurs
    /// - Parameters:
    ///   - view: The face detector view
    ///   - error: The error that occurred
    func faceDetectorView(_ view: JAAKVisageView, didEncounterError error: Error)
    
    /// Called when face detection status changes
    /// - Parameter status: The new status
    func faceDetectorView(status: JAAKVisageStatus)
    
    /// Called when face detection occurs
    /// - Parameter message: The face detection message
    func faceDetectorView(didDetectFace message: JAAKFaceDetectionMessage)
}

// MARK: - Optional Delegate Methods

@available(iOS 13.0, *)
public extension JAAKVisageViewDelegate {
    
    func faceDetectorView(_ view: JAAKVisageView, didStartDetection success: Bool) {
        // Optional implementation
    }
    
    func faceDetectorView(_ view: JAAKVisageView, didStopDetection success: Bool) {
        // Optional implementation
    }
    
    func faceDetectorView(_ view: JAAKVisageView, didToggleCamera success: Bool) {
        // Optional implementation
    }
    
    func faceDetectorView(_ view: JAAKVisageView, didCaptureFile fileResult: JAAKFileResult) {
        // Optional implementation
    }
    
    func faceDetectorView(_ view: JAAKVisageView, didEncounterError error: Error) {
        // Optional implementation
    }
    
    func faceDetectorView(status: JAAKVisageStatus) {
        // Optional implementation
    }
    
    func faceDetectorView(didDetectFace message: JAAKFaceDetectionMessage) {
        // Optional implementation
    }
}

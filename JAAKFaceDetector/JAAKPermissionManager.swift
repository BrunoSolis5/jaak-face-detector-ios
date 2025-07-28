import AVFoundation
import UIKit

/// Internal class for managing camera and microphone permissions
internal class JAAKPermissionManager {
    
    /// Check if camera permission is granted
    /// - Returns: true if camera access is authorized
    static func isCameraAuthorized() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }
    
    /// Check if microphone permission is granted
    /// - Returns: true if microphone access is authorized
    static func isMicrophoneAuthorized() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    /// Request camera permission
    /// - Parameter completion: completion handler with result
    static func requestCameraPermission(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            completion(true)
        case .denied, .restricted:
            completion(false)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        @unknown default:
            completion(false)
        }
    }
    
    /// Request microphone permission
    /// - Parameter completion: completion handler with result
    static func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            completion(true)
        case .denied, .restricted:
            completion(false)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        @unknown default:
            completion(false)
        }
    }
    
    /// Request all required permissions based on configuration
    /// - Parameters:
    ///   - enableMicrophone: whether microphone is needed
    ///   - completion: completion handler with result
    static func requestRequiredPermissions(enableMicrophone: Bool, completion: @escaping (Bool, JAAKFaceDetectorError?) -> Void) {
        requestCameraPermission { cameraGranted in
            guard cameraGranted else {
                let error = JAAKFaceDetectorError(
                    label: "Permiso de cámara denegado",
                    code: "CAMERA_PERMISSION_DENIED"
                )
                completion(false, error)
                return
            }
            
            if enableMicrophone {
                requestMicrophonePermission { microphoneGranted in
                    if microphoneGranted {
                        completion(true, nil)
                    } else {
                        let error = JAAKFaceDetectorError(
                            label: "Permiso de micrófono denegado",
                            code: "MICROPHONE_PERMISSION_DENIED"
                        )
                        completion(false, error)
                    }
                }
            } else {
                completion(true, nil)
            }
        }
    }
    
    /// Show alert to redirect user to settings for permissions
    /// - Parameter from: the view controller to present from
    static func showPermissionAlert(from viewController: UIViewController?) {
        let alert = UIAlertController(
            title: "Acceso a la cámara requerido",
            message: "Esta aplicación necesita acceso a la cámara para detectar rostros. Por favor, habilita el acceso a la cámara en Configuración.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Configuración", style: .default) { _ in
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        
        viewController?.present(alert, animated: true)
    }
}
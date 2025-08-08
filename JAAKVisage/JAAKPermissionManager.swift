import AVFoundation
import UIKit

/// Internal class for managing camera permissions
internal class JAAKPermissionManager {
    
    /// Check if camera permission is granted
    /// - Returns: true if camera access is authorized
    static func isCameraAuthorized() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
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
    
    
    /// Request camera permission (microphone removed)
    /// - Parameter completion: completion handler with result
    static func requestRequiredPermissions(completion: @escaping (Bool, JAAKVisageError?) -> Void) {
        requestCameraPermission { cameraGranted in
            guard cameraGranted else {
                let error = JAAKVisageError(
                    label: "Permiso de cámara denegado",
                    code: "CAMERA_PERMISSION_DENIED"
                )
                completion(false, error)
                return
            }
            
            completion(true, nil)
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
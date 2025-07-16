# SDK iOS - Face Detector

## **Tabla de contenido**

1. [Objetivo, alcance y usuarios](#1-objetivo-alcance-y-usuarios)
2. [Desarrollo](#2-desarrollo)
   - 2.1 [Prerrequisitos técnicos](#21-prerrequisitos-técnicos)
   - 2.2 [Configuración del entorno](#22-configuración-del-entorno)
     - [Paso 1. Instalación](#paso-1-instalación)
     - [Paso 2. Configuración Avanzada](#paso-2-configuración-avanzada)
   - 2.3 [Guía de implementación](#23-guía-de-implementación)
     - 2.3.1 [Implementación básica](#231-implementación-básica)
     - 2.3.2 [Implementación avanzada](#232-implementación-avanzada)
   - 2.4 [Referencias/Métodos](#24-referenciasmétodos)
     - 2.4.1 [Especificación principal](#241-especificación-principal)
     - 2.4.1 [Parámetros de entrada](#241-parámetros-de-entrada)
     - 2.4.2 [Estructura de respuesta](#242-estructura-de-respuesta)
       - [Respuesta Exitosa](#respuesta-exitosa)
       - [Respuestas de Error](#respuestas-de-error)
   - 2.5 [Componentes adicionales](#25-componentes-adicionales)
   - 2.6 [Pruebas y validación](#26-pruebas-y-validación)
   - 2.7 [Solución de problemas](#27-solución-de-problemas)
   - 2.8 [Consideraciones importantes](#28-consideraciones-importantes)
3. [Anexo(s)](#3-anexos)
4. [Validez y gestión de documentos](#4-validez-y-gestión-de-documentos)
5. [Versionado](#5-versionado)
6. [Historial de versiones](#6-historial-de-versiones)

---

## 1. **Objetivo, alcance y usuarios**

El objetivo de este documento es proporcionar una guía completa para la integración del SDK iOS JAAKFaceDetector, una biblioteca de detección facial en tiempo real con capacidades de grabación automática.

Este documento abarca la instalación, configuración, implementación y uso del SDK para aplicaciones iOS que requieren detección facial, validación de posición y grabación de video automática con tecnología MediaPipe BlazeFace.

**Dirigido a:** Desarrolladores iOS con experiencia en desarrollo de aplicaciones móviles, integración de SDKs y manejo de permisos de sistema.

**Nivel requerido:** Conocimientos avanzados en Swift, iOS SDK, AVFoundation, SwiftUI/UIKit, y manejo de permisos de cámara y micrófono.

---

## 2. **Desarrollo**

### 2.1 Prerrequisitos técnicos

#### a) **Requisitos técnicos**

| Requisito | Versión/Especificación | Obligatorio | Notas |
|-----------|------------------------|-------------|-------|
| iOS | 12.0+ | Sí | Versión mínima soportada |
| Swift | 5.0+ | Sí | Lenguaje de programación base |
| Xcode | 12.0+ | Sí | Entorno de desarrollo |
| MediaPipe Tasks Vision | ~0.10.3 | Sí | Motor de detección facial AI |
| AVFoundation | Sistema | Sí | Para captura de cámara |
| Camera | Física | Sí | Dispositivo debe tener cámara |

#### b) **Credenciales y configuración de accesos**

**Requisitos de acceso:**

- **Permisos iOS:** Acceso a cámara (obligatorio)
- **Configuración Info.plist:** Descripción de uso de permisos
- **Ambiente:** Desarrollo local, no requiere conexión a servidores JAAK
- **Dependencias:** CocoaPods para gestión de dependencias

### 2.2 Configuración del entorno

#### Paso 1. Instalación

##### a) **Método principal de instalación**

```ruby
# Agrega a tu Podfile
pod 'JAAKFaceDetector'

# Ejecuta instalación
pod install
```

##### b) **Configuración inicial**

```xml
<!-- Agregar a Info.plist -->
<key>NSCameraUsageDescription</key>
<string>Esta aplicación necesita acceso a la cámara para detectar rostros</string>
```

#### Paso 2. Configuración Avanzada

```swift
import JAAKFaceDetector

// Configuración avanzada personalizada
var config = JAAKFaceDetectorConfiguration()
config.videoDuration = 5.0
config.autoRecorder = true
config.cameraPosition = .front
config.videoQuality = .high
config.enableInstructions = true
config.instructionDelay = 3.0

// Estilos personalizados
config.timerStyles.textColor = .white
config.timerStyles.circleColor = .blue
config.timerStyles.strokeWidth = 8.0
config.faceTrackerStyles.validColor = .green
config.faceTrackerStyles.invalidColor = .red
```

### 2.3 Guía de implementación

#### 2.3.1 Implementación básica

##### a) **Ejemplo mínimo funcional:**

```swift
import UIKit
import JAAKFaceDetector

class ViewController: UIViewController {
    private var detector: JAAKFaceDetectorSDK?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 1. Configuración básica
        let config = JAAKFaceDetectorConfiguration()
        config.videoDuration = 4.0
        
        // 2. Inicializar detector
        detector = JAAKFaceDetectorSDK(configuration: config)
        detector?.delegate = self
        
        // 3. Crear vista de preview
        let previewView = detector?.createPreviewView()
        previewView?.frame = view.bounds
        view.addSubview(previewView!)
        
        // 4. Iniciar detección
        try? detector?.startDetection()
    }
}

// Implementar delegate
extension ViewController: JAAKFaceDetectorSDKDelegate {
    func faceDetector(_ detector: JAAKFaceDetectorSDK, didUpdateStatus status: JAAKFaceDetectorStatus) {
        print("Status: \(status.rawValue)")
    }
    
    func faceDetector(_ detector: JAAKFaceDetectorSDK, didCaptureFile result: JAAKFileResult) {
        print("Video capturado: \(result.fileName ?? "unknown")")
        // Procesar archivo de video
    }
    
    func faceDetector(_ detector: JAAKFaceDetectorSDK, didEncounterError error: JAAKFaceDetectorError) {
        print("Error: \(error.localizedDescription)")
    }
    
    func faceDetector(_ detector: JAAKFaceDetectorSDK, didDetectFace message: JAAKFaceDetectionMessage) {
        print("Face detected: \(message.faceExists), Position: \(message.correctPosition)")
    }
}
```

##### b) **Implementación SwiftUI:**

```swift
import SwiftUI
import JAAKFaceDetector

struct ContentView: View {
    @State private var config = JAAKFaceDetectorConfiguration()
    @State private var statusMessage = "Initializing..."
    
    var body: some View {
        VStack {
            // Vista del detector
            JAAKFaceDetectorView(configuration: config, delegate: self)
                .frame(height: 400)
                .cornerRadius(16)
            
            // Status
            Text(statusMessage)
                .padding()
            
            // Controles
            Button("Start Detection") {
                // Iniciar detección
            }
            .padding()
        }
        .onAppear {
            config.videoDuration = 5.0
            config.autoRecorder = true
        }
    }
}

extension ContentView: JAAKFaceDetectorViewDelegate {
    func faceDetectorView(status: JAAKFaceDetectorStatus) {
        statusMessage = "Status: \(status.rawValue)"
    }
    
    func faceDetectorView(_ view: JAAKFaceDetectorView, didCaptureFile fileResult: JAAKFileResult) {
        print("Video captured: \(fileResult.fileSize) bytes")
    }
    
    func faceDetectorView(_ view: JAAKFaceDetectorView, didEncounterError error: Error) {
        statusMessage = "Error: \(error.localizedDescription)"
    }
    
    func faceDetectorView(didDetectFace message: JAAKFaceDetectionMessage) {
        if message.faceExists && message.correctPosition {
            statusMessage = "Face detected in correct position"
        }
    }
}
```

#### 2.3.2 Implementación avanzada

```swift
import JAAKFaceDetector

class AdvancedFaceDetectorManager: NSObject {
    private var detector: JAAKFaceDetectorSDK
    private var isRecording = false
    
    init() {
        // Configuración avanzada
        var config = JAAKFaceDetectorConfiguration()
        config.videoDuration = 10.0
        config.autoRecorder = true
        config.cameraPosition = .front
        config.enableInstructions = true
        config.instructionDelay = 2.0
        
        // Estilos personalizados
        config.timerStyles.size = CGSize(width: 150, height: 150)
        config.timerStyles.textColor = .white
        config.timerStyles.circleColor = .systemBlue
        config.timerStyles.strokeWidth = 6.0
        
        detector = JAAKFaceDetectorSDK(configuration: config)
        super.init()
        detector.delegate = self
    }
    
    func startAdvancedDetection() {
        do {
            try detector.startDetection()
            print("Detection started successfully")
        } catch {
            handleError(error)
        }
    }
    
    func recordVideoManually() {
        guard !isRecording else { return }
        
        detector.recordVideo { [weak self] result in
            switch result {
            case .success(let fileResult):
                self?.processVideoFile(fileResult)
            case .failure(let error):
                self?.handleError(error)
            }
        }
    }
    
    private func processVideoFile(_ fileResult: JAAKFileResult) {
        print("Processing video file: \(fileResult.fileName ?? "unknown")")
        print("File size: \(fileResult.fileSize) bytes")
        print("MIME type: \(fileResult.mimeType ?? "unknown")")
        
        // Guardar archivo
        saveToDocuments(fileResult)
        
        // Subir a servidor
        uploadToServer(fileResult)
    }
    
    private func saveToDocuments(_ fileResult: JAAKFileResult) {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let fileName = fileResult.fileName ?? "video_\(Date().timeIntervalSince1970).mp4"
        let fileURL = documentsPath.appendingPathComponent(fileName)
        
        do {
            try fileResult.data.write(to: fileURL)
            print("Video saved to: \(fileURL)")
        } catch {
            print("Error saving video: \(error)")
        }
    }
    
    private func uploadToServer(_ fileResult: JAAKFileResult) {
        // Implementar subida al servidor usando base64
        let base64String = fileResult.base64
        // Enviar base64String al servidor
    }
    
    private func handleError(_ error: Error) {
        if let faceDetectorError = error as? JAAKFaceDetectorError {
            print("Face detector error: \(faceDetectorError.localizedDescription)")
            print("Error code: \(faceDetectorError.code ?? "unknown")")
        } else {
            print("General error: \(error.localizedDescription)")
        }
    }
}

extension AdvancedFaceDetectorManager: JAAKFaceDetectorSDKDelegate {
    func faceDetector(_ detector: JAAKFaceDetectorSDK, didUpdateStatus status: JAAKFaceDetectorStatus) {
        DispatchQueue.main.async {
            switch status {
            case .loading:
                print("Loading AI models...")
            case .loaded:
                print("Models loaded successfully")
            case .running:
                print("Face detection active")
            case .recording:
                self.isRecording = true
                print("Recording video...")
            case .finished:
                self.isRecording = false
                print("Recording completed")
            case .error:
                print("Detection error occurred")
            case .stopped:
                print("Detection stopped")
            case .notLoaded:
                print("Models not loaded")
            }
        }
    }
    
    func faceDetector(_ detector: JAAKFaceDetectorSDK, didCaptureFile result: JAAKFileResult) {
        processVideoFile(result)
    }
    
    func faceDetector(_ detector: JAAKFaceDetectorSDK, didEncounterError error: JAAKFaceDetectorError) {
        handleError(error)
    }
    
    func faceDetector(_ detector: JAAKFaceDetectorSDK, didDetectFace message: JAAKFaceDetectionMessage) {
        if message.faceExists && message.correctPosition {
            print("✅ Face detected in correct position")
        } else if message.faceExists {
            print("⚠️ Face detected but not in correct position")
        } else {
            print("❌ No face detected")
        }
    }
}
```

### 2.4 Referencias/Métodos

#### 2.4.1 Especificación principal

**JAAKFaceDetectorSDK - Clase principal del SDK**

**Descripción:** Clase principal que coordina la detección facial, grabación de video y gestión del ciclo de vida del detector. Proporciona una interfaz unificada para todas las funcionalidades del SDK, incluyendo detección en tiempo real, grabación automática y manual, y gestión de permisos.

#### 2.4.1 Parámetros de entrada

**JAAKFaceDetectorConfiguration:**

| Parámetro | Tipo | Requerido | Descripción | Ejemplo |
|-----------|------|-----------|-------------|---------|
| `videoDuration` | `TimeInterval` | No | Duración de la grabación en segundos | `4.0` |
| `autoRecorder` | `Bool` | No | Activar grabación automática al detectar rostro | `false` |
| `cameraPosition` | `AVCaptureDevice.Position` | No | Posición de la cámara (front/back) | `.front` |
| `videoQuality` | `AVCaptureSession.Preset` | No | Calidad de video | `.high` |
| `enableInstructions` | `Bool` | No | Mostrar instrucciones al usuario | `true` |
| `instructionDelay` | `TimeInterval` | No | Tiempo antes de mostrar instrucciones | `5.0` |
| `timerStyles` | `JAAKTimerStyles` | No | Estilos del timer circular | `JAAKTimerStyles()` |
| `faceTrackerStyles` | `JAAKFaceTrackerStyles` | No | Estilos del overlay de rostro | `JAAKFaceTrackerStyles()` |

#### 2.4.2 Estructura de respuesta

##### Respuesta Exitosa

**JAAKFileResult:**

```swift
public struct JAAKFileResult {
    public let data: Data           // Datos binarios del video
    public let base64: String       // Video codificado en base64
    public let mimeType: String?    // Tipo MIME (video/mp4)
    public let fileName: String?    // Nombre del archivo
    public let fileSize: Int        // Tamaño del archivo en bytes
}
```

**JAAKFaceDetectionMessage:**

```swift
public struct JAAKFaceDetectionMessage {
    public let label: String            // Mensaje descriptivo
    public let details: String?         // Detalles adicionales
    public let faceExists: Bool         // Si se detectó un rostro
    public let correctPosition: Bool    // Si el rostro está en posición correcta
}
```

##### Respuestas de Error

**JAAKFaceDetectorError:**

```swift
public struct JAAKFaceDetectorError: LocalizedError {
    public let label: String        // Descripción del error
    public let code: String?        // Código de error específico
    public let details: Any?        // Detalles adicionales del error
}
```

**Tipos de Error:**

```swift
public enum JAAKFaceDetectorErrorType: String {
    case modelLoading = "model-loading"
    case cameraAccess = "camera-access"
    case faceDetection = "face-detection"
    case videoRecording = "video-recording"
    case permissionDenied = "permission-denied"
    case deviceNotSupported = "device-not-supported"
}
```

### 2.5 Componentes adicionales

#### a) **Componentes UI**

- **JAAKFaceDetectorView:** Componente SwiftUI para integración declarativa
- **JAAKRecordingTimer:** Timer circular con progreso visual
- **JAAKFaceTrackingOverlay:** Overlay de seguimiento facial en tiempo real
- **JAAKInstructionController:** Sistema de instrucciones interactivas

#### b) **Utilidades**

- **JAAKPermissionManager:** Gestión de permisos de cámara
- **JAAKCameraManager:** Gestión de sesión de cámara y captura
- **JAAKVideoRecorder:** Grabación y procesamiento de video
- **JAAKFaceDetectionEngine:** Motor de detección facial con MediaPipe

### 2.6 Pruebas y validación

#### a) **Casos de prueba**

| Caso de Prueba | Entrada/Configuración | Resultado Esperado | Criterio de Éxito |
|----------------|----------------------|-------------------|-------------------|
| Inicialización básica | `JAAKFaceDetectorConfiguration()` por defecto | Detector inicializado correctamente | Status cambia a `.loaded` |
| Detección facial | Rostro visible en cámara | Detección exitosa | `didDetectFace` con `faceExists = true` |
| Grabación automática | `autoRecorder = true`, rostro detectado | Video grabado automáticamente | `didCaptureFile` llamado con `JAAKFileResult` |
| Cambio de cámara | `toggleCamera()` | Cámara cambiada exitosamente | Vista actualizada con nueva cámara |
| Manejo de permisos | Permisos denegados | Error de permisos | `didEncounterError` con tipo `permissionDenied` |
| Grabación manual | `recordVideo()` llamado | Video grabado | Archivo de video válido generado |

### 2.7 Solución de problemas

#### a) **Problemas comunes**

| Problema: | La cámara no se inicializa |
|-----------|----------------------------|
| **Descripción:** | El detector no puede acceder a la cámara y permanece en estado `loading` |
| **Causas posibles:** | Permisos de cámara denegados, dispositivo ocupado, configuración incorrecta |
| **Solución:** | Verificar permisos, revisar Info.plist, asegurar que ninguna otra app use la cámara |
| **Código de ejemplo:** | ```swift
// Verificar permisos
let status = AVCaptureDevice.authorizationStatus(for: .video)
if status == .denied {
    // Dirigir a configuración
    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(settingsUrl)
    }
}
``` |

| Problema: | El detector no detecta rostros |
|-----------|------------------------------|
| **Descripción:** | La detección facial no funciona correctamente |
| **Causas posibles:** | Iluminación insuficiente, rostro parcialmente oculto, configuración incorrecta |
| **Solución:** | Mejorar iluminación, asegurar rostro completamente visible, verificar configuración |
| **Código de ejemplo:** | ```swift
// Verificar configuración
if config.disableFaceDetection {
    config.disableFaceDetection = false
    detector.updateConfiguration(config)
}
``` |

| Problema: | La grabación termina inmediatamente |
|-----------|-------------------------------------|
| **Descripción:** | El video se graba pero termina al instante |
| **Causas posibles:** | Configuración de duración incorrecta, problema de sincronización |
| **Solución:** | Verificar `videoDuration`, reiniciar detector |
| **Código de ejemplo:** | ```swift
// Configurar duración mínima
config.videoDuration = max(config.videoDuration, 2.0)
detector.updateConfiguration(config)
``` |

#### b) **Códigos de error específicos**

| Código | Descripción | Causa | Solución |
|--------|-------------|-------|----------|
| `CAMERA_ACCESS_DENIED` | Permisos de cámara denegados | Usuario denegó permisos | Solicitar permisos nuevamente o dirigir a configuración |
| `MODEL_LOADING_FAILED` | Error al cargar modelo AI | Modelo corrupto o incompatible | Reinstalar SDK o verificar versión |
| `RECORDING_IN_PROGRESS` | Grabación ya en progreso | Múltiples llamadas a `recordVideo()` | Esperar a que termine grabación actual |
| `DEVICE_NOT_SUPPORTED` | Dispositivo no compatible | Hardware insuficiente | Usar dispositivo más reciente |
| `VIDEO_PROCESSING_FAILED` | Error procesando video | Falta de memoria o archivo corrupto | Reiniciar app o reducir calidad |

---

> **Contacta al equipo de soporte** ([soporte@jaak.ai](mailto:soporte@jaak.ai)) cuando:
> 
> - Los pasos de troubleshooting no resuelven el problema
> - Recibes errores no documentados
> - Necesitas configuraciones especiales para tu caso de uso
> - Experimentas problemas de rendimiento persistentes
> 
> **Información a incluir:** Logs del detector, configuración usada, modelo de dispositivo, versión iOS, pasos para reproducir el problema

---

### 2.8 Consideraciones importantes

#### a) **Seguridad**

- **Permisos:** Solo solicitar permisos necesarios (cámara obligatorio)
- **Datos:** Los videos se procesan localmente, no se envían automáticamente a servidores
- **Privacidad:** Informar claramente al usuario sobre el uso de la cámara
- **Almacenamiento:** Implementar limpieza automática de archivos temporales

#### b) **Rendimiento**

- **Memoria:** El SDK maneja automáticamente la memoria, pero monitorear uso en dispositivos antiguos
- **Batería:** La detección facial consume batería, optimizar para uso prolongado
- **Procesamiento:** Usar configuraciones de calidad apropiadas para el hardware
- **Threading:** Todos los callbacks se ejecutan en el hilo principal

#### c) **Calidad**

- **Iluminación:** Funciona mejor con buena iluminación frontal
- **Distancia:** Rostro debe estar a 30-60cm de la cámara
- **Orientación:** Funciona mejor con rostro centrado y vertical
- **Estabilidad:** Evitar movimientos bruscos durante la grabación

---

## 3. Anexo(s)

### **Anexo A.** Glosario de términos

| Término | Definición |
|---------|------------|
| **BlazeFace** | Modelo de detección facial de Google MediaPipe optimizado para móviles |
| **MediaPipe** | Framework de ML de Google para procesamiento multimedia en tiempo real |
| **AVCaptureSession** | Clase de iOS para coordinar entrada y salida de datos multimedia |
| **Auto-recorder** | Funcionalidad que inicia grabación automáticamente al detectar rostro |
| **Face tracking** | Seguimiento facial en tiempo real con overlay visual |
| **Delegate pattern** | Patrón de diseño usado para comunicar eventos del SDK |

### **Anexo B.** Enlaces de referencia

- [Apple AVFoundation Documentation](https://developer.apple.com/documentation/avfoundation)
- [MediaPipe Face Detection](https://google.github.io/mediapipe/solutions/face_detection.html)
- [CocoaPods Integration Guide](https://guides.cocoapods.org/using/using-cocoapods.html)
- [iOS Camera Permissions](https://developer.apple.com/documentation/avfoundation/cameras_and_media_capture/requesting_authorization_for_media_capture_on_ios)

---

## 4. **Validez y gestión de documentos**

*El propietario de este documento es el equipo de desarrollo de SDK iOS de JAAK, quien debe verificar y actualizar la documentación cuando sea necesario tras actualizaciones del SDK.*

---

## 5. **Versionado**

| **Responsable del documento:** | Equipo de desarrollo SDK iOS |
|-------------------------------|------------------------------|
| **Aprobado por:** | Arquitecto de Software Senior |
| **Fecha de aprobación:** | 15/07/2025 |
| **Clasificación de esta información:** | Documentación técnica pública |
| **Código:** | SDK-iOS-FACE-001 v.1.0 |

---

## 6. **Historial de versiones**

| Fecha | Versión | Tipo | Responsable | Descripción de la modificación |
|-------|---------|------|-------------|--------------------------------|
| 15/07/25 | 1.0 | Creación | Equipo SDK iOS | Documentación inicial basada en análisis completo del código |
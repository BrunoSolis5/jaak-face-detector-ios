# JAAKFaceDetector

[![CocoaPods](https://img.shields.io/cocoapods/v/JAAKFaceDetector.svg)](https://cocoapods.org/pods/JAAKFaceDetector)
[![Platform](https://img.shields.io/cocoapods/p/JAAKFaceDetector.svg)](https://cocoapods.org/pods/JAAKFaceDetector)
[![License](https://img.shields.io/cocoapods/l/JAAKFaceDetector.svg)](https://github.com/BrunoSolis5/jaak-face-detector-ios/blob/main/LICENSE)

AI-powered face detection and recording library for iOS using MediaPipe BlazeFace

## **Tabla de contenido**

1. [Instalación](#1-instalación)
2. [Inicio rápido](#2-inicio-rápido)
3. [Configuración](#3-configuración)
4. [Documentación técnica](#4-documentación-técnica)
   - 4.1 [Prerrequisitos técnicos](#41-prerrequisitos-técnicos)
   - 4.2 [Configuración del entorno](#42-configuración-del-entorno)
   - 4.3 [Guía de implementación](#43-guía-de-implementación)
     - 4.3.1 [Implementación básica](#431-implementación-básica)
     - 4.3.2 [Implementación avanzada](#432-implementación-avanzada)
   - 4.4 [Referencias/Métodos](#44-referenciasmétodos)
   - 4.5 [Componentes adicionales](#45-componentes-adicionales)
   - 4.6 [Pruebas y validación](#46-pruebas-y-validación)
   - 4.7 [Solución de problemas](#47-solución-de-problemas)
   - 4.8 [Consideraciones importantes](#48-consideraciones-importantes)
5. [Anexos](#5-anexos)
6. [Licencia](#6-licencia)

---

## 1. **Instalación**

### CocoaPods

Agrega la siguiente línea a tu `Podfile`:

```ruby
pod 'JAAKFaceDetector'
```

Luego ejecuta:

```bash
pod install
```

### Configuración de permisos

Agrega la siguiente clave a tu `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Esta aplicación necesita acceso a la cámara para detectar rostros</string>
```

---

## 2. **Inicio rápido**

### Integración completa con controles y reproductor

```swift
import SwiftUI
import JAAKFaceDetector
import AVKit

struct ContentView: View {
    @StateObject private var faceDetectorManager = FaceDetectorManager()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Vista del detector
                FaceDetectorViewWrapper(manager: faceDetectorManager)
                    .frame(height: UIScreen.main.bounds.height * 0.5)
                    .cornerRadius(16)
                    .padding(.horizontal)
                
                // Estado actual
                Text(faceDetectorManager.statusMessage)
                    .font(.headline)
                    .padding()
                
                // Controles principales
                HStack(spacing: 15) {
                    // Iniciar/Detener
                    Button(action: {
                        faceDetectorManager.toggleDetection()
                    }) {
                        Text(faceDetectorManager.isDetectionActive ? "Detener" : "Iniciar")
                            .foregroundColor(.white)
                            .padding()
                            .background(faceDetectorManager.isDetectionActive ? Color.red : Color.green)
                            .cornerRadius(8)
                    }
                    
                    // Cambiar cámara
                    Button(action: {
                        faceDetectorManager.toggleCamera()
                    }) {
                        Text("Cambiar Cámara")
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                    
                    // Reiniciar
                    Button(action: {
                        faceDetectorManager.restartDetector()
                    }) {
                        Text("Reiniciar")
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.indigo)
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
                
                // Videos grabados
                if !faceDetectorManager.recordedVideos.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Videos Grabados")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(faceDetectorManager.recordedVideos.reversed()) { video in
                            VideoRowView(video: video)
                                .padding(.horizontal)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Face Detector Manager
class FaceDetectorManager: ObservableObject {
    @Published var statusMessage = "Listo para iniciar"
    @Published var isDetectionActive = false
    @Published var recordedVideos: [RecordedVideo] = []
    
    private var faceDetectorUIView: JAAKFaceDetectorUIView?
    private var configuration: JAAKFaceDetectorConfiguration
    
    init() {
        // Configuración con los parámetros solicitados
        configuration = JAAKFaceDetectorConfiguration()
        configuration.videoDuration = 4.0          // 4 segundos
        configuration.autoRecorder = true          // Auto grabación
        configuration.enableInstructions = true    // Instrucciones habilitadas
        configuration.enableMicrophone = false     // Sin audio
        configuration.cameraPosition = .front      // Cámara frontal
    }
    
    func setFaceDetectorUIView(_ view: JAAKFaceDetectorUIView) {
        self.faceDetectorUIView = view
        
        // Auto-iniciar si está configurado
        if configuration.autoRecorder {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.startDetection()
            }
        }
    }
    
    func toggleDetection() {
        if isDetectionActive {
            stopDetection()
        } else {
            startDetection()
        }
    }
    
    func startDetection() {
        faceDetectorUIView?.startDetection { [weak self] success in
            DispatchQueue.main.async {
                self?.isDetectionActive = success
                self?.statusMessage = success ? "Detección activa" : "Error al iniciar"
            }
        }
    }
    
    func stopDetection() {
        faceDetectorUIView?.stopDetection { [weak self] success in
            DispatchQueue.main.async {
                self?.isDetectionActive = !success
                self?.statusMessage = success ? "Detección detenida" : "Error al detener"
            }
        }
    }
    
    func toggleCamera() {
        faceDetectorUIView?.toggleCamera { [weak self] success in
            DispatchQueue.main.async {
                self?.statusMessage = success ? "Cámara cambiada" : "Error al cambiar cámara"
            }
        }
    }
    
    func restartDetector() {
        stopDetection()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.startDetection()
        }
    }
}

// MARK: - Face Detector Delegates
extension FaceDetectorManager: JAAKFaceDetectorViewDelegate {
    func faceDetectorView(_ view: JAAKFaceDetectorView, didCaptureFile fileResult: JAAKFileResult) {
        DispatchQueue.main.async {
            let video = RecordedVideo(
                id: UUID(),
                fileName: fileResult.fileName ?? "video_\(Date().timeIntervalSince1970).mp4",
                data: fileResult.data,
                size: fileResult.fileSize,
                date: Date()
            )
            self.recordedVideos.append(video)
            self.statusMessage = "¡Video capturado! (\(fileResult.fileSize) bytes)"
        }
    }
    
    func faceDetectorView(_ view: JAAKFaceDetectorView, didEncounterError error: Error) {
        DispatchQueue.main.async {
            self.statusMessage = "Error: \(error.localizedDescription)"
        }
    }
    
    func faceDetectorView(status: JAAKFaceDetectorStatus) {
        DispatchQueue.main.async {
            switch status {
            case .loading:
                self.statusMessage = "Cargando modelos..."
            case .loaded:
                self.statusMessage = "Listo para detección"
            case .running:
                self.statusMessage = "Detectando rostro..."
            case .recording:
                self.statusMessage = "¡Grabando video!"
            case .finished:
                self.statusMessage = "Grabación completada"
            case .error:
                self.statusMessage = "Error en detección"
            case .stopped:
                self.statusMessage = "Detección detenida"
            case .notLoaded:
                self.statusMessage = "Modelos no cargados"
            }
        }
    }
    
    func faceDetectorView(didDetectFace message: JAAKFaceDetectionMessage) {
        // Opcional: mostrar mensajes de posicionamiento
        if message.faceExists && !message.correctPosition {
            DispatchQueue.main.async {
                self.statusMessage = "Ajuste la posición del rostro"
            }
        }
    }
}

// MARK: - Wrapper para integración UIKit/SwiftUI
struct FaceDetectorViewWrapper: UIViewRepresentable {
    let manager: FaceDetectorManager
    
    func makeUIView(context: Context) -> JAAKFaceDetectorUIView {
        let view = JAAKFaceDetectorUIView(configuration: manager.configuration)
        view.delegate = manager
        manager.setFaceDetectorUIView(view)
        return view
    }
    
    func updateUIView(_ uiView: JAAKFaceDetectorUIView, context: Context) {}
}

// MARK: - Modelo de Video
struct RecordedVideo: Identifiable {
    let id: UUID
    let fileName: String
    let data: Data
    let size: Int
    let date: Date
}

// MARK: - Vista de Video
struct VideoRowView: View {
    let video: RecordedVideo
    @State private var isExpanded = false
    @State private var videoURL: URL?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(video.fileName)
                        .font(.headline)
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(video.size), countStyle: .file))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(video.date, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    isExpanded.toggle()
                    if isExpanded {
                        createTemporaryVideoFile()
                    }
                }) {
                    Text(isExpanded ? "Cerrar" : "Reproducir")
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isExpanded ? Color.red : Color.blue)
                        .cornerRadius(6)
                }
            }
            
            if isExpanded, let videoURL = videoURL {
                VideoPlayer(player: AVPlayer(url: videoURL))
                    .frame(height: 200)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .onDisappear {
            cleanupTemporaryFile()
        }
    }
    
    private func createTemporaryVideoFile() {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(video.fileName)
        
        do {
            try video.data.write(to: tempURL)
            videoURL = tempURL
        } catch {
            print("Error creating temporary video file: \(error)")
        }
    }
    
    private func cleanupTemporaryFile() {
        if let url = videoURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
```

---

## 3. **Configuración**

### JAAKFaceDetectorConfiguration

| Parámetro | Tipo | Descripción | Valor por defecto |
|-----------|------|-------------|-------------------|
| `videoDuration` | `TimeInterval` | Duración de grabación en segundos | `4.0` |
| `autoRecorder` | `Bool` | Grabación automática al detectar rostro | `false` |
| `cameraPosition` | `AVCaptureDevice.Position` | Posición de cámara (front/back) | `.front` |
| `videoQuality` | `AVCaptureSession.Preset` | Calidad de video | `.high` |
| `enableInstructions` | `Bool` | Mostrar instrucciones al usuario | `true` |
| `instructionDelay` | `TimeInterval` | Tiempo antes de mostrar instrucciones | `5.0` |

### Estilos personalizados

```swift
config.timerStyles.textColor = .white
config.timerStyles.circleColor = .blue
config.timerStyles.strokeWidth = 8.0
config.faceTrackerStyles.validColor = .green
config.faceTrackerStyles.invalidColor = .red
```

---

## 4. **Documentación técnica**

### 4.1 Prerrequisitos técnicos

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

### 4.2 Configuración del entorno

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

### 4.3 Guía de implementación

#### 4.3.1 Implementación básica

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

#### 4.3.2 Implementación avanzada

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

### 4.4 Referencias/Métodos

#### 4.4.1 Especificación principal

**JAAKFaceDetectorSDK - Clase principal del SDK**

**Descripción:** Clase principal que coordina la detección facial, grabación de video y gestión del ciclo de vida del detector. Proporciona una interfaz unificada para todas las funcionalidades del SDK, incluyendo detección en tiempo real, grabación automática y manual, y gestión de permisos.

#### 4.4.2 Parámetros de entrada

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

#### 4.4.3 Estructura de respuesta

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

### 4.5 Componentes adicionales

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

### 4.6 Pruebas y validación

#### a) **Casos de prueba**

| Caso de Prueba | Entrada/Configuración | Resultado Esperado | Criterio de Éxito |
|----------------|----------------------|-------------------|-------------------|
| Inicialización básica | `JAAKFaceDetectorConfiguration()` por defecto | Detector inicializado correctamente | Status cambia a `.loaded` |
| Detección facial | Rostro visible en cámara | Detección exitosa | `didDetectFace` con `faceExists = true` |
| Grabación automática | `autoRecorder = true`, rostro detectado | Video grabado automáticamente | `didCaptureFile` llamado con `JAAKFileResult` |
| Cambio de cámara | `toggleCamera()` | Cámara cambiada exitosamente | Vista actualizada con nueva cámara |
| Manejo de permisos | Permisos denegados | Error de permisos | `didEncounterError` con tipo `permissionDenied` |
| Grabación manual | `recordVideo()` llamado | Video grabado | Archivo de video válido generado |

### 4.7 Solución de problemas

#### a) **Problemas comunes**

| Problema: | La cámara no se inicializa |
|-----------|----------------------------|
| **Descripción:** | El detector no puede acceder a la cámara y permanece en estado `loading` |
| **Causas posibles:** | Permisos de cámara denegados, dispositivo ocupado, configuración incorrecta |
| **Solución:** | Verificar permisos, revisar Info.plist, asegurar que ninguna otra app use la cámara |
| **Código de ejemplo:** | `let status = AVCaptureDevice.authorizationStatus(for: .video)` <br> `if status == .denied { UIApplication.shared.open(settingsUrl) }` |

| Problema: | El detector no detecta rostros |
|-----------|------------------------------|
| **Descripción:** | La detección facial no funciona correctamente |
| **Causas posibles:** | Iluminación insuficiente, rostro parcialmente oculto, configuración incorrecta |
| **Solución:** | Mejorar iluminación, asegurar rostro completamente visible, verificar configuración |
| **Código de ejemplo:** | `if config.disableFaceDetection { config.disableFaceDetection = false; detector.updateConfiguration(config) }` |

| Problema: | La grabación termina inmediatamente |
|-----------|-------------------------------------|
| **Descripción:** | El video se graba pero termina al instante |
| **Causas posibles:** | Configuración de duración incorrecta, problema de sincronización |
| **Solución:** | Verificar `videoDuration`, reiniciar detector |
| **Código de ejemplo:** | `config.videoDuration = max(config.videoDuration, 2.0); detector.updateConfiguration(config)` |

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

### 4.8 Consideraciones importantes

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

## 5. **Anexos**

### **Anexo A.** Glosario de términos

| Término | Definición |
|---------|------------|
| **BlazeFace** | Modelo de detección facial de Google MediaPipe optimizado para móviles |
| **MediaPipe** | Framework de ML de Google para procesamiento multimedia en tiempo real |
| **AVCaptureSession** | Clase de iOS para coordinar entrada y salida de datos multimedia |
| **Auto-recorder** | Funcionalidad que inicia grabación automáticamente al detectar rostro |
| **Face tracking** | Seguimiento facial en tiempo real con overlay visual |

### **Anexo B.** Enlaces de referencia

- [CocoaPods Pod Page](https://cocoapods.org/pods/JAAKFaceDetector)
- [Apple AVFoundation Documentation](https://developer.apple.com/documentation/avfoundation)
- [MediaPipe Face Detection](https://google.github.io/mediapipe/solutions/face_detection.html)
- [iOS Camera Permissions](https://developer.apple.com/documentation/avfoundation/cameras_and_media_capture/requesting_authorization_for_media_capture_on_ios)

---

## 6. **Licencia**

JAAKFaceDetector está disponible bajo la licencia MIT. Ver [LICENSE](LICENSE) para más detalles.

### **Soporte**

Para soporte técnico o reportar issues:
- Email: [diego.bruno@jaak.ai](mailto:diego.bruno@jaak.ai)
- Issues: [GitHub Issues](https://github.com/BrunoSolis5/jaak-face-detector-ios/issues)

### **Historial de versiones**

| Versión | Fecha | Descripción |
|---------|-------|-------------|
| 1.0.0 | 16/07/25 | Primera versión pública disponible en CocoaPods |
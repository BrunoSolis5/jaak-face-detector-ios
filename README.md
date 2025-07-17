# JAAKFaceDetector

[![CocoaPods](https://img.shields.io/cocoapods/v/JAAKFaceDetector.svg)](https://cocoapods.org/pods/JAAKFaceDetector)
[![Platform](https://img.shields.io/cocoapods/p/JAAKFaceDetector.svg)](https://cocoapods.org/pods/JAAKFaceDetector)
[![License](https://img.shields.io/cocoapods/l/JAAKFaceDetector.svg)](https://github.com/BrunoSolis5/jaak-face-detector-ios/blob/main/LICENSE)

AI-powered face detection and recording library for iOS using MediaPipe BlazeFace

## Tabla de contenido

- [Características](#características)
- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Inicio rápido](#inicio-rápido)
- [Uso](#uso)
  - [Implementación básica](#implementación-básica)
  - [Integración con SwiftUI](#integración-con-swiftui)
  - [Uso avanzado](#uso-avanzado)
- [Configuración](#configuración)
- [Referencia de API](#referencia-de-api)
- [Manejo de errores](#manejo-de-errores)
- [Solución de problemas](#solución-de-problemas)
- [Licencia](#licencia)
- [Soporte](#soporte)

## Características

- Detección facial en tiempo real usando MediaPipe BlazeFace
- Grabación automática de video cuando se detecta rostro
- Soporte para cámaras frontal y trasera
- Parámetros de detección altamente configurables
- Componentes UI personalizables y estilos
- Guía y validación de posicionamiento facial
- Compatibilidad con SwiftUI y UIKit
- Enfoque en privacidad (procesamiento local únicamente)

## Requisitos

- iOS 12.0+
- Xcode 12.0+
- Swift 5.0+
- Permisos de acceso a la cámara

## Instalación

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

#### Método 1: Mediante Xcode (Recomendado para versiones modernas)

1. Selecciona tu proyecto en el navegador
2. Ve a la pestaña **"Info"** de tu target
3. Haz clic en el botón **"+"** para agregar una nueva clave
4. Busca y selecciona: **"Privacy - Camera Usage Description"**
5. Agrega el valor: **"Esta aplicación necesita acceso a la cámara para detectar rostros"**

#### Método 2: Editando Info.plist directamente

Para versiones anteriores de Xcode o si prefieres editar el archivo directamente:

```xml
<key>NSCameraUsageDescription</key>
<string>Esta aplicación necesita acceso a la cámara para detectar rostros</string>
```

**Nota:** En versiones modernas de Xcode, el Info.plist tiene un formato diferente y es más recomendable usar la interfaz gráfica para evitar errores de sintaxis.

## Inicio rápido

### Ejemplo completo con SwiftUI

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

## Uso

### Implementación básica

```swift
import UIKit
import JAAKFaceDetector

class ViewController: UIViewController {
    private var detector: JAAKFaceDetectorSDK?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Configuración
        let config = JAAKFaceDetectorConfiguration()
        config.videoDuration = 4.0
        config.autoRecorder = true
        
        // Inicializar detector
        detector = JAAKFaceDetectorSDK(configuration: config)
        detector?.delegate = self
        
        // Crear vista
        let previewView = detector?.createPreviewView()
        previewView?.frame = view.bounds
        view.addSubview(previewView!)
        
        // Iniciar detección
        try? detector?.startDetection()
    }
}

extension ViewController: JAAKFaceDetectorSDKDelegate {
    func faceDetector(_ detector: JAAKFaceDetectorSDK, didCaptureFile result: JAAKFileResult) {
        print("Video capturado: \(result.fileSize) bytes")
    }
    
    func faceDetector(_ detector: JAAKFaceDetectorSDK, didEncounterError error: JAAKFaceDetectorError) {
        print("Error: \(error.localizedDescription)")
    }
}
```

### Integración con SwiftUI

```swift
import SwiftUI
import JAAKFaceDetector

struct ContentView: View {
    @StateObject private var faceDetectorManager = FaceDetectorManager()
    
    var body: some View {
        VStack {
            // Vista del detector
            FaceDetectorViewWrapper(manager: faceDetectorManager)
                .frame(height: 400)
                .cornerRadius(16)
            
            // Estado actual
            Text(faceDetectorManager.statusMessage)
                .font(.headline)
                .padding()
            
            // Controles
            HStack {
                Button(action: {
                    faceDetectorManager.toggleDetection()
                }) {
                    Text(faceDetectorManager.isDetectionActive ? "Detener" : "Iniciar")
                        .foregroundColor(.white)
                        .padding()
                        .background(faceDetectorManager.isDetectionActive ? Color.red : Color.green)
                        .cornerRadius(8)
                }
                
                Button(action: {
                    faceDetectorManager.toggleCamera()
                }) {
                    Text("Cambiar Cámara")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
        }
    }
}

// Wrapper para integración UIKit/SwiftUI
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
```

### Uso avanzado

```swift
// Configuración personalizada
var config = JAAKFaceDetectorConfiguration()
config.videoDuration = 10.0
config.autoRecorder = true
config.cameraPosition = .front
config.enableInstructions = true

// Estilos personalizados
config.timerStyles.textColor = .white
config.timerStyles.circleColor = .blue
config.faceTrackerStyles.validColor = .green
config.faceTrackerStyles.invalidColor = .red
```

## Configuración

### JAAKFaceDetectorConfiguration

| Parámetro | Tipo | Descripción | Valor por defecto |
|-----------|------|-------------|-------------------|
| `videoDuration` | `TimeInterval` | Duración de grabación en segundos | `4.0` |
| `autoRecorder` | `Bool` | Grabación automática al detectar rostro | `false` |
| `cameraPosition` | `AVCaptureDevice.Position` | Posición de cámara (front/back) | `.front` |
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

## Referencia de API

### JAAKFaceDetectorSDK

Clase principal del SDK que coordina la detección facial y grabación de video.

#### Métodos principales

```swift
// Inicializar
init(configuration: JAAKFaceDetectorConfiguration)

// Controlar detección
func startDetection() throws
func stopDetection()
func toggleCamera()

// Grabación manual
func recordVideo(completion: @escaping (Result<JAAKFileResult, Error>) -> Void)
```

#### Delegates

```swift
protocol JAAKFaceDetectorSDKDelegate {
    func faceDetector(_ detector: JAAKFaceDetectorSDK, didUpdateStatus status: JAAKFaceDetectorStatus)
    func faceDetector(_ detector: JAAKFaceDetectorSDK, didCaptureFile result: JAAKFileResult)
    func faceDetector(_ detector: JAAKFaceDetectorSDK, didEncounterError error: JAAKFaceDetectorError)
    func faceDetector(_ detector: JAAKFaceDetectorSDK, didDetectFace message: JAAKFaceDetectionMessage)
}
```

### Estructuras de datos

#### JAAKFileResult
```swift
public struct JAAKFileResult {
    public let data: Data           // Datos binarios del video
    public let base64: String       // Video codificado en base64
    public let mimeType: String?    // Tipo MIME (video/mp4)
    public let fileName: String?    // Nombre del archivo
    public let fileSize: Int        // Tamaño en bytes
}
```

#### JAAKFaceDetectionMessage
```swift
public struct JAAKFaceDetectionMessage {
    public let label: String            // Mensaje descriptivo
    public let details: String?         // Detalles adicionales
    public let faceExists: Bool         // Si se detectó un rostro
    public let correctPosition: Bool    // Si el rostro está en posición correcta
}
```

#### Estados del detector
```swift
public enum JAAKFaceDetectorStatus: String {
    case loading = "loading"
    case loaded = "loaded"
    case running = "running"
    case recording = "recording"
    case finished = "finished"
    case error = "error"
    case stopped = "stopped"
    case notLoaded = "not-loaded"
}
```

## Manejo de errores

### Tipos de error

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

### Ejemplo de manejo de errores

```swift
func faceDetector(_ detector: JAAKFaceDetectorSDK, didEncounterError error: JAAKFaceDetectorError) {
    switch error.code {
    case "camera-access":
        // Solicitar permisos de cámara
        break
    case "model-loading":
        // Reintentar carga del modelo
        break
    default:
        print("Error: \(error.localizedDescription)")
    }
}
```

## Solución de problemas

### Problemas comunes

#### La cámara no se inicializa
- **Causa:** Permisos de cámara denegados
- **Solución:** Verificar permisos y configuración de Info.plist

#### El detector no detecta rostros
- **Causa:** Iluminación insuficiente o rostro parcialmente oculto
- **Solución:** Mejorar iluminación y asegurar rostro completamente visible

#### La grabación termina inmediatamente
- **Causa:** Configuración de duración incorrecta
- **Solución:** Verificar `videoDuration` y reiniciar detector

### Códigos de error específicos

| Código | Descripción | Solución |
|--------|-------------|----------|
| `CAMERA_ACCESS_DENIED` | Permisos denegados | Solicitar permisos nuevamente |
| `MODEL_LOADING_FAILED` | Error al cargar modelo | Reinstalar SDK |
| `RECORDING_IN_PROGRESS` | Grabación en progreso | Esperar a que termine |
| `DEVICE_NOT_SUPPORTED` | Dispositivo no compatible | Usar dispositivo más reciente |

## Licencia

JAAKFaceDetector está disponible bajo la licencia MIT. Ver [LICENSE](LICENSE) para más detalles.

## Soporte

Para soporte técnico o reportar issues:
- Email: [soporte@jaak.ai](mailto:soporte@jaak.ai)
- Issues: [GitHub Issues](https://github.com/BrunoSolis5/jaak-face-detector-ios/issues)

---

### Historial de versiones

| Versión | Fecha | Descripción |
|---------|-------|-------------|
| 1.0.0 | 16/07/25 | Primera versión pública disponible en CocoaPods |
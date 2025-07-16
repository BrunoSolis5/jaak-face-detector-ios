# Guía de Validación QA - Bibliotecas iOS con CocoaPods

## **Tabla de contenido**

1. [Introducción](#1-introducción)
2. [Preparación del ambiente](#2-preparación-del-ambiente)
3. [Creación de proyecto base](#3-creación-de-proyecto-base)
4. [Integración de bibliotecas](#4-integración-de-bibliotecas)
5. [Despliegue en dispositivos](#5-despliegue-en-dispositivos)
6. [Solución de problemas](#6-solución-de-problemas)

---

## 1. **Introducción**

Esta guía está diseñada para personas sin experiencia en desarrollo iOS que necesitan validar bibliotecas integradas con CocoaPods. Siguiendo estos pasos podrás crear aplicaciones de prueba y validar el funcionamiento de cualquier biblioteca iOS.

**Requisitos previos:**
- Mac con macOS 12.0 o superior
- Aproximadamente 2 horas para la configuración inicial
- Cuenta de Apple (gratis para desarrollo)

---

## 2. **Preparación del ambiente**

### 2.1 Instalación de Xcode

1. **Abrir App Store**
   - Buscar "Xcode" en la App Store
   - Hacer clic en "Instalar" (la descarga puede tomar 1-2 horas)

2. **Verificar instalación**
   - Abrir Xcode
   - Aceptar los términos de licencia
   - Esperar a que termine la instalación de componentes adicionales

### 2.2 Instalación de CocoaPods

1. **Abrir Terminal**
   - Presionar `Cmd + Espacio`
   - Escribir "Terminal" y presionar Enter

2. **Instalar CocoaPods**
   ```bash
   sudo gem install cocoapods
   ```
   - Escribir tu contraseña de Mac cuando se solicite
   - Esperar a que termine la instalación (puede tomar varios minutos)

3. **Verificar instalación**
   ```bash
   pod --version
   ```
   - Debe mostrar un número de versión (ej: 1.11.3)

### 2.3 Configuración de cuenta de desarrollador

1. **Abrir Xcode**
2. **Ir a Preferences**
   - Menú: `Xcode → Preferences` (o `Cmd + ,`)
3. **Agregar cuenta**
   - Pestaña "Accounts"
   - Hacer clic en "+" y seleccionar "Apple ID"
   - Ingresar tu Apple ID y contraseña
   - Hacer clic en "Sign In"

---

## 3. **Creación de proyecto base**

### 3.1 Crear nuevo proyecto

1. **Abrir Xcode**
2. **Crear proyecto**
   - Seleccionar "Create a new Xcode project"
   - Elegir "iOS" → "App"
   - Hacer clic en "Next"

3. **Configurar proyecto**
   - **Product Name:** `TestApp` (o cualquier nombre)
   - **Team:** Seleccionar tu cuenta de Apple
   - **Organization Identifier:** `com.tuNombre.TestApp`
   - **Bundle Identifier:** Se genera automáticamente
   - **Language:** Swift
   - **Interface:** Storyboard
   - **Use Core Data:** Dejar desmarcado
   - **Include Tests:** Dejar desmarcado

4. **Guardar proyecto**
   - Elegir una carpeta (ej: Escritorio)
   - Hacer clic en "Create"

### 3.2 Probar proyecto base

1. **Seleccionar simulador**
   - En la barra superior, donde dice "iPhone 14" (o similar)
   - Elegir cualquier simulador disponible

2. **Ejecutar proyecto**
   - Hacer clic en el botón "Play" (▶️) o presionar `Cmd + R`
   - Esperar a que se abra el simulador
   - Debe aparecer una pantalla blanca - esto es normal

3. **Detener proyecto**
   - Hacer clic en el botón "Stop" (⏹️) o presionar `Cmd + .`

---

## 4. **Integración de bibliotecas**

### 4.1 Inicializar CocoaPods

1. **Abrir Terminal**
2. **Navegar al proyecto**
   ```bash
   cd ~/Desktop/TestApp
   ```
   (Ajustar la ruta según donde guardaste el proyecto)

3. **Inicializar CocoaPods**
   ```bash
   pod init
   ```
   - Debe crear un archivo llamado `Podfile`

### 4.2 Configurar biblioteca a probar

1. **Abrir Podfile**
   ```bash
   open Podfile
   ```
   - Se abrirá en un editor de texto

2. **Agregar biblioteca**
   Buscar la línea que dice:
   ```ruby
   # Pods for TestApp
   ```
   
   Debajo de esa línea, agregar la línea específica de la biblioteca según su documentación.

3. **Guardar archivo**
   - Presionar `Cmd + S` y cerrar el editor

### 4.3 Instalar biblioteca

1. **En Terminal, ejecutar:**
   ```bash
   pod install
   ```
   - Esperar a que termine (puede tomar varios minutos)
   - Debe mostrar "Pod installation complete!"

2. **Cerrar Xcode**
   - Importante: cerrar completamente Xcode

3. **Abrir workspace**
   ```bash
   open TestApp.xcworkspace
   ```
   - **Nota:** Siempre usar `.xcworkspace`, nunca `.xcodeproj`

### 4.4 Verificar integración

1. **En Xcode, abrir ViewController.swift**
   - En el panel izquierdo, hacer clic en `ViewController.swift`

2. **Agregar import**
   En la parte superior del archivo, después de `import UIKit`, agregar el import específico de la biblioteca según su documentación.

3. **Compilar proyecto**
   - Presionar `Cmd + B`
   - Si no hay errores, la biblioteca está correctamente integrada

---

## 5. **Despliegue en dispositivos**

### 5.1 Conectar dispositivo

1. **Conectar iPhone/iPad**
   - Usar cable USB
   - Desbloquear dispositivo
   - Si aparece "Trust this computer", seleccionar "Trust"

2. **Configurar dispositivo en Xcode**
   - En la barra superior, hacer clic donde dice el simulador
   - Seleccionar tu dispositivo físico de la lista

### 5.2 Configurar firma de código

1. **Abrir configuración del proyecto**
   - Hacer clic en el nombre del proyecto en el panel izquierdo
   - Seleccionar "Signing & Capabilities"

2. **Configurar Team**
   - Seleccionar tu cuenta de Apple en "Team"
   - Debe mostrar "Signing Certificate" en verde

### 5.3 Desplegar aplicación

1. **Ejecutar en dispositivo**
   - Hacer clic en "Play" (▶️) o presionar `Cmd + R`
   - La primera vez puede tardar más tiempo

2. **Confiar en desarrollador (primera vez)**
   - En el dispositivo: `Settings → General → VPN & Device Management`
   - Buscar tu Apple ID y hacer clic en "Trust"


---

## 6. **Solución de problemas**

### 6.1 Problemas comunes de CocoaPods

**Error: "Command not found: pod"**
- Solución: Reinstalar CocoaPods
```bash
sudo gem install cocoapods
```

**Error al instalar pods**
- Solución: Limpiar caché
```bash
pod cache clean --all
pod install
```

**Error: "No such file or directory"**
- Verificar que estás en la carpeta correcta del proyecto
- Usar `ls` para ver los archivos disponibles

### 6.2 Problemas de Xcode

**Error: "Signing for [App] requires a development team"**
- Ir a proyecto → Signing & Capabilities
- Seleccionar tu cuenta de Apple en "Team"

**Error: "Module not found"**
- Verificar que usas `.xcworkspace` en lugar de `.xcodeproj`
- Limpiar proyecto: `Product → Clean Build Folder`

**Simulador no responde**
- Reiniciar simulador: `Device → Restart`
- Si persiste, reiniciar Xcode

### 6.3 Problemas de dispositivo

**"Could not launch [App]"**
- Verificar que el dispositivo está desbloqueado
- Confiar en el desarrollador en configuración del dispositivo

**App se cierra inmediatamente**
- Revisar permisos en `Info.plist`
- Verificar logs en Xcode: `Window → Devices and Simulators`

### 6.4 Comandos útiles

**Ver logs del dispositivo:**
```bash
# En Xcode: Window → Devices and Simulators → Ver logs
```

**Limpiar CocoaPods:**
```bash
pod deintegrate
pod install
```

**Verificar estado de CocoaPods:**
```bash
pod --version
pod repo update
```

---

## **Notas importantes**

1. **Siempre usar `.xcworkspace`** después de instalar CocoaPods
2. **Guardar trabajo frecuentemente** con `Cmd + S`
3. **Si algo no funciona**, intentar limpiar proyecto (`Product → Clean Build Folder`)
4. **Para probar múltiples bibliotecas**, repetir proceso desde sección 4.2
5. **Cada biblioteca puede requerir configuración específica** - consultar documentación individual

---

## **Contacto de soporte**

Si encuentras problemas no cubiertos en esta guía, incluir en el reporte:
- Capturas de pantalla
- Mensajes de error completos
- Pasos realizados antes del problema

---

*Esta guía está diseñada para ser seguida paso a paso. Tómate tu tiempo y no dudes en repetir pasos si algo no funciona la primera vez.*
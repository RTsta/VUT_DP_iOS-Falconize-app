//
//  CameraService.swift
//  Falconize
//
//  Created by Arthur Nácar on 25.11.2022.
//

import Foundation
import AVFoundation
import UIKit // do budoucna to tady nemá co dělat, teď to tam je kvůli UIDevice.current
import Combine

class CameraService: NSObject {
    
    // published variable reflecting camera states
    @Published var isCaptureButtonEnabled = false
    @Published var isRecordButtonEnabled = false
    @Published var isCameraUnavailable = true
    @Published var deviceLensDirection: AVCaptureDevice.Position = .unspecified
    @Published var flashMode: AVCaptureDevice.FlashMode = .off
    @Published var slowMode: Bool = false
    @Published var isHistoryCaptureReady = false
    
    @Published var videoQuality: VideoSettings = .init(type: .v1080p30fps, codec: .hevc, fileType: .mov)
    
    private var isConfigured = false
    private var isSessionRunning = false
    private var cameraSetupResult: SessionSetupResult = .success
    @Published public var shouldShowSpinner = false
    
    private var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()
    let sessionQueue = DispatchQueue(label: "CameraQueue", qos: .userInteractive)
    var session = AVCaptureSession()
    private var subscriptions = Set<AnyCancellable>()
    
    // delegate for PosePredictor
    var outputDelegates: [AVCaptureVideoDataOutputSampleBufferDelegate] = .init()
    @Published var videoInputDevice: AVCaptureDeviceInput?
    
    private var photoOutput = AVCapturePhotoOutput()
    private var videoOutput = AVCaptureMovieFileOutput()
    
    // devices
    lazy var defaultBackVideoDevice: AVCaptureDevice? = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera], mediaType: .video, position: .back).devices.first // swiftlint:disable:this line_length
    private lazy var defaultFrontVideoDevice: AVCaptureDevice? = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera], mediaType: .video, position: .front).devices.first // swiftlint:disable:this line_length
    
    // those variables are related with zoom functionality in slowmotion mode, because for high frame rate, you have to treat lenses separately
    private lazy var backVideoDevicesForSlowMo: [AVCaptureDevice] = defaultBackVideoDevice?.constituentDevices ?? [AVCaptureDevice.default(for: .video)!]
    @Published var defaultBackDeviceZoomFactors: [NSNumber] = []
    
    private var videoProcessor = VideoCaptureProcessor()
    private lazy var captureHistory: CaptureHistoryProcessor = CaptureHistoryProcessor(videoSettings: self.videoQuality)
    public var isVideoRecording = false
    
    override init() {
        super.init()
        defaultBackDeviceZoomFactors = defaultBackVideoDevice?.virtualDeviceSwitchOverVideoZoomFactors ?? []
        captureHistory.$isReady.sink { [weak self] isReady in
            self?.isHistoryCaptureReady = isReady
        }.store(in: &self.subscriptions)
        
    }
    
    /// Check premissions for camera acces
    public func checkForPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                self.cameraSetupResult = .success
            case .notDetermined: // user never asked for premissions
                sessionQueue.suspend()
                AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                    if !granted {
                        self.cameraSetupResult = .notAuthorized
                    }
                    self.sessionQueue.resume()
                })
                
            default: // user denied camera access
                self.cameraSetupResult = .notAuthorized
                self.isCameraUnavailable = true
                self.isCaptureButtonEnabled = false
                self.isRecordButtonEnabled = false
        }
    }
    
    /// setupCameraSession
    public func setupCameraSession() {
        if cameraSetupResult != .success { // camera premissions not granted
            return
        }
        
        session.beginConfiguration()
        session.sessionPreset = videoQuality.value.preset()
        setupVideoInput()
        
        // setupPhotoOutput()
        // setupVideoOutput()
        addOutputDelegate(delegate: self.captureHistory)
        session.commitConfiguration()
        
        self.isConfigured = true
        self.start()
    }
    
    /// setupVideoInput
    private func setupVideoInput() {
        var videoDevice: AVCaptureDevice?
        // finding default camera device starting with camera, front
        if let defaultBackVideoDevice = defaultBackVideoDevice {
            videoDevice = defaultBackVideoDevice
        } else {
            if let defaultFrontVideoDevice = defaultFrontVideoDevice {
                videoDevice = defaultFrontVideoDevice
            } else {
                videoDevice = AVCaptureDevice.default(for: .video)
            }
        }
        
        guard let videoDevice = videoDevice else {
            myErrorPrint("\(String(describing: self )).\(#function) - Default video device is unavailable.")
            return
        }
        
        do { // adding input to session
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                videoInput.videoMinFrameDurationOverride = CMTimeMake(value: 1, timescale: 120)
                self.videoInputDevice = videoInput
                self.deviceLensDirection = videoInput.device.position
                
            }
        } catch {
            myErrorPrint("\(String(describing: self )).\(#function) - \(error.localizedDescription)")
            cameraSetupResult = .configurationFailed
            self.isConfigured = true
            session.commitConfiguration()
            return
        }
    }
    
    /// setupPhotoOutput
    private func setupPhotoOutput() {
        let output = AVCapturePhotoOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            // photoOutput.maxPhotoDimensions =
            // photoOutput.maxPhotoQualityPrioritization = .quality
        }
    }
    
    /// setupVideoOutput
    private func setupVideoOutput() {
        if self.session.canAddOutput(videoOutput) {
            self.session.addOutput(videoOutput)
            if let connection = videoOutput.connection(with: AVMediaType.video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
        }
    }
    
    /// Adds delegating class to output of AVCaptureSession
    ///
    /// - Parameter delegate: must be of type `AVCaptureVideoDataOutputSampleBufferDelegate`
    func addOutputDelegate(delegate: AVCaptureVideoDataOutputSampleBufferDelegate) {
        sessionQueue.async {
            self.session.beginConfiguration()
            let dataOutput = AVCaptureVideoDataOutput()
            
            if self.session.canAddOutput(dataOutput) {
                self.session.addOutput(dataOutput)
                dataOutput.setSampleBufferDelegate(delegate, queue: self.sessionQueue)
                self.outputDelegates.append(delegate)
            } else {
                return
            }
            self.session.commitConfiguration()
        }
    }
    
    /// Asynchronusly calls CaptureHistoryProcessor to capture video of acction
    public func captureAction() {
        Task {
            await captureHistory.movementActionTrigged()
        }
    }
}


// MARK: Camera actions
extension CameraService {
    
    /// Start camera session
    public func start() {
        sessionQueue.async {
            if !self.isSessionRunning && self.isConfigured {
                switch self.cameraSetupResult {
                    case .success:
                        self.session.startRunning()
                        self.isSessionRunning = self.session.isRunning
                        
                        if self.session.isRunning {
                            DispatchQueue.main.async {
                                self.isCaptureButtonEnabled = true
                                self.isRecordButtonEnabled = true
                                self.isCameraUnavailable = false
                            }
                        }
                        
                    case .configurationFailed, .notAuthorized:
                        myErrorPrint("Application not authorized to use camera")
                        DispatchQueue.main.async {
                            self.isCaptureButtonEnabled = false
                            self.isRecordButtonEnabled = false
                            self.isCameraUnavailable = true
                        }
                }
            }
        }
    }
    
    /// Stop camera session
    public func stop(completion: (() -> Void)? = nil) {
        sessionQueue.async {
            if self.isSessionRunning {
                if self.cameraSetupResult == .success {
                    self.session.stopRunning()
                    self.isSessionRunning = self.session.isRunning
                    if !self.session.isRunning {
                        DispatchQueue.main.async {
                            self.isCaptureButtonEnabled = false
                            self.isRecordButtonEnabled = false
                            self.isCameraUnavailable = true
                            completion?()
                        }
                    }
                }
            }
        }
    }
    
    /// Change to front/back camera
    public func flipCamera() {
        sessionQueue.async {
            guard let deviceInput = self.videoInputDevice else {
                return
            }
            let currentDevice = deviceInput.device
            let currentPosition = currentDevice.position
            var newDevice: AVCaptureDevice?
            
            // nastavení nového vstupního zařízení
            switch currentPosition {
                case .unspecified, .front:
                    newDevice = self.defaultBackVideoDevice
                case .back:
                    newDevice = self.defaultFrontVideoDevice
                @unknown default:
                    print("Unknown capture position. Defaulting to back, dual-camera.")
                    newDevice = AVCaptureDevice.default(for: .video)
            }
            
            if let newDevice = newDevice {
                self.changeDevice(for: newDevice)
            }
        }
    }
    
    /// Changes input device in AVCaptureSession and sets its activeFormat to format with fps
    public func changeDevice(for newDevice: AVCaptureDevice, withFPS fps: Double? = nil) {
        DispatchQueue.main.async {
            self.isCaptureButtonEnabled = false
            self.isRecordButtonEnabled = false
        }
        
        sessionQueue.async {
            guard let currentDeviceInput = self.videoInputDevice else {
                return
            }
            
            do {
                if let fps = fps {
                    newDevice.changeFrameRate(toFPS: fps)
                }
                let input = try AVCaptureDeviceInput(device: newDevice)
                
                self.session.beginConfiguration()
                self.session.removeInput(currentDeviceInput)
                
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.videoInputDevice = input
                    DispatchQueue.main.async {
                        self.outputDelegates.forEach {
                            if let posePredictor = $0 as? PosePredictor {
                                posePredictor.cameraPosition = input.device.position
                            }
                        }
                    }
                } else {
                    self.session.addInput(currentDeviceInput)
                }
                
                if let connection = self.photoOutput.connection(with: .video) {
                    if connection.isVideoStabilizationSupported {
                        connection.preferredVideoStabilizationMode = .auto
                    }
                }
                
                self.session.commitConfiguration()
            } catch {
                print("CameraService - changeDevice() - \(error.localizedDescription)")
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.isCaptureButtonEnabled = true
            self?.isRecordButtonEnabled = true
        }
    }
    
    /// checks what would be best camera device for selected zomm, changes it and zooms in
    ///
    /// - Parameter zoom: zoom value
    public func set(zoom: CGFloat) {
        // let factor = zoom < 1 ? 1 : zoom
        guard let device = videoInputDevice?.device else {
            return
        }
        
        if !device.isVirtualDevice { // in slowmotion mode, you have to manualy change devices, because virtual devices doesnt support 120/240fps
            self.changeLensesIfNeeded(zoom: zoom)
        }
        
        self.zoom(zoom)
    }
    
    /// zoom current device
    private func zoom(_ zoom: CGFloat) {
        guard let device = videoInputDevice?.device else {
            return
        }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = zoom
            device.unlockForConfiguration()
        } catch {
            print(error.localizedDescription)
        }
    }
    
    /// finds the best device, for selected zoom level and eventualy changes device in camera session for the best device
    private func changeLensesIfNeeded(zoom: CGFloat) {
        guard let device = videoInputDevice?.device else {
            return
        }
        
        let allAvaibileZoom = [1] + (defaultBackDeviceZoomFactors as? [CGFloat] ?? [])
        let bestCameraIndex = allAvaibileZoom.lastIndex { deviceFactor in
            deviceFactor <= zoom
        }
        
        guard let bestCameraIndex = bestCameraIndex else {
            return
        }
        let deviceForTheJob = backVideoDevicesForSlowMo[bestCameraIndex]
        
        if device.deviceType != deviceForTheJob.deviceType {
            changeDevice(for: deviceForTheJob, withFPS: videoQuality.value.fps())
        }
    }
    
    /// focus the lens to selected point. The point must be converted using `AVCaptureVideoPreviewLayer.captureDevicePointConverted(fromLayerPoint:)`
    public func focus(at focusPoint: CGPoint) {
        guard let device = self.videoInputDevice?.device else {
            return
        }
        
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = focusPoint
                device.focusMode = .continuousAutoFocus
                device.exposurePointOfInterest = focusPoint
                device.exposureMode = .continuousAutoExposure
                device.unlockForConfiguration()
            }
        } catch {
            print(error.localizedDescription)
        }
    }
    
    /// Switch on/off mode when device recording in high fps
    func switchSlowMode() {
        if slowMode {
            guard let device = defaultBackVideoDevice else {
                return
            }
            device.changeFrameRate(toFPS: 30) // default value of 30fps
            changeDevice(for: device)
            slowMode.toggle()
        } else {
            guard let device = backVideoDevicesForSlowMo.first else {
                return
            }
            videoQuality = .init(type: .v1080p120fps, codec: videoQuality.codec, fileType: videoQuality.fileType)
            captureHistory.changeSettings(newSettings: videoQuality)
            changeDevice(for: device)
            device.changeFrameRate(toFPS: videoQuality.value.fps())
            slowMode.toggle()
        }
    }
}

// MARK: - Photo Capture
// all functions for taking photos
extension CameraService {
    
    /// capturePhoto
    ///
    /// inspired by https://betterprogramming.pub/effortless-swiftui-camera-d7a74abde37e
    func capturePhoto() {
        guard self.cameraSetupResult != .configurationFailed else {
            return
        }
        self.isCaptureButtonEnabled = false
        self.isRecordButtonEnabled = false
        sessionQueue.async {
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                photoOutputConnection.videoOrientation = .portrait
            }
            var photoSettings = AVCapturePhotoSettings()
            
            // Capture HEIF photos when supported. Enable according to user settings and high-resolution photos.
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            
            // Sets the flash option for this capture.
            if let dev = self.videoInputDevice,
               dev.device.isFlashAvailable {
                photoSettings.flashMode = self.flashMode
            }
            
            // Sets the preview thumbnail pixel format
            if !photoSettings.__availablePreviewPhotoPixelFormatTypes.isEmpty {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: photoSettings.__availablePreviewPhotoPixelFormatTypes.first!]
            }
            
            
            let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, completionHandler: { (photoCaptureProcessor) in
                // When the capture is complete, remove a reference to the photo capture delegate so it can be deallocated.
                // swiftlint:disable:next unused_optional_binding
                if let _ = photoCaptureProcessor.photoData {
                    // self.photo = Photo(originalData: data)
                } else {
                    myDebugPrint("No photo data")
                }
                
                self.isCaptureButtonEnabled = true
                self.isRecordButtonEnabled = true
                
                self.sessionQueue.async {
                    self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
                }
            }, photoProcessingHandler: { animate in
                // Animates a spinner while photo is processing
                if animate {
                    self.shouldShowSpinner = true
                } else {
                    self.shouldShowSpinner = false
                }
            })
            
            // The photo output holds a weak reference to the photo capture delegate and stores it in an array to maintain a strong reference.
            self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = photoCaptureProcessor
            self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureProcessor)
        }
    }
}

// MARK: - Video Recording
// All functions for recording video
extension CameraService {
    /// startVideoRecording
    func startVideoRecording() {
        guard isSessionRunning == true else {
            myErrorPrint("Cannot start video recoding. Capture session is not running")
            return
        }
        // Must be fetched before on main thread
        let previewOrientation = UIDevice.current.orientation
        
        sessionQueue.async { [unowned self] in
            if !videoOutput.isRecording {
                if UIDevice.current.isMultitaskingSupported {
                    self.videoProcessor.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                }
                
                // Update the orientation on the movie file output video connection before starting recording.
                let movieFileOutputConnection = self.videoOutput.connection(with: AVMediaType.video)
                switch previewOrientation {
                    case .portrait:
                        movieFileOutputConnection?.videoOrientation = .portrait
                    case .landscapeLeft:
                        movieFileOutputConnection?.videoOrientation = .landscapeLeft
                    case .landscapeRight:
                        movieFileOutputConnection?.videoOrientation = .landscapeRight
                    default:
                        break
                }
                
                // Start recording to a temporary file.
                let outputFileName = UUID().uuidString
                let outputFilePath = URL.temporaryDirectory.appendingPathComponent(outputFileName).appendingPathExtension("mov")
                videoOutput.startRecording(to: outputFilePath, recordingDelegate: videoProcessor)
                self.isVideoRecording = true
            } else {
                videoOutput.stopRecording()
            }
        }
    }
    
    /// stopVideoRecording
    func stopVideoRecording() {
        if self.isVideoRecording == true {
            self.isVideoRecording = false
            videoOutput.stopRecording()
        }
    }
}

// MARK: CameraService - enum declaration
extension CameraService {
    
    /// enumeration for camera premission result
    enum SessionSetupResult {
        /// user approved camera usage
        case success
        /// user was never asked for camera usage
        case notAuthorized
        /// user denied camera usage
        case configurationFailed
    }
}

// MARK: CameraService - private functions
private extension CameraService {
    /// helper function for all posible values of back devices
    func allBackDeviceTypes() -> [AVCaptureDevice.DeviceType] {
        [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera]
    }
}

// MARK: AVCaptureDevice - extension
private extension AVCaptureDevice {
    func findFormat(fps: Double, width: Int32, height: Int32) -> Format? {
        
        self.formats.first { format in
            format.videoSupportedFrameRateRanges.contains { range in
                range.minFrameRate <= fps && fps <= range.maxFrameRate
            }
            && format.formatDescription.dimensions.width == width
            && format.formatDescription.dimensions.height == height
        }
    }
    
    /// changes activeFormat and fps of device
    func changeFrameRate(toFPS fps: Double) {
        let newFormat = self.findFormat(fps: fps,
                                        width: self.activeFormat.formatDescription.dimensions.width,
                                        height: self.activeFormat.formatDescription.dimensions.height)
        if let newFormat = newFormat {
            do {
                try self.lockForConfiguration()
                self.activeFormat = newFormat
                self.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(fps))
                self.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(fps))
                self.unlockForConfiguration()
            } catch {
                // Handle error.
            }
        }
    }
}

//
//  CameraService.swift
//  Falconize
//
//  Created by Arthur Nácar on 25.11.2022.
//

import Foundation
import AVFoundation
import UIKit // FIXME: do budoucna to tady nemá co dělat

class CameraService: NSObject {
    
    @Published public var flashMode: AVCaptureDevice.FlashMode = .off
    @Published public var willCapturePhoto = false
    @Published public var isCameraButtonDisabled = true
    @Published public var isCameraUnavailable = true
    @Published var deviceLensDirection: AVCaptureDevice.Position = .unspecified
    
    private var isConfigured = false
    private var isSessionRunning = false
    private var cameraSetupResult: SessionSetupResult = .success
    @Published public var shouldShowSpinner = false
    
    private var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()
    let sessionQueue = DispatchQueue(label: "CameraQueue", qos: .userInteractive)
    var session = AVCaptureSession()
    
    // delegate for PosePredictor
    var outputDelegates: [AVCaptureVideoDataOutputSampleBufferDelegate] = .init()
    
    private var deviceInput: AVCaptureDeviceInput?
    @Published var photoOutput = AVCapturePhotoOutput()
    
    @Published var videoOutput = AVCaptureMovieFileOutput()
    private var videoProcessor = VideoCaptureProcessor()
    public var isVideoRecording = false
    /// Video will be recorded to this folder
    public var outputFolder: String = NSTemporaryDirectory()
    
    private var captureHistory: CaptureHistoryProcessor = CaptureHistoryProcessor(videoSettings: .init(width: 1920, height: 1080, codec: .hevc, fileType: .mov, frameRate: 30))
    
    
    public func checkForPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
                self.cameraSetupResult = .success
        case .notDetermined:
                sessionQueue.suspend()
                AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                    if !granted {
                        self.cameraSetupResult = .notAuthorized
                    }
                    self.sessionQueue.resume()
                })
                
        default:
                self.cameraSetupResult = .notAuthorized
                self.isCameraUnavailable = true
                self.isCameraButtonDisabled = true
        }
    }
    
    public func setupCameraSession() {
        if cameraSetupResult != .success {
            return
        }
        
        session.beginConfiguration()
        setupVideoInput()
        // session.sessionPreset = .photo
        setupPhotoOutput()
        setupVideoOutput()
        addHistoryBufferTest()
        
        session.commitConfiguration()
        self.isConfigured = true
        self.start()
    }
    
    private func setupVideoInput() {
        var defaultVideoDevice: AVCaptureDevice? = AVCaptureDevice.default(for: .video)
        guard let videoDevice = defaultVideoDevice else {
            debugPrint("Default video device is unavailable.")
            return
        }
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                self.deviceInput = videoInput
                self.deviceLensDirection = videoInput.device.position
                
            }
        } catch {
            print("CameraService - configureSession")
            print(error.localizedDescription)
            cameraSetupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
    }
    
    private func setupPhotoOutput() {
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            // photoOutput.maxPhotoDimensions =
            // photoOutput.maxPhotoQualityPrioritization = .quality
        }
    }
    
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
    
    // FIXME: kdyžtak refactorovat a přemazat
    func addHistoryBufferTest() {
        sessionQueue.async {
            self.session.beginConfiguration()
            let dataOutput = AVCaptureVideoDataOutput()
            if self.session.canAddOutput(dataOutput) {
                self.session.addOutput(dataOutput)
                dataOutput.setSampleBufferDelegate(self.captureHistory, queue: self.sessionQueue)
                self.outputDelegates.append(self.captureHistory)
            } else {
                return
                
            }
            self.session.commitConfiguration()
        }
    }
    
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
    
    public func start() {
        sessionQueue.async {
            if !self.isSessionRunning && self.isConfigured {
                switch self.cameraSetupResult {
                    case .success:
                        self.session.startRunning()
                        self.isSessionRunning = self.session.isRunning
                        
                        if self.session.isRunning {
                            DispatchQueue.main.async {
                                self.isCameraButtonDisabled = false
                                self.isCameraUnavailable = false
                            }
                        }
                        
                    case .configurationFailed, .notAuthorized:
                        print("Application not authorized to use camera")
                        DispatchQueue.main.async {
                            self.isCameraButtonDisabled = true
                            self.isCameraUnavailable = true
                        }
                }
            }
        }
    }
    
    public func stop(completion: (() -> Void)? = nil) {
        sessionQueue.async {
            if self.isSessionRunning {
                if self.cameraSetupResult == .success {
                    self.session.stopRunning()
                    self.isSessionRunning = self.session.isRunning
                    
                    if !self.session.isRunning {
                        DispatchQueue.main.async {
                            self.isCameraButtonDisabled = true
                            self.isCameraUnavailable = true
                            completion?()
                        }
                    }
                }
            }
        }
    }
    
    public func changeCamera() {
        DispatchQueue.main.async {
            self.isCameraButtonDisabled = true
        }
        
        sessionQueue.async {
            guard let deviceInput = self.deviceInput else {
                return
            }
            let currentDevice = deviceInput.device
            let currentPosition = currentDevice.position
            var newDevice: AVCaptureDevice?
            
            let backVideoDeviceDiscoverySession = AVCaptureDevice.default(for: .video)
            let frontVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera], mediaType: .video, position: .front)
            
            // nastavení nového vstupního zařízení
            switch currentPosition {
                case .unspecified, .front:
                    newDevice = backVideoDeviceDiscoverySession
                case .back:
                    newDevice = frontVideoDeviceDiscoverySession.devices.first
                @unknown default:
                    print("Unknown capture position. Defaulting to back, dual-camera.")
                    newDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
            }
            
            if let newDevice = newDevice {
                do {
                    let input = try AVCaptureDeviceInput(device: newDevice )
                    self.session.beginConfiguration()
                    if let currentDeviceInput = self.deviceInput {
                        self.session.removeInput(currentDeviceInput)
                    }
                    
                    if self.session.canAddInput(input) {
                        self.session.addInput(input)
                        self.deviceInput = input
                        DispatchQueue.main.async {
                            self.outputDelegates.forEach {
                                if let posePredictor = $0 as? PosePredictor {
                                    posePredictor.cameraPosition = input.device.position
                                }
                            }
                        }
                        
                    } else {
                        if let currentDeviceInput = self.deviceInput {
                            self.session.addInput(currentDeviceInput)
                        }
                    }
                    
                    if let connection = self.photoOutput.connection(with: .video) {
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = .auto
                        }
                    }
                    
                    self.session.commitConfiguration()
                } catch {
                    print("CameraService - changecamera() - \(error.localizedDescription)")
                }
            }
            
            DispatchQueue.main.async {
                self.isCameraButtonDisabled = false
            }
        }
    }
    
    public func set(zoom: CGFloat) {
        let factor = zoom < 1 ? 1 : zoom
        guard let device = deviceInput?.device else {
            return
        }
        
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = factor
            device.unlockForConfiguration()
        } catch {
            print(error.localizedDescription)
        }
    }
    
    // podle https://betterprogramming.pub/effortless-swiftui-camera-d7a74abde37e
    func capturePhoto() {
        guard self.cameraSetupResult != .configurationFailed else {
            return
        }
        self.isCameraButtonDisabled = true
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
            if let dev = self.deviceInput,
               dev.device.isFlashAvailable {
                photoSettings.flashMode = self.flashMode
            }
            
            
            // Sets the preview thumbnail pixel format
            if !photoSettings.__availablePreviewPhotoPixelFormatTypes.isEmpty {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: photoSettings.__availablePreviewPhotoPixelFormatTypes.first!]
            }
            
            
            let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, completionHandler: { (photoCaptureProcessor) in
                // When the capture is complete, remove a reference to the photo capture delegate so it can be deallocated.
                if let data = photoCaptureProcessor.photoData {
                    // self.photo = Photo(originalData: data)
                    debugPrint(data.debugDescription)
                    myDebugPrint("passing photo")
                } else {
                    myDebugPrint("No photo data")
                }
                
                self.isCameraButtonDisabled = false
                
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
    
    public func startVideoRecording() {
        
        //        guard sessionRunning == true else {
        //            print("[SwiftyCam]: Cannot start video recoding. Capture session is not running")
        //            return
        //        }
        
        
        // Must be fetched before on main thread
        // let previewOrientation = previewLayer.videoPreviewLayer.connection!.videoOrientation
        
        sessionQueue.async { [unowned self] in
            if !videoOutput.isRecording {
                if UIDevice.current.isMultitaskingSupported {
                    self.videoProcessor.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                }
                
                // Update the orientation on the movie file output video connection before starting recording.
                let movieFileOutputConnection = self.videoOutput.connection(with: AVMediaType.video)
                
                
                // flip video output if front facing camera is selected
                //                if self.currentCamera == .front {
                //                    movieFileOutputConnection?.isVideoMirrored = true
                //                }
                
                // videoOutput?.videoOrientation = self.orientation.getVideoOrientation() ?? previewOrientation
                
                // Start recording to a temporary file.
                let outputFileName = UUID().uuidString
                let outputFilePath = (self.outputFolder as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
                videoOutput.startRecording(to: URL(fileURLWithPath: outputFilePath), recordingDelegate: videoProcessor)
                self.isVideoRecording = true
            } else {
                videoOutput.stopRecording()
            }
        }
    }
    
    public func stopVideoRecording() {
        if self.isVideoRecording == true {
            self.isVideoRecording = false
            videoOutput.stopRecording()
            // disableFlash()
            
            //            if currentCamera == .front && flashMode == .on && flashView != nil {
            //                UIView.animate(withDuration: 0.1, delay: 0.0, options: .curveEaseInOut, animations: {
            //                    self.flashView?.alpha = 0.0
            //                }, completion: { (_) in
            //                    self.flashView?.removeFromSuperview()
            //                })
            //            }
            //            DispatchQueue.main.async {
            //                self.cameraDelegate?.swiftyCam(self, didFinishRecordingVideo: self.currentCamera)
            //            }
        }
    }
    
    public func captureAction() {
        Task {
            await captureHistory.testAction()
        }
    }
}
extension CameraService {
    enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
}

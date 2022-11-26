//
//  CameraVC.swift
//  Falconize
//
//  Created by Arthur Nácar on 29.09.2022.
//

import Foundation
import UIKit
import AVFoundation
import Photos
import Combine

final class CameraViewController: UIViewController {
    //ViewModel
    var cameraViewStore : CameraViewStore = CameraViewStore()
    
    private let cameraSessionQueue = DispatchQueue(label: "CameraOutput", qos: .userInteractive)
    private var cameraSession: AVCaptureSession = AVCaptureSession()
    
    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!
    var delegate: AVCaptureVideoDataOutputSampleBufferDelegate?
    
    private var cameraView: CameraPreviewUIView { view as! CameraPreviewUIView }
    var cameraDirection: AVCaptureDevice.Position = .unspecified
    
    
    //capturing photo
    private let photoOutput = AVCapturePhotoOutput()
    private var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()
    
    private var setupResult: SessionSetupResult = .success
    
    var isSessionRunning: Bool = false
    
    private var spinner: UIActivityIndicatorView!
    
    var windowOrientation: UIInterfaceOrientation {
        return view.window?.windowScene?.interfaceOrientation ?? .unknown
    }
    
    // MARK: Recording Movies
    private var movieFileOutput: AVCaptureMovieFileOutput?
    
    /**
     loadView
     Nastavuje CameraPreviewUIView jako hlavní view pro tento Controller
     */
    override func loadView() {
        view = CameraPreviewUIView()
    }
    
    /**
     viewDidLoad
     Kontrola povolení fotoaparátu a vytvoření AVsession
     */
    override func viewDidLoad() {
        super.viewDidLoad()
        
        checkPremission()
        cameraSessionQueue.async {
            self.configureAVSession()
        }
    }
    
    /**
     viewDidAppear
     */
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        configureAVSession()
        cameraView.previewLayer.session = cameraSession
        cameraView.previewLayer.videoGravity = .resizeAspectFill
        
        DispatchQueue.global(qos: .background).async {
            self.cameraSession.startRunning()
            self.isSessionRunning = self.cameraSession.isRunning
        }
        
    }
    
    /**
     viewWilldisappear
     */
    override func viewWillDisappear(_ animated: Bool) {
        cameraSessionQueue.async {
            self.cameraSession.stopRunning()
            self.isSessionRunning = self.cameraSession.isRunning
        }
        
        super.viewWillDisappear(animated)
    }
    
    // MARK: - Screen orientation
    // Disable autorotation of the interface when recording is in progress.
    override var shouldAutorotate: Bool {
        if let movieFileOutput = movieFileOutput {
            return !movieFileOutput.isRecording
        }
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    //    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
    //        super.viewWillTransition(to: size, with: coordinator)
    //
    //        if let videoPreviewLayerConnection = previewView.videoPreviewLayer.connection {
    //            let deviceOrientation = UIDevice.current.orientation
    //            guard let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation),
    //                deviceOrientation.isPortrait || deviceOrientation.isLandscape else {
    //                    return
    //            }
    //
    //            videoPreviewLayerConnection.videoOrientation = newVideoOrientation
    //        }
    //    }
}

//MARK: - AVSession Setup
extension CameraViewController {
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    /**
     checkPremission
     Kontrola, jestli jsou povolené přístupové práva pro fotoaparát
     */
    func checkPremission(){
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                break
            case .notDetermined:
                cameraSessionQueue.suspend()
                AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                    if !granted {
                        self.setupResult = .notAuthorized
                    }
                    self.cameraSessionQueue.resume()
                })
            default:
                setupResult = .notAuthorized
        }
    }
    
    /**
     prepareAVSession
     pokud jsou povolené práva pro fotoaparát, tak se nastaví zařízení pro input a output
     */
    func configureAVSession() {
        if setupResult != .success {
            return
        }
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = AVCaptureSession.Preset.high
        
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera,for: .video, position: cameraDirection)
        else { return }
        
        guard let deviceInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }
        guard session.canAddInput(deviceInput) else { fatalError("Cant add device input") }
        session.addInput(deviceInput)
        self.videoDeviceInput = deviceInput
        
        let dataOutput = AVCaptureVideoDataOutput()
        if session.canAddOutput(dataOutput) {
            session.addOutput(dataOutput)
            dataOutput.setSampleBufferDelegate(delegate, queue: cameraSessionQueue)  
        } else { return }
        
        session.commitConfiguration()
        cameraSession = session
    }
    
    /**
     createVideoDeviceInput
     Vytvoří se vstupní zařízení pro CaptureSession
     */
    func createVideoDeviceInput() throws {
        var defaultVideoDevice: AVCaptureDevice?
        
        // Choose the back dual camera, if available, otherwise default to a wide angle camera.
        if let dualCameraDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
            defaultVideoDevice = dualCameraDevice
        } else if let dualWideCameraDevice = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
            // If a rear dual camera is not available, default to the rear dual wide camera.
            defaultVideoDevice = dualWideCameraDevice
        } else if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            // If a rear dual wide camera is not available, default to the rear wide angle camera.
            defaultVideoDevice = backCameraDevice
        } else if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            // If the rear wide angle camera isn't available, default to the front wide angle camera.
            defaultVideoDevice = frontCameraDevice
        }
        
        guard let videoDevice = defaultVideoDevice else {
            print("Default video device is unavailable.")
            setupResult = .configurationFailed
            cameraSession.commitConfiguration()
            return
        }
        
        let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        
        if cameraSession.canAddInput(videoDeviceInput) {
            cameraSession.addInput(videoDeviceInput)
            self.videoDeviceInput = videoDeviceInput
            
            DispatchQueue.main.async {
                var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                if self.windowOrientation != .unknown {
                    if let videoOrientation = AVCaptureVideoOrientation(rawValue: self.windowOrientation.rawValue) {
                        initialVideoOrientation = videoOrientation
                    }
                }
                
                
                self.cameraView.videoPreviewLayer.connection?.videoOrientation = initialVideoOrientation
            }
        }
        
        
    }
}


// MARK: - button actions
extension CameraViewController {
    func captureBtnAction(){
        /*
         Retrieve the video preview layer's video orientation on the main queue before
         entering the session queue. Do this to ensure that UI elements are accessed on
         the main thread and session configuration is done on the session queue.
         */
        
        let videoPreviewLayerOrientation = cameraView.videoPreviewLayer.connection?.videoOrientation
        
        cameraSessionQueue.async {
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                photoOutputConnection.videoOrientation = videoPreviewLayerOrientation!
            }
            var photoSettings = AVCapturePhotoSettings()
            
            // Capture HEIF photos when supported. Enable auto-flash and high-resolution photos.
            if  self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            
            if self.videoDeviceInput.device.isFlashAvailable {
                photoSettings.flashMode = .auto
            }
            
            photoSettings.isHighResolutionPhotoEnabled = true
            if let previewPhotoPixelFormatType = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: previewPhotoPixelFormatType]
            }
            
            let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, willCapturePhotoAnimation: {
                // Flash the screen to signal that AVCam took a photo.
                DispatchQueue.main.async {
                    self.cameraView.videoPreviewLayer.opacity = 0
                    UIView.animate(withDuration: 0.25) {
                        self.cameraView.videoPreviewLayer.opacity = 1
                    }
                }
            }, completionHandler: { photoCaptureProcessor in
                // When the capture is complete, remove a reference to the photo capture delegate so it can be deallocated.
                self.cameraSessionQueue.async {
                    self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
                }
            }, photoProcessingHandler: { animate in
                // Animates a spinner while photo is processing
                DispatchQueue.main.async {
                    if animate {
                        self.spinner.hidesWhenStopped = true
                        self.spinner.center = CGPoint(x: self.cameraView.previewLayer.frame.size.width / 2.0, y: self.cameraView.previewLayer.frame.size.height / 2.0)
                        self.spinner.startAnimating()
                    } else {
                        self.spinner.stopAnimating()
                    }
                }
            }
            )
            
            // The photo output holds a weak reference to the photo capture delegate and stores it in an array to maintain a strong reference.
            self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = photoCaptureProcessor
            self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureProcessor)
        }
        
        
        
        
        DispatchQueue.main.async {
            self.cameraViewStore.captureButtonTriggered = false
            self.cameraViewStore.switchCameraButtonTriggered = false
        }
    }
    
    func switchCameraBtnAction(){
        DispatchQueue.main.async {
            self.cameraViewStore.switchCameraBtnEnabled = false
            self.cameraViewStore.captureBtnEnabled = false
        }
        
        cameraSessionQueue.async {
            let currentVideoDevice = self.videoDeviceInput.device
            let currentPosition = currentVideoDevice.position
            var newVideoDevice: AVCaptureDevice? = nil
            
            // zjištění všech dostupných záznamových zařízení
            let backVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera, .builtInDualWideCamera, .builtInWideAngleCamera], mediaType: .video, position: .back)
            let frontVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera], mediaType: .video, position: .front)
            
            //nastavení nového vstupního zařízení
            switch currentPosition {
                case .unspecified, .front:
                    newVideoDevice = backVideoDeviceDiscoverySession.devices.first
                case .back:
                    newVideoDevice = frontVideoDeviceDiscoverySession.devices.first
                @unknown default:
                    print("Unknown capture position. Defaulting to back, dual-camera.")
                    newVideoDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
            }
            
            if let videoDevice = newVideoDevice {
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                    self.cameraSession.beginConfiguration()
                    
                    self.cameraSession.removeInput(self.videoDeviceInput) // Remove the existing device input first, because AVCaptureSession doesn't support simultaneous use of the rear and front cameras.
                    
                    if self.cameraSession.canAddInput(videoDeviceInput) {
                        
                        //FIXME: asi můžu vymazat
                        //NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: currentVideoDevice)
                        //NotificationCenter.default.addObserver(self, selector: #selector(self.subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)
                        
                        self.cameraSession.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                    } else {
                        self.cameraSession.addInput(self.videoDeviceInput)
                    }
                    
                    if let connection = self.movieFileOutput?.connection(with: .video) {
                        self.cameraSession.sessionPreset = .high
                        
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = .auto
                        }
                    }
                    
                    /*
                     Set Live Photo capture and depth data delivery if it's supported. When changing cameras, the
                     `livePhotoCaptureEnabled` and `depthDataDeliveryEnabled` properties of the AVCapturePhotoOutput
                     get set to false when a video device is disconnected from the session. After the new video device is
                     added to the session, re-enable them on the AVCapturePhotoOutput, if supported.
                     */
                    
                    self.photoOutput.maxPhotoQualityPrioritization = .quality
                    
                    self.cameraSession.commitConfiguration()
                } catch {
                    print("Error occurred while creating video device input: \(error)")
                }
            }
        }
        
        //znovu zaktivování tlačítek
        DispatchQueue.main.async {
            self.cameraViewStore.captureButtonTriggered = false
            self.cameraViewStore.switchCameraButtonTriggered = false // protože to zároveň změnít switchCameraBtnEnabled
        }
    }
}

// MARK: Camera Actions
extension CameraViewController {
    private func focus(with focusMode: AVCaptureDevice.FocusMode,
                       exposureMode: AVCaptureDevice.ExposureMode,
                       at devicePoint: CGPoint,
                       monitorSubjectAreaChange: Bool) {
        
        cameraSessionQueue.async {
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()
                
                /*
                 Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
                 Call set(Focus/Exposure)Mode() to apply the new point of interest.
                 */
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = focusMode
                }
                
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = exposureMode
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }
}

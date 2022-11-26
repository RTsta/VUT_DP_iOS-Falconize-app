//
//  CameraService.swift
//  Falconize
//
//  Created by Arthur Nácar on 25.11.2022.
//

import Foundation
import AVFoundation
import UIKit//FIXME: do budoucna to tady nemá co dělat

class CameraService: NSObject {
    
    @Published public var flashMode: AVCaptureDevice.FlashMode = .off
    @Published public var willCapturePhoto = false
    @Published public var isCameraButtonDisabled = true
    @Published public var isCameraUnavailable = true
    @Published var deviceLensDirection : AVCaptureDevice.Position = .unspecified
    
    private var cameraPremissionsGranted: Bool = false
    
    let sessionQueue = DispatchQueue(label: "CameraQueue", qos: .userInteractive)
    
    private var isSessionRunning = false
    
    var session = AVCaptureSession()
    
    //delegate for PosePredictor
    var outputDelegates : [AVCaptureVideoDataOutputSampleBufferDelegate] = .init()
    
    private var deviceInput: AVCaptureDeviceInput?
    @Published var photoOutput = AVCapturePhotoOutput()
    
    
    
    public func checkForPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                self.cameraPremissionsGranted = true
                break
            case .notDetermined:
                sessionQueue.suspend()
                AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                    self.cameraPremissionsGranted = granted
                    self.sessionQueue.resume()
                })
                
            default:
                self.cameraPremissionsGranted = false
                self.isCameraUnavailable = true
                self.isCameraButtonDisabled = true
        }
    }
    
    public func setupCameraSession() {
        if !cameraPremissionsGranted {
            return
        }
        
        var defaultVideoDevice: AVCaptureDevice? = AVCaptureDevice.default(for: .video)
        guard let videoDevice = defaultVideoDevice else {
            debugPrint("Default video device is unavailable.")
            return
        }
        
        session.beginConfiguration()
        //session.sessionPreset = .photo
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
            session.commitConfiguration()
            return
        }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            //photoOutput.maxPhotoDimensions =
            //photoOutput.maxPhotoQualityPrioritization = .quality
        }
        
        session.commitConfiguration()
        
        self.start()
    }
    
    func addOutputDelegate(delegate: AVCaptureVideoDataOutputSampleBufferDelegate){
        sessionQueue.async {
            self.session.beginConfiguration()
            let dataOutput = AVCaptureVideoDataOutput()
            if self.session.canAddOutput(dataOutput) {
                self.session.addOutput(dataOutput)
                dataOutput.setSampleBufferDelegate(delegate, queue: self.sessionQueue)
                self.outputDelegates.append(delegate)
                
            } else { return }
            self.session.commitConfiguration()
        }
    }
    
    public func start() {
        sessionQueue.async {
            self.session.startRunning()
            self.isSessionRunning = self.session.isRunning
            
            if self.session.isRunning {
                DispatchQueue.main.async {
                    self.isCameraButtonDisabled = false
                    self.isCameraUnavailable = false
                }
            }
        }
    }
    
    public func stop(completion: (() -> ())? = nil) {
        sessionQueue.async {
            if self.isSessionRunning {
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
    
    public func changeCamera() {
        DispatchQueue.main.async {
            self.isCameraButtonDisabled = true
        }
        
        sessionQueue.async {
            guard let deviceInput = self.deviceInput else {return}
            let currentDevice = deviceInput.device
            let currentPosition = currentDevice.position
            var newDevice : AVCaptureDevice? = nil
            
            let backVideoDeviceDiscoverySession = AVCaptureDevice.default(for: .video)
            let frontVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera], mediaType: .video, position: .front)
            
            //nastavení nového vstupního zařízení
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
                            self.outputDelegates.forEach{
                                if let posePredictor = $0 as? PosePredictor {
                                    posePredictor.cameraPosition = input.device.position
                                }
                            }
                        }
                        
                    }else{
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
    
    public func set(zoom: CGFloat){
        let factor = zoom < 1 ? 1 : zoom
        guard let device = deviceInput?.device else { return }
        
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = factor
            device.unlockForConfiguration()
        }
        catch {
            print(error.localizedDescription)
        }
    }
    
    //FIXME: - vylepšit podle https://betterprogramming.pub/effortless-swiftui-camera-d7a74abde37e
    func capturePhoto(){
        sessionQueue.async {
            self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            self.session.stopRunning()
        }
    }
    
    func savePic(photoData: Data){
        guard let image = UIImage(data: photoData) else { return }
        
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }
    
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let _ = error else { return }
        guard let imageData = photo.fileDataRepresentation() else {return}
    }
}

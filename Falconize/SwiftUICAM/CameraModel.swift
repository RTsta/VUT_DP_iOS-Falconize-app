//
//  CameraModel.swift
//  Falconize
//
//  Created by Arthur Nácar on 23.11.2022.
//

import Foundation
import UIKit
import AVFoundation

class CameraModel: NSObject, ObservableObject {
    
    @Published var isTaken = false
    @Published var deviceLensDirection : AVCaptureDevice.Position = .back
    @Published var session = AVCaptureSession()
    
    private var deviceInput: AVCaptureDeviceInput?
    @Published var photoOutput = AVCapturePhotoOutput()
    
    @Published var preview: AVCaptureVideoPreviewLayer!
    
    var posePredictorDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?
    
    private let cameraSessionQueue = DispatchQueue(label: "CameraOutput", qos: .userInteractive)
    
    func check(){
        switch AVCaptureDevice.authorizationStatus(for: .video){
            case.authorized:
                    self.setUp()
                return
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { status in
                    if status {
                            self.setUp()
                    }
                }
            case .denied:
                return
            default:
                return
        }
    }
    
    func setUp(){
        cameraSessionQueue.async {
            do {
                self.session.beginConfiguration()
                let device = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: self.deviceLensDirection)
                
                let input = try AVCaptureDeviceInput(device: device!   )
                
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.deviceInput = input
                }
                
                if self.session.canAddOutput(self.photoOutput){
                    self.session.addOutput(self.photoOutput)
                }
                
                let dataOutput = AVCaptureVideoDataOutput()
                if self.session.canAddOutput(dataOutput) {
                    self.session.addOutput(dataOutput)
                    dataOutput.setSampleBufferDelegate(self.posePredictorDelegate, queue: self.cameraSessionQueue)
                } else { return }
                
                
                self.session.commitConfiguration()
            }
            catch{
                print(error.localizedDescription)
            }
        }
    }
    
    func changeLensDirection(){
        cameraSessionQueue.async {
            // zjištění všech dostupných záznamových zařízení
            let backVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera, .builtInDualWideCamera, .builtInWideAngleCamera], mediaType: .video, position: .back)
            let frontVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera], mediaType: .video, position: .front)
            
            guard let deviceInput = self.deviceInput else {return}
            let currentDevice = deviceInput.device
            let currentPosition = currentDevice.position
            var newDevice : AVCaptureDevice? = nil
            
            
            //nastavení nového vstupního zařízení
            switch currentPosition {
                case .unspecified, .front:
                    newDevice = backVideoDeviceDiscoverySession.devices.first
                case .back:
                    newDevice = frontVideoDeviceDiscoverySession.devices.first
                @unknown default:
                    print("Unknown capture position. Defaulting to back, dual-camera.")
                    newDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
            }
            if let newDevice = newDevice {
                do {
                    self.session.beginConfiguration()
                    self.session.removeInput(deviceInput)
                    
                    let input = try AVCaptureDeviceInput(device: newDevice )
                    
                    if self.session.canAddInput(input) {
                        self.session.addInput(input)
                        self.deviceInput = input
                        self.deviceLensDirection = input.device.position
                    }
                    
                    if self.session.canAddOutput(self.photoOutput){
                        self.session.addOutput(self.photoOutput)
                    }
                    
                    self.session.commitConfiguration()
                    
                }
                catch{
                    print(error.localizedDescription)
                }
                
            }
        }
    }
    
    func takePic(){
        cameraSessionQueue.async {
            self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            self.session.stopRunning()
        }
    }
    
    func savePic(photoData: Data){
        guard let image = UIImage(data: photoData) else { return }
        
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }
    
    func continueCapturing(){
        self.session.startRunning()
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let _ = error else { return }
        guard let imageData = photo.fileDataRepresentation() else {return}
    }
}

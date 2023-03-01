//
//  CameraViewModel.swift
//  Falconize
//
//  Created by Arthur Nácar on 25.11.2022.
//

import Foundation
import AVFoundation
import Combine

final class CameraViewModel: ObservableObject {
    private let service = CameraService()
    @Published var isFlashOn = false
    
    var session: AVCaptureSession
    private var subscriptions = Set<AnyCancellable>()
    
    init() {
        self.session = service.session
        // service.$photo.sink { [weak self] (photo) in
        //    guard let pic = photo else { return }
        //    self?.photo = pic
        // }.store(in: &self.subscriptions)
        
        service.$flashMode.sink { [weak self] (mode) in
            self?.isFlashOn = mode == .on
        }.store(in: &self.subscriptions)
    }
    
    func configure() {
        service.checkForPermissions()
        service.setupCameraSession()
        service.start()
    }
    
    func capturePhoto() {
        service.capturePhoto()
    }
    
    func startVideoRecording() {
        service.startVideoRecording()
    }
    
    func stopVideoRecording() {
        service.stopVideoRecording()
    }
    
    func captureAction() {
        service.captureAction()
    }
    
    func changeCamera() {
        myDebugPrint("changed camera")
        service.changeCamera()
    }
    
    func zoom(with factor: CGFloat) {
        service.set(zoom: factor)
    }
    
    func switchFlash() {
        service.flashMode = service.flashMode == .on ? .off : .on
    }
    
    func addPoseDelegate(delegate: PosePredictor) {
        service.addOutputDelegate(delegate: delegate)
    }
}

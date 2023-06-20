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
    @Published var isSlowModeOn = false
    @Published var isHistoryCaptureReady: Bool = false
    @Published var isAutoCaptureOn = false
    
    private var inputDevice: AVCaptureDevice?
    
    @Published var currentZoom = 1.0
    @Published var minZoomFactor: CGFloat = 1.0
    @Published var maxZoomFactor: CGFloat = 1.0
    @Published var zoomPresets: [CGFloat] = []
    
    @Published var zoomPresetsSlowMo: [CGFloat] = []
    
    var session: AVCaptureSession
    var previewView: VideoPreviewView
    
    private var subscriptions = Set<AnyCancellable>()
    
    init() {
        self.session = service.session
        self.previewView = VideoPreviewView()
        initSubscribers()
    }
    
    /// set subscribers to all published proppertys of CameraService
    private func initSubscribers() {
        service.$flashMode.sink { [weak self] (mode) in
            self?.isFlashOn = mode == .on
        }.store(in: &self.subscriptions)
        
        service.$slowMode.sink { [weak self] slowMode in
            self?.isSlowModeOn = slowMode
        }.store(in: &self.subscriptions)
        
        // finds all avaibile zoom presets for devices (virtual / normal device)
        service.$videoInputDevice.sink { [weak self] (device) in
            DispatchQueue.main.async {
                guard let device = device?.device else {
                    return
                }
                self?.inputDevice = device
                if device.isVirtualDevice {
                    self?.minZoomFactor = self?.inputDevice?.minAvailableVideoZoomFactor ?? 1.0
                    self?.maxZoomFactor = self?.inputDevice?.maxAvailableVideoZoomFactor ?? 1.0
                    var presets: [CGFloat] = self?.minZoomFactor != nil ? [self!.minZoomFactor] : []
                    presets.append(contentsOf: self?.inputDevice?.virtualDeviceSwitchOverVideoZoomFactors as? [CGFloat] ?? [])
                    self?.zoomPresets = presets
                } else {
                    var presets: [CGFloat] = [device.minAvailableVideoZoomFactor]
                    presets.append(contentsOf: self?.service.defaultBackDeviceZoomFactors.map({ CGFloat(truncating: $0) }) ?? [] )
                    self?.zoomPresetsSlowMo = presets
                }
            }
        }.store(in: &self.subscriptions)
        
        service.$isHistoryCaptureReady.sink { isReady in
            DispatchQueue.main.async {[weak self]  in
                self?.isHistoryCaptureReady = isReady
            }
        }.store(in: &self.subscriptions)
        
    }
    
}
// MARK: CameraViewModel - CameraSession actions
extension CameraViewModel {
    /// Initial configuration of CameraSession
    func configure() {
        service.checkForPermissions()
        service.setupCameraSession()
        service.start()
    }
    
    /// capturePhoto
    func capturePhoto() {
        service.capturePhoto()
    }
    
    /// startVideoRecording
    func startVideoRecording() {
        service.startVideoRecording()
    }
    
    /// stopVideoRecording
    func stopVideoRecording() {
        service.stopVideoRecording()
    }
    
    /// captureAction
    func captureAction() {
        service.captureAction()
    }
    
    /// autoCapture
    func autoCapture() {
        self.isAutoCaptureOn.toggle()
    }
    
    /// flipCamera
    func flipCamera() {
        service.flipCamera()
    }
    
    /// switchSlowMode - switches mode with high refresh rate
    func switchSlowMode() {
        service.switchSlowMode()
    }
    
    /// zoom
    func zoom(with zoom: CGFloat) {
        var finalZoom = zoom
        if finalZoom > maxZoomFactor {
            finalZoom = maxZoomFactor
        } else if zoom < minZoomFactor {
            finalZoom = minZoomFactor
        }
        DispatchQueue.main.async {[weak self] in
            self?.service.set(zoom: finalZoom)
            self?.currentZoom = finalZoom
        }

    }
    
    /// focus
    func focus(at focusPoint: CGPoint) {
        service.focus(at: focusPoint)
    }
    
    /// switchFlash
    func switchFlash() {
        service.flashMode = service.flashMode == .on ? .off : .on
    }
    
    /// addPoseDelegate
    func addPoseDelegate(delegate: PosePredictor) {
        service.addOutputDelegate(delegate: delegate)
    }
}

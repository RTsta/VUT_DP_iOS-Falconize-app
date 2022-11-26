//
//  CameraViewModel.swift
//  Falconize
//
//  Created by Arthur Nácar on 21.11.2022.
//

import Foundation
import AVFoundation.AVCaptureDevice
import SwiftUI

class CameraViewStore: ObservableObject {
    @Published var captureButtonTriggered: Bool = false {didSet {
        captureBtnEnabled = !captureButtonTriggered
    }}
    
    @Published var switchCameraButtonTriggered: Bool = false {
        didSet {
            switchCameraBtnEnabled = !switchCameraButtonTriggered
        }
    }
    
    @Published var captureBtnEnabled = true
    @Published var switchCameraButtonEnabled = true
    @Published var switchCameraBtnEnabled = true
    
    @Published var cameraDirection: AVCaptureDevice.Position = .back
}

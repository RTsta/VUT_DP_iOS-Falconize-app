//
//  CameraView.swift
//  CameraTest
//
//  Created by Arthur Nácar on 29.09.2022.
//

import SwiftUI
import AVFoundation.AVCaptureDevice

struct CameraHostedView: UIViewControllerRepresentable {
    var posePredictor: PosePredictor
    @ObservedObject var cameraViewStore: CameraViewStore
    
    func makeUIViewController(context: Context) -> some CameraViewController {
        let cameraVC = CameraViewController()
        cameraVC.delegate = posePredictor
        cameraVC.cameraViewStore = cameraViewStore
        return cameraVC
    }
    
    
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
        if (self.cameraViewStore.captureButtonTriggered == true){
            uiViewController.captureBtnAction()
        }
        if  (self.cameraViewStore.switchCameraButtonTriggered == true){
            uiViewController.switchCameraBtnAction()
        }
        //guard let controler = uiViewController as? CameraVC else { return }
        //controler.cameraDirection = cameraDirection
        //print(cameraDirection.rawValue)
        //controler.loadAVSession()
    }
}

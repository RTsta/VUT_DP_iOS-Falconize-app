//
//  File.swift
//  Falconize
//
//  Created by Arthur Nácar on 23.11.2022.
//

import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    
    @ObservedObject var camera : CameraModel
    @ObservedObject var posePredictor: PosePredictor
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        camera.preview = AVCaptureVideoPreviewLayer(session: camera.session)
        camera.preview.frame = view.frame
        camera.posePredictorDelegate = posePredictor
        view.layer.addSublayer(camera.preview)
        
        camera.preview.videoGravity = .resizeAspectFill
        
        camera.session.startRunning()
        return view
        
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        
    }
}

//
//  CameraPreview2.swift
//  Falconize
//
//  Created by Arthur Nácar on 25.11.2022.
//

import Foundation
import UIKit
import AVFoundation
import SwiftUI

class VideoPreviewView: UIView {
    override class var layerClass: AnyClass {
         AVCaptureVideoPreviewLayer.self
    }
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}

struct CameraPreview: UIViewRepresentable {
    
    let session: AVCaptureSession
    let view: VideoPreviewView
    
    func makeUIView(context: Context) -> VideoPreviewView {
        view.backgroundColor = .black
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.videoPreviewLayer.connection?.videoOrientation = .portrait

        return view
    }
    
    func updateUIView(_ uiView: VideoPreviewView, context: Context) {
        
    }
}

//
//  CameraCaptureView.swift
//  Falconize
//
//  Created by Arthur Nácar on 09.11.2022.
//

import SwiftUI
import AVFoundation.AVCaptureDevice

struct CameraCaptureView: View {
    var posePredictor: PosePredictor = PosePredictor()
    @StateObject private var store: CameraViewStore = CameraViewStore()
    
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                CameraHostedView(posePredictor: posePredictor, cameraViewStore: store)
                StickFigureView(posePredictor: posePredictor, size: geometry.size)
            }
            
            VStack() {
                HStack() {
                    Button(action: {
                        store.switchCameraButtonTriggered = true
                    }) {
                        Text("Switch")
                    }.disabled(!store.switchCameraBtnEnabled)
                }
                Spacer()
                Button(action: {
                    store.captureButtonTriggered = true
                }, label: {ZStack{
                    Circle()
                        .foregroundColor(Color.white)
                        .frame(width: 70, height: 70)
                    
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 80, height: 80)
                    
                }})
                .disabled(!store.captureBtnEnabled)
            }
        }
    }
}

struct CameraCaptureView_Previews: PreviewProvider {
    static var previews: some View {
        CameraCaptureView()
    }
}

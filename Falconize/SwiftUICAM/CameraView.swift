//
//  CameraView.swift
//  Falconize
//
//  Created by Arthur Nácar on 23.11.2022.
//

import SwiftUI

struct CameraView: View {
    var posePredictor: PosePredictor = PosePredictor()
    @StateObject var camera = CameraModel()
    
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                CameraPreview(camera: camera, posePredictor: posePredictor).ignoresSafeArea()
                StickFigureView(posePredictor: posePredictor, size: geometry.size)
            }
            
            VStack() {
                HStack() {
                    Button(action: {
                        camera.changeLensDirection()
                    }) {
                        Text("Switch")
                    }
                }
                Spacer()
                Button(action: {
                    
                }, label: {ZStack{
                    Circle()
                        .foregroundColor(Color.white)
                        .frame(width: 70, height: 70)
                    
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 80, height: 80)
                    
                }})
            }
        }.onAppear{
            camera.check()
        }
    }
}

struct CameraView_Previews: PreviewProvider {
    static var previews: some View {
        CameraView()
    }
}

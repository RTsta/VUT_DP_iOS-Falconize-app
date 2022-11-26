//
//  CameraView.swift
//  Falconize
//
//  Created by Arthur Nácar on 23.11.2022.
//

import SwiftUI

struct CameraView: View {
    @StateObject var cameraViewModel = CameraViewModel()
    @StateObject var posePredictor = PosePredictor()
    @State var currentZoomFactor: CGFloat = 1.0
    @State var running : Bool = false
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                cameraPreview
                    .gesture( DragGesture().onChanged({ (val) in
                        //  Only accept vertical drag
                        if abs(val.translation.height) > abs(val.translation.width) {
                            //  Get the percentage of vertical screen space covered by drag
                            let percentage: CGFloat = -(val.translation.height / geometry.size.height)
                            //  Calculate new zoom factor
                            let calc = currentZoomFactor + percentage
                            //  Limit zoom factor to a maximum of 5x and a minimum of 1x
                            let zoomFactor: CGFloat = min(max(calc, 1), 5)
                            //  Store the newly calculated zoom factor
                            currentZoomFactor = zoomFactor
                            //  Sets the zoom factor to the capture device session
                            cameraViewModel.zoom(with: zoomFactor)
                        }
                    }))
            }
            VStack() {
                HStack() {
                    resetButton
                    Spacer()
                    switchButton
                    
                }.padding([.trailing, .leading], 20)
                PoseTextView(posePredictor: posePredictor)
                Spacer()
                captureButton
            }
        }
        .onAppear{
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation") // Forcing the rotation to portrait
            AppDelegate.orientationLock = .portrait // And making sure it stays that way
        }
        .onDisappear{
            AppDelegate.orientationLock = .all
        }
    }
    
    @ViewBuilder var cameraPreview: some View {
        GeometryReader { geometry in
            CameraPreview(session: cameraViewModel.session)
                .ignoresSafeArea()
                .onAppear{
                    cameraViewModel.configure()
                    cameraViewModel.addPoseDelegate(delegate: posePredictor)
                }
            
            StickFigureView(posePredictor: posePredictor, size: geometry.size)
        }
    }
    
    
    @ViewBuilder var captureButton: some View {
        Button(action: {
            
        }, label: {ZStack{
            Circle()
                .foregroundColor(running ? Color.white : Color.red)
                .frame(width: 70, height: 70)
            
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 80, height: 80)
            
            (running ? Image(systemName: "pause.fill"): Image(systemName: "play.fill")).foregroundColor(Color.black)
            
        }})
    }
    
    @ViewBuilder var switchButton: some View {
        Button(action: {
            cameraViewModel.changeCamera()
        }) {
            ZStack{
                RoundedRectangle(cornerRadius: 20).frame(width: 60, height: 40).foregroundColor(Color.white).opacity(0.7)
                Image(systemName: "arrow.triangle.2.circlepath.camera").foregroundColor(Color.black)
            }
        }
    }
    
    @ViewBuilder var resetButton: some View {
        Button(action: {
            posePredictor.actionCount = 0
            
        }) {
            ZStack{
                RoundedRectangle(cornerRadius: 20).frame(width: 60, height: 40).foregroundColor(Color.white).opacity(0.7)
                Image(systemName: "arrow.counterclockwise").foregroundColor(Color.black)
            }
        }
    }
}

struct CameraView_Previews: PreviewProvider {
    static var previews: some View {
        CameraView()
    }
}

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
    @State var recording : Bool = false
    
    @State var testOpacity = 0.5
    
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
                ZStack{
                    
                    RoundedRectangle(cornerRadius: 44)
                        .foregroundColor(.white)
                        .opacity(testOpacity)
                        .ignoresSafeArea()
                        .onTapGesture { _ in
                            testOpacity = (testOpacity > 0.5 ? 0.5 : 1.0)
                        }
                    PoseTextView(posePredictor: posePredictor)
                    
                }.frame(height: 100)
                HStack() {
                    resetButton
                    Spacer()
                    switchButton
                    
                }.padding([.trailing, .leading], 20)
                
                Spacer()
                ZStack{
                    recordButton
                    HStack{
                        Spacer()
                        captureButton
                    }.padding()
                }
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
    
    
    @ViewBuilder var recordButton: some View {
        Button(action: {
            (!recording ? cameraViewModel.startVideoRecording(): cameraViewModel.stopVideoRecording())
            recording.toggle()
        }, label: {ZStack{
            Circle()
                .foregroundColor(recording ? Color.red : Color.white)
                .frame(width: 70, height: 70)
            
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 80, height: 80)
            
            (recording ? Image(systemName: "pause.fill"): Image(systemName: "play.fill")).foregroundColor(Color.black)
            
        }})
    }
    
    @ViewBuilder var captureButton: some View {
        Button(action: {
            cameraViewModel.capturePhoto()
        }, label: {ZStack{
            Circle()
                .foregroundColor(Color.white)
                .frame(width: 40, height: 40)
            
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 50, height: 50)
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
        ZStack{
            Rectangle().foregroundColor(Color.black).scaledToFill().ignoresSafeArea()
            CameraView()
        }
    }
}

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
    @State var recording: Bool = false
    
    @State var debugMode: Bool = true
    @State private var showFocusPoint = false
    
    @State var testOpacity = 0.5
    @State var currentZoom = 1.0
    @State var displayZoom = 1.0
    @State var tapFocusPoint: CGPoint = .init()
    
    
    var body: some View {
        ZStack {
            ZStack {
                cameraPreview
                gridView
            }
            if showFocusPoint {
                FocusPointView()
                    .frame(width: 100, height: 100)
                    .position(tapFocusPoint)
                    .transition(.opacity)
            }
            VStack {
                
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .opacity(0.3)
                        .foregroundColor(.black)
                    HStack {
                        resetButton
                        flashButton
                        Spacer()
                        Toggle(isOn: $debugMode) {
                            
                        }.onChange(of: debugMode) { _ in
                            myDebugPrint(debugMode)
                        }
                        frameRateButton
                        switchButton
                    }.padding(3)
                }
                .padding([.trailing, .leading], 10)
                .frame(height: 40)
                .fixedSize(horizontal: false, vertical: true)
                debuggingUI
                Spacer().layoutPriority(2)
                switchLensButtons
                ZStack {
                    testCaptureButton
                        
//                    HStack {
//                        recordButton
//                        Spacer()
//                        captureButton
//                    }.padding()
                }
            }
        }
        .onAppear {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation") // Forcing the rotation to portrait
            AppDelegate.orientationLock = .portrait // And making sure it stays that way
        }
        .onDisappear {
            AppDelegate.orientationLock = .all
        }
        .onChange(of: posePredictor.evenAction) { evenAction in
            if !debugMode {
                cameraViewModel.captureAction()
            }
            // if !evenAction && !debugMode {
            //    myDebugPrint("Recording starting")
            //    recording.toggle()
            //    cameraViewModel.startVideoRecording()
            // } else {
            //    myDebugPrint("Recording stopping")
            //    recording.toggle()
            //    cameraViewModel.stopVideoRecording()
            // }
        }.background(.black)
        
    }
    
    @ViewBuilder var debuggingUI: some View {
        if debugMode {
        ZStack {
            RoundedRectangle(cornerRadius: 44)
                .foregroundColor(.white)
                .opacity(testOpacity)
                .ignoresSafeArea()
                .onTapGesture { _ in
                    testOpacity = (testOpacity > 0.5 ? 0.5 : 1.0)
                }
            VStack {
                PoseTextView(posePredictor: posePredictor)
                ConsoleLogText()
            }
        }.frame(maxHeight: 150)
    }
    }
    
    @ViewBuilder var cameraPreview: some View {
        GeometryReader { geometry in
            CameraPreview(session: cameraViewModel.session, view: cameraViewModel.previewView)
                .onAppear {
                    cameraViewModel.configure()
                    cameraViewModel.addPoseDelegate(delegate: posePredictor)
                }
                .gesture(
                    MagnificationGesture().onChanged { value in
                        if value > 1.0 {
                            displayZoom = currentZoom + value
                            cameraViewModel.zoom(with: displayZoom)
                        } else {
                            displayZoom = currentZoom * value
                            displayZoom = displayZoom < 1.0 ? 1.0 : displayZoom
                            cameraViewModel.zoom(with: currentZoom * value)
                        }
                    }.onEnded { value in
                        if value > 1.0 {
                            currentZoom += value
                        } else {
                            currentZoom *= value
                        }
                        displayZoom = currentZoom
                    }
                )
                .onTapGesture(count: 1, coordinateSpace: .local) { point in
                    tapFocusPoint = point
                    let convertedPoint = cameraViewModel.previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: point)
                    cameraViewModel.focus(at: convertedPoint)
                    
                        self.showFocusPoint.toggle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(.linear(duration: 1)) {
                            self.showFocusPoint.toggle()
                        }
                    }
                }
            StickFigureView(posePredictor: posePredictor, size: geometry.size)
        }
    }
    
    @ViewBuilder var gridView: some View {
        EmptyView()
    }
    
    // MARK: - Buttons
    @ViewBuilder
    var recordButton: some View {
        Button(action: {
            (!recording && !debugMode ? cameraViewModel.startVideoRecording(): cameraViewModel.stopVideoRecording())
            recording.toggle()
        }, label: {ZStack {
            Circle()
                .foregroundColor(recording ? Color.red : Color.white)
                .frame(width: 70, height: 70)
            
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 80, height: 80)
            
            (recording ? Image(systemName: "pause.fill"): Image(systemName: "play.fill")).foregroundColor(Color.black)
            
        }})
    }
    
    @ViewBuilder
    var captureButton: some View {
        Button(action: {
            if !debugMode {
                cameraViewModel.capturePhoto()
            }
        }, label: {ZStack {
            Circle()
                .foregroundColor(Color.white)
                .frame(width: 40, height: 40)
            
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 50, height: 50)
        }})
    }
    
    @ViewBuilder
    var frameRateButton: some View {
        Button(action: {
            cameraViewModel.switchSlowMode()
        },
               label: {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .frame(width: 60, height: 40)
                    .foregroundColor(cameraViewModel.isSlowModeOn ? Color.yellow : Color.black)
                    .opacity(0.7)
                Text("FPS+")
                    .foregroundColor(cameraViewModel.isSlowModeOn ? Color.black : Color.white)
            }})
    }
    
    @ViewBuilder
    var testCaptureButton: some View {
        Button(action: {
            cameraViewModel.captureAction()
        }, label: {ZStack {
            Circle()
                .foregroundColor(Color.white)
                .frame(width: 60, height: 60)
            
            Circle()
                .stroke((cameraViewModel.isHistoryCaptureReady ? Color.green : Color.red), lineWidth: 2)
                .frame(width: 70, height: 70)
        }})
    }
    
    @ViewBuilder
    var switchButton: some View {
        Button(action: {
            cameraViewModel.flipCamera()
        },
               label: {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .frame(width: 60)
                    .foregroundColor(Color.black)
                    .opacity(0.7)
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .foregroundColor(Color.white)
            }})
    }
    
    @ViewBuilder
    var flashButton: some View {
        Button(action: {
            cameraViewModel.switchFlash()
        },
               label: {
            ZStack {
                Circle()
                    .foregroundColor(Color.black)
                    .opacity(0.7)
                Image(systemName: cameraViewModel.isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                    .foregroundColor(Color.white)
            }})
    }
    
    @ViewBuilder
    var resetButton: some View {
        Button(action: {
            posePredictor.actionCount = 0
            
        }, label: {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .frame(width: 60, height: 40)
                    .foregroundColor(Color.black)
                    .opacity(0.7)
                Image(systemName: "arrow.counterclockwise")
                    .foregroundColor(Color.white)
            }
        })
    }
    
    @ViewBuilder
    var switchLensButtons: some View {
        let presets = cameraViewModel.isSlowModeOn ? cameraViewModel.zoomPresetsSlowMo : cameraViewModel.zoomPresets
        
        if presets.count > 1 {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .opacity(0.3)
                    .foregroundColor(.black)
                HStack {
                    ForEach(presets.indices, id: \.self) { index in
                        let preset = presets[index]
                        let nextPreset: CGFloat = index+1 < presets.count ? presets[index + 1] : .infinity
                        Button(action: {
                            cameraViewModel.zoom(with: preset)
                        }) {
                            ZStack {
                                Circle()
                                    .foregroundColor(.black)
                                if preset <= currentZoom && currentZoom < nextPreset {
                                    Text("\(String(format: "%.1f", displayZoom*0.5))x")
                                        .foregroundColor(.yellow)
                                } else {
                                    Text("\(String(format: "%.1f", preset*0.5))x")
                                        .foregroundColor(.yellow)
                                }
                            }
                                
                        }
                        .padding(3)
                        .opacity(0.8)
                    }
                }
            }
            .frame(height: 40)
            .fixedSize()
        }
    }
}

// MARK: - Preview
struct CameraView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Rectangle().foregroundColor(Color.black).scaledToFill().ignoresSafeArea()
            CameraView()
        }
    }
}

//
//  Predictor.swift
//  Falconize
//
//  Created by Arthur Nácar on 07.11.2022.
//

import Foundation
import Vision
import AVFoundation
import Combine

class PosePredictor: NSObject, ObservableObject {
    let sequenceHandler = VNSequenceRequestHandler()
    @Published var bodyParts: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]?
    var subscriptions = Set<AnyCancellable>()
    var cameraPosition: AVFoundation.AVCaptureDevice.Position?
    
    var overNose = false
    @Published var actionCount: Int = 0
    @Published var evenAction: Bool = true
    
    override init() {
        super.init()
        $bodyParts
            .dropFirst()
            .sink(receiveValue: { bodyParts in self.countActions(bodyParts: bodyParts) })
            .store(in: &subscriptions)
    }
    
}

extension PosePredictor: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let humanBodyRequest = VNDetectHumanBodyPoseRequest(completionHandler: detectedBodyPose)
        
        let orientation: CGImagePropertyOrientation = cameraPosition == AVCaptureDevice.Position.front ? CGImagePropertyOrientation.right : CGImagePropertyOrientation.leftMirrored
        do {
            try sequenceHandler.perform([humanBodyRequest], on: sampleBuffer, orientation: orientation)
        } catch {
          print(error.localizedDescription)
        }
    }
    
    func detectedBodyPose(request: VNRequest, error: Error?) {
        guard let bodyPoseResults = request.results as? [VNHumanBodyPoseObservation] else {
            return
        }
        let bodyParts = try? bodyPoseResults.first?.recognizedPoints(.all)
        
        
        DispatchQueue.main.async {
            self.bodyParts = bodyParts
        }
    }
    
    func countActions(bodyParts: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]?) {
        guard let bodyParts = bodyParts else {
            return
        }
        let rightWrist = bodyParts[.rightWrist]!.location
        let rightElbow = bodyParts[.rightElbow]!.location
        let leftWrist = bodyParts[.leftWrist]!.location
        let leftElbow = bodyParts[.leftElbow]!.location
        let nose = bodyParts[.nose]!.location
        
        if nose.y < rightWrist.y &&
                nose.y < rightElbow.y &&
                nose.y < leftWrist.y &&
                nose.y < leftElbow.y {
            if !self.overNose {
                self.overNose = true
                actionCount += 1
                evenAction.toggle()
            }
        } else {
            self.overNose = false
        }
    }
}

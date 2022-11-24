//
//  Predictor.swift
//  Falconize
//
//  Created by Arthur Nácar on 07.11.2022.
//

import Foundation
import Vision
import AVFoundation

class PosePredictor: NSObject, ObservableObject {
    let sequenceHandler = VNSequenceRequestHandler()
    @Published var bodyParts = [VNHumanBodyPoseObservation.JointName : VNRecognizedPoint]()
    var cameraPosition: AVFoundation.AVCaptureDevice.Position?
    
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
        guard let bodyPoseResults = request.results as? [VNHumanBodyPoseObservation] else { return }
        guard let bodyParts = try? bodyPoseResults.first?.recognizedPoints(.all) else { return }
        
        
        DispatchQueue.main.async {
            self.bodyParts = bodyParts
        }
    }
}

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

typealias FalconizedPoseClasifier = Falconized_PoseModel

class PosePredictor: NSObject, ObservableObject {
    struct ClasifierResult {
        let label: String
        let convidence: Double
    }
    let sequenceHandler = VNSequenceRequestHandler()
    @Published var bodyParts: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]?
    var subscriptions = Set<AnyCancellable>()
    var cameraPosition: AVFoundation.AVCaptureDevice.Position?
    
    var overNose = false
    @Published var actionCount: Int = 0
    @Published var evenAction: Bool = true
    
    @Published var poseClasification: ClasifierResult?
    
    var predictionWindowSize = 60 // TODO: dependend on quality
    var poseWindow: [VNHumanBodyPoseObservation] = []
    
    override init() {
        poseWindow.reserveCapacity(predictionWindowSize)
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
        guard let bodyPoseResults = request.results as? [VNHumanBodyPoseObservation],
              let bodyPoseResult = bodyPoseResults.first else {
            return
        }
        let bodyParts = try? bodyPoseResult.recognizedPoints(.all)
        
        
        DispatchQueue.main.async {
            self.bodyParts = bodyParts
        }
        storeObservation(bodyPoseResult)
        
        labelActionType()
    }
    
    func labelActionType() {
        guard let throwingClasifier = try? FalconizedPoseClasifier(configuration: MLModelConfiguration()),
              let poseMultiArray = prepareInputWithObservations(poseWindow),
              let predictions = try? throwingClasifier.prediction(poses: poseMultiArray)
        else { return }
        
        let label = predictions.label
        let confidence = predictions.labelProbabilities[label] ?? 0
        DispatchQueue.main.async { [weak self] in
            self?.poseClasification = ClasifierResult(label: label, convidence: confidence)
        }
        
    }
    
    func prepareInputWithObservations(_ observations: [VNHumanBodyPoseObservation]) -> MLMultiArray? {
        let numberAvaibileFrames = observations.count
        let observationsNeeded = predictionWindowSize
        var multiArrayBuffer = [MLMultiArray]()
        
        for frameIndex in 0 ..< min(numberAvaibileFrames, observationsNeeded) {
            let pose = observations[frameIndex]
            do {
                let oneFrameMultiArray = try pose.keypointsMultiArray()
                multiArrayBuffer.append(oneFrameMultiArray)
            } catch { continue }
        }
        
        if numberAvaibileFrames < observationsNeeded {
            for _ in 0 ..< (observationsNeeded - numberAvaibileFrames) {
                do {
                    let oneFrameMultiArray = try MLMultiArray(shape: [1, 3, 18], dataType: .double)
                    try resetMultiArray(oneFrameMultiArray)
                    multiArrayBuffer.append(oneFrameMultiArray)
                } catch {
                    continue
                }
            }
        }
        return MLMultiArray(concatenating: [MLMultiArray](multiArrayBuffer), axis: 0, dataType: .float)
    }
    
    private func resetMultiArray(_ predictionWindow: MLMultiArray, with value: Double = 0.0) throws {
        let pointer = try UnsafeMutableBufferPointer<Double>(predictionWindow)
        pointer.initialize(repeating: value)
    }
    
    func storeObservation(_ observation: VNHumanBodyPoseObservation) {
        if poseWindow.count >= predictionWindowSize {
            poseWindow.removeFirst()
        }
        poseWindow.append(observation)
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

//
//  VideoCapture.swift
//  Falconize
//
//  Created by Arthur Nácar on 07.11.2022.
//

import Foundation
import AVFoundation

class VideoCapture: NSObject {
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    let captureSession = AVCaptureSession()
    let videoOutput = AVCaptureVideoDataOutput()
    
    override init() {
        super.init()
        guard let captureDevice = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: captureDevice)
        else { return }
        
        captureSession.addInput(input)
        
        captureSession.addOutput(videoOutput)
        videoOutput.alwaysDiscardsLateVideoFrames = true
    }
    
    func startCaptureSession() {
        sessionQueue.async { [unowned self] in
            captureSession.startRunning()
        }
        
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
    }
}

// MARK: - VideoCapture - AVCaptureVideo DataOutputSampleBufferDelegate
extension VideoCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // predictor.estimation(sampleBuffer: sampleBuffer)
    }
    
}

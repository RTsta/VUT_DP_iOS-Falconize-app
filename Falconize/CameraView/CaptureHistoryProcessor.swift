//
//  CaptureHistoryProcessor.swift
//  Falconize
//
//  Created by Arthur Nácar on 03.02.2023.
//

import Foundation
import AVFoundation
import UIKit

import Photos

class CaptureHistoryProcessor: NSObject {
    //private var captureHistory: CMBlockBuffer = .init(capacity: 120)
    private var totalNumberOfChunks : Int = 20
    private var chunkDuration : Double = 1
    private var chunkNumber : Int = 0
    private var assetWriter : AVAssetWriter?
    private var chunkStartTime: CMTime?
    private var chunkOutputURL : URL?
    private var assetWriterInput : AVAssetWriterInput?
    
    override init() {
        super.init()
        
        let fileManager = FileManager.default
        guard let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            .sorted(by: {
                $0.deletingPathExtension().lastPathComponent < $1.deletingPathExtension().lastPathComponent
            }).filter({$0.pathExtension == "mov"}) else { return }
        contents.forEach(){
            try? fileManager.removeItem(at:$0)
        }
        
        
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CaptureHistoryProcessor : AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        createVideoOutput(from: sampleBuffer)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    }
}

// MARK: - AVAssetWriter
extension CaptureHistoryProcessor {
    
    func createWriterInput(at startTime : CMTime) {
        print("Start recoriding: \(chunkNumber)")
        chunkOutputURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(component: "chunk\(String(format: "%02d", chunkNumber)).mov")
        try? FileManager.default.removeItem(at: chunkOutputURL!)
        
        assetWriter = try? AVAssetWriter(outputURL: chunkOutputURL!, fileType: .mov)
        guard let assetWriter = assetWriter else {
            fatalError("CaptureHistoryProcessor - not initialized AVAssetWriter")
        }
        assetWriter.shouldOptimizeForNetworkUse = true
        
        let outputSettings : [String : Any] = [AVVideoCodecKey : AVVideoCodecType.hevc,
                                                AVVideoWidthKey: 1920,
                                               AVVideoHeightKey: 1080,
        ]
        
        assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        guard let assetWriterInput = assetWriterInput else {
            fatalError("CaptureHistoryProcessor - not initialized assetWriterInput")
        }
        assetWriterInput.expectsMediaDataInRealTime = true
        assetWriter.add(assetWriterInput)
        
        chunkNumber = (chunkNumber + 1 ) % totalNumberOfChunks
        chunkStartTime = startTime
        
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: startTime)
    }
    
    func createVideoOutput(from buffer: CMSampleBuffer){
        let timeStamp = CMSampleBufferGetPresentationTimeStamp(buffer)
        // video is running
        if let assetWriter = assetWriter, let chunkStartTime = chunkStartTime {
            let currentDuration = CMTimeGetSeconds(CMTimeSubtract(timeStamp, chunkStartTime))
            
            // video over duration limit
            if currentDuration > chunkDuration {
                assetWriter.endSession(atSourceTime: timeStamp)
                
                assetWriter.finishWriting {  }
                createWriterInput(at: timeStamp)
            }
            // never recorde
        } else {
            createWriterInput(at: timeStamp)
        }
        
        if let assetWriterInput = assetWriterInput,
           assetWriterInput.isReadyForMoreMediaData {
            if !assetWriterInput.append(buffer){
                debugPrint("Error appending assetWriterInput")
            }
        }
        
    }
    
    func didOutputPlayerItem(_ item: AVPlayerItem){
        
    }
    
}

// MARK: - AVMutableComposition
extension CaptureHistoryProcessor {
    func mergeVideos(outputURL1 : URL, outputURL2 : URL) async {
        let asset1 = AVURLAsset(url: outputURL1)
        let asset2 = AVURLAsset(url: outputURL2)
        let composition = AVMutableComposition()
        
        
        guard let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) //vytvoří novou stopu v kompozici (composition)
        else {
            print("Unable to create compositionTrack")
            return
        }
        
        guard let asset1Track = try? await asset1.loadTracks(withMediaType: .video).first
        else {
            print("Something is wrong with the 1st asset.")
            return
        }
        
        guard let asset2Track = try? await asset2.loadTracks(withMediaType: .video).first
        else {
            print("Something is wrong with the 2nd asset.")
            return
        }
        
        
        var duration1 : CMTime = CMTime()
        var duration2 : CMTime = CMTime()
        do {
            duration1 = try await asset1.load(.duration)
            let timeRange1 = CMTimeRange(start: .zero, duration: duration1)
            try compositionTrack.insertTimeRange(timeRange1, of: asset1Track, at: .zero) //vloží stopu do kompozice
            
            duration2 = try await asset2.load(.duration)
            let timeRange2 = CMTimeRange(start: .zero, duration: duration2)
            try compositionTrack.insertTimeRange(timeRange2, of: asset2Track, at: duration1)
        } catch {
            print(error.localizedDescription)
            return
        }
        
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = try! await asset1Track.load(.naturalSize)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero,duration: CMTimeAdd(duration1, duration2))
        videoComposition.instructions = [instruction]
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
        layerInstruction.setTransform(try! await asset1Track.load(.preferredTransform), at: .zero)
        instruction.layerInstructions = [layerInstruction]
        
        // export
        guard let export = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality)
        else {
            print("Cannot create export session.")
            return
        }
        
        let videoName = UUID().uuidString
        let exportURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(videoName)
            .appendingPathExtension("mov")
        
        export.videoComposition = videoComposition
        export.outputFileType = .mov
        export.outputURL = exportURL
        
        await export.export()
        
        switch export.status {
            case .completed:
                print("saving")
                saveVideoToPhotos(url: exportURL)
            default:
                print("Something went wrong during export.")
                print(export.error ?? "unknown error")
                break
        }
    }
        
    func mergeVideos(videoURLs : [URL]) async {
        if videoURLs.isEmpty { return }
            
            let composition = AVMutableComposition()
            guard let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) //vytvoří novou stopu v kompozici (composition)
            else {
                print("Unable to create compositionTrack")
                return
            }
        
        var assetTrack : AVAssetTrack?
            var previusTrackTime : CMTime = .zero
            for videoURL in videoURLs {
                let asset = AVURLAsset(url: videoURL)
                
                assetTrack = try? await asset.loadTracks(withMediaType: .video).first
                guard let assetTrack = assetTrack
                else {
                    print("Something is wrong with the asset.\(videoURL.debugDescription)")
                    return
                }
                
                
                do {
                    let duration = try await asset.load(.duration)
                    let timeRange = CMTimeRange(start: .zero, duration: duration)
                    try compositionTrack.insertTimeRange(timeRange, of: assetTrack, at: previusTrackTime)
                    
                    previusTrackTime = CMTimeAdd(previusTrackTime, duration)
                } catch {
                    print(error.localizedDescription)
                    return
                }
            }
        
        guard let assetTrack = assetTrack
        else {
            print("Something is wrong with the asset.")
            return
        }
            
            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = try! await assetTrack.load(.naturalSize)
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            
            
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero,duration: previusTrackTime)
            videoComposition.instructions = [instruction]
            
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
            layerInstruction.setTransform(try! await assetTrack.load(.preferredTransform), at: .zero)
            instruction.layerInstructions = [layerInstruction]
            
            // export
            guard let export = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality)
            else {
                print("Cannot create export session.")
                return
            }
            
            let videoName = UUID().uuidString
            let exportURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(videoName)
                .appendingPathExtension("mov")
            
            export.videoComposition = videoComposition
            export.outputFileType = .mov
            export.outputURL = exportURL
            
            await export.export()
            
            switch export.status {
                case .completed:
                    print("saving")
                    saveVideoToPhotos(url: exportURL)
                default:
                    print("Something went wrong during export.")
                    print(export.error ?? "unknown error")
                    break
            }
    }
    
    private func orientation(from transform: CGAffineTransform) -> (orientation: UIImage.Orientation, isPortrait: Bool) {
        var assetOrientation = UIImage.Orientation.up
        var isPortrait = false
        
        if transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0 {
            assetOrientation = .right
            isPortrait = true
        } else if transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0 {
            assetOrientation = .left
            isPortrait = true
        } else if transform.a == 1.0 && transform.b == 0 && transform.c == 0 && transform.d == 1.0 {
            assetOrientation = .up
        } else if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
            assetOrientation = .down
        }
      
      return (assetOrientation, isPortrait)
    }
    
    private func getVideoTransform() -> CGAffineTransform {
        switch UIDevice.current.orientation {
            case .portrait:
                return .identity
            case .portraitUpsideDown:
                return CGAffineTransform(rotationAngle: .pi)
            case .landscapeLeft:
                return CGAffineTransform(rotationAngle: .pi/2)
            case .landscapeRight:
                return CGAffineTransform(rotationAngle: -.pi/2)
            default:
                return .identity
            }
        }
    
    func testAction() async {
        let fileManager = FileManager.default
        guard let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        Task{
            print("AKCE v framu \(chunkNumber)")
            let currentChunkNumber = chunkNumber

            try await Task.sleep(for:Duration.milliseconds(3010))
            guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                .sorted(by: {
                    $0.deletingPathExtension().lastPathComponent < $1.deletingPathExtension().lastPathComponent
                }).filter({$0.pathExtension == "mov"}) else { return }
            
            await mergeVideos(videoURLs: [contents[chunkNumberIndexing(for: currentChunkNumber-4)],
                                          contents[chunkNumberIndexing(for: currentChunkNumber-3)],
                                          contents[chunkNumberIndexing(for: currentChunkNumber-2)],
                                          contents[chunkNumberIndexing(for: currentChunkNumber-1)],
                                          contents[chunkNumberIndexing(for: currentChunkNumber)],
                                          contents[chunkNumberIndexing(for: currentChunkNumber+1)]
                                         ])
        }
    }
    
    private func chunkNumberIndexing(for index: Int) -> Int {
        if index >= 0 {
            return index % totalNumberOfChunks
        }
        else {
            return (totalNumberOfChunks + index) % totalNumberOfChunks
        }
    }
    
    func saveVideoToPhotos(url videoURL: URL) {
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            switch status {
                case .authorized:
                    PHPhotoLibrary.shared().performChanges( {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                    }) { [weak self] (isSaved, error) in
                        if isSaved {
                            myDebugPrint("video saved",onScreen: true)
                        } else {
                            print("\(String(describing: self )).\(#function) - Cannot save video. - \(error?.localizedDescription ?? "unknown error")")
                        }
                    }
                default:
                    print("\(String(describing: self)).\(#function) - Photos permissions not granted.")
            }
        }
    }
}

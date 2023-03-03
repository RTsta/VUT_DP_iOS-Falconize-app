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
    struct VideoSettings {
        let width: Int
        let height: Int
        let codec: AVVideoCodecType
        let fileType: AVFileType
        let frameRate: CMTimeScale
        init(width: Int, height: Int, codec: AVVideoCodecType, fileType: AVFileType, frameRate: Int) {
            self.width = width
            self.height = height
            self.codec = codec
            self.fileType = fileType
            self.frameRate = CMTimeScale(frameRate)
        }
        
        func fileTypeExtension() -> String {
            switch self.fileType {
                case .mov:
                    return "mov"
                default:
                    return ""
            }
        }
    }
    
    private let fileManager : FileManager = FileManager.default
    private lazy var chunksDirURL : URL = {
        let url = URL.documentsDirectory.appending(path: "videoChunks")
        try? fileManager.removeItem(at: url)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        
        return url
    }()
    
    private var totalNumberOfChunks : Int = 20
    private var chunkDuration : Double = 1 // seconds

    private var assetWriter : AVAssetWriter?
    private var assetWriterInput : AVAssetWriterInput?
    
    private var chunkNumber : Int = 0
    private var chunkStartTime: CMTime?
    
    private var videoSettings : VideoSettings
    
    enum CaptureHistoryError: Error {
        case runtimeError(String)
    }
    
    
    init(videoSettings: VideoSettings) {
        self.videoSettings = videoSettings
        super.init()
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
    private func createVideoOutput(from buffer: CMSampleBuffer) {
        let timeStamp = CMSampleBufferGetPresentationTimeStamp(buffer)
        // video is running
        if let assetWriter = assetWriter, let chunkStartTime = chunkStartTime {
            let currentDuration = CMTimeGetSeconds(CMTimeSubtract(timeStamp, chunkStartTime))
            // video over duration limit
            if currentDuration > chunkDuration {
                assetWriter.endSession(atSourceTime: timeStamp)
                Task {
                    await assetWriter.finishWriting()
                }
                createWriterInput(at: timeStamp)
            }
        // never recorded before
        } else {
            createWriterInput(at: timeStamp)
        }
        
        if let assetWriterInput = assetWriterInput, assetWriterInput.isReadyForMoreMediaData {
            if !assetWriterInput.append(buffer){
                myErrorPrint("\(String(describing: self )).\(#function) - Error appending assetWriterInput")
            }
        }
    }
        
    private func createWriterInput(at startTime : CMTime) {
        print("Start recoriding: \(chunkNumber)")
        let chunkOutputURL = chunksDirURL.appending(component: "chunk\(String(format: "%02d", chunkNumber)).\(videoSettings.fileTypeExtension())")
        try? fileManager.removeItem(at: chunkOutputURL)
        
        assetWriter = try? AVAssetWriter(outputURL: chunkOutputURL, fileType: .mov)
        guard let assetWriter = assetWriter else {
            myErrorPrint("\(String(describing: self )).\(#function) - not initialized AVAssetWriter")
            fatalError()
        }
            
        assetWriter.shouldOptimizeForNetworkUse = true
        
        let outputSettings : [String : Any] = [AVVideoCodecKey : videoSettings.codec,
                                                AVVideoWidthKey: videoSettings.width,
                                               AVVideoHeightKey: videoSettings.height]
        
        assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        guard let assetWriterInput = assetWriterInput else {
            myErrorPrint("\(String(describing: self )).\(#function) - not initialized AssetWriterInput")
            fatalError()
        }
        assetWriterInput.expectsMediaDataInRealTime = true
        assetWriter.add(assetWriterInput)
        
        chunkNumber = (chunkNumber + 1) % totalNumberOfChunks
        chunkStartTime = startTime
        
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: startTime)
    }
}

// MARK: - AVMutableComposition
extension CaptureHistoryProcessor {
    private func mergeVideos(videoURLs : [URL]) async throws{
        if videoURLs.isEmpty { return }
        
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) //vytvoří novou stopu v kompozici (composition)
        else {
            throw CaptureHistoryError.runtimeError("\(String(describing: self )).\(#function) - Unable to create compositionTrack")
        }
        
        var assetTrack : AVAssetTrack?
        var previusTrackTime : CMTime = .zero
        for videoURL in videoURLs {
            let asset = AVURLAsset(url: videoURL)
            
            assetTrack = try? await asset.loadTracks(withMediaType: .video).first
            guard let assetTrack = assetTrack
            else {
                throw CaptureHistoryError.runtimeError("\(String(describing: self )).\(#function) - Something is wrong with the asset.\(videoURL.debugDescription)")
            }
            
            do {
                let duration = try await asset.load(.duration)
                let timeRange = CMTimeRange(start: .zero, duration: duration)
                try compositionTrack.insertTimeRange(timeRange, of: assetTrack, at: previusTrackTime)
                
                previusTrackTime = CMTimeAdd(previusTrackTime, duration)
            } catch {
                throw error
            }
        }
        
        guard let assetTrack = assetTrack
        else {
            throw CaptureHistoryError.runtimeError("\(String(describing: self )).\(#function) - Something is wrong with the asset.")
        }
        
        let videoComposition = AVMutableVideoComposition()
        do {
            videoComposition.renderSize = try await assetTrack.load(.naturalSize)
        } catch {
            throw error
        }
        videoComposition.frameDuration = CMTime(value: 1, timescale: videoSettings.frameRate)
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero,duration: previusTrackTime)
        videoComposition.instructions = [instruction]
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
        do {
            let transform = try await assetTrack.load(.preferredTransform)
            layerInstruction.setTransform(transform, at: .zero)
            instruction.layerInstructions = [layerInstruction]
        } catch {
            throw error
        }
            
        // export
        let exportURL = await exportVideo(asset: composition, videoComposition: videoComposition)
        if let exportURL = exportURL {
            saveVideoToPhotos(url: exportURL)
        }
    }
    
    private func exportVideo(asset: AVAsset, videoComposition: AVVideoComposition ) async -> URL?{
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
        else {
            myErrorPrint("\(String(describing: self )).\(#function) - Cannot create export session.")
            return nil
        }
        let videoName = UUID().uuidString
        let exportURL = URL.temporaryDirectory
            .appendingPathComponent(videoName)
            .appendingPathExtension(videoSettings.fileTypeExtension())
            
        export.videoComposition = videoComposition
        export.outputFileType = videoSettings.fileType
        export.outputURL = exportURL
            
        await export.export()
        
        switch export.status {
            case .completed:
                return exportURL
            default:
                myErrorPrint("\(String(describing: self )).\(#function) - Something went wrong during export - \(export.error?.localizedDescription ?? "")")
                break
        }
        return nil
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
                            myErrorPrint("\(String(describing: self )).\(#function) - Cannot save video. - \(error?.localizedDescription ?? "unknown error")")
                        }
                    }
                default:
                    myErrorPrint("\(String(describing: self)).\(#function) - Photos permissions not granted.")
            }
        }
    }
    
    func testAction() async {
        guard let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        Task{
            print("AKCE v framu \(chunkNumber)")
            let currentChunkNumber = chunkNumber

            try await Task.sleep(for:Duration.milliseconds(3010))
            guard let contents = try? fileManager.contentsOfDirectory(at: chunksDirURL, includingPropertiesForKeys: nil)
                .sorted(by: {
                    $0.deletingPathExtension().lastPathComponent < $1.deletingPathExtension().lastPathComponent
                }).filter({$0.pathExtension == "mov"}) else { return }
            
            try? await mergeVideos(videoURLs: [contents[chunkNumberIndexing(for: currentChunkNumber-4)],
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
}

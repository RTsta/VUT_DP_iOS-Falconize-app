//
//  CaptureHistoryProcessor.swift
//  Falconize
//
//  Created by Arthur Nácar on 03.02.2023.
//

import Foundation
import AVFoundation
import Photos
import UIKit

// MARK: CaptureHistoryProcessor
class CaptureHistoryProcessor: NSObject {
    private let fileManager: FileManager = FileManager.default
    private lazy var chunksDirURL: URL = {
        let url = URL.documentsDirectory.appending(path: "videoChunks")
        try? fileManager.removeItem(at: url)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        
        return url
    }()
    @Published var isReady: Bool = false
    
    private var totalNumberOfChunks: Int = 20
    private var chunkDuration: Double = 1 // seconds

    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    
    private var chunkNumber: Int = 0
    private var chunkStartTime: CMTime?
    
    private var videoSettings: VideoSettings
    
    /// enumeration for errors related with CaptureHistorySession
    enum CaptureHistoryError: Error {
        case runtimeError(String)
    }
    
    
    init(videoSettings: VideoSettings) {
        self.videoSettings = videoSettings
        super.init()
    }
    
    func changeSettings(newSettings: VideoSettings) {
        self.videoSettings = newSettings
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CaptureHistoryProcessor: AVCaptureVideoDataOutputSampleBufferDelegate {
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
        
        // append frame
        if let assetWriterInput = assetWriterInput, assetWriterInput.isReadyForMoreMediaData {
            if !assetWriterInput.append(buffer) {
                myErrorPrint("\(String(describing: self )).\(#function) - Error appending assetWriterInput")
            }
        }
    }
        
    private func createWriterInput(at startTime: CMTime) {
        print("Start recoriding: \(chunkNumber)")
        let chunkOutputURL = chunksDirURL.appending(component: "chunk\(String(format: "%02d", chunkNumber)).\(videoSettings.fileTypeExtension())")
        try? fileManager.removeItem(at: chunkOutputURL)
        
        assetWriter = try? AVAssetWriter(outputURL: chunkOutputURL, fileType: .mov)
        guard let assetWriter = assetWriter else {
            myErrorPrint("\(String(describing: self )).\(#function) - not initialized AVAssetWriter")
            fatalError("not initialized AVAssetWriter")
        }
            
        assetWriter.shouldOptimizeForNetworkUse = true
        
        var bitsPerPixel: CGFloat = 10.1 // This bitrate approximately matches the quality produced by AVCaptureSessionPresetHigh.
        if self.videoSettings.value.dimensions().width * self.videoSettings.value.dimensions().height < 640 * 480 {
            bitsPerPixel = 4.05 // This bitrate approximately matches the quality produced by AVCaptureSessionPresetMedium or Low.
        }
        
        
        let outputSettings: [String: Any] = [ AVVideoCodecKey: videoSettings.codec,
                                              AVVideoWidthKey: videoSettings.value.dimensions().width,
                                              AVVideoHeightKey: videoSettings.value.dimensions().height,
                              AVVideoCompressionPropertiesKey: [ AVVideoAverageBitRateKey: CGFloat(self.videoSettings.value.dimensions().width) * CGFloat(self.videoSettings.value.dimensions().height) * bitsPerPixel, // swiftlint:disable:this line_length
                                                                              AVVideoExpectedSourceFrameRateKey: self.videoSettings.value.fps(),
                                                                                  AVVideoMaxKeyFrameIntervalKey: self.videoSettings.value.fps()
                                                               ]
                                              ]
        
        assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        guard let assetWriterInput = assetWriterInput else {
            myErrorPrint("\(String(describing: self )).\(#function) - not initialized AssetWriterInput")
            fatalError("not initialized AssetWriterInput")
        }
        assetWriterInput.expectsMediaDataInRealTime = true
        assetWriter.add(assetWriterInput)
        
        chunkNumber = (chunkNumber + 1) % totalNumberOfChunks
        chunkStartTime = startTime
        
        if !isReady && chunkNumber > 4 {
            isReady = true
        }
        
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: startTime)
    }
}

// MARK: - AVMutableComposition
extension CaptureHistoryProcessor {
    
    /// merging videos into one and saves it into camera roll
    ///
    /// - Parameter videoURLs: url of the videos to be merged
    private func mergeVideos(videoURLs: [URL]) async throws {
        if videoURLs.isEmpty {
            return
        }
        
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) // vytvoří novou stopu v kompozici (composition)
        else {
            throw CaptureHistoryError.runtimeError("\(String(describing: self )).\(#function) - Unable to create compositionTrack")
        }
        
        var assetTrack: AVAssetTrack?
        var previusTrackTime: CMTime = .zero
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
        
        // Transform video, set frameRate, resolution
        videoComposition.frameDuration = CMTime(value: 1, timescale: videoSettings.frameRate)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: previusTrackTime)
        videoComposition.instructions = [instruction]
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
        do {
            let sizeAndRotation = outputFinalSizeAndRotation(size: try await assetTrack.load(.naturalSize),
                                  transform: try await assetTrack.load(.preferredTransform))
            videoComposition.renderSize = sizeAndRotation.size
            layerInstruction.setTransform(sizeAndRotation.transform, at: .zero)
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
    
    /// Rotation based on current device orientation
    private func outputFinalSizeAndRotation(size: CGSize, transform: CGAffineTransform) -> (size: CGSize, transform: CGAffineTransform) {
        let deviceOrientation = UIDevice.current.orientation
        if deviceOrientation == .portrait && size.width > size.height {
            return (CGSize(width: size.height, height: size.width),
                    transform.translatedBy(x: size.height, y: 0).rotated(by: .pi/2))
        } else if deviceOrientation == .portraitUpsideDown && size.width > size.height {
            return (CGSize(width: size.height, height: size.width),
                     transform.translatedBy(x: 0, y: size.width).rotated(by: .pi * 1.5))
        } else if deviceOrientation == .landscapeRight {
            return (size, transform.translatedBy(x: size.width, y: size.height).rotated(by: .pi))
        } else {
            return (size, transform)
        }
    }

    /// export video
    ///
    /// - Returns: temporary URL of the video
    private func exportVideo(asset: AVAsset, videoComposition: AVVideoComposition ) async -> URL? {
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
        }
        return nil
    }
    
    /// save to camera roll
    func saveVideoToPhotos(url videoURL: URL) {
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            switch status {
                case .authorized:
                    PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                    } completionHandler: { [weak self] (isSaved, error) in
                        if isSaved {
                            myDebugPrint("video saved", onScreen: true)
                        } else {
                            myErrorPrint("\(String(describing: self )).\(#function) - Cannot save video. - \(error?.localizedDescription ?? "unknown error")")
                        }
                    }
                default:
                    myErrorPrint("\(String(describing: self)).\(#function) - Photos permissions not granted.")
            }
        }
    }
    
    /// selects last 2 seconds and one further of the video, merges it and saves it
    func movementActionTrigged() async {
        Task {
            print("AKCE v framu \(chunkNumber)")
            let currentChunkNumber = chunkNumber

            try await Task.sleep(for: Duration.milliseconds(3010))
            guard let contents = try? fileManager.contentsOfDirectory(at: chunksDirURL, includingPropertiesForKeys: nil)
                .sorted(by: { $0.deletingPathExtension().lastPathComponent < $1.deletingPathExtension().lastPathComponent })
                .filter({ $0.pathExtension == "mov" })
            else { return }
            
            try? await mergeVideos(videoURLs: [contents[chunkNumberIndexing(for: currentChunkNumber-4)],
                                          contents[chunkNumberIndexing(for: currentChunkNumber-3)],
                                          contents[chunkNumberIndexing(for: currentChunkNumber-2)],
                                          contents[chunkNumberIndexing(for: currentChunkNumber-1)],
                                          contents[chunkNumberIndexing(for: currentChunkNumber)],
                                          contents[chunkNumberIndexing(for: currentChunkNumber+1)]
                                         ])
        }
    }
    
    /// helper function for indexing of chunks
    private func chunkNumberIndexing(for index: Int) -> Int {
        if index >= 0 {
            return index % totalNumberOfChunks
        } else {
            return (totalNumberOfChunks + index) % totalNumberOfChunks
        }
    }
}

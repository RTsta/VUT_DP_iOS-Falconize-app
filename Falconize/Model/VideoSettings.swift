//
//  VideoSettings.swift
//  Falconize
//
//  Created by Arthur Nácar on 16.03.2023.
//

import Foundation
import AVFoundation

struct VideoSettings {
    let value: CaptureQualityPreset
    
    /// enumeration with custom video settings
    enum CaptureQualityPreset: Equatable {
        case v720p30fps
        case v1080p30fps
        case v1080p60fps
        case v4k30fps
        case v1080p120fps
        case v1080p240fps
        
        /// fps
        func fps() -> Double {
            switch self {
                case .v720p30fps, .v1080p30fps, .v4k30fps:
                    return 30
                case .v1080p60fps:
                    return 60
                case .v1080p120fps:
                    return 120
                case .v1080p240fps:
                    return 240
            }
        }
        
        /// Resolution of the format
        func preset() -> AVCaptureSession.Preset {
            switch self {
                case .v720p30fps:
                    return .hd1280x720
                case .v1080p30fps, .v1080p60fps, .v1080p120fps, .v1080p240fps:
                    return .hd1920x1080
                case .v4k30fps:
                    return .hd4K3840x2160
            }
        }
        
        /// dimensions using CMVideoDimensions
        func dimensions() -> CMVideoDimensions {
            switch self {
                case .v720p30fps:
                    return CMVideoDimensions(width: 1280, height: 720)
                case .v1080p30fps, .v1080p60fps, .v1080p120fps, .v1080p240fps:
                    return CMVideoDimensions(width: 1920, height: 1080)
                case .v4k30fps:
                    return CMVideoDimensions(width: 3840, height: 2160)
            }
        }
    }
    
    let codec: AVVideoCodecType
    let fileType: AVFileType
    let frameRate: CMTimeScale
    let width: Int32
    let height: Int32
    
    init(type: CaptureQualityPreset, codec: AVVideoCodecType, fileType: AVFileType) {
        self.value = type
        self.codec = codec
        self.fileType = fileType
        self.frameRate = CMTimeScale(type.fps())
        self.width = type.dimensions().width
        self.height = type.dimensions().height
    }
    
    /// video file format
    func fileTypeExtension() -> String {
        switch self.fileType {
            case .mov:
                return "mov"
            default:
                return ""
        }
    }
}

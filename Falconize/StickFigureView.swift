//
//  StickFigureView.swift
//  Falconize
//
//  Created by Arthur Nácar on 08.11.2022.
//

import SwiftUI
import AVFoundation.AVCaptureDevice

struct StickFigureView: View {
    struct Stick: Shape {
        var points: [CGPoint]
        var size: CGSize
        
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: points[0])
            
            for point in points {
                if point.y == 0.0 || point.y == 1.0 {
                    break
                }
                path.addLine(to: point)
            }
                
            path = path.applying(CGAffineTransform.identity.scaledBy(x: size.width, y: size.height))
            path = path.applying(CGAffineTransform(scaleX: -1, y: -1).translatedBy(x: -size.width, y: -size.height))
            return path
        }
    }
    
    @ObservedObject var posePredictor: PosePredictor
    var size: CGSize
    var body: some View {
        if let parts = posePredictor.bodyParts {
            ZStack {
                // Right leg
                Stick(points: [parts[.rightAnkle]!.location,
                               parts[.rightKnee]!.location,
                               parts[.rightHip]!.location,
                               parts[.root]!.location],
                      size: size)
                .stroke(lineWidth: 5.0)
                .fill(Color.green)
                
                // Left leg
                Stick(points: [parts[.leftAnkle]!.location,
                               parts[.leftKnee]!.location,
                               parts[.leftHip]!.location,
                               parts[.root]!.location],
                      size: size)
                .stroke(lineWidth: 5.0)
                .fill(Color.green)
                
                // Right arm
                Stick(points: [parts[.rightWrist]!.location,
                               parts[.rightElbow]!.location,
                               parts[.rightShoulder]!.location,
                               parts[.neck]!.location],
                      size: size)
                    .stroke(lineWidth: 5.0)
                    .fill(Color.green)
                // Left arm
                Stick(points: [parts[.leftWrist]!.location,
                               parts[.leftElbow]!.location,
                               parts[.leftShoulder]!.location,
                               parts[.neck]!.location],
                      size: size)
                    .stroke(lineWidth: 5.0)
                    .fill(Color.green)
                // Root to nose
                Stick(points: [parts[.root]!.location,
                               parts[.neck]!.location,
                               parts[.nose]!.location],
                      size: size)
                .stroke(lineWidth: 5.0)
                .fill(Color.green)
            }
        }
    }
}

struct StickFigureView_Previews: PreviewProvider {
    static var previews: some View {
        StickFigureView(posePredictor: PosePredictor(), size: CGSize(width: 100, height: 100))
    }
}

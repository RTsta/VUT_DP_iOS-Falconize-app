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
            points.forEach{
                path.addLine(to: $0)
            }
            path = path.applying(CGAffineTransform.identity.scaledBy(x: size.width, y: size.height))
            path = path.applying(CGAffineTransform(scaleX: -1, y: -1).translatedBy(x: -size.width, y: -size.height))
            return path
        }
    }
    
    @ObservedObject var posePredictor: PosePredictor
    var size: CGSize
    var body: some View {
        if posePredictor.bodyParts.isEmpty == false {
            ZStack {
                // Right leg
                Stick(points: [posePredictor.bodyParts[.rightAnkle]!.location,
                               posePredictor.bodyParts[.rightKnee]!.location,
                               posePredictor.bodyParts[.rightHip]!.location,
                               posePredictor.bodyParts[.root]!.location],
                      size: size)
                .stroke(lineWidth: 5.0)
                .fill(Color.green)
                
                // Left leg
                Stick(points: [posePredictor.bodyParts[.leftAnkle]!.location,
                               posePredictor.bodyParts[.leftKnee]!.location,
                               posePredictor.bodyParts[.leftHip]!.location,
                               posePredictor.bodyParts[.root]!.location],
                      size: size)
                .stroke(lineWidth: 5.0)
                .fill(Color.green)
                
                // Right arm
                Stick(points: [posePredictor.bodyParts[.rightWrist]!.location,
                               posePredictor.bodyParts[.rightElbow]!.location,
                               posePredictor.bodyParts[.rightShoulder]!.location,
                               posePredictor.bodyParts[.neck]!.location],
                      size: size)
                    .stroke(lineWidth: 5.0)
                    .fill(Color.green)
                // Left arm
                Stick(points: [posePredictor.bodyParts[.leftWrist]!.location,
                               posePredictor.bodyParts[.leftElbow]!.location,
                               posePredictor.bodyParts[.leftShoulder]!.location,
                               posePredictor.bodyParts[.neck]!.location],
                      size: size)
                    .stroke(lineWidth: 5.0)
                    .fill(Color.green)
                // Root to nose
                Stick(points: [posePredictor.bodyParts[.root]!.location,
                               posePredictor.bodyParts[.neck]!.location,
                               posePredictor.bodyParts[.nose]!.location],
                      size: size)
                .stroke(lineWidth: 5.0)
                .fill(Color.green)
            }
        }
    }
}

struct StickFigureView_Previews: PreviewProvider {
    static var previews: some View {
        StickFigureView(posePredictor: PosePredictor() , size: CGSize(width: 100, height: 100))
    }
}

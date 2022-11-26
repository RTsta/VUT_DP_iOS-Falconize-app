//
//  PoseTextView.swift
//  Falconize
//
//  Created by Arthur Nácar on 25.11.2022.
//

import SwiftUI

struct PoseTextView: View {
    @ObservedObject var posePredictor: PosePredictor
    
    var body: some View {
        if posePredictor.bodyParts.isEmpty == false {
            VStack {
                Text("Right x:\(posePredictor.bodyParts[.rightWrist]!.location.x) y:\(posePredictor.bodyParts[.rightWrist]!.location.y)")
                Text("Left x:\(posePredictor.bodyParts[.leftWrist]!.location.x) y:\(posePredictor.bodyParts[.leftWrist]!.location.y)")
                Text("Actions: \(posePredictor.actionCount)")
            }
        }
    }
}

struct PoseTextView_Previews: PreviewProvider {
    static var previews: some View {
        PoseTextView(posePredictor: PosePredictor())
    }
}

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
        if let parts = posePredictor.bodyParts {
            VStack {
                Text("Right x:\(parts[.rightWrist]!.location.x) y:\(parts[.rightWrist]!.location.y)")
                Text("Left x:\(parts[.leftWrist]!.location.x) y:\(parts[.leftWrist]!.location.y)")
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

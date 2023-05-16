//
//  myUtil.swift
//  Falconize
//
//  Created by Arthur Nácar on 07.02.2023.
//

import Foundation
import SwiftUI

/// global declaration for Notification string used for printing on custom debugView
extension Notification.Name {
    static let myDebugPrintNotification = Notification.Name("myDebugPrintNotification")
}

/// formated printing for debug purposes
func myDebugPrint(_ something: Any, _ title: String = "", onScreen: Bool = false) {
    print("*********** \(title) ***********")
    print("\(something)")
    var final = ""
    for _ in 0..<title.count { final += "*"}
    print("************\(final)************")
    if onScreen {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .myDebugPrintNotification, object: nil, userInfo: ["debugPrintText": "\(something)"])
        }
    }
}


/// formated print error
func myErrorPrint(_ something: Any) {
    print("!!! Error !!! \(something)")
}

/// view for displaying prins in app
struct ConsoleLogText: View {
    @State private var consoleText: String = ""
    var body: some View {
        ScrollView {
            Text(consoleText)
                .multilineTextAlignment(.leading)
                .onReceive(NotificationCenter.default.publisher(for: .myDebugPrintNotification)) { objc in
                    if let userInfo = objc.userInfo,
                       let debugPrintText = userInfo["debugPrintText"] as? String {
                        consoleText = "[\(Date().formatted(date: .omitted, time: .standard))] \(debugPrintText)\n" + consoleText
                    }
                }
        }.frame(maxWidth: .infinity, minHeight: 40)
    }
}


/// view for displaying debug information from posePredictor
struct PoseTextView: View {
    @ObservedObject var posePredictor: PosePredictor
    
    var body: some View {
        if let parts = posePredictor.bodyParts {
            VStack {
                Text("Right x:\(parts[.rightWrist]!.location.x) y:\(parts[.rightWrist]!.location.y)")
                Text("Left x:\(parts[.leftWrist]!.location.x) y:\(parts[.leftWrist]!.location.y)")
                HStack {
                    Text("Actions: \(posePredictor.actionCount)")
                    if let pose = posePredictor.poseClasification {
                        Text("\(pose.label), \(pose.convidence)")
                    }
                }
            }
        }
    }
}

struct PoseTextView_Previews: PreviewProvider {
    static var previews: some View {
        PoseTextView(posePredictor: PosePredictor())
    }
}

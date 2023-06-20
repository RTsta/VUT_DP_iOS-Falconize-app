//
//  FocusPointView.swift
//  Falconize
//
//  Created by Arthur Nácar on 29.03.2023.
//

import SwiftUI

struct FocusPointView: View {
    var lineWidth: CGFloat = 1
    var linesLenght: CGFloat = 10
    
    var body: some View {
        Canvas { context, size in
            context.stroke(
                Path { path in
                    path.addRect(CGRect(origin: CGPoint(x: lineWidth/2,
                                                        y: lineWidth/2),
                                        size: CGSize(width: size.width-lineWidth,
                                                     height: size.height-lineWidth)))

                    path.move(to: CGPoint(x: size.width/2, y: .zero))
                    path.addLine(to: CGPoint(x: size.width/2, y: linesLenght))
                        
                    path.move(to: CGPoint(x: size.width/2, y: size.height))
                    path.addLine(to: CGPoint(x: size.width/2, y: size.height-linesLenght))
                    
                    path.move(to: CGPoint(x: .zero, y: size.height/2))
                    path.addLine(to: CGPoint(x: linesLenght, y: size.height/2))
                    
                    path.move(to: CGPoint(x: size.width, y: size.height/2))
                    path.addLine(to: CGPoint(x: size.width-linesLenght, y: size.height/2))
                    
                },
                with: .color(.yellow),
                lineWidth: lineWidth)
        }
    }
}

struct FocusPointView_Previews: PreviewProvider {
    static var previews: some View {
        FocusPointView(lineWidth: 1)
    }
}

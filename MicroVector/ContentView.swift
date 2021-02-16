//
//  ContentView.swift
//  MicroVector
//
//  Created by Marc Prud'hommeaux on 2/12/21.
//

import SwiftUI
import MemoZ

struct ContentView: View {
    @Binding var document: MicroVectorDocument

    var body: some View {
        VSplitView {
            ScrollView([.vertical, .horizontal], showsIndicators: true) {
                MagnificationGestureView { magnifyBy in
                    Image(nsImage: document.svgText.svgImageZ ?? errorImage)
//                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(magnifyBy)
                }
            }
            GroupBox(label: Text("SVG")) {
                TextEditor(text: $document.svgText)
                    .font(Font.custom("Menlo", size: 15, relativeTo: .body))
            }
        }
    }
}

struct MagnificationGestureView<Content: View>: View {
    @GestureState var magnifyBy = CGFloat(1.0)
    @State private var magnifyState = CGFloat?.none

    let content: (CGFloat) -> Content

    var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { _ in
                self.magnifyState = nil
            }
            .updating($magnifyBy) { currentState, gestureState, transaction in
                //print("magnify", currentState, gestureState, transaction)
            }
            .onEnded({ (value) in
                self.magnifyState = value
            })
    }

    var body: some View {
        content(min(999, max(0.0000001, magnifyState ?? magnifyBy)))
            .gesture(magnification)
            //.environment(\.displayScale, magnifyBy)
    }
}


let errorImage = NSImage(named: NSImage.bookmarksTemplateName)!

extension String {
    var svgImageZ: NSImage? {
        memoz.svgImage
    }

    var svgImage: NSImage? {
        NSImage(svg: self.data(using: .utf8) ?? .init())
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(document: .constant(MicroVectorDocument()))
    }
}

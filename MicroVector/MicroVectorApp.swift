//
//  MicroVectorApp.swift
//  MicroVector
//
//  Created by Marc Prud'hommeaux on 2/12/21.
//

import SwiftUI
import MiscKit
import MemoZ

@main
struct MicroVectorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: MicroVectorDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        dbg(notification)
        HubOMatic.start(update: URL(string: "https://github.com/hubomatic/MicroVector/releases/latest/download/RELEASE_NOTES.md")!, artifact: "MicroVector.zip", title: loc("A new version of MicroVector is available!"))
    }

    func applicationDidResignActive(_ notification: Notification) {
        MemoizationCache.shared.clear()
    }
}

//
//  MicroVectorApp.swift
//  MicroVector
//
//  Created by Marc Prud'hommeaux on 2/12/21.
//

import SwiftUI
import MiscKit
import HubOMatic

@main
struct MicroVectorApp: App {
    @StateObject var hub = HubOMatic.create(.github(org: "hubomatic", repo: "MicroVector"))

    @SceneBuilder var body: some Scene {
        DocumentGroup(newDocument: MicroVectorDocument()) { file in
            ContentView(document: file.$document)
                .toolbar {
                    hub.toolbarButton()
                }
        }
        .withHubOMatic(hub)

//        Settings {
//            hub.settingsView(autoupdate: $autoupdate)
//        }
    }
}

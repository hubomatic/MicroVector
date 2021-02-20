//
//  Hub.swift
//  MicroVector
//
//  Created by Marc Prud'hommeaux on 2/20/21.
//

import Foundation
import HubOMatic

///// TODO: Move into HubOMatic once GitHub CI machines enable macos-11.0
//public struct HubOMaticUpdateCommands : Commands {
//    let hub: HubOMatic
//
//    public var body: some Commands {
//        Group {
//            CommandGroup(after: CommandGroupPlacement.appSettings) {
//                Button(LocalizedStringKey("Check for Updates"), action: hub.checkForUpdateAction)
//            }
//        }
//    }
//}
//
//public extension Scene {
//    func withHubOMatic(_ hub: HubOMatic) -> some Scene {
//        Group {
//            self.commands { HubOMaticUpdateCommands(hub: hub) }
//        }
//    }
//}

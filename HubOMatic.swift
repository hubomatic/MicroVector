//
//  HubOMatic.swift
//  MicroVector
//
//  Created by Marc Prud'hommeaux on 2/12/21.
//

import Foundation
import MiscKit
// import HubOMatic // TODO: re-import

public extension HubOMatic {
    @discardableResult static func start(update: URL, artifact: String, title: String = loc("An update is available for installation"), updateTitle: String = loc("Update"), cancelTitle: String = loc("Cancel")) -> Self {
        HubOMatic()
    }
}

public struct HubOMatic {
    struct Config : Hashable, Codable {
        var repository: URL
    }

    var text = "Hello, World!"

    public init() {

    }
}


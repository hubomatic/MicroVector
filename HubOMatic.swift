//
//  HubOMatic.swift
//  MicroVector
//
//  Created by Marc Prud'hommeaux on 2/12/21.
//

import Foundation
import MiscKit
import SwiftUI

// import HubOMatic // TODO: re-import

public extension View {
    /// - Note: the current environment much have a `HubOMatic` environment object
    func withHub(oMatic component: HubOMatic.Component) -> some View {
        self
    }
}

public extension HubOMatic {
    enum Component {
        case settingsPanel
        case checkForUpdateButton
        case viewReleaseNotesPanel
    }

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

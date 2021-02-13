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

public struct HubOMatic {
    struct Config : Hashable, Codable {
        var repository: URL
    }

    var text = "Hello, World!"

    public init() {
    }
}

public extension HubOMatic {
    @discardableResult static func start(update: URL, artifact: String, title: String = loc("An update is available for installation"), updateTitle: String = loc("Update"), cancelTitle: String = loc("Cancel")) -> Self {
        HubOMatic()
    }
}

public extension HubOMatic {
    struct UpdateAvailableBannerView : View {
        public var body: some View {
            wip(EmptyView())
        }
    }

    struct CheckForUpdateButton : View {
        public var body: some View {
            wip(EmptyView())
        }
    }

    struct UpdateSettingsView : View {
        public var body: some View {
            wip(EmptyView())
        }
    }

    struct ReleaseNotesPreviewView : View {
        public var body: some View {
            wip(EmptyView())
        }
    }

}

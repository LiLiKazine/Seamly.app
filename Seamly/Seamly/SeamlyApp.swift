//
//  SeamlyApp.swift
//  Seamly
//
//  Created by Leo Sheng on 2026/7/4.
//

import SwiftUI

@main
struct SeamlyApp: App {
    init() {
        #if DEBUG
        DebugSeed.seedIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            AppShell()
        }
    }
}

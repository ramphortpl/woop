import SwiftUI

@main
struct WoopApp: App {
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.black.ignoresSafeArea()
                Text("WOOP").font(.largeTitle.weight(.bold)).foregroundColor(.white)
            }
        }
    }
}

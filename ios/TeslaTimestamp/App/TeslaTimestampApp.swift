#if canImport(UIKit)
import SwiftUI

@main
struct TeslaTimestampApp: App {
    @StateObject private var viewModel = MainViewModel()

    var body: some Scene {
        WindowGroup {
            MainView(viewModel: viewModel)
                .onOpenURL { url in
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                        viewModel.scanFolder(url: url)
                    } else if url.pathExtension.lowercased() == "mp4" || url.pathExtension.lowercased() == "mov" {
                        viewModel.scanDocument(url: url)
                    }
                }
        }
    }
}
#endif

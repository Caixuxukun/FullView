import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var tapCount = 0

    var body: some View {
        VStack(spacing: 20) {
            Text("你好，世界！")
                .font(.largeTitle)
            Text("按钮已点击 \(tapCount) 次")
            Button(action: {
                tapCount += 1
            }) {
                Text("点我 +1")
                    .padding()
                    .background(Color.blue.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
    }
}
import SwiftUI

struct ContentView: View {
    @StateObject private var tvbox = TVBoxStore()

    var body: some View {
        TabView {
            // 一比一复刻：首页（点播 98 站点）/ 直播 / 搜索 / 我的 / 设置
            TVBoxHomeView(store: tvbox)
                .tabItem { Label("首页", systemImage: "house.fill") }
            TVBoxLiveView(store: tvbox)
                .tabItem { Label("直播", systemImage: "tv") }
            TVBoxSearchView(store: tvbox)
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
            TVBoxLibraryView(store: tvbox)
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
            TVBoxSettingsView(store: tvbox)
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        // 原有独立功能在「我的 → 更多功能」中保留；全屏播放器由 HubPlayerApp 统一调度
    }
}

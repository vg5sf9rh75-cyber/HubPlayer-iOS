# Hub 播放器 iOS 版（HubPlayer）— 单机空壳版

## 当前版本（2026-11-04）：单机运行，无需中继

按「不用中继、站点空壳、后期自行配置」重构。App **不依赖第二台安卓设备**，
配置 / 站点 / 直播源全部由你在 App 内自行填写，由 iOS 本地引擎直连执行。

```
iPhone 本机 (HubPlayer.ipa)
├── 配置来源：URL 拉取 / 粘贴 JSON / 粘贴 base64
├── 站点：自定义 CMS(苹果CMS v10) / 直链 JSON / ext 直读
│         └─ homeContent / categoryContent / detailContent / searchContent
│            → ac=videolist & t / pg / wd / ids
├── 播放：playerContent 直链 → parses 解析接口 → AVPlayer（自定义 Header）
├── 直播：M3U 地址 / 粘贴 M3U 文本（分组、搜索、UA、EPG 属性）
└── 其他：网络直链 / WebDAV / 夸克 / 哔哩扫码 / 历史 / 收藏 / 屏显
```

### 关于配置里的 `csp_` 站点

`aiwex.json` 的 98 个站点全部是 `type=3 / csp_*`，真实逻辑在 `spider` 包
（伪装成 `.jpg` 的 jar）里的 DEX + ARM 加固壳：`wexguard_v7/v8.so` +
`wexshinidie.guard`（968 KB 加密载荷），依赖 bionic / JNI / Android Framework。
iOS 侧没有这套运行时，因此这些条目**只作为占位保留在站点列表**（标「占位」），
点开会给出明确提示，不会伪造数据。后期在「设置 → 自定义站点」换成任意
CMS / 直链接口即可使用，站点切换、分类、筛选、搜索、详情、选集、播放链路都是现成的。

### 三步开始用

1. 安装 `HubPlayer-unsigned.ipa`（Sideloadly / AltStore 用你自己的 Apple ID 重签）。
2. App →「设置」→「添加站点」，填 CMS 采集地址，例如
   `https://example.com/api.php/provide/vod/`；也可填配置地址、粘贴整份 TVBox 配置或 base64。
3. 「设置」→「自检并重新加载」；直播在「添加直播源」填 M3U 地址，或直接粘贴 M3U 文本。

> 默认不预置站点、不预置配置地址——按要求全部后期自行配置。

---

## 功能对照

| 功能 | 状态 | 说明 |
|---|---|---|
| 首页 / 站点切换 / 分类 / 筛选 | ✅ | 数据来自你配置的站点 |
| 搜索（当前源 + 全站聚合并发） | ✅ | 自动跳过 `csp_` 占位站点 |
| 详情 / 多线路 / 选集 / 播放 | ✅ | AVPlayer，支持自定义 Header |
| parses 解析接口 + headers | ✅ | 配置里带就自动生效 |
| 直播 M3U（分组 / 搜索 / UA / 屏显） | ✅ | 地址或粘贴文本 |
| 网络直链 / WebDAV / 夸克 / 哔哩扫码 | ✅ | 「我的 → 更多功能」 |
| 播放历史 / 收藏 | ✅ | UserDefaults 本地持久化 |
| 播放时显示详细信息（屏显） | ✅ | 设置里开关 |
| 98 个 `csp_` DEX 点播站 | ⚠️ 占位 | 单机版不内置安卓 DEX 运行时 |

---

## 出 IPA

### 方式一：macOS + Xcode 一键（推荐）

整个目录拷到 Mac，终端进入目录执行：

```bash
bash build_ipa.sh
```

默认走 `CODE_SIGNING_ALLOWED=NO` 的 Archive，直接产出
`build/ipa/HubPlayer-unsigned.ipa`，**不需要任何 Apple 开发者配置**，
再用 Sideloadly / AltStore 现场重签安装。

若有证书与描述文件：

```bash
TEAM_ID=XXXXXXXXXX PROFILE_NAME="My Profile" bash build_ipa.sh
```

会生成 `ExportOptions.plist` 并走 `xcodebuild -exportArchive` 出签名 IPA。

> Windows / 本机环境无法生成 IPA（必须 macOS + Xcode 工具链）。

### 方式二：GitHub Actions 云端 Mac

`.github/workflows/build-ipa.yml` 在 `macos-latest` 上 Archive：

- 未配置签名 Secrets → 打包 `HubPlayer-unsigned.ipa`（`Payload/` + zip）
- 配置 `TEAM_ID` / `P12_BASE64` / `CERT_PASSWORD` / `PROVISIONING_PROFILE_BASE64`
  → 手动签名导出

产物同时上传 Artifact、回传 `ipa-delivery` 分支。
`tools/push_and_get_ipa.py` 可用 `GITHUB_TOKEN` 自动建仓 / 推送 / 触发 / 下载到桌面：

```bash
GITHUB_TOKEN=ghp_xxx python tools/push_and_get_ipa.py
```

---

## 使用说明

- **自定义站点**：「设置 → 添加站点」填名称 / API / 类型 / ext。引擎把标准 Spider
  方法映射到苹果CMS v10 参数（`ac=videolist`、`t`、`pg`、`wd`、`ids`），
  数字型 `type_id` / `vod_id` / `pagecount` 已做兼容。
- **配置来源优先级**：粘贴的配置内容 > 配置地址 > 空模板；自定义站点与直播源会追加合并。
- **直播源**：支持 M3U / M3U8 / txt / php 代理接口，只要返回标准 M3U 文本；
  也可直接粘贴 M3U，生成「粘贴的直播源」。
- **夸克 / 哔哩**：扫码登录后用 Cookie 持久化，夸克走 `file/list` + `file/download` 换直链。
- **WebDAV**：PROPFIND 浏览目录，点视频即播。

---

## 工程结构

```
HubPlayer-iOS/
├── HubPlayer.xcodeproj/            # Xcode 工程（已注册全部 Swift 文件）
├── build_ipa.sh                    # macOS 一键出 IPA（默认未签名）
├── ExportOptions.plist             # 签名导出配置（可选）
├── .github/workflows/build-ipa.yml # 云端 macOS 编译
├── tools/
│   ├── hub_to_m3u8.py              # TVBox 配置 → 标准 M3U
│   └── push_and_get_ipa.py         # REST API 推送 + 触发 + 下载 IPA
├── exports/Hub直播源_aiwex.m3u     # 从 aiwex.json 提取的 308 频道（可直接粘贴导入）
└── HubPlayer/
    ├── HubPlayerApp.swift          # 入口 + 全屏播放调度
    ├── ContentView.swift           # 首页/直播/搜索/我的/设置
    ├── Info.plist                  # iOS 16+、arm64、NSAllowsArbitraryLoads
    ├── TVBox/
    │   ├── RelayClient.swift       # 单机本地引擎（无中继）
    │   ├── TVBoxModels.swift       # 配置模型 / VOD 解析 / M3U 解析
    │   ├── TVBoxStore.swift        # 状态机
    │   ├── TVBoxHomeView.swift     # 首页影片墙
    │   ├── TVBoxDetailView.swift   # 详情 / 选集
    │   └── TVBoxMoreViews.swift    # 搜索 / 直播 / 我的 / 设置 / 自定义源
    ├── ViewModels/PlayerManager.swift
    ├── Views/                      # 播放器、直链、WebDAV、夸克、哔哩、登录壳
    ├── Helpers/                    # SourceStore / WebDavManager / QuarkManager
    └── Models/                     # Channel / PlaylistParser
```

---

## 已知限制

- 最低系统 **iOS 16.0**，仅 arm64 真机。
- `NSAllowsArbitraryLoads=true`，因为大量直播源是 `http://`。
- `Assets.xcassets/AppIcon.appiconset` 未放图，上架前需补 1024×1024 图标。
- `HubRelay/` 与 `.github/workflows/build-relay.yml` 是上一版中继方案的历史源码，
  当前单机版不会编译、也不需要使用。

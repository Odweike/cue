import ProjectDescription

let baseSettings: [String: SettingValue] = [
    "SWIFT_VERSION": "6.0",
    "MACOSX_DEPLOYMENT_TARGET": "26.0",
    "MARKETING_VERSION": "0.1.0",
    "CURRENT_PROJECT_VERSION": "1",
    "CODE_SIGN_STYLE": "Automatic",
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon"
]

var appSettings = baseSettings
appSettings["PRODUCT_NAME"] = "Cue"
appSettings["EXECUTABLE_NAME"] = "VideoPlayer"
appSettings["PRODUCT_MODULE_NAME"] = "VideoPlayer"

let project = Project(
    name: "VideoPlayer",
    options: .options(
        disableBundleAccessors: true,
        disableSynthesizedResourceAccessors: true
    ),
    settings: .settings(base: baseSettings),
    targets: [
        .target(
            name: "VideoPlayer",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.maxim.videoplayer",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Cue",
                "CFBundleName": "Cue",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "CFBundleDocumentTypes": .array([
                    .dictionary([
                        "CFBundleTypeName": .string("Video"),
                        "CFBundleTypeRole": .string("Viewer"),
                        "LSHandlerRank": .string("Owner"),
                        "LSItemContentTypes": .array([.string("public.movie")])
                    ])
                ]),
                "LSApplicationCategoryType": "public.app-category.video"
            ]),
            sources: ["Sources/VideoPlayer/**"],
            resources: ["Sources/VideoPlayer/Resources/**"],
            dependencies: [],
            settings: .settings(base: appSettings)
        ),
        .target(
            name: "VideoPlayerTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.maxim.videoplayer.tests",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .default,
            sources: ["Tests/VideoPlayerTests/**"],
            dependencies: [.target(name: "VideoPlayer")]
        )
    ]
)

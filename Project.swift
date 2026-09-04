import ProjectDescription

let settings: Settings = .settings(base: [
    "SWIFT_VERSION": "6.0",
    "MACOSX_DEPLOYMENT_TARGET": "26.0",
    "MARKETING_VERSION": "0.1.0",
    "CURRENT_PROJECT_VERSION": "1",
    "CODE_SIGN_STYLE": "Automatic",
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon"
])

let project = Project(
    name: "VideoPlayer",
    options: .options(
        disableBundleAccessors: true,
        disableSynthesizedResourceAccessors: true
    ),
    settings: settings,
    targets: [
        .target(
            name: "VideoPlayer",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.maxim.videoplayer",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "VoxFrame",
                "CFBundleName": "VoxFrame",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "LSApplicationCategoryType": "public.app-category.video"
            ]),
            sources: ["Sources/VideoPlayer/**"],
            resources: ["Sources/VideoPlayer/Resources/**"],
            dependencies: [],
            settings: settings
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

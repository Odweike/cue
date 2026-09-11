import ProjectDescription

let baseSettings: [String: SettingValue] = [
    "SWIFT_VERSION": "6.0",
    "MACOSX_DEPLOYMENT_TARGET": "26.0",
    "MARKETING_VERSION": "0.1.4",
    "CURRENT_PROJECT_VERSION": "6",
    "CODE_SIGN_STYLE": "Automatic",
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon"
]

var appSettings = baseSettings
appSettings["PRODUCT_NAME"] = "Cue"
appSettings["EXECUTABLE_NAME"] = "VideoPlayer"
appSettings["PRODUCT_MODULE_NAME"] = "VideoPlayer"
appSettings["DEVELOPMENT_TEAM"] = "95TC3M7268"
appSettings["CODE_SIGN_IDENTITY"] = "Apple Development"

let project = Project(
    name: "VideoPlayer",
    options: .options(
        disableBundleAccessors: true,
        disableSynthesizedResourceAccessors: true
    ),
    packages: [
        .remote(
            url: "https://github.com/mpvkit/MPVKit.git",
            requirement: .exact("1.0.0")
        )
    ],
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
                "NSMainStoryboardFile": "",
                "NSSpeechRecognitionUsageDescription": "Cue uses on-device speech recognition to generate subtitles for videos you choose.",
                "NSDesktopFolderUsageDescription": "Cue reads video files you open from the Desktop.",
                "NSDocumentsFolderUsageDescription": "Cue reads video files you open from Documents.",
                "NSDownloadsFolderUsageDescription": "Cue reads video files you open from Downloads.",
                "NSRemovableVolumesUsageDescription": "Cue reads video files you open from external drives.",
                "NSNetworkVolumesUsageDescription": "Cue reads video files you open from network volumes.",
                "LSSupportsOpeningDocumentsInPlace": true,
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "CFBundleDocumentTypes": .array([
                    .dictionary([
                        "CFBundleTypeName": .string("Video"),
                        "CFBundleTypeRole": .string("Viewer"),
                        "LSHandlerRank": .string("Owner"),
                        "LSItemContentTypes": .array([
                            .string("public.movie"),
                            .string("org.matroska.mkv")
                        ])
                    ])
                ]),
                "UTImportedTypeDeclarations": .array([
                    .dictionary([
                        "UTTypeConformsTo": .array([.string("public.movie")]),
                        "UTTypeDescription": .string("Matroska Video"),
                        "UTTypeIdentifier": .string("org.matroska.mkv"),
                        "UTTypeTagSpecification": .dictionary([
                            "public.filename-extension": .array([.string("mkv")]),
                            "public.mime-type": .string("video/x-matroska")
                        ])
                    ])
                ]),
                "LSApplicationCategoryType": "public.app-category.video"
            ]),
            sources: ["Sources/VideoPlayer/**"],
            resources: ["Sources/VideoPlayer/Resources/**"],
            dependencies: [
                .package(product: "MPVKit")
            ],
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

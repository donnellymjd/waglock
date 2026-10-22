// swift-tools-version: 6.2
import PackageDescription

// Isolated research executable. This package is not referenced by the iOS app.
let package = Package(
    name: "VaultitoCryptomatorSpike",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(url: "https://github.com/cryptomator/cryptolib-swift.git",
                 revision: "b339c9ba84f7737377ef187a78900f9cc384cb12"),
    ],
    targets: [
        .executableTarget(name: "WagLockPortableExportFixture", dependencies: [
            .product(name: "CryptomatorCryptoLib", package: "cryptolib-swift"),
        ]),
        .executableTarget(name: "VaultitoCryptomatorSpike", dependencies: [
            .product(name: "CryptomatorCryptoLib", package: "cryptolib-swift"),
        ]),
    ]
)

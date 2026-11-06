# Local toolchain configuration for scripts/build-ipa.ps1.
#
# Copy this file to BuildConfig.local.ps1 and point every entry at your own
# installation. BuildConfig.local.ps1 is ignored by Git and must never be
# committed.
#
# IosSdk is a directory; all other entries are executables.
@{
    IpaBuilderCli    = 'C:\path\to\WindowsIPABuilder\ipabuilder-cli.exe'
    IosSdk           = 'C:\path\to\sdks\iPhoneOS.sdk'
    Ldid             = 'C:\path\to\tools\ldid.exe'
    Swiftc           = 'C:\path\to\Swift\Toolchains\<version>\usr\bin\swiftc.exe'
    Clang            = 'C:\path\to\LLVM\bin\clang.exe'

    # Optional persistent module cache for the builder. Remove the key to use
    # the builder default.
    SwiftModuleCache = 'C:\path\to\swift-module-cache'
}

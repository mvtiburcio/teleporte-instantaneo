import CoreMediaIO
import Foundation

let providerSource = CameraProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)
CFRunLoopRun()

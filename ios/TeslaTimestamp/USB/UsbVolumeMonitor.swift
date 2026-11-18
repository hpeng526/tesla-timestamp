import Foundation

/// Detects mounted external / removable storage (e.g. USB-C or Lightning OTG Tesla drive)
/// using public Foundation volume APIs and active security-scoped source URLs.
public enum UsbVolumeMonitor {

    public static func attachedVolumeNames(activeSourceURL: URL? = nil) -> [String] {
        var names: [String] = []

        // 1. Check active security-scoped URL first (on iOS, external USB drives mount under LiveFiles
        //    and expose volumeIsRemovable / volumeIsInternal once selected in Files).
        if let activeURL = activeSourceURL {
            if let label = externalVolumeLabel(for: activeURL), !names.contains(label) {
                names.append(label)
            }
        }

        // 2. Check mounted volumes visible to the process.
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeIsEjectableKey
        ]
        if let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) {
            for volumeURL in volumes {
                if let label = externalVolumeLabel(for: volumeURL), !names.contains(label) {
                    names.append(label)
                }
            }
        }

        return names
    }

    private static func externalVolumeLabel(for url: URL) -> String? {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeIsEjectableKey
        ]
        if let values = try? url.resourceValues(forKeys: keys) {
            let isExternal = (values.volumeIsRemovable == true)
                || (values.volumeIsEjectable == true)
                || (values.volumeIsInternal == false)
            if isExternal, let name = values.volumeName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return name
            }
        }

        // iOS mounts external USB thumb drives via LiveFiles (`/private/var/mobile/Library/LiveFiles/...`).
        let path = url.standardizedFileURL.path
        if path.contains("/LiveFiles/") {
            let components = path.split(separator: "/").map(String.init)
            if let idx = components.firstIndex(of: "LiveFiles"), idx + 1 < components.count {
                let mountFolder = components[idx + 1]
                return mountFolder.isEmpty ? "USB 存储设备" : mountFolder
            }
            return "USB 存储设备"
        }
        return nil
    }
}

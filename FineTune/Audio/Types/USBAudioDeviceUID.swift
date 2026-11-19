nonisolated enum USBAudioDeviceUID {
    static func locationIndependentUID(for uid: String) -> String? {
        let parts = uid.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 5, parts.first == "AppleUSBAudioEngine" else { return nil }
        let location = parts[parts.count - 2]
        guard location.utf8.count == 8, location.hasSuffix("0000"), UInt32(location, radix: 16) != nil else { return nil }
        return parts.dropLast(2).joined(separator: ":") + ":" + parts[parts.count - 1]
    }
}

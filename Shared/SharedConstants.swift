import Foundation

enum SharedConstants {
    static let appGroupID = "group.studio.seventwo.clusage"

    static var appGroupContainerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)!
    }

    static var widgetDataURL: URL {
        appGroupContainerURL.appendingPathComponent("widget-data.json")
    }
}

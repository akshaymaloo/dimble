import Foundation
import Testing
@testable import PelmetCore

struct HelperProtocolTests {
    let item = HostedItem(title: "separator", kind: .separator)

    @Test func eventsAreBoundToAuthenticatedSectionAndOwnedItems() {
        let event = HelperEvent.clicked(bundle: "hidden", title: item.title, rightButton: false, x: 10, y: 20)
        #expect(event.isAuthorized(peer: "hidden", items: [item]))
        #expect(!event.isAuthorized(peer: "alwaysHidden", items: [item]))
        #expect(!event.isAuthorized(peer: "hidden", items: []))
        #expect(!HelperEvent.ready(bundle: "hidden").isAuthorized(peer: "alwaysHidden", items: []))
        #expect(!HelperEvent.hosted(bundle: "hidden", title: "unknown").isAuthorized(peer: "hidden", items: [item]))
    }

    @Test func rejectsInvalidCoordinatesAndRemovalOfLockedItems() {
        var locked = item
        locked.removable = false
        let drag = HelperEvent.draggedOff(bundle: "hidden", title: item.title)
        #expect(drag.isAuthorized(peer: "hidden", items: [item]))
        #expect(!drag.isAuthorized(peer: "hidden", items: [locked]))
        let click = HelperEvent.clicked(bundle: "hidden", title: item.title, rightButton: false, x: .nan, y: 20)
        #expect(!click.isAuthorized(peer: "hidden", items: [item]))
    }

    @Test func syncRejectsDuplicateAndOversizedOrInvalidItems() {
        #expect(HelperCommand.sync([item]).isValid)
        #expect(HelperCommand.sync([]).isValid)
        #expect(!HelperCommand.sync([item, item]).isValid)
        var invalid = item
        invalid.length = -.infinity
        #expect(!HelperCommand.sync([invalid]).isValid)
        invalid = item
        invalid.alpha = 2
        #expect(!HelperCommand.sync([invalid]).isValid)
        invalid = item
        invalid.imagePNG = Data(count: 256 * 1024 + 1)
        #expect(!HelperCommand.sync([invalid]).isValid)
    }
}

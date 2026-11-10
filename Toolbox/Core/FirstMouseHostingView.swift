import Cocoa
import SwiftUI

/// The first click on the panel works right away (without having to "activate" the window first).
final class FirstMouseHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

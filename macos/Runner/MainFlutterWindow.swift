import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // Before the engine exists, so that no display link is ever timed
    // without it.
    FrameClockGuard.install()

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

/// Keeps Flutter's frame clock from being handed a period that is not one.
///
/// The macOS engine works a display's refresh period out of its CVDisplayLink
/// as `timeValue / timeScale` and never checks the answer. A display that has
/// gone away — the Sidecar iPad, when the Mac goes to sleep — reports 0 / 0,
/// and the NaN that makes is used to schedule the next frame: the frame is
/// queued for a moment that never arrives, every later frame waits behind it,
/// and the window never draws again however visible it becomes. The app keeps
/// taking clicks and answering them; none of it reaches the screen.
///
/// 0 is what the engine itself uses for "no display to time against", and it
/// handles that with a plain timer. So anything that is not a real period is
/// handed over as 0.
///
/// This stands in front of a private method of the engine's. If a later
/// Flutter renames it there is nothing to stand in front of, and nothing is
/// changed.
enum FrameClockGuard {
  /// Where the engine's own answer is kept once the guard is in front of it.
  static let engineSelector = NSSelectorFromString("codora_engineNominalOutputRefreshPeriod")
  private static let selector = NSSelectorFromString("nominalOutputRefreshPeriod")

  static func install() {
    guard let displayLink = NSClassFromString("_FlutterDisplayLink"),
          let method = class_getInstanceMethod(displayLink, selector),
          class_addMethod(
            displayLink, engineSelector,
            method_getImplementation(method), method_getTypeEncoding(method))
    else { return }

    typealias Getter = @convention(c) (AnyObject, Selector) -> CFTimeInterval
    let guarded: @convention(block) (AnyObject) -> CFTimeInterval = { link in
      // Looked up on every call rather than captured, so the engine's answer
      // is always the one currently filed under [engineSelector].
      let engine = unsafeBitCast(
        class_getMethodImplementation(object_getClass(link), engineSelector),
        to: Getter.self)
      return usable(engine(link, engineSelector))
    }
    method_setImplementation(
      method, imp_implementationWithBlock(unsafeBitCast(guarded, to: AnyObject.self)))
  }

  /// A period a frame can be scheduled by: the engine's own when it is one,
  /// and otherwise the 0 it treats as "no display".
  static func usable(_ period: CFTimeInterval) -> CFTimeInterval {
    period.isFinite && period > 0 ? period : 0
  }
}

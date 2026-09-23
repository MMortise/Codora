import Cocoa
import FlutterMacOS
import XCTest

@testable import codora

/// The guard in front of the engine's frame clock, tried on the engine's own
/// display link rather than on a stand-in: what matters is that the class it
/// patches is the one the engine times frames with.
class FrameClockGuardTests: XCTestCase {
  typealias Getter = @convention(c) (AnyObject, Selector) -> CFTimeInterval
  private let period = NSSelectorFromString("nominalOutputRefreshPeriod")

  private var link: AnyObject!
  private var engineAnswer: Method!
  private var engineOriginal: IMP!

  override func setUpWithError() throws {
    // The app this runs inside installed the guard as its window woke up.
    let displayLink = try XCTUnwrap(
      NSClassFromString("_FlutterDisplayLink"), "the engine's display link class")
    engineAnswer = try XCTUnwrap(
      class_getInstanceMethod(displayLink, FrameClockGuard.engineSelector),
      "the guard is standing in front of the engine")
    engineOriginal = method_getImplementation(engineAnswer)

    // A display link for a view in no window: the engine's own "no display".
    let factory = try XCTUnwrap(NSClassFromString("FlutterDisplayLink")) as AnyObject
    link = factory.perform(NSSelectorFromString("displayLinkWithView:"), with: NSView())
      .takeUnretainedValue()
  }

  override func tearDown() {
    method_setImplementation(engineAnswer, engineOriginal)
    _ = link?.perform(NSSelectorFromString("invalidate"))
    link = nil
  }

  /// Makes the engine's own answer [value], as a display that has gone away
  /// makes it 0 / 0.
  private func engineSays(_ value: CFTimeInterval) {
    let answer: @convention(block) (AnyObject) -> CFTimeInterval = { _ in value }
    method_setImplementation(
      engineAnswer, imp_implementationWithBlock(unsafeBitCast(answer, to: AnyObject.self)))
  }

  /// What the vsync waiter is handed when it asks.
  private func waiterGets() -> CFTimeInterval {
    let getter = unsafeBitCast(link.method(for: period), to: Getter.self)
    return getter(link, period)
  }

  func testNaNFromAVanishedDisplayBecomesTheEnginesNoDisplay() {
    // 0 / 0, which is what froze the window: a frame queued for a time that
    // never comes.
    engineSays(0.0 / 0.0)
    XCTAssertEqual(waiterGets(), 0)
  }

  func testInfinityIsNotAPeriodEither() {
    // timeValue over a timeScale of 0. Scheduled against, it lands a frame at
    // +inf, which is the same as never.
    engineSays(.infinity)
    XCTAssertEqual(waiterGets(), 0)
  }

  func testNegativeIsNotAPeriod() {
    engineSays(-1.0 / 60.0)
    XCTAssertEqual(waiterGets(), 0)
  }

  func testARealPeriodIsPassedOnUntouched() {
    engineSays(1.0 / 120.0)
    XCTAssertEqual(waiterGets(), 1.0 / 120.0)
  }

  func testTheEnginesOwnAnswerStillComesThrough() {
    // Unpatched: a view in no window has no display, and the engine says 0.
    XCTAssertEqual(waiterGets(), 0)
  }

  func testUsable() {
    XCTAssertEqual(FrameClockGuard.usable(.nan), 0)
    XCTAssertEqual(FrameClockGuard.usable(.infinity), 0)
    XCTAssertEqual(FrameClockGuard.usable(-.infinity), 0)
    XCTAssertEqual(FrameClockGuard.usable(0), 0)
    XCTAssertEqual(FrameClockGuard.usable(1.0 / 60.0), 1.0 / 60.0)
  }
}

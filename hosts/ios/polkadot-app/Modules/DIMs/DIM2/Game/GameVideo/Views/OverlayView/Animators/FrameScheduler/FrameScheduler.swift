import Foundation

/// A generic frame scheduler abstraction
protocol FrameScheduler: AnyObject {
    var isRunning: Bool { get }
    func start(handler: @escaping (_ timestamp: CFTimeInterval, _ targetTimestamp: CFTimeInterval) -> Void)
    func stop()
}

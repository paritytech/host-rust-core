import Foundation
import Operation_iOS

protocol ProceduralTattooRenderer {
    func render(input: ProceduralTattooInput, completion: @escaping (Data?) -> Void)
}

final class ProceduralTattooWebViewRenderer: ProceduralTattooRenderer {
    let poolSize: Int = 2

    let operationQueue = OperationQueue()

    var renderPool: Set<ProceduralTattooWebImageRenderer> = []
    let renderLock = NSLock()

    init() {
        operationQueue.maxConcurrentOperationCount = poolSize

        for _ in 0 ..< poolSize {
            renderPool.insert(ProceduralTattooWebImageRenderer())
        }
    }

    func dequeueRenderer() -> ProceduralTattooWebImageRenderer? {
        renderLock.lock()
        defer { renderLock.unlock() }
        return renderPool.popFirst()
    }

    func enqueueRenderer(_ renderer: ProceduralTattooWebImageRenderer) {
        renderLock.lock()
        renderPool.insert(renderer)
        renderLock.unlock()
    }

    func render(input: ProceduralTattooInput, completion: @escaping (Data?) -> Void) {
        var rendererRef: ProceduralTattooWebImageRenderer?
        let rendererRefLock = NSLock()

        let loadOperation = AsyncClosureOperation<Data?> { [weak self] resultHandler in
            guard let self else {
                resultHandler(.success(nil))
                return
            }
            guard let renderer = dequeueRenderer() else {
                resultHandler(.success(nil))
                return assertionFailure()
            }

            rendererRefLock.lock()
            rendererRef = renderer
            rendererRefLock.unlock()

            DispatchQueue.main.async {
                renderer.loadProceduralTattoo(input: input) { [weak self] image in
                    rendererRefLock.lock()
                    if let renderer = rendererRef {
                        rendererRef = nil
                        self?.enqueueRenderer(renderer)
                    }
                    rendererRefLock.unlock()

                    resultHandler(.success(image))
                }
            }
        } cancelationClosure: { [weak self] in
            guard let self else { return }
            rendererRefLock.lock()
            if let renderer = rendererRef {
                rendererRef = nil
                enqueueRenderer(renderer)
            }
            rendererRefLock.unlock()
        }

        execute(
            operation: loadOperation,
            inOperationQueue: operationQueue,
            runningCallbackIn: .main
        ) { result in
            switch result {
            case let .success(image):
                completion(image)
            case .failure:
                completion(nil)
            }
        }
    }
}

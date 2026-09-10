import Foundation
import UIKit
import PDFKit
import Operation_iOS

protocol StencilPDFGenerating {
    func generateStencilPDF(outputFileURL: URL) -> CompoundOperationWrapper<URL>
}

final class StencilPDFGenerator {
    enum StencilPDFGeneratorError: Error {
        case failedToLoadPDF
        case failedToLoadImage
    }

    struct PDFStencil {
        let image: UIImage
        /// Target physical size in millimetres
        let size: CGSize
    }

    // MARK: - Properties

    /// A4 Size in millimetres
    private let a4Size: CGSize = .init(width: 210, height: 297)

    // High res DPI for accurate stencil is in range of 300 - 600
    private let dpi: Double = 300

    private let mmPerInch: CGFloat = 25.4

    /// Vertical spacing between stencils in millimetres
    private let verticalSpacing: CGFloat = 20

    private let stencilSizes: [CGSize] = [
        CGSize(width: 50, height: 50),
        CGSize(width: 37, height: 37),
        CGSize(width: 25, height: 25)
    ]

    private let imageProvider: TattooImageProviding
    private let fileManager: FileManager

    // MARK: - Init

    init(
        imageProvider: TattooImageProviding,
        fileManager: FileManager = .default
    ) {
        self.imageProvider = imageProvider
        self.fileManager = fileManager
    }
}

// MARK: - StencilPDFGenerationProtocol

extension StencilPDFGenerator: StencilPDFGenerating {
    func generateStencilPDF(outputFileURL: URL) -> CompoundOperationWrapper<URL> {
        // Return cached
        if fileManager.fileExists(atPath: outputFileURL.path) {
            let operation = ClosureOperation { outputFileURL }
            return CompoundOperationWrapper(targetOperation: operation)
        }

        let imageLoadingWrapper = imageProvider.provideImage()

        let generatePDFOperation = ClosureOperation { [weak self] in
            guard let self else {
                throw BaseOperationError.unexpectedDependentResult
            }

            guard let templateURL = Bundle.main.url(
                forResource: "tattoo-stencil-template",
                withExtension: "pdf"
            ) else {
                throw StencilPDFGeneratorError.failedToLoadPDF
            }

            guard let image = try imageLoadingWrapper.targetOperation.extractNoCancellableResultData() else {
                throw StencilPDFGeneratorError.failedToLoadImage
            }

            // TODO: Its better to generate 3 different size images
            let stencils: [PDFStencil] = stencilSizes.map { PDFStencil(image: image, size: $0) }

            try ensureParentDirectoryExists(for: outputFileURL)

            try overlayStencilsOnFirstPage(
                templateURL: templateURL,
                outputURL: outputFileURL,
                stencils: stencils,
                targetDPI: dpi
            )
        }
        generatePDFOperation.addDependency(imageLoadingWrapper.targetOperation)

        let returnResultOperation = ClosureOperation {
            _ = try generatePDFOperation.extractNoCancellableResultData()
            return outputFileURL
        }
        returnResultOperation.addDependency(generatePDFOperation)

        let dependencies = imageLoadingWrapper.allOperations + [generatePDFOperation]

        return CompoundOperationWrapper(
            targetOperation: returnResultOperation,
            dependencies: dependencies
        )
    }
}

// MARK: - Private Handlers

private extension StencilPDFGenerator {
    func ensureParentDirectoryExists(for fileURL: URL) throws {
        let parentDirectory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parentDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    func overlayStencilsOnFirstPage(
        templateURL: URL,
        outputURL: URL,
        stencils: [PDFStencil],
        targetDPI: Double
    ) throws {
        // Load PDF

        guard let templatePDF = PDFDocument(url: templateURL),
              templatePDF.pageCount > 0,
              let basePage = templatePDF.page(at: 0) else {
            throw StencilPDFGeneratorError.failedToLoadPDF
        }

        let originalBounds = basePage.bounds(for: .mediaBox)

        // Calculate DPI scaling

        let pointsPerMMX = originalBounds.width / a4Size.width
        let pointsPerMMY = originalBounds.height / a4Size.height
        let avgPointsPerMM = (pointsPerMMX + pointsPerMMY) / 2
        let inferredDPI = avgPointsPerMM * mmPerInch
        let dpiScale = targetDPI / inferredDPI

        // Calculate target page size

        let targetPageSize = CGSize(
            width: originalBounds.width * dpiScale,
            height: originalBounds.height * dpiScale
        )

        let targetPageRect = CGRect(origin: .zero, size: targetPageSize)

        // Calculate first stencil vertical location

        let spacingPoints = verticalSpacing * avgPointsPerMM * dpiScale
        let totalStencilsHeight = stencils.reduce(0) { result, stencil in
            result + stencil.size.height * avgPointsPerMM * dpiScale
        }
        let spacingsHeight = spacingPoints * CGFloat(max(stencils.count - 1, 0))
        let stencilsBoundingBoxHeight = totalStencilsHeight + spacingsHeight
        let stencilStartY = (targetPageSize.height - stencilsBoundingBoxHeight) / 2

        // Rendering

        try UIGraphicsPDFRenderer(bounds: targetPageRect).writePDF(to: outputURL) { context in
            for pageIndex in 0 ..< templatePDF.pageCount {
                context.beginPage()
                guard let page = templatePDF.page(at: pageIndex),
                      let cgContext = UIGraphicsGetCurrentContext() else {
                    continue
                }

                drawPageContent(
                    from: page,
                    into: cgContext,
                    scale: dpiScale,
                    canvasSize: targetPageSize
                )

                if pageIndex == 0 {
                    drawStencils(
                        stencils,
                        canvasSize: targetPageSize,
                        startY: stencilStartY,
                        pointsPerMM: avgPointsPerMM,
                        scale: dpiScale,
                        spacingPoints: spacingPoints
                    )
                }
            }
        }
    }
}

// MARK: - Draw helpers

private extension StencilPDFGenerator {
    func drawPageContent(
        from page: PDFPage,
        into context: CGContext,
        scale: CGFloat,
        canvasSize: CGSize
    ) {
        context.saveGState()
        context.translateBy(x: 0, y: canvasSize.height)
        context.scaleBy(x: 1.0, y: -1.0)
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
    }

    func drawStencils(
        _ stencils: [PDFStencil],
        canvasSize: CGSize,
        startY: CGFloat,
        pointsPerMM: CGFloat,
        scale: CGFloat,
        spacingPoints: CGFloat
    ) {
        var yCursor = startY

        stencils.forEach {
            let stencilSize = CGSize(
                width: $0.size.width * pointsPerMM * scale,
                height: $0.size.height * pointsPerMM * scale
            )
            let xPosition = (canvasSize.width - stencilSize.width) / 2
            let rect = CGRect(origin: CGPoint(x: xPosition, y: yCursor), size: stencilSize)
            $0.image.draw(in: rect)
            yCursor += stencilSize.height + spacingPoints
        }
    }
}

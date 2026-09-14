import DesignSystem
import Operation_iOS
import Products
import SwiftUI
import UIKit
import UIKitExt

final class DebugSettingsWireframe: NSObject, DebugSettingsWireframeProtocol, WebPresentable {
    private let flowStateProvider: any SPAFlowStateProviding
    private weak var issueView: ControllerBackedProtocol?

    init(flowStateProvider: any SPAFlowStateProviding) {
        self.flowStateProvider = flowStateProvider
    }

    func saveIssueLogs(_ archive: URL, from view: ControllerBackedProtocol?) {
        issueView = view
        let picker = UIDocumentPickerViewController(forExporting: [archive], asCopy: true)
        picker.delegate = self
        view?.controller.present(picker, animated: true)
    }

    func showProducts(from view: ControllerBackedProtocol?) {
        let factory = ProductRepositoryFactory()

        let viewModel = DebugProductsViewModel(
            productRepository: factory.createRepository(),
            chatRepositoryFactory: ChatRepositoryFactory()
        )

        let productsView = DebugProductsListView(viewModel: viewModel)
        let hostingController = UIHostingController(rootView: productsView)

        view?.controller.navigationController?.pushViewController(hostingController, animated: true)
    }

    func showThemeSelection(from view: ControllerBackedProtocol?) {
        let themeView = DebugThemeSelectionView(
            themeManager: ThemeManager.shared,
            typographyManager: TypographyManager.shared
        )
        let hostingController = UIHostingController(rootView: themeView)
        hostingController.title = "Theme Selection"

        view?.controller.navigationController?.pushViewController(hostingController, animated: true)
    }

    func showTrUAPIPlayground(from view: ControllerBackedProtocol?) {
        #if DEBUG
            guard let playgroundView = TrUAPIPlaygroundViewFactory.createView(
                flowStateProvider: flowStateProvider
            ) else {
                return
            }

            let navigationController = AppNavigationController(
                rootViewController: playgroundView.controller
            )
            navigationController.modalPresentationStyle = .fullScreen

            view?.controller.present(navigationController, animated: true)
        #endif
    }

    func showDotNsBrowser(from view: ControllerBackedProtocol?) {
        let alert = UIAlertController(
            title: "Open SPA",
            message: "Enter a dotns name to open",
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = "browse.dot"
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open", style: .default) { [weak view, weak self] _ in
            guard
                let input = alert.textFields?.first?.text,
                let self
            else {
                return
            }

            let flowState = flowStateProvider.flowState()

            Task {
                guard
                    let productHost = try? await flowState.hostProvider.resolveHost(rawString: input),
                    let spaView = SPAViewFactory.createView(
                        page: ProductPage(host: productHost),
                        flowState: flowState
                    )
                else {
                    return
                }

                await MainActor.run {
                    view?.controller.navigationController?.pushViewController(
                        spaView.controller,
                        animated: true
                    )
                }
            }
        })

        view?.controller.present(alert, animated: true)
    }
}

extension DebugSettingsWireframe: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let view = issueView, let archive = urls.first else {
            return
        }
        issueView = nil

        controller.dismiss(animated: true) { [weak self, weak view] in
            guard let self, let view, let url = issueURL(archiveName: archive.lastPathComponent) else {
                return
            }
            showWeb(url: url, from: view, style: .init(mode: .modal(.fullScreen)))
        }
    }

    func documentPickerWasCancelled(_: UIDocumentPickerViewController) {
        issueView = nil
    }
}

private extension DebugSettingsWireframe {
    func issueURL(archiveName: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/paritytech/platform-issues/issues/new"
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "title", value: "iOS bug report"),
            URLQueryItem(name: "where", value: "Polkadot Mobile (iOS)"),
            URLQueryItem(name: "details", value: String(localized: .debugIssueDetails(
                Bundle.main.appVersion ?? "?",
                Bundle.main.appBuild ?? "?",
                UIDevice.current.systemVersion,
                UIDevice.current.model,
                archiveName
            )))
        ]
        return components.url
    }
}

import Foundation

@MainActor
enum GameAlarmSettingsViewFactory {
    static func createView(model: GameAlarmSettingsModel) -> GameAlarmSettingsViewProtocol {
        let interactor = GameAlarmSettingsInteractor()
        let presenter = GameAlarmSettingsPresenter(model: model, interactor: interactor)
        let view = GameAlarmSettingsViewController(title: nil, message: nil, preferredStyle: .actionSheet)

        presenter.view = view
        interactor.presenter = presenter
        view.presenter = presenter

        presenter.setup()

        return view
    }
}

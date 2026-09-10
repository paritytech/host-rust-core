import Coinage

final class PaymentsSupport {
    let coinageService: CoinageServicing

    var externalPaymentService: ExternalPaymentServicing {
        coinageService.externalPaymentService
    }

    init(coinageService: CoinageServicing) {
        self.coinageService = coinageService
    }
}

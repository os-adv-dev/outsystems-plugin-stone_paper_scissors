import UIKit

@objc(RPSGamePlugin)
class RPSGamePlugin: CDVPlugin {

    @objc(showGameScreen:)
    func showGameScreen(command: CDVInvokedUrlCommand) {
        DispatchQueue.main.async {
            let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
            guard let vc = storyboard.instantiateViewController(withIdentifier: "RPSDetectionViewController") as? RPSDetectionViewController else {
                let result = CDVPluginResult(status: .error, messageAs: "Failed to load ViewController")
                self.commandDelegate.send(result, callbackId: command.callbackId)
                return
            }

            if let root = self.viewController {
                root.present(vc, animated: true) {
                    let result = CDVPluginResult(status: .ok)
                    self.commandDelegate.send(result, callbackId: command.callbackId)
                }
            }
        }
    }
}

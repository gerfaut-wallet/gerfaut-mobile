import Flutter
import UIKit

// The scene's comings and goings, which the app delegate no longer hears
// of with scenes: the cover of a secure window goes up before the system
// takes the switcher's picture, and comes off once the scene is back and
// the lock screen drawn.
class SceneDelegate: FlutterSceneDelegate {
  override func sceneWillResignActive(_ scene: UIScene) {
    WindowGuard.shared.cover(scene)
    super.sceneWillResignActive(scene)
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    WindowGuard.shared.cover(scene)
    // A dialog or a share sheet left up would sit over the lock screen
    // when the app is back, the wallets behind it: closed, as though
    // the user had cancelled it.
    if WindowGuard.shared.secure { Documents.shared.closeForLock() }
    super.sceneDidEnterBackground(scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    WindowGuard.shared.uncoverOnceDrawn(scene)
  }
}

import Flutter
import UIKit

// The scene's comings and goings, which the app delegate no longer hears
// of with scenes: the cover of a secure window goes up before the system
// takes the switcher's picture, and comes off once the scene is back.
class SceneDelegate: FlutterSceneDelegate {
  override func sceneWillResignActive(_ scene: UIScene) {
    WindowGuard.shared.cover(scene)
    super.sceneWillResignActive(scene)
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    WindowGuard.shared.cover(scene)
    super.sceneDidEnterBackground(scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    WindowGuard.shared.uncover(scene)
  }
}

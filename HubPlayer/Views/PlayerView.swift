import SwiftUI
import AVKit

struct PlayerView: View {
    @EnvironmentObject private var manager: PlayerManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            PlayerVC().environmentObject(manager)
            VStack {
                HStack {
                    Spacer()
                    Button {
                        manager.stop()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
    }
}

struct PlayerVC: UIViewControllerRepresentable {
    @EnvironmentObject private var manager: PlayerManager

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = manager.player
        vc.allowsPictureInPicturePlayback = true
        vc.videoGravity = .resizeAspect
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = manager.player
    }
}

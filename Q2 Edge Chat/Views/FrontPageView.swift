import SwiftUI

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.primary)
            .foregroundColor(.white)
            .cornerRadius(10)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
struct AccentButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(10)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct FrontPageView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                
                Text("Q2 Edge Chat")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Run AI models locally on your iPhone")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 40)
                
                Spacer()
                
                VStack(spacing:16){
                    NavigationLink("Browse Models") { ModelBrowserView() }
                        .buttonStyle(PrimaryButton())
                    
                    NavigationLink("Chat") { ChatWorkspaceView() }
                        .buttonStyle(AccentButton())
                }
                .padding(.horizontal, 40)
                
                Spacer()
            }
            .background(Color(.systemBackground))
            .ignoresSafeArea()
        }
    }
}

struct FrontPageView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            FrontPageView()
        }
        .preferredColorScheme(.light)

        NavigationStack {
            FrontPageView()
        }
        .preferredColorScheme(.dark)
    }
}

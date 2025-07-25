import SwiftUI

struct FrontPageView: View {
    var body: some View {
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

            VStack(spacing: 16) {
                NavigationLink(destination: ModelBrowserView()) {
                    Text("Browse Models")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.primary)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                NavigationLink(destination: ChatView()) {
                    Text("Chat")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea()
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

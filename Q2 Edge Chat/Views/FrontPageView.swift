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
                Button(action: {
                    // Navigate to Model Browser
                }) {
                    Text("Browse Models")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.primary)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                Button(action: {
                    // Navigate to Quick Chat
                }) {
                    Text("Quick Chat")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.primary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.primary, lineWidth: 2)
                        )
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .background(Color.white)
        .ignoresSafeArea()
    }
}

struct FrontPageView_Previews: PreviewProvider {
    static var previews: some View {
        FrontPageView()
    }
}

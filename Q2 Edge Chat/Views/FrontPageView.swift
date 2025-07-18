//
//  FrontPageView.swift
//  Q2 Edge Chat
//
//  Created by Michael Gathara on 7/18/25.
//


import SwiftUI

struct FrontPageView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color("AccentColor"), Color("AccentColorDark")]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                // App logo (add "AppLogo" asset to Assets.xcassets)
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)

                Text("Q2 Edge Chat")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Run AI models locally on your iPhone")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 40)

                Spacer()

                VStack(spacing: 16) {
                    Button(action: {
                        // Navigate to Model Browser here or something
                    }) {
                        Text("Browse Models")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .foregroundColor(Color("AccentColor"))
                            .cornerRadius(10)
                    }

                    Button(action: {
                        // Navigate to Quick Chat here and stuff
                    }) {
                        Text("Quick Chat")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white, lineWidth: 2)
                            )
                    }
                }
                .padding(.horizontal, 40)

                Spacer()
            }
        }
    }
}

struct FrontPageView_Previews: PreviewProvider {
    static var previews: some View {
        FrontPageView()
    }
}

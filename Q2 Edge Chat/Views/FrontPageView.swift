import SwiftUI
import Combine

struct ModernButton: ButtonStyle {
    let color: Color
    let textColor: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(textColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(color)
                    .shadow(color: color.opacity(0.3), radius: 8, x: 0, y: 4)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}


struct FrontPageView: View {
    @State private var localModels: [ManifestEntry] = []
    @State private var store: ManifestStore?
    @State private var cancellable: AnyCancellable?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header Section
                    VStack(spacing: 20) {
                        // App Logo/Icon
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 100, height: 100)
                            
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 40, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 20, x: 0, y: 10)
                        
                        VStack(spacing: 8) {
                            Text("Q2 Edge Chat")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            Text("AI-powered conversations on your device")
                                .font(.title3)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 40)
                    
                    // Status Cards
                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            StatusCard(
                                title: "100+",
                                subtitle: "Models",
                                icon: "brain.head.profile",
                                color: .blue
                            )
                            
                            StatusCard(
                                title: "Local",
                                subtitle: "Processing",
                                icon: "iphone",
                                color: .green
                            )
                        }
                        
                        HStack(spacing: 16) {
                            StatusCard(
                                title: "Private",
                                subtitle: "Secure",
                                icon: "lock.shield",
                                color: .orange
                            )
                            
                            StatusCard(
                                title: "Fast",
                                subtitle: "Response",
                                icon: "bolt",
                                color: .purple
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Main Action Buttons
                    VStack(spacing: 16) {
                        NavigationLink(destination: ChatWorkspaceView()) {
                            HStack {
                                Image(systemName: "message.fill")
                                    .font(.title3)
                                Text("Start Chatting")
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(ModernButton(color: .accentColor, textColor: .white))
                        
                        NavigationLink(destination: ModelBrowserView()) {
                            HStack {
                                Image(systemName: "brain.head.profile")
                                    .font(.title3)
                                Text("Browse Models")
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(ModernButton(color: Color(.systemGray5), textColor: .primary))
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer(minLength: 50)
                }
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.systemGray6).opacity(0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .onAppear {
            loadModels()
        }
    }
    
    private func loadModels() {
        Task {
            do {
                store = try ManifestStore()
                localModels = await store?.all() ?? []
                cancellable = store?.didChange
                    .receive(on: RunLoop.main)
                    .sink { _ in Task { localModels = await store?.all() ?? [] } }
            } catch {
                print("Failed to load models: \(error)")
            }
        }
    }
}

struct StatusCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
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

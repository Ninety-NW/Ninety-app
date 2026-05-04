//
//  OnboardingView.swift
//  Ninety
//
//  Created by Deimante Valunaite on 07/07/2024.
//

import SwiftUI

struct OnboardingView: View {
    @AppStorage("isBoarding") var isOnBoarding: Bool = true
    @AppStorage("hasSeenTour") var hasSeenTour: Bool = false
    @AppStorage("showGuidedTour") var showGuidedTour: Bool = false
    @AppStorage("appLanguage") private var appLanguage: String = AppLanguage.english.rawValue
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showTermsOfService = false
    @State private var showPrivacyPolicy = false

    var body: some View {
        if isOnBoarding {
            ZStack {
                HorizonBackground()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Logo — no glass variant: decorative image, not a navigation control
                    Image("Logo design")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 160)
                        .accessibilityLabel("Ninety logo".localized(for: appLanguage))
                        .cornerRadius(32)

                    VStack(spacing: 12) {
                        Text("Ninety".localized(for: appLanguage))
                            .font(.largeTitle.bold())

                        Text("Your next Smart Alarm".localized(for: appLanguage))
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 28)
                    .padding(.horizontal, 40)

                    Spacer()

                    VStack(spacing: 10) {
                        Button("Get Started".localized(for: appLanguage)) {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                isOnBoarding.toggle()
                            }
                            // Trigger guided tour on first install
                            if !hasSeenTour {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    hasSeenTour = true
                                    showGuidedTour = true
                                }
                            }
                        }
                        .buttonStyle(GlassButtonStyle.glassProminent)
                        .tint(Color.themeAccent(for: colorScheme))
                        .controlSize(.large)
                        .accessibilityHint("Opens the main sleep schedule".localized(for: appLanguage))

                        VStack(spacing: 2) {
                            Text("By continuing, you agree to Ninety's".localized(for: appLanguage))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                
                            HStack(spacing: 4) {
                                Button(action: {
                                    showTermsOfService = true
                                }) {
                                    Text("Terms of Service".localized(for: appLanguage))
                                        .bold()
                                        .foregroundStyle(.blue)
                                }
                                
                                Text("and".localized(for: appLanguage))
                                
                                Button(action: {
                                    showPrivacyPolicy = true
                                }) {
                                    Text("Privacy Policy.".localized(for: appLanguage))
                                        .bold()
                                        .foregroundStyle(.blue)
                                }
                            }
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        }
                        .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 32)
                }
            }
            .sheet(isPresented: $showTermsOfService) {
                if let url = URL(string: "https://example.com/terms") {
                    SafariView(url: url)
                        .ignoresSafeArea()
                }
            }
            .sheet(isPresented: $showPrivacyPolicy) {
                if let url = URL(string: "https://example.com/privacy") {
                    SafariView(url: url)
                        .ignoresSafeArea()
                }
            }
        } else {
            ScheduleView()
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(ScheduleViewModel())
        .environmentObject(TourFrameStore())
}

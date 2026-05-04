//
//  SettingsView.swift
//  Ninety
//
//  Created by Deimante Valunaite on 08/07/2024.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var settingsViewModel = SettingsViewModel()
    @State private var showingAbout = false
    @AppStorage("appLanguage") private var appLanguage: String = AppLanguage.english.rawValue
    @AppStorage("showGuidedTour") private var showGuidedTour: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    private var accent: Color { .themeAccent(for: colorScheme) }
    
    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 24) {
                VStack(spacing: 32) {
                    
                    // Smart Alarm Section
                    settingsSection("SMART ALARM".localized(for: appLanguage)) {
                        VStack(spacing: 0) {
                            
                            Divider().padding(.leading, 44)
                            
                            settingsToggleRow(icon: "water.waves", color: .indigo, title: "Haptic Pre-Alarm".localized(for: appLanguage), isOn: $settingsViewModel.hapticAlarm)
                            
                            Divider()
                            
                            settingsToggleRow(icon: "hand.tap.fill", color: .orange, title: "Haptic Feedback".localized(for: appLanguage), isOn: $settingsViewModel.hapticFeedbackEnabled)
                        }
                    }
                    
                    // Appearance Section
                    settingsSection("APPEARANCE".localized(for: appLanguage)) {
                        VStack(spacing: 0) {
                            Divider().padding(.leading, 44)
                            
                            // Visual Previews
                            HStack(spacing: 40) {
                                Spacer()
                                // Light Preview
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        settingsViewModel.selectedTheme = .light
                                    }
                                } label: {
                                    ThemePreviewView(theme: .light, isSelected: settingsViewModel.selectedTheme == .light)
                                }
                                .buttonStyle(.plain)
                                
                                // Night Preview
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        settingsViewModel.selectedTheme = .night
                                    }
                                } label: {
                                    ThemePreviewView(theme: .night, isSelected: settingsViewModel.selectedTheme == .night)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                            }
                            .padding(.vertical, 24)
                            // .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))

                            Divider()

                            // Automatic Toggle
                            settingsToggleRow(
                                icon: "circle.lefthalf.filled",
                                color: .primary,
                                title: "Automatic".localized(for: appLanguage),
                                isOn: Binding(
                                    get: { settingsViewModel.selectedTheme == .system },
                                    set: { isOn in
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            settingsViewModel.selectedTheme = isOn ? .system : .light
                                        }
                                    }
                                )
                            )
                        }
                    }
                    // Permissions Section
//                    settingsSection("PERMISSIONS".localized(for: appLanguage)) {
//                        VStack(spacing: 0) {
//                            settingsToggleRow(icon: "bell.badge.fill", color: .red, title: "Notifications".localized(for: appLanguage), isOn: $settingsViewModel.isNotificationsEnabled)
//                            
//                            Divider()
//                            
//                            settingsToggleRow(icon: "heart.text.square.fill", color: .pink, title: "Apple Health".localized(for: appLanguage), isOn: $settingsViewModel.saveToHealthKit)
//                        }
//                    }
                    
                    // General Section
                    settingsSection("GENERAL".localized(for: appLanguage)) {
                        VStack(spacing: 0) {
                            settingsRow(icon: "globe", color: accent, title: "Language".localized(for: appLanguage)) {
                                Picker("Language", selection: $appLanguage) {
                                    ForEach(AppLanguage.allCases) { lang in
                                        Text(lang.displayName).tag(lang.rawValue)
                                    }
                                }
                                .labelsHidden()
                                .tint(.secondary)
                            }
                            
                            Divider()
                            
                            Button {
                                showGuidedTour = true
                                dismiss()
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "questionmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.purple)
                                        .frame(width: 24)
                                    Text("Replay Tour".localized(for: appLanguage))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            Divider()
                            
                            Button {
                                showingAbout = true
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(accent)
                                        .frame(width: 24)
                                    Text("About Ninety".localized(for: appLanguage))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
        }
        // Disable HorizonBackground for the Settings View
        // .background {
        //     HorizonBackground(isActive: false)
        //         .ignoresSafeArea()
        // }
        .navigationTitle("Settings".localized(for: appLanguage))
        .navigationBarTitleDisplayMode(.large)
        .scrollContentBackground(.hidden)
        .containerBackground(.clear, for: .navigation)
        .onAppear {
            settingsViewModel.checkNotificationStatus()
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
    }
    
    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.caption.bold())
                .tracking(2)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
            
            content()
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        }
    }
    
    @ViewBuilder
    private func settingsRow<Content: View>(icon: String, color: Color, title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            content()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
    
    @ViewBuilder
    private func settingsToggleRow(icon: String, color: Color, title: String, isOn: Binding<Bool>) -> some View {
        settingsRow(icon: icon, color: color, title: title) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(accent)
        }
    }
}


// MARK: - About View

private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage: String = AppLanguage.english.rawValue
    
    @State private var showingTerms = false
    @State private var showingPrivacy = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 48) {
                    // branding
                    VStack(spacing: 20) {
                        Image("Logo design")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 160)
                            .accessibilityLabel("Ninety logo".localized(for: appLanguage))
                            .cornerRadius(32)

                        VStack(spacing: 6) {
                            Text("Ninety".localized(for: appLanguage))
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                            Text("\("Version".localized(for: appLanguage)) \(appVersion)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 60)

                    // copy
                    VStack(spacing: 0) {
                        Text("Smart sleep tracking powered by on-device ML. Your data stays on your devices.".localized(for: appLanguage))
                            .font(.body)
                            .lineSpacing(8)
                            .foregroundStyle(.primary.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(32)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32))
                    }
                    .padding(.horizontal, 24)

                    // Legal links
                    HStack(spacing: 16) {
                        Button("Terms of Service".localized(for: appLanguage)) {
                            showingTerms = true
                        }
                        
                        Text("•")
                            .foregroundColor(.secondary.opacity(0.5))

                        Button("Privacy Policy".localized(for: appLanguage)) {
                            showingPrivacy = true
                        }
                    }
                    .font(.footnote.bold())
                    .foregroundColor(.secondary)
                    .padding(.top, 8)

                    Spacer(minLength: 40)
                }
            }
            .background {
                HorizonBackground(isActive: false)
                    .ignoresSafeArea()
            }
            .navigationTitle("About Ninety".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done".localized(for: appLanguage)) { dismiss() }
                }
            }
            .sheet(isPresented: $showingTerms) {
                if let url = URL(string: "https://example.com/terms") {
                    SafariView(url: url)
                        .ignoresSafeArea()
                }
            }
            .sheet(isPresented: $showingPrivacy) {
                if let url = URL(string: "https://example.com/privacy") {
                    SafariView(url: url)
                        .ignoresSafeArea()
                }
            }
        }
    }
}

private struct ThemePreviewView: View {
    let theme: AppTheme
    let isSelected: Bool
    @AppStorage("appLanguage") private var appLanguage: String = AppLanguage.english.rawValue

    private var previewBackground: some ShapeStyle {
        switch theme {
        case .light:
            return AnyShapeStyle(Color.white)
        case .night:
            return AnyShapeStyle(Color.black.opacity(0.92))
        case .system:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.white, Color.black.opacity(0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var accentColor: Color {
        switch theme {
        case .light:
            return .orange
        case .night:
            return .blue
        case .system:
            return .purple
        }
    }

    private var titleColor: Color {
        switch theme {
        case .light:
            return .black.opacity(0.8)
        case .night:
            return .white.opacity(0.9)
        case .system:
            return .primary
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(previewBackground)
                .overlay {
                    VStack(alignment: .leading, spacing: 8) {
                        Capsule()
                            .fill(accentColor.opacity(0.9))
                            .frame(width: 42, height: 8)

                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accentColor.opacity(theme == .light ? 0.18 : 0.28))
                            .frame(height: 26)

                        Spacer()

                        HStack(spacing: 6) {
                            Circle()
                                .fill(accentColor.opacity(0.85))
                                .frame(width: 8, height: 8)
                            Capsule()
                                .fill(titleColor.opacity(0.2))
                                .frame(width: 30, height: 8)
                        }
                    }
                    .padding(14)
                }
                .frame(width: 104, height: 148)
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, .blue)
                            .padding(10)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                }
                .shadow(color: .black.opacity(theme == .light ? 0.08 : 0.22), radius: 12, y: 6)

            Text(theme.rawValue.capitalized.localized(for: appLanguage))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
    }
}


#Preview {
    SettingsView()
}

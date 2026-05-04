import SwiftUI
import AudioToolbox

struct SoundPickerView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @AppStorage("appLanguage") private var appLanguage: String = AppLanguage.english.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    private var accent: Color { .themeAccent(for: colorScheme) }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 0) {
                    ForEach(AlarmSound.allSounds) { sound in
                        Button {
                            selectSound(sound)
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "music.note")
                                    .font(.title3)
                                    .foregroundStyle(viewModel.selectedSoundID == sound.id ? accent : .secondary)
                                    .frame(width: 24)
                                
                                Text(sound.name.localized(for: appLanguage))
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                if viewModel.selectedSoundID == sound.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(accent)
                                        .font(.system(size: 14, weight: .bold))
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        if sound.id != AlarmSound.allSounds.last?.id {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
                .padding()
            }
        }
        .background {
            HorizonBackground(isActive: false)
                .ignoresSafeArea()
        }
        .navigationTitle("Sound".localized(for: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func selectSound(_ sound: AlarmSound) {
        viewModel.selectedSoundID = sound.id
        // Play preview
        AudioServicesPlaySystemSound(SystemSoundID(sound.id))
    }
}

#Preview {
    NavigationStack {
        SoundPickerView(viewModel: SettingsViewModel())
    }
}

import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        TabView {
            GeneralSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            IndexingSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Indexing", systemImage: "magnifyingglass")
                }

            AppearanceSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
        }
        .frame(width: 480, height: 360)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Hotkey") {
                HStack {
                    Text("Activation Hotkey")
                    Spacer()
                    HotkeyRecorderView(
                        keyCode: $viewModel.hotkeyKeyCode,
                        modifiers: $viewModel.hotkeyModifiers
                    )
                }

                if let error = viewModel.hotkeyError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("Startup") {
                Toggle("Launch at Login", isOn: $viewModel.launchAtLogin)
                Toggle("Show Menu Bar Icon", isOn: $viewModel.showMenuBarIcon)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Indexing Settings

struct IndexingSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Indexed Directories") {
                List {
                    ForEach(viewModel.indexingPaths, id: \.self) { path in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(role: .destructive) {
                                viewModel.removePath(path)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .frame(height: 120)

                Button("Add Directory...") {
                    viewModel.addDirectory()
                }
            }

            Section("Limits") {
                HStack {
                    Text("Max Indexed Files")
                    Spacer()
                    TextField("", value: $viewModel.maxIndexedFiles, format: .number)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                HStack {
                    Button("Re-index Now") {
                        viewModel.triggerReIndex()
                    }

                    if viewModel.isReIndexing {
                        ProgressView()
                            .controlSize(.small)
                        Text("Indexing...")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Color Scheme") {
                Picker("Appearance", selection: $viewModel.appearanceMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section("Command Bar") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Width")
                        Spacer()
                        Text("\(Int(viewModel.commandBarWidth))pt")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewModel.commandBarWidth, in: 500...900, step: 10)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

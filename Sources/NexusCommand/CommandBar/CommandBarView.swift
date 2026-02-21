import SwiftUI

struct CommandBarView: View {
    @Bindable var viewModel: CommandBarViewModel
    let shaderService: ShaderService
    var onDismiss: () -> Void

    @Namespace private var resultNamespace
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            searchField

            Divider()
                .opacity(viewModel.results.isEmpty ? 0 : 1)

            // Results list
            if viewModel.isLoading && viewModel.results.isEmpty {
                loadingView
            } else if !viewModel.results.isEmpty {
                resultsList
            } else if let error = viewModel.errorMessage {
                errorRow(message: error)
            } else if !viewModel.query.isEmpty {
                emptyState
            }
        }
        .frame(width: 680)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onAppear {
            isTextFieldFocused = true
            viewModel.onAppear()
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.moveSelectionDown()
            return .handled
        }
        .onKeyPress(.upArrow) {
            viewModel.moveSelectionUp()
            return .handled
        }
        .onKeyPress(.return) {
            viewModel.executeSelected()
            if viewModel.shouldDismissAfterExecution {
                onDismiss()
            }
            return .handled
        }
        .onKeyPress(.tab) {
            // Reserved for future autocomplete
            return .handled
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)

            TextField("Type a command...", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isTextFieldFocused)
                .onSubmit {
                    viewModel.executeSelected()
                    if viewModel.shouldDismissAfterExecution {
                        onDismiss()
                    }
                }

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, item in
                        ResultRowView(
                            item: item,
                            isSelected: index == viewModel.selectedIndex
                        )
                        .id(item.id)
                        .matchedGeometryEffect(id: item.id, in: resultNamespace)
                        .onTapGesture {
                            viewModel.selectedIndex = index
                            viewModel.executeSelected()
                            if viewModel.shouldDismissAfterExecution {
                                onDismiss()
                            }
                        }
                        .phaseAnimator([false, true], trigger: item.id) { content, phase in
                            content
                                .opacity(phase ? 1 : 0)
                                .offset(y: phase ? 0 : 8)
                        } animation: { _ in
                            .easeOut(duration: 0.2)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 340)
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                if let selectedItem = viewModel.results[safe: newIndex] {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(selectedItem.id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - States

    private var loadingView: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { timeline in
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Searching...")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text("No results found")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func errorRow(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.orange.opacity(0.1))
    }
}

// MARK: - Result Row

struct ResultRowView: View {
    let item: SearchResultItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.title3)
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isSelected {
                Text("⏎")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Safe Array Access

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

import SwiftUI

/// 通用筛选面板。完全由图源的 `filterFields` 驱动，不含任何图源专属代码。
struct FilterSheet: View {
    let source: any WallpaperSource
    let hasCredential: Bool
    let onApply: (FilterState) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var state: FilterState

    init(source: any WallpaperSource, current: FilterState, hasCredential: Bool,
         onApply: @escaping (FilterState) -> Void) {
        self.source = source
        self.hasCredential = hasCredential
        self.onApply = onApply
        _state = State(initialValue: current.filled(with: source.filterFields))
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(visibleFields) { field in
                    FieldSection(field: field, state: $state, hasCredential: hasCredential)
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("恢复默认") { state = source.defaultFilters }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        onApply(state)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    /// 根据其他字段的取值，决定哪些字段需要显示。
    private var visibleFields: [FilterField] {
        source.filterFields.filter { field in
            guard let condition = field.visibleWhen else { return true }
            return state.choice(condition.fieldID) == condition.equals
        }
    }

    /// 多选字段要满足最少选择数量。
    private var isValid: Bool {
        visibleFields.allSatisfy { field in
            guard case .multi(_, let minimum) = field.kind else { return true }
            return (state.multi(field.id)?.count ?? 0) >= minimum
        }
    }
}

/// 单个筛选字段对应的一段表单。
private struct FieldSection: View {
    let field: FilterField
    @Binding var state: FilterState
    let hasCredential: Bool

    var body: some View {
        Section {
            switch field.kind {
            case .choice(let options):
                Picker(field.title, selection: choiceBinding) {
                    ForEach(options) { option in
                        Text(label(for: option)).tag(option.id)
                    }
                }
                .pickerStyle(.menu)

            case .multi(let options, _):
                ForEach(options) { option in
                    Toggle(label(for: option), isOn: multiBinding(option.id))
                        .disabled(option.requiresKey && !hasCredential)
                }

            case .toggle:
                Toggle(field.title, isOn: flagBinding)

            case .text(let prompt, let keyboard):
                TextField(prompt, text: textBinding)
                    .keyboardType(keyboard == .resolution ? .numbersAndPunctuation : .default)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } header: {
            // 单选与文本字段的标题已在控件上，仅多选需要分组标题。
            if case .multi = field.kind { Text(field.title) }
        } footer: {
            if let footer = field.footer { Text(footer) }
        }
    }

    private func label(for option: FilterField.Option) -> String {
        option.requiresKey && !hasCredential ? "\(option.title)（需密钥）" : option.title
    }

    private var choiceBinding: Binding<String> {
        Binding(
            get: { state.choice(field.id) ?? "" },
            set: { state.values[field.id] = .choice($0) }
        )
    }

    private func multiBinding(_ optionID: String) -> Binding<Bool> {
        Binding(
            get: { state.multi(field.id)?.contains(optionID) ?? false },
            set: { isOn in
                var set = state.multi(field.id) ?? []
                if isOn { set.insert(optionID) } else { set.remove(optionID) }
                state.values[field.id] = .multi(set)
            }
        )
    }

    private var flagBinding: Binding<Bool> {
        Binding(
            get: { state.flag(field.id) ?? false },
            set: { state.values[field.id] = .flag($0) }
        )
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { state.text(field.id) ?? "" },
            set: { state.values[field.id] = .text($0) }
        )
    }
}

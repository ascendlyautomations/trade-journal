import Combine
import SwiftUI
import UIKit

/// Shared keyboard dismissal helpers for pad keyboards (no Return / Done key).
///
/// - Tap outside: ``View/experienceKeyboardDismissOnTapOutside()``
/// - Form focus + lifecycle: ``View/experienceFormKeyboard(focus:releaseOnDisappear:)`` in ``ExperienceFormKeyboard.swift``
/// - Done toolbar: ``View/experienceKeyboardDoneToolbar()`` (calls ``ExperienceKeyboard/dismissFormKeyboard()``)
enum ExperienceKeyboard {
    /// Resigns first responder only. Prefer ``dismissFormKeyboard()`` when clearing ``FocusState``.
    @MainActor
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

// MARK: - Policy

enum ExperienceKeyboardFieldDonePolicy: Equatable {
  case automatic
  case requiresDone
  case excludesDone
}

struct ExperienceKeyboardFieldFocusDeclaration: Equatable {
  var isFocused: Bool
  var kind: ExperienceKeyboardFieldDonePolicy
}

private struct ExperienceKeyboardFieldFocusPreferenceKey: PreferenceKey {
  static var defaultValue: [ExperienceKeyboardFieldFocusDeclaration] = []

  static func reduce(
    value: inout [ExperienceKeyboardFieldFocusDeclaration],
    nextValue: () -> [ExperienceKeyboardFieldFocusDeclaration]
  ) {
    value.append(contentsOf: nextValue())
  }
}

enum ExperienceKeyboardDonePolicy {
  /// Whether the shared **Done** control should appear for the current first responder.
  static func showsDoneForFirstResponder() -> Bool {
    switch firstResponderInputContext() {
    case .none, .textField:
      return false
    case .textView:
      return true
    case .decimalPad:
      return true
    }
  }

  private enum FirstResponderInputContext {
    case none
    case textField
    case textView
    case decimalPad
  }

  private static func firstResponderInputContext() -> FirstResponderInputContext {
    guard let responder = UIResponder.tradeTraxsCurrentFirstResponder else {
      return .none
    }
    if responder is UITextView {
      return .textView
    }
    if let field = responder as? UITextField {
      return field.keyboardType.showsExperienceDoneToolbar ? .decimalPad : .textField
    }
    if let view = responder as? UIView {
      if view is UITextView || view.tradeTraxsContainsFirstTextView() {
        return .textView
      }
      if let hostedPad = view.tradeTraxsHostedDecimalPadKeyboardType() {
        return hostedPad ? .decimalPad : .textField
      }
    }
    return .none
  }

  static func resolvedShowsDone(
    suppressed: Bool,
    focusedDeclarations: [ExperienceKeyboardFieldFocusDeclaration],
    signedDecimalActive: Bool
  ) -> Bool {
    guard !suppressed else { return false }

    if let focused = focusedDeclarations.last(where: { $0.isFocused }) {
      switch focused.kind {
      case .excludesDone:
        return false
      case .requiresDone:
        return true
      case .automatic:
        break
      }
    }

    if signedDecimalActive { return true }
    return showsDoneForFirstResponder()
  }
}

private extension UIKeyboardType {
  var showsExperienceDoneToolbar: Bool {
    switch self {
    case .numberPad, .decimalPad, .phonePad, .asciiCapableNumberPad:
      return true
    default:
      return false
    }
  }
}

private extension UIView {
  func tradeTraxsContainsFirstTextView() -> Bool {
    if self is UITextView { return true }
    for subview in subviews where subview.tradeTraxsContainsFirstTextView() {
      return true
    }
    return false
  }

  /// Returns whether a descendant `UITextField` uses a pad keyboard; `nil` when none found.
  func tradeTraxsHostedDecimalPadKeyboardType() -> Bool? {
    if let field = self as? UITextField {
      return field.keyboardType.showsExperienceDoneToolbar
    }
    for subview in subviews {
      if let hosted = subview.tradeTraxsHostedDecimalPadKeyboardType() {
        return hosted
      }
    }
    return nil
  }
}

// MARK: - Accessory model (sign toggle + visibility)

@MainActor
private final class ExperienceKeyboardAccessoryModel: ObservableObject {
  @Published private(set) var showsAccessoryBar = false

  var signedDecimalActive = false {
    didSet { recalculate() }
  }

  var onSignedDecimalToggle: (() -> Void)?

  private var focusedDeclarations: [ExperienceKeyboardFieldFocusDeclaration] = []
  private var suppressed = false

  func setSuppressed(_ suppressed: Bool) {
    self.suppressed = suppressed
    recalculate()
  }

  func setFocusedDeclarations(_ declarations: [ExperienceKeyboardFieldFocusDeclaration]) {
    focusedDeclarations = declarations
    recalculate()
  }

  func refreshAutomaticFromFirstResponder() {
    recalculate()
  }

  func clearOnKeyboardHidden() {
    recalculate()
  }

  private func recalculate() {
    let showsDone = ExperienceKeyboardDonePolicy.resolvedShowsDone(
      suppressed: suppressed,
      focusedDeclarations: focusedDeclarations,
      signedDecimalActive: signedDecimalActive
    )
    let showsSign = signedDecimalActive && onSignedDecimalToggle != nil && !suppressed
    let next = showsDone || showsSign
    if showsAccessoryBar != next {
      showsAccessoryBar = next
    } else if next {
      objectWillChange.send()
    }
  }

  var showsDoneButton: Bool {
    ExperienceKeyboardDonePolicy.resolvedShowsDone(
      suppressed: suppressed,
      focusedDeclarations: focusedDeclarations,
      signedDecimalActive: signedDecimalActive
    )
  }
}

private struct ExperienceKeyboardAccessoryModelKey: EnvironmentKey {
  static let defaultValue: ExperienceKeyboardAccessoryModel? = nil
}

extension EnvironmentValues {
  fileprivate var experienceKeyboardAccessoryModel: ExperienceKeyboardAccessoryModel? {
    get { self[ExperienceKeyboardAccessoryModelKey.self] }
    set { self[ExperienceKeyboardAccessoryModelKey.self] = newValue }
  }
}

// MARK: - Suppression

private struct ExperienceKeyboardDoneToolbarSuppressedKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  /// When true, ``experienceKeyboardDoneToolbar()`` does not show any keyboard accessory.
  var experienceKeyboardDoneToolbarSuppressed: Bool {
    get { self[ExperienceKeyboardDoneToolbarSuppressedKey.self] }
    set { self[ExperienceKeyboardDoneToolbarSuppressedKey.self] = newValue }
  }
}

// MARK: - Modifiers

private struct ExperienceKeyboardDoneToolbarModifier: ViewModifier {
  @Environment(\.experienceKeyboardDoneToolbarSuppressed) private var suppressed
  @StateObject private var model = ExperienceKeyboardAccessoryModel()

  func body(content: Content) -> some View {
    Group {
      if suppressed {
        content
      } else {
        content
          .environment(\.experienceKeyboardAccessoryModel, model)
          .onAppear { model.setSuppressed(false) }
          .onPreferenceChange(ExperienceKeyboardFieldFocusPreferenceKey.self) { declarations in
            model.setFocusedDeclarations(declarations)
          }
          .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            model.refreshAutomaticFromFirstResponder()
          }
          .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            model.refreshAutomaticFromFirstResponder()
          }
          .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { _ in
            model.refreshAutomaticFromFirstResponder()
          }
          .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            model.clearOnKeyboardHidden()
          }
          .modifier(ExperienceKeyboardAccessoryBarModifier(model: model))
      }
    }
    .onChange(of: suppressed) { _, isSuppressed in
      model.setSuppressed(isSuppressed)
    }
  }
}

private struct ExperienceKeyboardAccessoryBarModifier: ViewModifier {
  @ObservedObject var model: ExperienceKeyboardAccessoryModel
  @Environment(\.themeColors) private var colors

  @ViewBuilder
  func body(content: Content) -> some View {
    if model.showsAccessoryBar {
      content.toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          keyboardAccessoryControls
        }
      }
    } else {
      content
    }
  }

  @ViewBuilder
  private var keyboardAccessoryControls: some View {
    if model.signedDecimalActive, let onToggle = model.onSignedDecimalToggle {
      Button("+/−") {
        ExperienceHaptics.play(.selection)
        onToggle()
      }
      .font(.body.weight(.semibold))
      .foregroundStyle(colors.accent)
      .accessibilityLabel("Toggle plus or minus")
      .accessibilityIdentifier("keyboard.toggleSign")
    }
    Spacer(minLength: 0)
    if model.showsDoneButton {
      Button("Done") {
        ExperienceKeyboard.dismissFormKeyboard()
      }
      .font(.body.weight(.semibold))
      .foregroundStyle(colors.accent)
      .accessibilityLabel("Done")
      .accessibilityHint("Dismisses the keyboard")
      .accessibilityIdentifier("keyboard.done")
    }
  }
}

private struct ExperienceKeyboardFieldDonePolicyModifier: ViewModifier {
  let policy: ExperienceKeyboardFieldDonePolicy
  let isFocused: Bool

  func body(content: Content) -> some View {
    content.preference(
      key: ExperienceKeyboardFieldFocusPreferenceKey.self,
      value: isFocused
        ? [ExperienceKeyboardFieldFocusDeclaration(isFocused: true, kind: policy)]
        : []
    )
  }
}

private struct ExperienceSignedDecimalKeyboardSignToggleModifier: ViewModifier {
  let isActive: Bool
  let onToggleSign: () -> Void

  @Environment(\.experienceKeyboardAccessoryModel) private var accessoryModel

  func body(content: Content) -> some View {
    content
      .onAppear { registerSignToggle(active: isActive) }
      .onChange(of: isActive) { _, active in
        registerSignToggle(active: active)
      }
      .onDisappear {
        accessoryModel?.signedDecimalActive = false
        accessoryModel?.onSignedDecimalToggle = nil
      }
  }

  private func registerSignToggle(active: Bool) {
    accessoryModel?.onSignedDecimalToggle = onToggleSign
    accessoryModel?.signedDecimalActive = active
  }
}

extension View {
  /// Adds a context-sensitive keyboard accessory (Done and optional +/−) for the active field.
  func experienceKeyboardDoneToolbar() -> some View {
    modifier(ExperienceKeyboardDoneToolbarModifier())
  }

  /// Leading **+/−** on the keyboard for signed decimal fields (use with `.decimalPad`).
  func experienceSignedDecimalKeyboardSignToggle(
    isActive: Bool,
    onToggleSign: @escaping () -> Void
  ) -> some View {
    modifier(
      ExperienceSignedDecimalKeyboardSignToggleModifier(
        isActive: isActive,
        onToggleSign: onToggleSign
      )
    )
  }

  /// Return / Send composers and search-like fields: no Done toolbar and no empty accessory strip.
  func experienceKeyboardExcludesDoneToolbarWhenFocused(_ isFocused: Bool) -> some View {
    modifier(
      ExperienceKeyboardFieldDonePolicyModifier(
        policy: .excludesDone,
        isFocused: isFocused
      )
    )
  }

  /// Multiline notes and captions when automatic first-responder detection is unreliable.
  func experienceKeyboardRequiresDoneToolbarWhenFocused(_ isFocused: Bool) -> some View {
    modifier(
      ExperienceKeyboardFieldDonePolicyModifier(
        policy: .requiresDone,
        isFocused: isFocused
      )
    )
  }
}
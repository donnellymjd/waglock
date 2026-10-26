@testable import WagLock
//
//  CalculatorViewModel.swift
//  WagLock
//
//  Calculator logic view model
//  Basic arithmetic plus password sequence detection
//

import Foundation
import SwiftUI

class CalculatorViewModel: ObservableObject {
    @Published var state = CalculatorState()
    @Published private(set) var shouldUnlock: Bool = false

    private let maxHistoryLength = 20
    // Avoid the default-MainActor synthesized-deinit back-deployment crash on
    // older iOS runtimes (swiftlang/swift#88036). No actor-bound cleanup is needed.
    nonisolated deinit { }

    // MARK: - Calculator logic

    /// Digit button pressed
    func numberPressed(_ number: Int) {
        let numString = String(number)

        if state.shouldResetDisplay {
            state.displayValue = numString
            state.shouldResetDisplay = false
        } else {
            // Limit the display length
            if state.displayValue.count < 12 {
                state.displayValue =
                    state.displayValue == "0" ? numString : state.displayValue + numString
            }
        }

        // Add to the password history (digits only)
        addToPasswordHistory(numString)
    }

    /// Decimal point pressed
    func decimalPressed() {
        if !state.displayValue.contains(".") {
            state.displayValue += "."

            // Add to the password history (the decimal point counts too)
            addToPasswordHistory(".")
        }
    }

    /// Operator pressed
    func operationPressed(_ operation: CalculatorState.Operation) {
        // If an operator is already pending, compute the result first
        if let currentOp = state.currentOperation {
            calculateResult()
        } else {
            state.previousValue = Double(state.displayValue) ?? 0
        }

        state.currentOperation = operation
        state.shouldResetDisplay = true

        // ❌ Operators are not added to the password history
    }

    /// Equals pressed
    func equalsPressed() {
        // Then perform the calculation
        calculateResult()

        state.currentOperation = nil
        state.shouldResetDisplay = true
    }

    /// Clear button
    func clearPressed() {
        state = CalculatorState()
    }

    /// Percent button
    func percentPressed() {
        if let value = Double(state.displayValue) {
            state.displayValue = formatNumber(value / 100)
        }
    }

    /// Sign toggle button
    func negatePressed() {
        if let value = Double(state.displayValue) {
            state.displayValue = formatNumber(-value)
        }
    }

    // MARK: - Calculation logic

    private func calculateResult() {
        guard let operation = state.currentOperation,
            let currentValue = Double(state.displayValue)
        else {
            return
        }

        let result = operation.calculate(state.previousValue, currentValue)
        state.displayValue = formatNumber(result)
        state.previousValue = result
    }

    private func formatNumber(_ number: Double) -> String {
        // If it's an integer, show integer formatting
        if number.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", number)
        }

        // Otherwise show at most 8 decimal places
        let formatted = String(format: "%.8f", number)
        // Strip trailing zeros
        return formatted.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    // MARK: - Password detection

    /// Add to the password history (digits and decimal point only)
    private func addToPasswordHistory(_ input: String) {
        state.inputHistory.append(input)

        // Limit the history length
        if state.inputHistory.count > maxHistoryLength {
            state.inputHistory.removeFirst()
        }
    }

    // Arithmetic has no credential access or unlock side effects.
}

// MARK: - Notification Name

extension Notification.Name {
    static let unlockFromDisguise = Notification.Name("unlockFromDisguise")
}

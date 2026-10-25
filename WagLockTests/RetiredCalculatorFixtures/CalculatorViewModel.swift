@testable import WagLock
//
//  CalculatorViewModel.swift
//  WagLock
//
//  计算器逻辑视图模型
//  支持基础四则运算 + 密码序列检测
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

    // MARK: - 计算器逻辑

    /// 数字按钮按下
    func numberPressed(_ number: Int) {
        let numString = String(number)

        if state.shouldResetDisplay {
            state.displayValue = numString
            state.shouldResetDisplay = false
        } else {
            // 限制显示长度
            if state.displayValue.count < 12 {
                state.displayValue =
                    state.displayValue == "0" ? numString : state.displayValue + numString
            }
        }

        // 添加到密码历史（仅数字）
        addToPasswordHistory(numString)
    }

    /// 小数点按下
    func decimalPressed() {
        if !state.displayValue.contains(".") {
            state.displayValue += "."

            // 添加到密码历史（小数点也计入）
            addToPasswordHistory(".")
        }
    }

    /// 运算符按下
    func operationPressed(_ operation: CalculatorState.Operation) {
        // 如果已有运算符，先计算结果
        if let currentOp = state.currentOperation {
            calculateResult()
        } else {
            state.previousValue = Double(state.displayValue) ?? 0
        }

        state.currentOperation = operation
        state.shouldResetDisplay = true

        // ❌ 运算符不计入密码历史
    }

    /// 等号按下
    func equalsPressed() {
        // 再执行计算
        calculateResult()

        state.currentOperation = nil
        state.shouldResetDisplay = true
    }

    /// 清除按钮
    func clearPressed() {
        state = CalculatorState()
    }

    /// 百分号按钮
    func percentPressed() {
        if let value = Double(state.displayValue) {
            state.displayValue = formatNumber(value / 100)
        }
    }

    /// 正负号按钮
    func negatePressed() {
        if let value = Double(state.displayValue) {
            state.displayValue = formatNumber(-value)
        }
    }

    // MARK: - 计算逻辑

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
        // 如果是整数，显示整数格式
        if number.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", number)
        }

        // 否则最多显示8位小数
        let formatted = String(format: "%.8f", number)
        // 去除尾部的0
        return formatted.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    // MARK: - 密码检测

    /// 添加到密码历史（仅数字和小数点）
    private func addToPasswordHistory(_ input: String) {
        state.inputHistory.append(input)

        // 限制历史长度
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

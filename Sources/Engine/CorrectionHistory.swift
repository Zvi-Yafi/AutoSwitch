import Foundation

class CorrectionHistory {
    static let shared = CorrectionHistory()
    
    private var stack: [CorrectionHistoryItem] = []
    private let maxHistoryLength = 5
    
    private init() {}
    
    func push(_ item: CorrectionHistoryItem) {
        if stack.count >= maxHistoryLength {
            stack.removeFirst()
        }
        stack.append(item)
    }
    
    func popLast() -> CorrectionHistoryItem? {
        return stack.popLast()
    }
    
    func popLast(within seconds: Double) -> CorrectionHistoryItem? {
        guard let last = stack.last else {
            return nil
        }
        let age = Date().timeIntervalSince(last.timestamp)
        if age <= seconds {
            return stack.popLast()
        }
        return nil
    }
    
    func peekLast() -> CorrectionHistoryItem? {
        return stack.last
    }
    
    func clear() {
        stack.removeAll()
    }
}

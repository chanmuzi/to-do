import AppKit
import Theme

/// TextKit 조각은 줄의 논리 상태와 별개로 현재 프레임의 불투명도와 꺾쇠 각도만 읽는다.
nonisolated final class FoldDrawing {
    struct Frame {
        var children: Range<Int>
        var openness: Double
    }
    var frames: [Int: Frame] = [:]

    func opacity(at row: Int) -> Double {
        frames.values.reduce(1) { $1.children.contains(row) ? $0 * $1.openness : $0 }
    }
}

struct FoldTransition {
    let from: Double
    let to: Double
    let start: TimeInterval
    let duration: TimeInterval

    func value(at now: TimeInterval, curve: BezierCurve) -> Double {
        guard duration > 0 else { return to }
        return from + (to - from) * curve.progress(at: (now - start) / duration)
    }
}

extension EditorController {
    /// 줄 명령에 넘길 접힘. 기본값으로 닫힌 빈 토글은 커서 줄에서만 판단하면 된다.
    func foldsAtCaret(_ caret: NSRange) -> Set<Int> {
        let row = document.blockLines(at: document.lineIndex(at: caret.location)).lowerBound
        return foldState.isClosed(row, in: document) ? folded.union([row]) : folded
    }

    func performFoldCommand(_ action: EditorAction, at caret: NSRange, moveCaret: Bool) {
        let current = foldsAtCaret(caret)
        let next: Set<Int>
        if action == .fold {
            guard let change = FoldState.fold(document, selection: caret, folded: current) else { return }
            if moveCaret { setSelection(change.selection) }
            next = change.folded
        } else {
            guard let change = FoldState.unfold(document, selection: caret, folded: current) else { return }
            next = change
        }
        changeUserFolds(foldState.toggling(current.symmetricDifference(next), in: document))
    }

    func changeUserFolds(_ next: FoldState) {
        guard next != foldState else { return }
        startFoldMotion(from: folded, to: next.closed)
        applyFolds(next)
        notifyFoldChangeIfNeeded()
    }

    func startFoldMotion(from previous: Set<Int>, to next: Set<Int>) {
        guard foldAnimationsEnabled(), theme.motion.duration > 0 else {
            stopFoldMotion()
            return
        }
        let now = foldClock()
        for root in previous.symmetricDifference(next) {
            let children = (document.blockLines(at: root).upperBound + 1)..<document.lines[root].subtreeEnd
            guard !children.isEmpty else { continue }
            let target: Double = next.contains(root) ? 0 : 1
            let from = foldTransitions[root]?.value(at: now, curve: theme.motion.curve) ?? (1 - target)
            foldTransitions[root] = FoldTransition(from: from, to: target, start: now,
                                                   duration: theme.motion.duration * abs(target - from))
            foldDrawing.frames[root] = FoldDrawing.Frame(children: children, openness: from)
        }
        guard foldTask == nil, !foldTransitions.isEmpty else { return }
        let fps = max(1, textView.window?.screen?.maximumFramesPerSecond ?? 60)
        foldTask = Task { [weak self] in
            while !Task.isCancelled, self?.advanceFoldMotion() == true {
                try? await Task.sleep(for: .seconds(1 / Double(fps)))
            }
        }
    }

    @discardableResult func advanceFoldMotion() -> Bool {
        let now = foldClock()
        let count = foldTransitions.count
        for (row, transition) in foldTransitions {
            if !foldAnimationsEnabled() || now >= transition.start + transition.duration {
                foldTransitions.removeValue(forKey: row)
                foldDrawing.frames.removeValue(forKey: row)
            } else {
                foldDrawing.frames[row]?.openness = transition.value(at: now, curve: theme.motion.curve)
            }
        }
        refreshStyling()
        textView.needsDisplay = true
        if count != foldTransitions.count { reportContentHeight() }
        if foldTransitions.isEmpty {
            foldTask = nil
            return false
        }
        return true
    }

    func stopFoldMotion() {
        foldTask?.cancel()
        foldTask = nil
        foldDrawing.frames.removeAll()
        foldTransitions.removeAll()
    }
}

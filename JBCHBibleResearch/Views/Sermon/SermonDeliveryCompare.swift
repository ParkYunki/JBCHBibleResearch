//
//  SermonDeliveryCompare.swift
//  JBCHBibleResearch
//
//  [2026-11-14 내 설교 고도화] 회차 비교 — 메인 설교와 회차 사본(또는 회차끼리)을 문단 단위로 견준다.
//  - `SermonParagraphDiff`: 문단 배열 LCS 비교(공통 앞뒤는 먼저 걷어 내고, 가운데가 너무 크면 통째 교체로 처리).
//  - `SermonDeliveryCompareView`: 기준·비교 대상 선택, 추가/삭제 요약, 변경된 부분만 보기, 바뀐 글자 강조.
//

import SwiftUI
import SwiftData
import BibleResearchModels

// MARK: - 문단 비교

nonisolated struct SermonDiffLine: Identifiable, Equatable {
    enum Kind { case same, added, removed }

    let id: Int
    let kind: Kind
    let text: String
    /// 삭제/추가가 짝을 이룰 때, 짝과 다른 가운데 글자 범위(UTF-16). 없으면 nil.
    var changedRange: NSRange?
}

nonisolated enum SermonParagraphDiff {
    /// LCS 표가 이 크기(칸 수)를 넘으면 가운데 부분을 "전부 삭제 + 전부 추가"로 처리한다(메모리·시간 상한).
    static let maxTableCells = 4_000_000

    static func diff(old: [String], new: [String]) -> [SermonDiffLine] {
        func norm(_ text: String) -> String { text.trimmingCharacters(in: .whitespaces) }
        let a0 = old.map(norm), b0 = new.map(norm)

        var prefix = 0
        while prefix < a0.count, prefix < b0.count, a0[prefix] == b0[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < a0.count - prefix, suffix < b0.count - prefix,
              a0[a0.count - 1 - suffix] == b0[b0.count - 1 - suffix] { suffix += 1 }
        let a = Array(a0[prefix..<(a0.count - suffix)])
        let b = Array(b0[prefix..<(b0.count - suffix)])

        var raw: [(SermonDiffLine.Kind, String)] = []
        for index in 0..<prefix { raw.append((.same, new[index])) }

        if a.isEmpty {
            for text in new[prefix..<(new.count - suffix)] { raw.append((.added, text)) }
        } else if b.isEmpty {
            for text in old[prefix..<(old.count - suffix)] { raw.append((.removed, text)) }
        } else if a.count * b.count > maxTableCells {
            for text in old[prefix..<(old.count - suffix)] { raw.append((.removed, text)) }
            for text in new[prefix..<(new.count - suffix)] { raw.append((.added, text)) }
        } else {
            // 뒤에서부터 채우는 표: table[i][j] = a[i...]와 b[j...]의 LCS 길이.
            let n = a.count, m = b.count
            var table = [[Int32]](repeating: [Int32](repeating: 0, count: m + 1), count: n + 1)
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
                }
            }
            var i = 0, j = 0
            let oldMiddle = Array(old[prefix..<(old.count - suffix)])
            let newMiddle = Array(new[prefix..<(new.count - suffix)])
            while i < n, j < m {
                if a[i] == b[j] {
                    raw.append((.same, newMiddle[j])); i += 1; j += 1
                } else if table[i + 1][j] >= table[i][j + 1] {
                    raw.append((.removed, oldMiddle[i])); i += 1
                } else {
                    raw.append((.added, newMiddle[j])); j += 1
                }
            }
            while i < n { raw.append((.removed, oldMiddle[i])); i += 1 }
            while j < m { raw.append((.added, newMiddle[j])); j += 1 }
        }
        for index in (new.count - suffix)..<new.count where suffix > 0 { raw.append((.same, new[index])) }

        // 연속한 삭제 묶음과 바로 뒤 추가 묶음을 앞에서부터 1:1로 짝지어 바뀐 글자 범위를 계산한다.
        var lines: [SermonDiffLine] = []
        var index = 0
        while index < raw.count {
            if raw[index].0 == .removed {
                var removedEnd = index
                while removedEnd < raw.count, raw[removedEnd].0 == .removed { removedEnd += 1 }
                var addedEnd = removedEnd
                while addedEnd < raw.count, raw[addedEnd].0 == .added { addedEnd += 1 }
                let removed = Array(raw[index..<removedEnd]), added = Array(raw[removedEnd..<addedEnd])
                let pairs = min(removed.count, added.count)
                var removedLines: [SermonDiffLine] = [], addedLines: [SermonDiffLine] = []
                for k in 0..<removed.count {
                    let range = k < pairs ? changedMiddle(removed[k].1, added[k].1).old : nil
                    removedLines.append(SermonDiffLine(id: 0, kind: .removed, text: removed[k].1, changedRange: range))
                }
                for k in 0..<added.count {
                    let range = k < pairs ? changedMiddle(removed[k].1, added[k].1).new : nil
                    addedLines.append(SermonDiffLine(id: 0, kind: .added, text: added[k].1, changedRange: range))
                }
                for line in removedLines + addedLines { lines.append(line) }
                index = addedEnd
            } else {
                lines.append(SermonDiffLine(id: 0, kind: raw[index].0, text: raw[index].1, changedRange: nil))
                index += 1
            }
        }
        return lines.enumerated().map { SermonDiffLine(id: $0.offset, kind: $0.element.kind, text: $0.element.text, changedRange: $0.element.changedRange) }
    }

    /// 두 문단의 공통 앞부분·뒷부분을 걷어 낸 가운데 범위(UTF-16). 전체가 같거나 한쪽이 비면 nil.
    static func changedMiddle(_ old: String, _ new: String) -> (old: NSRange?, new: NSRange?) {
        let a = Array(old.utf16), b = Array(new.utf16)
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        let oldRange = NSRange(location: prefix, length: a.count - prefix - suffix)
        let newRange = NSRange(location: prefix, length: b.count - prefix - suffix)
        return (oldRange.length > 0 ? oldRange : nil, newRange.length > 0 ? newRange : nil)
    }

    /// 문단 배열(텍스트만).
    static func paragraphs(of text: String) -> [String] {
        let ns = text as NSString
        guard ns.length > 0 else { return [] }
        var result: [String] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { substring, _, _, _ in
            result.append(substring ?? "")
        }
        return result
    }
}

// MARK: - 비교 화면

struct SermonDeliveryCompareView: View {
    let sermon: Sermon
    /// 처음에 비교 대상으로 놓을 회차.
    let initialDelivery: SermonDelivery

    @Environment(\.dismiss) private var dismiss

    private enum Source: Hashable {
        case main
        case delivery(UUID)
    }

    @State private var baseSource: Source = .main
    @State private var targetSource: Source
    @State private var changesOnly = true
    @State private var lines: [SermonDiffLine] = []

    init(sermon: Sermon, initialDelivery: SermonDelivery) {
        self.sermon = sermon
        self.initialDelivery = initialDelivery
        _targetSource = State(initialValue: .delivery(initialDelivery.id))
    }

    private var accent: Color { SermonTheme.accent(.light) }
    private var deliveries: [SermonDelivery] { (sermon.deliveries ?? []).sorted { $0.deliveredAt > $1.deliveredAt } }

    private func text(for source: Source) -> String {
        switch source {
        case .main: return sermon.contentText
        case .delivery(let id): return deliveries.first { $0.id == id }?.contentText ?? ""
        }
    }

    private func label(for source: Source) -> String {
        switch source {
        case .main: return String(localized: "메인 설교")
        case .delivery(let id):
            guard let delivery = deliveries.first(where: { $0.id == id }) else { return String(localized: "삭제된 회차") }
            return "\(delivery.gathering?.name ?? String(localized: "모임 미지정")) · \(delivery.deliveredAt.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    private var addedCount: Int { lines.filter { $0.kind == .added }.count }
    private var removedCount: Int { lines.filter { $0.kind == .removed }.count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                pickers
                Divider()
                summary
                Divider()
                if lines.isEmpty {
                    Text(String(localized: "비교할 내용이 없습니다."))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(visibleRows, id: \.key) { row in rowView(row) }
                        }
                        .padding(14)
                    }
                }
            }
            .background(SermonViewerPaper.color)
            .navigationTitle(String(localized: "회차 비교"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(String(localized: "닫기")) { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 560)
        #endif
        .environment(\.colorScheme, .light)
        .onAppear(perform: recompute)
        .onChange(of: baseSource) { _, _ in recompute() }
        .onChange(of: targetSource) { _, _ in recompute() }
    }

    private func recompute() {
        lines = SermonParagraphDiff.diff(
            old: SermonParagraphDiff.paragraphs(of: text(for: baseSource)),
            new: SermonParagraphDiff.paragraphs(of: text(for: targetSource))
        )
    }

    private var pickers: some View {
        VStack(alignment: .leading, spacing: 8) {
            sourcePicker(String(localized: "기준"), selection: $baseSource)
            sourcePicker(String(localized: "비교 대상"), selection: $targetSource)
        }
        .padding(14)
    }

    private func sourcePicker(_ title: String, selection: Binding<Source>) -> some View {
        HStack {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            Picker(title, selection: selection) {
                Text(label(for: .main)).tag(Source.main)
                ForEach(deliveries) { delivery in Text(label(for: .delivery(delivery.id))).tag(Source.delivery(delivery.id)) }
            }
            .labelsHidden()
            Spacer(minLength: 0)
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            SermonBadge(text: String(localized: "추가 \(addedCount)문단"), color: SermonTheme.success)
            SermonBadge(text: String(localized: "삭제 \(removedCount)문단"), color: Color(red: 0.69, green: 0.25, blue: 0.25))
            let delta = text(for: targetSource).count - text(for: baseSource).count
            Text(String(localized: "글자 수 \(delta >= 0 ? "+" : "")\(delta)")).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Spacer()
            Toggle(String(localized: "변경된 부분만"), isOn: $changesOnly).toggleStyle(.switch).controlSize(.small).fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // 표시 행: 바뀐 줄 또는 (전체 보기일 때) 같은 줄. "변경된 부분만"이면 같은 줄 묶음을 한 줄 요약으로 접는다.
    private struct Row { let key: String; let line: SermonDiffLine?; let collapsed: Int }

    private var visibleRows: [Row] {
        var rows: [Row] = []
        var run = 0
        var runStart = 0
        func flush() {
            if run > 0 { rows.append(Row(key: "c\(runStart)", line: nil, collapsed: run)); run = 0 }
        }
        for line in lines {
            if line.kind == .same && changesOnly {
                if run == 0 { runStart = line.id }
                run += 1
            } else {
                flush()
                rows.append(Row(key: "l\(line.id)", line: line, collapsed: 0))
            }
        }
        flush()
        return rows
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        if let line = row.line {
            let isAdded = line.kind == .added, isRemoved = line.kind == .removed
            HStack(alignment: .top, spacing: 8) {
                Text(isAdded ? "+" : (isRemoved ? "−" : " "))
                    .font(.callout.monospaced().weight(.bold))
                    .foregroundStyle(isAdded ? SermonTheme.success : Color(red: 0.69, green: 0.25, blue: 0.25))
                    .frame(width: 14)
                Text(highlighted(line))
                    .font(.callout)
                    .foregroundStyle(line.kind == .same ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(
                isAdded ? SermonTheme.success.opacity(0.12) : (isRemoved ? Color(red: 0.69, green: 0.25, blue: 0.25).opacity(0.10) : Color.clear),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
        } else {
            Text(String(localized: "… 같은 문단 \(row.collapsed)개"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
        }
    }

    private func highlighted(_ line: SermonDiffLine) -> AttributedString {
        var attributed = AttributedString(line.text.isEmpty ? " " : line.text)
        guard let range = line.changedRange, line.kind != .same,
              let swiftRange = Range(range, in: line.text),
              let lower = AttributedString.Index(swiftRange.lowerBound, within: attributed),
              let upper = AttributedString.Index(swiftRange.upperBound, within: attributed) else { return attributed }
        attributed[lower..<upper].font = .callout.weight(.bold)
        attributed[lower..<upper].backgroundColor = (line.kind == .added ? SermonTheme.success : Color(red: 0.69, green: 0.25, blue: 0.25)).opacity(0.25)
        return attributed
    }
}

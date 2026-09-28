import SwiftUI

//
//  OtherRelationsEditorView.swift
//  PersonSeedEditor
//
//  [2026-09-16 신설] "기타관계"(예: "예수(스승)") 문자열 목록 편집 + 사용자가
//  요청한 "동명이인 중 정확한 대상 고르기" 지원. build_reference_data.py의
//  기타관계 파싱 규칙(마지막 괄호 앞까지가 이름, 괄호 안이 라벨 — 그
//  파일의 `OTHER_RELATION_LABEL_MAP` 처리부 참고)과 똑같은 방식으로 이름을
//  뽑아, `PersonSeedStore.candidates(named:)`(지금 메모리에 있는 PersonSeed.
//  json 전체에서 word/word2 일치)로 동명이인 여부를 보여준다.
//
//  ⚠️ [의도적으로 하지 않은 것] 여기서 "이 후보다"라고 골라도 그 선택을
//  PersonSeed.json에 별도로 저장하지는 않는다 — 지금 "이름(라벨)" 문자열
//  포맷엔 idx를 끼워 넣을 자리가 없고, 새 포맷을 만드는 건 이번 요청
//  범위를 벗어나는 스키마 변경이라 임의로 추가하지 않았다(요청받지 않은
//  설계 변경 금지). 대신 이 화면은 순수 "확인 도구"로만 동작한다 —
//  동명이인이 있으면 화면에 보여주고, 애매하면 개발자가 이름 자체를 더
//  구체적으로 고치거나(예: "예수" -> "유스도라 하는 예수") PersonSeed.json에
//  새 구분 항목을 만들지 직접 판단한다. 오늘 세션에서 야고보/요한/빌립
//  문제를 실제로 고친 방식(이름을 구체화하거나 새 항목을 분리)과 같은
//  맥락이다.
struct OtherRelationsEditorView: View {
    @EnvironmentObject var store: PersonSeedStore
    @Binding var items: [String]

    @State private var candidateSheetName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    TextField("이름(라벨) — 예: 예수(스승)", text: Binding(
                        get: { items.indices.contains(index) ? items[index] : "" },
                        set: { newValue in
                            guard items.indices.contains(index) else { return }
                            items[index] = newValue
                        }
                    ))
                    .textFieldStyle(.roundedBorder)

                    let name = Self.extractName(from: items.indices.contains(index) ? items[index] : "")
                    let count = name.isEmpty ? 0 : store.candidates(named: name).count
                    Button {
                        candidateSheetName = name
                    } label: {
                        if count > 1 {
                            Label("\(count)명", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        } else if count == 1 {
                            Label("확인", systemImage: "checkmark.circle")
                                .foregroundStyle(.green)
                        } else {
                            Label("없음", systemImage: "questionmark.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(name.isEmpty)
                    .help("이 이름을 가진 PersonSeed.json 항목이 몇 명인지 확인합니다.")

                    Button(role: .destructive) {
                        guard items.indices.contains(index) else { return }
                        items.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }
            Button {
                items.append("")
            } label: {
                Label("기타관계 추가", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .font(.callout)
        }
        .sheet(item: Binding(
            get: { candidateSheetName.map { CandidateSheetTarget(name: $0) } },
            set: { candidateSheetName = $0?.name }
        )) { target in
            RelationCandidatesSheet(name: target.name, candidates: store.candidates(named: target.name))
        }
    }

    /// "예수(스승)" -> "예수". 괄호가 없으면(포맷을 벗어난 자유 텍스트)
    /// 전체를 이름으로 취급하지 않고 빈 문자열을 돌려준다 — 이 화면은
    /// build_reference_data.py가 실제로 인식하는 포맷("이름(라벨)")만
    /// 대상으로 하기 때문에, 그 포맷이 아닌 항목까지 억지로 동명이인 검사를
    /// 시도해 엉뚱한 결과를 보여주지 않기 위함.
    static func extractName(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(")"),
              let openIndex = trimmed.firstIndex(of: "("),
              trimmed.distance(from: trimmed.startIndex, to: openIndex) > 0 else {
            return ""
        }
        // build_reference_data.py는 "괄호가 정확히 1개"일 때만 처리한다
        // (기타관계 파싱부 주석 참고) — 여기서도 같은 조건을 맞춘다.
        guard trimmed.filter({ $0 == "(" }).count == 1 else { return "" }
        return String(trimmed[trimmed.startIndex..<openIndex]).trimmingCharacters(in: .whitespaces)
    }
}

private struct CandidateSheetTarget: Identifiable {
    let name: String
    var id: String { name }
}

struct RelationCandidatesSheet: View {
    let name: String
    let candidates: [PersonSeedEntry]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\"\(name)\" 후보 \(candidates.count)명")
                    .font(.headline)
                Spacer()
                Button("닫기") { dismiss() }
            }
            .padding()

            Divider()

            if candidates.isEmpty {
                ContentUnavailableView(
                    "일치하는 인물 없음",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("PersonSeed.json에 이 이름(word/word2)을 가진 항목이 없습니다.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(candidates) { candidate in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(candidate.word).font(.headline)
                            Text("idx=\(candidate.idx)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !candidate.call.isEmpty {
                            Text(candidate.call).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if !candidate.introduce.isEmpty {
                            Text(candidate.introduce)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 320)
    }
}

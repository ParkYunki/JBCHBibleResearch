//
//  ImportedMemoPreviewSheet.swift
//  JBCHBibleResearch
//
//  [2026-09-13 신설] 사용자 요청 — "받은 개인묵상 파일을 열었을 때, 바로
//  목록에 추가할까요, 아니면 내용을 미리 보여주고 확인(추가/취소)을
//  받을까요?" → "미리보기 후 확인"을 선택해, 내용을 먼저 보여주고
//  사용자가 직접 "추가"를 눌러야만 실제로 저장되는 확인 화면이다. 실수로
//  받은 파일이 조용히 저장되는 일이 없다.
//

import SwiftUI
import SwiftData
import BibleResearchModels

struct ImportedMemoPreviewSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let payload: SharedMemoPayload
    /// 시트가 "추가"/"취소" 어느 쪽으로 끝나든 호출부(`ContentView`)가
    /// `PendingMemoImportRequest.shared.consume()`을 부를 수 있게 알려준다.
    let onFinished: () -> Void

    @State private var saveErrorMessage: String?

    private var coordinateLabel: String {
        let bookName = BooksProvider.shared.book(id: payload.bookId)?.nameKo ?? "알 수 없는 책(\(payload.bookId))"
        if let verse = payload.verse {
            return "\(bookName) \(payload.chapter)장 \(verse)절"
        }
        return "\(bookName) \(payload.chapter)장"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label(coordinateLabel, systemImage: "book")
                        .font(.headline)

                    if let anchorText = payload.anchorText, !anchorText.isEmpty {
                        Text("연결된 구절: \(anchorText)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    Text(payload.contentText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)

                    if !payload.tagNames.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("태그")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            // 사용자 결정 — "폴더는 폴더 없음으로 받되, 태그
                            // 정보는 같이 보내기." 폴더를 여기서 보여주지
                            // 않는 이유가 이것이다 — 페이로드 자체에 폴더
                            // 정보를 담지 않으므로(`SharedMemoPayload` 정의
                            // 참고) 보여줄 것도 없다.
                            //
                            // 칩 스타일은 `MemoDetailView.body`의 태그 칩과
                            // 정확히 같은 값(강조색 15% 채움 + 캡슐)을 그대로
                            // 옮겨 왔다 — `FlowLayoutHStack`도 그 화면과 같은
                            // 공용 레이아웃(`Views/Memo/FlowLayoutHStack.swift`)
                            // 을 재사용한다.
                            FlowLayoutHStack {
                                ForEach(payload.tagNames, id: \.self) { name in
                                    Text(name)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color("AccentColor").opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("받은 묵상 미리보기")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        onFinished()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("추가", action: addToLibrary)
                        .fontWeight(.semibold)
                }
            }
            .alert(
                "추가하지 못했습니다",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("확인") { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "")
            }
        }
    }

    private func addToLibrary() {
        do {
            try PendingMemoImportRequest.importIntoLibrary(payload, context: modelContext)
            onFinished()
            dismiss()
        } catch {
            // [2026-09-13] 저장 자체가 실패했을 때는 시트를 닫지 않는다 —
            // 사용자가 알림을 확인한 뒤 다시 "추가"를 시도하거나 "취소"를
            // 직접 누를 수 있게, 미리보기 내용을 그대로 남겨 둔다.
            print("[ImportedMemoPreviewSheet] 개인묵상 추가 실패: \(error)")
            saveErrorMessage = error.localizedDescription
        }
    }
}

//
//  ImportedMemoPreviewSheet.swift
//  JBCHBibleResearch
//
//  받은 개인묵상 파일을 미리 보여 주고, 사용자가 "추가"를 눌러야만 저장하는
//  확인 시트. 받은 파일이 조용히 저장되는 일을 막는다.
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
                            // 폴더는 페이로드에 담기지 않으므로(`SharedMemoPayload` 참고) 여기서 보여주지 않는다.
                            // 칩 스타일과 `FlowLayoutHStack`은 `MemoDetailView.body`의 태그 칩과 같다.
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
            // 저장 실패 시 시트를 닫지 않고 미리보기를 남겨, 다시 "추가"하거나 "취소"할 수 있게 한다.
            print("[ImportedMemoPreviewSheet] 개인묵상 추가 실패: \(error)")
            saveErrorMessage = error.localizedDescription
        }
    }
}

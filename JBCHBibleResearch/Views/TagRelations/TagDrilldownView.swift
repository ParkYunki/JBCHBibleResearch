//
//  TagDrilldownView.swift
//  JBCHBibleResearch
//
//  태그 클릭 시 여는 3분류 드릴다운(관련 메모 / 관련 연구문서 / 관련 OCR 이미지).
//  TagRelationsView(S10)와 MemoDetailView(태그 칩) 양쪽에서 재사용하는 독립 시트 뷰다.
//  자체 NavigationStack을 가져, 어느 화면에서 열든 항목을 눌러 메모/문서 상세로 계속 들어갈 수 있다.
//

import SwiftUI
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

struct TagDrilldownView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    // 맥/아이패드는 문서를 별도 창("document-viewer" WindowGroup)으로 연다. 아이폰은 다중 씬을
    // 지원하지 않아 openWindow가 런타임 에러를 내므로 NavigationLink로 푸시한다(isPhoneIdiom 참고).
    @Environment(\.openWindow) private var openWindow
    let tag: Tag

    @State private var result = TagDrilldownResult()

    private var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    var body: some View {
        NavigationStack {
            List {
                Section("관련 메모 (\(result.memos.count))") {
                    if result.memos.isEmpty {
                        Text("없음").foregroundStyle(.secondary)
                    }
                    ForEach(result.memos) { item in
                        NavigationLink {
                            MemoDetailView(memo: item.memo)
                        } label: {
                            Text(memoLabel(item.memo))
                        }
                    }
                }

                Section("관련 연구문서 (\(result.documents.count))") {
                    if result.documents.isEmpty {
                        Text("없음").foregroundStyle(.secondary)
                    }
                    ForEach(result.documents) { item in
                        // 맥/아이패드는 새 창, 아이폰은 NavigationLink 푸시(다중 씬 미지원, isPhoneIdiom 참고).
                        if isPhoneIdiom {
                            NavigationLink {
                                DocumentViewerWindowContent(documentID: item.document.persistentModelID)
                            } label: {
                                Text("\(item.document.originalFilename) — p.\(item.anchor.pageNumber + 1)")
                            }
                        } else {
                            Button {
                                openWindow(id: "document-viewer", value: item.document.persistentModelID)
                            } label: {
                                Text("\(item.document.originalFilename) — p.\(item.anchor.pageNumber + 1)")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("관련 OCR 이미지 (\(result.ocrImages.count))") {
                    if result.ocrImages.isEmpty {
                        Text("없음").foregroundStyle(.secondary)
                    }
                    ForEach(result.ocrImages) { item in
                        // ⚠️ 문서 뷰어(S6)를 여는 데까지만 구현 — anchor.bboxOrOffset 기반 이미지 하이라이트
                        // 오버레이는 없다.
                        if isPhoneIdiom {
                            NavigationLink {
                                DocumentViewerWindowContent(documentID: item.document.persistentModelID)
                            } label: {
                                Text(item.document.originalFilename)
                            }
                        } else {
                            Button {
                                openWindow(id: "document-viewer", value: item.document.persistentModelID)
                            } label: {
                                Text(item.document.originalFilename)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(tag.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .onAppear {
            result = TagGraphViewModel.loadDrilldown(for: tag, context: modelContext)
        }
    }

    /// 메모에 제목 개념이 없어(content_text만 있음) 본문 앞 20자를 발췌해 라벨로 쓴다.
    private func memoLabel(_ memo: UserMemo) -> String {
        let bookName = BooksProvider.shared.book(id: memo.bookId)?.nameKo ?? "성경"
        let excerpt = memo.contentText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20)
        if excerpt.isEmpty {
            return "\(bookName) \(memo.chapter)장 메모"
        }
        return "\(excerpt) — \(bookName) \(memo.chapter)장"
    }
}

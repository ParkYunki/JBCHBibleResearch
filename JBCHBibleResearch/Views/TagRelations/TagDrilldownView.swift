//
//  TagDrilldownView.swift
//  JBCHBibleResearch
//
//  screens.md S10 "태그 클릭 → 3분류 드릴다운(확정)" — 관련 메모 / 관련 연구문서 /
//  관련 OCR 이미지. "이 드릴다운 컴포넌트는 S10뿐 아니라 메모·문서의 태그 칩을
//  클릭했을 때도 동일하게 재사용합니다"라는 원문 그대로, 독립된 시트 뷰로 분리해서
//  `TagRelationsView`(S10)와 `MemoDetailView`(태그 칩) 양쪽에서 쓴다.
//
//  자체 NavigationStack을 갖고 있어(시트로 표시), 어느 화면에서 열든 항목을 눌러
//  메모/문서 상세로 계속 들어갈 수 있다.
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
    // [2026-08-07 추가] S6이 별도 창 구조로 바뀌면서(JBCHBibleResearchApp.swift
    // "document-viewer" WindowGroup 참고), 이 화면의 문서 진입점 두 곳도 더 이상
    // NavigationLink로 문서 뷰어를 이 시트 안에 푸시하지 않는다.
    // [2026-08-18 수정] 위 원칙은 맥/아이패드에만 유효 — 아이폰은 다중 씬을
    // 지원하지 않아 openWindow가 런타임 에러를 낸다(isPhoneIdiom 참고).
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
                        // [2026-08-07 수정] S6이 별도 창(Preview.app 패턴)으로 바뀌면서
                        // NavigationLink 푸시 대신 새 창을 연다.
                        // [2026-08-18 수정, 아이폰 크래시 fix] 아이폰만 다시
                        // NavigationLink 푸시로(다중 씬 미지원, isPhoneIdiom 참고).
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
                        // ⚠️ [단순화] 원문은 "OCR 이미지를 하이라이트와 함께 오픈"이라고
                        // 적었지만, 이 구현은 문서 뷰어(S6)를 그냥 여는 것까지만
                        // 한다 — anchor.bboxOrOffset을 실제 이미지 좌표 오버레이로
                        // 그리는 하이라이트 렌더링은 만들지 않았다(범위 밖).
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

    /// 스펙 목업 "'거듭남에 대하여' — 요3장 메모" 형태를 흉내낸다. 메모에 제목
    /// 개념이 없어(6.5, content_text만 있음) 본문 앞부분을 발췌해 대신 썼다.
    private func memoLabel(_ memo: UserMemo) -> String {
        let bookName = BooksProvider.shared.book(id: memo.bookId)?.nameKo ?? "성경"
        let excerpt = memo.contentText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20)
        if excerpt.isEmpty {
            return "\(bookName) \(memo.chapter)장 메모"
        }
        return "\(excerpt) — \(bookName) \(memo.chapter)장"
    }
}

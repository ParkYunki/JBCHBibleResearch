//
//  OutlineSeedImporter.swift
//  JBCHBibleResearch
//
//  번들된 `Resources/OutlineSeed.json`의 기본 개요를 신규 사용자 DB로 복사해 넣는 1회성 가져오기(복사된 뒤에는
//  사용자가 수정 가능). 파일이 없으면 조용히 건너뛴다(에러 아님).
//
//  ## OutlineSeed.json 형식
//  ```json
//  [
//    { "book": "창세기", "chapter": null, "text": "책 전체 개요 텍스트" },
//    { "book": "창세기", "chapter": 1, "text": "1장 개요 텍스트" }
//  ]
//  ```
//  - `book`: 정경 순 66권 한글 이름 그대로(`books.json`의 `nameKo`) — 예: "창세기", "시편", "요한복음".
//    오타가 있으면 그 항목만 건너뛰고 콘솔에 로그를 남긴다(다른 항목엔 영향 없음).
//  - `chapter`: 생략하거나 `null`이면 "책 개요"(`BookOutline`), 숫자를 넣으면 그 장 개요(`ChapterSummary`).
//  - `text`: 순수 텍스트(줄바꿈은 `\n`) 또는 `OutlineSeedExporter`가 내보낸 RTF 문자열(`{\rtf1`로 시작).
//    `RichTextCodec.decode`가 접두사로 판별하므로 두 형식이 같은 배열에 섞여 있어도 된다.
//
//  작성 워크플로: DEBUG 빌드에서 `OutlineBookBulkEditView`의 리치 에디터로 서식을 넣어 작성 → 설정 > 개발자 탭의
//  "내보내기"(`OutlineSeedExporter`) → 결과를 `Resources/OutlineSeed.json`에 덮어쓴다. 서식이 필요 없는 짧은
//  항목은 텍스트 편집기로 직접 써도 된다.
//
//  ⚠️ JSON 파일을 처음 만든 뒤 Xcode Copy Bundle Resources에 한 번 등록해야 한다(다른 번들 리소스와 동일).
//  같은 경로를 유지하는 한 내용을 고쳐도 재등록은 필요 없다.
//
//  ⚠️ `importIfNeeded`는 기기당 한 번만 실행된다(`UserSettingsStore.hasImportedOutlineSeed` 플래그).
//  JSON을 고친 뒤 다시 테스트하려면 앱을 지우고 재설치해 플래그를 초기화해야 한다.
//
//  [2026-10-22] 번역 개요 — 비한국어 앱(`AppLanguage.referenceDataLanguage`)이면 `Resources/OutlineSeed_<en|zh|es>.json`을
//  대신 가져온다(없으면 기존 한국어 `OutlineSeed.json`). 번역본은 평문이라, 가져올 때 한 번 "설교 본문 글자 크기"
//  (`UserSettingsStore.sermonBodyFontSize`, 설정 "내 설교 – 본문")의 단일 서식 RTF로 감싸 저장한다 — 그 뒤 설정을 바꿔도
//  이미 가져온 개요는 따라가지 않는다(사용자 확정). 가져오기 플래그는 언어와 무관한 기존 1회 플래그 그대로라, 가져온 뒤
//  앱 언어를 바꿔도 다시 가져오지 않는다. 책 이름("book")은 번역본도 한글 `nameKo` 그대로다.
//  ⚠️ 번역 JSON 3개도 Copy Bundle Resources(타깃 멤버십)에 포함돼야 한다.
//

import Foundation
import SwiftData
import BibleResearchModels
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
enum OutlineSeedImporter {
    /// 항목마다 `ModelContext.fetch`/`insert`를 동기 호출하고 반복 횟수가 콘텐츠 분량(장 수)에 비례한다.
    /// `await` 없이 `@MainActor`에서 끝까지 돌면 최초 실행 때 UI 이벤트(온보딩 "다음" 탭 등)가 처리되지 못해
    /// 한동안 멈춘 것처럼 보이므로, `yieldInterval`개마다 `await Task.yield()`로 메인 런루프에 제어를 돌려준다.
    private static let yieldInterval = 20

    static func importIfNeeded(into context: ModelContext) async {
        guard !UserSettingsStore.shared.hasImportedOutlineSeed else { return }
        defer { UserSettingsStore.shared.hasImportedOutlineSeed = true }

        guard let seed = seedResource() else {
            // 아직 번들에 시드 파일이 없다 — 정상 상황이므로 에러로 취급하지 않는다.
            return
        }
        let url = seed.url

        do {
            let data = try Data(contentsOf: url)
            guard let rawEntries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                print("[OutlineSeedImporter] OutlineSeed.json이 배열(JSON array) 형식이 아닙니다.")
                return
            }

            var filledBookCount = 0
            var filledChapterCount = 0
            var skippedCount = 0

            for (index, raw) in rawEntries.enumerated() {
                // 메인 스레드를 계속 붙들지 않도록 일정 개수마다 실행을 양보한다(`yieldInterval` 참고).
                if index > 0 && index % yieldInterval == 0 {
                    await Task.yield()
                }
                guard let bookName = raw["book"] as? String, let text = raw["text"] as? String else {
                    print("[OutlineSeedImporter] 형식이 맞지 않아 건너뜁니다(book/text 필요): \(raw)")
                    skippedCount += 1
                    continue
                }
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedText.isEmpty else { continue }

                guard let book = resolveBook(named: bookName) else {
                    print("[OutlineSeedImporter] \"\(bookName)\" 책 이름을 찾지 못해 건너뜁니다 — books.json의 정확한 한글 이름(nameKo)과 맞는지 확인하세요.")
                    skippedCount += 1
                    continue
                }

                // JSON에 "chapter"가 없거나 null이면 raw["chapter"]는 nil이거나
                // NSNull이다 — 둘 다 `as? Int`가 nil을 돌려주므로 별도 처리 없이
                // "책 개요"로 해석된다.
                let chapter = raw["chapter"] as? Int

                do {
                    if let chapter {
                        let target = try ChapterSummaryDeduplication.findOrCreateChapterSummary(
                            bookId: book.bookId, chapter: chapter, context: context
                        )
                        guard target.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                        let stored = storedContent(for: text, isTranslatedPlainText: seed.isTranslatedPlainText)
                        target.contentHtml = stored.html
                        target.contentText = stored.text
                        target.updatedAt = .now
                        filledChapterCount += 1
                    } else {
                        let target = try BookOutlineDeduplication.findOrCreateBookOutline(bookId: book.bookId, context: context)
                        guard target.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                        let stored = storedContent(for: text, isTranslatedPlainText: seed.isTranslatedPlainText)
                        target.contentHtml = stored.html
                        target.contentText = stored.text
                        target.updatedAt = .now
                        filledBookCount += 1
                    }
                } catch {
                    print("[OutlineSeedImporter] \(bookName) 항목 적용 실패: \(error)")
                    skippedCount += 1
                }
            }

            try context.save()
            print("[OutlineSeedImporter] 기본 개요 가져오기 완료(\(url.lastPathComponent)) — 책 \(filledBookCount)권 / 장 \(filledChapterCount)개 적용, \(skippedCount)개 건너뜀.")
        } catch {
            print("[OutlineSeedImporter] \(url.lastPathComponent) 읽기 실패: \(error)")
        }
    }

    // MARK: - 번역 개요 (2026-10-22)

    private struct SeedResource {
        let url: URL
        /// 번역 시드(평문) — 저장 전에 설교 본문 크기 RTF로 감싼다. 한국어 시드는 false(기존 대입 그대로).
        let isTranslatedPlainText: Bool
    }

    /// 비한국어 앱이면 `OutlineSeed_<lang>.json`, 그 파일이 번들에 없거나 한국어 앱이면 기존 `OutlineSeed.json`.
    private static func seedResource() -> SeedResource? {
        if let language = AppLanguage.referenceDataLanguage,
           let url = Bundle.main.url(forResource: "OutlineSeed_\(language)", withExtension: "json") {
            return SeedResource(url: url, isTranslatedPlainText: true)
        }
        guard let url = Bundle.main.url(forResource: "OutlineSeed", withExtension: "json") else { return nil }
        return SeedResource(url: url, isTranslatedPlainText: false)
    }

    /// 저장할 (contentHtml, contentText). 한국어 시드이거나 번역 항목이 이미 RTF면 기존과 똑같이 원문을 두 칸에 넣는다.
    /// 번역 평문이면 RTF로 감싸 contentHtml에, 평문을 contentText(검색·미리보기용 계약)에 넣는다. RTF 인코딩이 실패하면
    /// `RichTextCodec.encode`가 평문을 두 값 모두로 돌려주므로 최악에도 내용은 보존된다(화면 기본 글꼴로 보일 뿐).
    private static func storedContent(for text: String, isTranslatedPlainText: Bool) -> (html: String, text: String) {
        guard isTranslatedPlainText, !text.hasPrefix("{\\rtf1") else { return (text, text) }
        let encoded = plainTextAsSermonBodyRTF(text)
        return (encoded.rtf, encoded.plainText)
    }

    /// 번역 평문 → 편집기 기본 글꼴 계열(`EditorDefaultStyle.typingFont`) + "내 설교 – 본문" 글자 크기의 단일 서식 RTF.
    /// 줄간격·글자색은 개요 편집기(`OutlineBookBulkEditView`가 넘기는 `RichTextEditor` 기본 서식)와 같은 공식·값이다.
    /// 설정값이 0 이하(비정상)면 편집기 기본 크기를 쓴다.
    private static func plainTextAsSermonBodyRTF(_ plain: String) -> (rtf: String, plainText: String) {
        let base = EditorDefaultStyle.typingFont
        let requestedSize = CGFloat(UserSettingsStore.shared.sermonBodyFontSize)
        let pointSize = requestedSize > 0 ? requestedSize : base.pointSize
        #if os(iOS)
        let font = base.withSize(pointSize)
        #elseif os(macOS)
        let font = NSFont(descriptor: base.fontDescriptor, size: pointSize) ?? base
        #endif
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = font.typographicLineHeight * max(0, EditorDefaultStyle.lineHeightMultiple - 1)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
            .foregroundColor: EditorDefaultStyle.textColor,
        ]
        return RichTextCodec.encode(NSAttributedString(string: plain, attributes: attributes))
    }

    /// `book` 문자열을 `Book`으로 해석한다 — 정확한 한글 이름(`nameKo`) 우선,
    /// 없으면 약칭(`abbreviation`) 목록에서 찾는다. 공백은 앞뒤로 트리밍한다.
    private static func resolveBook(named name: String) -> Book? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = BooksProvider.shared.books.first(where: { $0.nameKo == trimmed }) {
            return exact
        }
        return BooksProvider.shared.books.first { $0.abbreviation.contains(trimmed) }
    }
}

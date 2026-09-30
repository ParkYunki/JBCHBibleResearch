//
//  OutlineSeedExporter.swift
//  JBCHBibleResearch
//
//  DEBUG 전용 개발자 도구: 개발자 기기의 로컬 DB에 쌓인 `BookOutline`/`ChapterSummary`를
//  `Resources/OutlineSeed.json`과 같은 JSON 배열 포맷으로 내보낸다. 개요는 이미 `OutlineBookBulkEditView`
//  (`RichTextEditor` + `EditorDefaultStyle`)에서 서식을 넣어 작성하므로, 이 파일은 그 결과를 배포용 시드
//  파일로 뽑아내는 것만 맡는다.
//
//  `text` 필드에는 `RichTextCodec`가 만든 RTF 문자열을 그대로 담는다(`{`/`}`/`\` 같은 제어 문자는
//  `JSONSerialization`이 이스케이프하므로 base64가 필요 없다). `OutlineSeedImporter`는 `{\rtf1`로 시작하면 RTF,
//  아니면 평문으로 판별하므로 두 형식이 같은 JSON 배열에 섞여 있어도 된다.
//
//  ⚠️ 개발자 도구이므로 파일 전체를 `#if DEBUG`로 감싼다(설정 > 개발자 탭도 동일). `OutlineSeedImporter`는
//  배포 빌드에도 필요해 별도 파일로 뒀다 — 의도적인 비대칭이다.
//

#if DEBUG
import Foundation
import SwiftData
import BibleResearchModels

@MainActor
enum OutlineSeedExporter {
    struct Summary {
        let bookCount: Int
        let chapterCount: Int
    }

    /// 지금 이 기기(개발자 자신의 DB)에 쌓인 책 개요/장 개요 중 내용이 있는
    /// 것만 모아 `OutlineSeed.json`과 같은 배열 포맷으로 내보낸다. `text` 필드는
    /// `contentHtml`(실제로는 RTF, `RichTextEditor.swift` 상단 주석 참고)을
    /// 그대로 옮긴다 — 리치 에디터로 넣은 서식(글꼴/색/굵게 등)이 그대로 보존된다.
    static func exportSeedJSON(context: ModelContext) throws -> (data: Data, summary: Summary) {
        let outlines = try context.fetch(FetchDescriptor<BookOutline>())
            .filter { !$0.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let summaries = try context.fetch(FetchDescriptor<ChapterSummary>())
            .filter { !$0.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        var entries: [[String: Any]] = []

        for outline in outlines.sorted(by: { $0.bookId < $1.bookId }) {
            guard let book = BooksProvider.shared.book(id: outline.bookId) else { continue }
            entries.append(["book": book.nameKo, "chapter": NSNull(), "text": outline.contentHtml])
        }
        for summary in summaries.sorted(by: { $0.bookId != $1.bookId ? $0.bookId < $1.bookId : $0.chapter < $1.chapter }) {
            guard let book = BooksProvider.shared.book(id: summary.bookId) else { continue }
            entries.append(["book": book.nameKo, "chapter": summary.chapter, "text": summary.contentHtml])
        }

        let data = try JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .sortedKeys])
        return (data, Summary(bookCount: outlines.count, chapterCount: summaries.count))
    }
}
#endif

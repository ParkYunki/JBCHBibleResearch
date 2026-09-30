//
//  EmbeddingIndexingService.swift
//  JBCHBibleResearch
//
//  임베딩 의미검색의 "색인" 단계. 번들 번역본(개역한글,
//  `TranslationBootstrap.bundledTranslationCode`) 66권 31,102절 전체를
//  `EmbeddingService.embedPassage(_:)`(multilingual-e5-small, Core ML)로
//  벡터화해 디스크에 저장하고, 검색 시점엔 전부 메모리로 읽어 코사인 유사도
//  (brute-force)로 비교한다.
//
//  설계 결정 — SwiftData/CloudKit을 쓰지 않는다: 이 인덱스는 번들 성경 원문과
//  임베딩 모델만으로 100% 재생성 가능한 파생 캐시이고, 31,102개 벡터 행을
//  CloudKit으로 동기화하면 대역폭/저장공간 낭비와 동기화 충돌 여지만 늘어난다.
//  그래서 `Application Support`의 바이너리 파일 하나로 로컬에만 두며, 기기를
//  바꾸거나 앱을 재설치하면 그 기기에서 다시 색인한다.
//
//  색인은 오래 걸릴 수 있어 진행률 콜백과 Task 취소를 지원한다.
//

import Foundation
import BibleResearchModels
#if os(iOS)
import UIKit
#endif

@MainActor
final class EmbeddingIndexingService {
    static let shared = EmbeddingIndexingService()

    private init() {
        refreshStatus()
        #if os(iOS)
        // 싱글턴이라 해제될 일이 없어 옵저버 토큰은 보관하지 않는다.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseLoadedIndex() }
        }
        #endif
    }

    /// 메모리 압박 시 메모리에 올려 둔 색인 벡터를 버린다(파일은 그대로) — 다음 검색에서 다시 읽는다.
    func releaseLoadedIndex() {
        loadedIndex = nil
    }

    enum IndexStatus: Equatable {
        case notBuilt
        case building(progress: Double)
        case ready(verseCount: Int, builtAt: Date)
        case failed(String)
    }

    enum IndexError: Error, CustomStringConvertible {
        case sourceUnavailable(String)
        case corrupted(String)
        case cancelled

        var description: String {
            switch self {
            case .sourceUnavailable(let message): return message
            case .corrupted(let message): return message
            case .cancelled: return "색인 생성이 취소되었습니다."
            }
        }
    }

    /// `vector`는 그 절 본문 하나만 임베딩한 것(표시 단위와 일치), `contextVector`는
    /// 같은 장 안에서 앞뒤 절을 포함한 국소 문맥을 임베딩한 것(짧은 절은 의미가
    /// 희박한 경우를 보완). 검색 결과는 절 단위로 표시한다.
    struct Record {
        let bookId: Int32
        let chapter: Int32
        let verse: Int32
        let vector: [Float]
        let contextVector: [Float]
    }

    /// `ensureLoaded()`가 돌려주는 묶음. `meanVerseVector`/`meanContextVector`는
    /// 코퍼스 전체 벡터의 평균이다. `BibleSemanticSearchService`는 더 이상 검색에
    /// 쓰지 않지만, 필드를 지우면 파일 포맷이 바뀌어 재색인이 강제되므로
    /// 계속 계산/저장한다(비용은 미미하다).
    struct LoadedIndex {
        let records: [Record]
        let meanVerseVector: [Float]
        let meanContextVector: [Float]
    }

    private(set) var status: IndexStatus = .notBuilt
    private var loadedIndex: LoadedIndex?

    private static let fileMagic: [UInt8] = Array("BVEI".utf8)
    /// 포맷을 바꾸면 버전을 올린다 — 버전 불일치 시 `parseHeader`가 nil을 돌려주고
    /// `refreshStatus()`가 `.notBuilt`로 판단해, 별도 마이그레이션 없이 재색인으로 유도된다.
    private static let fileVersion: UInt32 = 2
    /// 절 하나당 헤더 뒤 고정 3필드(bookId/chapter/verse, Int32 3개=12바이트) +
    /// 벡터 2개(절/문맥, 각각 Float32 × dimension).
    private static let recordFixedByteCount = 12

    private static func meanVector(of vectors: [[Float]], dimension: Int) -> [Float] {
        guard !vectors.isEmpty else { return [Float](repeating: 0, count: dimension) }
        var sum = [Float](repeating: 0, count: dimension)
        for vector in vectors {
            guard vector.count == dimension else { continue }
            for i in 0..<dimension { sum[i] += vector[i] }
        }
        let count = Float(vectors.count)
        return sum.map { $0 / count }
    }

    private var indexDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("BibleVerseEmbeddingIndex", isDirectory: true)
    }

    private func indexFileURL(translationCode: String) -> URL {
        indexDirectory.appendingPathComponent("\(translationCode).bvei")
    }

    // MARK: - 상태 확인 (가볍다 — 파일 헤더만 읽는다, 전체 로드 아님)

    func refreshStatus() {
        // 생성 중엔 파일이 아직 없는 게 정상이다(끝날 때 한 번에 쓴다) —
        // 진행률을 `.notBuilt`로 되돌리면 안 된다.
        if case .building = status { return }
        let url = indexFileURL(translationCode: TranslationBootstrap.bundledTranslationCode)
        // `.mappedIfSafe` — 헤더 몇십 바이트만 필요한데 `Data(contentsOf:)`는 파일 전체(≈95MB)를
        // 메모리로 읽는다. 매핑하면 실제로 건드린 앞쪽 페이지만 올라온다.
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), let header = Self.parseHeader(data: data) else {
            status = .notBuilt
            return
        }
        status = .ready(verseCount: Int(header.count), builtAt: header.builtAt)
    }

    // MARK: - 색인 생성 작업 소유(싱글턴이 직접 들고 있음)

    private var buildTask: Task<Void, Never>?

    /// Task를 화면 수명에 묶인 `SearchViewModel`이 아니라 싱글턴이 소유해, 색인 생성 중
    /// 다른 화면으로 이동해도 계산이 끊기지 않는다. 이미 진행 중이면 무시한다.
    func startBuilding(
        progress: @escaping @MainActor (Double) -> Void,
        completion: @escaping @MainActor (IndexStatus) -> Void
    ) {
        guard buildTask == nil else { return }
        buildTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.buildIndex(progress: progress)
            } catch {
                // 실패/취소 원인은 `buildIndex`가 이미 `status`에 반영했다 —
                // 최종 상태를 콜백에 넘기기만 한다.
            }
            completion(self.status)
            self.buildTask = nil
        }
    }

    func cancelBuilding() {
        buildTask?.cancel()
    }

    func deleteIndex() {
        let url = indexFileURL(translationCode: TranslationBootstrap.bundledTranslationCode)
        try? FileManager.default.removeItem(at: url)
        loadedIndex = nil
        status = .notBuilt
    }

    // MARK: - 파일 포맷(v2): "BVEI" 매직 + 버전(UInt32) + 번역본코드(길이-프리픽스
    // UTF8) + 차원(UInt32) + 절 개수(UInt32) + 생성시각(Double, Unix epoch)
    // + 코퍼스 평균 벡터 2개(절용/문맥용, 각각 Float32 × dimension) + 레코드 반복
    // (Int32 bookId, Int32 chapter, Int32 verse, Float32 × dimension(절 벡터),
    // Float32 × dimension(문맥 벡터)).

    private struct Header {
        let dimension: UInt32
        let count: UInt32
        let builtAt: Date
        let meanVerseVector: [Float]
        let meanContextVector: [Float]
        let headerByteCount: Int
    }

    private static func parseHeader(data: Data) -> Header? {
        guard data.count >= fileMagic.count, Array(data.prefix(fileMagic.count)) == fileMagic else { return nil }
        var offset = fileMagic.count
        guard let version = VectorCoding.uint32(from: data, at: offset), version == fileVersion else { return nil }
        offset += 4
        guard let codeLength = VectorCoding.uint32(from: data, at: offset) else { return nil }
        offset += 4 + Int(codeLength) // 번역본 코드 문자열 자체는 검증에만 쓰고 건너뛴다.
        guard let dimension = VectorCoding.uint32(from: data, at: offset) else { return nil }
        offset += 4
        guard let count = VectorCoding.uint32(from: data, at: offset) else { return nil }
        offset += 4
        guard let builtAtInterval = VectorCoding.double(from: data, at: offset) else { return nil }
        offset += 8
        let dimensionInt = Int(dimension)
        let vectorByteCount = dimensionInt * MemoryLayout<Float>.size
        guard offset + vectorByteCount * 2 <= data.count else { return nil }
        guard let meanVerseVector = VectorCoding.floatArray(from: data.subdata(in: offset..<(offset + vectorByteCount)), count: dimensionInt) else { return nil }
        offset += vectorByteCount
        guard let meanContextVector = VectorCoding.floatArray(from: data.subdata(in: offset..<(offset + vectorByteCount)), count: dimensionInt) else { return nil }
        offset += vectorByteCount
        return Header(
            dimension: dimension, count: count, builtAt: Date(timeIntervalSince1970: builtAtInterval),
            meanVerseVector: meanVerseVector, meanContextVector: meanContextVector, headerByteCount: offset
        )
    }

    // MARK: - 검색용 전체 로드

    /// 검색(코사인 유사도 brute-force) 직전에 한 번 호출 — 파일 전체를 메모리로
    /// 읽어 캐시한다(31,102개 × 384차원 × 2 × 4바이트 ≈ 95MB).
    func ensureLoaded() throws -> LoadedIndex {
        if let loadedIndex { return loadedIndex }
        let url = indexFileURL(translationCode: TranslationBootstrap.bundledTranslationCode)
        // `.mappedIfSafe` — 원본 바이트는 매핑(회수 가능한 파일 캐시)으로 두고 `Record` 배열만
        // 힙에 만든다. 이 함수는 동기라 매핑이 곧 해제되고, 색인 갱신은 원자적 교체(새 파일)라
        // 읽는 도중 내용이 바뀌지 않는다.
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw IndexError.sourceUnavailable("색인 파일이 없습니다. 먼저 색인을 만들어주세요.")
        }
        guard let header = Self.parseHeader(data: data) else {
            throw IndexError.corrupted("색인 파일을 읽을 수 없습니다. 다시 만들어주세요.")
        }
        let dimension = Int(header.dimension)
        let vectorByteCount = dimension * MemoryLayout<Float>.size
        let recordByteCount = Self.recordFixedByteCount + vectorByteCount * 2
        var records: [Record] = []
        records.reserveCapacity(Int(header.count))
        var offset = header.headerByteCount
        for _ in 0..<header.count {
            guard offset + recordByteCount <= data.count,
                  let bookId = VectorCoding.int32(from: data, at: offset),
                  let chapter = VectorCoding.int32(from: data, at: offset + 4),
                  let verse = VectorCoding.int32(from: data, at: offset + 8) else {
                throw IndexError.corrupted("색인 파일이 손상되었습니다. 다시 만들어주세요.")
            }
            let verseVectorStart = offset + Self.recordFixedByteCount
            let contextVectorStart = verseVectorStart + vectorByteCount
            guard let vector = VectorCoding.floatArray(from: data.subdata(in: verseVectorStart..<(verseVectorStart + vectorByteCount)), count: dimension),
                  let contextVector = VectorCoding.floatArray(from: data.subdata(in: contextVectorStart..<(contextVectorStart + vectorByteCount)), count: dimension) else {
                throw IndexError.corrupted("색인 파일이 손상되었습니다. 다시 만들어주세요.")
            }
            records.append(Record(bookId: bookId, chapter: chapter, verse: verse, vector: vector, contextVector: contextVector))
            offset += recordByteCount
        }
        let index = LoadedIndex(records: records, meanVerseVector: header.meanVerseVector, meanContextVector: header.meanContextVector)
        loadedIndex = index
        return index
    }

    // MARK: - 색인 생성

    /// 번들 번역본 66권 전체를 절 단위로 순회하며 임베딩을 계산한다. 메모리에 전부
    /// 모아뒀다가 끝에 파일 하나로 원자적으로 쓴다 — 중간에 취소되면 파일을
    /// 만들지 않으며 이어서 계속하기는 지원하지 않는다.
    func buildIndex(progress: @escaping @MainActor (Double) -> Void) async throws {
        status = .building(progress: 0)
        do {
            let translationCode = TranslationBootstrap.bundledTranslationCode
            let store = try BibleReferenceStore(filePath: TranslationBootstrap.resolvedBundledDatabaseURL().path)
            let books = BooksProvider.shared.books
            guard !books.isEmpty else {
                throw IndexError.sourceUnavailable("책 목록(books.json)을 불러오지 못했습니다.")
            }

            struct VerseEntry {
                let bookId: Int
                let chapter: Int
                let verse: Int
                let content: String
            }
            // 장(chapter) 단위로 묶어 둔다 — 문맥 임베딩이 같은 장 안의 앞뒤 절만
            // 참조해야 하므로(장 경계를 넘으면 안 됨) 평평한 배열로는 이웃 절을
            // 안전하게 찾기 어렵다.
            //
            // 아래 이중 루프(약 1,189장)는 동기 SQLite 조회를 반복하고 첫 `await`
            // 이전에 실행되므로, 20장마다 `Task.yield()`로 메인 액터를 양보한다.
            var chapters: [[VerseEntry]] = []
            var scannedChapterCount = 0
            for book in books {
                guard let maxChapter = try? store.maxChapter(bookId: book.bookId), maxChapter > 0 else { continue }
                for chapter in 1...maxChapter {
                    scannedChapterCount += 1
                    if scannedChapterCount % 20 == 0 {
                        await Task.yield()
                    }
                    guard let verses = try? store.verses(bookId: book.bookId, chapter: chapter), !verses.isEmpty else { continue }
                    chapters.append(verses.map { VerseEntry(bookId: $0.bookId, chapter: $0.chapter, verse: $0.verse, content: $0.content) })
                }
            }
            guard !chapters.isEmpty else {
                throw IndexError.sourceUnavailable("성경 본문을 하나도 읽지 못했습니다.")
            }
            let totalVerseCount = chapters.reduce(0) { $0 + $1.count }
            guard totalVerseCount > 0 else {
                throw IndexError.sourceUnavailable("성경 본문을 하나도 읽지 못했습니다.")
            }

            // 문맥 윈도우 반경 — 같은 장 안에서 이 절 앞뒤로 몇 절씩 이어붙일지(추정치).
            let windowRadius = 2

            var records: [Record] = []
            records.reserveCapacity(totalVerseCount)
            let total = Double(totalVerseCount)
            var processedCount = 0

            for chapterVerses in chapters {
                // 책 이름을 앞에 붙여 임베딩에 "이 절이 어느 책 소속인지"를 담는다
                // (books.json 데이터만 사용).
                let bookNameKo = chapterVerses.first.flatMap { BooksProvider.shared.book(id: $0.bookId)?.nameKo }
                let prefix = bookNameKo.map { "\($0). " } ?? ""

                for (localIndex, entry) in chapterVerses.enumerated() {
                    try Task.checkCancellation()

                    // E5 비대칭 검색 규약 — 색인 대상은 "passage: " 접두사로 임베딩하고,
                    // 검색어 쪽은 `BibleSemanticSearchService`가 `embedQuery`를 쓴다.
                    let verseText = prefix + entry.content
                    let verseVector = try await EmbeddingService.embedPassage(verseText)

                    // 문맥 임베딩 — "그가 이르되"처럼 절 하나만으론 의미가 희박한
                    // 경우를 보완한다(장 경계 밖으로는 넘어가지 않음).
                    let start = max(0, localIndex - windowRadius)
                    let end = min(chapterVerses.count - 1, localIndex + windowRadius)
                    let contextContent = chapterVerses[start...end].map(\.content).joined(separator: " ")
                    let contextText = prefix + contextContent
                    let contextVector = try await EmbeddingService.embedPassage(contextText)

                    records.append(Record(
                        bookId: Int32(entry.bookId), chapter: Int32(entry.chapter), verse: Int32(entry.verse),
                        vector: verseVector, contextVector: contextVector
                    ))

                    // 매 절마다 진행률을 갱신하면 SwiftUI 리렌더가 너무 잦아질
                    // 수 있어 25개 단위(+마지막 1개)로만 콜백한다.
                    processedCount += 1
                    if processedCount % 25 == 0 || processedCount == totalVerseCount {
                        let fraction = Double(processedCount) / total
                        status = .building(progress: fraction)
                        progress(fraction)
                    }
                }
            }

            // 코퍼스 평균 벡터(`LoadedIndex` 주석 참고).
            let meanVerseVector = Self.meanVector(of: records.map(\.vector), dimension: EmbeddingService.dimension)
            let meanContextVector = Self.meanVector(of: records.map(\.contextVector), dimension: EmbeddingService.dimension)

            try write(
                records: records, translationCode: translationCode, dimension: EmbeddingService.dimension,
                meanVerseVector: meanVerseVector, meanContextVector: meanContextVector
            )
            status = .ready(verseCount: records.count, builtAt: .now)
            loadedIndex = LoadedIndex(records: records, meanVerseVector: meanVerseVector, meanContextVector: meanContextVector)
        } catch is CancellationError {
            status = .notBuilt
            throw IndexError.cancelled
        } catch let error as IndexError {
            status = .failed(error.description)
            throw error
        } catch let error as EmbeddingService.EmbeddingError {
            // `EmbeddingService`의 에러는 이미 한글 문구로 정리돼 있어 그대로 쓴다.
            let message = error.description
            status = .failed(message)
            throw IndexError.sourceUnavailable(message)
        } catch {
            // 그 외(파일 쓰기 실패 등) — 원본 에러는 콘솔에만 남기고 화면엔 일반 문구만 보인다.
            print("[EmbeddingIndexingService] 색인 생성 실패(원본 에러, 콘솔 전용): \(error)")
            let message = "색인 생성 중 문제가 발생했습니다."
            status = .failed(message)
            throw IndexError.sourceUnavailable(message)
        }
    }

    private func write(
        records: [Record], translationCode: String, dimension: Int,
        meanVerseVector: [Float], meanContextVector: [Float]
    ) throws {
        try FileManager.default.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
        var data = Data()
        data.append(contentsOf: Self.fileMagic)
        data.append(contentsOf: VectorCoding.bytes(from: Self.fileVersion))
        let codeBytes = Array(translationCode.utf8)
        data.append(contentsOf: VectorCoding.bytes(from: UInt32(codeBytes.count)))
        data.append(contentsOf: codeBytes)
        data.append(contentsOf: VectorCoding.bytes(from: UInt32(dimension)))
        data.append(contentsOf: VectorCoding.bytes(from: UInt32(records.count)))
        data.append(contentsOf: VectorCoding.bytes(from: Date.now.timeIntervalSince1970))
        data.append(VectorCoding.data(from: meanVerseVector))
        data.append(VectorCoding.data(from: meanContextVector))
        for record in records {
            data.append(contentsOf: VectorCoding.bytes(from: record.bookId))
            data.append(contentsOf: VectorCoding.bytes(from: record.chapter))
            data.append(contentsOf: VectorCoding.bytes(from: record.verse))
            data.append(VectorCoding.data(from: record.vector))
            data.append(VectorCoding.data(from: record.contextVector))
        }
        let url = indexFileURL(translationCode: translationCode)
        try data.write(to: url, options: .atomic)
    }
}

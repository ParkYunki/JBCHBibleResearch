//
//  EmbeddingIndexingService.swift
//  JBCHBibleResearch
//
//  [2026-08-19 신설, 이후 임베딩 모델 교체] 사용자 요청 — "애플 인텔리전스로
//  텍스트를 정제하고, 방식 A — 임베딩 기반 의미검색을 한다면?" 파이프라인의
//  "색인" 단계. 번들 번역본(개역한글, `TranslationBootstrap.bundledTranslationCode`)
//  66권 31,102절 전체를 `EmbeddingService.embedPassage(_:)`(multilingual-e5-small,
//  Core ML — `EmbeddingService.swift` 상단 주석 참고)로 벡터화해 디스크에
//  저장하고, 검색 시점엔 전부 메모리로 읽어 코사인 유사도(brute-force,
//  schema.md 4장 확정 방식)로 비교한다.
//
//  ⚠️ [SwiftData/CloudKit을 쓰지 않은 이유, 의도적 설계 결정] 이전 구현
//  (README 830~925줄 기록)은 `EmbeddingChunk`라는 SwiftData `@Model`로 이 데이터를
//  CloudKit과 함께 동기화했다. 이번엔 일부러 그러지 않았다 — 이 인덱스는 (1) 번들
//  성경 원문(모든 기기에 이미 동일하게 들어있음)과 (2) 순수 계산(임베딩 모델)만으로
//  100% 재생성 가능한 파생 캐시일 뿐이고, (3) 31,102개 벡터 행을 기기마다 CloudKit
//  으로 왕복시키는 건 대역폭/저장공간 낭비이자 동기화 충돌 여지만 늘린다. 그래서
//  그냥 `Application Support`의 평범한 바이너리 파일 하나로 로컬에만 둔다 — 기기를
//  바꾸면(또는 앱을 재설치하면) 그 기기에서 한 번 더 색인하면 된다.
//
//  ⚠️ [실기기 성능 미검증] 절 31,102개를 순차로 임베딩하는 데 실제로 얼마나
//  걸리는지 이 세션은 확인할 수 없다(Xcode/실기기 없음). 그래서 진행률 콜백과
//  취소(Task 취소)를 처음부터 갖춰 사용자가 "너무 오래 걸린다"고 판단하면 중간에
//  멈출 수 있게 했다 — 이전 라운드가 같은 이유로 "장 단위(1,189개)"로 타협했던
//  것과 달리, 이번엔 원래 목표인 절 단위 그대로 시도한다. 실사용 중 너무 느리면
//  장 단위로 되돌리거나 배치 처리로 최적화하면 된다.
//

import Foundation
import BibleResearchModels

@MainActor
final class EmbeddingIndexingService {
    static let shared = EmbeddingIndexingService()

    private init() {
        refreshStatus()
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

    /// [2026-08-19 v2] 사용자 요청 — "절단위와 문맥단위 embedding으로 만들고,
    /// 검색 결과는 다시 절 단위로 표시." `vector`는 그 절 본문 하나만 임베딩한
    /// 것(정밀함, 화면 표시 단위와 정확히 일치), `contextVector`는 같은 장
    /// 안에서 앞뒤 절을 포함한 국소 문맥을 임베딩한 것(짧은 절 하나만으론
    /// 의미가 희박한 경우를 보완) — `EmbeddingIndexingService.buildIndex`
    /// 상단 주석 참고.
    struct Record {
        let bookId: Int32
        let chapter: Int32
        let verse: Int32
        let vector: [Float]
        let contextVector: [Float]
    }

    /// `ensureLoaded()`가 돌려주는 묶음. `meanVerseVector`/`meanContextVector`는
    /// 코퍼스(전체 31,102절) 벡터의 평균 — 원래 검색 시점에 이 평균을 빼고
    /// 비교하는 "중심화(centering)"에 쓰기 위해 추가했었다("all-but-the-top"류
    /// 화이트닝 기법). [2026-08-19 v3] 사용자 지시("① centering 제거")로
    /// `BibleSemanticSearchService`는 더 이상 이 값들을 검색에 쓰지 않는다 —
    /// 그래도 여기서는 계속 계산/저장한다. 이미 v1→v2로 한 번 강제 재색인을
    /// 겪었는데, 지금 이 필드를 지우려고 v2→v3로 포맷을 또 바꾸면 재색인을
    /// 또 강제하게 된다. 계산/저장 비용이 미미해서(전체 색인 시간의 대부분은
    /// Core ML 추론이 차지) 남겨두는 쪽이 낫다고 판단 — 나중에 중심화를 다시
    /// 실험해볼 여지도 남는다.
    struct LoadedIndex {
        let records: [Record]
        let meanVerseVector: [Float]
        let meanContextVector: [Float]
    }

    private(set) var status: IndexStatus = .notBuilt
    private var loadedIndex: LoadedIndex?

    private static let fileMagic: [UInt8] = Array("BVEI".utf8)
    /// [2026-08-19 v1→v2] 절 벡터 하나만 저장하던 v1 포맷에 문맥 벡터 +
    /// 코퍼스 평균 벡터 2개를 추가했다. 버전 번호를 올려서, 기존에 이미
    /// 색인을 만들어 둔 사용자 기기에서도 v1 파일은 자동으로 "다시 만들어야
    /// 함" 상태로 처리된다(`parseHeader`가 버전 불일치 시 nil을 돌려주면
    /// `refreshStatus()`가 `.notBuilt`로 판단 — 별도 마이그레이션 코드 없이도
    /// 안전하게 새 포맷으로 유도됨).
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
        // [2026-08-19 추가] 색인이 한창 만들어지는 중일 땐 아직 파일이 없는 게
        // 정상이다(끝날 때 한 번에 쓴다, `write(records:translationCode:dimension:
        // meanVerseVector:meanContextVector:)` 참고) — 그 상태에서 이 함수가
        // 호출되면(예: 화면을 나갔다 다시 들어옴) 파일이 없다는 이유로 진행률을
        // `.notBuilt`로 되돌려버리면 안 된다.
        if case .building = status { return }
        let url = indexFileURL(translationCode: TranslationBootstrap.bundledTranslationCode)
        guard let data = try? Data(contentsOf: url), let header = Self.parseHeader(data: data) else {
            status = .notBuilt
            return
        }
        status = .ready(verseCount: Int(header.count), builtAt: header.builtAt)
    }

    // MARK: - 색인 생성 작업 소유(싱글턴이 직접 들고 있음)

    private var buildTask: Task<Void, Never>?

    /// [2026-08-19] 이 Task를 `SearchViewModel`(화면이 사라지면 같이 해제될 수
    /// 있는 인스턴스)이 아니라 여기(앱 전역에서 하나뿐인 싱글턴)에 둔다 — 사용자가
    /// 색인 생성 도중 다른 화면으로 이동해도(검색 화면이 사라져도) 31,102절
    /// 임베딩 계산이 중간에 끊기지 않고 백그라운드에서 계속되도록 하기 위함이다.
    /// 이미 진행 중이면 무시한다(중복 시작 방지).
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
                // 실패/취소 원인은 `buildIndex` 내부에서 이미 `status`(.failed
                // 또는 .notBuilt)에 반영해 뒀다 — 여기선 그 최종 상태를 그대로
                // 콜백에 넘기기만 한다.
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
    /// 읽어 캐시한다. 절 벡터 + 문맥 벡터를 모두 저장해 v1 대비 용량이 약
    /// 2배(31,102개 × 384차원 × 2 × 4바이트 ≈ 95MB)로 늘었다 — 실기기에서
    /// 확인된 값은 아니다.
    func ensureLoaded() throws -> LoadedIndex {
        if let loadedIndex { return loadedIndex }
        let url = indexFileURL(translationCode: TranslationBootstrap.bundledTranslationCode)
        guard let data = try? Data(contentsOf: url) else {
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
    /// 모아뒀다가 끝에 파일 하나로 원자적으로 쓴다 — 중간에 취소되면 파일 자체를
    /// 만들지 않는다("이어서 계속하기"는 지원하지 않는다. 처음부터 다시 만드는
    /// 것으로 충분하다고 판단 — 오버엔지니어링 방지 원칙).
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
            // [2026-08-19] 장(chapter) 단위로 묶어 둔다 — 문맥(청크) 임베딩이
            // "같은 장 안에서 앞뒤 절"을 참조해야 하는데(장 경계를 넘으면
            // 안 됨), 평평한 배열 하나만으론 이웃 절을 안전하게 찾기 어렵다.
            //
            // [2026-09-03 변경] `OutlineSeedImporter.swift` 상단 주석 참고 —
            // 이 아래 이중 루프(66권 × 최대 장 수, 총 66권/약 1,189장)는 매
            // 반복마다 `store.maxChapter`/`store.verses`(동기 SQLite 조회)를
            // 부르는데, 이 루프 전체가 첫 `await`(아래 절 단위 루프의
            // `EmbeddingService.embedPassage` 호출)보다 앞서 실행돼 `await` 지점이
            // 하나도 없다 — 색인이 아직 없는 첫 실행(정확히 이 함수가 온보딩과
            // 무관하게 즉시 시작되는 그 경우)에 메인 액터를 계속 붙잡을 수
            // 있었다. `OutlineSeedImporter`와 같은 방식으로, 장(chapter) 단위로
            // 일정 개수마다 한 번씩 실행을 양보한다 — 무엇을 얼마나 읽는지는
            // 그대로다.
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

            // [2026-08-19] 문맥 윈도우 반경 — 같은 장 안에서 이 절 앞뒤로 몇
            // 절씩을 이어붙여 국소 문맥을 만들지. 추정치, 나중에 조정 가능.
            let windowRadius = 2

            var records: [Record] = []
            records.reserveCapacity(totalVerseCount)
            let total = Double(totalVerseCount)
            var processedCount = 0

            for chapterVerses in chapters {
                // [2026-08-19] 규칙 기반 메타데이터 — 책 이름을 앞에 붙여
                // 임베딩에 "이 절이 어느 책 소속인지"를 명시적으로 담는다(추가
                // AI 호출 없이 이미 갖고 있는 books.json 데이터만 사용). 나중에
                // 장별 개요(ChapterOutlineDraftService 결과) 같은 더 풍부한
                // 메타데이터로 확장할 수 있다.
                let bookNameKo = chapterVerses.first.flatMap { BooksProvider.shared.book(id: $0.bookId)?.nameKo }
                let prefix = bookNameKo.map { "\($0). " } ?? ""

                for (localIndex, entry) in chapterVerses.enumerated() {
                    try Task.checkCancellation()

                    // E5 비대칭 검색 규약 — 색인 대상(성경 절)은 "passage: "
                    // 접두사로 임베딩한다(`EmbeddingService.swift` 상단 주석
                    // 참고). 검색어 쪽은 `BibleSemanticSearchService`가
                    // `embedQuery`를 쓴다.
                    let verseText = prefix + entry.content
                    let verseVector = try await EmbeddingService.embedPassage(verseText)

                    // 문맥 임베딩 — "그가 이르되"처럼 절 하나만으론 의미가
                    // 희박한 경우를 보완한다(장 경계 밖으로는 넘어가지 않음).
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

            // [2026-08-19] 코퍼스 평균 벡터 계산 — 검색 시점 중심화(centering)에
            // 쓰인다(`LoadedIndex` 상단 주석 참고).
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
            // `EmbeddingService.embed(_:)`가 던지는 에러는 이미 순수 한글
            // 문구로 정리돼 있다(그 파일 상단 "작업을 완료할 수 없습니다..."
            // 관련 주석 참고) — 그대로 쓴다.
            let message = error.description
            status = .failed(message)
            throw IndexError.sourceUnavailable(message)
        } catch {
            // 그 외(파일 쓰기 실패 등) — 원본은 콘솔에만 남기고 화면엔 영어
            // 타입명 없는 일반 문구만 보인다(EmbeddingService.swift와 같은 원칙).
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

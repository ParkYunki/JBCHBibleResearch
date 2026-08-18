import Foundation
import SwiftData

// [2026-08-09 신설] "원문 정보" 기능의 한글 뜻풀이 캐시. 사용자 결정 — "한글 뜻풀이는
// Apple 온디바이스 번역 사용하되, 최초 번역된 내용은 DB에 저장될 수 있게 할 것.
// 그 이후부터는 DB내용을 조회할것." (오픈 라이선스 한글 Strong 사전이 존재하지
// 않아 STEPBible의 영어 뜻풀이를 Apple Translation 프레임워크로 그때그때 번역하고,
// 이 모델에 캐싱해 다음부터는 재번역 없이 바로 읽는다.)
//
// 캐시 키는 Strong 번호(`strongCode`, 예: "G2316")다 — 같은 Strong 번호는 어느 절에
// 나오든 STEPBible 사전상 같은 영어 뜻풀이를 쓰므로, 절 단위가 아니라 Strong 번호
// 단위로 캐싱하면 사실상 전체 성경에서 한 번씩만 번역하면 된다(구약+신약 합쳐도
// 고유 Strong 번호는 1만 개 안팎).
//
// `sourceEnglishGloss`는 번역 시점의 영어 원문 스냅샷 — 향후 원문 데이터(OriginalText.sqlite)가
// 갱신되어 영어 뜻풀이가 바뀌면, 저장된 한글과 스냅샷을 비교해 캐시가 오래됐는지
// 판단할 수 있게 남겨 둔다(다른 값이면 재번역).
@Model
public final class StrongGlossTranslation {
    public var strongCode: String = ""
    public var sourceEnglishGloss: String = ""
    public var koreanGloss: String = ""
    public var updatedAt: Date = Date.now

    public init(
        strongCode: String,
        sourceEnglishGloss: String,
        koreanGloss: String,
        updatedAt: Date = .now
    ) {
        self.strongCode = strongCode
        self.sourceEnglishGloss = sourceEnglishGloss
        self.koreanGloss = koreanGloss
        self.updatedAt = updatedAt
    }
}

import Foundation

/// "말씀 요약" 편집기의 기본 첫 줄("YYYY.MM.dd 말씀") 계산을 한곳에 모은 타입.
/// 본문을 만들 때(`BibleReadingView.swift`)와 닫을 때 그 문구뿐인지 확인하는 자리
/// (`WordSummaryEditorView.swift`)가 정확히 같은 문자열을 써야 하므로 공유한다.
///
/// 레코드의 고정된 `createdAt`만 기준으로 계산하며 view의 `@State` 스냅샷에 의존하지
/// 않는다 — 화면이 다시 그려질 때 스냅샷이 사용자 입력 내용으로 잘못 재캡처되는 문제를 피한다.
public enum WordSummaryDefaultSeed {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()

    /// "말씀 요약" 편집기를 처음 열 때 채워주는 기본 문구(앱 언어로 지역화).
    /// 패키지에는 리소스 번들이 없으므로 앱 번들(`.main`)의 String Catalog를 쓴다.
    public static func text(for date: Date) -> String {
        String(localized: "\(dateFormatter.string(from: date)) 말씀", bundle: .main)
    }

    /// `text`가 이 날짜의 기본 문구 그대로인지. 앱 언어를 바꾼 뒤에도 이전에(한국어로) 채워진
    /// 기본 문구를 알아보도록 지역화 이전의 한국어 원문도 함께 비교한다.
    public static func isSeedText(_ text: String, for date: Date) -> Bool {
        text == self.text(for: date) || text == "\(dateFormatter.string(from: date)) 말씀"
    }
}

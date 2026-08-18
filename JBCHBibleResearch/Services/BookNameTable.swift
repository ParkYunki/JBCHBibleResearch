//
//  BookNameTable.swift
//  JBCHBibleResearch
//
//  2026-08-06: 사용자가 이전에 만들어 쓰던 앱(BibleSeminarPresentationForIOS)의
//  TranslationInfo.swift(원래는 macOS BibleAutofill 프로젝트의 BibleBookInfo.swift /
//  BibleDBManager.swift를 이식한 것)에서 `BookNameTable`과 내장 9개 언어 이름표를
//  거의 그대로 가져왔다. 배경: 사용자 추가 번역본(user-added translation) SQLite
//  파일은 대부분 책 이름이 안 들어있고 book_id(정수)만 있어서, 어느 언어로 책 이름을
//  보여줄지 알 수 없다 — 이 이름표가 그 문제를 해결한다.
//
//  [원본 대비 조정한 부분]
//   - 원본은 책 이름을 book_id가 아니라 "한글 이름 문자열"로 관리하는 다른 스키마
//     (macOS BibleAutofill) 대비 macOS/iOS 차이를 설명하는 주석이 있었는데, 이
//     프로젝트는 애초에 BooksProvider/BibleReferenceStore가 book_id(1~66,
//     books.json의 bookId와 매칭)로만 다루므로 그 비교 설명은 걷어냈다.
//   - `TranslationInfo`(번역본 값 타입)는 이 프로젝트엔 이미 SwiftData
//     `TranslationRegistry`(BibleResearchModels)가 그 역할을 하고 있어 새로 만들지
//     않았다. 대신 `TranslationRegistry.bookNameTableID: String?` 필드를 추가해
//     원본의 `TranslationInfo.bookNameTableID`와 같은 역할을 하게 했다
//     (TranslationRegistry.swift 참고).
//   - `nonisolated` 표시는 원본이 겪은 실제 버그(프로젝트의 기본 액터 격리 설정
//     때문에 static 멤버가 의도치 않게 MainActor에 격리돼 컴파일 에러가 났던 것)에
//     대한 방어이므로 그대로 유지했다 — 이 프로젝트가 같은 빌드 설정을 쓰는지
//     확인하지 못했지만, 그대로 둬도 해가 없고(순수 Codable 값 타입이라 애초에
//     액터 격리가 필요 없음) 원본이 이미 실전에서 검증한 해법이라 유지하는 쪽을
//     택했다.
//
//  ⚠️ [출처 신뢰도, 원본 주석 그대로 승계] 이 데이터는 macOS BibleAutofill
//  프로젝트에서 이미 검증되어 쓰이던 값을 옮긴 것이다 — 새로 추측해서 채운 값이
//  아니다. 영어=확신 높음(전 세계 공통 표준 표기) / 태국어·몽골어=단일 출처 확인
//  (각각 bible.eu, mongol.bible) / 스페인어·독일어·이탈리아어·일본어·타갈로그=
//  fullNames+shortNames 확보 / 네팔어=fullNames만 확보, shortNames는 비어 있음.
//

import Foundation

/// 성경 66권 책이름을 언어 단위로 묶은 이름표. 여러 번역본이 이름표 하나를 공유할
/// 수 있다(번역본마다 이름을 반복 저장하지 않기 위함).
nonisolated struct BookNameTable: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var displayName: String
    var isBuiltIn: Bool
    var fullNames: [String]   // 66개, books.json(정경 순서)과 동일한 순서(index 1...66 ↔ 배열 0-based)
    var shortNames: [String]  // 66개, 공식 약어가 없으면 빈 문자열

    // 중첩 타입도 별도의 격리 추론 대상이라, 바깥 struct와 별개로 nonisolated를 명시한다.
    nonisolated enum BuiltInBookNameTable {
        static let english = "lang.en"
        static let thai = "lang.th"
        static let mongolian = "lang.mn"
        static let nepali = "lang.ne"
        static let tagalog = "lang.tl"
        static let spanish = "lang.es"
        static let german = "lang.de"
        static let italian = "lang.it"
        static let japanese = "lang.ja"
    }

    /// 내장 이름표 9종.
    static func builtInBookNameTables() -> [BookNameTable] {
        [
            // 영어 — 전 세계 공통 표준 표기 (확신 높음, 별도 출처 확인 불필요)
            BookNameTable(
                id: BuiltInBookNameTable.english, displayName: "영어", isBuiltIn: true,
                fullNames: [
                    "Genesis","Exodus","Leviticus","Numbers","Deuteronomy","Joshua","Judges","Ruth",
                    "1 Samuel","2 Samuel","1 Kings","2 Kings","1 Chronicles","2 Chronicles","Ezra","Nehemiah",
                    "Esther","Job","Psalms","Proverbs","Ecclesiastes","Song of Solomon","Isaiah","Jeremiah",
                    "Lamentations","Ezekiel","Daniel","Hosea","Joel","Amos","Obadiah","Jonah","Micah","Nahum",
                    "Habakkuk","Zephaniah","Haggai","Zechariah","Malachi",
                    "Matthew","Mark","Luke","John","Acts","Romans","1 Corinthians","2 Corinthians","Galatians",
                    "Ephesians","Philippians","Colossians","1 Thessalonians","2 Thessalonians","1 Timothy",
                    "2 Timothy","Titus","Philemon","Hebrews","James","1 Peter","2 Peter","1 John","2 John",
                    "3 John","Jude","Revelation"
                ],
                // 널리 쓰이는 관용 약어(예: SBL/일반 출판물 스타일) — "공식 표준"은 아니라 참고용이다.
                shortNames: [
                    "Gen","Exod","Lev","Num","Deut","Josh","Judg","Ruth","1Sam","2Sam","1Kgs","2Kgs","1Chr",
                    "2Chr","Ezra","Neh","Esth","Job","Ps","Prov","Eccl","Song","Isa","Jer","Lam","Ezek","Dan",
                    "Hos","Joel","Amos","Obad","Jonah","Mic","Nah","Hab","Zeph","Hag","Zech","Mal","Matt","Mark",
                    "Luke","John","Acts","Rom","1Cor","2Cor","Gal","Eph","Phil","Col","1Thess","2Thess","1Tim",
                    "2Tim","Titus","Phlm","Heb","Jas","1Pet","2Pet","1John","2John","3John","Jude","Rev"
                ]
            ),
            // 태국어 — 출처: bible.eu (Thai New Contemporary Bible) 66권 목록 확인.
            // ⚠️ 단일 출처이며, 공식 약어 체계를 확인하지 못해 shortNames는 비워둔다.
            BookNameTable(
                id: BuiltInBookNameTable.thai, displayName: "태국어", isBuiltIn: true,
                fullNames: [
                    "ปฐมกาล","อพยพ","เลวีนิติ","กันดารวิถี","เฉลยธรรมบัญญัติ","โยชูวา","ผู้วินิจฉัย","นางรูธ",
                    "1 ซามูเอล","2 ซามูเอล","1 พงศ์กษัตริย์","2 พงศ์กษัตริย์","1 พงศาวดาร","2 พงศาวดาร","เอสรา","เนหะมีย์",
                    "เอสเธอร์","โยบ","สดุดี","สุภาษิต","ปัญญาจารย์","เพลงโซโลมอน","อิสยาห์","เยเรมีย์",
                    "เพลงคร่ำครวญ","เอเสเคียล","ดาเนียล","โฮเชยา","โยเอล","อาโมส","โอบาดีห์","โยนาห์","มีคาห์","นาฮูม",
                    "ฮาบากุก","เศฟันยาห์","ฮักกัย","เศคาริยาห์","มาลาคี",
                    "มัทธิว","มาระโก","ลูกา","ยอห์น","กิจการของอัครทูต","โรม","1 โครินธ์","2 โครินธ์","กาลาเทีย",
                    "เอเฟซัส","ฟีลิปปี","โคโลสี","1 เธสะโลนิกา","2 เธสะโลนิกา","1 ทิโมธี","2 ทิโมธี","ทิตัส","ฟีเลโมน",
                    "ฮีบรู","ยากอบ","1 เปโตร","2 เปโตร","1 ยอห์น","2 ยอห์น","3 ยอห์น","ยูดา","วิวรณ์"
                ],
                shortNames: Array(repeating: "", count: 66)
            ),
            // 몽골어 — 출처: mongol.bible (Ariun Nom, AB2013 번역본) 66권 목록 확인.
            // ⚠️ 단일 출처이며, 공식 약어 체계를 확인하지 못해 shortNames는 비워둔다.
            BookNameTable(
                id: BuiltInBookNameTable.mongolian, displayName: "몽골어", isBuiltIn: true,
                fullNames: [
                    "Эхлэл","Гэтлэл","Леви","Тооллого","Дэд хууль","Иошуа","Шүүгчид","Рут",
                    "1 Самуел","2 Самуел","1 Хаад","2 Хаад","1 Шастир","2 Шастир","Езра","Нехемиа",
                    "Естер","Иов","Дуулал","Сургаалт үгс","Номлогчийн үгс","Соломоны дуун","Исаиа","Иеремиа",
                    "Гашуудал","Езекиел","Даниел","Хосеа","Иоел","Амос","Обадиа","Иона","Мика","Нахум",
                    "Хабаккук","Зефаниа","Хаггаи","Зехариа","Малахи",
                    "Матай","Марк","Лук","Иохан","Үйлс","Ром","1 Коринт","2 Коринт","Галат",
                    "Ефес","Филиппой","Колоссай","1 Тесалоник","2 Тесалоник","1 Тимот","2 Тимот","Тит","Филемон",
                    "Еврей","Иаков","1 Петр","2 Петр","1 Иохан","2 Иохан","3 Иохан","Иуда","Илчлэл"
                ],
                shortNames: Array(repeating: "", count: 66)
            ),
            // 아래 두 언어(네팔어, 필리핀어/타갈로그)와 네 언어(스페인어/독일어/이탈리아어/일본어)는
            // 신뢰할 만한 출처로 66권 전체를 검증한 원본 데이터를 그대로 옮긴 것이다.
            BookNameTable(
                id: BuiltInBookNameTable.nepali, displayName: "네팔어", isBuiltIn: true,
                fullNames: [
                    "उत्पत्तिको पुस्तक", "प्रस्थानको पुस्तक", "लेवीहरूको पुस्तक", "गन्तीको पुस्तक", "व्यवस्था", "यहोशू", "न्यायकर्ताहरू",
                    "रूत", "१ शमूएल", "२ शमूएल", "१ राजाहरू", "२ राजाहरू", "१ इतिहास", "२ इतिहास", "एज्रा", "नहेम्याह",
                    "एस्तर", "अय्यूब", "भजनसंग्रह", "हितोपदेश", "उपदेशक", "श्रेष्ठगीत", "यशैया", "यर्मिया", "विलाप", "इजकिएल",
                    "दानियल", "होशे", "योएल", "आमोस", "ओबदिया", "योना", "मीका", "नहूम", "हबकूक", "सपन्याह", "हाग्गै",
                    "जकरिया", "मलाकी", "मत्ती", "मर्कूस", "लूका", "यूहन्ना", "प्रेरितहरूका काम", "रोमी", "१ कोरिन्थी", "२ कोरिन्थी",
                    "गलाती", "एफिसी", "फिलिप्पी", "कलस्सी", "१ थिस्सलोनिकी", "२ थिस्सलोनिकी", "१ तिमोथी", "२ तिमोथी",
                    "तीतस", "फिलेमोन", "हिब्रू", "याकूब", "१ पत्रुस", "२ पत्रुस", "१ यूहन्ना", "२ यूहन्ना", "३ यूहन्ना", "यहूदा", "प्रकाश"
                ],
                shortNames: Array(repeating: "", count: 66)),
            BookNameTable(
                id: BuiltInBookNameTable.tagalog, displayName: "필리핀어(타갈로그)", isBuiltIn: true,
                fullNames: [
                     "Genesis", "Exodo", "Levitico", "Mga Bilang", "Deuteronomio", "Josue", "Mga Hukom", "Ruth",
                     "1 Samuel", "2 Samuel", "1 Mga Hari", "2 Mga Hari", "1 Mga Cronica", "2 Mga Cronica", "Ezra",
                     "Nehemias", "Ester", "Job", "Mga Awit", "Mga Kawikaan", "Ang Mangangaral", "Ang Awit ni Solomon",
                     "Isaias", "Jeremias", "Mga Panaghoy", "Ezekiel", "Daniel", "Hosea", "Joel", "Amos", "Obadias",
                     "Jonas", "Mikas", "Nahum", "Habacuc", "Zefanias", "Hagai", "Zacarias", "Malakias", "Mateo",
                     "Marcos", "Lucas", "Juan", "Mga Gawa", "Mga Taga-Roma", "1 Mga Taga-Corinto",
                     "2 Mga Taga-Corinto", "Mga Taga-Galacia", "Mga Taga-Efeso", "Mga Taga-Filipos",
                     "Mga Taga-Colosas", "1 Mga Taga-Tesalonica", "2 Mga Taga-Tesalonica", "1 Timoteo",
                     "2 Timoteo", "Tito", "Filemon", "Mga Hebreo", "Santiago", "1 Pedro", "2 Pedro",
                     "1 Juan", "2 Juan", "3 Juan", "Judas", "Pahayag"
                ],
                shortNames: Array(repeating: "", count: 66)),
            BookNameTable(
                id: BuiltInBookNameTable.spanish, displayName: "스페인어", isBuiltIn: true,
                fullNames: [
                    "Génesis", "Éxodo", "Levítico", "Números", "Deuteronomio", "Josué", "Jueces", "Rut",
                    "1 Samuel", "2 Samuel", "1 Reyes", "2 Reyes", "1 Crónicas", "2 Crónicas", "Esdras",
                    "Nehemías", "Ester", "Job", "Salmos", "Proverbios", "Eclesiastés", "Cantares", "Isaías",
                    "Jeremías", "Lamentaciones", "Ezequiel", "Daniel", "Oseas", "Joel", "Amós", "Abdías",
                    "Jonás", "Miqueas", "Nahúm", "Habacuc", "Sofonías", "Hageo", "Zacarías", "Malaquías",
                    "Mateo", "Marcos", "Lucas", "Juan", "Hechos", "Romanos", "1 Corintios", "2 Corintios",
                    "Gálatas", "Efesios", "Filipenses", "Colosenses", "1 Tesalonicenses", "2 Tesalonicenses",
                    "1 Timoteo", "2 Timoteo", "Tito", "Filemón", "Hebreos", "Santiago", "1 Pedro", "2 Pedro",
                    "1 Juan", "2 Juan", "3 Juan", "Judas", "Apocalipsis"
                ],
                shortNames: [
                    "Gén", "Éxo", "Lev", "Núm", "Deut", "Jos", "Jue", "Rut", "1 Sam", "2 Sam", "1 Rey", "2 Rey",
                    "1 Crón", "2 Crón", "Esd", "Neh", "Est", "Job", "Sal", "Prov", "Ecl", "Cant", "Isa", "Jer",
                    "Lam", "Eze", "Dan", "Os", "Joel", "Am", "Abd", "Jon", "Miq", "Nah", "Hab", "Sof", "Hag",
                    "Zac", "Mal", "Mat", "Mar", "Luc", "Jn", "Hch", "Rom", "1 Cor", "2 Cor", "Gál", "Ef",
                    "Fil", "Col", "1 Tes", "2 Tes", "1 Tim", "2 Tim", "Tit", "Flm", "Heb", "Stg", "1 Pe", "2 Pe",
                    "1 Jn", "2 Jn", "3 Jn", "Jud", "Ap"
                ]),
            BookNameTable(
                id: BuiltInBookNameTable.german, displayName: "독일어", isBuiltIn: true,
                fullNames: [
                    "Genesis", "Exodus", "Levitikus", "Numeri", "Deuteronomium", "Josua", "Richter", "Rut",
                    "1 Samuel", "2 Samuel", "1 Könige", "2 Könige", "1 Chronik", "2 Chronik", "Esra", "Nehemia",
                    "Ester", "Hiob", "Psalmen", "Sprüche", "Prediger", "Hoheslied", "Jesaja", "Jeremia",
                    "Klagelieder", "Ezechiel", "Daniel", "Hosea", "Joel", "Amos", "Obadja", "Jona", "Micha",
                    "Nahum", "Habakuk", "Zefanja", "Haggai", "Sacharja", "Maleachi", "Matthäus", "Markus",
                    "Lukas", "Johannes", "Apostelgeschichte", "Römer", "1 Korinther", "2 Korinther", "Galater",
                    "Epheser", "Philipper", "Kolosser", "1 Thessalonicher", "2 Thessalonicher",
                    "1 Timotheus", "2 Timotheus", "Titus", "Philemon", "Hebräer", "Jakobus", "1 Petrus", "2 Petrus",
                    "1 Johannes", "2 Johannes", "3 Johannes", "Judas", "Offenbarung"
                ],
                shortNames: [
                    "Gen", "Ex", "Lev", "Num", "Dtn", "Jos", "Ri", "Rut", "1 Sam", "2 Sam", "1 Kön",
                    "2 Kön", "1 Chr", "2 Chr", "Esr", "Neh", "Est", "Hi", "Ps", "Spr", "Pred", "Hld",
                    "Jes", "Jer", "Klgl", "Hes", "Dan", "Hos", "Joel", "Am", "Obd", "Jona", "Mi", "Nah",
                    "Hab", "Zef", "Hag", "Sach", "Mal", "Mt", "Mk", "Lk", "Joh", "Apg", "Röm",
                    "1 Kor", "2 Kor", "Gal", "Eph", "Phil", "Kol", "1 Thess", "2 Thess", "1 Tim", "2 Tim",
                    "Tit", "Phlm", "Hebr", "Jak", "1 Petr", "2 Petr", "1 Joh", "2 Joh", "3 Joh", "Jud", "Offb"
                ]),
            BookNameTable(
                id: BuiltInBookNameTable.italian, displayName: "이탈리아어", isBuiltIn: true,
                fullNames: [
                    "Genesi", "Esodo", "Levitico", "Numeri", "Deuteronomio", "Giosuè", "Giudici", "Rut",
                    "1 Samuele", "2 Samuele", "1 Re", "2 Re", "1 Cronache", "2 Cronache", "Esdra", "Neemia",
                    "Ester", "Giobbe", "Salmi", "Proverbi", "Ecclesiaste", "Cantico dei Cantici", "Isaia",
                    "Geremia", "Lamentazioni", "Ezechiele", "Daniele", "Osea", "Gioele", "Amos", "Abdia",
                    "Giona", "Michea", "Naum", "Abacuc", "Sofonia", "Aggeo", "Zaccaria", "Malachia",
                    "Matteo", "Marco", "Luca", "Giovanni", "Atti degli Apostoli", "Romani",
                    "1 Corinzi", "2 Corinzi", "Galati", "Efesini", "Filippesi", "Colossesi",
                    "1 Tessalonicesi", "2 Tessalonicesi", "1 Timoteo", "2 Timoteo", "Tito", "Filemone",
                    "Ebrei", "Giacomo", "1 Pietro", "2 Pietro", "1 Giovanni", "2 Giovanni", "3 Giovanni",
                    "Giuda", "Apocalisse"
                ],
                shortNames: [
                    "Gen", "Es", "Lev", "Num", "Deut", "Gios", "Giud", "Rut", "1 Sam", "2 Sam", "1 Re", "2 Re",
                    "1 Cron", "2 Cron", "Esd", "Ne", "Est", "Gb", "Sal", "Prov", "Ec", "Cant", "Is", "Ger",
                    "Lam", "Ez", "Dan", "Os", "Gio", "Am", "Abd", "Gion", "Mi", "Na", "Ab", "Sof", "Ag", "Zac",
                    "Mal", "Mt", "Mc", "Lc", "Gv", "At", "Ro", "1 Cor", "2 Cor", "Gal", "Ef", "Fil", "Col",
                    "1 Ts", "2 Ts", "1 Tm", "2 Tm", "Tt", "Fm", "Eb", "Gc", "1 Pt", "2 Pt", "1 Gv", "2 Gv", "3 Gv",
                    "Gd", "Ap"
                ]),
            BookNameTable(
                id: BuiltInBookNameTable.japanese, displayName: "일본어", isBuiltIn: true,
                fullNames: [
                    "創世記", "出エジプト記", "レビ記", "民数記", "申命記", "ヨシュア記", "士師記", "ルツ記", "サムエル記 第一",
                    "サムエル記 第二", "列王記 第一", "列王記 第二", "歴代誌 第一", "歴代誌 第二", "エズラ記", "ネヘミヤ記", "エステル記",
                    "ヨブ記", "詩篇", "箴言", "伝道者の書", "雅歌", "イザヤ書", "エレミヤ書", "哀歌", "エゼキエル書", "ダニエル書",
                    "ホセア書", "ヨエル書", "アモス書", "オバデヤ書", "ヨナ書", "ミカ書", "ナホム書", "ハバクク書", "ゼパニヤ書",
                    "ハガイ書", "ゼカリヤ書", "マラキ書", "マタイの福音書", "マルコの福音書", "ルカの福音書", "ヨハネの福音書", "使徒の働き",
                    "ローマ人への手紙", "コリント人への手紙 第一", "コリント人への手紙 第二", "ガラテヤ人への手紙", "エペソ人への手紙",
                    "ピリピ人への手紙", "コロサイ人への手紙", "テサロニケ人への手紙 第一", "テサロニケ人への手紙 第二", "テモテへの手紙 第一",
                    "テモテへの手紙 第二", "テトスへの手紙", "ピレモンへの手紙", "ヘブル人への手紙", "ヤコブの手紙", "ペテロの手紙 第一",
                    "ペテロの手紙 第二", "ヨハネの手紙 第一", "ヨハネの手紙 第二", "ヨハネの手紙 第三", "ユダの手紙", "ヨハネの黙示録"
                ],
                shortNames: [
                    "創", "出", "レ", "民", "申", "ヨシ", "士", "ルツ", "Ⅰサム", "Ⅱサム", "Ⅰ列", "Ⅱ列", "Ⅰ歴", "Ⅱ歴",
                    "エズ", "ネヘ", "エス", "ヨブ", "詩", "箴", "伝", "雅", "イザ", "エレ", "哀", "エゼ", "ダニ", "ホセ",
                    "ヨエ", "アモ", "オバ", "ヨナ", "ミカ", "ナホ", "ハバ", "ゼパ", "ハガ", "ゼカ", "マラ", "マタ", "マコ",
                    "ルカ", "ヨハ", "使", "ロマ", "Ⅰコリ", "Ⅱコリ", "ガラ", "エペ", "ピリ", "コロ", "Ⅰテサ", "Ⅱテサ",
                    "Ⅰテモ", "Ⅱテモ", "テト", "ピレ", "ヘブ", "ヤコ", "Ⅰペテ", "Ⅱペテ", "Ⅰヨハ", "Ⅱヨハ", "Ⅲヨハ", "ユダ", "黙"
                ]),
        ]
    }
}

// MARK: - 번역본 Import 에러 (UI 표시용)
//
// 원본(TranslationImportError)을 그대로 이식. S12(번역본 관리/가져오기)에서 실제로
// 쓰기 전까지는 아직 어디서도 던지지 않는 "대기 중" 타입이다 — 지금 당장 쓰이진
// 않지만, 나중에 새로 설계하지 않도록 미리 옮겨 둔다.

enum TranslationImportError: LocalizedError, Sendable {
    case fileNotReadable(String)
    case invalidSchema(String)
    case bookNumberingMismatch(book: Int, expectedChapters: Int, foundChapters: Int)
    case migrationFailed(String)
    /// 2026-08-07 추가(S12 실제 구현 시점) — 원본에는 없던 케이스. `TranslationRegistry.code`가
    /// CloudKit `@Attribute(.unique)`를 못 쓰는 것과 같은 이유(README "CloudKit 제약 적용" 절)로
    /// DB 레벨 중복 방지가 불가능해, import 서비스가 저장 전에 직접 검사하고 이 에러로 알린다.
    case duplicateCode(String)
    /// 2026-08-07 추가 — 표시 이름/코드를 비워 둔 채 가져오기를 누른 경우.
    case missingRequiredField(String)

    var errorDescription: String? {
        switch self {
        case .fileNotReadable(let msg):
            return "파일을 열 수 없습니다: \(msg)"
        case .invalidSchema(let msg):
            return "예상한 성경 데이터베이스 형식이 아닙니다: \(msg)"
        case .bookNumberingMismatch(let book, let expected, let found):
            return "책 번호 \(book)의 장 수(\(found)장)가 표준 성경 구조(\(expected)장)와 다릅니다.\n이 파일의 책 번호 체계가 앱이 가정하는 정경 순서와 다를 수 있습니다."
        case .migrationFailed(let msg):
            return "번역본 가져오기 중 오류가 발생했습니다: \(msg)"
        case .duplicateCode(let code):
            return "이미 등록된 번역본 코드입니다: \(code)"
        case .missingRequiredField(let field):
            return "\(field)을(를) 입력해 주세요."
        }
    }
}

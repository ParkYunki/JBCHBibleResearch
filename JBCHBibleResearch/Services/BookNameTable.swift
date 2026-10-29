//
//  BookNameTable.swift
//  JBCHBibleResearch
//
//  내장 15개 언어 책 이름표(`BookNameTable`). 사용자 추가 번역본 SQLite는 대부분 책 이름 없이
//  book_id(정수)만 있어 어느 언어로 이름을 보여줄지 알 수 없는데, 이 이름표가 그 문제를
//  해결한다. `TranslationRegistry.bookNameTableID`가 사용할 이름표를 가리킨다.
//
//  `nonisolated`는 프로젝트 기본 액터 격리 설정 때문에 static 멤버가 의도치 않게 MainActor로
//  격리되는 것을 막기 위한 것이다(순수 Codable 값 타입이라 액터 격리가 필요 없음).
//
//  ⚠️ 출처 신뢰도: 영어=전 세계 공통 표준 표기 / 태국어·몽골어=단일 출처 확인(각각 bible.eu,
//  mongol.bible) / 스페인어·독일어·이탈리아어·일본어·타갈로그=fullNames+shortNames 확보 /
//  네팔어=fullNames만 확보, shortNames는 비어 있음.
//  [2026-10-29 booklabel2] 프랑스어·중국어 간체/번체·포르투갈어·러시아어 shortNames를 채웠다(출처는 각 표 주석).
//  태국어·몽골어·네팔어·타갈로그·베트남어는 출처를 확정하지 못해 계속 비어 있다(표시는 fullNames로 폴백).
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
        static let french = "lang.fr"
        static let chineseSimplified = "lang.zh-Hans"
        static let chineseTraditional = "lang.zh-Hant"
        static let portuguese = "lang.pt"
        static let russian = "lang.ru"
        static let vietnamese = "lang.vi"
    }

    /// 내장 이름표 15종(2026-10-11 i18n으로 프랑스어·중국어 간체/번체·포르투갈어·러시아어·베트남어 추가).
    static func builtInBookNameTables() -> [BookNameTable] {
        [
            // 영어 — 전 세계 공통 표준 표기 (확신 높음, 별도 출처 확인 불필요)
            BookNameTable(
                id: BuiltInBookNameTable.english, displayName: String(localized: "영어"), isBuiltIn: true,
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
                id: BuiltInBookNameTable.thai, displayName: String(localized: "태국어"), isBuiltIn: true,
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
                id: BuiltInBookNameTable.mongolian, displayName: String(localized: "몽골어"), isBuiltIn: true,
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
            // 네팔어·타갈로그·스페인어·독일어·이탈리아어·일본어는 66권 전체를 검증한 데이터다.
            BookNameTable(
                id: BuiltInBookNameTable.nepali, displayName: String(localized: "네팔어"), isBuiltIn: true,
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
                id: BuiltInBookNameTable.tagalog, displayName: String(localized: "필리핀어(타갈로그)"), isBuiltIn: true,
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
                id: BuiltInBookNameTable.spanish, displayName: String(localized: "스페인어"), isBuiltIn: true,
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
                id: BuiltInBookNameTable.german, displayName: String(localized: "독일어"), isBuiltIn: true,
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
                id: BuiltInBookNameTable.italian, displayName: String(localized: "이탈리아어"), isBuiltIn: true,
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
                id: BuiltInBookNameTable.japanese, displayName: String(localized: "일본어"), isBuiltIn: true,
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
            // [2026-10-11 i18n] 출처: getbible v2 darby (French Darby, Public Domain). 스크립트로 원본 파일에서 추출(수기 입력 아님).
            // [2026-10-29 booklabel2] shortNames 출처: La Bible Segond 21 (Société Biblique de Genève, 2007) 약어표.
            // 숫자와 약칭은 영어 이름표처럼 붙여 쓴다("1S", "1Jn").
            BookNameTable(
                id: BuiltInBookNameTable.french, displayName: String(localized: "프랑스어"), isBuiltIn: true,
                fullNames: [
                    "Genèse", "Exode", "Lévitique", "Nombres", "Deutéronome", "Josué", "Juges", "Ruth", "1 Samuel",
                    "2 Samuel", "1 Rois", "2 Rois", "1 Chroniques", "2 Chroniques", "Esdras", "Néhémie", "Esther",
                    "Job", "Psaumes", "Proverbes", "Ecclésiaste", "Cantique des Cantiques", "Ésaïe", "Jérémie",
                    "Lamentations", "Ézéchiel", "Daniel", "Osée", "Joël", "Amos", "Abdias", "Jonas", "Michée", "Nahum",
                    "Habacuc", "Sophonie", "Aggée", "Zacharie", "Malachie", "Matthieu", "Marc", "Luc", "Jean",
                    "Actes des Apôtres", "Romains", "1 Corinthiens", "2 Corinthiens", "Galates", "Éphésiens",
                    "Philippiens", "Colossiens", "1 Thessaloniciens", "2 Thessaloniciens", "1 Timothée", "2 Timothée",
                    "Tite", "Philémon", "Hébreux", "Jacques", "1 Pierre", "2 Pierre", "1 Jean", "2 Jean", "3 Jean",
                    "Jude", "Apocalypse"
                ],
                shortNames: [
                    "Gn", "Ex", "Lv", "Nb", "Dt", "Jos", "Jg", "Rt", "1S", "2S", "1R", "2R", "1Ch", "2Ch", "Esd",
                    "Né", "Est", "Jb", "Ps", "Pr", "Ec", "Ct", "Es", "Jr", "Lm", "Ez", "Dn", "Os", "Jl", "Am", "Ab",
                    "Jon", "Mi", "Na", "Ha", "So", "Ag", "Za", "Ml", "Mt", "Mc", "Lc", "Jn", "Ac", "Rm", "1Co",
                    "2Co", "Ga", "Ep", "Ph", "Col", "1Th", "2Th", "1Tm", "2Tm", "Tt", "Phm", "Hé", "Jc", "1P", "2P",
                    "1Jn", "2Jn", "3Jn", "Jd", "Ap"
                ]),
            // [2026-10-11 i18n] 출처: open-bibles chi-cuv-simp (Chinese Union Version, Public Domain). 스크립트로 원본 파일에서 추출(수기 입력 아님).
            // [2026-10-29 booklabel2] shortNames 출처: 和合本 관례 약칭(信望愛 bible.fhl.net 經卷簡寫列表의 간체 대응, casgv.org 簡繁 대조표).
            BookNameTable(
                id: BuiltInBookNameTable.chineseSimplified, displayName: String(localized: "중국어(간체)"), isBuiltIn: true,
                fullNames: [
                    "创世纪", "出埃及记", "利未记", "民数记", "申命记", "约书亚记", "士师记", "路得记", "撒母耳记上", "撒母耳记下", "列王纪上", "列王纪下", "历代志上",
                    "历代志下", "以斯拉记", "尼希米记", "以斯帖记", "约伯记", "诗篇", "箴言", "传道书", "雅歌", "以赛亚书", "耶利米书", "耶利米哀歌", "以西结书",
                    "但以理书", "何西阿书", "约珥书", "阿摩司书", "俄巴底亚书", "约拿书", "弥迦书", "那鸿书", "哈巴谷书", "西番雅书", "哈该书", "撒迦利亚书",
                    "玛拉基书", "马太福音", "马可福音", "路加福音", "约翰福音", "使徒行传", "罗马书", "哥林多前书", "哥林多后书", "加拉太书", "以弗所书", "腓利比书",
                    "歌罗西书", "帖撒罗尼迦前书", "帖撒罗尼迦后书", "提摩太前书", "提摩太后书", "提多书", "腓利门书", "希伯来书", "雅各书", "彼得前书", "彼得后书",
                    "约翰壹书", "约翰贰书", "约翰参书", "犹大书", "启示录"
                ],
                shortNames: [
                    "创", "出", "利", "民", "申", "书", "士", "得", "撒上", "撒下", "王上", "王下", "代上", "代下", "拉", "尼", "斯", "伯",
                    "诗", "箴", "传", "歌", "赛", "耶", "哀", "结", "但", "何", "珥", "摩", "俄", "拿", "弥", "鸿", "哈", "番", "该",
                    "亚", "玛", "太", "可", "路", "约", "徒", "罗", "林前", "林后", "加", "弗", "腓", "西", "帖前", "帖后", "提前", "提后",
                    "多", "门", "来", "雅", "彼前", "彼后", "约一", "约二", "约三", "犹", "启"
                ]),
            // [2026-10-11 i18n] 출처: open-bibles chi-cuv (Chinese Union Version, Public Domain). 스크립트로 원본 파일에서 추출(수기 입력 아님).
            // [2026-10-29 booklabel2] shortNames 출처: 信望愛 bible.fhl.net 經卷簡寫列表(和合本). 요한1~3서는 대만 관례대로 約一·約二·約三.
            BookNameTable(
                id: BuiltInBookNameTable.chineseTraditional, displayName: String(localized: "중국어(번체)"), isBuiltIn: true,
                fullNames: [
                    "創世紀", "出埃及記", "利未記", "民數記", "申命記", "約書亞記", "士師記", "路得記", "撒母耳記上", "撒母耳記下", "列王紀上", "列王紀下", "歷代志上",
                    "歷代志下", "以斯拉記", "尼希米記", "以斯帖記", "約伯記", "詩篇", "箴言", "傳道書", "雅歌", "以賽亞書", "耶利米書", "耶利米哀歌", "以西結書",
                    "但以理書", "何西阿書", "約珥書", "阿摩司書", "俄巴底亞書", "約拿書", "彌迦書", "那鴻書", "哈巴谷書", "西番雅書", "哈該書", "撒迦利亞書",
                    "瑪拉基書", "馬太福音", "馬可福音", "路加福音", "約翰福音", "使徒行傳", "羅馬書", "哥林多前書", "哥林多後書", "加拉太書", "以弗所書", "腓利比書",
                    "歌羅西書", "帖撒羅尼迦前書", "帖撒羅尼迦後書", "提摩太前書", "提摩太後書", "提多書", "腓利門書", "希伯來書", "雅各書", "彼得前書", "彼得後書",
                    "約翰壹書", "約翰貳書", "約翰參書", "猶大書", "啟示錄"
                ],
                shortNames: [
                    "創", "出", "利", "民", "申", "書", "士", "得", "撒上", "撒下", "王上", "王下", "代上", "代下", "拉", "尼", "斯", "伯",
                    "詩", "箴", "傳", "歌", "賽", "耶", "哀", "結", "但", "何", "珥", "摩", "俄", "拿", "彌", "鴻", "哈", "番", "該",
                    "亞", "瑪", "太", "可", "路", "約", "徒", "羅", "林前", "林後", "加", "弗", "腓", "西", "帖前", "帖後", "提前", "提後",
                    "多", "門", "來", "雅", "彼前", "彼後", "約一", "約二", "約三", "猶", "啟"
                ]),
            // [2026-10-11 i18n] 출처: open-bibles por-almeida (João Ferreira de Almeida, Public Domain). 스크립트로 원본 파일에서 추출(수기 입력 아님).
            // [2026-10-29 booklabel2] shortNames 출처: 번들 원본 BibleSources/porbrbsl_usfm.zip(Bíblia Portuguesa Mundial)의 각 책 \toc3 값을
            // 스크립트로 추출했다(외경 제외, 수기 입력 아님). fullNames(Almeida)와 출처가 다르다.
            BookNameTable(
                id: BuiltInBookNameTable.portuguese, displayName: String(localized: "포르투갈어"), isBuiltIn: true,
                fullNames: [
                    "Gênesis", "Êxodo", "Levítico", "Números", "Deuteronômio", "Josué", "Juízes", "Rute", "1 Samuel",
                    "2 Samuel", "1 Reis", "2 Reis", "1 Crônicas", "2 Crônicas", "Esdras", "Neemias", "Ester", "Jó",
                    "Salmos", "Provérbios", "Eclesiastes", "Cânticos", "Isaías", "Jeremias", "Lamentações", "Ezequiel",
                    "Daniel", "Oséias", "Joel", "Amós", "Obadias", "Jonas", "Miquéias", "Naum", "Habacuque",
                    "Sofonias", "Ageu", "Zacarias", "Malaquias", "Mateus", "Marcos", "Lucas", "João", "Atos",
                    "Romanos", "1 Coríntios", "2 Coríntios", "Gálatas", "Efésios", "Filipenses", "Colossenses",
                    "1 Tessalonicenses", "2 Tessalonicenses", "1 Timóteo", "2 Timóteo", "Tito", "Filemom", "Hebreus",
                    "Tiago", "1 Pedro", "2 Pedro", "1 João", "2 João", "3 João", "Judas", "Apocalipse"
                ],
                shortNames: [
                    "Gn", "Êxo", "Lv", "Nm", "Dt", "Jos", "Jz", "Rt", "1Sm", "2Sm", "1Rs", "2Rs", "1Cr", "2Cr", "Ed",
                    "Ne", "Est", "Jó", "Sl", "Pv", "Ecl", "Ct", "Is", "Jr", "Lm", "Ez", "Dn", "Os", "Jl", "Am",
                    "Oba", "Jn", "Mq", "Na", "Hc", "Sof", "Ageu", "Zac", "Ml", "Mt", "Mc", "Lc", "Jo", "At", "Rm",
                    "1Co", "2Co", "Gl", "Ef", "Fp", "Cl", "1Ts", "2Ts", "1Tm", "2Tm", "Tt", "Fm", "Hb", "Tg", "1Pe",
                    "2Pe", "1Jo", "2Jo", "3Jo", "Jd", "Ap"
                ]),
            // [2026-10-11 i18n] 출처: open-bibles rus-synodal (Russian Synodal Translation, Public Domain). 스크립트로 원본 파일에서 추출(수기 입력 아님).
            // [2026-10-29 booklabel2] shortNames 출처: 시노달역 관례 약칭(ru.wikipedia "Сокращения названий книг Библии",
            // azbyka.ru 약어표). 숫자와 약칭은 영어 이름표처럼 붙여 쓴다("1Цар", "1Ин").
            BookNameTable(
                id: BuiltInBookNameTable.russian, displayName: String(localized: "러시아어"), isBuiltIn: true,
                fullNames: [
                    "Бытие", "Исход", "Левит", "Числа", "Второзаконие", "Иисус Навин", "Судьи", "Руфь", "1-я Царств",
                    "2-я Царств", "3-я Царств", "4-я Царств", "1-я Паралипоменон", "2-я Паралипоменон", "Ездра",
                    "Неемия", "Есфирь", "Иов", "Псалтирь", "Притчи", "Екклесиаст", "Песнь Песней", "Исаия", "Иеремия",
                    "Плач Иеремии", "Иезекииль", "Даниил", "Осия", "Иоиль", "Амос", "Авдий", "Иона", "Михей", "Наум",
                    "Аввакум", "Софония", "Аггей", "Захария", "Малахия", "От Матфея", "От Марка", "От Луки",
                    "От Иоанна", "Деяния", "К Римлянам", "1-е Коринфянам", "2-е Коринфянам", "К Галатам", "К Ефесянам",
                    "К Филиппийцам", "К Колоссянам", "1-е Фессалоникийцам", "2-е Фессалоникийцам", "1-е Тимофею",
                    "2-е Тимофею", "К Титу", "К Филимону", "К Евреям", "Иакова", "1-е Петра", "2-е Петра",
                    "1-е Иоанна", "2-е Иоанна", "3-е Иоанна", "Иуды", "Откровение"
                ],
                shortNames: [
                    "Быт", "Исх", "Лев", "Чис", "Втор", "Нав", "Суд", "Руф", "1Цар", "2Цар", "3Цар", "4Цар", "1Пар",
                    "2Пар", "Езд", "Неем", "Есф", "Иов", "Пс", "Притч", "Еккл", "Песн", "Ис", "Иер", "Плач", "Иез",
                    "Дан", "Ос", "Иоил", "Ам", "Авд", "Ион", "Мих", "Наум", "Авв", "Соф", "Агг", "Зах", "Мал", "Мф",
                    "Мк", "Лк", "Ин", "Деян", "Рим", "1Кор", "2Кор", "Гал", "Еф", "Флп", "Кол", "1Фес", "2Фес",
                    "1Тим", "2Тим", "Тит", "Флм", "Евр", "Иак", "1Пет", "2Пет", "1Ин", "2Ин", "3Ин", "Иуд", "Откр"
                ]),
            // [2026-10-11 i18n] 출처: getbible v2 vietnamese (Vietnamese 1934, Public Domain). 스크립트로 원본 파일에서 추출(수기 입력 아님).
            // 공식 약어 체계를 확인하지 않아 shortNames는 비워 둔다(표시는 fullNames로 폴백).
            BookNameTable(
                id: BuiltInBookNameTable.vietnamese, displayName: String(localized: "베트남어"), isBuiltIn: true,
                fullNames: [
                    "Sáng Thế Ký", "Xuất Hành Ký", "Lê-vi Ký", "Số Đếm Ký", "Phục Truyền Luật Lệ Ký", "Giô-suê",
                    "Các Thủ Lãnh", "Ru-tơ", "1 Sa-mu-ên", "2 Sa-mu-ên", "1 Các Vua", "2 Các Vua", "1 Sử Ký",
                    "2 Sử Ký", "Ê-xơ-ra", "Nê-hê-mi", "Ê-xơ-tê", "Gióp", "Thi-thiên", "Châm Ngôn", "Truyền Đạo",
                    "Nhã Ca", "Ê-sai", "Giê-rê-mi", "Ai Ca", "Ê-xê-chi-ên", "Đa-ni-ên", "Hô-sêa", "Giô-ên", "A-mốt",
                    "Áp-đi-a", "Giô-na", "Mi-chê", "Na-hum", "Ha-ba-cúc", "Sô-phô-ni", "A-gê", "Xa-cha-ri",
                    "Ma-la-chi", "Ma-thi-ơ", "Mác", "Lu-ca", "Giăng", "Công Vụ Các Sứ Đồ", "Rô-ma", "1 Cô-rinh-tô",
                    "2 Cô-rinh-tô", "Ga-la-ti", "Ê-phê-sô", "Phi-líp", "Cô-lô-se", "1 Tê-sa-lô-ni-ca",
                    "2 Tê-sa-lô-ni-ca", "1 Ti-mô-thê", "2 Ti-mô-thê", "Tít", "Phi-lê-môn", "Hê-bơ-rơ", "Gia-cơ",
                    "1 Phi-rơ", "2 Phi-rơ", "1 Giăng", "2 Giăng", "3 Giăng", "Giu-đe", "Khải Huyền"
                ],
                shortNames: Array(repeating: "", count: 66)),
        ]
    }
}

// MARK: - 번역본 Import 에러 (UI 표시용)
//
// 번역본 가져오기 에러. S12(번역본 관리/가져오기)에서 실제로 쓰기 전까지는 던지는 곳이 없다.

enum TranslationImportError: LocalizedError, Sendable {
    case fileNotReadable(String)
    case invalidSchema(String)
    case bookNumberingMismatch(book: Int, expectedChapters: Int, foundChapters: Int)
    case migrationFailed(String)
    /// `TranslationRegistry.code`는 CloudKit `@Attribute(.unique)`를 못 써서 DB 레벨 중복 방지가
    /// 불가능하다. import 서비스가 저장 전에 직접 검사해 이 에러로 알린다.
    case duplicateCode(String)
    /// 표시 이름/코드를 비워 둔 채 가져오기를 누른 경우.
    case missingRequiredField(String)

    var errorDescription: String? {
        switch self {
        case .fileNotReadable(let msg):
            return String(localized: "파일을 열 수 없습니다: \(msg)")
        case .invalidSchema(let msg):
            return String(localized: "예상한 성경 데이터베이스 형식이 아닙니다: \(msg)")
        case .bookNumberingMismatch(let book, let expected, let found):
            return String(localized: "책 번호 \(book)의 장 수(\(found)장)가 표준 성경 구조(\(expected)장)와 다릅니다.\n이 파일의 책 번호 체계가 앱이 가정하는 정경 순서와 다를 수 있습니다.")
        case .migrationFailed(let msg):
            return String(localized: "번역본 가져오기 중 오류가 발생했습니다: \(msg)")
        case .duplicateCode(let code):
            return String(localized: "이미 등록된 번역본 코드입니다: \(code)")
        case .missingRequiredField(let field):
            return String(localized: "\(field)을(를) 입력해 주세요.")
        }
    }
}

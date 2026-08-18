//
//  hwp_viewer.js
//  JBCHBibleResearch
//
//  [2026-08-16 재도입] hwp_viewer.html 상단 주석 참고 — rhwp(@rhwp/core) WASM
//  파서/렌더러를 감싸는 최소 호스트 스크립트. Swift 쪽(RhwpWebViewController)이
//  WKWebView.callAsyncJavaScript로 이 파일이 window에 노출하는 두 함수만
//  호출한다.
//
//  이번 라운드의 핵심 변경 — 렌더링을 `renderPageSvg`(legacy SVG, innerHTML)에서
//  `renderPageToCanvas`(rhwp-studio 자신이 화면에 쓰는 최신 Canvas2D/PageLayerTree
//  replay 경로)로 바꿨다. hwp-swift 네이티브 뷰어보다 렌더링이 불완전하다는
//  사용자 지적에 대한 대응 — legacy SVG보다 이 경로가 실제 rhwp-studio 온라인
//  데모와 같은 렌더 파이프라인이라 완전성이 더 높을 것으로 기대한다.
//
//  rhwp.js는 npm 패키지 원본 그대로다(수정 안 함) — default export `init()`이
//  같은 폴더의 rhwp_bg.wasm을 `new URL('rhwp_bg.wasm', import.meta.url)`로
//  상대 경로 fetch한다. 그래서 이 두 파일과 rhwp_bg.wasm은 항상 같은 폴더에
//  나란히 있어야 한다(Resources/ 바로 아래, 하위 폴더 없이).

import init, { HwpDocument } from './rhwp.js';

let wasmReadyPromise = null;
let currentDocument = null;
let pageCount = 0;
/// [2026-08-16 추가] 사용자 요청 — hwp 뷰어 UI를 pdf 뷰어(돋보기 아이콘 3개:
/// 확대/축소/원본크기)와 맞추면서, 웹 뷰어에도 실제 확대/축소 기능을 붙였다.
/// `renderPageToCanvas(pageIndex, canvas, scale)`의 `scale`은 원래
/// "레티나 디스플레이 대응 배율"(devicePixelRatio) 용도였는데, 여기에 사용자
/// 배율을 곱해 같은 인자로 확대/축소까지 함께 처리한다 — Swift 쪽
/// `RhwpViewerController.zoomScale`이 `window.rhwpSetZoom(scale)`을 호출해
/// 이 값을 바꾼다.
let zoomMultiplier = 1.0;
/// [2026-08-16 변경] 사용자 요청 — "전체페이지가 다 나올 수 있도록." 원래는
/// 캔버스 하나에 현재 페이지만 그렸는데(페이지 이동 버튼도 UI 통일 요청으로
/// 이미 없앤 상태라, 여러 쪽 문서는 첫 쪽만 볼 수 있었다), 이제 pdf 뷰어처럼
/// 모든 페이지를 세로로 이어붙여 그리고 스크롤로 전체 문서를 본다 — 페이지당
/// `<canvas>` 하나씩 만들어 `hwp-page-container`에 순서대로 쌓는다.
const pageContainer = document.getElementById('hwp-page-container');
/// 문서를 열 때마다 새로 채워지는, 페이지 인덱스 순서의 캔버스 배열 —
/// 확대/축소 시엔 이 배열을 그대로 재사용해 다시 그린다(DOM 엘리먼트를 매번
/// 새로 만들지 않는다).
let pageCanvases = [];
/// [2026-08-16 추가] 가장 최근 `window.rhwpSearchText` 호출 결과(원본 매치
/// 객체 배열) — `window.rhwpGoToSearchMatch(index)`가 이 배열의 인덱스로
/// 어느 매치인지 찾는다. `rhwpLoadDocument`가 새 문서를 열 때 비운다.
let searchResults = [];

/// hwp_viewer.html의 인라인 스크립트가 등록한 `postHwpDebug`를 그대로 재사용 —
/// 이 모듈이 여기까지 실행됐다는 것 자체가 "import 자체는 성공했다"는 뜻이므로,
/// 아래 줄이 Swift 쪽 로그에 찍히는지 여부만으로도 "모듈 로딩 실패"와 "로딩은
/// 됐지만 wasm init/파싱 실패"를 구분할 수 있다.
function debugLog(text) {
  if (typeof window.postHwpDebug === 'function') {
    window.postHwpDebug(text);
  }
}
debugLog('hwp_viewer.js 모듈 로딩 및 rhwp.js import 성공 (canvas 렌더러)');

/// "모듈 로딩 및 rhwp.js import 성공"까지는 찍히는데 그 다음(wasm init
/// 성공/실패) 로그가 전혀 안 찍히는 상황을 이전 라운드에 실제로 겪었다 —
/// `init()`이 정말 실패했는데 로그만 못 남긴 건지, `fetch(rhwp_bg.wasm)`이
/// 끝까지 응답을 못 받고 멈춰 있는 건지 구분이 안 됐다. 15초 타임아웃을 걸어서,
/// 멈춰 있는 경우엔 최소한 "멈춰 있다"는 사실 자체는 확실히 알 수 있게 한다.
function withTimeout(promise, ms, label) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error(label + ' — ' + ms + 'ms 안에 끝나지 않음(타임아웃)'));
    }, ms);
    promise.then(
      (value) => { clearTimeout(timer); resolve(value); },
      (err) => { clearTimeout(timer); reject(err); }
    );
  });
}

function ensureWasmReady() {
  if (!wasmReadyPromise) {
    debugLog('rhwp wasm init() 호출 시작 (rhwp_bg.wasm 약 8MB 로딩 포함)');
    wasmReadyPromise = withTimeout(init(), 15000, 'rhwp wasm init()').then(
      (result) => {
        debugLog('rhwp wasm init() 성공');
        return result;
      },
      (err) => {
        debugLog('rhwp wasm init() 실패: ' + (err && err.message ? err.message : String(err)));
        // 실패한 채로 캐시해 두면 다음 시도도 계속 같은 실패만 반복하니,
        // 다음 호출에서 처음부터 다시 시도할 수 있게 캐시를 비운다.
        wasmReadyPromise = null;
        throw err;
      }
    );
  }
  return wasmReadyPromise;
}

function base64ToBytes(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

/// `renderPageToCanvas`가 canvas.width/height(디바이스 픽셀 backing store)를
/// "페이지 크기 × scale"로 직접 설정해 준다(rhwp.d.ts 주석) — 그래서 페이지
/// 치수를 우리가 미리 알아내 계산할 필요가 없다. scale에 devicePixelRatio를
/// 써서 Retina 디스플레이에서도 또렷하게 그리고, CSS 표시 크기(style.width/
/// height)는 그 배율만큼 다시 나눠 실제 화면 크기가 부풀지 않게 한다 — 표준
/// "retina canvas" 패턴.
///
/// [2026-08-16 변경] 현재 페이지 하나만 그리던 `renderPage(pageIndex)`를
/// 모든 페이지를 순서대로 그리는 `renderAllPages()`로 바꿨다 — 문서를 처음
/// 열 때는 페이지 수만큼 `<canvas>`를 새로 만들어 채우고, 확대/축소로 다시
/// 불릴 때는 이미 만들어진 캔버스를 재사용해 다시 그리기만 한다.
///
/// [2026-08-16 버그 수정] "확대/축소가 실제로 전혀 안 먹힌다"는 두 번째
/// 원인(CSS `max-width` 제거만으론 안 고쳐졌다) — `scale`(=devicePixelRatio
/// × zoomMultiplier)로 캔버스 backing store 크기를 키워 놓고, CSS 표시
/// 크기를 다시 그 `scale`로 나누면 `zoomMultiplier`가 분자·분모에서 그대로
/// 상쇄돼 버린다(canvas.width = pageSize × scale이므로 canvas.width / scale
/// = pageSize, 배율과 무관하게 항상 똑같은 값). "retina canvas" 패턴은
/// 원래 devicePixelRatio만 상쇄시키기 위한 것이라, 표시 크기를 나눌 때는
/// zoomMultiplier가 섞이지 않은 `pixelRatio`만 써야 한다 — backing store는
/// 여전히 `scale`(devicePixelRatio × zoomMultiplier)로 키워 화질은 유지하고,
/// CSS 크기만 devicePixelRatio로만 나눠 zoomMultiplier가 실제 레이아웃 크기에
/// 그대로 반영되게 한다.
function renderAllPages() {
  if (!currentDocument) {
    throw new Error('문서가 아직 로드되지 않았습니다.');
  }
  const pixelRatio = window.devicePixelRatio || 1;
  const scale = pixelRatio * zoomMultiplier;
  for (let i = 0; i < pageCount; i++) {
    let pageCanvas = pageCanvases[i];
    if (!pageCanvas) {
      pageCanvas = document.createElement('canvas');
      pageCanvas.className = 'hwp-page-canvas';
      pageContainer.appendChild(pageCanvas);
      pageCanvases[i] = pageCanvas;
    }
    currentDocument.renderPageToCanvas(i, pageCanvas, scale);
    pageCanvas.style.width = (pageCanvas.width / pixelRatio) + 'px';
    pageCanvas.style.height = (pageCanvas.height / pixelRatio) + 'px';
  }
}

/// 새 문서를 열기 전, 이전 문서가 만들어 둔 캔버스 엘리먼트를 전부 지운다 —
/// 안 지우면 페이지 수가 다른 문서를 연달아 열 때 이전 문서의 마지막 페이지
/// 캔버스가 그대로 남는다.
function clearPageCanvases() {
  for (const pageCanvas of pageCanvases) {
    pageCanvas.remove();
  }
  pageCanvases = [];
}

/// Swift → JS 진입점 1: base64로 인코딩된 hwp/hwpx 원본 바이트를 받아 문서를
/// 열고, 모든 페이지를 세로로 이어 그린 뒤 `{ pageCount }`를 돌려준다.
window.rhwpLoadDocument = async function (base64) {
  debugLog('rhwpLoadDocument 호출됨 (base64 길이 ' + (base64 ? base64.length : 0) + ')');
  try {
    await ensureWasmReady();
    debugLog('rhwpLoadDocument: wasm 준비 완료, 문서 파싱 시작');

    if (currentDocument) {
      // WASM 쪽 메모리는 GC 대상이 아니라 명시적으로 free()해야 한다 — 새
      // 문서를 열 때마다 이전 문서를 정리해 메모리가 계속 쌓이는 것을 막는다.
      currentDocument.free();
      currentDocument = null;
    }
    clearPageCanvases();

    const bytes = base64ToBytes(base64);
    currentDocument = new HwpDocument(bytes);
    pageCount = currentDocument.pageCount();
    zoomMultiplier = 1.0;
    searchResults = [];

    if (pageCount > 0) {
      renderAllPages();
      // [2026-08-16 추가, 사전 조사용 → 2026-08-16 실기기로 실제 응답 확인]
      // "텍스트 드래그 선택/복사" 요청 대응 — 캔버스 렌더링은 DOM에 실제
      // 텍스트가 없어 브라우저 기본 선택이 안 된다. `HwpDocument.
      // getPageTextLayout(page_num)`이 "각 TextRun의 위치, 텍스트, 글자별
      // X 좌표 경계값"을 JSON으로 준다고 문서화돼 있어(rhwp.js JSDoc), 이걸로
      // 캔버스 위에 투명한 선택 가능 텍스트 레이어를 올릴 수 있을 것으로
      // 봤다.
      //
      // 실기기 로그로 실제 응답 모양을 확인했다 — `{ runs: [...] }` 형태고,
      // 각 run은:
      //   { text, x, y, w, h, charX: [...], fontFamily, fontSize, bold,
      //     italic, ratio, letterSpacing, underline, strikethrough,
      //     textColor, charShapeId, paraShapeId, secIdx, paraIdx, charStart }
      // `x`/`y`/`w`/`h`는 px 단위로 보인다(renderPageSvg의 SVG width/height와
      // 같은 좌표계로 추정 — 페이지 제목 run 하나가 x≈75.6, y≈132.3인 걸
      // 보면 A4 페이지 상단 여백과 맞아떨어진다). `charX`는 run 시작점
      // 기준 각 글자의 상대 x 오프셋 배열이라 글자 단위로 선택 영역을 쪼갤
      // 때 그대로 쓸 수 있다. `charStart`는 이 run이 문단 전체 텍스트에서
      // 몇 번째 글자부터 시작하는지(0-based) — 검색 결과(`searchAllText`가
      // 주는 `charOffset`)와 같은 좌표계로 보여, 나중에 "검색 결과 하이라이트"
      // 도 이 레이어로 옮길 수 있을 것 같다.
      //
      // 아직 이 정보로 실제 선택 가능 텍스트 레이어(overlay)를 만들지는
      // 않았다 — 별도 요청이 오면 이 확인된 필드 그대로 오버레이를 붙인다.
      try {
        const rawLayout = currentDocument.getPageTextLayout(0);
        debugLog('getPageTextLayout(0) 원본(첫 800자): ' + String(rawLayout).slice(0, 800));
      } catch (layoutErr) {
        debugLog('getPageTextLayout(0) 호출 실패(텍스트 선택 오버레이 조사용, 문서 로딩과는 무관): ' + describeError(layoutErr));
      }
    }

    return { pageCount };
  } catch (err) {
    // WKWebView의 `callAsyncJavaScript`가 JS 예외를 던지면 Swift 쪽엔
    // "JavaScript 예외가 발생했습니다"라는 일반 문구만 남고 실제 예외 메시지를
    // 꺼낼 공식 API가 없다 — 그래서 여기서 throw하는 대신 `{ error: "..." }`를
    // 정상 반환값으로 돌려준다. Swift 쪽은 항상 이 반환값의 `error` 키를 먼저
    // 확인한다.
    return { error: describeError(err) };
  }
};

/// Swift → JS 진입점 2: [2026-08-16 변경] 모든 페이지가 항상 한 번에 그려져
/// 있으므로(위 `renderAllPages` 참고), 이제 "다시 그리기"가 아니라 해당
/// 페이지의 캔버스로 스크롤만 이동한다.
window.rhwpGoToPage = async function (pageNum) {
  try {
    const target = pageCanvases[pageNum];
    if (!target) {
      throw new Error('페이지 번호가 범위를 벗어났습니다: ' + pageNum);
    }
    target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    return { ok: true };
  } catch (err) {
    return { error: describeError(err) };
  }
};

/// Swift → JS 진입점 3: [2026-08-16 추가] 모든 페이지를 주어진 배율(1.0 = 100%)로
/// 다시 그린다 — RhwpWebViewerPane의 확대/축소/원본크기 버튼 3개가 이걸 호출한다.
window.rhwpSetZoom = async function (scale) {
  try {
    zoomMultiplier = scale;
    renderAllPages();
    return { ok: true };
  } catch (err) {
    return { error: describeError(err) };
  }
};

/// Swift → JS 진입점 4: [2026-08-16 추가] 사용자 요청 — "개요 창처럼 검색
/// 기능/검색결과/검색이동." `HwpDocument.searchAllText(query, case_sensitive,
/// include_cells)`가 매치 목록을 JSON 문자열로 돌려준다(rhwp.js 참고,
/// case_sensitive는 항상 false로, include_cells는 표 셀 안 텍스트도 찾도록
/// true로 고정한다). rhwp는 이 결과 객체의 정확한 필드 구성을 알려주는 공개
/// 타입 선언(.d.ts)이 따로 없어(Resources/에 rhwp.js만 있고 타입 선언 파일은
/// 없음), 배열 하나로 통일해 `searchResults`에 저장하고 개수만 신뢰해서
/// 돌려준다 — 각 매치의 실제 필드는 `window.rhwpGoToSearchMatch`가 쓴다.
/// 첫 매치의 원본 JSON을 디버그 채널로 남겨서, 페이지 이동이 실패하면 Xcode
/// 콘솔에서 실제 필드 이름을 확인할 수 있게 한다.
window.rhwpSearchText = async function (query) {
  try {
    if (!currentDocument) {
      throw new Error('문서가 아직 로드되지 않았습니다.');
    }
    const trimmed = (query || '').trim();
    if (!trimmed) {
      searchResults = [];
      return { count: 0 };
    }
    const raw = currentDocument.searchAllText(trimmed, false, true);
    const parsed = JSON.parse(raw);
    searchResults = Array.isArray(parsed)
      ? parsed
      : (parsed && Array.isArray(parsed.matches) ? parsed.matches : []);
    debugLog(
      'rhwpSearchText: "' + trimmed + '" → ' + searchResults.length +
      '건 (첫 매치 원본: ' + JSON.stringify(searchResults[0] || null) + ')'
    );
    return { count: searchResults.length };
  } catch (err) {
    return { error: describeError(err) };
  }
};

/// 실기기 로그로 매치 객체의 실제 필드가 `{sec, para, charOffset, length}`
/// 임을 확인했다(페이지 번호 필드는 없음) — `rhwp.js`의
/// `HwpDocument.getPageOfPosition(section_idx, para_idx)`가 "위치에 해당하는
/// 글로벌 쪽 번호 반환"이라고 문서화돼 있는 진짜 API다(page 번호를 매치
/// 객체가 직접 들고 있지 않아, 검색과 별도로 이 함수를 호출해 변환한다).
/// `@returns {string}`이라 순수 숫자 문자열("3")인지 JSON인지는 JSDoc에
/// 명시가 안 돼 있어(rhwp에 별도 .d.ts가 없음), 둘 다 시도하고 실패하면 원본
/// 응답을 디버그 로그로 남긴다.
function parsePageNumber(raw) {
  if (typeof raw === 'number') return raw;
  if (typeof raw !== 'string') return null;
  const trimmed = raw.trim();
  if (/^-?\d+$/.test(trimmed)) {
    return parseInt(trimmed, 10);
  }
  try {
    const parsed = JSON.parse(trimmed);
    if (typeof parsed === 'number') return parsed;
    if (parsed && typeof parsed === 'object') {
      for (const key of ['page', 'pageIndex', 'page_index', 'globalPage', 'global_page']) {
        if (typeof parsed[key] === 'number') return parsed[key];
      }
    }
  } catch (e) {
    // JSON도 아니면 아래에서 null 반환 → 호출부가 원본 문자열을 에러 메시지에 그대로 남긴다.
  }
  return null;
}

/// Swift → JS 진입점 5: [2026-08-16 추가] `searchResults[index]`가 있는
/// 페이지로 스크롤한다. `getPageOfPosition`으로 실제 쪽 번호를 얻어 그 쪽의
/// 캔버스로 이동한다. 텍스트 하이라이트(정확한 위치 표시)는 캔버스 렌더링이라
/// 별도 오버레이가 필요해 이번엔 페이지 스크롤까지만 구현했다.
window.rhwpGoToSearchMatch = async function (index) {
  try {
    const match = searchResults[index];
    if (!match) {
      throw new Error('검색 결과 인덱스가 범위를 벗어났습니다: ' + index);
    }
    if (typeof match.sec !== 'number' || typeof match.para !== 'number') {
      throw new Error('검색 결과에 sec/para가 없습니다: ' + JSON.stringify(match));
    }
    const rawPage = currentDocument.getPageOfPosition(match.sec, match.para);
    const pageIndex = parsePageNumber(rawPage);
    debugLog('rhwpGoToSearchMatch: sec=' + match.sec + ' para=' + match.para + ' → getPageOfPosition="' + rawPage + '" → pageIndex=' + pageIndex);
    if (pageIndex === null) {
      throw new Error('getPageOfPosition 응답을 해석하지 못했습니다: ' + JSON.stringify(rawPage));
    }
    const target = pageCanvases[pageIndex];
    if (!target) {
      throw new Error('페이지 캔버스를 찾을 수 없습니다 (인덱스 ' + pageIndex + ', 원본 응답 ' + JSON.stringify(rawPage) + ')');
    }
    target.scrollIntoView({ behavior: 'smooth', block: 'center' });
    return { ok: true };
  } catch (err) {
    return { error: describeError(err) };
  }
};

/// Swift → JS 진입점 6: [2026-08-16 추가] 사용자 요청 — "pdf 변환 탭"을
/// hwp-swift 네이티브 렌더러(기존 탭과 렌더링이 완전히 같아서 존재 이유가
/// 없다는 지적을 받음) 대신 rhwp 쪽 경로로 다시 만들기 위한 진입점이다.
/// rhwp 자신은 PDF 출력 API가 없다(edwardkim/rhwp README의 로드맵에 "다양한
/// 출력 포맷(PDF, DOCX 등)"이 아직 시작 안 한 v2.0.0 항목으로 명시돼 있음,
/// 현재 배포 버전은 v0.7.15) — 대신 있는 `HwpDocument.renderPageSvg(page_num)`
/// (rhwp.js 문서: "특정 페이지를 SVG 문자열로 렌더링")로 한 쪽씩 SVG를 뽑아
/// Swift 쪽(RhwpPDFExportService)이 오프스크린 WKWebView에 그 SVG 하나만
/// 올리고 `WKWebView.createPDF`로 그 쪽을 PDF로 바꾼다 —
/// postmelee/alhangeul-macos의 실제 PDF 내보내기가 쓰는 것과 같은 방식이다.
/// SVG의 루트 `<svg width="..” height="..">` 속성을 페이지 픽셀 크기로 그대로
/// 신뢰한다(rhwp README가 출력 단위를 "px"라고 명시) — Swift 쪽이 이 크기로
/// 오프스크린 웹뷰 프레임과 `WKPDFConfiguration.rect`를 맞춘다.
window.rhwpGetPageSvg = async function (pageIndex) {
  try {
    if (!currentDocument) {
      throw new Error('문서가 아직 로드되지 않았습니다.');
    }
    const svg = currentDocument.renderPageSvg(pageIndex);
    if (!svg || typeof svg !== 'string') {
      throw new Error('renderPageSvg가 빈 값을 반환했습니다 (페이지 ' + pageIndex + ')');
    }
    const parsed = new DOMParser().parseFromString(svg, 'image/svg+xml');
    if (parsed.querySelector('parsererror')) {
      throw new Error('renderPageSvg 결과를 SVG로 파싱하지 못했습니다 (페이지 ' + pageIndex + ')');
    }
    const root = parsed.documentElement;
    const width = parseFloat(root.getAttribute('width') || '');
    const height = parseFloat(root.getAttribute('height') || '');
    if (!width || !height || Number.isNaN(width) || Number.isNaN(height)) {
      throw new Error('SVG 루트에 width/height가 없습니다 (페이지 ' + pageIndex + ')');
    }
    return { svg, width, height };
  } catch (err) {
    return { error: describeError(err) };
  }
};

/// Swift → JS 진입점 7: [2026-08-16 추가] 사용자 지적 — hwp-swift 네이티브
/// 파서가 특정 문서를 못 여는 사례("Presentation build failed: Bytes are not
/// EOF..." — hwp-swift의 `HwpIdMappings` 버전별 필드 파싱 한계, 상세 경위는
/// DocumentTextExtractionService.swift 참고)가 실기기에서 확인돼, 텍스트
/// 추출(검색/성경구절 인덱싱용)에도 rhwp 폴백 경로가 필요해졌다.
/// `HwpDocument.getPageText(page_index)`(rhwp.js 문서: "쪽 하나의 글 —
/// 웹한글컨트롤 GetPageText")로 페이지 단위 순수 텍스트를 뽑는다 — `rhwpGetPageSvg`
/// 와 달리 화면 합성(compositing)/`createPDF` 스냅샷이 전혀 필요 없는 순수
/// JS/WASM 호출이라, 실기기에서 확인된 RunningBoard 문제(`createPDF` 근처에서
/// 발생, RhwpPDFExportService.swift 참고)에 걸릴 가능성이 그쪽보다 낮다.
window.rhwpGetPageText = async function (pageIndex) {
  try {
    if (!currentDocument) {
      throw new Error('문서가 아직 로드되지 않았습니다.');
    }
    const text = currentDocument.getPageText(pageIndex);
    return { text: typeof text === 'string' ? text : '' };
  } catch (err) {
    return { error: describeError(err) };
  }
};

/// [2026-08-16 추가] `WKNavigationDelegate.didFinish`가 이 모듈의 실행
/// 완료(=바로 위 세 `window.rhwp*` 할당)보다 먼저 올 수 있다는 게 확인돼,
/// "페이지 로딩 완료" 대신 "이 세 함수가 실제로 다 정의된 시점"을 Swift에
/// 명시적으로 알려준다 — HWPWebViewSupport.swift의
/// `makeConfiguration(onReady:)`/`HWPReadyMessageHandler` 참고. postHwpDebug와
/// 마찬가지로 브라우저에서 이 파일을 직접 열어 테스트할 때(메시지 핸들러
/// 미등록)를 대비해 try/catch로 감싼다.
try {
  window.webkit.messageHandlers.hwpViewerReady.postMessage(true);
} catch (e) {
  // 무시 — 위 postHwpDebug와 같은 이유.
}

/// JS 예외 객체(또는 문자열/기타 값)를 사람이 읽을 수 있는 문자열로 바꾼다 —
/// 위 두 진입점이 전부 이걸로 `{ error: ... }`를 만든다.
function describeError(err) {
  if (err instanceof Error) return err.message || String(err);
  if (typeof err === 'string') return err;
  try {
    return JSON.stringify(err);
  } catch (e) {
    return String(err);
  }
}

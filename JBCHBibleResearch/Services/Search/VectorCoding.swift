//
//  VectorCoding.swift
//  JBCHBibleResearch
//
//  [2026-08-19 신설] 사용자 요청 — "애플 인텔리전스로 텍스트를 정제하고, 방식 A —
//  임베딩 기반 의미검색을 한다면?" 에 대한 구현. `EmbeddingIndexingService`가
//  개역한글 31,102절의 임베딩 벡터를 디스크의 평범한 바이너리 파일 하나에 저장하는데
//  (SwiftData/CloudKit을 쓰지 않는 이유는 그 파일 상단 주석 참고), 그 파일 포맷 안에서
//  `[Float]` 벡터 하나를 바이트로 넣고 빼는 저수준 변환만 이 파일이 담당한다.
//
//  [2026-08-19 삭제 이력] 이 경로에 있던 이전 버전(같은 이름)은 `EmbeddingChunk`
//  (SwiftData 모델)의 `Data` 필드용 변환기였다 — "의미검색(AI) 기능 삭제" 요청으로
//  그 모델과 함께 지워졌다(사용자가 Xcode에서 실제로 파일을 삭제함, 이 세션은
//  파일을 지울 수 없어 대신 내용만 비워 안내만 남겨 뒀었다). 지금 이 파일은 같은
//  경로에 새로 쓴 것이지, 그 파일을 되살린 게 아니다 — 용도(SwiftData 필드 변환 →
//  바이너리 인덱스 파일 포맷)도 달라졌다.
//

import Foundation

enum VectorCoding {
    /// `[Float]` → `Data`(리틀 엔디안, 플랫폼 네이티브 바이트 순서 그대로 — 이 앱은
    /// 항상 Apple 기기에서만 쓰고 파일을 다른 아키텍처로 옮길 일이 없어 엔디안 변환은
    /// 하지 않는다).
    static func data(from vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// `Data` → `[Float]`. `count`(기대하는 원소 개수)를 명시적으로 받아 바이트 길이가
    /// 맞는지 먼저 확인한다 — 손상되거나 버전이 다른 인덱스 파일을 읽었을 때 조용히
    /// 잘못된 벡터를 만들어내는 대신 nil로 실패를 알린다.
    static func floatArray(from data: Data, count: Int) -> [Float]? {
        let expectedByteCount = count * MemoryLayout<Float>.size
        guard data.count == expectedByteCount else { return nil }
        return data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self))
        }
    }

    // MARK: - 인덱스 파일 헤더용 정수/실수 인코딩

    /// `EmbeddingIndexingService`의 바이너리 인덱스 파일은 SwiftData가 아니라
    /// 직접 설계한 평범한 포맷이라, 헤더에 들어가는 고정폭 정수/실수도 직접
    /// 인코딩한다 — `Data`에 `append(contentsOf:)`로 바로 쓸 수 있게 리틀 엔디안
    /// 바이트 배열을 돌려준다.
    static func bytes(from value: Int32) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    static func bytes(from value: UInt32) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    static func bytes(from value: Double) -> [UInt8] {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { Array($0) }
    }

    static func int32(from data: Data, at offset: Int) -> Int32? {
        guard offset + 4 <= data.count else { return nil }
        let slice = data.subdata(in: offset..<(offset + 4))
        let bitPattern = slice.withUnsafeBytes { $0.load(as: UInt32.self) }
        return Int32(bitPattern: UInt32(littleEndian: bitPattern))
    }

    static func uint32(from data: Data, at offset: Int) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        let slice = data.subdata(in: offset..<(offset + 4))
        return UInt32(littleEndian: slice.withUnsafeBytes { $0.load(as: UInt32.self) })
    }

    static func double(from data: Data, at offset: Int) -> Double? {
        guard offset + 8 <= data.count else { return nil }
        let slice = data.subdata(in: offset..<(offset + 8))
        let bitPattern = UInt64(littleEndian: slice.withUnsafeBytes { $0.load(as: UInt64.self) })
        return Double(bitPattern: bitPattern)
    }
}

//
//  VectorCoding.swift
//  JBCHBibleResearch
//
//  EmbeddingChunk.embeddingVector(Data)와 계산에 쓰는 [Float] 사이의 변환. 이 변환
//  자체는 BibleResearchModels 패키지(EmbeddingChunk가 정의된 곳)가 아니라 앱 레이어에
//  둔다 — 패키지는 "Float32 배열을 Data로 저장한다"는 스키마 규칙만 알면 되고, 그
//  Data를 실제로 어떤 알고리즘(EmbeddingService)으로 만들고 읽는지는 앱 레이어의
//  책임으로 분리했다.
//
//  ⚠️ endianness: 같은 기기에서 쓰고 같은 기기(또는 CloudKit으로 동기화된 동일
//  아키텍처의 Apple 기기)에서만 읽는다는 전제다. 모든 대상 플랫폼(macOS/iPadOS/iOS)이
//  전부 little-endian이라 실질적 위험은 없지만, 다른 바이트 순서를 가진 환경과
//  데이터를 주고받을 일은 없다고 가정했다.
//

import Foundation

extension Array where Element == Float {
    var asData: Data {
        withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

extension Data {
    var asFloatArray: [Float] {
        guard count % MemoryLayout<Float>.stride == 0 else { return [] }
        return withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self))
        }
    }
}

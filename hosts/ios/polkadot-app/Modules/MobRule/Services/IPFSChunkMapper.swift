import Foundation

enum IPFSChunkMapper {
    static func getStartChunkIndex(
        from request: IPFSDataStreamingRequest,
        chunkSize: Int
    ) -> Int {
        Int(request.startOffset) / chunkSize
    }

    static func getEndChunkIndex(
        from request: IPFSDataStreamingRequest,
        chunkSize: Int
    ) -> Int {
        Int(request.endOffset) / chunkSize
    }

    static func getChunkDataRange(
        for chunkIndex: Int,
        request: IPFSDataStreamingRequest,
        chunkSize: Int,
        resultSize: Int
    ) -> Range<Int>? {
        let startChunkIndex = getStartChunkIndex(from: request, chunkSize: chunkSize)
        let endChunkIndex = getEndChunkIndex(from: request, chunkSize: chunkSize)

        guard startChunkIndex <= endChunkIndex else {
            return nil
        }

        let currentOffset = Int64(chunkIndex * chunkSize)

        let rangeStart: Int64? =
            if chunkIndex == startChunkIndex {
                request.startOffset >= currentOffset ? request.startOffset - currentOffset : nil
            } else {
                0
            }

        let rangeEnd: Int64? =
            if chunkIndex == endChunkIndex {
                request.endOffset >= currentOffset ? request.endOffset - currentOffset + 1 : nil
            } else {
                Int64(resultSize)
            }

        if let rangeStart, let rangeEnd {
            return Int(rangeStart) ..< Int(rangeEnd)
        } else {
            return nil
        }
    }
}

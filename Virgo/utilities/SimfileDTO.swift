import Foundation

/// File text encoding as reported by the backend (`DtxFile.fileEncoding`).
enum SimfileEncoding: String, Equatable {
    case shiftJIS = "SHIFT_JIS"
    case utf8 = "UTF_8"
}

/// One difficulty chart within a simfile (`DtxFile`).
struct DtxFileDTO: Equatable {
    let label: String        // e.g. "BASIC", "EXTREME"
    let level: Double        // GraphQL Float! (scale TBD — see spec open question)
    let fileURL: String      // public R2 URL
    let fileSizeBytes: Int
    let encoding: SimfileEncoding
}

/// A catalog simfile (`Simfile`), reduced to the fields the client consumes.
struct SimfileDTO: Equatable {
    let id: String
    let title: String
    let artist: String
    let bpm: Double
    let genre: String?
    let tags: [String]
    let durationSeconds: Int?
    let updatedAt: String        // ISO-8601 string
    let dtxFiles: [DtxFileDTO]
    let fileKeys: [String]       // `Simfile.files[].key`, for audio availability
}

/// One page of catalog results (`SimfileConnection`).
struct SimfilePage: Equatable {
    let simfiles: [SimfileDTO]
    let totalCount: Int
}

/// Read-only access to the simfile catalog. Apollo lives behind this seam.
protocol SimfileFetching {
    func fetchSimfiles(page: Int, pageSize: Int, search: String?) async throws -> SimfilePage
    func fetchSimfile(id: String) async throws -> SimfileDTO?
}

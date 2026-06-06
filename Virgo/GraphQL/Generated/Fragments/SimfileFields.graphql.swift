// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

extension VirgoGraphQL {
  struct SimfileFields: VirgoGraphQL.SelectionSet, Fragment {
    static var fragmentDefinition: StaticString {
      #"fragment SimfileFields on Simfile { __typename id title artist bpm genre tags durationSeconds updatedAt dtxFiles { __typename label level fileUrl fileSizeBytes fileEncoding } files { __typename key size } }"#
    }

    let __data: DataDict
    init(_dataDict: DataDict) { __data = _dataDict }

    static var __parentType: any ApolloAPI.ParentType { VirgoGraphQL.Objects.Simfile }
    static var __selections: [ApolloAPI.Selection] { [
      .field("__typename", String.self),
      .field("id", VirgoGraphQL.ID.self),
      .field("title", String.self),
      .field("artist", String.self),
      .field("bpm", Double.self),
      .field("genre", String?.self),
      .field("tags", [String].self),
      .field("durationSeconds", Int?.self),
      .field("updatedAt", String.self),
      .field("dtxFiles", [DtxFile].self),
      .field("files", [File].self),
    ] }
    static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      SimfileFields.self
    ] }

    var id: VirgoGraphQL.ID { __data["id"] }
    var title: String { __data["title"] }
    var artist: String { __data["artist"] }
    var bpm: Double { __data["bpm"] }
    var genre: String? { __data["genre"] }
    var tags: [String] { __data["tags"] }
    var durationSeconds: Int? { __data["durationSeconds"] }
    var updatedAt: String { __data["updatedAt"] }
    var dtxFiles: [DtxFile] { __data["dtxFiles"] }
    var files: [File] { __data["files"] }

    /// DtxFile
    struct DtxFile: VirgoGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { VirgoGraphQL.Objects.DtxFile }
      static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("label", String.self),
        .field("level", Double.self),
        .field("fileUrl", String.self),
        .field("fileSizeBytes", Int.self),
        .field("fileEncoding", GraphQLEnum<VirgoGraphQL.FileEncoding>.self),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SimfileFields.DtxFile.self
      ] }

      var label: String { __data["label"] }
      var level: Double { __data["level"] }
      var fileUrl: String { __data["fileUrl"] }
      var fileSizeBytes: Int { __data["fileSizeBytes"] }
      var fileEncoding: GraphQLEnum<VirgoGraphQL.FileEncoding> { __data["fileEncoding"] }
    }

    /// File
    struct File: VirgoGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { VirgoGraphQL.Objects.R2File }
      static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("key", String.self),
        .field("size", Int.self),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SimfileFields.File.self
      ] }

      var key: String { __data["key"] }
      var size: Int { __data["size"] }
    }
  }

}
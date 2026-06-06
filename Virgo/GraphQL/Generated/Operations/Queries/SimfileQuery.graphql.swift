// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

extension VirgoGraphQL {
  class SimfileQuery: GraphQLQuery {
    static let operationName: String = "Simfile"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query Simfile($id: ID!) { simfile(id: $id) { __typename ...SimfileFields } }"#,
        fragments: [SimfileFields.self]
      ))

    public var id: ID

    public init(id: ID) {
      self.id = id
    }

    public var __variables: Variables? { ["id": id] }

    struct Data: VirgoGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { VirgoGraphQL.Objects.Query }
      static var __selections: [ApolloAPI.Selection] { [
        .field("simfile", Simfile?.self, arguments: ["id": .variable("id")]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SimfileQuery.Data.self
      ] }

      var simfile: Simfile? { __data["simfile"] }

      /// Simfile
      struct Simfile: VirgoGraphQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { VirgoGraphQL.Objects.Simfile }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(SimfileFields.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          SimfileQuery.Data.Simfile.self,
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

        struct Fragments: FragmentContainer {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          var simfileFields: SimfileFields { _toFragment() }
        }

        typealias DtxFile = SimfileFields.DtxFile

        typealias File = SimfileFields.File
      }
    }
  }

}
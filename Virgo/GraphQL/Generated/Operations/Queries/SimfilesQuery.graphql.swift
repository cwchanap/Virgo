// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

extension VirgoGraphQL {
  class SimfilesQuery: GraphQLQuery {
    static let operationName: String = "Simfiles"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query Simfiles($page: Int!, $pageSize: Int!, $search: String) { simfiles(scope: PUBLISHED, page: $page, pageSize: $pageSize, search: $search) { __typename count data { __typename ...SimfileFields } } }"#,
        fragments: [SimfileFields.self]
      ))

    public var page: Int
    public var pageSize: Int
    public var search: GraphQLNullable<String>

    public init(
      page: Int,
      pageSize: Int,
      search: GraphQLNullable<String>
    ) {
      self.page = page
      self.pageSize = pageSize
      self.search = search
    }

    public var __variables: Variables? { [
      "page": page,
      "pageSize": pageSize,
      "search": search
    ] }

    struct Data: VirgoGraphQL.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { VirgoGraphQL.Objects.Query }
      static var __selections: [ApolloAPI.Selection] { [
        .field("simfiles", Simfiles.self, arguments: [
          "scope": "PUBLISHED",
          "page": .variable("page"),
          "pageSize": .variable("pageSize"),
          "search": .variable("search")
        ]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        SimfilesQuery.Data.self
      ] }

      var simfiles: Simfiles { __data["simfiles"] }

      /// Simfiles
      struct Simfiles: VirgoGraphQL.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { VirgoGraphQL.Objects.SimfileConnection }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("count", Int.self),
          .field("data", [Datum].self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          SimfilesQuery.Data.Simfiles.self
        ] }

        var count: Int { __data["count"] }
        var data: [Datum] { __data["data"] }

        /// Simfiles.Datum
        struct Datum: VirgoGraphQL.SelectionSet {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __parentType: any ApolloAPI.ParentType { VirgoGraphQL.Objects.Simfile }
          static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .fragment(SimfileFields.self),
          ] }
          static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            SimfilesQuery.Data.Simfiles.Datum.self,
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

}
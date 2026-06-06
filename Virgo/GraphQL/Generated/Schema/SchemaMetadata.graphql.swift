// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

protocol VirgoGraphQL_SelectionSet: ApolloAPI.SelectionSet & ApolloAPI.RootSelectionSet
where Schema == VirgoGraphQL.SchemaMetadata {}

protocol VirgoGraphQL_InlineFragment: ApolloAPI.SelectionSet & ApolloAPI.InlineFragment
where Schema == VirgoGraphQL.SchemaMetadata {}

protocol VirgoGraphQL_MutableSelectionSet: ApolloAPI.MutableRootSelectionSet
where Schema == VirgoGraphQL.SchemaMetadata {}

protocol VirgoGraphQL_MutableInlineFragment: ApolloAPI.MutableSelectionSet & ApolloAPI.InlineFragment
where Schema == VirgoGraphQL.SchemaMetadata {}

extension VirgoGraphQL {
  typealias SelectionSet = VirgoGraphQL_SelectionSet

  typealias InlineFragment = VirgoGraphQL_InlineFragment

  typealias MutableSelectionSet = VirgoGraphQL_MutableSelectionSet

  typealias MutableInlineFragment = VirgoGraphQL_MutableInlineFragment

  enum SchemaMetadata: ApolloAPI.SchemaMetadata {
    static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self

    private static let objectTypeMap: [String: ApolloAPI.Object] = [
      "DtxFile": VirgoGraphQL.Objects.DtxFile,
      "Query": VirgoGraphQL.Objects.Query,
      "R2File": VirgoGraphQL.Objects.R2File,
      "Simfile": VirgoGraphQL.Objects.Simfile,
      "SimfileConnection": VirgoGraphQL.Objects.SimfileConnection
    ]

    static func objectType(forTypename typename: String) -> ApolloAPI.Object? {
      objectTypeMap[typename]
    }
  }

  enum Objects {}
  enum Interfaces {}
  enum Unions {}

}
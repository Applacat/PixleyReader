// aimdRenderer - Markdown rendering building blocks
//
// A Swift package providing structured markdown parsing and rendering capabilities.
// Designed to power content blocks across websites, SaaS products, and native apps.

@_exported import struct Foundation.UUID
@_exported import struct Foundation.URL

// Re-export public types for convenient access
// Models
public typealias Document = DocumentModel
public typealias AST = MarkdownAST

// Theme system is exported directly from Themes/

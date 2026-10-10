import SwiftUI

/// Layout shared by the header and the rows, so their columns line up.
extension LinkColumn {
    /// Fixed widths for Tags and Site; Name takes the rest.
    static let tagsWidth: CGFloat = 170
    static let siteWidth: CGFloat = 170
    static let spacing: CGFloat = 12
}

/// Column titles; clicking one sorts by it, clicking again reverses, a third time goes back to newest first.
struct LinkColumnHeader: View {
    @Binding var sort: LinkSort?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: LinkColumn.spacing) {
                button(.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                button(.tags)
                    .frame(width: LinkColumn.tagsWidth, alignment: .leading)
                button(.site)
                    .frame(width: LinkColumn.siteWidth, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            Divider()
        }
        .background(.background)
    }

    private func button(_ column: LinkColumn) -> some View {
        let isSorted = sort?.column == column
        return Button {
            switch sort {
            case let current? where current.column == column && current.ascending:
                sort = LinkSort(column: column, ascending: false)
            case let current? where current.column == column:
                sort = nil
            default:
                sort = LinkSort(column: column)
            }
        } label: {
            HStack(spacing: 4) {
                Text(column.title)
                    .fontWeight(isSorted ? .semibold : .regular)
                if isSorted, let sort {
                    Image(systemName: sort.ascending ? "chevron.up" : "chevron.down")
                        .imageScale(.small)
                }
            }
            .foregroundStyle(isSorted ? .primary : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(column.title)")
        .accessibilityAddTraits(isSorted ? .isSelected : [])
    }
}

/// One folder or link, in the same columns as the header.
struct LinkListRow: View {
    let entry: LinkListEntry

    var body: some View {
        HStack(spacing: LinkColumn.spacing) {
            NameCell(entry: entry)
                .frame(maxWidth: .infinity, alignment: .leading)
            TagsCell(tags: entry.tags)
                .frame(width: LinkColumn.tagsWidth, alignment: .leading)
            Group {
                if let count = entry.count {
                    Text(count == 1 ? "1 bookmark" : "\(count) bookmarks")
                } else {
                    Text(entry.site)
                }
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(width: LinkColumn.siteWidth, alignment: .leading)
        }
        .padding(.vertical, 2)
        .help(entry.help)
    }
}

// MARK: - Cells

/// A favicon (or folder icon) and the name, like Finder's Name column.
private struct NameCell: View {
    let entry: LinkListEntry

    var body: some View {
        HStack(spacing: 8) {
            if entry.isFolder {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.tint)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            } else {
                Favicon(url: entry.iconURL)
            }
            Text(entry.name)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.isFolder ? "\(entry.name), folder" : entry.name)
    }
}

/// As many tags as fit the column, then "+N" for the rest.
private struct TagsCell: View {
    let tags: [String]

    var body: some View {
        // Widest first: every tag, then fewer and fewer with a "+N".
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: tags.count, through: 0, by: -1)), id: \.self) { shown in
                pills(showing: shown)
            }
        }
        .help(tags.joined(separator: ", "))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tags.isEmpty ? "No tags" : "Tags: \(tags.joined(separator: ", "))")
    }

    private func pills(showing shown: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(tags.prefix(shown), id: \.self) { tag in
                Text(tag)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            if tags.count > shown {
                Text("+\(tags.count - shown)")
                    .padding(.horizontal, 2)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
    }
}

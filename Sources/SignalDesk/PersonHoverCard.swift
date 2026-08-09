import SwiftUI

struct PersonProfile: Equatable {
    var name: String
    var subtitle: String
    var overview: String
    var highlights: [String]
}

enum PersonProfileCatalog {
    static func profile(for investor: InvestorPreset) -> PersonProfile {
        let disclosure: String
        switch investor.holdingsKind {
        case .sec13F:
            disclosure = "通过 SEC 13F 追踪公开持仓；数据为季度末快照，不是实时持仓。"
        case .chineseFund:
            disclosure = "通过基金季报追踪公开的前十大持仓；不代表完整组合。"
        case .unavailable:
            disclosure = "目前没有连续、可核验的公开持仓披露。"
        }

        return PersonProfile(
            name: investor.name,
            subtitle: investor.firm,
            overview: investor.style,
            highlights: [disclosure]
        )
    }

    static func profile(forSourceName sourceName: String) -> PersonProfile? {
        let personName = sourceName.components(separatedBy: " · ").first ?? sourceName
        if let person = PersonPreset.aiRoboticsLeaders.first(where: { person in
            aliases(for: person.name).contains {
                personName.localizedCaseInsensitiveContains($0)
            }
        }) {
            return PersonProfile(
                name: person.name,
                subtitle: "AI、机器人与科技关键人物",
                overview: person.stance,
                highlights: [
                    "时间判断：\(person.horizon)",
                    "重点变量：\(person.variables.prefix(6).joined(separator: "、"))"
                ]
            )
        }

        if let investor = InvestorPreset.featured.first(where: { investor in
            personName.localizedCaseInsensitiveCompare(investor.name) == .orderedSame
        }) {
            return profile(for: investor)
        }
        return nil
    }

    private static func aliases(for name: String) -> [String] {
        name.split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct PersonHoverName: View {
    let title: String
    let profile: PersonProfile

    @State private var isPresented = false
    @State private var isNameHovered = false
    @State private var isCardHovered = false

    var body: some View {
        Text(title)
            .underline(pattern: .dot, color: .secondary)
            .onHover { hovering in
                isNameHovered = hovering
                if hovering {
                    isPresented = true
                } else {
                    scheduleDismissal()
                }
            }
            .popover(
                isPresented: $isPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                PersonProfileCard(profile: profile)
                    .onHover { hovering in
                        isCardHovered = hovering
                        if !hovering {
                            scheduleDismissal()
                        }
                    }
            }
            .help("悬停查看人物简介")
    }

    private func scheduleDismissal() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            if !isNameHovered && !isCardHovered {
                isPresented = false
            }
        }
    }
}

private struct PersonProfileCard: View {
    let profile: PersonProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .scaledFont(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name)
                        .scaledFont(.headline)
                    Text(profile.subtitle)
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(profile.overview)
                .scaledFont(.body)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(profile.highlights, id: \.self) { highlight in
                Label(highlight, systemImage: "circle.fill")
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(ProfileHighlightLabelStyle())
            }

            Text("移开鼠标即可关闭")
                .scaledFont(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }
}

private struct ProfileHighlightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon
                .scaledFont(.system(size: 5))
                .foregroundStyle(.blue)
            configuration.title
        }
    }
}

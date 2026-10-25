//
//  PermissionCardView.swift
//  OpenCodeClient
//

import SwiftUI

struct PermissionCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let permission: PendingPermission
    let onRespond: (APIClient.PermissionResponse) -> Void

    // Action cards speak a single language: a left electric-blue accent bar
    // plus plain text actions. Blue is the only color — green/orange/red are
    // dropped so the card reads as "decision needed", not "alarm".
    private let accent = DesignColors.Brand.primary

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accent)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 8) {
                if let name = permission.permission, !name.isEmpty {
                    Text(name)
                        .font(DesignTypography.body.weight(.semibold))
                }

                // Agent-authored: attributed so the user reads it as the
                // requester's claim about the action, not the app's own.
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.permissionAgentRequest))
                        .font(DesignTypography.meta)
                        .foregroundStyle(DesignColors.Neutral.textSecondary)
                    Text(permission.description)
                        .font(DesignTypography.body)
                        .foregroundStyle(DesignColors.Neutral.text)
                        .textSelection(.enabled)
                }

                // Granted scope: never clipped — approving a pattern you cannot
                // fully read is how over-broad grants happen.
                if !permission.patterns.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(permission.patterns.enumerated()), id: \.offset) { _, pattern in
                            Text(pattern)
                                .font(DesignTypography.microMono)
                                .foregroundStyle(DesignColors.Neutral.textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                HStack(spacing: DesignSpacing.lg) {
                    Button {
                        onRespond(.once)
                    } label: {
                        Text(L10n.t(.permissionAllowOnce))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)

                    if permission.allowAlways {
                        Button {
                            onRespond(.always)
                        } label: {
                            Text(L10n.t(.permissionAllowAlways))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(accent)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        onRespond(.reject)
                    } label: {
                        Text(L10n.t(.permissionReject))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DesignColors.Neutral.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
            .padding(DesignSpacing.cardPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignColors.Neutral.text.opacity(DesignColors.surfaceFill(for: colorScheme)))
        .clipShape(RoundedRectangle(cornerRadius: DesignCorners.medium))
    }
}

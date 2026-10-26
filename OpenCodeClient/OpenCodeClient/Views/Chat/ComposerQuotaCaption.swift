//
//  ComposerQuotaCaption.swift
//  OpenCodeClient
//

import SwiftUI

/// The composer's usage caption: one compact line in the composer's caption
/// row that says what this conversation has consumed — or, once the host
/// reports a provider allowance, how much of it is left.
///
/// The caption is quiet by construction: `ComposerQuota.caption` is `nil`
/// when the host reported nothing, and the view then renders nothing at all
/// rather than an empty line.
struct ComposerQuotaCaption: View {
    let quota: ComposerQuota

    var body: some View {
        if let caption = quota.caption {
            HStack(spacing: DesignSpacing.xs) {
                Image(systemName: "chart.bar.fill")
                    .font(DesignTypography.micro)
                    .foregroundStyle(DesignColors.Neutral.textTertiary)
                Text(caption)
                    .font(DesignTypography.micro)
                    .foregroundStyle(DesignColors.Neutral.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(quota.accessibilityLabel ?? caption)
            .accessibilityIdentifier("composer-quota-caption")
            // The caption shares its row with the model chip, the todo chip
            // and the live status, so it grows with the reader's text size
            // up to the accessibility sizes and no further: past those the
            // composer row itself would break.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }
}

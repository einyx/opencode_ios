# Product-page header and search artwork

Prepared for the English (U.S.) OpenCodeX listing. These are creative assets,
not replacement app icons or replacement screenshots. They use the existing
Warm Editorial palette, the current icon, and actual app UI captures populated
with illustrative sample data.

| Placement | File under `.occlient/appstore-prep/creative/` | Dimensions |
|---|---|---|
| Product-page header | `opencodex-header.png` | 3840 × 1646 (21:9) |
| Search results | `opencodex-search.png` | 1920 × 1280 (3:2) |

Both PNGs are opaque RGB with no alpha channel. No prices, URLs, awards,
Apple recognition badges, or third-party marketplace logos are included.
Copy: “Your coding agents. Within reach.” / “Chat. Follow tools. Review changes.”

Both were uploaded to the English (U.S.) listing on 2026-10-26: the header
panel shows “1 of 1 Header Asset” and the search panel “1 of 1 Search Results
Asset”.

## Re-render

Use `scripts/render_store_creatives.swift` with `--chat`, `--workspace`, and
`--output` arguments. The first two point to the exported native screenshots;
output goes to an ignored artifact directory, not the shipped app tree.

```sh
swift scripts/render_store_creatives.swift \
  --chat .occlient/appstore-prep/iphone-final/8E957EF8-87EE-47FB-B5DD-4EC9C22BA92C.png \
  --workspace .occlient/appstore-prep/ipad/E580ABE2-FE4C-4771-BCE6-5C4FE249CC8C.png \
  --output .occlient/appstore-prep/creative
```

Inspect the images, verify size/opacity with `sips`, and use the App Store
Connect preview before submission. Uploading/assigning assets to the draft
does not authorize submitting them for review or publishing the app.

## Apple references checked

- https://developer.apple.com/app-store/asset-best-practices/
- https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications

The specifications checked on 2026-10-26 allow 3840 × 1646 for the header,
1920 × 1280 through 3840 × 2560 at 3:2 for search, or a shared 5244 × 2950 PNG.
Alpha channels/transparency are not allowed. This pair uses the placement-
specific sizes rather than depending on automatic cropping of a shared image.

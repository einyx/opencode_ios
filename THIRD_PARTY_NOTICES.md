# Third-party licences

This app links the packages below. The licences are reproduced in full in
[`OpenCodeClient/OpenCodeClient/Resources/ThirdPartyNotices.txt`](OpenCodeClient/OpenCodeClient/Resources/ThirdPartyNotices.txt),
which ships inside the app and is shown under Settings → About → Open source licences.

The file is generated from `Package.resolved` and `scripts/third_party_licenses.json`:
run `python3 scripts/generate_third_party_notices.py` after changing a dependency.

| Package | Version | Licence |
|---|---|---|
| BigInt | 5.7.0 | MIT |
| Citadel | 0.12.0 | MIT |
| NetworkImage | 6.0.1-visionos.1 | MIT |
| swift-asn1 | 1.5.1 | Apache-2.0 |
| swift-atomics | 1.3.0 | Apache-2.0 |
| swift-cmark | 0.7.1 | BSD-2-Clause |
| swift-collections | 1.3.0 | Apache-2.0 |
| swift-crypto | 3.15.1 | Apache-2.0 |
| swift-log | 1.9.1 | Apache-2.0 |
| swift-markdown-ui | 2.4.1-visionos.1 | MIT |
| swift-nio | 2.94.1 | Apache-2.0 |
| swift-nio-ssh | 0.3.5 | Apache-2.0 |
| swift-system | 1.6.4 | Apache-2.0 |
| VoiceFlowKit | 0.4.0 | NOASSERTION |

## Packages without a licence

- **VoiceFlowKit 0.4.0** (https://github.com/grapeot/voiceflow): The upstream repository ships no licence file, so there is no grant to redistribute this code. A licence has to be added to the upstream repository (or the package replaced) before the app can be distributed.

# Third-party notices

VoxKey is MIT licensed (see [LICENSE](LICENSE)). It builds on the following projects.

## Linked into the app

| Component | License | Source |
|-----------|---------|--------|
| FluidAudio | Apache License 2.0 | https://github.com/FluidInference/FluidAudio |
| whisper.cpp (`whisper.framework`, embedded in the app bundle) | MIT | https://github.com/ggml-org/whisper.cpp |
| MacUtilityKit | MIT | https://github.com/georgecristea/MacUtilityKit |

FluidAudio is distributed under the Apache License 2.0; its license and the licenses of the code it
depends on are in its repository (`LICENSE`, `ThirdPartyLicenses/`).

## Downloaded at runtime

The speech models are not part of this repository or the app bundle. VoxKey downloads the ones you
choose from Hugging Face, and their own licenses apply.

| Model | License | Source |
|-------|---------|--------|
| NVIDIA Parakeet TDT 0.6B v3 (Core ML) | CC-BY-4.0 | https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml |
| NVIDIA Parakeet TDT 0.6B v2 (Core ML) | CC-BY-4.0 | https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml |
| NVIDIA Parakeet TDT-CTC 110M (Core ML) | CC-BY-4.0 | https://huggingface.co/FluidInference/parakeet-tdt-ctc-110m-coreml |
| NVIDIA Parakeet Realtime EOU 120M (Core ML) | NVIDIA Open Model License | https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml |
| OpenAI Whisper (ggml conversions) | MIT | https://huggingface.co/ggerganov/whisper.cpp |

Parakeet models © NVIDIA Corporation. Whisper models © OpenAI.

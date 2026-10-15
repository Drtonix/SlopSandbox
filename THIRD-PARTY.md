# Third-party components

The MIT license in `LICENSE` covers the code in this repository except the
vendored and submodule libraries below, which keep their own licenses.

| Component | Where | License | Source |
|---|---|---|---|
| Box2D | `Vendor/box2d` (vendored), `CVER/SlopSandboxCpp/third_party/box2d` (submodule) | MIT | https://github.com/erincatto/box2d |
| raylib | `CVER/SlopSandboxCpp/third_party/raylib` (submodule, C++ version only) | Zlib | https://github.com/raysan5/raylib |
| SDL2 | loaded at run time by the SDL build only, not bundled | Zlib | https://github.com/libsdl-org/SDL |

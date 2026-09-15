##### splits an `apple/swiftusd` checkout into top level `pxr` modules for faster compilation and reduced memory usage.

```pwsh
git clone https://github.com/apple/SwiftUsd.git
git clone https://github.com/furbytm/swiftusd-split.git

cd swiftusd-split
swift build
cd ..

swiftusd-split/.build/debug/swiftusd-split ./SwiftUsd --to ./ModularSwiftUsd
```

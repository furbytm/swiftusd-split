##### splits an `apple/swiftusd` checkout into top level `pxr` modules for faster compilation and reduced memory usage.

```pwsh
git clone https://github.com/apple/SwiftUsd.git
git clone https://github.com/furbytm/swiftusd-split.git

cd swiftusd-split
swift build
cd ..

swiftusd-split/.build/debug/swiftusd-split ./SwiftUsd --to ./ModularSwiftUsd
```

<br/>
<br/>

## Current Benchmark Results

### M5 (10 Core) Macbook Air with 16 GB memory, macOS 27.0 (26A428), Xcode 27 (beta 6), SwiftPM
```swift
Modular trial 1: nGB, (426s) 7m:7s

Vanilla trial 1: nGB, (970s) 16m:10s
```
> todo: figure out memory footprint, _"it doesn't hit OOM, is not a valid benchmark number"_.

<br/>

### M1 Max (10 core) MacBook Pro with 64 GB memory, macOS 26.5 (25F71), Xcode 26.5 (17F42), Xcode GUI
```swift
Modular trial 1: 2.49GB, (239s) 3m:59s
Modular trial 2: 2.62GB, (189s) 3m:9s
Modular trial 3: 2.58GB, (189s) 3m:9s
Modular trial 4: 2.54GB, (185s) 3m:5s

Vanilla trial 1: 3.6GGB, (184s) 3m:4s
Vanilla trial 2: 3.24GB, (154s) 2m:34s
Vanilla trial 3: 3.08GB, (160s) 2m:40s
Vanilla trial 4: 3.09GB, (149s) 2m:29s
```

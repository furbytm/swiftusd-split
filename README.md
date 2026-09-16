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

###### M5 (10 Core) Macbook Air with 16 GB memory, macOS 27.0 (26A428), Xcode 27 (beta 6), Xcode GUI
```swift
Modular trial 1: 2.50GB, (315.7s) 5m:15s
Modular trial 2: 2.32GB, (315.2s) 5m:2s
Modular trial 3: 2.37GB, (384.0s) 6m:24s
Modular trial 4: 2.24GB, (347.0s) 5m:47s

Vanilla trial 1: 3.24GB, (970s) 16m:10s
// (painfully slow while thrashing machine into OOM, todo: 3x more times)
```

###### M1 Max (10 core) MacBook Pro with 64 GB memory, macOS 26.5 (25F71), Xcode 26.5 (17F42), Xcode GUI
```swift
Modular trial 1: 2.77 GB, (355s) 5m:55s
Modular trial 2: 2.57 GB, (197s) 3m:17s
Modular trial 3: 2.60 GB, (202s) 3m:22s
Modular trial 4: 2.61 GB, (201s) 3m:21s

Vanilla trial 1: 3.07 GB, (156s) 2m:36s
Vanilla trial 2: 3.19 GB, (162s) 2m:42s
Vanilla trial 3: 3.14 GB, (158s) 2m:38s
Vanilla trial 4: 3.10 GB, (148s) 2m:28s
```

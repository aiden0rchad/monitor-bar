#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
clang -std=c11 -Wall -Wextra -Werror -DDDC_BRIDGE_TEST Sources/DDCBridge.c \
    -framework IOKit -framework CoreFoundation -o .build/ddc-tests
.build/ddc-tests
swiftc Sources/EDID.swift Tests/EDIDTests.swift -o .build/edid-tests
.build/edid-tests
clang -std=c11 -Wall -Wextra -Werror -c Sources/DDCBridge.c -o .build/DDCBridge-test.o
swiftc -swift-version 5 -import-objc-header Sources/DDCBridge.h \
    Sources/Models.swift Sources/EDID.swift Sources/Hardware.swift Tests/CapabilityTests.swift \
    .build/DDCBridge-test.o -framework IOKit -framework AppKit -o .build/capability-tests
.build/capability-tests
swiftc -swift-version 5 Sources/Models.swift Tests/DisplayModeTests.swift -o .build/display-mode-tests
.build/display-mode-tests
swiftc -swift-version 5 Sources/AbsoluteSlider.swift Tests/AbsoluteSliderTests.swift \
    -framework AppKit -o .build/absolute-slider-tests
.build/absolute-slider-tests
swiftc -swift-version 5 -import-objc-header Sources/DDCBridge.h \
    Sources/Models.swift Sources/EDID.swift Sources/Hardware.swift Sources/MonitorStore.swift \
    Tests/ControlWriteTests.swift .build/DDCBridge-test.o \
    -framework IOKit -framework AppKit -framework ServiceManagement -o .build/control-write-tests
.build/control-write-tests
swiftc -swift-version 5 -import-objc-header Sources/DDCBridge.h \
    Sources/Models.swift Sources/EDID.swift Sources/Hardware.swift Sources/MonitorStore.swift \
    Tests/BrightnessCalibrationTests.swift .build/DDCBridge-test.o \
    -framework IOKit -framework AppKit -framework ServiceManagement -o .build/brightness-calibration-tests
.build/brightness-calibration-tests

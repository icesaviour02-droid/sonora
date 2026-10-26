#!/usr/bin/env python3
"""Build the pinned provider core for device/simulator and stage libraries for Xcode."""

import os
from pathlib import Path
import shutil
import subprocess

IOS = Path(__file__).resolve().parents[1]


def build():
    clang = Path(subprocess.check_output(["xcrun", "--find", "clang"], text=True).strip())
    environment = os.environ.copy()
    environment["RUSTUP_TOOLCHAIN"] = "stable"
    environment["IPHONEOS_DEPLOYMENT_TARGET"] = "26.0"
    environment["LIBCLANG_PATH"] = str(clang.parent.parent / "lib")
    for target, sdk in [("aarch64-apple-ios", "iphoneos"), ("aarch64-apple-ios-sim", "iphonesimulator")]:
        selected = environment.copy()
        selected["SDKROOT"] = subprocess.check_output(["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True).strip()
        command = ["cargo", "build", "--manifest-path", str(IOS / "Core/Cargo.toml"), "--locked", "--release", "--target", target]
        # Swift simulator Debug uses an optimized Rust archive. Enable its deterministic QA fixture
        # explicitly; the iPhoneOS archive packaged in the IPA never enables this feature.
        if sdk == "iphonesimulator":
            command.extend(["--features", "review-fixtures"])
        subprocess.run(command, env=selected, check=True)
        source = IOS / "Core/target" / target / "release/libsonora_mobile_core.a"
        destination = IOS / "build/native" / sdk / source.name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        print(f"Staged {target} library: {destination}", flush=True)


if __name__ == "__main__":
    build()

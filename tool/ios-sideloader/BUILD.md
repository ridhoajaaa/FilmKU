# Sideloader (built from source) — why & how

`./sideloader` in this directory is the **CLI frontend of
[Dadoum/Sideloader](https://github.com/Dadoum/Sideloader)** — an open-source,
cross-platform iOS sideloader (Linux included) that signs + installs an IPA
with a **free Apple ID** (no $99 developer account, no Mac).

## Why we do NOT ship the official prebuilt binary

The latest GitHub **release** is `1.0-pre4` (Sep 2024). On 2026 Apple auth it
**crashes silently right after 2FA completes** (process dies with no error,
right at `Completing authentication...`). The repo's `main` branch is
actively maintained (checked 2026-07-31) and works end-to-end, but has no
release binary — so we build it ourselves and vendor the result here.

## Build recipe (what was done on 2026-08-02)

### 1. Prerequisites (Arch/CachyOS)

```bash
paru -S libimobiledevice libplist ideviceinstaller  # runtime libs (dev headers come with them on Arch)
# libxml2 (see step 3 for the symlink), openssl and libzip headers:
paru -S libxml2 openssl libzip
```

Other distros: install `libimobiledevice-dev libplist-dev libssl-dev libzip-dev` etc.

### 2. D compiler: **LDC 1.34.0** (exact version the project's CI uses)

Using a newer LDC (e.g. 1.42) fails the build with:

```
source/sideload/sign.d(305,17): Error: Runtime function `objc_opt_isKindOfClass` was not found
```

The project is tested with **D 2.104.2 = LDC 1.34.0** (see
`.github/actions/setup-d-compiler/action.yml` in the Sideloader repo). Get it
from the GitHub releases (not the dlang.org installer — its GPG check fails):

```bash
curl -sL -o /tmp/ldc.tar.xz \
  'https://github.com/ldc-developers/ldc/releases/download/v1.34.0/ldc2-1.34.0-linux-x86_64.tar.xz'
tar xJf /tmp/ldc.tar.xz -C /opt   # -> /opt/ldc2-1.34.0-linux-x86_64

# dub (D package manager):
curl -sL -o /tmp/dub.tar.gz \
  'https://github.com/dlang/dub/releases/download/v1.41.0/dub-v1.41.0-linux-x86_64.tar.gz'
tar xzf /tmp/dub.tar.gz -C /opt  # -> /opt/dub

export PATH=/opt/ldc2-1.34.0-linux-x86_64/bin:/opt/dub:$PATH
ldc2 --version   # LDC 1.34.0
```

### 3. libxml2 soname shim (newer distros only)

LDC 1.34 is linked against the old `libxml2.so.2` soname, but Arch/CachyOS
ships `libxml2.so.16` (same ABI, newer soname). Without it, ldc2 refuses to
start:

```
ldc2: error while loading shared libraries: libxml2.so.2: cannot open shared object file
```

```bash
sudo ln -sf /usr/lib/libxml2.so.16 /usr/lib/libxml2.so.2
```

(The "no version information available" warning on the symlink is harmless.)

### 4. Clone + build (mirrors the project's CI)

```bash
git clone https://github.com/Dadoum/Sideloader.git
cd Sideloader
dub build -b release-debug --compiler=ldc2 --arch x86_64-linux-gnu :cli-frontend
# output: bin/sideloader
```

- `-b release-debug` and the `:cli-frontend` subpackage are **required** —
  building the whole project pulls in the GTK/Qt/SwiftUI frontends and fails
  on Linux.
- First run auto-downloads the Apple Music Android APK from
  `apps.mzstatic.com` (~150 MB) and extracts `libCoreADI.so` +
  `libstoreservicescore.so` into `~/.config/Sideloader/lib/` — this gives
  **local anisette** (Apple's device identity), so no third-party anisette
  server is needed (unlike AltServer-Linux, whose default anisette server was
  dead in 2026).

### 5. Copy the binary into the repo

```bash
cp Sideloader/bin/sideloader tool/ios-sideloader/sideloader
strip tool/ios-sideloader/sideloader   # 45MB → ~5.8MB (matches the vendored binary)
chmod +x tool/ios-sideloader/sideloader
```

(Stripping removes debug symbols only — runtime behavior is unchanged and
keeps the repo lean.)

Runtime deps on the host: `libimobiledevice`, `libplist`, `openssl`, and the
`~/.config/Sideloader/` provisioning state (created on first run).

## Re-signing every 7 days

Free-Apple-ID signatures expire after 7 days. Just re-run:

```bash
./tool/resign_ios.sh FilmKU-unsigned.ipa you@icloud.com
```

Sideloader **reuses the certificate + private key** it created on the first
install (stored under `~/.config/Sideloader/keys/<sha1>/key.pem` and matched
against Apple's online certs by public key), so no revoke is needed — it
re-provisions and reinstalls with a fresh profile.

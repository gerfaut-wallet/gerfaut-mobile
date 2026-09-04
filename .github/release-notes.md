### Downloads

Three APKs, one per processor architecture. Take `gerfaut-*-android-arm64-v8a.apk` if you are not sure: every Android phone sold since roughly 2017 runs on 64-bit ARM.

- `gerfaut-*-android-arm64-v8a.apk`, 64-bit ARM, the right file for almost every phone
- `gerfaut-*-android-armeabi-v7a.apk`, 32-bit ARM, for older or entry-level devices
- `gerfaut-*-android-x86_64.apk`, Intel and AMD, mostly emulators and Chromebooks

Download the file on your phone and open it to install; allow installs from your browser or file manager if Android asks. Picking the wrong architecture costs you nothing: Android refuses the install and says so.

### Verify your download (optional)
`SHA256SUMS` lists the hash of every file above and is signed with the author's [minisign](https://jedisct1.github.io/minisign/) key:

```
RWTz3c4gUmglCX5Uvjthigz1ts3TS3ZSdhRNpFgOJRW/Wr4XjGlqTR3O
```

1. The signature proves the hash list comes from the author:
   `minisign -Vm SHA256SUMS -P RWTz3c4gUmglCX5Uvjthigz1ts3TS3ZSdhRNpFgOJRW/Wr4XjGlqTR3O`
2. The hash proves your file was not altered:
   - Linux: `sha256sum --check SHA256SUMS --ignore-missing`
   - macOS: `shasum -a 256 --check SHA256SUMS --ignore-missing`
   - Windows: `(Get-FileHash .\<file>).Hash` must match the file's line in `SHA256SUMS`

### Rebuild it yourself (optional)
These APKs come out of a container where every tool version is pinned, so the same commit always produces the same bytes. Rebuild them on your own machine and compare: only the signature should differ. The procedure is in [docs/REPRODUCIBLE-BUILDS.md](https://github.com/gerfaut-wallet/gerfaut-mobile/blob/main/docs/REPRODUCIBLE-BUILDS.md).

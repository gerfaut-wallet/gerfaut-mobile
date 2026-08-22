### Downloads
- **Android**: `gerfaut-*-android.apk`. Download it on your phone and open it to install; allow installs from your browser or file manager if Android asks.

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

# Vendored sources and assets

Everything required to build the contracts, run the delivered tests, and serve the website is stored as ordinary files. There are no git submodules, package-manager installs, CDN dependencies, or compiler binaries in the deliverable. Foundry/Solidity and Node/Python are execution tools provided by the checking environment.

## OpenZeppelin Contracts v5.2.0

- Upstream: https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.2.0
- Archive: https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.2.0
- Archive SHA-256: `80f86d2dba4e1c0d66a216d2ddf0ac5d731edf9338ea12a985edca8774802814`
- Local root: `lib/openzeppelin-contracts/`
- License: MIT, retained at `lib/openzeppelin-contracts/LICENSE`.
- Included unmodified: `ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`, `Context.sol`, and `draft-IERC6093.sol`, preserving upstream paths. This is the complete import closure needed by the token.

## forge-std v1.9.7

- Upstream: https://github.com/foundry-rs/forge-std/tree/v1.9.7
- Archive: https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7
- Archive SHA-256: `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`
- Local root: `lib/forge-std/`
- Included unmodified: upstream `src/`, `LICENSE-MIT`, and `LICENSE-APACHE`. Only the test suite imports this library.

## Official logo

- Local file: `website/assets/official-logo.webp`
- Format/dimensions: WebP, 687 × 1024.
- SHA-256: `a6592048385b28f99400907797524a4ce013dadb70a1f06f8fa5567d6d6facca`
- The following exact supplied URL returned the stored bytes. No resizing, replacement, image generation, background removal, or content editing was performed. The local copy prevents expiry of the signed Discord URL from breaking the site.

```text
https://media.discordapp.net/attachments/841728246857072703/1560977929117376674/image_40.jpg?ex=6ad4ad7b&is=6ad35bfb&hm=f4c3716c34c6a7aa0d505f8a96e3f093c1c50bb52ee86363a638e577ef1135db&=&format=webp&width=687&height=1024
```

The supplied logo is requester-provided artwork; its copyright is not relicensed by this project's source-code license. The publisher must have permission to use it. Decorative bottles elsewhere on the page are CSS shapes and do not replace or alter the official logo.

## Barlow Condensed Black Italic

- Source: https://github.com/google/fonts/tree/main/ofl/barlowcondensed
- Local file: `website/assets/fonts/BarlowCondensed-BlackItalic.ttf`
- SHA-256: `e1ed5d7e50c6a4498454d40509ce2362384a2c7870df3418fdbd010f81dffad3`
- License: SIL Open Font License 1.1, retained at `website/assets/fonts/OFL.txt` (SHA-256 `186d750eb496a4c17a76385f82be6aea2ac1cf2de074a811d63786cf374ea73f`).
- The source branch is mutable; the exact vendored bytes are fixed by the checksum above. The website uses these local bytes with system-font fallbacks.

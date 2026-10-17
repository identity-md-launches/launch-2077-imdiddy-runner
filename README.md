# IMDiddy Runner · IMDIDDY

A fixed-supply Ethereum ERC-20 and a self-contained meme website using the exact official image supplied in the assignment. The project is ready for the IdentityMD launch pipeline. No mainnet transaction has been signed or broadcast by this assignment, and no public website has been published.

| Requested output | Current status |
| --- | --- |
| Token address | Assigned by the subsequent factory launch; not yet available |
| Deployment transaction hash | Returned by that launch; not yet available |
| Live website URL | Assigned when the operator publishes `website/`; not yet available |

The website deliberately shows “Warming up for launch” until all confirmed launch values are supplied. `website/launch-config.json` uses `null` for unavailable values. These are recoverable, explicit settings, never substitute addresses or invented receipts. The task's separate manifest step owns `launch.json`; this repository does not provide one.

## Build and check

Use Foundry with Solidity **0.8.26** available. All Solidity dependencies are vendored as ordinary files in `lib/`; no dependency installation, submodules, API keys, RPC endpoints, or network access are needed to build and test. The static website requires no package manager or build step. Website tests require Node.js 22.15+ (checked here with Node.js 24).

```sh
forge build
FOUNDRY_FUZZ_SEED=0xaac6c607953084abacd5531034593f5136e8b094a4eac8c9e7621c8caaedf255 forge test
forge fmt --check
node --test test/website.test.mjs
```

The tests do not read or change environment variables, fork a chain, enable FFI, or request filesystem cheatcode permissions. The fuzz seed above is a runner setting supplied by the assignment, not a contract configuration value.

For a local website preview:

```sh
python3 -m http.server 8080 --bind 127.0.0.1 --directory website
```

Open `http://127.0.0.1:8080`. Use HTTP for local preview rather than opening the HTML as a `file:` URL, because the module scripts and launch-settings request need a web origin. The site works under a subdirectory as well as a domain root. All artwork, scripts, CSS, and fonts are local.

## Contract and deployment parameters

| Parameter | Value |
| --- | --- |
| Source / Solidity identifier | `src/IMDiddyToken.sol` / `IMDiddyToken` |
| Constructor arguments | None (`[]`) |
| Chain | Ethereum mainnet, chain ID `1` |
| Name | `IMDiddy Runner` |
| Symbol | `IMDIDDY` |
| Decimals | `18` |
| Human-readable supply | `1,000,000,000` |
| Supply in minor units | `1000000000000000000000000000` |
| Supply constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |
| Constructor recipient | `msg.sender`, the actual deploying factory in this launch |
| Additional application contracts | None |
| Owner / admin / initialization | None |
| Compiler / EVM target | Solidity `0.8.26` / Cancun |
| Optimization | Enabled, `200` runs |
| Bytecode metadata hash | `none` |
| Library linking | None; inherited implementation is compiled into the token |

The constructor mints the entire supply exactly once and emits the standard mint `Transfer` event. It does not allocate tokens itself or call an external contract. Deploying through CREATE2 behaves identically to direct CREATE: the constructor caller receives the supply, not `tx.origin` or a hardcoded wallet.

The token inherits the vendored OpenZeppelin Contracts **v5.2.0** ERC-20 without transfer overrides. It supports `transfer`, `approve`, `transferFrom`, `balanceOf`, `allowance`, `totalSupply`, and metadata. Transfers deliver their exact amount. Zero-value transfers and self-transfers follow standard ERC-20 behavior; zero recipients and spenders are rejected. Finite allowances decrease when spent; maximum `uint256` allowances retain OpenZeppelin's unlimited-allowance semantics. `approve` emits `Approval`; this OpenZeppelin version does not emit an additional `Approval` when `transferFrom` spends an allowance.

There is no public mint, burn, pause, blacklist, seize, owner, tax, proxy, or upgrade function. Internal OpenZeppelin mint/burn helpers are not exposed. No one has a privileged recovery power over tokens transferred to an inaccessible address or contract. The contract rejects ordinary ETH transfers and unknown selectors; forcibly sent ETH cannot be recovered.

## Launch economics supplied by the assignment

These values describe the subsequent launch pipeline. They are not extra token constructor arguments or on-token settings.

| Launch parameter | Assignment value |
| --- | --- |
| Paired currency | IMD on Ethereum, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` |
| Paired currency decimals | `18` |
| Pool fee | `12500` (1.25% swap fee) |
| Tick spacing | `60` |
| Pool initial-price provenance value | `79228162514264337593543950336` |
| `economics.poolBps` | `8800` |
| `economics.initialMarketCapWei` | `2500000000000000000000` (2,500 IMD for the whole supply) |
| `economics.remainderTo` | `0x3d6a89c8751a45dd577a4c1f3b34e71c58236193` |

The factory initially receives 100% of the supply. It transfers 10% (100,000,000 IMDIDDY) to the launch's MerkleDistributor, uses 88% (880,000,000 IMDIDDY) for the pool allocation, and forwards the remaining 2% (20,000,000 IMDIDDY) to the specified remainder recipient according to launch policy. The contributor allocation is handled entirely by the factory/distributor. This project creates no allocation wallet, distributor, pool, hook, or extra reserve.

The launch deployer derives the actual opening price from the supplied initial market cap, supply, and deployed currency ordering. The website distinguishes the **0% token transfer tax** from the **1.25% pool swap fee**. The stated market cap is an opening configuration, not a valuation guarantee. The pair and recipient addresses above are assignment inputs, not externally discovered or independently verified onchain by this task.

## Website and publication

`website/` is the complete static document root. It includes the supplied logo, running-club styling, baby-oil meme cards, six cycling captions with copy controls, logo download, token details, launch allocation, a contract-address copy control, buy/explorer links, and FAQ. It adapts to mobile widths, uses semantic navigation and native disclosure controls, provides visible keyboard focus, and respects reduced-motion preferences. It has no wallet connection or signing code, third-party scripts, analytics, remote fonts, or runtime package dependencies.

The site is a parody and does not claim affiliation with any person or brand in the artwork. The supplied logo is preserved byte-for-byte; provenance and its SHA-256 are in `DEPENDENCIES.md`. The requester is responsible for having the necessary rights to publish the supplied image.

Publish the **contents of `website/`** to an HTTPS static host. Use no build command and no server-side runtime. Serve `.mjs` as `text/javascript` or `application/javascript`, JSON as `application/json`, the logo as `image/webp`, and the font as `font/ttf`. Disable caching for `launch-config.json` or configure it to revalidate on every request. Do not add a service worker or cache a stale launch configuration. The page also explicitly requests the file with `cache: "no-store"`.

The HTML includes a content security policy limited to local resources. Set these response headers at the chosen host where supported:

```text
Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'
X-Content-Type-Options: nosniff
Referrer-Policy: strict-origin-when-cross-origin
```

The meta policy in the document cannot enforce `frame-ancestors`; that directive requires the response header. Hosting integration and domain/DNS ownership remain the operator's responsibility.

## After launch

1. The IdentityMD deployer completes the factory launch and records its actual token address and transaction hash. Verify the deployed bytecode against the accepted artifact, check name/symbol/decimals/supply, review the mint and allocation events, and verify source on Etherscan with the pinned build settings. The builder does not call the factory, supply keys, or broadcast transactions.
2. The launch operator confirms liquidity and a usable buy/sell route for the **actual IMDIDDY/IMD pool**. Obtain the correct public buy URL from that launch/trading interface and test it against the actual contract. This task does not guess a router address or assume a generic swap URL supports the launch pool's fee.
3. The website operator publishes `website/` to its chosen HTTPS host and records the real public URL. A pre-launch page may be published before trading is ready.
4. Supply all four real values to the local configuration utility, then republish the resulting `website/launch-config.json`:

   ```text
   node tools/configure-site.mjs --address TOKEN_ADDRESS --tx TRANSACTION_HASH --buy-url CONFIRMED_BUY_URL --site-url LIVE_WEBSITE_URL
   ```

   Uppercase argument labels above are documentation metavariables: replace each with the real launch value; do not run the labels literally. Quote URL arguments in the shell. The tool validates all values before writing, uses an atomic file replacement, and prints the token address, transaction hash, and live URL for handoff. It never reads a wallet, uses an RPC, or signs anything. `node tools/configure-site.mjs --help` explains its arguments. If an interrupted prior write leaves `website/launch-config.json.tmp`, inspect and remove that temporary file before retrying.
5. Reload the published page, compare the entire displayed address and transaction link to the launch receipt, test copy and buy links, and review the quote in the trading interface. For social previews, replace the relative `og:image` value in `index.html` with the actual public HTTPS asset URL once the site origin is known.

There are **no owner-only token setters** to call after deployment. The launch values above are website settings controlled by the website publisher. URL/address validation checks syntax and completeness, not onchain truth or a destination site's trustworthiness; the operator must verify the receipt and buy destination before publication. All four values must be provided together. Missing, partial, malformed, wrong-chain, or unavailable settings keep purchase and explorer controls disabled. The site never enables a fabricated address as a fallback.

The publisher maintains hosting, TLS, the buy route, and launch details. Neither this contract nor the website guarantees liquidity, price, returns, image rights, or availability of external trading services. The running-club and race-pass language is thematic; no separate membership asset is issued.

## Verification and limits

- **Foundry:** 25 passing tests, including four fuzz tests at 1,024 cases each and a stateful invariant at 256 runs × 64 calls (16,384 calls). Tests cover exact minting to a CREATE2 factory, allocation/claim/return flows, balances and supply, finite/infinite/revoked allowances, events, failed transfers and rollback, invalid addresses, missing admin entrypoints, non-callback transfers, ETH rejection, runtime size, and forbidden opcodes.
- **Website:** 15 passing Node tests check receipt validation, absent/failed configuration, exact link rendering and stale-link removal, clipboard failures, caption interaction, CLI arguments, local asset availability, internal links, disabled pre-launch controls, and the exact logo checksum. The DOM adapter checks behavior; it is not a browser rendering test.
- **Formatting/build:** `forge build`, `forge test` with the assignment seed, and `forge fmt --check` pass using the compiler pinned in `foundry.toml`.
- **Offline handoff:** a clean temporary copy containing only delivered source, vendored libraries, website, and tests also passed `forge build --offline`, the seeded `forge test --offline`, formatting, and all website tests. The token runtime is 1,753 bytes with no library link references. Local HTTP checks confirmed every site asset and MIME type at both a domain root and `/website/`; HTML tag nesting was checked.
- The supplied protected tests were read as requirements. Their factory/PoolManager harness and environment are not present as a runnable project here. Local allocation tests model token movements, not actual Uniswap v4 execution; the platform's independent protected tests must exercise the real launch integration.
- A source review against the supplied Ethereum security checklist found no external calls, privileged controls, signature flow, pricing oracle, or upgrade surface in the token. These features were unnecessary for the requested standard token. Slither, Mythril, a live mainnet trade, and a browser rendering test were not run. Passing tests are not an independent security audit; the platform's final review and deployment checks remain pending.

See `DEPENDENCIES.md` for versions, licenses, and artifact provenance.

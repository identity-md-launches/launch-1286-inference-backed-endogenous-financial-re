# INFER

An immutable ERC-20 named **Inference Backed Endogenous Financial Re**, symbol **INFER**.
Its constructor mints **1,000,000,000 tokens with 18 decimals** to the immediate deployer.
The exact total supply in minor units is **1000000000000000000000000000** (`10^27`).

## Contract and assumptions

`src/INFERToken.sol:INFERToken` uses OpenZeppelin Contracts v5.0.2 ERC20 without transfer overrides.
The requested token is interpreted as a standard, fixed-supply ERC-20: transfers deliver the
exact amount, with no transfer fee, rebase, burn, vesting, or additional application contracts.
The token name does not implement or promise financial backing, inference services, or redemption.

The only mint occurs in the constructor. There is no owner, admin role, external mint or burn,
pause, blacklist, seizure, upgrade, initialization, oracle, or maintenance function. The
deployer has the same rights as any other holder after deployment. Balances move only through
the holder's `transfer` or a spender's approved `transferFrom`.

Standard ERC-20 behavior includes:

- `transfer`, `approve`, and `transferFrom` return `true` on success and revert on failure.
- Zero-value transfers between nonzero addresses and self-transfers are supported.
- Zero recipients, zero spenders, insufficient balances, and insufficient allowances revert
  with OpenZeppelin's ERC-6093 custom errors. Failed transfers preserve balances and allowances.
- `approve` replaces the current allowance; `approve(spender, 0)` revokes it.
- The maximum `uint256` allowance is treated as unlimited and is not reduced on spending.
- Minting and transfers emit `Transfer`; approvals emit `Approval`. In this version,
  spending allowance through `transferFrom` does not emit an additional `Approval` event.

## Build and test

Run from the repository root with Foundry and Solidity **0.8.26** installed:

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, optimization at 200 runs, and
`bytecode_hash = "none"`. FFI and filesystem permissions are not enabled. The source
dependencies are vendored as ordinary files in `lib/`; no network, package installation,
environment configuration, RPC endpoint, or git submodule is needed to build or test.
The compiler itself must be supplied by the build environment.

`DEPENDENCIES.json` records upstream tags, exact commits, archive hashes, and the SHA-256 of
each vendored file. OpenZeppelin includes only the ERC20 dependency closure and its MIT license;
forge-std v1.9.7 includes its `src/` tree and MIT/Apache licenses. Vendored sources are unmodified.

Tests cover exact metadata and mint events, direct and CREATE2 factory deployments, full
distribution and return transfers, ERC-20 events and allowance semantics, zero and maximum
values, revocation, failed-call atomicity, and rejected privileged entry points. Three fuzz
tests exercise transfer and allowance boundaries; a stateful invariant checks that arbitrary
sequences of transfers and approvals preserve the supply and sum of all holder balances.
Test addresses are local fixtures, not deployment parameters. Tests do not read or mutate
environment variables and do not depend on execution order.

## Deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract identifier | `INFERToken` |
| Artifact after building | `out/INFERToken.sol/INFERToken.json` |
| Constructor arguments | None (`[]`; empty encoded arguments) |
| Native currency sent with deployment | None; constructor is nonpayable |
| Initial recipient | Constructor `msg.sender`, the immediate deploying account or factory |
| Name | `Inference Backed Endogenous Financial Re` |
| Symbol | `INFER` |
| Decimals | `18` |
| Total supply (minor units) | `1000000000000000000000000000` |
| Target launch chain | Ethereum, chain ID `1` |

Deploy the compiled creation bytecode directly, with no constructor data appended, no linked
libraries, and no initialization call. No proxy or deployment helper is required. If deployed
through a factory, **the factory receives the entire supply**, not the transaction origin or
the account calling the factory. It must be able to distribute the tokens. A direct EOA
deployment instead gives the supply to that EOA. No fixed recipient address is embedded.

The IdentityMD factory is responsible for the supplied launch economics: 10% to the launch
MerkleDistributor, 80% for pool seeding, and the remaining 10% to
`0x6bf192ebef135e0f645e99d59d9bf44e7711606c`. The paired currency is IMD at
`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`; the given fee is `12500`, tick spacing `60`,
and initial market cap `2500000000000000000000` in paired-currency minor units. These are
external factory/manifest responsibilities, not token constructor parameters or allocations.
The token constructor transfers nothing to those recipients. The separate manifest step
creates `launch.json`; this project does not include one.

## After launch

No token settings, operators, external services, or owner transactions are needed. The launch
operator must confirm the deployed bytecode, metadata, total supply, factory distribution,
and actual pool operation, and publish/verify source using the pinned compiler settings.
The local factory test checks exact token movements; it does not execute a real Uniswap pool
or replace the network's protected launch integration tests.

Holders are responsible for recipient correctness, custody, and approvals. Prefer limited
allowances and revoke unused approvals. When replacing a nonzero allowance, first revoke it
and wait for confirmation to reduce the standard ERC-20 approval race; revocation cannot undo
spending already executed. Tokens sent to contracts that cannot send them onward may be stuck;
there is no administrator or recovery function. Ordinary ETH transfers to the token revert.

## Security review scope

The supplied security reference was reviewed against this implementation. Token operations
perform no external calls or callbacks, so transfers introduce no reentrancy interaction.
There is no price arithmetic, randomness, signature recovery, delegatecall, or upgrade path.
Supply scaling uses exact integer arithmetic, and balance and allowance validation are handled
by the vendored ERC20 implementation. Unit, fuzz, and stateful invariant tests are local
verification, not an independent security audit. Slither and Mythril were not run. An independent
adversarial review and the launch network's integration checks remain release responsibilities.
No transactions are broadcast and no wallet keys are used by this project.

# FirmMux Firmware Contract

This document describes the minimal read-only firmware contract exported by the experimental FirmMux support layer.

## Scope

This pass exports readiness state plus the minimal direct-chainload request latch.

It does not:
- reroute HOME
- rewrite APT IPC
- change stock launch routing
- add file-I/O tracing

The contract is only available when built with `EXPERIMENTAL_FIRMMUX_SHELL=1`.

## Userland Slots

Read with `svcGetSystemInfo(0x10000, id)`.

- `0x188`: `fw_shell_ready`
- `0x189`: `fw_route_kind`
- `0x18A`: `fw_jump_readiness`
- `0x18B`: `fw_flags`
- `0x18C`: `contract_version`
- `0x190`: `direct_chainload_intent`
- `0x191`: `direct_chainload_titleid`
- `0x192`: `direct_chainload_mediatype`

When the experiment is off, all slots return `0`.

## Values

### `fw_shell_ready`

- `0`: unknown or unsupported
- `1`: not ready
- `2`: ready

`ready` is only reported after:
- PM has observed NS startup
- and one of:
  - stock HOME has been seen
  - the configured hbldr takeover title is active as the shell
  - no normal foreground application is active

### `fw_route_kind`

Informational only in this phase.

- `0`: none or unknown
- `1`: stock HOME target observed
- `2`: stock fallback non-menu target observed
- `3`: non-menu candidate path observed

### `fw_jump_readiness`

- `0`: unknown
- `1`: not ready
- `2`: ready

This is conservative and currently mirrors shell readiness:
- `2` only when `fw_shell_ready == 2`

### `fw_flags`

Diagnostic bits:

- `BIT(0)`: NS seen
- `BIT(1)`: HOME-related APT seen
- `BIT(2)`: foreground app known
- `BIT(3)`: recent app-jump seen
- `BIT(4)`: route classification valid
- `BIT(5)`: stock HOME seen
- `BIT(6)`: hbldr shell active

### `contract_version`

- `0`: unsupported
- `1`: supported

### `direct_chainload_intent`

- `0`: not set
- `1`: set

This is a one-shot firmware-visible latch for hbldr-owned shells that intend
to exit into a direct installed-title chainload instead of the normal
homebrew-restart path.

### `direct_chainload_titleid`

- `0`: unset
- otherwise: the installed CTR title to launch

### `direct_chainload_mediatype`

- `0..2`: `FS_MediaType` for the installed CTR title

## Observation Sources

The contract is normalized from:
- PM observation of NS startup
- PM observation of foreground-app and app-jump state
- k11 observation of post-stock `APT:ReceiveParameter` traffic for commands `10..12`

These observations are read-only in this phase.

The contract may also report shell-ready for a HOME-less shell when:
- NS is up
- the current foreground app is the configured hbldr takeover title

## Consumer Guidance

FirmMux should consume this contract conservatively:

- treat `fw_shell_ready == 2` as the only positive shell-ready signal
- treat `fw_jump_readiness == 2` as the only positive jump-ready signal
- treat any other value as fail-closed
- treat `fw_route_kind` as informational only

For direct installed-title launch from a hbldr-owned shell:

- set `svcKernelSetState(0x10083, mediaType, (u32)titleId, (u32)(titleId >> 32))`
- then set `svcKernelSetState(0x10082, 1, 0, 0)` immediately before queueing the
  chainload and exiting
- PM consumes and clears this latch during notification `0x3000`
- if the request is valid, PM waits for the hbldr-owned app to exit and then
  launches the latched title directly
- CTR titles use the existing PM `LaunchTitle(...)` path
- TWL/DSiWare titles use `NS_RebootToTitle(...)`
- if the request is absent or invalid, normal homebrew restart behavior remains
  unchanged

## Changed Components

- `k11_extension`
- `sysmodules/pm`

No FirmMux code is required for the export side of this contract.

# Contributing to WagLock

Thanks for your interest in WagLock. Start with [AGENTS.md](AGENTS.md), the [README](README.md) and the [development documentation](docs/portable-vault/README.md). The [requirements](docs/portable-vault/requirements.md) and [architectural decisions](docs/portable-vault/decisions.md) are the source of truth for product behavior.

## Ground rules

- Keep existing readers, credentials and user data intact. Never reset, uninstall or migrate a real library to work around a build problem.
- Storage, credential or recovery changes need disposable fixtures, failure-path tests and a source-preserving transition plan.
- Use disposable sample media only. Never commit passwords, recovery material or private media.
- The app UI, code comments and documentation are English. Unicode test data (for example non-Latin file names) is intentional and should stay.

## Building and testing

See [Build and run](README.md#build-and-run) in the README. The default `WagLock` scheme builds the development app; release builds use `config/AppStore.xcconfig` as described there.

## Reporting issues

Include the build number, device and iOS version, and steps to reproduce using disposable samples. Security-sensitive reports should leave exploit details out of public issues until a private reporting route is agreed.

## License

Contributions are made under the repository's [GNU GPL version 3](LICENSE) license. See [NOTICE.md](NOTICE.md) and [TRADEMARK.md](TRADEMARK.md) for attribution and upstream branding guidance.

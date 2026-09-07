# Contributing

Monitor reports are useful even when you aren't changing code. A clear report
from a different monitor often helps more than a large speculative patch.

## Report a monitor problem

Include the app version, macOS version, Mac model, monitor model if known, and
the complete connection path: cable, adapter, dock, or KVM. Describe what you
expected and what actually happened. For slider problems, a few concrete values
are more useful than "it looks wrong."

Try the app on its own, with other DDC utilities closed. If you attach a report
from the gear menu, review it first. Remove display serials, identifying EDID
data, and registry paths you don't want published. Reports are optional; don't
post passwords, tokens, or unrelated system logs.

## Change the code

1. Fork the repo and make a branch for your change.
2. Keep the change focused. Explain the hardware behavior or user problem it fixes.
3. Run `./scripts/test.sh` and `./scripts/build.sh` on an Apple Silicon Mac.
4. For UI changes, run `./scripts/preview.sh` and check both appearances.
5. Open a pull request with the behavior before and after, plus how you checked it.

The normal test suite does not operate your monitor. Hardware checks are opt-in;
see the [development guide](https://aiden0rchad.github.io/monitor-bar/development/).
Never add hardware writes to the unattended test suite or CI.

Please discuss new dependencies, background services, forced display modes, or
changes to the DDC transport before building them. There are no third-party app
packages at the moment, and keeping the app small makes it easier to understand
when a particular monitor misbehaves.

## Documentation

The Pages site lives in `docs/` and is built by GitHub from the `main` branch.
Keep instructions consistent with the app and scripts. Hardware-specific advice
should say which monitor was tested; a workaround for one controller should not
become a default for every display.

By submitting a contribution, you agree that it can be distributed under the
project's MIT license.

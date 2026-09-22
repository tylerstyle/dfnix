# Claude Code Guidelines - dfnix

Please read and follow `AGENTS.md` for complete repository architecture and multi-repo conventions.

## Key Rules
1. **Multi-Repo Architecture**:
   - `dfnix` is the NixOS distribution configuration and integration repository.
   - `dfdisk` (`~/git/dfdisk`), `dfmount` (`~/git/dfmount`), and `dfnet` (`~/git/dfnet`) are separate, independent Git repositories.
2. **Tool Modifications**:
   - Changes to forensic tools (`dfdisk`, `dfmount`, `dfnet`) must be made and tested in `~/git/<tool>`, NEVER in `dfnix`.
   - Forensic tools are single-source-of-truth: packaged directly from their standalone repos via Flake inputs and `package.nix`. No scripts are vendored in `dfnix`.
3. **Verification**:
   - In `dfnix`: `make check` (runs `nix flake check --no-build`, shellcheck, and flakeless instantiation).
   - In Rust projects: `cargo check` and `cargo test`.

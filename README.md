# x86_64-linux-musl toolchain

A repo for building a cross-compilation toolchain for the x86_64-linux-musl target.

## Installation

### Using Homebrew (Recommended)

```bash
# Add the tap
brew tap aar10n/x86_64-linux-musl

# Install the toolchain
brew install x86_64-linux-musl
```

Pre-built bottles are available for Apple Silicon Macs. 

> **Note:** Homebrew formulas and bottles are maintained in a separate repository: [homebrew-x86_64-linux-musl](https://github.com/aar10n/homebrew-x86_64-linux-musl)

### Building from Source

If you prefer to build locally:

```bash
# Clone the repository
git clone https://github.com/aar10n/x86_64-linux-musl.git
cd x86_64-linux-musl

# Interactive build (requires dialog)
./build.sh

./build.sh --headless --all
```

## License

MIT License - see repository for details.

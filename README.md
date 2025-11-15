# x86_64-linux-musl toolchain

A cross-compilation toolchain for building x86_64 Linux binaries with musl libc on macOS.

## Installation

### Using Homebrew (Recommended)

```bash
# Add the tap
brew tap aar10n/x86_64-linux-musl

# Install the official musl variant
brew install x86_64-linux-musl

# Or install the osdev-musl variant
brew install x86_64-linux-musl-osdev
```

Pre-built bottles are available for Apple Silicon Macs, providing fast installation without compilation.

> **Note:** Homebrew formulas and bottles are maintained in a separate repository: [homebrew-x86_64-linux-musl](https://github.com/aar10n/homebrew-x86_64-linux-musl)

### Building from Source

If you prefer to build locally:

```bash
# Clone the repository
git clone https://github.com/aar10n/x86_64-linux-musl.git
cd x86_64-linux-musl

# Interactive build (requires dialog)
./build.sh

# Or headless build
./build.sh --headless --all

# Or use make directly
make autoconf binutils gcc musl libtool
```

## Usage

After installation, the toolchain will be available in your PATH:

```bash
# Check version
x86_64-linux-musl-gcc --version

# Compile a static binary
x86_64-linux-musl-gcc -static hello.c -o hello

# Verify it's a Linux binary
file hello
# hello: ELF 64-bit LSB executable, x86-64, statically linked
```

## What's Included

The toolchain includes:

- **binutils 2.38** - Assembler, linker, and related tools
- **GCC 12.1.0** - C and C++ compiler support
- **musl libc** - Lightweight, fast, standard-compliant C library
- **autoconf** - Build configuration tool
- **libtool** - Shared library support

## Variants

### x86_64-linux-musl
Uses the official musl libc from [musl-libc.org](https://musl-libc.org/).

### x86_64-linux-musl-osdev
Uses a custom fork ([osdev-musl](https://github.com/aar10n/osdev-musl)) with modifications for OS development.

## Configuration

You can customize the build by creating a `local.mk` file:

```makefile
# Override installation directory
TOOL_ROOT = /custom/path

# Use a custom musl source
MUSL_GIT_URL = https://github.com/user/musl.git
MUSL_GIT_BRANCH = custom-branch

# Use a specific host compiler
HOST_CC = gcc-14
HOST_CXX = g++-14
```

## Development

### Build Script Options

```bash
# Show help
./build.sh --help

# Interactive mode (default)
./build.sh

# Non-interactive build
./build.sh --headless --all

# Build specific components
./build.sh --headless gcc musl
```

### Using Make

```bash
# Build all components
make all

# Build specific components
make binutils gcc musl

# Clean build artifacts
make clean

# Full clean (includes toolchain)
make distclean
```

## License

MIT License - see repository for details.

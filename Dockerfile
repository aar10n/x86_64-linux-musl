# Multi-stage Dockerfile for x86_64-linux-musl toolchain
# Stage 1: Build the toolchain
# Using Alpine 3.16 which has GCC 11 as default (GCC 12 in 3.18 causes build issues)
FROM alpine:3.16 AS builder

# Install build dependencies
RUN apk add --no-cache \
    bash \
    build-base \
    wget \
    git \
    texinfo \
    bison \
    flex \
    gmp-dev \
    mpfr-dev \
    mpc1-dev \
    linux-headers

WORKDIR /toolchain-build

# Copy build files
COPY config.mk Makefile ./
COPY patches/ ./patches/

# Build the toolchain
RUN make -j$(nproc) all

# Stage 2: Create the final image with just the toolchain
FROM alpine:3.16

# Install runtime dependencies
RUN apk add --no-cache \
    bash \
    make \
    libgcc \
    libstdc++ \
    gmp \
    mpfr4 \
    mpc1 \
    binutils

# Copy the built toolchain from builder stage
COPY --from=builder /toolchain-build/toolchain /opt/x86_64-linux-musl

# Strip binaries to reduce image size significantly (removes debug symbols)
RUN find /opt/x86_64-linux-musl -type f \( -name "*.so*" -o -executable \) \
    -exec sh -c 'file "$1" | grep -q ELF && strip --strip-unneeded "$1" 2>/dev/null || true' _ {} \;

# Create symlinks without the cross-compilation prefix
# This allows using 'gcc' instead of 'x86_64-linux-musl-gcc'
RUN cd /opt/x86_64-linux-musl/bin && \
    for tool in x86_64-linux-musl-*; do \
        if [ -f "$tool" ]; then \
            ln -sf "$tool" "${tool#x86_64-linux-musl-}"; \
        fi \
    done

# Set up environment
ENV PATH="/opt/x86_64-linux-musl/bin:${PATH}"
ENV TOOLCHAIN_ROOT="/opt/x86_64-linux-musl"
ENV CC="gcc"
ENV CXX="g++"
ENV AR="ar"
ENV AS="as"
ENV LD="ld"
ENV RANLIB="ranlib"
ENV STRIP="strip"

# Set working directory
WORKDIR /workspace

# Display toolchain info on container start
CMD ["/bin/bash", "-c", "echo 'x86_64-linux-musl toolchain container' && echo && gcc --version && echo && echo 'Toolchain location: /opt/x86_64-linux-musl' && echo 'Use gcc, g++, as, ld, etc. directly' && /bin/bash"]

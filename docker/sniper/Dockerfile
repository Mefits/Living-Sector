# Steam Linux Runtime "sniper" SDK with a Rust toolchain layered on top.
#
# Sniper is Debian 11 based (glibc 2.31). Building inside it produces a
# binary that runs on Steam Deck / SteamOS 3 *and* every desktop Linux
# distro shipped in the last few years — strictly broader compatibility
# than building on a current Ubuntu LTS host.
#
# The sniper image ships gcc / g++ / pkg-config / X11 / ALSA / udev
# headers — everything Bevy + bevy_hanabi need at link time. We add:
#   * curl + ca-certificates to fetch rustup
#   * libwayland-dev (optional Bevy backend, harmless to have)
#   * rustup + stable Rust + the x86_64-unknown-linux-gnu target
#
# Build the image once with `make docker-sniper-image`. The Cargo
# registry + build artefacts persist across runs in two named
# Docker volumes (see the Makefile), so successive builds are fast.

FROM registry.gitlab.steamos.cloud/steamrt/sniper/sdk:latest

ENV DEBIAN_FRONTEND=noninteractive \
    RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates \
        libwayland-dev libxkbcommon-dev \
    && rm -rf /var/lib/apt/lists/*

ARG RUST_VERSION=stable
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain ${RUST_VERSION} --profile minimal \
        --target x86_64-unknown-linux-gnu \
    && rustc --version

WORKDIR /workspace

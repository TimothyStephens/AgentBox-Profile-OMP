# Optional user image layer for Tim's agentbox OMP profile.
#
# agentbox builds this with `ab image build omp` and passes the current
# agentbox-omp tag as BASE, so this file must start with `ARG BASE` followed by
# `FROM ${BASE}` and must not set USER, ENTRYPOINT or CMD — the base image owns
# all three. `ab run --no-profile` skips this layer.
#
# Adds neovim 0.10.4 and points EDITOR/VISUAL at it, which is what OMP's
# external-editor key (`app.editor.external`, Ctrl+G) opens for `/annotate` and
# `/plan-review` notes (reference/omp/slash-command-internals.md §12).

ARG BASE
FROM ${BASE}

# neovim 0.10.4, release tarball, checksum-verified before extraction.
# sha256 verified against the published artifact on 2026-11-03.
# The URL and the sha256 stay literal in this RUN so `./build.sh check` can see
# that the one download in this file is covered by the one checksum.
RUN set -eux; \
    command -v curl >/dev/null 2>&1 || { echo "Containerfile needs curl in BASE" >&2; exit 1; }; \
    url='https://github.com/neovim/neovim/releases/download/v0.10.4/nvim-linux-x86_64.tar.gz'; \
    sha256='95aaa8e89473f5421114f2787c13ae0ec6e11ebbd1a13a1bd6fcf63420f8073f'; \
    tmp="$(mktemp -d)"; \
    curl -fsSL --retry 3 --retry-delay 2 -o "$tmp/nvim.tar.gz" "$url"; \
    printf '%s  %s\n' "$sha256" "$tmp/nvim.tar.gz" | sha256sum -c -; \
    mkdir -p /opt/nvim; \
    tar -xzf "$tmp/nvim.tar.gz" -C /opt/nvim --strip-components=1; \
    rm -rf "$tmp"; \
    /opt/nvim/bin/nvim --version

ENV PATH="/opt/nvim/bin:${PATH}"
ENV EDITOR=nvim
ENV VISUAL=nvim

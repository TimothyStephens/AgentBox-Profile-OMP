# Optional user image layer for this agentbox OMP profile.
#
# agentbox builds this with `ab image build omp` and passes the current
# agentbox-omp tag as BASE, so this file must start with `ARG BASE` followed by
# `FROM ${BASE}` and must not set USER, ENTRYPOINT or CMD — the base image owns
# all three. `ab session start --no-profile` skips this layer.
#
# As in the sibling Claude profile repo, this file holds neovim 0.10.4 with a
# sha256 check, EDITOR and VISUAL, and nothing else. It extracts into /usr/local so nvim lands on the
# default PATH without an ENV PATH line.
#
# EDITOR/VISUAL are what OMP's external-editor key (`app.editor.external`,
# Ctrl+G) opens for `/annotate` and `/plan-review` notes
# (reference/omp/slash-command-internals.md §12).

ARG BASE
FROM ${BASE}

# The URL and the sha256 stay literal in this RUN so `./build.sh check` can see
# that the one download in this file is covered by the one checksum. The digest
# was verified against the published artifact on 2026-11-03.
RUN set -eux; \
    url='https://github.com/neovim/neovim/releases/download/v0.10.4/nvim-linux-x86_64.tar.gz'; \
    sha256='95aaa8e89473f5421114f2787c13ae0ec6e11ebbd1a13a1bd6fcf63420f8073f'; \
    tmp="$(mktemp -d)"; \
    curl -fsSL --retry 3 --retry-delay 2 -o "$tmp/nvim.tar.gz" "$url"; \
    printf '%s  %s\n' "$sha256" "$tmp/nvim.tar.gz" | sha256sum -c -; \
    tar -xzf "$tmp/nvim.tar.gz" -C /usr/local --strip-components=1; \
    rm -rf "$tmp"; \
    nvim --version

ENV EDITOR=nvim
ENV VISUAL=nvim
